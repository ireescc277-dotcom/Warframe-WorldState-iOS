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
    private let ownedWeapon: InventoryData.OwnedWeapon?
    private let ownedWarframe: InventoryData.OwnedWarframe?
    private let warframeConfigIndex: Int
    private let availableWarframes: [InventoryData.OwnedWarframe]
    private let title: String

    public init(weapon: String? = nil,
                ownedWeapon: InventoryData.OwnedWeapon? = nil,
                ownedWarframe: InventoryData.OwnedWarframe? = nil,
                warframeConfigIndex: Int = 0,
                availableWarframes: [InventoryData.OwnedWarframe] = [],
                title: String = "伤害计算") {
        self.weapon = weapon
        self.ownedWeapon = ownedWeapon
        self.ownedWarframe = ownedWarframe
        self.warframeConfigIndex = warframeConfigIndex
        self.availableWarframes = availableWarframes
        self.title = title
    }

    public var body: some View {
        NativeDamageCalculatorView(
            weapon: weapon,
            ownedWeapon: ownedWeapon,
            ownedWarframe: ownedWarframe,
            warframeConfigIndex: warframeConfigIndex,
            availableWarframes: availableWarframes,
            title: title
        )
    }
}
