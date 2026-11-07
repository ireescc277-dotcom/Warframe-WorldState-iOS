import SwiftUI

public struct InvasionRowView: View {
    public let invasion: Invasion
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(invasion: Invasion) {
        self.invasion = invasion
    }
    
    public var body: some View {
        let nodeName = dict.nodeName(invasion.Node)
        let attacker = dict.faction(invasion.Faction)
        let defender = dict.faction(invasion.DefenderFaction)
        let key = "invasions|\(invasion.Node)"
        
        WFCard {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    TagView(invasion.Completed ? "已结束" : "入侵争夺", style: invasion.Completed ? .neutral : .red, icon: "swords")
                    
                    Text(nodeName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WFTheme.textPrimary)
                }
                
                Spacer()
                
                StarButton(
                    key: key,
                    label: "入侵 · \(nodeName)",
                    section: "入侵事件",
                    expiry: nil
                )
            }
            
            // Tug-of-war progress
            DuelProgressBarView(
                count: invasion.Count,
                goal: invasion.targetGoal,
                attackerFaction: attacker,
                defenderFaction: defender
            )
            .padding(.vertical, 4)
            
            // Rewards for both factions
            HStack(alignment: .top) {
                // Attacker reward
                VStack(alignment: .leading, spacing: 3) {
                    Text("攻方支持奖励")
                        .font(.system(size: 10))
                        .foregroundColor(WFTheme.cyan)
                    
                    rewardItems(invasion.AttackerReward)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider()
                    .background(WFTheme.border)
                    .frame(height: 36)
                
                // Defender reward
                VStack(alignment: .trailing, spacing: 3) {
                    Text("守方支持奖励")
                        .font(.system(size: 10))
                        .foregroundColor(WFTheme.gold)
                    
                    rewardItems(invasion.DefenderReward)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(8)
            .background(WFTheme.panelElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
    
    @ViewBuilder
    private func rewardItems(_ reward: MissionReward?) -> some View {
        if let counted = reward?.countedItems, !counted.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(counted) { item in
                    Text("\(dict.itemName(item.ItemType)) ×\(item.ItemCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                }
            }
        } else if let items = reward?.items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(items, id: \.self) { item in
                    Text(dict.itemName(item))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                }
            }
        } else {
            Text("无奖励 / 阵营战败")
                .font(.system(size: 11))
                .foregroundColor(WFTheme.textMuted)
        }
    }
}
