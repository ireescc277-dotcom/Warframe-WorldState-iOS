import SwiftUI

public struct WatchlistView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    @State private var selectedTab: WatchTab = .catalog
    @State private var selectedCategory: WatchCategory = .all
    
    public enum WatchTab: String, CaseIterable, Identifiable {
        case catalog = "监控大盘"
        case watchlist = "已关注"
        case diff = "数据变动"
        public var id: String { rawValue }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 10) {
                    // Main Segment Picker
                    Picker("模式", selection: $selectedTab) {
                        ForEach(WatchTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            switch selectedTab {
                            case .catalog:
                                catalogContent
                            case .watchlist:
                                watchlistContent
                            case .diff:
                                DiffListView(diffs: vm.currentDiffs)
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
            .navigationTitle("全景监控与关注")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - 监控大盘 (全量穷举 + 实时评估 + 概率拟合)
    @ViewBuilder
    private var catalogContent: some View {
        // Category Pills Filter
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WatchCategory.allCases) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 11))
                            Text(cat.rawValue)
                                .font(.system(size: 12, weight: selectedCategory == cat ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(selectedCategory == cat ? WFTheme.bgPrimary : WFTheme.textSecondary)
                        .background(selectedCategory == cat ? WFTheme.gold : WFTheme.cardBg)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedCategory == cat ? Color.clear : WFTheme.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        
        let allItems = vm.evaluatedCatalogItems
        let filteredItems = allItems.filter { item in
            selectedCategory == .all || item.item.category == selectedCategory
        }
        
        // Summary KPI Banner
        let activeCount = allItems.filter { $0.state.isActive }.count
        let subscribedCount = vm.subscribedCatalogIds.count
        
        WFCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前正在发生")
                        .font(.system(size: 11))
                        .foregroundColor(WFTheme.textMuted)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(WFTheme.green)
                            .frame(width: 8, height: 8)
                        Text("\(activeCount)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(WFTheme.green)
                        Text("项")
                            .font(.system(size: 12))
                            .foregroundColor(WFTheme.textSecondary)
                    }
                }
                
                Divider()
                    .frame(height: 24)
                    .background(WFTheme.cardBorder)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("我的关注项目")
                        .font(.system(size: 11))
                        .foregroundColor(WFTheme.textMuted)
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(WFTheme.gold)
                        Text("\(subscribedCount)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(WFTheme.gold)
                        Text("项")
                            .font(.system(size: 12))
                            .foregroundColor(WFTheme.textSecondary)
                    }
                }
                
                Spacer()
                
                Text("优先呈现进行中")
                    .font(.system(size: 11))
                    .foregroundColor(WFTheme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(WFTheme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        
        // Catalog Items List
        ForEach(filteredItems) { evaluated in
            WatchCatalogRowView(evaluated: evaluated) {
                vm.toggleCatalogSubscription(evaluated.item.id)
            }
        }
    }
    
    // MARK: - 已关注清单
    @ViewBuilder
    private var watchlistContent: some View {
        // Notification permission banner if not authorized
        if !vm.isNotificationAuthorized {
            WFCard {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 20))
                        .foregroundColor(WFTheme.gold)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("开启到期提醒通知")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(WFTheme.textPrimary)
                        Text("在关注任务到期前 30 分钟向您发送本地通知提醒。")
                            .font(.system(size: 11))
                            .foregroundColor(WFTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button("开启") {
                        vm.requestNotificationPermission()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(WFTheme.bgPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(WFTheme.gold)
                    .clipShape(Capsule())
                }
            }
        }
        
        let subscribedCatalog = vm.evaluatedCatalogItems.filter { $0.isSubscribed }
        let manualItems = vm.sortedWatchItems
        
        if subscribedCatalog.isEmpty && manualItems.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "star.slash.fill")
                    .font(.system(size: 40))
                    .foregroundColor(WFTheme.textMuted)
                
                Text("还没有关注任何条目")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(WFTheme.textPrimary)
                
                Text("切换到【监控大盘】点击 ★，或在任务列表点击右上角星标，即可在此集中追踪。")
                    .font(.system(size: 12))
                    .foregroundColor(WFTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            if !subscribedCatalog.isEmpty {
                HStack {
                    Text("监控大盘已关注 (\(subscribedCatalog.count))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(WFTheme.gold)
                    Spacer()
                }
                .padding(.top, 4)
                
                ForEach(subscribedCatalog) { evaluated in
                    WatchCatalogRowView(evaluated: evaluated) {
                        vm.toggleCatalogSubscription(evaluated.item.id)
                    }
                }
            }
            
            if !manualItems.isEmpty {
                HStack {
                    Text("单节点手动星标 (\(manualItems.count))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(WFTheme.cyan)
                    Spacer()
                }
                .padding(.top, 8)
                
                ForEach(manualItems) { item in
                    manualWatchItemRow(item: item)
                }
            }
        }
    }
    
    @ViewBuilder
    private func manualWatchItemRow(item: WatchItem) -> some View {
        WFCard(isHighlighted: item.isExpiringSoon) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TagView(item.section, style: .gold)
                        
                        Text(item.label)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(WFTheme.textPrimary)
                            .lineLimit(1)
                    }
                    
                    if let exp = item.expiry {
                        Text("到期: \(exp.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(WFTheme.textMuted)
                    }
                }
                
                Spacer()
                
                CountdownView(targetDate: item.expiry)
                
                // Toggle reminder
                Button {
                    vm.toggleReminder(for: item.key)
                } label: {
                    Image(systemName: item.isReminderEnabled ? "bell.fill" : "bell.slash")
                        .font(.system(size: 14))
                        .foregroundColor(item.isReminderEnabled ? WFTheme.gold : WFTheme.textMuted)
                        .frame(width: 28, height: 28)
                }
                
                // Delete
                Button {
                    withAnimation {
                        vm.toggleWatchItem(key: item.key, label: item.label, section: item.section, expiry: item.expiry)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(WFTheme.red)
                        .frame(width: 28, height: 28)
                }
            }
        }
    }
}
