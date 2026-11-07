import SwiftUI

public struct WFCard<Content: View>: View {
    public let isHighlighted: Bool
    public let content: Content
    
    public init(isHighlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.isHighlighted = isHighlighted
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: WFTheme.cornerRadius)
                .fill(isHighlighted ? WFTheme.cardGradient : LinearGradient(colors: [WFTheme.panel, WFTheme.panel], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: WFTheme.cornerRadius)
                .stroke(isHighlighted ? WFTheme.gold.opacity(0.4) : WFTheme.border, lineWidth: 1)
        )
    }
}

public extension View {
    func wfCardStyle(isHighlighted: Bool = false) -> some View {
        WFCard(isHighlighted: isHighlighted) {
            self
        }
    }
}
