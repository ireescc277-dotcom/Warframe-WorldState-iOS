import SwiftUI

public enum TagStyle {
    case cyan
    case gold
    case green
    case red
    case purple
    case neutral
    
    public var foregroundColor: Color {
        switch self {
        case .cyan: return WFTheme.cyan
        case .gold: return WFTheme.gold
        case .green: return WFTheme.green
        case .red: return WFTheme.red
        case .purple: return WFTheme.purple
        case .neutral: return WFTheme.textSecondary
        }
    }
    
    public var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
    
    public var borderColor: Color {
        foregroundColor.opacity(0.3)
    }
}

public struct TagView: View {
    public let title: String
    public var style: TagStyle = .cyan
    public var icon: String? = nil
    
    public init(_ title: String, style: TagStyle = .cyan, icon: String? = nil) {
        self.title = title
        self.style = style
        self.icon = icon
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundColor(style.foregroundColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: WFTheme.badgeRadius))
        .overlay(
            RoundedRectangle(cornerRadius: WFTheme.badgeRadius)
                .stroke(style.borderColor, lineWidth: 1)
        )
    }
}
