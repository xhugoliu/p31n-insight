import P31nInsightCore
import SwiftUI

struct KeyboardLayoutView: View {
    @EnvironmentObject private var appState: AppState
    let metricMode: PanelMetricMode
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Physical Keys").font(.caption.weight(.semibold))
                Spacer()
                Text("31 keys · Center 1.5u").font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let unit = proxy.size.width / P31nGeometry.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [.black.opacity(0.82), .gray.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .overlay(VStack(spacing: 4) {
                            Text("X.Tips").font(.system(size: 11, weight: .bold))
                            Text("P31n").font(.system(size: 9))
                        }.foregroundStyle(.white.opacity(0.8)))
                        .frame(width: unit * 1.5 - 5, height: 105)
                        .offset(x: unit * 5)
                    ForEach(P31nGeometry.keys) { key in
                        let summary = appState.keySummaries.first { $0.row == key.row && $0.col == key.col }
                            ?? KeySummary(row: key.row, col: key.col, pressCount: 0, heldMs: 0)
                        PhysicalKeyTile(key: key, summary: summary, metricMode: metricMode,
                                        maxPresses: appState.keySummaries.map(\.pressCount).max() ?? 1,
                                        maxHeld: appState.keySummaries.map(\.heldMs).max() ?? 1,
                                        active: appState.activeKeys.contains(AppState.keyID(row: key.row, col: key.col)))
                            .frame(width: unit * key.width - 5, height: 50)
                            .offset(x: key.x * unit, y: key.y * 55)
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.08)))
    }
}

private struct PhysicalKeyTile: View {
    let key: PhysicalKey
    let summary: KeySummary
    let metricMode: PanelMetricMode
    let maxPresses: Int
    let maxHeld: Int64
    let active: Bool
    private var intensity: Double {
        let press = Double(summary.pressCount) / Double(max(maxPresses, 1))
        let held = Double(summary.heldMs) / Double(max(maxHeld, 1))
        switch metricMode {
        case .combined: return press * 0.7 + held * 0.3
        case .press: return press
        case .held: return held
        }
    }
    var body: some View {
        VStack(spacing: 2) {
            Text(key.label).font(.system(size: 9, weight: .medium))
            if metricMode != .held {
                Text("\(summary.pressCount)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            if metricMode != .press {
                Text(duration).font(.system(size: 8)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(key.hand == .center ? Color.white : Color.primary)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(key.hand == .center ? Color.black.opacity(0.8) : Color.accentColor.opacity(0.06 + intensity * 0.35))
            if key.hand == .center {
                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(intensity * 0.4))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(active ? Color.green : Color.secondary.opacity(0.2), lineWidth: active ? 2 : 1))
        .help("Position \(key.position) · \(key.hand.rawValue)")
    }
    private var duration: String {
        let seconds = Double(summary.heldMs) / 1000
        return seconds < 60 ? String(format: "%.1fs", seconds) : String(format: "%.1fm", seconds / 60)
    }
}
