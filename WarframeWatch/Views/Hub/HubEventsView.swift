import SwiftUI

public struct HubEventsView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    private let dict = DictionaryService.shared
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Category Picker
                    categoryPicker
                    
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            switch vm.selectedHubCategory {
                            case .goals:
                                goalsList
                            case .nightwave:
                                if let season = vm.worldState?.SeasonInfo {
                                    NightwaveActsView(season: season)
                                } else {
                                    emptyView("暂无午夜电波赛季数据")
                                }
                            case .syndicates:
                                syndicatesList
                            case .news:
                                newsList
                            case .flashSales:
                                flashSalesList
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .refreshable {
                        await vm.refreshData()
                    }
                }
            }
            .navigationTitle("社区与枢纽")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WorldStateViewModel.HubCategory.allCases) { cat in
                    let isSelected = vm.selectedHubCategory == cat
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.selectedHubCategory = cat
                        }
                    } label: {
                        Text(cat.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? WFTheme.gold : WFTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSelected ? WFTheme.gold.opacity(0.15) : WFTheme.panelElevated)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? WFTheme.gold.opacity(0.4) : WFTheme.border, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private var goalsList: some View {
        if let goals = vm.worldState?.Goals, !goals.isEmpty {
            ForEach(goals) { goal in
                GoalRowView(goal: goal)
            }
        } else {
            emptyView("当前无全服社区目标推进")
        }
    }
    
    @ViewBuilder
    private var syndicatesList: some View {
        if let synds = vm.worldState?.SyndicateMissions, !synds.isEmpty {
            ForEach(synds) { s in
                WFCard {
                    HStack {
                        TagView("集团任务", style: .cyan)
                        Text(dict.syndicate(s.Tag))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(WFTheme.textPrimary)
                        
                        Spacer()
                        
                        CountdownView(targetDate: s.Expiry?.date)
                    }
                    
                    if let nodes = s.Nodes, !nodes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("任务节点 (\(nodes.count)个):")
                                .font(.system(size: 11))
                                .foregroundColor(WFTheme.textMuted)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(nodes, id: \.self) { node in
                                        Text(dict.nodeName(node))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(WFTheme.textSecondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(WFTheme.panelElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            emptyView("暂无集团任务数据")
        }
    }
    
    @ViewBuilder
    private var newsList: some View {
        if let events = vm.worldState?.Events, !events.isEmpty {
            ForEach(events) { ev in
                NewsRowView(news: ev)
            }
        } else {
            emptyView("暂无官方新闻数据")
        }
    }
    
    @ViewBuilder
    private var flashSalesList: some View {
        if let sales = vm.worldState?.FlashSales, !sales.isEmpty {
            ForEach(sales) { sale in
                WFCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dict.itemName(sale.TypeName))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(WFTheme.textPrimary)
                                .lineLimit(1)
                            
                            if let end = sale.EndDate?.date {
                                Text("下架时间: \(end.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(WFTheme.textMuted)
                            }
                        }
                        
                        Spacer()
                        
                        if let plat = sale.PremiumOverride {
                            TagView("\(plat) 白金", style: .cyan)
                        } else if let regular = sale.RegularOverride {
                            TagView("\(regular.formatted()) 现金", style: .green)
                        }
                    }
                }
            }
        } else {
            emptyView("暂无商城特惠组合包")
        }
    }
    
    @ViewBuilder
    private func emptyView(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.system(size: 32))
                .foregroundColor(WFTheme.textMuted)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(WFTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
