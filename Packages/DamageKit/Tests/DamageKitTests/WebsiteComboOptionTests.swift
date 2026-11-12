import XCTest
@testable import DamageKit

final class WebsiteComboOptionTests: XCTestCase {
    private let target = Enemy(name: "E", faction: "Neutral", health: 1e12, armor: 0)

    private func output(weapon: Weapon, options: Options) -> AttackResult {
        Calculator().evaluate(DamageInput(weapon: weapon, enemy: target, level: 1,
                                         build: Build(), options: options)).attacks[0]
    }

    func testAbilityComboIsCoreResolvedOnlyForExaltedWeapons() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.heat: 100])
        let ordinary = Weapon(name: "Ordinary", attacks: [attack], magazineSize: 10,
                              reloadTime: 0, category: "primary", type: "Rifle")
        let exalted = Weapon(name: "Exalted", attacks: [attack], magazineSize: 10,
                             reloadTime: 0, category: "Melee", type: "Exalted Weapon")
        let baseline = output(weapon: exalted, options: Options(window: 7))
        let option = output(weapon: exalted,
                            options: Options(window: 7, abilityComboMultiplier: 4))
        let custom = output(weapon: exalted,
                            options: Options(window: 7,
                                             customStats: [CustomStatKey.abilityCombo.rawValue: 5],
                                             abilityComboMultiplier: 3))
        let ordinaryBaseline = output(weapon: ordinary, options: Options(window: 7))
        let ignored = output(weapon: ordinary,
                             options: Options(window: 7, abilityComboMultiplier: 4))

        XCTAssertEqual(option.targetDirectDamage, baseline.targetDirectDamage * 4, accuracy: 1e-9)
        XCTAssertEqual(option.targetDotDamage, baseline.targetDotDamage * 4, accuracy: 1e-9)
        XCTAssertEqual(custom.targetDirectDamage, baseline.targetDirectDamage * 5, accuracy: 1e-9)
        XCTAssertEqual(custom.targetDotDamage, baseline.targetDotDamage * 5, accuracy: 1e-9)
        XCTAssertEqual(ignored.targetDirectDamage, ordinaryBaseline.targetDirectDamage, accuracy: 1e-9)
        XCTAssertEqual(ignored.targetDotDamage, ordinaryBaseline.targetDotDamage, accuracy: 1e-9)
    }

    func testSniperComboUsesSourceAttackFlagAndDefaultWhenOverrideIsOff() {
        let sniperAttack = Attack(name: "Zoom", speed: 1, critChance: 0, critMultiplier: 1,
                                  statusChance: 100, damage: [.heat: 100], sniperCombo: true)
        let plainAttack = Attack(name: "Hip", speed: 1, critChance: 0, critMultiplier: 1,
                                 statusChance: 100, damage: [.heat: 100])
        let sniper = Weapon(name: "Sniper", attacks: [sniperAttack], magazineSize: 10,
                            reloadTime: 0, category: "primary", type: "Rifle")
        let plain = Weapon(name: "Plain", attacks: [plainAttack], magazineSize: 10,
                           reloadTime: 0, category: "primary", type: "Rifle")

        let baseline = output(weapon: plain, options: Options(window: 7))
        let defaultSniper = output(weapon: sniper, options: Options(window: 7))
        let override = output(weapon: sniper,
                              options: Options(window: 7, sniperComboMultiplier: 3))

        XCTAssertEqual(defaultSniper.targetDirectDamage, baseline.targetDirectDamage * 1.5, accuracy: 1e-9)
        XCTAssertEqual(defaultSniper.targetDotDamage, baseline.targetDotDamage * 1.5, accuracy: 1e-9)
        XCTAssertEqual(override.targetDirectDamage, baseline.targetDirectDamage * 3, accuracy: 1e-9)
        XCTAssertEqual(override.targetDotDamage, baseline.targetDotDamage * 3, accuracy: 1e-9)
    }

    func testComboOptionCodingPreservesOffState() throws {
        let off = try JSONDecoder().decode(Options.self, from: Data("{}".utf8))
        XCTAssertNil(off.abilityComboMultiplier)
        XCTAssertNil(off.sniperComboMultiplier)

        let encoded = try JSONEncoder().encode(Options(abilityComboMultiplier: 12,
                                                        sniperComboMultiplier: 3))
        let decoded = try JSONDecoder().decode(Options.self, from: encoded)
        XCTAssertEqual(try XCTUnwrap(decoded.abilityComboMultiplier), 12, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(decoded.sniperComboMultiplier), 3, accuracy: 1e-12)
    }
}
