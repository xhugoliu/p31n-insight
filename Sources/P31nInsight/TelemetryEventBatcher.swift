import Foundation
import P31nInsightCore

final class TelemetryEventBatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "p31n-insight.event-batcher", qos: .userInitiated)
    private let flushInterval: TimeInterval
    private let onFlush: @Sendable ([TelemetryEvent]) -> Void

    private var pending: [TelemetryEvent] = []
    private var isScheduled = false

    init(flushInterval: TimeInterval = 0.05, onFlush: @escaping @Sendable ([TelemetryEvent]) -> Void) {
        self.flushInterval = flushInterval
        self.onFlush = onFlush
    }

    func enqueue(_ event: TelemetryEvent) {
        queue.async {
            self.pending.append(event)
            guard !self.isScheduled else { return }

            self.isScheduled = true
            self.queue.asyncAfter(deadline: .now() + self.flushInterval) {
                let events = self.pending
                self.pending.removeAll(keepingCapacity: true)
                self.isScheduled = false

                guard !events.isEmpty else { return }
                self.onFlush(events)
            }
        }
    }
}
