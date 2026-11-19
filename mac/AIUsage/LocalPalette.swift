import SwiftUI

/// The colours the app adds on top of the shared palette: the healthy green, the warning orange and the link blue.
/// The brand colours come from `ProviderStyle`. Gauges, bars, rings and pills take their colour from `UsageTier`.
enum LocalPalette {
    /// The green of "All systems normal" and of the cost figures.
    static let healthy = Color(red: Double(0x34) / 255, green: Double(0xC7) / 255, blue: Double(0x59) / 255)
    static let warning = Color(red: Double(0xFF) / 255, green: Double(0x9F) / 255, blue: Double(0x0A) / 255)
    /// Links such as "Open app".
    static let accent = Color(red: Double(0x0A) / 255, green: Double(0x84) / 255, blue: Double(0xFF) / 255)

    /// The brand colour of a provider, from the shared palette.
    static func brand(for provider: String) -> Color {
        ProviderStyle.color(for: provider)
    }
}

extension AppUsageInsights.StatusLine.Tone {
    var color: Color {
        switch self {
        case .healthy: return LocalPalette.healthy
        case .warning: return LocalPalette.warning
        case .neutral: return .secondary
        }
    }
}
