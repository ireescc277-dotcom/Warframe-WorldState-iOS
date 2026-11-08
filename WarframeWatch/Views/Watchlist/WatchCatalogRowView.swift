import SwiftUI

public struct WatchCatalogRowView: View {
    public let evaluated: EvaluatedWatchEntry
    public let onToggleSubscription: () -> Void
    
    public init(evaluated: EvaluatedWatchEntry, onToggleSubscription: @escaping () -> Void) {
        self.evaluated = evaluated
        self.onToggleSubscription = onToggleSubscription
    }
    
    public var body: some View {
        WFCard(isHighlighted: evaluated.status.isActive) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: evaluated.entry.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 26, height: 26)
                        .background(iconColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(evaluated.entry.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(WFTheme.textPrimary)
                                .lineLimit(1)
                            
                            statusBadge
                        }
                        
                        Text(evaluated.entry.subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                            onToggleSubscription()
                            HapticService.impact(.medium)
                        }
                    } label: {
                        Image(systemName: evaluated.isSubscribed ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundColor(evaluated.isSubscribed ? WFTheme.gold : WFTheme.textMuted)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                
                // Real-time Status Details (if active or deterministic)
                switch evaluated.status {
                case .active(let summary, let location, let expiry, _):
                    Divider()
                        .background(WFTheme.border.opacity(0.5))
                    
                    HStack {
                        HStack(spacing: 4) {
                            Text(summary)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(WFTheme.green)
                            Text("·")
                                .foregroundColor(WFTheme.textMuted)
                            Text(location)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(WFTheme.textPrimary)
                        }
                        
                        Spacer()
                        
                        if let exp = expiry {
                            CountdownView(targetDate: exp)
                        } else {
                            Text("进行中")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(WFTheme.green)
                        }
                    }
                    
                case .deterministic(let nextDate, _, let note):
                    Divider()
                        .background(WFTheme.border.opacity(0.5))
                    
                    HStack {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.textSecondary)
                        
                        Spacer()
                        
                        CountdownView(targetDate: nextDate)
                    }
                    
                case .idle:
                    EmptyView()
                }
            }
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        switch evaluated.status {
        case .active:
            HStack(spacing: 3) {
                Circle()
                    .fill(WFTheme.green)
                    .frame(width: 5, height: 5)
                Text("进行中")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(WFTheme.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WFTheme.green.opacity(0.15))
            .clipShape(Capsule())
            
        case .deterministic:
            HStack(spacing: 3) {
                Circle()
                    .fill(WFTheme.cyan)
                    .frame(width: 5, height: 5)
                Text("确定周期")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(WFTheme.cyan)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WFTheme.cyan.opacity(0.15))
            .clipShape(Capsule())
            
        case .idle:
            EmptyView()
        }
    }
    
    private var iconColor: Color {
        switch evaluated.status {
        case .active: return WFTheme.green
        case .deterministic: return WFTheme.cyan
        case .idle: return WFTheme.textSecondary
        }
    }
}
