import SwiftUI

/// Anything that resets on a daily or weekly clock: sortie, archon hunt, Baro,
/// daily deals. These do not need to be watched, they need to be checked off,
/// so the layout is one block per item with a single countdown on top.
public struct CycleView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    private let dict = DictionaryService.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: WFUI.s4) {
                        header

                        if let sorties = vm.worldState?.Sorties, !sorties.isEmpty {
                            ForEach(sorties) { sortie in
                                sortieBlock(sortie)
                            }
                        }

                        if let archons = vm.worldState?.LiteSorties, !archons.isEmpty {
                            ForEach(archons) { archon in
                                archonBlock(archon)
                            }
                        }

                        if let traders = vm.worldState?.VoidTraders, !traders.isEmpty {
                            ForEach(traders) { trader in
                                traderBlock(trader)
                            }
                        }

                        if let deals = vm.worldState?.DailyDeals, !deals.isEmpty {
                            dealsBlock(deals)
                        }

                        if vm.worldState == nil {
                            Text("还没有数据，下拉刷新。")
                                .font(.wfBody)
                                .foregroundColor(WFTheme.textMuted)
                                .padding(.top, 40)
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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("周期")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(WFTheme.textPrimary)
            Text("每天或每周重置的内容")
                .font(.wfLabel)
                .foregroundColor(WFTheme.textMuted)
        }
    }

    // MARK: - Sortie

    private func sortieBlock(_ sortie: Sortie) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("每日突击", trailing: dict.bossName(sortie.Boss))

            WFSurface {
                VStack(spacing: 0) {
                    ForEach(Array((sortie.Variants ?? []).enumerated()), id: \.element.id) { index, variant in
                        stageRow(
                            index: index + 1,
                            title: "\(dict.missionType(variant.missionType)) · \(dict.nodeShortName(variant.node))",
                            detail: dict.sortieModifierName(variant.modifierType),
                            warning: true,
                            isLast: index == (sortie.Variants ?? []).count - 1
                        )
                    }
                    if let expiry = sortie.Expiry?.date {
                        footer(expiry)
                    }
                }
            }
        }
    }

    // MARK: - Archon

    private func archonBlock(_ archon: LiteSortie) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("执刑官猎杀", trailing: dict.bossName(archon.Boss))

            WFSurface {
                VStack(spacing: 0) {
                    ForEach(Array((archon.Missions ?? []).enumerated()), id: \.element.id) { index, mission in
                        stageRow(
                            index: index + 1,
                            title: "\(dict.missionType(mission.missionType)) · \(dict.nodeShortName(mission.node))",
                            detail: "",
                            warning: false,
                            isLast: index == (archon.Missions ?? []).count - 1
                        )
                    }
                    if let expiry = archon.Expiry?.date {
                        footer(expiry)
                    }
                }
            }
        }
    }

    // MARK: - Baro

    private func traderBlock(_ trader: VoidTrader) -> some View {
        let active = trader.isActive
        return VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("虚空商人", trailing: nil)

            WFSurface {
                HStack(spacing: WFUI.s3) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(active ? WFTheme.gold : WFTheme.textMuted)
                        .frame(width: 3, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(active ? "Baro 已在 \(dict.nodeShortName(trader.Node))" : "Baro 尚未抵达")
                            .font(.wfTitle)
                            .foregroundColor(WFTheme.textPrimary)
                            .lineLimit(1)
                        Text(active ? "带着 \(trader.Manifest?.count ?? 0) 件商品" : "下一站 \(dict.nodeShortName(trader.Node))")
                            .font(.wfBody)
                            .foregroundColor(WFTheme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: WFUI.s2)

                    WFTimeLeft(active ? trader.Expiry?.date : trader.Activation?.date)
                }
                .padding(14)
            }
        }
    }

    // MARK: - Deals

    private func dealsBlock(_ deals: [DailyDeal]) -> some View {
        VStack(alignment: .leading, spacing: WFUI.s2) {
            WFSectionHeader("每日特惠", trailing: "\(deals.count) 项")

            WFSurface {
                ForEach(Array(deals.enumerated()), id: \.element.id) { index, deal in
                    WFEventRow(
                        accent: WFTheme.cyan,
                        title: dict.itemName(deal.StoreItem),
                        subtitle: "\(deal.Discount)% off · \(deal.SalePrice) 白金",
                        isLast: index == deals.count - 1
                    ) {
                        WFTimeLeft(deal.Expiry?.date)
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private func stageRow(index: Int, title: String, detail: String, warning: Bool, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: WFUI.s3) {
                Text("\(index)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WFTheme.textMuted)
                    .frame(width: 16, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(WFTheme.textPrimary)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.wfBody)
                            .foregroundColor(warning ? WFTheme.red.opacity(0.85) : WFTheme.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if !isLast {
                WFHairline().padding(.leading, 43)
            }
        }
    }

    private func footer(_ expiry: Date) -> some View {
        VStack(spacing: 0) {
            WFHairline()
            HStack {
                Text("剩余")
                    .font(.wfLabel)
                    .foregroundColor(WFTheme.textMuted)
                Spacer()
                WFTimeLeft(expiry)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
