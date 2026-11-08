import SwiftUI

public struct WatchlistView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    @State private var searchQuery: String = ""
    @State private var onlySelected: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 8) {
                    topBar

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            matchedSection

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
                        .padding(.horizontal)
                        .padding(.bottom, 90)
                    }
                    .refreshable {
                        await vm.refreshData()
                    }
                }
            }
            .navigationTitle("关注中心")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(WFTheme.textMuted)
                        .font(.system(size: 13))

                    TextField("搜索节点 / 任务类型 / 纪元…", text: $searchQuery)
                        .foregroundColor(WFTheme.textPrimary)
                        .font(.system(size: 13))

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(WFTheme.textMuted)
                                .font(.system(size: 12))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(WFTheme.panelElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(WFTheme.border, lineWidth: 1)
                )

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        onlySelected.toggle()
                        HapticService.selection()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: onlySelected ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12))
                        Text("仅看已选")
                            .font(.system(size: 12, weight: onlySelected ? .bold : .medium))
                    }
                    .foregroundColor(onlySelected ? WFTheme.gold : WFTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(onlySelected ? WFTheme.gold.opacity(0.15) : WFTheme.panelElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(onlySelected ? WFTheme.gold.opacity(0.4) : WFTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Text("已选 \(vm.watchSelection.count) 组")
                    .foregroundColor(vm.watchSelection.isEmpty ? WFTheme.textMuted : WFTheme.gold)
                Text("·")
                Text("命中 \(vm.matchedLiveHits.count)")
                    .foregroundColor(vm.matchedLiveHits.isEmpty ? WFTheme.textMuted : WFTheme.green)
                Spacer()
                Text("点圆圈勾选整支")
            }
            .font(.system(size: 10))
            .foregroundColor(WFTheme.textMuted)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - Live hits

    @ViewBuilder
    private var matchedSection: some View {
        let hits = Array(vm.matchedLiveHits.prefix(6))
        if !hits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(WFTheme.green)
                        .frame(width: 6, height: 6)
                    Text("正在命中 (\(vm.matchedLiveHits.count))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(WFTheme.green)
                    Spacer()
                }

                ForEach(hits) { hit in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hit.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(WFTheme.textPrimary)
                                .lineLimit(1)
                            Text(hit.detail)
                                .font(.system(size: 10))
                                .foregroundColor(WFTheme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        if let expiry = hit.expiry {
                            CountdownView(targetDate: expiry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(WFTheme.panelElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Rows

    private var visibleRows: [WatchRow] {
        if !searchQuery.isEmpty {
            return searchRows
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

    private var searchRows: [WatchRow] {
        var rows: [WatchRow] = []
        appendSearchRows(vm.watchTree.roots, into: &rows)
        return rows
    }

    private func appendSearchRows(_ nodes: [WatchNode], into rows: inout [WatchRow]) {
        for node in nodes {
            if node.title.localizedCaseInsensitiveContains(searchQuery) {
                rows.append(WatchRow(node: node, depth: 0))
            }
            appendSearchRows(node.children, into: &rows)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: onlySelected ? "star.slash" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(WFTheme.textMuted)

            Text(emptyTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(WFTheme.textPrimary)

            Text(emptyHint)
                .font(.system(size: 11))
                .foregroundColor(WFTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyTitle: String {
        if !searchQuery.isEmpty { return "没有匹配的节点" }
        if onlySelected { return "还没有勾选任何组合" }
        return "暂无可选条目"
    }

    private var emptyHint: String {
        if !searchQuery.isEmpty { return "试试节点名（如 Tycho）、任务类型（如 捕获）或纪元（如 古纪）。" }
        if onlySelected { return "关掉「仅看已选」，展开某一支后点右侧圆圈勾选。" }
        return "下拉刷新世界状态后重试。"
    }
}

// MARK: - Row model

private struct WatchRow: Identifiable {
    let node: WatchNode
    let depth: Int
    var id: String { node.id }
}

// MARK: - Row view

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
        HStack(spacing: 6) {
            Button(action: onExpand) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(WFTheme.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 18, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(row.node.isLeaf ? 0 : 1)
            .disabled(row.node.isLeaf)

            Image(systemName: row.node.icon)
                .font(.system(size: 11))
                .foregroundColor(row.depth == 0 ? WFTheme.gold : WFTheme.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.node.title)
                    .font(.system(size: 13, weight: row.depth <= 1 ? .semibold : .regular))
                    .foregroundColor(row.depth == 0 ? WFTheme.gold : WFTheme.textPrimary)
                    .lineLimit(1)

                if let subtitle = breadcrumb ?? row.node.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(WFTheme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if hitCount > 0 {
                Text("\(hitCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(WFTheme.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(WFTheme.green.opacity(0.15))
                    .clipShape(Capsule())
            } else if let nextDate = nextDate {
                CountdownView(targetDate: nextDate, showSeconds: false)
            }

            Button(action: onToggleSelection) {
                Image(systemName: checkboxIcon)
                    .font(.system(size: 17))
                    .foregroundColor(checkboxColor)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(row.depth) * 14)
        .padding(.trailing, 2)
        .padding(.vertical, 5)
        .background(row.depth == 0 ? WFTheme.panelElevated : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
