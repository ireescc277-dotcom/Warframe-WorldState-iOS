import SwiftUI

public struct MainTabView: View {
    @EnvironmentObject private var vm: WorldStateViewModel

    /// Selected tab, seeded from a launch argument so the CI screenshot gate
    /// can photograph each screen without tapping anything. Passing
    /// `-startTab 2` on the command line opens 周期 on launch; the value is
    /// otherwise absent and the user simply starts on 现在.
    @State private var selection: Int = MainTabView.seededTab

    private static var seededTab: Int {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "-startTab"), args.index(after: flag) < args.endIndex,
              let value = Int(args[args.index(after: flag)]), (0...4).contains(value)
        else { return 0 }
        return value
    }

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            NowView()
                .tabItem {
                    Label("现在", systemImage: "circle.dotted")
                }
                .tag(0)

            WatchView()
                .tabItem {
                    Label("蹲守", systemImage: "scope")
                }
                .badge(vm.matchedLiveHits.count)
                .tag(1)

            AssetsView()
                .tabItem {
                    Label("资产", systemImage: "shippingbox")
                }
                .tag(2)

            ArsenalView()
                .tabItem {
                    Label("军械库", systemImage: "scope")
                }
                .tag(3)

            MoreView()
                .tabItem {
                    Label("更多", systemImage: "ellipsis")
                }
                .tag(4)
        }
        .tint(WFTheme.gold)
    }
}
