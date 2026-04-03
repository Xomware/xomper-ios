import Foundation

extension Double {
    /// Formats as fantasy points with 2 decimal places: "1,234.56"
    var formattedPoints: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }

    /// Formats as win percentage: ".750" or "1.000" or ".000"
    var formattedWinPct: String {
        if self >= 1.0 { return "1.000" }
        if self <= 0.0 { return ".000" }
        return String(format: ".%03.0f", self * 1000)
    }
}
