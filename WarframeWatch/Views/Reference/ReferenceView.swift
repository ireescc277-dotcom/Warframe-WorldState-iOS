import SwiftUI

public struct ReferenceView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    @State private var searchNodeQuery: String = ""
    @State private var showRawJson: Bool = false
    
    private let dict = DictionaryService.shared
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Raw JSON Card
                        WFCard(isHighlighted: true) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("原始世界状态 JSON")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(WFTheme.gold)
                                    Text("未经任何加工的完整官方数据报文 (约 160 KB)")
                                        .font(.system(size: 11))
                                        .foregroundColor(WFTheme.textMuted)
                                }
                                
                                Spacer()
                                
                                Button {
                                    showRawJson = true
                                } label: {
                                    Text("检查数据")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(WFTheme.gold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(WFTheme.gold.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        
                        // Sortie Modifiers Handbook
                        sortieModifiersSection
                        
                        // API Metadata Card
                        metadataSection
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("资料库与工具")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRawJson) {
                RawJsonView(worldState: vm.worldState)
            }
        }
    }
    
    // MARK: - Sortie Modifiers
    private var sortieModifiersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("突击异常状态指南 (SORTIE MODIFIERS)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(WFTheme.cyan)
            
            let modifiers: [(String, String, String)] = [
                ("能量减少", "战甲的能量上限降低为四分之一，并且能量恢复速率也会大大降低。", "建议使用 Lavos、Hildryn 或携带大量能量井"),
                ("卓越者大本营", "卓越者单位生成率大幅提升，携带多个高危光环。", "建议携带强力虚灵解甲武器或近战高爆发"),
                ("辐射灾害", "版图中会出现绿色辐射云，进入后将触发辐射状态并开启队友友伤。", "注意走位，切勿向队友丢大招或范围爆炸武器"),
                ("电磁异常", "重力减弱，蓝色磁力气泡会导致能量清空并使界面受扰。", "避开悬浮气泡，或装备顶级电磁抗性赋能"),
                ("副武器限定", "任务中只能使用次要武器，主武器与近战将被自动禁用。", "建议配置赤毒布拉玛 / 葬铭等高火力副手"),
                ("敌人护甲强化", "敌人护甲减伤极高，腐蚀触发效果减半。", "使用完全削甲技能 (如 Ash、Styanax) 或纯火切真实伤害")
            ]
            
            ForEach(modifiers, id: \.0) { item in
                WFCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TagView(item.0, style: .red, icon: "exclamationmark.octagon.fill")
                            Spacer()
                        }
                        
                        Text(item.1)
                            .font(.system(size: 12))
                            .foregroundColor(WFTheme.textPrimary)
                        
                        Text("💡 攻略建议: \(item.2)")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.green)
                    }
                }
            }
        }
    }
    
    // MARK: - Metadata
    private var metadataSection: some View {
        WFCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("客户端与连接信息")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(WFTheme.textPrimary)
                
                if let seed = vm.worldState?.WorldSeed {
                    Text("世界种子 (WorldSeed): \(seed.prefix(32))...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(WFTheme.textMuted)
                }
                
                if let label = vm.worldState?.BuildLabel {
                    Text("构建标签 (BuildLabel): \(label)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(WFTheme.textMuted)
                }
                
                Text("数据源: https://api.warframe.com/cdn/worldState.php")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(WFTheme.textMuted)
            }
        }
    }
}
