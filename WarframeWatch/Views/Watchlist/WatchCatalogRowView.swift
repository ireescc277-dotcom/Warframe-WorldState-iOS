import SwiftUI

public struct WatchCatalogRowView: View {
    public let evaluated: EvaluatedWatchItem
    public let onToggleSubscription: () -> Void
    
    public init(evaluated: EvaluatedWatchItem, onToggleSubscription: @escaping () -> Void) {
        self.evaluated = evaluated
        self.onToggleSubscription = onToggleSubscription
    }
    
    public var body: some View {
        WFCard(isHighlighted: evaluated.state.isActive) {
            VStack(alignment: .leading, spacing: 10) {
                // Tier 1: Category, Title, Status Badge, Subscription Toggle
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: evaluated.item.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(iconColor)
                        .frame(width: 28, height: 28)
                        .background(iconColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(evaluated.item.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(WFTheme.textPrimary)
                                .lineLimit(1)
                            
                            stateBadge
                        }
                        
                        Text(evaluated.item.subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                
                Divider()
                    .background(WFTheme.border.opacity(0.5))
                
                // Tier 2: Real-time Evaluation Details
                stateContent
                
                // Tier 3: Metadata Footer
                HStack(spacing: 8) {
                    TagView(evaluated.item.category.rawValue, style: .neutral)
                    
                    Text(evaluated.item.frequencyHint)
                        .font(.system(size: 11))
                        .foregroundColor(WFTheme.textMuted)
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - State Badge
    @ViewBuilder
    private var stateBadge: some View {
        switch evaluated.state {
        case .active:
            HStack(spacing: 3) {
                Circle()
                    .fill(WFTheme.green)
                    .frame(width: 6, height: 6)
                Text("正在发生")
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
                    .frame(width: 6, height: 6)
                Text("确定周期")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(WFTheme.cyan)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WFTheme.cyan.opacity(0.15))
            .clipShape(Capsule())
            
        case .probabilistic(_, _, let pct, _):
            HStack(spacing: 3) {
                Text("预测 ~\(pct)%")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(WFTheme.gold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WFTheme.gold.opacity(0.12))
            .clipShape(Capsule())
        }
    }
    
    // MARK: - State Content
    @ViewBuilder
    private var stateContent: some View {
        switch evaluated.state {
        case .active(let location, let expiry, _):
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(WFTheme.green)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if let exp = expiry {
                    CountdownView(targetDate: exp)
                } else {
                    Text("进行中")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(WFTheme.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(WFTheme.green.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            
        case .deterministic(let nextDate, _, let note):
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(WFTheme.textSecondary)
                    
                    Text("预计: \(nextDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(WFTheme.textMuted)
                }
                
                Spacer()
                
                CountdownView(targetDate: nextDate)
            }
            
        case .probabilistic(let lastSeen, let avgInterval, let pct, let note):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("上次出现:")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.textMuted)
                        Text(lastSeen)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(WFTheme.textPrimary)
                    }
                    
                    HStack(spacing: 4) {
                        Text("平均间隔:")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.textMuted)
                        Text(avgInterval)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(WFTheme.textPrimary)
                    }
                    
                    Spacer()
                }
                
                // Probability bar
                HStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(WFTheme.bgSecondary)
                                .frame(height: 4)
                            Capsule()
                                .fill(LinearGradient(colors: [WFTheme.gold.opacity(0.6), WFTheme.gold], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(8, geo.size.width * CGFloat(pct) / 100.0), height: 4)
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(pct)%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(WFTheme.gold)
                        .frame(width: 32, alignment: .trailing)
                }
                
                if !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(WFTheme.textMuted)
                }
            }
        }
    }
    
    private var iconColor: Color {
        switch evaluated.state {
        case .active: return WFTheme.green
        case .deterministic: return WFTheme.cyan
        case .probabilistic: return WFTheme.gold
        }
    }
}
