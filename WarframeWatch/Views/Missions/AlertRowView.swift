import SwiftUI

public struct AlertRowView: View {
    public let alert: Alert
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(alert: Alert) {
        self.alert = alert
    }
    
    public var body: some View {
        let location = dict.nodeName(alert.MissionInfo?.location)
        let mType = dict.missionType(alert.MissionInfo?.missionType)
        let faction = dict.faction(alert.MissionInfo?.faction)
        let key = "alerts|\(location) · \(mType)"
        
        WFCard {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    TagView(alert.Tag ?? "警报", style: .gold, icon: "bell.badge.fill")
                    
                    Text("\(mType) · \(location)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WFTheme.textPrimary)
                }
                
                Spacer()
                
                CountdownView(targetDate: alert.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "警报 · \(location)",
                    section: "限时警报",
                    expiry: alert.Expiry?.date
                )
            }
            
            HStack {
                HStack(spacing: 8) {
                    Text(faction)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WFTheme.textSecondary)
                    
                    if let minL = alert.MissionInfo?.minEnemyLevel, let maxL = alert.MissionInfo?.maxEnemyLevel {
                        Text("等级 \(minL) - \(maxL)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(WFTheme.textMuted)
                    }
                }
                
                Spacer()
            }
            
            // Reward badges
            if let reward = alert.MissionInfo?.missionReward {
                HStack(spacing: 6) {
                    if let credits = reward.credits, credits > 0 {
                        TagView("\(credits.formatted()) 现金", style: .cyan, icon: "dollarsign.circle")
                    }
                    
                    if let counted = reward.countedItems {
                        ForEach(counted) { item in
                            TagView("\(dict.itemName(item.ItemType)) ×\(item.ItemCount)", style: .gold, icon: "gift.fill")
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}
