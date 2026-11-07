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
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    TagView(eraName, style: eraStyle(fissure.Modifier), icon: "circle.circle.fill")
                    
                    if fissure.isSteelPath {
                        TagView("钢铁之路", style: .red, icon: "shield.slash.fill")
                    }
                    
                    Text(nodeName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                CountdownView(targetDate: fissure.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "虚空裂隙 · \(nodeName)",
                    section: "虚空裂隙",
                    expiry: fissure.Expiry?.date
                )
            }
            
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundColor(WFTheme.cyan)
                    Text("任务模式: \(mType)")
                        .font(.system(size: 12))
                        .foregroundColor(WFTheme.textSecondary)
                }
                
                Spacer()
                
                if let region = fissure.Region {
                    Text("区域 #\(region)")
                        .font(.system(size: 10, design: .monospaced))
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
