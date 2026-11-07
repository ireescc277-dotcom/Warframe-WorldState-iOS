import SwiftUI

public struct DailyDealCardView: View {
    public let deal: DailyDeal
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(deal: DailyDeal) {
        self.deal = deal
    }
    
    public var body: some View {
        let itemName = dict.itemName(deal.StoreItem)
        let key = "deal|\(deal.StoreItem)"
        
        WFCard {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    TagView("-\(deal.Discount)%", style: .green, icon: "tag.fill")
                    
                    Text(itemName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                CountdownView(targetDate: deal.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "每日特惠 · \(itemName)",
                    section: "每日特惠",
                    expiry: deal.Expiry?.date
                )
            }
            
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("\(deal.SalePrice) 白金")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(WFTheme.green)
                        
                        Text("\(deal.OriginalPrice)")
                            .font(.system(size: 12, design: .monospaced))
                            .strikethrough()
                            .foregroundColor(WFTheme.textMuted)
                    }
                    
                    Text("限量: \(deal.AmountSold) / \(deal.AmountTotal) 件已售")
                        .font(.system(size: 11))
                        .foregroundColor(WFTheme.textSecondary)
                }
                
                Spacer()
            }
            
            ProgressBarView(
                progress: deal.soldPercentage,
                label: "抢购进度",
                tintGradient: WFTheme.cyanGreenGradient,
                height: 5
            )
        }
    }
}
