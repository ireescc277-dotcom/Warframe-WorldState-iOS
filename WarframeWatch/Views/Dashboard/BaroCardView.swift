import SwiftUI

public struct BaroCardView: View {
    public let trader: VoidTrader
    @State private var showSheet: Bool = false
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(trader: VoidTrader) {
        self.trader = trader
    }
    
    public var body: some View {
        let isActive = trader.isActive
        let key = "baro|\(trader.Character)"
        let targetDate = isActive ? trader.Expiry?.date : trader.Activation?.date
        let prefix = isActive ? "离开剩余" : "到达还有"
        
        WFCard {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    TagView("虚空商人", style: .purple, icon: "person.crop.rectangle.stack")
                    
                    Text(trader.Character)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(WFTheme.purple)
                }
                
                Spacer()
                
                CountdownView(targetDate: targetDate, prefix: prefix)
                
                StarButton(
                    key: key,
                    label: "虚空商人 · \(trader.Character)",
                    section: "虚空商人",
                    expiry: targetDate
                )
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.cyan)
                        Text(dict.nodeName(trader.Node))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(WFTheme.textPrimary)
                    }
                    
                    if let count = trader.Manifest?.count, count > 0 {
                        Text("带来商品 \(count) 件")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.textMuted)
                    }
                }
                
                Spacer()
                
                if trader.Manifest != nil && !(trader.Manifest?.isEmpty ?? true) {
                    Button {
                        showSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("浏览商品")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(WFTheme.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(WFTheme.purple.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .sheet(isPresented: $showSheet) {
            BaroDetailSheet(trader: trader)
        }
    }
}
