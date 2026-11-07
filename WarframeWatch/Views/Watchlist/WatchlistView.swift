import SwiftUI

public struct WatchlistView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    @State private var onlySubscribed: Bool = false
    @State private var searchQuery: String = ""
    @State private var selectedCategory: WatchCategory = .all
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 8) {
                    // Single Compact Filter Bar (Search + Star Toggle)
                    topSearchBar
                    
                    // Simple Category Strip
                    categoryStrip
                    
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            let items = filteredItems
                            
                            if items.isEmpty {
                                emptyState
                            } else {
                                // 1. Active Section
                                let activeItems = items.filter { $0.state.isActive }
                                if !activeItems.isEmpty {
                                    sectionHeader("正在发生 (\(activeItems.count))", color: WFTheme.green)
                                    ForEach(activeItems) { evaluated in
                                        WatchCatalogRowView(evaluated: evaluated) {
                                            toggleSubscription(evaluated)
                                        }
                                    }
                                }
                                
                                // 2. Deterministic Cycles Section
                                let deterministicItems = items.filter {
                                    if case .deterministic = $0.state { return true }
                                    return false
                                }
                                if !deterministicItems.isEmpty {
                                    sectionHeader("确定性周期与重置 (\(deterministicItems.count))", color: WFTheme.cyan)
                                    ForEach(deterministicItems) { evaluated in
                                        WatchCatalogRowView(evaluated: evaluated) {
                                            toggleSubscription(evaluated)
                                        }
                                    }
                                }
                                
                                // 3. Probabilistic & Upcoming Section
                                let probabilisticItems = items.filter {
                                    if case .probabilistic = $0.state { return true }
                                    return false
                                }
                                if !probabilisticItems.isEmpty {
                                    sectionHeader("监控库与预测 (\(probabilisticItems.count))", color: WFTheme.gold)
                                    ForEach(probabilisticItems) { evaluated in
                                        WatchCatalogRowView(evaluated: evaluated) {
                                            toggleSubscription(evaluated)
                                        }
                                    }
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
    
    // MARK: - Single Compact Search & Star Bar
    private var topSearchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(WFTheme.textMuted)
                    .font(.system(size: 13))
                
                TextField("搜索监控目标 / 道具 / 模式…", text: $searchQuery)
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
            
            // Only Subscribed Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    onlySubscribed.toggle()
                    HapticService.selection()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: onlySubscribed ? "star.fill" : "star")
                        .font(.system(size: 12))
                    Text("仅看关注")
                        .font(.system(size: 12, weight: onlySubscribed ? .bold : .medium))
                }
                .foregroundColor(onlySubscribed ? WFTheme.gold : WFTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(onlySubscribed ? WFTheme.gold.opacity(0.15) : WFTheme.panelElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(onlySubscribed ? WFTheme.gold.opacity(0.4) : WFTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }
    
    // MARK: - Category Strip
    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(WatchCategory.allCases) { cat in
                    let isSelected = selectedCategory == cat
                    Button {
                        selectedCategory = cat
                        HapticService.selection()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 10))
                            Text(cat.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .foregroundColor(isSelected ? WFTheme.bgPrimary : WFTheme.textSecondary)
                        .background(isSelected ? WFTheme.gold : WFTheme.panelElevated)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.clear : WFTheme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
        }
    }
    
    // MARK: - Section Header
    @ViewBuilder
    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
            
            Spacer()
        }
        .padding(.top, 8)
        .padding(.horizontal, 2)
    }
    
    // MARK: - Filtered Items Logic
    private var filteredItems: [EvaluatedWatchItem] {
        vm.evaluatedCatalogItems.filter { item in
            if onlySubscribed && !item.isSubscribed {
                return false
            }
            if selectedCategory != .all && item.item.category != selectedCategory {
                return false
            }
            if searchQuery.isEmpty {
                return true
            }
            return item.item.title.localizedCaseInsensitiveContains(searchQuery) ||
                   item.item.subtitle.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    private func toggleSubscription(_ item: EvaluatedWatchItem) {
        vm.toggleCatalogSubscription(item.item.id)
        HapticService.impact(.medium)
        
        // Native local notification scheduling for deterministic items
        if case let .deterministic(nextDate, _, note) = item.state {
            if !item.isSubscribed {
                // Scheduled
                let watch = WatchItem(key: item.item.id, label: item.item.title, section: note, expiry: nextDate)
                NotificationService.shared.scheduleReminder(for: watch)
            } else {
                NotificationService.shared.cancelReminder(for: item.item.id)
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "star.slash")
                .font(.system(size: 32))
                .foregroundColor(WFTheme.textMuted)
            
            Text(onlySubscribed ? "暂无已关注条目" : "未搜索到匹配项")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(WFTheme.textPrimary)
            
            Text(onlySubscribed ? "点击卡片右侧 ★ 即可加入关注，或取消「仅看关注」浏览全量监控库。" : "尝试更换搜索词或切换分类。")
                .font(.system(size: 11))
                .foregroundColor(WFTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
