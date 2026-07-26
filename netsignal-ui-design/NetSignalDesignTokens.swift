import AppKit

// MARK: - NetSignal Design Tokens
// Auto-generated from TRAE Work Design Library

extension NSColor {

    // MARK: - Background

    static let nsBackgroundDefault = NSColor(hex: "#ffffff")
    static let nsBackgroundSecondary = NSColor(hex: "#f5f5f5")
    static let nsBackgroundTertiary = NSColor(hex: "#e5e5e5")
    static let nsOverlayLight = NSColor(hex: "#1b1b1b").withAlphaComponent(0.08)

    // MARK: - Text

    static let nsTextDefault = NSColor(hex: "#171717")
    static let nsTextSecondary = NSColor(hex: "#404040")
    static let nsTextTertiary = NSColor(hex: "#737373")
    static let nsTextDisabled = NSColor(hex: "#a1a1a1")

    // MARK: - Icon

    static let nsIconDefault = NSColor(hex: "#262626")
    static let nsIconTertiary = NSColor(hex: "#737373")

    // MARK: - Border

    static let nsBorderNeutral = NSColor(hex: "#737373").withAlphaComponent(0.12)

    // MARK: - Status

    static let nsStatusSuccess = NSColor(hex: "#15a877")
    static let nsStatusWarning = NSColor(hex: "#fea900")
    static let nsStatusError = NSColor(hex: "#e8463a")

    // MARK: - Brand

    static let nsBrandPrimary = NSColor(hex: "#4b3fe3")

    // MARK: - Greys

    static let nsGrey100 = NSColor(hex: "#f5f5f5")
    static let nsGrey300 = NSColor(hex: "#d4d4d4")
    static let nsGrey400 = NSColor(hex: "#a1a1a1")
    static let nsGrey700 = NSColor(hex: "#404040")
    static let nsGrey800 = NSColor(hex: "#262626")
    static let nsGrey900 = NSColor(hex: "#171717")

    // MARK: - Helper

    convenience init(hex: String) {
        let hex = hex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

// MARK: - Typography

enum NSDesignFont {

    static let title = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let body = NSFont.systemFont(ofSize: 12, weight: .regular)
    static let caption = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let legend = NSFont.systemFont(ofSize: 10, weight: .regular)
    static let button = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let sectionHeading = NSFont.systemFont(ofSize: 11, weight: .semibold)
}

// MARK: - Spacing

enum NSDesignSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

// MARK: - Status Thresholds (ms)

enum NSLatencyThreshold {
    static let excellent: Int = 200
    static let good: Int = 500
    static let fair: Int = 1500

    static func statusColor(for ms: Int) -> NSColor {
        switch ms {
        case ..<excellent: return .nsStatusSuccess
        case ..<good: return .nsStatusSuccess
        case ..<fair: return .nsStatusWarning
        default: return .nsStatusError
        }
    }

    static func statusBarWidth(for ms: Int, maxWidth: CGFloat = 56) -> CGFloat {
        let normalized = max(0, min(1, 1.0 - CGFloat(ms) / 3000.0))
        return max(4, maxWidth * normalized)
    }
}

// MARK: - Layout

enum NSDesignLayout {
    static let popoverWidth: CGFloat = 340
    static let cornerRadius: CGFloat = 10
    static let rowHeight: CGFloat = 36
    static let headerHeight: CGFloat = 44
    static let horizontalPadding: CGFloat = 14  // px-3.5 ≈ 14px
}
