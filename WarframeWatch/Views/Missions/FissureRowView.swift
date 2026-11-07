import SwiftUI

public struct FissureRowView: View {
    public let fissure: ActiveMission
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(fissure: ActiveMission) {
        self.fissure = fissure
    }
    
    public var body: some View {
        let nodeName = dict.nodeName(fissure.Node)
        let mType = dict.missionType(fissure.MissionType)
        let eraName = dict.tierName(fissure.Modifier)
        let key = "fissures|\(fissure.id)"
        
        WFCard {
            // Line 1: Badges + Countdown + Star
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    TagView(eraName, style: eraStyle(fissure.Modifier), icon: "circle.circle.fill")
                    
                    if fissure.isSteelPath {
                        TagView("钢铁之路", style: .red, icon: "shield.slash.fill")
                    }
                }
                
                Spacer()
                
                CountdownView(targetDate: fissure.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "虚空裂隙 · \(mType) · \(nodeName)",
                    section: "虚空裂隙",
                    expiry: fissure.Expiry?.date
                )
            }
            
            // Line 2: Mission Type & Node/Planet (Prominent, Full Width, No Truncation)
            Text("\(mType) · \(nodeName)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(WFTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
            
            // Line 3: Meta details
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundColor(WFTheme.cyan)
                    Text("裂隙探索")
                        .font(.system(size: 11))
                        .foregroundColor(WFTheme.textSecondary)
                }
                
                Spacer()
                
                if let region = fissure.Region {
                    Text("区域 #\(region)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(WFTheme.textMuted)
                }
            }
        }
    }
    
    private func eraStyle(_ era: String) -> TagStyle {
        switch era {
        case "VoidT1": return .neutral
        case "VoidT2": return .cyan
        case "VoidT3": return .green
        case "VoidT4": return .gold
        case "VoidT5": return .red
        case "VoidT6": return .purple
        default: return .cyan
        }
    }
}
