import SwiftUI

public struct ArchonCardView: View {
    public let archon: LiteSortie
    
    private let dict = DictionaryService.shared
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init(archon: LiteSortie) {
        self.archon = archon
    }
    
    public var body: some View {
        let bossName = dict.bossName(archon.Boss)
        let key = "archon|\(archon.Boss)"
        
        WFCard {
            // Line 1: Badge + Countdown + Star
            HStack(alignment: .center) {
                TagView("执政官猎杀", style: .red, icon: "flame.fill")
                
                Spacer()
                
                CountdownView(targetDate: archon.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "执政官猎杀 · \(bossName)",
                    section: "执政官",
                    expiry: archon.Expiry?.date
                )
            }
            
            // Line 2: Boss Name (Prominent)
            Text(bossName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(WFTheme.red)
                .padding(.vertical, 2)
            
            // 3-Stage Mission List
            if let missions = archon.Missions {
                VStack(spacing: 6) {
                    ForEach(Array(missions.enumerated()), id: \.offset) { index, mission in
                        let mType = dict.missionType(mission.missionType)
                        let node = dict.nodeName(mission.node)
                        
                        HStack {
                            Text("阶段 \(index + 1) · \(mType) · \(node)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(WFTheme.textPrimary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            TagView(mType, style: .cyan)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(WFTheme.panelElevated.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}
