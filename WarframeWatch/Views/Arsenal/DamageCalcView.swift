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
    /// The concrete A/B/C build selected on the Arsenal configuration page.
    /// It must travel with the owned instance; defaulting back to A here would
    /// make a loadout look correct while calculating a different build.
    private let ownedWeaponConfigIndex: Int
    private let ownedWarframe: InventoryData.OwnedWarframe?
    private let warframeConfigIndex: Int
    private let availableWarframes: [InventoryData.OwnedWarframe]
    /// Companion bodies are separate account instances with their own A/B/C
    /// builds.  They are passed through so the calculator can bind a buff to
    /// a real source instead of asking for a free-form Mod name.
    private let availableCompanions: [InventoryData.OwnedEquipment]
    private let title: String

    public init(weapon: String? = nil,
                ownedWeapon: InventoryData.OwnedWeapon? = nil,
                ownedWeaponConfigIndex: Int = 0,
                ownedWarframe: InventoryData.OwnedWarframe? = nil,
                warframeConfigIndex: Int = 0,
                availableWarframes: [InventoryData.OwnedWarframe] = [],
                availableCompanions: [InventoryData.OwnedEquipment] = [],
                title: String = "伤害计算") {
        self.weapon = weapon
        self.ownedWeapon = ownedWeapon
        self.ownedWeaponConfigIndex = ownedWeaponConfigIndex
        self.ownedWarframe = ownedWarframe
        self.warframeConfigIndex = warframeConfigIndex
        self.availableWarframes = availableWarframes
        self.availableCompanions = availableCompanions
        self.title = title
    }

    public var body: some View {
        NativeDamageCalculatorView(
            weapon: weapon,
            ownedWeapon: ownedWeapon,
            ownedWeaponConfigIndex: ownedWeaponConfigIndex,
            ownedWarframe: ownedWarframe,
            warframeConfigIndex: warframeConfigIndex,
            availableWarframes: availableWarframes,
            availableCompanions: availableCompanions,
            title: title
        )
    }
}
