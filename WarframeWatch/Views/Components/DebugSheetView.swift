import SwiftUI

public struct DebugSheetView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var inputUrl: String = ""
    @State private var showSavedAlert: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Diagnostic Banner
                        diagnosticCard
                        
                        // Active Source & Configuration
                        dataSourceConfigCard
                        
                        // Local Debug Tutorial
                        localHostTutorialCard
                    }
                    .padding()
                }
            }
            .navigationTitle("调试与数据源配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(WFTheme.cyan)
                }
            }
            .onAppear {
                inputUrl = vm.activeApiUrlString
            }
        }
    }
    
    // MARK: - Diagnostics
    private var diagnosticCard: some View {
        WFCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(WFTheme.cyan)
                    Text("实时网络与解析状态")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(WFTheme.cyan)
                    
                    Spacer()
                    
                    Text(vm.isLive ? "在线同步中" : "离线/快照")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(vm.isLive ? WFTheme.green : WFTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((vm.isLive ? WFTheme.green : WFTheme.gold).opacity(0.15))
                        .clipShape(Capsule())
                }
                
                let info = vm.diagnosticInfo
                
                HStack(spacing: 12) {
                    metricTag(title: "状态码", value: info.status == 0 ? "N/A" : "\(info.status)", color: info.status == 200 ? WFTheme.green : WFTheme.gold)
                    metricTag(title: "报文大小", value: String(format: "%.1f KB", Double(info.bytes) / 1024.0), color: WFTheme.textPrimary)
                    metricTag(title: "耗时", value: String(format: "%.0f ms", info.duration * 1000), color: WFTheme.textPrimary)
                }
                
                if let err = vm.errorMessage ?? info.error {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("异常信息:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(WFTheme.red)
                        Text(err)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(WFTheme.textPrimary)
                            .lineLimit(4)
                    }
                    .padding(8)
                    .background(WFTheme.red.opacity(0.12))
                    .cornerRadius(6)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(WFTheme.green)
                        Text("数据解析正常，所有卡片已完成映射")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.green)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func metricTag(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(WFTheme.textMuted)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(WFTheme.panelElevated)
        .cornerRadius(6)
    }
    
    // MARK: - Data Source Config
    private var dataSourceConfigCard: some View {
        WFCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("数据源 (URL) 配置")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(WFTheme.gold)
                
                Text("输入自定义 API 接口，或指定局域网内电脑 HTTP 地址：")
                    .font(.system(size: 11))
                    .foregroundColor(WFTheme.textSecondary)
                
                TextField("http://192.168.x.x:8080/worldstate.json", text: $inputUrl)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(WFTheme.textPrimary)
                    .padding(10)
                    .background(Color(hex: "0B1017"))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(WFTheme.border, lineWidth: 1)
                    )
                
                HStack(spacing: 10) {
                    Button {
                        vm.updateCustomApiUrl(inputUrl)
                        dismiss()
                    } label: {
                        Text("保存并立刻生效")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(WFTheme.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Button {
                        vm.resetToDefaultApiUrl()
                        inputUrl = vm.activeApiUrlString
                    } label: {
                        Text("恢复官方源")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(WFTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(WFTheme.panelElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                Divider().background(WFTheme.border)
                
                Button {
                    vm.loadBundledSnapshotDirectly()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "archivebox.fill")
                        Text("直接加载内置离线快照 (DefaultSnapshot)")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WFTheme.gold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }
        }
    }
    
    // MARK: - Tutorial
    private var localHostTutorialCard: some View {
        WFCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("💡 局域网免编译热调试技巧")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(WFTheme.cyan)
                
                Text("""
                1. 确保手机与电脑连入同一 Wi-Fi；
                2. 在电脑项目终端中运行：
                   python -m http.server 8080
                3. 查看电脑局域网 IP（cmd 输入 ipconfig，如 192.168.1.100）；
                4. 在上方输入框填入：
                   http://192.168.1.100:8080/worldstate.json
                5. 之后在电脑上修改 JSON 文件保存，手机下拉刷新即刻更新界面！
                """)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(WFTheme.textSecondary)
                .lineSpacing(3)
            }
        }
    }
}
