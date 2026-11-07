import SwiftUI

public struct GlobalBuffCardView: View {
    public let buff: GlobalUpgrade
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(buff: GlobalUpgrade) {
        self.buff = buff
    }
    
    public var body: some View {
        let upgradeName = dict.upgradeName(buff.UpgradeType)
        let key = "buff|\(buff.UpgradeType)"
        
        WFCard(isHighlighted: true) {
            HStack {
                HStack(spacing: 6) {
                    TagView("全局增益", style: .green, icon: "bolt.fill")
                    
                    Text(upgradeName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WFTheme.textPrimary)
                }
                
                Spacer()
                
                CountdownView(targetDate: buff.ExpiryDate?.date)
                
                StarButton(
                    key: key,
                    label: "全局增益 · \(upgradeName)",
                    section: "全局增益",
                    expiry: buff.ExpiryDate?.date
                )
            }
            
            HStack(spacing: 8) {
                Text("\(Int(buff.Value))× 倍率")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(WFTheme.green)
                
                Text("全服生效 · 自动加成")
                    .font(.system(size: 11))
                    .foregroundColor(WFTheme.textSecondary)
                
                Spacer()
            }
            .padding(.top, 2)
        }
    }
}
