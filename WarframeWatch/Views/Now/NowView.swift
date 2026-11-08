import SwiftUI

/// The opening screen: one timeline, sorted by how soon it ends.
///
/// The old dashboard stacked a KPI grid, a search box, a star strip and five
/// kinds of card, so nothing led. Here there is one hero (the next thing to
/// expire) and one list; the categories are a filter row, not four screens.
public struct NowView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    private let dict = DictionaryService.shared

    @State private var filter: NowFilter = .all
    @State private var showDebug: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: WFUI.s4) {
                        header

                        if let err = vm.errorMessage {
                            notice(err)
                        }

                        if vm.worldState == nil {
                            fallbackCard
                        } else {
                            heroBlock
                            chipRow

                            if filter == .fissures {
                                eraStrip
                            }

                            listBlock
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await vm.refreshData()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDebug) {
                DebugSheetView()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("现在")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                Text(statusLine)
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }

            Spacer()

            Button {
                showDebug = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(WFTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(WFUI.surface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await vm.refreshData() }
            } label: {
                Group {
                    if vm.isLoading {
                        ProgressView().tint(WFTheme.textSecondary)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(WFTheme.textSecondary)
                    }
                }
                .frame(width: 34, height: 34)
                .background(WFUI.surface)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var statusLine: String {
        if !vm.isLive {
            return "离线快照 · 下拉重新获取"
        }
        let minutes = Int(Date().timeIntervalSince(vm.lastUpdated) / 60)
        if minutes < 1 {
            return "实时 · 刚刚更新"
        }
        if minutes < 60 {
            return "实时 · \(minutes) 分钟前更新"
        }
        return "实时 · \(minutes / 60) 小时前更新"
    }

    private func notice(_ text: String) -> some View {
        HStack(spacing: WFUI.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(WFTheme.gold)
            Text(text)
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(WFTheme.gold.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroBlock: some View {
        if let next = items.first {
            WFSurface {
                VStack(alignment: .leading, spacing: WFUI.s3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.kicker)
                            .font(.wfLabel)
                            .foregroundColor(next.accent)
                        Spacer()
                        Text("接下来")
                            .font(.wfLabel)
                            .foregroundColor(WFTheme.textMuted)
                    }

                    HStack(alignment: .center, spacing: WFUI.s3) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(next.title)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(WFTheme.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(next.subtitle)
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: WFUI.s2)

                        WFTimeLeft(next.expiry, isHero: true)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Fallback

    private var fallbackCard: some View {
        WFSurface {
            VStack(alignment: .leading, spacing: WFUI.s3) {
                Text("还没有读到世界状态")
                    .font(.wfTitle)
                    .foregroundColor(WFTheme.textPrimary)
                Text("检查网络，或者先用内置快照看看界面。")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textSecondary)
                Button {
                    vm.loadBundledSnapshotDirectly()
                } label: {
                    Text("载入内置快照")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: "0A0E17"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(WFTheme.gold)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    // MARK: - Filters

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WFUI.s2) {
                ForEach(NowFilter.allCases) { kind in
                    WFChip(
                        icon: kind.icon,
                        label: kind.label,
                        count: count(for: kind),
                        tint: kind.tint,
                        isOn: filter == kind
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            filter = kind
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var eraStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                eraButton("全部", value: nil)
                eraButton("古纪", value: "VoidT1")
                eraButton("前纪", value: "VoidT2")
                eraButton("中纪", value: "VoidT3")
                eraButton("后纪", value: "VoidT4")
                eraButton("安魂", value: "VoidT5")
                eraButton("全能", value: "VoidT6")

                Rectangle()
                    .fill(WFUI.hairline)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, WFUI.s1)

                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        vm.isSteelPathOnly.toggle()
                    }
                } label: {
                    Text("钢铁")
                        .font(.system(size: 12, weight: vm.isSteelPathOnly ? .semibold : .regular))
                        .foregroundColor(vm.isSteelPathOnly ? WFTheme.red : WFTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func eraButton(_ title: String, value: String?) -> some View {
        let isOn = vm.selectedEra == value
        let color = value.map { WFUI.eraColor($0) } ?? WFTheme.cyan
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                vm.selectedEra = value
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                .foregroundColor(isOn ? color : WFTheme.textMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isOn ? color.opacity(0.12) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var listBlock: some View {
        let rows = visibleRows
        let hint: String? = rows.isEmpty ? nil : "\(rows.count) 项"
        return VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("按剩余时间", trailing: hint)

            if rows.isEmpty {
                emptyState
            } else {
                WFSurface {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        WFEventRow(
                            accent: item.accent,
                            title: item.title,
                            subtitle: item.subtitle,
                            isLast: index == rows.count - 1
                        ) {
                            trailing(for: item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trailing(for item: NowItem) -> some View {
        if let percent = item.percent, item.expiry == nil {
            Text("\(percent)%")
                .font(.wfNumSmall)
                .foregroundColor(percent >= 100 ? WFTheme.textMuted : WFTheme.red)
                .fixedSize()
        } else {
            WFTimeLeft(item.expiry)
        }
    }

    private var emptyState: some View {
        VStack(spacing: WFUI.s2) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundColor(WFTheme.textMuted)
            Text(filter == .all ? "当前没有进行中的事件" : "这一栏现在是空的")
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Data

    private var visibleRows: [NowItem] {
        let all = items
        let scoped = filter == .all ? all : all.filter { $0.category == filter }
        // The hero is always the first of these, so the list starts at the second.
        return Array(scoped.dropFirst().prefix(60))
    }

    private func count(for kind: NowFilter) -> Int {
        kind == .all ? items.count : items.filter { $0.category == kind }.count
    }

    /// Everything on the board, soonest first. Events without a deadline
    /// (invasions) sort last, which is also where people look for them.
    private var items: [NowItem] {
        var all: [NowItem] = []
        all.append(contentsOf: fissureItems)
        all.append(contentsOf: invasionItems)
        all.append(contentsOf: alertItems)
        all.append(contentsOf: stormItems)
        return all.sorted { lhs, rhs in
            (lhs.expiry ?? .distantFuture) < (rhs.expiry ?? .distantFuture)
        }
    }

    private var fissureItems: [NowItem] {
        var list = vm.worldState?.ActiveMissions ?? []
        if let era = vm.selectedEra {
            list = list.filter { $0.Modifier == era }
        }
        if vm.isSteelPathOnly {
            list = list.filter { $0.isSteelPath }
        }
        return list.map { mission in
            var bits: [String] = []
            if let planet = dict.nodePlanet(mission.Node) {
                bits.append(planet)
            }
            bits.append(dict.tierName(mission.Modifier))
            if mission.isSteelPath {
                bits.append("钢铁")
            }
            return NowItem(
                id: "fis-" + mission.id,
                accent: WFUI.eraColor(mission.Modifier),
                kicker: "虚空裂隙",
                title: "\(dict.missionType(mission.MissionType)) · \(dict.nodeShortName(mission.Node))",
                subtitle: bits.joined(separator: " · "),
                expiry: mission.Expiry?.date,
                percent: nil,
                category: .fissures
            )
        }
    }

    private var invasionItems: [NowItem] {
        let list = (vm.worldState?.Invasions ?? []).filter { invasion in
            vm.hideCompletedInvasions ? !invasion.Completed : true
        }
        return list.map { invasion in
            NowItem(
                id: "inv-" + invasion.id,
                accent: invasion.Completed ? WFTheme.textMuted : WFTheme.red,
                kicker: "入侵",
                title: "入侵 · \(dict.nodeShortName(invasion.Node))",
                subtitle: dict.faction(invasion.Faction),
                expiry: nil,
                percent: Int((invasion.progressPct * 100).rounded()),
                category: .invasions
            )
        }
    }

    private var alertItems: [NowItem] {
        (vm.worldState?.Alerts ?? []).map { alert in
            NowItem(
                id: "alr-" + alert.id,
                accent: WFTheme.gold,
                kicker: "限时警报",
                title: "警报 · \(dict.missionType(alert.MissionInfo?.missionType))",
                subtitle: dict.nodeName(alert.MissionInfo?.location),
                expiry: alert.Expiry?.date,
                percent: nil,
                category: .alerts
            )
        }
    }

    private var stormItems: [NowItem] {
        (vm.worldState?.VoidStorms ?? []).map { storm in
            NowItem(
                id: "stm-" + storm.id,
                accent: WFTheme.purple,
                kicker: "虚空风暴",
                title: "风暴 · \(dict.nodeShortName(storm.Node))",
                subtitle: dict.tierName(storm.ActiveMissionTier),
                expiry: storm.Expiry?.date,
                percent: nil,
                category: .storms
            )
        }
    }
}

// MARK: - Models

private struct NowItem: Identifiable {
    let id: String
    let accent: Color
    let kicker: String
    let title: String
    let subtitle: String
    let expiry: Date?
    let percent: Int?
    let category: NowFilter
}

private enum NowFilter: String, CaseIterable, Identifiable {
    case all
    case fissures
    case invasions
    case alerts
    case storms

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .fissures: return "裂隙"
        case .invasions: return "入侵"
        case .alerts: return "警报"
        case .storms: return "风暴"
        }
    }

    var icon: String {
        switch self {
        case .all: return "circle.grid.2x2"
        case .fissures: return "sparkles"
        case .invasions: return "arrow.left.arrow.right"
        case .alerts: return "bell"
        case .storms: return "tornado"
        }
    }

    var tint: Color {
        switch self {
        case .all: return WFTheme.textPrimary
        case .fissures: return WFTheme.cyan
        case .invasions: return WFTheme.red
        case .alerts: return WFTheme.gold
        case .storms: return WFTheme.purple
        }
    }
}
