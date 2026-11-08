import SwiftUI

/// Everything that is not a live answer: community goals, the reference tables,
/// and the connection diagnostics. Pushed out of the tab bar on purpose — these
/// are visited when something is wrong or when the player is curious, not daily.
public struct MoreView: View {
    @EnvironmentObject private var vm: WorldStateViewModel

    @State private var sheet: MoreSheet?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: WFUI.s4) {
                        header

                        WFSurface {
                            entry(
                                icon: "globe.asia.australia",
                                title: "社区与枢纽",
                                subtitle: "集团任务 · 午夜电波 · 公告",
                                isLast: false
                            ) { sheet = .hub }

                            entry(
                                icon: "books.vertical",
                                title: "资料库",
                                subtitle: "任务类型 · 词缀 · 物品",
                                isLast: false
                            ) { sheet = .reference }

                            entry(
                                icon: "antenna.radiowaves.left.and.right",
                                title: "连接与诊断",
                                subtitle: vm.isLive ? "实时数据源正常" : "当前为离线快照",
                                isLast: true
                            ) { sheet = .debug }
                        }

                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 100)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { item in
                switch item {
                case .hub:
                    HubEventsView()
                case .reference:
                    ReferenceView()
                case .debug:
                    DebugSheetView()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("更多")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(WFTheme.textPrimary)
            Text("不是每天要看的东西")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
        }
    }

    private func entry(
        icon: String,
        title: String,
        subtitle: String,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: WFUI.s3) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(WFTheme.textSecondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.wfTitle)
                            .foregroundColor(WFTheme.textPrimary)
                        Text(subtitle)
                            .font(.wfBody)
                            .foregroundColor(WFTheme.textMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: WFUI.s2)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(WFTheme.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

                if !isLast {
                    WFHairline().padding(.leading, 51)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: WFUI.s1) {
            Text("数据源 api.warframe.com")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            if let version = vm.worldState?.Version {
                Text("协议版本 v\(version)")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }
            Text(vm.activeApiUrlString)
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, WFUI.s1)
    }
}

private enum MoreSheet: String, Identifiable {
    case hub
    case reference
    case debug

    var id: String { rawValue }
}
