import SwiftUI

/// Entry point kept for the Arsenal navigation API.
///
/// The former implementation embedded the copied website in WKWebView and
/// started a loopback HTTP server. The calculator is now a native SwiftUI
/// screen: its state is built into `DamageInput` and evaluated by DamageKit in
/// process. Website data is used only as an offline JSON catalogue and as the
/// comparison oracle in development tests; it is not executed in the app.
public struct DamageCalcView: View {
    private let weapon: String?
    private let title: String

    public init(weapon: String? = nil, title: String = "伤害计算") {
        self.weapon = weapon
        self.title = title
    }

    public var body: some View {
        NativeDamageCalculatorView(weapon: weapon, title: title)
    }
}
