import SwiftUI

#if canImport(UIKit)
import UIKit

/// 后台刷新和通知注册都得在 `didFinishLaunching` 里做完，SwiftUI 的
/// `WindowGroup` 在后台唤起时不一定被求值，所以这两件事只能挂在 AppDelegate 上。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundRefresh.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 每次退到后台就续一发；不续的话系统跑完一次就不再唤醒了。
        BackgroundRefresh.schedule()
    }
}
#endif

@main
public struct WarframeWatchApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    /// 单例，不是状态：后台任务被唤起时 SwiftUI 的 body 不一定跑过，
    /// 只有共享实例能保证那条路径拿得到真的 ViewModel。
    @StateObject private var viewModel = WorldStateViewModel.shared
    
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
