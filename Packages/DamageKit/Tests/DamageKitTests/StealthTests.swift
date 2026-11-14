import XCTest
@testable import DamageKit

final class StealthTests: XCTestCase {
    private let enemy = Enemy(name: "E", faction: "Neutral", health: 1e12, armor: 0)

    private func melee() -> Weapon {
        Weapon(name: "Melee", attacks: [
            Attack(name: "Normal Attack", speed: 1, critChance: 20, critMultiplier: 2,
                   statusChance: 0, damage: [.impact: 100]),
        ], magazineSize: 1, reloadTime: 0, category: "Melee")
    }

    func testStealthUsesSiteNonCriticalAndCriticalBranchesForMelee() {
        let baseline = Calculator().evaluate(DamageInput(
            weapon: melee(), enemy: enemy, level: 1, build: Build(), options: Options(window: 1)
        )).attacks[0]
        let stealth = Calculator().evaluate(DamageInput(
            weapon: melee(), enemy: enemy, level: 1, build: Build(),
            options: Options(window: 1, stealth: true)
        )).attacks[0]

        // Critical damage itself is quantized by the core's normal game rule,
        // so lock the site-specific stealth delta rather than re-specifying
        // that independent quantization here.
        // Site rule: a non-crit 1x becomes 7x; a crit 2x becomes 9x.
        // .8 * 7 + .2 * 9 = 7.4.
        XCTAssertEqual(stealth.targetDirectDamage - baseline.targetDirectDamage, 620, accuracy: 1e-9)
    }

    func testStealthPreservesSiteHeadshotBranching() {
        let baseline = Calculator().evaluate(DamageInput(
            weapon: melee(), enemy: enemy, level: 1, build: Build(),
            options: Options(window: 1, headshot: true)
        )).attacks[0]
        let result = Calculator().evaluate(DamageInput(
            weapon: melee(), enemy: enemy, level: 1, build: Build(),
            options: Options(window: 1, stealth: true, headshot: true)
        )).attacks[0]

        // Non-crit: 3x headshot then 7x stealth = 21x. Crit: the site's
        // critical-headshot result is 12x, followed by +7 = 19x.
        XCTAssertEqual(result.targetDirectDamage - baseline.targetDirectDamage, 1_580,
                       accuracy: 1e-9)
    }

    func testStealthToggleDoesNothingForNonMeleeWeapon() {
        var gun = melee()
        gun.category = "primary"
        let baseline = Calculator().evaluate(DamageInput(
            weapon: gun, enemy: enemy, level: 1, build: Build(), options: Options(window: 1)
        )).attacks[0]
        let stealth = Calculator().evaluate(DamageInput(
            weapon: gun, enemy: enemy, level: 1, build: Build(), options: Options(window: 1, stealth: true)
        )).attacks[0]
        XCTAssertEqual(stealth.targetDirectDamage, baseline.targetDirectDamage, accuracy: 1e-9)
    }
}
