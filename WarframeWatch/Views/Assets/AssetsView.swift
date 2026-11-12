import SwiftUI

/// 资产：把库存当成资产看，而不是待办清单。
///
/// 三类东西，三种问法：
///   套装 —— 我有什么成套的、能卖多少、缺几件
///   遗物 —— 哪些值得开、开出来能补哪套
///   Aya  —— 这期能换什么、值不值得换
///
/// 价格全部是**在线卖家的最低价**，也就是此刻真能成交的价。挂单最低价里
/// 有 1p 钓鱼单，不可信（详见 `scripts/wf_market.py` 的注释）。
public struct AssetsView: View {
    @ObservedObject private var feed = InventoryFeed.shared

    @State private var segment: AssetSegment = AssetsView.seededSegment
    @State private var sort: SetSortKey = .loose
    @State private var query = ""
    @State private var detail: PrimeSet?

    /// `simctl` 点不了屏幕，所以靠启动参数把某个分段/详情直接摆出来，
    /// CI 才能拍到遗物页和套装详情，而不是只有默认的套装列表。
    private static var seededSegment: AssetSegment {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "-assetTab"),
              args.index(after: flag) < args.endIndex else { return .sets }
        switch args[args.index(after: flag)] {
        case "relics": return .relics
        case "aya": return .aya
        default: return .sets
        }
    }

    private static var seededSet: String? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "-assetSet"),
              args.index(after: flag) < args.endIndex else { return nil }
        return args[args.index(after: flag)]
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()

                if let data = feed.data {
                    ScrollView {
                        VStack(alignment: .leading, spacing: WFUI.s4) {
                            header(data)
                            summary(data)
                            segmentBar
                            content(data)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 100)
                    }
                    .refreshable { await feed.refresh() }
                } else {
                    empty
                }
            }
            .task { await feed.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                guard let name = AssetsView.seededSet, detail == nil,
                      let hit = feed.data?.sets.first(where: { $0.zh.hasPrefix(name) })
                else { return }
                detail = hit
            }
            .sheet(item: $detail) { picked in
                SetDetailView(set: picked)
                    // 部件表 + 整卖对比 + 遗物列表，medium 高度装不下，
                    // 底部会切在「能出的遗物」标题上
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 头

    private func header(_ data: InventoryData) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("资产")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                HStack(spacing: 5) {
                    Text("背包源 \(AssetFormat.stamp(data.profile.sync)) · "
                         + "已发布 \(AssetFormat.stamp(feed.manifest?.publishedAt)) · "
                         + "价格 \(AssetFormat.stamp(data.marketAt))")
                    if feed.fetching {
                        ProgressView()
                            .controlSize(.mini)
                    } else if feed.failed {
                        // 拉不到就还是本地那份，不假装是最新的
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 9))
                    }
                }
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
            }

            Spacer(minLength: WFUI.s2)

            // 白金余额是这里唯一会「花掉」的数字，放最上面
            VStack(alignment: .trailing, spacing: 1) {
                Text(AssetFormat.grouped(data.profile.plat))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WFTheme.cyan)
                Text("白金")
                    .font(.system(size: 10))
                    .foregroundColor(WFTheme.textMuted)
            }
        }
    }

    // MARK: - 总览

    private func summary(_ data: InventoryData) -> some View {
        let t = data.totals
        let allDucats = t.allDucats ?? t.looseDucats
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                bigNumber("\(AssetFormat.plat(t.loosePlat))", unit: "p", label: "散件可变现")
                Rectangle().fill(WFUI.hairline).frame(width: 0.5, height: 44)
                bigNumber(AssetFormat.grouped(allDucats), unit: "", label: "全部可换 Ducats")
                Rectangle().fill(WFUI.hairline).frame(width: 0.5, height: 44)
                bigNumber("\(t.setsOwned)", unit: "/\(t.setsAll)", label: "已制成")
            }
            .padding(.vertical, 16)

            if allDucats != t.looseDucats {
                Text("保留每套未制作物品各一件后：\(AssetFormat.grouped(t.looseDucats)) Ducats")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                    .padding(.bottom, 11)
            }

            WFHairline()

            HStack(spacing: 0) {
                miniStat("可制造", t.setsReady)
                miniStat("缺 ≤2 件", t.setsClose)
                miniStat("遗物", t.relicKinds, suffix: " 代号")
                miniStat("Mod", t.mods, suffix: " 张")
            }
            .padding(.vertical, 11)
        }
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: WFUI.radius, style: .continuous))
    }

    private func bigNumber(_ value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WFTheme.gold)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(WFTheme.gold.opacity(0.7))
                }
            }
            Text(label)
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func miniStat(_ label: String, _ value: Int, suffix: String = "") -> some View {
        VStack(spacing: 3) {
            Text("\(value)\(suffix)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(WFTheme.textPrimary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(WFTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 分段

    private var segmentBar: some View {
        HStack(spacing: 6) {
            ForEach(AssetSegment.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { segment = item }
                } label: {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(.system(size: 12, weight: segment == item ? .semibold : .regular))
                        Text("\(count(item))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(segment == item ? WFTheme.gold : WFTheme.textMuted)
                    }
                    .foregroundColor(segment == item ? WFTheme.gold : WFTheme.textSecondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(segment == item ? WFTheme.gold.opacity(0.13) : WFUI.surface)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func count(_ segment: AssetSegment) -> Int {
        guard let data = feed.data else { return 0 }
        switch segment {
        case .sets: return data.sets.count
        case .relics: return data.relics.count
        case .aya: return data.aya.items.count
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(_ data: InventoryData) -> some View {
        switch segment {
        case .sets: setList(data)
        case .relics: relicList(data)
        case .aya: ayaList(data)
        }
    }

    private func setList(_ data: InventoryData) -> some View {
        let rows = filteredSets(data)
        return VStack(alignment: .leading, spacing: WFUI.s2) {
            searchField
            sortRow

            if rows.isEmpty {
                emptyNote("没有匹配的套装")
            } else {
                WFSurface {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                        Button { detail = item } label: {
                            setRow(item, isLast: index == rows.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(WFTheme.textMuted)
            TextField("搜套装", text: $query)
                .font(.system(size: 13))
                .foregroundColor(WFTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(WFTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(WFUI.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func filteredSets(_ data: InventoryData) -> [PrimeSet] {
        var rows = data.sets
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            rows = rows.filter { $0.zh.localizedCaseInsensitiveContains(q) }
        }
        // 已制成的但一件余件都没有的，只留个存在感，别占前面
        switch sort {
        case .loose:
            rows.sort { ($0.loose, $0.setPrice) > ($1.loose, $1.setPrice) }
        case .missing:
            // 缺件少的在前；已制成（没有缺口可补）沉到底
            rows.sort {
                let lhs = $0.missing == 0 ? Int.max : $0.missing
                let rhs = $1.missing == 0 ? Int.max : $1.missing
                return lhs != rhs ? lhs < rhs : $0.setPrice > $1.setPrice
            }
        case .price:
            rows.sort { $0.setPrice > $1.setPrice }
        case .name:
            rows.sort { $0.zh < $1.zh }
        }
        return rows
    }

    private var sortRow: some View {
        HStack(spacing: 6) {
            Text("排序")
                .font(.system(size: 10))
                .foregroundColor(WFTheme.textMuted)
            ForEach(SetSortKey.allCases, id: \.self) { item in
                Button {
                    sort = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 11, weight: sort == item ? .semibold : .regular))
                        .foregroundColor(sort == item ? WFTheme.cyan : WFTheme.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(sort == item ? WFTheme.cyan.opacity(0.12) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WFUI.s1)
    }

    private func setRow(_ entry: PrimeSet, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: WFUI.s3) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(accent(entry))
                    .frame(width: 2.5, height: 38)

                ItemIcon(entry.i, remote: entry.u, size: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.zh)
                        .font(.wfTitle)
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle(entry))
                        .font(.wfBody)
                        .foregroundColor(WFTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: WFUI.s2)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(entry.loose > 0 ? "\(AssetFormat.plat(entry.loose)) p" : (entry.setPrice > 0 ? "\(AssetFormat.plat(entry.setPrice)) p" : "—"))
                        .font(.wfNumSmall)
                        .foregroundColor(entry.loose > 0 ? WFTheme.gold : WFTheme.textSecondary)
                    Text(entry.loose > 0 ? "余件" : "套价")
                        .font(.system(size: 10))
                        .foregroundColor(WFTheme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLast { WFHairline().padding(.leading, 30) }
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ entry: PrimeSet) -> String {
        var bits = [entry.cat]
        if entry.isOwned {
            bits.append("已制成")
            let spare = entry.parts.reduce(0) { $0 + $1.n }
            if spare > 0 { bits.append("余 \(spare) 件") }
        } else if entry.isReady {
            bits.append("部件齐全待制造")
        } else {
            bits.append("缺 \(entry.missing) 件")
            if !entry.relics.isEmpty { bits.append("\(entry.relics.count) 张遗物可出") }
        }
        return bits.joined(separator: " · ")
    }

    private func accent(_ entry: PrimeSet) -> Color {
        if entry.isOwned { return WFTheme.green }
        if entry.isReady { return WFTheme.gold }
        return entry.missing <= 2 ? WFTheme.cyan : WFTheme.textMuted.opacity(0.5)
    }

    private func relicList(_ data: InventoryData) -> some View {
        WFSurface {
            ForEach(Array(data.relics.enumerated()), id: \.element.id) { index, relic in
                relicRow(relic, isLast: index == data.relics.count - 1)
            }
        }
    }

    private func relicRow(_ relic: RelicRow, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: WFUI.s3) {
                ItemIcon(relic.i, remote: relic.u, size: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(relic.id)
                            .font(.wfTitle)
                            .foregroundColor(WFTheme.textPrimary)
                        Text("×\(relic.n)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(WFTheme.textSecondary)
                    }
                    HStack(spacing: 8) {
                        ForEach(Array(relic.refine.enumerated()), id: \.offset) { _, pair in
                            HStack(spacing: 2) {
                                Text(pair.0)
                                    .font(.system(size: 10))
                                    .foregroundColor(WFTheme.textMuted)
                                Text("\(pair.1)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(pair.1 > 0 ? WFTheme.textSecondary : WFTheme.textMuted.opacity(0.45))
                            }
                        }
                    }
                }

                Spacer(minLength: WFUI.s2)

                VStack(alignment: .trailing, spacing: 3) {
                    // 遗物按张卖，价格是单张的；乘上持有量才是这堆的总值
                    Text(relic.p > 0 ? "\(relic.p) p" : "—")
                        .font(.wfNumSmall)
                        .foregroundColor(relic.p > 0 ? WFTheme.gold : WFTheme.textMuted)
                    Text(relic.miss > 0 ? "每张 · 缺 \(relic.miss) 套" : "每张")
                        .font(.system(size: 10))
                        .foregroundColor(relic.miss > 0 ? WFTheme.cyan : WFTheme.textMuted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLast { WFHairline().padding(.leading, 14) }
        }
    }

    private func ayaList(_ data: InventoryData) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            if let expiry = data.aya.expiry {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("本期到 \(AssetFormat.stamp(expiry))")
                        .font(.system(size: 11))
                }
                .foregroundColor(WFTheme.textMuted)
                .padding(.horizontal, WFUI.s1)
            }

            if data.aya.items.isEmpty {
                emptyNote("没拿到当期 Aya 清单")
            } else {
                WFSurface {
                    ForEach(Array(data.aya.items.enumerated()), id: \.element.id) { index, item in
                        ayaRow(item, isLast: index == data.aya.items.count - 1)
                    }
                }
            }

            Text("Varzia 用 Aya 换的遗物，1 Aya = 1 张。价格是该遗物在 market 的在线最低价，成组卖给别人的上限大约就是它。")
                .font(.system(size: 11))
                .foregroundColor(WFTheme.textMuted)
                .padding(.horizontal, WFUI.s1)
                .padding(.top, 2)
        }
    }

    private func ayaRow(_ item: AyaShop.Item, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: WFUI.s3) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(item.owned ? WFTheme.textMuted.opacity(0.4) : WFTheme.gold)
                    .frame(width: 2.5, height: 30)

                ItemIcon(item.i, remote: item.u, size: 30)

                Text(item.id)
                    .font(.wfTitle)
                    .foregroundColor(WFTheme.textPrimary)

                Spacer(minLength: WFUI.s2)

                Text(item.owned ? "已有" : "没有")
                    .font(.system(size: 11))
                    .foregroundColor(item.owned ? WFTheme.green : WFTheme.cyan)

                Text(item.p > 0 ? "\(item.p) p" : "—")
                    .font(.wfNumSmall)
                    .foregroundColor(item.p > 0 ? WFTheme.gold : WFTheme.textMuted)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLast { WFHairline().padding(.leading, 30) }
        }
    }

    // MARK: - 空态

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.wfBody)
            .foregroundColor(WFTheme.textMuted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 36)
    }

    private var empty: some View {
        VStack(spacing: WFUI.s3) {
            Image(systemName: "shippingbox")
                .font(.system(size: 30, weight: .light))
                .foregroundColor(WFTheme.textMuted)
            Text("还没有背包快照")
                .font(.wfTitle)
                .foregroundColor(WFTheme.textSecondary)
            Text("在电脑上跑 scripts/wf_inventory.py read\n再跑 build_app_inventory.py 重新打包")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundColor(WFTheme.textMuted)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - 枚举

public enum AssetSegment: CaseIterable, Hashable {
    case sets, relics, aya

    var title: String {
        switch self {
        case .sets: return "套装"
        case .relics: return "遗物"
        case .aya: return "Aya"
        }
    }
}

public enum SetSortKey: CaseIterable, Hashable {
    case loose, missing, price, name

    var title: String {
        switch self {
        case .loose: return "余件价值"
        case .missing: return "缺件"
        case .price: return "套价"
        case .name: return "名称"
        }
    }
}
