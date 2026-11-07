import SwiftUI

public struct GoalRowView: View {
    public let goal: Goal
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(goal: Goal) {
        self.goal = goal
    }
    
    public var body: some View {
        let title = dict.localizedDesc(goal.Desc)
        let tooltip = dict.localizedDesc(goal.ToolTip)
        let nodeName = goal.Node != nil ? dict.nodeName(goal.Node) : ""
        let key = "goal|\(goal.id)"
        
        WFCard {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    TagView("全服目标", style: .gold, icon: "target")
                    
                    Text(title.isEmpty ? (goal.Tag ?? "社区活动") : title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WFTheme.textPrimary)
                }
                
                Spacer()
                
                CountdownView(targetDate: goal.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "目标 · \(title)",
                    section: "社区目标",
                    expiry: goal.Expiry?.date
                )
            }
            
            if !nodeName.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10))
                        .foregroundColor(WFTheme.cyan)
                    Text("目标节点: \(nodeName)")
                        .font(.system(size: 11))
                        .foregroundColor(WFTheme.textSecondary)
                }
            }
            
            if !tooltip.isEmpty {
                Text(tooltip)
                    .font(.system(size: 12))
                    .foregroundColor(WFTheme.textMuted)
                    .lineLimit(2)
            }
            
            // Progress Bar
            ProgressBarView(
                progress: goal.percentage,
                label: "全服推进进度",
                tintGradient: WFTheme.goldGradient,
                height: 6
            )
            .padding(.top, 2)
            
            // Rewards if present
            if let reward = goal.Reward {
                HStack(spacing: 6) {
                    if let counted = reward.countedItems {
                        ForEach(counted) { item in
                            TagView("\(dict.itemName(item.ItemType)) ×\(item.ItemCount)", style: .green, icon: "gift.fill")
                        }
                    }
                    if let items = reward.items {
                        ForEach(items, id: \.self) { item in
                            TagView(dict.itemName(item), style: .green, icon: "gift.fill")
                        }
                    }
                }
            }
        }
    }
}
