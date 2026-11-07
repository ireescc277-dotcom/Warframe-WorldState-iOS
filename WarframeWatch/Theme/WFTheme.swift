import SwiftUI

public enum WFTheme {
    // MARK: - Color Palette
    public static let bgPrimary = Color(hex: "0A0E17")
    public static let bgSecondary = Color(hex: "0E141C")
    public static let panel = Color(hex: "141D27")
    public static let panelElevated = Color(hex: "192532")
    public static let border = Color(hex: "243544")
    public static let borderLight = Color(hex: "2E4152")
    
    // Accents
    public static let gold = Color(hex: "E9C579")
    public static let cyan = Color(hex: "5FD0E0")
    public static let green = Color(hex: "79C99A")
    public static let red = Color(hex: "EC7B72")
    public static let purple = Color(hex: "B39CE8")
    
    // Text
    public static let textPrimary = Color(hex: "E8EEF4")
    public static let textSecondary = Color(hex: "8FA3B5")
    public static let textMuted = Color(hex: "63788B")
    
    // MARK: - Gradients
    public static let cardGradient = LinearGradient(
        colors: [panelElevated, panel],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let goldGradient = LinearGradient(
        colors: [gold, Color(hex: "E88F5A")],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    public static let cyanGreenGradient = LinearGradient(
        colors: [cyan, green],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    public static let redGradient = LinearGradient(
        colors: [red, Color(hex: "C85A52")],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // MARK: - Dimensions
    public static let cornerRadius: CGFloat = 12
    public static let badgeRadius: CGFloat = 6
}

// MARK: - Color Hex Initializer
public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
