import XCTest
@testable import DamageKit

final class AbilityStrengthWeaponTests: XCTestCase {
    private let neutral = FactionProfile.resolve(rawFaction: "Neutral")

    private func weapon() -> Weapon {
        Weapon(name: "Strength-source test",
               attacks: [Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                                statusChance: 0, damage: [.impact: 100])],
               magazineSize: 10, reloadTime: 1, category: "secondary")
    }

    private func resolve(_ weapon: Weapon, strength: Double = 1,
                         allConditions: Bool = true) -> ResolvedAttack {
        BuildResolver(weapon: weapon, build: Build(),
                      options: Options(allModConditionsMet: allConditions,
                                       abilityStrength: strength),
                      faction: neutral).resolveAll()[0]
    }

    func testWeaponDecodesWebsiteStrengthAndAdditionalBuffFields() throws {
        let json = #"""
        {
          "name": "Source fields",
          "strengthType": "simple",
          "additionalBuff": 2.5,
          "attacks": [{
            "name": "Hit", "speed": 1, "crit_chance": 0,
            "crit_mult": 1, "status_chance": 0, "damage": {"impact": 100}
          }]
        }
        """#
        let decoded = try JSONDecoder().decode(Weapon.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.strengthType, "simple")
        XCTAssertEqual(decoded.additionalBuff ?? -1, 2.5, accuracy: 1e-12)
    }

    func testSimpleStrengthIsFinalDirectAndStatusMultiplier() {
        var source = weapon()
        source.strengthType = "simple"
        let resolved = resolve(source, strength: 1.5)

        XCTAssertEqual(resolved.directDamageMultiplier, 1.5, accuracy: 1e-12)
        XCTAssertEqual(resolved.weaponVectorDamageMultiplier, 1, accuracy: 1e-12)
        XCTAssertEqual(resolved.statusDamageMultiplier, 1.5, accuracy: 1e-12)
    }

    func testCyteStrengthOnlyChangesTheWeaponVector() {
        var source = weapon()
        source.strengthType = "cyte"
        let resolved = resolve(source, strength: 1.5)

        XCTAssertEqual(resolved.directDamageMultiplier, 1, accuracy: 1e-12)
        XCTAssertEqual(resolved.weaponVectorDamageMultiplier, 1.875, accuracy: 1e-12)
        XCTAssertEqual(resolved.statusDamageMultiplier, 1, accuracy: 1e-12)
    }

    func testMesaStrengthEntersTheBaseDamagePoolBeforeQuantization() {
        var source = weapon()
        source.strengthType = "mesa"
        let resolved = resolve(source, strength: 1.5)

        // The website adds 1.5 × Strength to Mesa's base-damage bonus. At
        // 150% that is +225%, so a 100 base component becomes 325 before the
        // direct-damage grid is applied.
        XCTAssertEqual(resolved.damage[.impact] ?? 0, 325, accuracy: 1e-9)
    }

    func testAdditionalBuffIsSourceDataNotAnInputLayerFormula() {
        var source = weapon()
        source.additionalBuff = 2.5
        let resolved = resolve(source)

        XCTAssertEqual(resolved.directDamageMultiplier, 2.5, accuracy: 1e-12)
        XCTAssertEqual(resolved.statusDamageMultiplier, 2.5, accuracy: 1e-12)
    }

    func testStrengthScaledUniqueActionHonorsTheGlobalConditionSwitch() {
        var source = weapon()
        source.unique = [
            "WITH_COND": .object(["flat_change_dmg_by_strength": .number(250)])
        ]

        let disabled = resolve(source, strength: 1.5, allConditions: false)
        let enabled = resolve(source, strength: 1.5, allConditions: true)

        XCTAssertEqual(disabled.damage[.impact] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(enabled.damage[.impact] ?? 0, 475, accuracy: 1e-9)
    }
}
