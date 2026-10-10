enum PanelMetricMode: String, CaseIterable, Identifiable {
    case combined
    case press
    case held

    var id: Self { self }

    var label: String {
        switch self {
        case .combined:
            return "Both"
        case .press:
            return "Press"
        case .held:
            return "Held"
        }
    }
}
