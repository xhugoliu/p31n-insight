import P31nInsightCore
import SwiftUI

// Explicit alias selects the property-wrapper API when the SDK also exports a State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct MenuView: View {
    @EnvironmentObject private var appState: AppState
    @ViewState private var metricMode: PanelMetricMode = .combined
    @ViewState private var topKeysCardHeight: CGFloat = 0
    @ViewState private var handLoadCardHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !appState.status.isConnected && appState.isLogging {
                Button("Reconnect") { appState.reconnect() }.buttonStyle(.bordered)
            }
            summaryCards
            trend
            insights
            KeyboardLayoutView(metricMode: metricMode)
            actions
            if appState.health.hasLoss {
                Text("Collection gaps: \(appState.health.missingPackets) · Firmware dropped: \(appState.health.firmwareDropped)")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let detail = footerMessage {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(appState.statusShowsIssue ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                    Text("P31n Insight")
                        .font(.headline)
                }
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                if let detail = appState.statusDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(appState.statusShowsIssue ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                statusBadge
                metricModePicker
            }
        }
        .padding(14)
        .background(sectionBackground)
    }

    private var metricModePicker: some View {
        Picker("Metric", selection: $metricMode) {
            ForEach(PanelMetricMode.allCases) { mode in
                Text(mode.label)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .tint(Color.blue.opacity(0.3))
        .frame(width: 230)
        .labelsHidden()
    }

    private var summaryCards: some View {
        HStack(spacing: 8) {
            switch metricMode {
            case .combined:
                MetricCard(title: "Today", value: "\(appState.todayPresses)", detail: "press")
                MetricCard(title: "Held", value: formatDuration(appState.todayHeldMs), detail: "today")
                MetricCard(title: "7D Press", value: "\(appState.last7DaysPresses)", detail: "press")
                MetricCard(title: "7D Held", value: formatDuration(appState.last7DaysHeldMs), detail: "range")
            case .press:
                MetricCard(title: "Today", value: "\(appState.todayPresses)", detail: "press")
                MetricCard(title: "7D Press", value: "\(appState.last7DaysPresses)", detail: "range")
            case .held:
                MetricCard(title: "Held", value: formatDuration(appState.todayHeldMs), detail: "today")
                MetricCard(title: "7D Held", value: formatDuration(appState.last7DaysHeldMs), detail: "range")
            }
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("7-Day Trend")
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(appState.dailySummaries, id: \.dayStart) { summary in
                    DailyTrendBar(
                        label: dayLabel(for: summary.dayStart),
                        valueText: trendValueText(for: summary),
                        value: trendValue(for: summary),
                        maxValue: maxDailyValue,
                        detailText: trendDetailText(for: summary)
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottomLeading)
        }
        .padding(14)
        .background(sectionBackground)
    }

    private var insights: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                topKeysCard
                handLoadCard
            }
            VStack(alignment: .leading, spacing: 10) {
                topKeysCard
                handLoadCard
            }
        }
    }

    private var topKeysCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Top Keys")
            if topKeys.isEmpty {
                Text("No activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(topKeys.enumerated()), id: \.offset) { index, summary in
                    HStack(spacing: 8) {
                        Text("#\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(P31nGeometry.key(row: summary.row, col: summary.col)?.label ?? "Key")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(topKeyValueText(for: summary))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            HeightReader { height in
                topKeysCardHeight = height
            }
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: equalizedInsightCardHeight, alignment: .topLeading)
        .background(sectionBackground)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            actionButton("Pause Logging", alternate: "Resume Logging", isAlternate: !appState.isLogging) {
                appState.toggleLogging()
            }
            Spacer(minLength: 12)
            actionButton("Export Today CSV") {
                appState.exportToday()
            }
            Spacer(minLength: 12)
            actionButton("Export 7 Days") {
                appState.exportSummary()
            }
            Spacer(minLength: 12)
            actionButton("Reveal Database") {
                appState.revealDatabase()
            }
            Spacer(minLength: 12)
            actionButton("Quit") {
                appState.quit()
            }
        }
    }

    private var statusText: String {
        switch appState.status {
        case .connected(let name):
            return name
        case .waiting(let reason):
            switch reason {
            case .initial:
                return "Waiting for keyboard"
            case .disconnected:
                return "Keyboard disconnected"
            }
        case .stopped:
            return "Paused"
        case .issue(let issue):
            return issue.title
        }
    }

    private var statusBadge: some View {
        Text(appState.isLogging ? "Live" : "Paused")
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        if appState.statusShowsIssue {
            return .orange
        }
        return appState.status.isConnected && appState.isLogging ? .green : .yellow
    }

    private var footerMessage: String? {
        guard appState.statusShowsIssue else {
            return nil
        }
        return appState.statusDetail
    }

    private var topKeys: [KeySummary] {
        switch metricMode {
        case .combined, .press:
            return appState.keySummaries
                .filter { $0.pressCount > 0 }
                .sorted {
                    if $0.pressCount == $1.pressCount {
                        return $0.heldMs > $1.heldMs
                    }
                    return $0.pressCount > $1.pressCount
                }
                .prefix(3)
                .map { $0 }
        case .held:
            return appState.keySummaries
                .filter { $0.heldMs > 0 }
                .sorted {
                    if $0.heldMs == $1.heldMs {
                        return $0.pressCount > $1.pressCount
                    }
                    return $0.heldMs > $1.heldMs
                }
                .prefix(3)
                .map { $0 }
        }
    }

    private var leftPresses: Int {
        presses(in: .left)
    }

    private var rightPresses: Int {
        presses(in: .right)
    }

    private var leftHeldMs: Int64 {
        heldMs(in: .left)
    }

    private var rightHeldMs: Int64 {
        heldMs(in: .right)
    }

    private var totalPresses: Int {
        max(leftPresses + rightPresses, 1)
    }

    private var totalHeldMs: Int64 {
        max(leftHeldMs + rightHeldMs, 1)
    }

    private var maxDailyValue: Double {
        switch metricMode {
        case .combined, .press:
            return Double(max(appState.dailySummaries.map(\.pressCount).max() ?? 0, 1))
        case .held:
            return Double(max(appState.dailySummaries.map(\.heldMs).max() ?? 0, 1))
        }
    }

    private var equalizedInsightCardHeight: CGFloat? {
        let height = max(topKeysCardHeight, handLoadCardHeight)
        return height > 0 ? height : nil
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func presses(in hand: HandGroup) -> Int {
        appState.keySummaries
            .filter { P31nGeometry.key(row: $0.row, col: $0.col)?.hand == hand }
            .reduce(0) { $0 + $1.pressCount }
    }

    private func heldMs(in hand: HandGroup) -> Int64 {
        appState.keySummaries
            .filter { P31nGeometry.key(row: $0.row, col: $0.col)?.hand == hand }
            .reduce(0) { $0 + $1.heldMs }
    }

    private func loadFraction(_ value: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }

    private func loadFraction(_ value: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return Double(value) / Double(total)
    }

    private func trendValue(for summary: DailySummary) -> Double {
        switch metricMode {
        case .combined, .press:
            return Double(summary.pressCount)
        case .held:
            return Double(summary.heldMs)
        }
    }

    private func trendValueText(for summary: DailySummary) -> String {
        switch metricMode {
        case .combined, .press:
            return "\(summary.pressCount)"
        case .held:
            return trendDuration(summary.heldMs)
        }
    }

    private func trendDetailText(for summary: DailySummary) -> String? {
        switch metricMode {
        case .combined:
            return trendDuration(summary.heldMs)
        case .press, .held:
            return nil
        }
    }

    private func topKeyValueText(for summary: KeySummary) -> String {
        switch metricMode {
        case .combined, .press:
            return "\(summary.pressCount)"
        case .held:
            return shortDuration(summary.heldMs)
        }
    }

    private var handLoadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Hand Load")
            UnifiedLoadBar(
                leftLabel: "Left",
                leftValueText: loadValueText(presses: leftPresses, heldMs: leftHeldMs),
                leftDetailText: loadDetailText(heldMs: leftHeldMs),
                leftFraction: loadFraction,
                rightLabel: "Right",
                rightValueText: loadValueText(presses: rightPresses, heldMs: rightHeldMs),
                rightDetailText: loadDetailText(heldMs: rightHeldMs)
            )
            Text("Center 1.5u · \(presses(in: .center)) presses · \(shortDuration(heldMs(in: .center)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            HeightReader { height in
                handLoadCardHeight = height
            }
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: equalizedInsightCardHeight, alignment: .topLeading)
        .background(sectionBackground)
    }

    private var loadFraction: Double {
        switch metricMode {
        case .combined, .press:
            return loadFraction(leftPresses, total: totalPresses)
        case .held:
            return loadFraction(leftHeldMs, total: totalHeldMs)
        }
    }

    private func loadValueText(presses: Int, heldMs: Int64) -> String {
        switch metricMode {
        case .combined, .press:
            return "\(presses) presses"
        case .held:
            return shortDuration(heldMs)
        }
    }

    private func loadDetailText(heldMs: Int64) -> String? {
        switch metricMode {
        case .combined:
            return shortDuration(heldMs)
        case .press, .held:
            return nil
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
    }

    private func actionButton(_ title: String, alternate: String? = nil, isAlternate: Bool = false, action: @escaping () -> Void) -> some View {
        Button(isAlternate ? (alternate ?? title) : title, action: action)
            .controlSize(.small)
            .lineLimit(1)
    }

    private func formatDuration(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        return String(format: "%.1fmin", seconds / 60)
    }

    private func shortDuration(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1000
        if seconds < 10 {
            return String(format: "%.1fs", seconds)
        }
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        return String(format: "%.1fm", seconds / 60)
    }

    private func trendDuration(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1000
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        return String(format: "%.1fm", seconds / 60)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct HeightReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    onChange(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, newValue in
                    onChange(newValue)
                }
        }
    }
}

private struct UnifiedLoadBar: View {
    let leftLabel: String
    let leftValueText: String
    let leftDetailText: String?
    let leftFraction: Double
    let rightLabel: String
    let rightValueText: String
    let rightDetailText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let leftWidth = max(14, proxy.size.width * leftFraction)
                let rightWidth = max(14, proxy.size.width - leftWidth)
                let overlap: CGFloat = 12
                let leftIsLonger = leftWidth >= rightWidth
                let leftColor = leftIsLonger ? Color.blue.opacity(0.82) : Color.blue.opacity(0.38)
                let rightColor = leftIsLonger ? Color.blue.opacity(0.38) : Color.blue.opacity(0.82)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(leftColor)
                        .frame(width: min(proxy.size.width, leftWidth + overlap))
                    Capsule()
                        .fill(rightColor)
                        .frame(width: min(proxy.size.width, rightWidth + overlap))
                        .offset(x: max(0, leftWidth - overlap))
                }
            }
            .frame(height: 10)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(leftLabel)
                        .font(.caption.weight(.semibold))
                    Text(leftValueText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let leftDetailText {
                        Text(leftDetailText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(rightLabel)
                        .font(.caption.weight(.semibold))
                    Text(rightValueText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let rightDetailText {
                        Text(rightDetailText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct DailyTrendBar: View {
    let label: String
    let valueText: String
    let value: Double
    let maxValue: Double
    let detailText: String?

    var body: some View {
        VStack(spacing: 6) {
            Text(valueText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
            RoundedRectangle(cornerRadius: 5)
                .fill(barColor)
                .frame(maxWidth: .infinity)
                .frame(height: barHeight)
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let detailText {
                    Spacer(minLength: 2)
                    Text(detailText)
                        .font(.system(size: 8, weight: .regular, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private var barHeight: CGFloat {
        let ratio = maxValue > 0 ? value / maxValue : 0
        return max(12, 12 + ratio * 42)
    }

    private var barColor: Color {
        value == 0 ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.22 + min(value / maxValue, 1) * 0.5)
    }
}
