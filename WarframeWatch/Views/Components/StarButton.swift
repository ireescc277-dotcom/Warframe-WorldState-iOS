import SwiftUI

public struct StarButton: View {
    public let key: String
    public let label: String
    public let section: String
    public let expiry: Date?
    
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(key: String, label: String, section: String, expiry: Date?) {
        self.key = key
        self.label = label
        self.section = section
        self.expiry = expiry
    }
    
    public var body: some View {
        let isStarred = vm.isStarred(key: key)
        
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                vm.toggleWatchItem(key: key, label: label, section: section, expiry: expiry)
            }
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isStarred ? WFTheme.gold : WFTheme.textMuted)
                .frame(width: 32, height: 32)
                .background(isStarred ? WFTheme.gold.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isStarred ? WFTheme.gold.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
