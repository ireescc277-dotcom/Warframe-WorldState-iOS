import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The watch tab answers one question: did anything I am waiting for show up.
///
/// The tree of 3102 selectable nodes used to be this screen, which meant the
/// first thing a user saw was five levels of indentation. The tree is a
/// configuration surface, not a dashboard, so it now lives one push away.
public struct WatchView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    @Environment(\.openURL) private var openURL

    @State private var showTree: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: WFUI.s4) {
                        header
                        summary
                        if !vm.watchSelection.isEmpty {
                            alertRow
                        }
                        hitSection
                        if !vm.watchSelection.isEmpty {
                            targetSection
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
            .navigationDestination(isPresented: $showTree) {
                WatchTreeScreen()
                    .environmentObject(vm)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("蹲守")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                Text(vm.watchSelection.isEmpty ? "还没有勾选目标" : "已勾选 \(vm.watchSelection.count) 组")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
            }

            Spacer()

            Button {
                showTree = true
            } label: {
                Text("编辑")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WFTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(WFUI.surface)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Summary

    /// The big number is only worth 46pt when it is counting something. At
    /// zero it said "0 个目标正在出现" in the largest type on the screen, which
    /// reads as a broken page rather than a quiet one, so the card becomes an
    /// instruction when nothing is selected and a plain status line when
    /// nothing is hitting.
    @ViewBuilder
    private var summary: some View {
        let hits = vm.matchedLiveHits.count
        WFSurface {
            if vm.watchSelection.isEmpty {
                setupCard
            } else if hits == 0 {
                waitingCard
            } else {
                hitCard(hits)
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            Text("还没有蹲守目标")
                .font(.wfTitle)
                .foregroundColor(WFTheme.textPrimary)

            Text("从任务树上勾选组合，比如「中纪 · 钢铁 · 中断」。组里任何一个节点出现，都会列在下面。")
                .font(.wfBody)
                .foregroundColor(WFTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showTree = true
            } label: {
                Text("选择目标")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "0A0E17"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(WFTheme.gold)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            WFHairline().padding(.top, WFUI.s1)

            Text("或者从一个常用的开始")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)

            HStack(spacing: WFUI.s2) {
                ForEach(WatchPreset.all) { preset in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            vm.addWatchPaths(preset.paths)
                        }
                    } label: {
                        Text(preset.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(WFTheme.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(WFUI.raised)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            HStack(alignment: .center, spacing: WFUI.s2) {
                Text("没有命中")
                    .font(.wfTitle)
                    .foregroundColor(WFTheme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "hourglass")
                    .font(.system(size: 14))
                    .foregroundColor(WFTheme.textMuted)
            }

            Text("正在等 \(vm.watchSelection.count) 组目标。盘面轮换后出现的会立刻列在这里。")
                .font(.wfBody)
                .foregroundColor(WFTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private func hitCard(_ hits: Int) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s3) {
            HStack(alignment: .firstTextBaseline, spacing: WFUI.s2) {
                Text("\(hits)")
                    .font(.wfHero)
                    .foregroundColor(WFTheme.green)
                Text("个目标正在出现")
                    .font(.wfBody)
                    .foregroundColor(WFTheme.textSecondary)
                Spacer(minLength: 0)
            }

            Text("下面每一条都在你勾选的范围内。")
                .font(.wfBody)
                .foregroundColor(WFTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    /// 面包屑在根节点上就是它自己的标题（「仲裁 / 仲裁」），那样等于白占一行。
    /// 这种情况下换成节点的说明文字（「任务类型 / 星球 / 节点」）。
    private func subtitle(for path: String) -> String {
        let title = vm.watchTree.node(path)?.title ?? ""
        let crumb = vm.watchTree.breadcrumb(of: path)
        if crumb != title { return crumb }
        return vm.watchTree.node(path)?.subtitle ?? ""
    }

    // MARK: - Alerts

    /// 通知开关放在蹲守页而不是「更多」：它跟「蹲什么」是同一件事，放在设置里
    /// 就成了第二个需要想起来的地方。权限被拒的时候开关没有意义，所以那一路
    /// 直接把右侧换成「设置」，点了跳系统页。
    private var alertRow: some View {
        WFSurface {
            HStack(spacing: WFUI.s3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(vm.notificationsEnabled ? WFTheme.gold : WFTheme.textMuted)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("开打提醒")
                        .font(.wfTitle)
                        .foregroundColor(WFTheme.textPrimary)
                    Text(hint)
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: WFUI.s2)

                if vm.notificationPermission == .denied {
                    #if canImport(UIKit)
                    Button("设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(WFTheme.cyan)
                    .buttonStyle(.plain)
                    #endif
                } else {
                    Toggle("", isOn: Binding(
                        get: { vm.notificationsEnabled },
                        set: { vm.setNotificationsEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(WFTheme.gold)
                }
            }
            .padding(14)
        }
    }

    private var icon: String {
        vm.notificationsEnabled ? "bell.fill" : "bell"
    }

    private var hint: String {
        switch vm.notificationPermission {
        case .denied:
            return "系统里关掉了通知，点右边去开"
        case .notDetermined, .authorized:
            break
        }
        guard vm.notificationsEnabled else {
            return "仲裁和周期会提前 5 分钟响，关掉 App 也算数"
        }
        guard vm.pendingAlertCount > 0 else {
            return "已开启，暂时没有排得上时间的条目"
        }
        return "已排 \(vm.pendingAlertCount) 条：仲裁 / 周期提前 5 分钟，目标提前 30 分钟"
    }

    // MARK: - Hits

    @ViewBuilder
    private var hitSection: some View {
        let hits = Array(vm.matchedLiveHits.prefix(12))
        if !hits.isEmpty {
            VStack(alignment: .leading, spacing: WFUI.s2) {
                WFSectionHeader("正在命中", trailing: "\(vm.matchedLiveHits.count) 项")

                WFSurface {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        WFEventRow(
                            accent: WFTheme.green,
                            title: hit.title,
                            subtitle: hit.detail,
                            isLast: index == hits.count - 1
                        ) {
                            WFTimeLeft(hit.expiry)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Targets

    private var targetSection: some View {
        let paths = Array(vm.watchSelection.paths).sorted().prefix(5)
        let hint: String? = vm.watchSelection.isEmpty ? nil : "\(vm.watchSelection.count) 组"
        return VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("监控范围", trailing: hint)

            if vm.watchSelection.isEmpty {
                WFSurface {
                    Button {
                        showTree = true
                    } label: {
                        HStack(spacing: WFUI.s2) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 15))
                                .foregroundColor(WFTheme.gold)
                            Text("选择要蹲的目标")
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textSecondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(WFTheme.textMuted)
                        }
                        .padding(14)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                WFSurface {
                    ForEach(Array(paths.enumerated()), id: \.element) { index, path in
                        HStack(spacing: WFUI.s3) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(WFTheme.gold)
                                .frame(width: 3, height: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vm.watchTree.node(path)?.title ?? path)
                                    .font(.wfTitle)
                                    .foregroundColor(WFTheme.textPrimary)
                                    .lineLimit(1)
                                let subtitle = subtitle(for: path)
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.wfBody)
                                        .foregroundColor(WFTheme.textMuted)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if index != paths.count - 1 {
                                WFHairline().padding(.leading, 30)
                            }
                        }
                    }
                }

                if vm.watchSelection.count > paths.count {
                    Button {
                        showTree = true
                    } label: {
                        Text("还有 \(vm.watchSelection.count - paths.count) 组 · 展开全部")
                            .font(.wfBody)
                            .foregroundColor(WFTheme.cyan)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Tree screen

struct WatchTreeScreen: View {
    @EnvironmentObject private var vm: WorldStateViewModel

    @State private var searchQuery: String = ""
    @State private var onlySelected: Bool = false

    var body: some View {
        ZStack {
            WFTheme.bgPrimary.ignoresSafeArea()

            VStack(spacing: WFUI.s3) {
                searchField
                filterRow

                ScrollView {
                    LazyVStack(spacing: 1) {
                        let rows = visibleRows
                        if rows.isEmpty {
                            emptyState
                        } else {
                            ForEach(rows) { row in
                                WatchTreeRow(
                                    row: row,
                                    selectionState: vm.watchSelectionState(row.node.id),
                                    hitCount: vm.liveHitCount(for: row.node.id),
                                    nextDate: vm.nextOccurrence(for: row.node.id),
                                    isExpanded: vm.isWatchExpanded(row.node.id),
                                    breadcrumb: searchQuery.isEmpty ? nil : vm.watchTree.breadcrumb(of: row.node.id),
                                    onExpand: { vm.toggleWatchExpansion(row.node.id) },
                                    onToggleSelection: { vm.toggleWatchSelection(row.node.id) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 90)
                }
            }
        }
        .navigationTitle("监控目标")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchField: some View {
        HStack(spacing: WFUI.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(WFTheme.textMuted)
            TextField("节点 / 任务类型 / 纪元", text: $searchQuery)
                .font(.wfBody)
                .foregroundColor(WFTheme.textPrimary)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(WFTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 12)
    }

    private var filterRow: some View {
        HStack(spacing: WFUI.s2) {
            Text("已选 \(vm.watchSelection.count) 组")
                .font(.wfLabel)
                .foregroundColor(vm.watchSelection.isEmpty ? WFTheme.textMuted : WFTheme.gold)
            Text("命中 \(vm.matchedLiveHits.count)")
                .font(.wfLabel)
                .foregroundColor(vm.matchedLiveHits.isEmpty ? WFTheme.textMuted : WFTheme.green)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    onlySelected.toggle()
                }
            } label: {
                Text(onlySelected ? "仅看已选" : "看全部")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(onlySelected ? WFTheme.gold : WFTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(onlySelected ? WFTheme.gold.opacity(0.14) : WFUI.surface)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Rows

    private var visibleRows: [WatchRow] {
        if !searchQuery.isEmpty {
            var rows: [WatchRow] = []
            appendSearchRows(vm.watchTree.roots, into: &rows)
            return rows
        }
        if onlySelected {
            var rows: [WatchRow] = []
            appendSelectedRows(vm.watchTree.roots, depth: 0, into: &rows)
            return rows
        }
        var rows: [WatchRow] = []
        appendExpandedRows(vm.watchTree.roots, depth: 0, into: &rows)
        return rows
    }

    private func appendExpandedRows(_ nodes: [WatchNode], depth: Int, into rows: inout [WatchRow]) {
        for node in nodes {
            rows.append(WatchRow(node: node, depth: depth))
            if vm.isWatchExpanded(node.id) {
                appendExpandedRows(node.children, depth: depth + 1, into: &rows)
            }
        }
    }

    private func appendSelectedRows(_ nodes: [WatchNode], depth: Int, into rows: inout [WatchRow]) {
        for node in nodes {
            let state = vm.watchSelectionState(node.id)
            if state == .off { continue }
            rows.append(WatchRow(node: node, depth: depth))
            if state == .mixed {
                appendSelectedRows(node.children, depth: depth + 1, into: &rows)
            }
        }
    }

    private func appendSearchRows(_ nodes: [WatchNode], into rows: inout [WatchRow]) {
        for node in nodes {
            if node.title.localizedCaseInsensitiveContains(searchQuery) {
                rows.append(WatchRow(node: node, depth: 0))
            }
            appendSearchRows(node.children, into: &rows)
        }
    }

    private var emptyState: some View {
        VStack(spacing: WFUI.s2) {
            Image(systemName: onlySelected ? "star.slash" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundColor(WFTheme.textMuted)
            Text(emptyTitle)
                .font(.wfBody)
                .foregroundColor(WFTheme.textSecondary)
            Text(emptyHint)
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyTitle: String {
        if !searchQuery.isEmpty { return "没有匹配的节点" }
        if onlySelected { return "还没有勾选任何组合" }
        return "暂无可选条目"
    }

    private var emptyHint: String {
        if !searchQuery.isEmpty { return "试试 Tycho、捕获、古纪" }
        if onlySelected { return "关掉「仅看已选」，展开后点右侧圆圈" }
        return "下拉刷新世界状态后重试"
    }
}

private struct WatchRow: Identifiable {
    let node: WatchNode
    let depth: Int
    var id: String { node.id }
}

/// One-tap starting points offered while nothing is selected. Each string is a
/// real path in the tree, so applying one is exactly what tapping the circles
/// by hand would produce.
private struct WatchPreset: Identifiable {
    let title: String
    let paths: [String]

    var id: String { title }

    static let all: [WatchPreset] = [
        WatchPreset(title: "全部仲裁", paths: ["arb"]),
        WatchPreset(
            title: "钢铁裂隙",
            paths: ["fis|VoidT1|sp", "fis|VoidT2|sp", "fis|VoidT3|sp",
                    "fis|VoidT4|sp", "fis|VoidT5|sp", "fis|VoidT6|sp"]
        ),
        WatchPreset(title: "全部入侵", paths: ["inv"])
    ]
}

private struct WatchTreeRow: View {
    let row: WatchRow
    let selectionState: WatchSelectionState
    let hitCount: Int
    let nextDate: Date?
    let isExpanded: Bool
    let breadcrumb: String?
    let onExpand: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: WFUI.s2) {
            Button(action: onExpand) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(WFTheme.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 20, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(row.node.isLeaf ? 0 : 1)
            .disabled(row.node.isLeaf)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.node.title)
                    .font(.system(size: 15, weight: row.depth <= 1 ? .semibold : .regular))
                    .foregroundColor(row.depth == 0 ? WFTheme.gold : WFTheme.textPrimary)
                    .lineLimit(1)

                if let subtitle = breadcrumb ?? row.node.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(WFTheme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: WFUI.s1)

            if hitCount > 0 {
                Text("\(hitCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WFTheme.green)
            } else if let nextDate = nextDate {
                WFTimeLeft(nextDate)
            }

            Button(action: onToggleSelection) {
                Image(systemName: checkboxIcon)
                    .font(.system(size: 20))
                    .foregroundColor(checkboxColor)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(row.depth) * 16)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(row.depth == 0 ? WFUI.surface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var checkboxIcon: String {
        switch selectionState {
        case .on: return "checkmark.circle.fill"
        case .mixed: return "minus.circle.fill"
        case .off: return "circle"
        }
    }

    private var checkboxColor: Color {
        switch selectionState {
        case .on: return WFTheme.gold
        case .mixed: return WFTheme.cyan
        case .off: return WFTheme.textMuted
        }
    }
}
