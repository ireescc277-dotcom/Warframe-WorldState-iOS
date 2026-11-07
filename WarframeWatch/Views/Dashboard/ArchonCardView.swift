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
            HStack {
                HStack(spacing: 6) {
                    TagView("执政官猎杀", style: .red, icon: "flame.fill")
                    Text(bossName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(WFTheme.red)
                }
                
                Spacer()
                
                CountdownView(targetDate: archon.Expiry?.date)
                
                StarButton(
                    key: key,
                    label: "执政官猎杀 · \(bossName)",
                    section: "执政官",
                    expiry: archon.Expiry?.date
                )
            }
            
            if let missions = archon.Missions {
                VStack(spacing: 6) {
                    ForEach(Array(missions.enumerated()), id: \.offset) { index, mission in
                        HStack {
                            Text("阶段 \(index + 1) · \(dict.nodeName(mission.node))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(WFTheme.textPrimary)
                            
                            Spacer()
                            
                            TagView(dict.missionType(mission.missionType), style: .cyan)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(WFTheme.panelElevated.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
}
