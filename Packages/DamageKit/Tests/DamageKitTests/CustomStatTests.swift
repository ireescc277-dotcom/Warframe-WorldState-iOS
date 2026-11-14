import XCTest
@testable import DamageKit

final class CustomStatTests: XCTestCase {
    private let neutral = FactionProfile.neutral

    private func weapon() -> Weapon {
        Weapon(
            name: "Custom stat test",
            attacks: [
                Attack(name: "Hit", speed: 2, critChance: 20, critMultiplier: 2,
                       statusChance: 20, damage: [.impact: 100]),
            ],
            magazineSize: 10,
            reloadTime: 2,
            category: "primary"
        )
    }

    func testSupportedCustomStatsResolveInTheSamePoolsAsSiteInputs() {
        let options = Options(
            allModConditionsMet: true,
            forceMultiplicativePerStatusDamage: true,
            customStats: [
                CustomStatKey.base.rawValue: 0.5,
                CustomStatKey.flatChangeDamage.rawValue: 10,
                CustomStatKey.basePerStatus.rawValue: 0.4,
                CustomStatKey.critChance.rawValue: 0.5,
                CustomStatKey.flatCritChance.rawValue: 0.1,
                CustomStatKey.multiplicativeCritChance.rawValue: 0.5,
                CustomStatKey.critMultiplier.rawValue: 0.5,
                CustomStatKey.flatCritMultiplier.rawValue: 0.5,
                CustomStatKey.finalCritMultiplier.rawValue: 0.2,
                CustomStatKey.statusChance.rawValue: 0.5,
                CustomStatKey.absoluteStatusChance.rawValue: 2,
                CustomStatKey.statusChanceMultiplier.rawValue: 0.25,
                CustomStatKey.statusDamage.rawValue: 0.8,
                CustomStatKey.vulnerableStatusDamage.rawValue: 0.25,
                CustomStatKey.damageVulnerability.rawValue: 0.5,
                CustomStatKey.speed.rawValue: 0.5,
                CustomStatKey.multishot.rawValue: 0.5,
                CustomStatKey.magazineSize.rawValue: 0.5,
                CustomStatKey.reloadTime.rawValue: 0.5,
                CustomStatKey.headshotDamage.rawValue: 0.2,
                CustomStatKey.weakPointDamage.rawValue: 0.5,
            ],
            headshot: true
        )
        let resolved = BuildResolver(weapon: weapon(), build: Build(), options: options,
                                     faction: neutral).resolveAll()[0]

        // +10 flat base damage, then +50% base damage.
        XCTAssertEqual(resolved.damage[.impact] ?? 0, 165, accuracy: 1e-9)
        XCTAssertEqual(resolved.dotBaseDamage, 165, accuracy: 1e-9)
        // ((20% × 1.5) + 10 pp) × 1.5.
        XCTAssertEqual(resolved.critChance, 0.6, accuracy: 1e-9)
        // ((quantized base crit 2 × 1.5) + 0.5) × 1.2.
        XCTAssertEqual(resolved.critMultiplier,
                       (Rules.quantizeBaseCritDamage(2) * 1.5 + 0.5) * 1.2,
                       accuracy: 1e-9)
        // ((20% × 1.5) + 2 pp) × 1.25.
        XCTAssertEqual(resolved.statusChance, 0.4, accuracy: 1e-9)
        XCTAssertEqual(resolved.statusDamageBonus, 0.8, accuracy: 1e-9)
        XCTAssertEqual(resolved.damageVulnerabilityMultiplier, 1.5, accuracy: 1e-9)
        XCTAssertEqual(resolved.statusDamageVulnerabilityMultiplier, 1.25, accuracy: 1e-9)
        XCTAssertEqual(resolved.fireRate, 3, accuracy: 1e-9)
        XCTAssertEqual(resolved.multishot, 1.5, accuracy: 1e-9)
        XCTAssertEqual(resolved.magazine, 15, accuracy: 1e-9)
        XCTAssertEqual(resolved.reload, 2 / 1.5, accuracy: 1e-9)
        // (default headshot 3x + 0.5) × (1 + 0.2).
        XCTAssertEqual(resolved.headshotMultiplier, 4.2, accuracy: 1e-9)
        XCTAssertEqual(resolved.directDamagePerStatusType, 0.4, accuracy: 1e-9)
        XCTAssertTrue(resolved.conditionalDamageIsMultiplicative)
    }

    func testCustomPerStatusIsDisabledWithTheSiteGlobalConditionSwitch() {
        let options = Options(allModConditionsMet: false,
                              customStats: [CustomStatKey.basePerStatus.rawValue: 0.4])
        let resolved = BuildResolver(weapon: weapon(), build: Build(), options: options,
                                     faction: neutral).resolveAll()[0]

        XCTAssertEqual(resolved.directDamagePerStatusType, 0, accuracy: 1e-12)
    }

    func testHeatAddCreatesSeparateDirectHeatAndHeatStatusBonus() {
        let resolved = BuildResolver(
            weapon: weapon(), build: Build(),
            options: Options(customStats: [CustomStatKey.heatAdd.rawValue: 1]),
            faction: neutral
        ).resolveAll()[0]

        XCTAssertEqual(resolved.damage[.impact] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(resolved.damage[.heat] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(resolved.dotBaseDamage, 100, accuracy: 1e-9)
        XCTAssertEqual(resolved.dotElementBonuses[.heat] ?? 0, 1, accuracy: 1e-9)
        XCTAssertFalse(resolved.notes.contains { $0.contains(CustomStatKey.heatAdd.rawValue) })
    }

    func testHeatInheritReplacesOnlyHeatDotElementPool() {
        let resolved = BuildResolver(
            weapon: weapon(), build: Build(),
            options: Options(customStats: [
                CustomStatKey.heatAdd.rawValue: 0.3,
                CustomStatKey.heatInherit.rawValue: 1.5,
            ]),
            faction: neutral
        ).resolveAll()[0]

        // The independent 30 Heat component still enters the normal direct
        // damage quantization grid (100 / 32 = 3.125), so it rounds to 31.25.
        XCTAssertEqual(resolved.damage[.heat] ?? 0, 31.25, accuracy: 1e-9)
        XCTAssertEqual(resolved.dotElementBonuses[.heat] ?? 0, 1.5, accuracy: 1e-9)
        XCTAssertFalse(resolved.notes.contains { $0.contains(CustomStatKey.heatInherit.rawValue) })
    }

    func testUnknownCustomInputsAreReported() {
        let options = Options(customStats: ["not_a_site_stat": 42])
        let resolved = BuildResolver(weapon: weapon(), build: Build(), options: options,
                                     faction: neutral).resolveAll()[0]

        XCTAssertTrue(resolved.notes.contains { $0.contains("not_a_site_stat") })
    }

    func testDamageAndStatusVulnerabilitiesUseSeparateMultiplicativePools() {
        let attack = Attack(name: "Heat", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.heat: 100])
        let weapon = Weapon(name: "Vulnerability test", attacks: [attack], magazineSize: 100,
                            reloadTime: 0, category: "primary")
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e12)
        let base = Calculator().evaluate(DamageInput(weapon: weapon, enemy: enemy, level: 1,
                                                     options: Options(window: 3))).attacks[0]
        let custom = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            options: Options(window: 3, customStats: [
                CustomStatKey.damageVulnerability.rawValue: 0.5,
                CustomStatKey.vulnerableStatusDamage.rawValue: 0.25,
            ])
        )).attacks[0]

        XCTAssertEqual(custom.targetDirectDamage / base.targetDirectDamage, 1.5, accuracy: 1e-9)
        XCTAssertEqual(custom.targetDotDamage / base.targetDotDamage, 1.875, accuracy: 1e-9)
    }

    func testCustomStatInputUnitsMatchWebsiteMetadata() {
        XCTAssertTrue(CustomStatKey.base.usesPercentInput)
        XCTAssertTrue(CustomStatKey.weakPointDamage.usesPercentInput)
        XCTAssertFalse(CustomStatKey.absoluteStatusChance.usesPercentInput)
        XCTAssertFalse(CustomStatKey.multishot.usesPercentInput)
        XCTAssertFalse(CustomStatKey.finalCritMultiplier.usesPercentInput)
        XCTAssertEqual(CustomStatKey.base.inputValue(fromDisplayValue: 125), 1.25, accuracy: 1e-12)
        XCTAssertEqual(CustomStatKey.flatCritChance.inputValue(fromDisplayValue: -35), -0.35,
                       accuracy: 1e-12)
        XCTAssertEqual(CustomStatKey.absoluteStatusChance.inputValue(fromDisplayValue: -21), -21,
                       accuracy: 1e-12)
        XCTAssertEqual(CustomStatKey.multishot.inputValue(fromDisplayValue: 0.2), 0.2,
                       accuracy: 1e-12)
    }
}
