import Foundation

/// The look the user picks in Settings › General › Appearance. Every theme has a
/// light and a dark variant that follow the system appearance.
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    /// Translucent, native vibrancy with an indigo–violet accent.
    case glass
    /// Black and white, no accent.
    case mono
    /// Paper background, serif headings, ink accent.
    case editorial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .mono: "Mono"
        case .editorial: "Editorial"
        }
    }

    var detail: String {
        switch self {
        case .glass: "Translucent and native, with a violet accent."
        case .mono: "Black and white. Nothing else."
        case .editorial: "Warm paper and serif type, for writers."
        }
    }
}
