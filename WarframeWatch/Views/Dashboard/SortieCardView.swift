import SwiftUI

public struct SortieCardView: View {
    public let sortie: Sortie
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(sortie: Sortie) {
        self.sortie = sortie
    }
    
    public var body: some View {
        let bossName = dict.bossName(sortie.Boss)
        let key = "sortie|\(sortie.Boss)"
        
        WFCard(isHighlighted: true) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        TagView("每日突击", style: .gold, icon: "shield.checkered")
                        Text(bossName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(WFTheme.gold)
                    }
                    
                    if let reward = sortie.Reward {
                        Text("奖励池: \(dict.itemName(reward))")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.textMuted)
                    }
                }
                
                Spacer()
                
                CountdownView(targetDate: sortie.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "每日突击 · \(bossName)",
                    section: "每日突击",
                    expiry: sortie.Expiry?.date
                )
            }
            
            Divider()
                .background(WFTheme.border)
                .padding(.vertical, 2)
            
            // 3-Stage Mission List
            if let variants = sortie.Variants {
                VStack(spacing: 8) {
                    ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                        stageRow(index: index + 1, variant: variant)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func stageRow(index: Int, variant: SortieVariant) -> some View {
        let mType = dict.missionType(variant.missionType)
        let node = dict.nodeName(variant.node)
        let modName = dict.sortieModifierName(variant.modifierType)
        let modDesc = dict.sortieModifierDesc(variant.modifierType)
        
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("第 \(index) 关 · \(node)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                
                Spacer()
                
                TagView(mType, style: .cyan)
            }
            
            HStack(alignment: .top, spacing: 6) {
                TagView(modName, style: .red, icon: "exclamationmark.triangle.fill")
                
                if !modDesc.isEmpty {
                    Text(modDesc)
                        .font(.system(size: 11))
                        .foregroundColor(WFTheme.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(8)
        .background(WFTheme.panelElevated.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
