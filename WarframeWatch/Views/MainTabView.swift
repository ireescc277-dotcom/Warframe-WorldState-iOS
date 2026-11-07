import SwiftUI

public struct MainTabView: View {
    @EnvironmentObject private var vm: WorldStateViewModel
    
    public init() {}
    
    public var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("焦点", systemImage: "gauge.with.needle.fill")
                }
            
            MissionsListView()
                .tabItem {
                    Label("任务", systemImage: "target")
                }
            
            HubEventsView()
                .tabItem {
                    Label("探索", systemImage: "globe.asia.australia.fill")
                }
            
            WatchlistView()
                .tabItem {
                    Label("关注", systemImage: "star.fill")
                }
                .badge(vm.watchItems.isEmpty ? 0 : vm.watchItems.count)
            
            ReferenceView()
                .tabItem {
                    Label("资料库", systemImage: "books.vertical.fill")
                }
        }
        .tint(WFTheme.gold)
    }
}
