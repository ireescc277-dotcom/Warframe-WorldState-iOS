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
        let nodeName = dict.nodeName(trader.Node)
        
        WFCard {
            // Line 1: Badge + Countdown + Star
            HStack(alignment: .center) {
                TagView(isActive ? "虚空商人 (已到达)" : "虚空商人 (行程中)", style: isActive ? .gold : .purple, icon: "person.crop.rectangle.stack")
                
                Spacer()
                
                CountdownView(targetDate: targetDate, prefix: prefix)
                
                StarButton(
                    key: key,
                    label: "虚空商人 · \(trader.Character)",
                    section: "虚空商人",
                    expiry: targetDate
                )
            }
            
            // Line 2: Character Name
            Text(trader.Character)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(WFTheme.purple)
                .padding(.vertical, 2)
            
            // Line 3: Location and Manifest
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.cyan)
                        Text(nodeName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(WFTheme.textPrimary)
                    }
                    
                    if let count = trader.Manifest?.count, count > 0 {
                        Text("携带珍宝: \(count) 件商品")
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
                        .background(WFTheme.purple.opacity(0.15))
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
