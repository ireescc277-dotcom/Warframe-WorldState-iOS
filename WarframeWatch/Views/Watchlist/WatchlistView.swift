import SwiftUI

public struct WatchlistView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    @State private var selectedTab: WatchTab = .watchlist
    
    public enum WatchTab: String, CaseIterable, Identifiable {
        case watchlist = "关注清单"
        case diff = "数据变动"
        public var id: String { rawValue }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                WFTheme.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    // Segment Picker
                    Picker("模式", selection: $selectedTab) {
                        ForEach(WatchTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            switch selectedTab {
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
            .navigationTitle("关注与变动")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
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
        
        let items = vm.sortedWatchItems
        if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "star.slash.fill")
                    .font(.system(size: 36))
                    .foregroundColor(WFTheme.textMuted)
                
                Text("还没有关注任何条目")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(WFTheme.textPrimary)
                
                Text("点击任何任务或特惠卡片右上角的 ☆ 即可加入此清单，支持到期自动提醒。")
                    .font(.system(size: 12))
                    .foregroundColor(WFTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        } else {
            ForEach(items) { item in
                watchItemRow(item: item)
            }
        }
    }
    
    @ViewBuilder
    private func watchItemRow(item: WatchItem) -> some View {
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
                
                // Toggle notification reminder
                Button {
                    vm.toggleReminder(for: item.key)
                } label: {
                    Image(systemName: item.isReminderEnabled ? "bell.fill" : "bell.slash")
                        .font(.system(size: 14))
                        .foregroundColor(item.isReminderEnabled ? WFTheme.gold : WFTheme.textMuted)
                        .frame(width: 28, height: 28)
                }
                
                // Delete / Unstar
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
