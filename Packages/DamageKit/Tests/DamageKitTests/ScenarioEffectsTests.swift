import XCTest
@testable import DamageKit

final class ScenarioEffectsTests: XCTestCase {
    private let neutral = FactionProfile.neutral

    func testScenarioEffectInputContractsAreCoreOwnedAndCoverEveryIdentifier() {
        XCTAssertEqual(ScenarioEffectID.allCases.count, 7)
        XCTAssertEqual(ScenarioEffectID.roar.defaultDisplayValue, 100, accuracy: 1e-12)
        XCTAssertEqual(ScenarioEffectID.eclipse.defaultDisplayValue, 100, accuracy: 1e-12)
        XCTAssertEqual(ScenarioEffectID.nourish.defaultDisplayValue, 50, accuracy: 1e-12)
        XCTAssertEqual(ScenarioEffectID.xata.defaultDisplayValue, 50, accuracy: 1e-12)
        XCTAssertEqual(ScenarioEffectID.toxicLash.defaultDisplayValue, 30, accuracy: 1e-12)
        XCTAssertEqual(ScenarioEffectID.flatCriticalChance.defaultDisplayValue, 50, accuracy: 1e-12)
        XCTAssertFalse(ScenarioEffectID.madurai.acceptsDisplayPercentage)
        XCTAssertEqual(ScenarioEffectID.madurai.inputValue(fromDisplayValue: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(ScenarioEffectID.madurai.inputValue(fromDisplayValue: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(ScenarioEffectID.eclipse.inputValue(fromDisplayValue: 125), 1.25, accuracy: 1e-12)
    }

    func testVerifiedNamedScenarioEffectsUseTheirResolvedFormulaPools() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 20, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = Weapon(name: "Scenario weapon", attacks: [attack], magazineSize: 10,
                            reloadTime: 1, category: "primary")
        let options = Options(scenarioEffects: ScenarioEffects(values: [
            .roar: 0.3,
            .eclipse: 1.0,
            .nourish: 0.45,
            .flatCriticalChance: 0.5,
        ]))
        let resolved = BuildResolver(weapon: weapon, build: Build(), options: options,
                                     faction: neutral).resolveAll()[0]

        XCTAssertEqual(resolved.critChance, 0.7, accuracy: 1e-12)
        XCTAssertEqual(resolved.factionBonus, 0.3, accuracy: 1e-12)
        XCTAssertEqual(resolved.directDamageMultiplier, 2, accuracy: 1e-12)
        XCTAssertEqual(resolved.statusDamageMultiplier, 2, accuracy: 1e-12)
        XCTAssertEqual(resolved.damage[.impact] ?? 0, 100, accuracy: 1e-9)
        // Nourish's Viral is an external instance. It does not combine with
        // the existing Impact component and is quantized on the same direct grid.
        XCTAssertEqual(resolved.damage[.viral] ?? 0, 43.75, accuracy: 1e-9)
    }

    func testEclipseMultipliesDirectDamageAtTheFinalOutgoingStage() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = Weapon(name: "Scenario weapon", attacks: [attack], magazineSize: 10,
                            reloadTime: 0, category: "primary")
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9, armor: 0)
        let output = Calculator().evaluate(DamageInput(
            weapon: weapon,
            enemy: enemy,
            level: 1,
            build: Build(),
            options: Options(window: 1, scenarioEffects: ScenarioEffects(values: [.eclipse: 1]))
        ))

        XCTAssertEqual(output.attacks[0].targetDirectDamage, 200, accuracy: 1e-9)
        XCTAssertEqual(output.attacks[0].targetDps, 200, accuracy: 1e-9)
    }

    func testMaduraiOnlyMultipliesEligibleDirectDamage() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9, armor: 0)
        let eligible = Weapon(name: "Ordinary", attacks: [attack], magazineSize: 10,
                              reloadTime: 0, category: "primary")
        var power = Weapon(name: "Power", attacks: [attack], magazineSize: 10,
                           reloadTime: 0, category: "primary")
        power.compTags = ["POWER_WEAPON"]
        let options = Options(window: 1, scenarioEffects: ScenarioEffects(values: [.madurai: 1]))

        let eligibleOut = Calculator().evaluate(DamageInput(weapon: eligible, enemy: enemy,
                                                             level: 1, build: Build(), options: options))
        let powerOut = Calculator().evaluate(DamageInput(weapon: power, enemy: enemy,
                                                          level: 1, build: Build(), options: options))
        XCTAssertEqual(eligibleOut.attacks[0].targetDirectDamage, 130, accuracy: 1e-9)
        XCTAssertEqual(powerOut.attacks[0].targetDirectDamage, 100, accuracy: 1e-9)
    }

    func testScenarioEffectsDecodeCanonicalIDsAndLegacyPayloads() throws {
        let canonical = #"{"scenarioEffects":{"values":{"roar":0.3,"eclipse":1,"nourish":0.45,"flatCriticalChance":0.5,"madurai":1}}}"#
        let canonicalOptions = try JSONDecoder().decode(Options.self, from: Data(canonical.utf8))

        XCTAssertEqual(canonicalOptions.scenarioEffects.value(for: .roar), 0.3, accuracy: 1e-12)
        XCTAssertEqual(canonicalOptions.scenarioEffects.value(for: .eclipse), 1, accuracy: 1e-12)
        XCTAssertEqual(canonicalOptions.scenarioEffects.value(for: .madurai), 1, accuracy: 1e-12)
        XCTAssertEqual(canonicalOptions.scenarioEffects.value(for: .nourish), 0.45, accuracy: 1e-12)
        XCTAssertEqual(canonicalOptions.scenarioEffects.value(for: .flatCriticalChance), 0.5, accuracy: 1e-12)

        // Existing build JSON remains readable while the native UI and parity
        // cases use the ID-to-value form above.
        let legacy = #"{"scenarioEffects":{"roarFactionBonus":0.3,"nourishViralBonus":0.45,"flatCriticalChance":0.5}}"#
        let legacyOptions = try JSONDecoder().decode(Options.self, from: Data(legacy.utf8))

        XCTAssertEqual(legacyOptions.scenarioEffects.value(for: .roar), 0.3, accuracy: 1e-12)
        XCTAssertEqual(legacyOptions.scenarioEffects.value(for: .nourish), 0.45, accuracy: 1e-12)
        XCTAssertEqual(legacyOptions.scenarioEffects.value(for: .flatCriticalChance), 0.5, accuracy: 1e-12)

        let encoded = try JSONEncoder().encode(canonicalOptions.scenarioEffects)
        let encodedObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertNotNil(encodedObject?["values"])
    }
}
