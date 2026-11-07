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
            // Line 1: Discount Badge + Countdown + Star
            HStack(alignment: .center) {
                TagView("达沃特惠 -\(deal.Discount)%", style: .green, icon: "tag.fill")
                
                Spacer()
                
                CountdownView(targetDate: deal.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "特惠 · \(itemName)",
                    section: "每日特惠",
                    expiry: deal.Expiry?.date
                )
            }
            
            // Line 2: Full Item Name (Prominent, No Truncation)
            Text(itemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(WFTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
            
            // Line 3: Pricing & Remaining Stock
            HStack(alignment: .bottom) {
                HStack(spacing: 8) {
                    Text("\(deal.SalePrice) 白金")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(WFTheme.green)
                    
                    Text("\(deal.OriginalPrice) 白金")
                        .font(.system(size: 13, design: .monospaced))
                        .strikethrough()
                        .foregroundColor(WFTheme.textMuted)
                }
                
                Spacer()
                
                let remaining = max(0, deal.AmountTotal - deal.AmountSold)
                Text("仅剩 \(remaining) 件 / 总量 \(deal.AmountTotal)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(remaining < 10 ? WFTheme.red : WFTheme.textSecondary)
            }
            
            // Line 4: Progress Bar
            ProgressBarView(
                progress: deal.soldPercentage,
                label: "抢购进度",
                tintGradient: WFTheme.cyanGreenGradient,
                height: 5
            )
            .padding(.top, 2)
        }
    }
}
