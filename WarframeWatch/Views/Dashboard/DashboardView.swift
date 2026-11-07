import SwiftUI

public struct DashboardView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    private let dict = DictionaryService.shared
    @State private var showDebugSheet: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Top Header & Stats
                        headerSection
                        
                        // Error/Notice Banner
                        if let err = vm.errorMessage {
                            errorBanner(err)
                        }
                        
                        // KPI Grid
                        kpiGridSection
                        
                        // Watchlist Strip (if starred items exist)
                        if !vm.watchItems.isEmpty {
                            watchlistQuickStrip
                        }
                        
                        // Main Focus Cards or Empty Fallback
                        if vm.worldState == nil {
                            emptyDataFallbackCard
                        } else {
                            focusCardsFeed
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
                .refreshable {
                    await vm.refreshData()
                }
            }
            .navigationTitle("焦点看板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDebugSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(vm.isLive ? WFTheme.green : WFTheme.gold)
                                .frame(width: 8, height: 8)
                                .shadow(color: vm.isLive ? WFTheme.green : WFTheme.gold, radius: 4)
                            
                            Text(vm.isLive ? "实时同步" : "快照模式")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(WFTheme.textSecondary)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            showDebugSheet = true
                        } label: {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(WFTheme.textSecondary)
                        }
                        
                        Button {
                            Task {
                                await vm.refreshData()
                            }
                        } label: {
                            if vm.isLoading {
                                ProgressView()
                                    .tint(WFTheme.cyan)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(WFTheme.cyan)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showDebugSheet) {
                DebugSheetView()
            }
        }
    }
    
    // MARK: - Error Banner
    private func errorBanner(_ err: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(WFTheme.gold)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(WFTheme.textPrimary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button("设置/重试") {
                showDebugSheet = true
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(WFTheme.cyan)
        }
        .padding(10)
        .background(WFTheme.gold.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(WFTheme.gold.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Empty State Fallback
    private var emptyDataFallbackCard: some View {
        WFCard {
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 32))
                    .foregroundColor(WFTheme.textMuted)
                
                Text("暂未加载世界状态数据")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(WFTheme.textPrimary)
                
                Text("可能由于设备未授权局域网/蜂窝网络，或官方 API 连接受阻。您可以点击下方直接载入内置离线数据包，或配置电脑局域网 Mock 源。")
                    .font(.system(size: 11))
                    .foregroundColor(WFTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                
                HStack(spacing: 12) {
                    Button {
                        vm.loadBundledSnapshotDirectly()
                    } label: {
                        Text("载入内置离线数据")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(WFTheme.gold)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Button {
                        showDebugSheet = true
                    } label: {
                        Text("打开调试配置")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(WFTheme.cyan)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(WFTheme.cyan.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("WARFRAME")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(WFTheme.textPrimary)
                        
                        Text("世界状态")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(WFTheme.gold)
                    }
                    
                    Text("API: api.warframe.com · 北京时间")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(WFTheme.textMuted)
                }
                
                Spacer()
                
                if let version = vm.worldState?.Version {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("v\(version)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(WFTheme.cyan)
                        
                        Text("协议版本")
                            .font(.system(size: 10))
                            .foregroundColor(WFTheme.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(WFTheme.panelElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.top, 4)
            
            // Search Bar
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(WFTheme.textMuted)
                    
                    TextField("搜索卡片 / 节点 / 物品 / 词缀...", text: $vm.searchQuery)
                        .foregroundColor(WFTheme.textPrimary)
                    
                    if !vm.searchQuery.isEmpty {
                        Button {
                            vm.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(WFTheme.textMuted)
                        }
                    }
                }
                .padding(8)
                .background(WFTheme.panelElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(WFTheme.border, lineWidth: 1)
                )
                
                Button {
                    withAnimation {
                        vm.onlyStarred.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: vm.onlyStarred ? "star.fill" : "star")
                        Text("仅看关注")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(vm.onlyStarred ? WFTheme.gold : WFTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(vm.onlyStarred ? WFTheme.gold.opacity(0.15) : WFTheme.panelElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(vm.onlyStarred ? WFTheme.gold.opacity(0.4) : WFTheme.border, lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // MARK: - KPI Grid
    private var kpiGridSection: some View {
        let alertsCount = vm.worldState?.Alerts?.count ?? 0
        let invCount = vm.worldState?.Invasions?.filter { !$0.Completed }.count ?? 0
        let fissuresCount = vm.worldState?.ActiveMissions?.count ?? 0
        let stormsCount = vm.worldState?.VoidStorms?.count ?? 0
        
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            kpiCard(title: "限时警报", count: "\(alertsCount)", color: WFTheme.gold)
            kpiCard(title: "进行中入侵", count: "\(invCount)", color: WFTheme.red)
            kpiCard(title: "虚空裂隙", count: "\(fissuresCount)", color: WFTheme.cyan)
            kpiCard(title: "虚空风暴", count: "\(stormsCount)", color: WFTheme.purple)
        }
    }
    
    @ViewBuilder
    private func kpiCard(title: String, count: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(count)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(WFTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(WFTheme.panelElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(WFTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Watchlist Strip
    private var watchlistQuickStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("已关注到期时间线")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(WFTheme.gold)
                
                Spacer()
                
                Text("\(vm.watchItems.count)项")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(WFTheme.textMuted)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.sortedWatchItems) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(item.isExpiringSoon ? WFTheme.gold : WFTheme.green)
                                .frame(width: 6, height: 6)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(WFTheme.textPrimary)
                                    .lineLimit(1)
                                
                                CountdownView(targetDate: item.expiry, showSeconds: false)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(WFTheme.panelElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(item.isExpiringSoon ? WFTheme.gold.opacity(0.5) : WFTheme.border, lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Focus Cards Feed
    private var focusCardsFeed: some View {
        VStack(spacing: 12) {
            // Global Buff
            if let buffs = vm.worldState?.GlobalUpgrades {
                ForEach(buffs) { buff in
                    GlobalBuffCardView(buff: buff)
                }
            }
            
            // Daily Sortie
            if let sorties = vm.worldState?.Sorties {
                ForEach(sorties) { sortie in
                    SortieCardView(sortie: sortie)
                }
            }
            
            // Archon Hunt
            if let archons = vm.worldState?.LiteSorties {
                ForEach(archons) { archon in
                    ArchonCardView(archon: archon)
                }
            }
            
            // Void Trader (Baro)
            if let traders = vm.worldState?.VoidTraders {
                ForEach(traders) { trader in
                    BaroCardView(trader: trader)
                }
            }
            
            // Daily Deals
            if let deals = vm.worldState?.DailyDeals {
                ForEach(deals) { deal in
                    DailyDealCardView(deal: deal)
                }
            }
        }
    }
}
