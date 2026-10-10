import AppKit
import Foundation
import P31nInsightCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private static let configuration = AppConfiguration.p31n
    private static let summaryRangeDays = 7

    @Published var status: CollectorStatus = .waiting(.initial)
    @Published var isLogging = true
    @Published var health = CollectorHealth()
    @Published var todayPresses = 0
    @Published var last7DaysPresses = 0
    @Published var todayHeldMs: Int64 = 0
    @Published var last7DaysHeldMs: Int64 = 0
    @Published var dailySummaries: [DailySummary] = []
    @Published var lastEventText = "No events yet"
    @Published var appError: String?
    @Published var exportedURL: URL?
    @Published var keySummaries = SummarySnapshot.empty(layout: AppState.configuration.layout).keySummaries
    @Published var activeKeys: Set<String> = []

    let databaseURL = AppPaths.databaseURL
    let configuration = AppState.configuration

    private let database: SQLiteDatabase
    private let persistenceQueue = DispatchQueue(label: "p31n-insight.persistence", qos: .utility)
    private var collector: TelemetryCollector?
    private var eventBatcher: TelemetryEventBatcher?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var isRefreshingStats = false
    private var needsStatsRefresh = false
    private var summaryTracker = DayScopedLiveSummaryTracker(
        layout: AppState.configuration.layout,
        dayStart: Calendar.current.startOfDay(for: Date())
    )
    private var bootstrapEvents: [TelemetryEvent] = []
    private var didLoadInitialSnapshot = false

    init(preview: Bool = false) {
        do {
            database = try SQLiteDatabase(url: preview ? FileManager.default.temporaryDirectory.appendingPathComponent("p31n-preview-\(UUID().uuidString).sqlite3") : AppPaths.databaseURL, layout: Self.configuration.layout)
        } catch {
            fatalError("Failed to open database: \(error.localizedDescription)")
        }

        if preview {
            let keys = P31nGeometry.keys.map { key in
                KeySummary(row: key.row, col: key.col, pressCount: key.hand == .center ? 42 : 40 + Int(key.position) * 13,
                           heldMs: key.hand == .center ? 12400 : Int64(1500 + Int(key.position) * 700))
            }
            let snapshot = SummarySnapshot(keySummaries: keys, pressCount: keys.reduce(0) { $0 + $1.pressCount }, heldMs: keys.reduce(0) { $0 + $1.heldMs })
            summaryTracker = DayScopedLiveSummaryTracker(layout: Self.configuration.layout, dayStart: Date(), snapshot: snapshot)
            syncPublishedSummary()
            status = .connected("X.P31n Keyboard")
            dailySummaries = (0..<7).map { day in
                DailySummary(dayStart: Calendar.current.date(byAdding: .day, value: day - 6, to: todayStartDate)!, pressCount: day == 6 ? todayPresses : 1700 + day * 400, heldMs: day == 6 ? todayHeldMs : Int64(120000 + day * 18000))
            }
            last7DaysPresses = dailySummaries.reduce(0) { $0 + $1.pressCount }
            last7DaysHeldMs = dailySummaries.reduce(0) { $0 + $1.heldMs }
            return
        }

        let eventBatcher = TelemetryEventBatcher { [weak self] events in
            Task { @MainActor in
                self?.handle(events)
            }
        }
        self.eventBatcher = eventBatcher

        let database = self.database
        let persistenceQueue = self.persistenceQueue
        collector = TelemetryCollector(
            configuration: Self.configuration,
            onEvent: { [weak self] event in
                persistenceQueue.async {
                    do { try database.insert(event) }
                    catch {
                        let message = error.localizedDescription
                        Task { @MainActor in self?.appError = message }
                    }
                }
                eventBatcher.enqueue(event)
            },
            onStatus: { [weak self] status in
                Task { @MainActor in
                    self?.status = status
                    if !status.isConnected {
                        self?.summaryTracker.reset(dayStart: self?.todayStartDate ?? Date(), snapshot: self?.summaryTracker.snapshot)
                        self?.syncPublishedSummary()
                    }
                }
            },
            onHealth: { [weak self] health in
                Task { @MainActor in self?.health = health }
            }
        )

        refreshStats()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStats() }
        }
    }

    func reconnect() { collector?.reconnect() }

    func toggleLogging() {
        isLogging.toggle()
        if isLogging {
            start()
        } else {
            stop()
        }
    }

    func exportToday() {
        do {
            let url = try database.exportTodayCSV()
            exportedURL = url
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            appError = error.localizedDescription
        }
    }

    func exportSummary() {
        do {
            let url = try database.exportSummaryCSV(since: summaryStartDate)
            exportedURL = url
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            appError = error.localizedDescription
        }
    }

    func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
    }

    func quit() {
        shutdown()
        NSApplication.shared.terminate(nil)
    }

    func shutdown() {
        stop()
        refreshTimer?.invalidate()
        persistenceQueue.sync {}
    }

    private func start() {
        isLogging = true
        collector?.start()
    }

    private func stop() {
        collector?.stop()
        summaryTracker.reset(dayStart: todayStartDate, snapshot: summaryTracker.snapshot)
        syncPublishedSummary()
    }

    private func handle(_ events: [TelemetryEvent]) {
        appError = nil
        guard let lastEvent = events.last else { return }

        if !didLoadInitialSnapshot {
            bootstrapEvents.append(contentsOf: events)
        }
        lastEventText = "r\(lastEvent.row)c\(lastEvent.col) \(lastEvent.pressed ? "down" : "up")"
        var didRollDay = false
        for event in events {
            didRollDay = summaryTracker.apply(event) || didRollDay
        }
        syncPublishedSummary()
        if didRollDay {
            refreshStats()
        }
    }

    private func refreshStats() {
        guard !isRefreshingStats else {
            needsStatsRefresh = true
            return
        }

        isRefreshingStats = true

        let database = self.database
        let todayStartDate = self.todayStartDate
        let summaryStartDate = self.summaryStartDate
        let days = Self.summaryRangeDays

        refreshTask = Task.detached(priority: .utility) { [weak self] in
            let result: Result<DashboardSnapshot, Error>
            do {
                result = .success(try database.dashboardSnapshot(
                    since: summaryStartDate,
                    todayStart: todayStartDate,
                    days: days
                ))
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                self?.finishRefreshStats(result, todayStart: todayStartDate)
            }
        }
    }

    static func keyID(row: Int, col: Int) -> String {
        LiveSummaryTracker.keyID(row: row, col: col)
    }

    private func syncPublishedSummary() {
        let snapshot = summaryTracker.snapshot
        keySummaries = snapshot.keySummaries
        todayPresses = snapshot.pressCount
        todayHeldMs = snapshot.heldMs
        activeKeys = summaryTracker.activeKeys
    }

    private func applyRefreshedStats(
        todayStart: Date,
        todaySnapshot: SummarySnapshot,
        last7DaysSnapshot: SummarySnapshot,
        dailySummaries: [DailySummary]
    ) {
        let refreshedDayStart = Calendar.current.startOfDay(for: todayStart)
        if !didLoadInitialSnapshot {
            var tracker = DayScopedLiveSummaryTracker(
                layout: configuration.layout,
                dayStart: refreshedDayStart,
                snapshot: todaySnapshot
            )
            for event in bootstrapEvents {
                tracker.apply(event)
            }
            bootstrapEvents.removeAll()
            summaryTracker = tracker
            didLoadInitialSnapshot = true
            syncPublishedSummary()
        } else if refreshedDayStart > summaryTracker.dayStart {
            summaryTracker.rebase(dayStart: refreshedDayStart, snapshot: todaySnapshot)
            syncPublishedSummary()
        }

        last7DaysPresses = last7DaysSnapshot.pressCount
        last7DaysHeldMs = last7DaysSnapshot.heldMs
        self.dailySummaries = dailySummaries
        appError = nil
    }

    private func finishRefreshStats(_ result: Result<DashboardSnapshot, Error>, todayStart: Date) {
        refreshTask = nil
        isRefreshingStats = false

        switch result {
        case .success(let dashboard):
            let initialRefresh = !didLoadInitialSnapshot
            applyRefreshedStats(
                todayStart: todayStart,
                todaySnapshot: dashboard.today,
                last7DaysSnapshot: dashboard.range,
                dailySummaries: dashboard.dailySummaries
            )
            if initialRefresh && isLogging { start() }
        case .failure(let error):
            appError = error.localizedDescription
        }

        if needsStatsRefresh {
            needsStatsRefresh = false
            refreshStats()
        }
    }

    var statusDetail: String? {
        appError ?? status.detail
    }

    var statusShowsIssue: Bool {
        appError != nil || status.showsIssue
    }

    private var todayStartDate: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var summaryStartDate: Date {
        Calendar.current.date(byAdding: .day, value: -(Self.summaryRangeDays - 1), to: todayStartDate) ?? todayStartDate
    }
}
