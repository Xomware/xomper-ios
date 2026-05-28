import SwiftUI

/// Coarse severity bucket for a CloudWatch log event. The backend
/// derives this heuristically from message text (substring scan for
/// `' ERROR '` / `'[ERROR]'` / `'ERROR:'` etc.) — Python lambdas emit
/// to stdout without a structured `level` field, so this is
/// best-effort annotation, not authoritative classification.
///
/// `displayName` drives both the filter picker and the row chip.
/// `color` is sourced from `XomperColors` to keep the chip palette
/// consistent with the rest of the Midnight Emerald theme.
enum LogLevel: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case info
    case warn
    case error

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .info:  return "Info"
        case .warn:  return "Warn"
        case .error: return "Error"
        }
    }

    /// Chip color for the row leading badge. Info renders in the
    /// theme's emerald accent (steel blue), warn in champion gold,
    /// and error in the loud accent red so it pops in a long tail.
    var color: Color {
        switch self {
        case .info:  return XomperColors.steelBlue
        case .warn:  return XomperColors.championGold
        case .error: return XomperColors.accentRed
        }
    }
}
