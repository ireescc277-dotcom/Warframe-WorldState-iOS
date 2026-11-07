import SwiftUI

@main
public struct WarframeWatchApp: App {
    @StateObject private var viewModel = WorldStateViewModel()
    
    public init() {
        // Configure global appearance for dark theme
        #if os(iOS)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(WFTheme.bgPrimary)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(WFTheme.textPrimary)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(WFTheme.textPrimary)]
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(WFTheme.bgSecondary)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        #endif
    }
    
    public var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
