import SwiftUI

public struct MainTabView: View {
    @EnvironmentObject private var vm: WorldStateViewModel

    public init() {}

    public var body: some View {
        TabView {
            NowView()
                .tabItem {
                    Label("现在", systemImage: "circle.dotted")
                }

            WatchView()
                .tabItem {
                    Label("蹲守", systemImage: "scope")
                }
                .badge(vm.matchedLiveHits.count)

            CycleView()
                .tabItem {
                    Label("周期", systemImage: "calendar")
                }

            MoreView()
                .tabItem {
                    Label("更多", systemImage: "ellipsis")
                }
        }
        .tint(WFTheme.gold)
    }
}
