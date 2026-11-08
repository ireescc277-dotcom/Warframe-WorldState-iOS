import SwiftUI

public struct WatchlistView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    @State private var onlySubscribed: Bool = false
    @State private var searchQuery: String = ""
    @State private var selectedSection: CatalogSection = .all
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 8) {
                    // Single Compact Filter Bar (Search + Star Toggle)
                    topSearchBar
                    
                    // Simple Section Strip
                    sectionStrip
                    
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            let entries = filteredEntries
                            
                            if entries.isEmpty {
                                emptyState
                            } else {
                                // 1. Active Section (Live Hits)
                                let activeEntries = entries.filter { $0.status.isActive }
                                if !activeEntries.isEmpty {
                                    groupHeader("正在发生 (\(activeEntries.count))", color: WFTheme.green)
                                    ForEach(activeEntries) { evaluated in
                                        WatchCatalogRowView(evaluated: evaluated) {
                                            toggleSubscription(evaluated)
                                        }
                                    }
                                }
                                
                                // 2. Deterministic Cycles Section
                                let deterministicEntries = entries.filter {
                                    if case .deterministic = $0.status { return true }
                                    return false
                                }
                                if !deterministicEntries.isEmpty {
                                    groupHeader("确定性周期与重置 (\(deterministicEntries.count))", color: WFTheme.cyan)
                                    ForEach(deterministicEntries) { evaluated in
                                        WatchCatalogRowView(evaluated: evaluated) {
                                            toggleSubscription(evaluated)
                                        }
                                    }
                                }
                                
                                // 3. All Remaining Library Entries
                                let idleEntries = entries.filter {
                                    if case .idle = $0.status { return true }
                                    return false
                                }
                                if !idleEntries.isEmpty {
                                    groupHeader("全量监控库 (\(idleEntries.count))", color: WFTheme.textSecondary)
                                    ForEach(idleEntries) { evaluated in
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
    
    // MARK: - Section Strip
    private var sectionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(CatalogSection.allCases) { sec in
                    let isSelected = selectedSection == sec
                    Button {
                        selectedSection = sec
                        HapticService.selection()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: sec.icon)
                                .font(.system(size: 10))
                            Text(sec.rawValue)
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
    
    // MARK: - Group Header
    @ViewBuilder
    private func groupHeader(_ title: String, color: Color) -> some View {
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
    
    // MARK: - Filtered Logic
    private var filteredEntries: [EvaluatedWatchEntry] {
        vm.evaluatedCatalogEntries.filter { item in
            if onlySubscribed && !item.isSubscribed {
                return false
            }
            if selectedSection != .all && item.entry.section != selectedSection {
                return false
            }
            if searchQuery.isEmpty {
                return true
            }
            return item.entry.title.localizedCaseInsensitiveContains(searchQuery) ||
                   item.entry.subtitle.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    private func toggleSubscription(_ item: EvaluatedWatchEntry) {
        vm.toggleCatalogSubscription(item.entry.id)
        HapticService.impact(.medium)
        
        // Native local notification scheduling for deterministic items
        if case let .deterministic(nextDate, _, note) = item.status {
            if !item.isSubscribed {
                let watch = WatchItem(key: item.entry.id, label: item.entry.title, section: note, expiry: nextDate)
                NotificationService.shared.scheduleReminder(for: watch)
            } else {
                NotificationService.shared.cancelReminder(for: item.entry.id)
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
