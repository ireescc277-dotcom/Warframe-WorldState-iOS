import XCTest
@testable import DamageKit

final class RankedModTests: XCTestCase {

    func testSourceProvenNonMaxRankScalesTheConcreteCardAction() {
        // The account snapshot's normal Gunslinger has +60% fire rate at
        // fusion rank 4 and +72% at rank 5. The inventory adapter emits 5/6
        // only after matching those exact source values to this one-action
        // DamageKit definition; this test guards the core-side application.
        let attack = Attack(name: "Shot", speed: 10, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1])
        var weapon = Weapon(name: "Secondary", attacks: [attack], magazineSize: 10)
        weapon.categories = ["secondary"]

        let ranked = Build(slottedMods: [
            SlottedMod(slot: 0, name: "Gunslinger", actionScale: 5.0 / 6.0)
        ])
        let resolved = BuildResolver(weapon: weapon, build: ranked, options: Options(),
                                     faction: .neutral).resolve(attack: attack)

        // 10 × (1 + 0.72 × 5/6) = 16. It must not be silently promoted to
        // the full-rank 17.2 fire rate.
        XCTAssertEqual(resolved.fireRate, 16, accuracy: 1e-12)
    }

    func testAbsentRankScaleKeepsTheResourceDefinitionUnchanged() {
        let attack = Attack(name: "Shot", speed: 10, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1])
        var weapon = Weapon(name: "Secondary", attacks: [attack], magazineSize: 10)
        weapon.categories = ["secondary"]

        let full = Build(slottedMods: [SlottedMod(slot: 0, name: "Gunslinger")])
        let resolved = BuildResolver(weapon: weapon, build: full, options: Options(),
                                     faction: .neutral).resolve(attack: attack)

        XCTAssertEqual(resolved.fireRate, 17.2, accuracy: 1e-12)
    }
}
