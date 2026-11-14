import XCTest
@testable import DamageKit

final class EnvironmentEffectsTests: XCTestCase {
    private let neutral = FactionProfile.resolve(rawFaction: "Neutral")

    private func secondaryWeapon(_ attack: Attack, reload: Double = 2) -> Weapon {
        Weapon(name: "External source test", attacks: [attack], magazineSize: 12,
               reloadTime: reload, category: "secondary")
    }

    func testNamedWarframeModUsesExactLibraryActionAndStrength() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let environment = EnvironmentEffects(
            warframeMods: [
                ExternalEffectSource(name: "Saryn Venom Dose", mod: "Venom Dose",
                                     abilityStrength: 1.5)
            ])
        let resolved = BuildResolver(weapon: secondaryWeapon(attack), build: Build(),
                                     options: Options(environment: environment), faction: neutral)
            .resolveAll()[0]

        // Venom Dose 的数据动作是 addCorrosiveS=1，按 150% strength 变成
        // Modded Base Damage 的 150% Corrosive；它不会和武器槽位元素重新组合。
        XCTAssertEqual(resolved.damage[.impact] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(resolved.damage[.corrosive] ?? 0, 150, accuracy: 1e-9)
    }

    func testWebsiteGlobalAbilityStrengthDrivesExternalDataWhenNoSourceOverrideExists() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let environment = EnvironmentEffects(
            warframeMods: [ExternalEffectSource(name: "Saryn Venom Dose", mod: "Venom Dose")]
        )
        let resolved = BuildResolver(
            weapon: secondaryWeapon(attack), build: Build(),
            options: Options(abilityStrength: 1.5, environment: environment), faction: neutral
        ).resolveAll()[0]

        // The external row intentionally has no strength of its own. This
        // locks the website contract: its one global Strength field scales the
        // data action selected in that row.
        XCTAssertEqual(resolved.damage[.impact] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(resolved.damage[.corrosive] ?? 0, 150, accuracy: 1e-9)
    }

    func testExplicitSourceStrengthOverrideRemainsOptInForNonWebsiteAPICallers() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let environment = EnvironmentEffects(
            warframeMods: [
                ExternalEffectSource(name: "Saryn Venom Dose", mod: "Venom Dose",
                                     abilityStrength: 1.25)
            ]
        )
        let resolved = BuildResolver(
            weapon: secondaryWeapon(attack), build: Build(),
            options: Options(abilityStrength: 1.5, environment: environment), faction: neutral
        ).resolveAll()[0]

        XCTAssertEqual(resolved.damage[.corrosive] ?? 0, 125, accuracy: 1e-9)
    }

    func testExternalAugmentRankScaleDoesNotPromoteLowerRankToMax() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let environment = EnvironmentEffects(
            warframeMods: [
                // Venom Dose rank 0 is +50%, while DamageKit's compact
                // action table stores its rank-3 coefficient as 1.0.
                ExternalEffectSource(name: "Saryn Prime A · Venom Dose", mod: "Venom Dose",
                                     abilityStrength: 1.5, effectScale: 0.5)
            ]
        )
        let resolved = BuildResolver(weapon: secondaryWeapon(attack), build: Build(),
                                     options: Options(environment: environment), faction: neutral)
            .resolveAll()[0]

        XCTAssertEqual(resolved.damage[.impact] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(resolved.damage[.corrosive] ?? 0, 75, accuracy: 1e-9)
    }

    func testShockTrooperKeepsDirectAndDotElectricityRulesSeparate() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.impact: 100])
        let environment = EnvironmentEffects(
            warframeMods: [
                ExternalEffectSource(name: "Volt Shock Trooper", mod: "Shock Trooper",
                                     abilityStrength: 1.25)
            ])
        let resolved = BuildResolver(weapon: secondaryWeapon(attack), build: Build(),
                                     options: Options(environment: environment), faction: neutral)
            .resolveAll()[0]

        XCTAssertEqual(resolved.damage[.electricity] ?? 0, 125, accuracy: 1e-9)
        XCTAssertEqual(resolved.dotElementBonuses[.electricity] ?? 0, 1.25, accuracy: 1e-9)
    }

    func testNamedCompanionConditionRequiresExplicitCurrentValue() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        let inactive = BuildResolver(
            weapon: secondaryWeapon(attack), build: Build(),
            options: Options(environment: EnvironmentEffects(companionMods: [
                ExternalEffectSource(name: "Tenacious Bond", mod: "Tenacious Bond")
            ])), faction: neutral
        ).resolveAll()[0]
        let active = BuildResolver(
            weapon: secondaryWeapon(attack), build: Build(),
            options: Options(environment: EnvironmentEffects(companionMods: [
                ExternalEffectSource(name: "Tenacious Bond", mod: "Tenacious Bond",
                                     conditionValue: 1)
            ])), faction: neutral
        ).resolveAll()[0]

        let baseCrit = Rules.quantizeBaseCritDamage(2)
        XCTAssertEqual(inactive.critMultiplier, baseCrit, accuracy: 1e-9)
        XCTAssertEqual(active.critMultiplier, baseCrit + 1.2, accuracy: 1e-9)
        XCTAssertFalse(active.notes.contains { $0.contains("crit_mult_add") })
    }

    func testManualEnvironmentBuffDoesNotNeedARecognizedName() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 10, critMultiplier: 2,
                            statusChance: 10, damage: [.impact: 100])
        let buff = ExternalWeaponBuff(damageBonus: 0.5, critChanceBonus: 1,
                                      critDamageBonus: 0.5, multishotBonus: 1,
                                      fireRateBonus: 0.5, reloadSpeedBonus: 1,
                                      statusChanceBonus: 1, statusDurationBonus: 0.5,
                                      statusDamageBonus: 0.9, factionBonus: 0.3,
                                      elements: ["toxin": 0.25])
        let environment = EnvironmentEffects(buffs: [
            ExternalEffectSource(name: "Arbitrary test aura", buff: buff)
        ])
        let resolved = BuildResolver(weapon: secondaryWeapon(attack), build: Build(),
                                     options: Options(environment: environment), faction: neutral)
            .resolveAll()[0]

        XCTAssertEqual(resolved.damage[.impact] ?? 0, 150, accuracy: 1e-9)
        // 25 raw Toxin lands on the Modded-Base/32 direct-damage grid (150/32),
        // so it quantizes to five grid steps rather than remaining 25 exactly.
        XCTAssertEqual(resolved.damage[.toxin] ?? 0, 23.4375, accuracy: 1e-9)
        XCTAssertEqual(resolved.critChance, 0.2, accuracy: 1e-9)
        XCTAssertEqual(resolved.critMultiplier, Rules.quantizeBaseCritDamage(2) + 0.5,
                       accuracy: 1e-9)
        XCTAssertEqual(resolved.multishot, 2, accuracy: 1e-9)
        XCTAssertEqual(resolved.fireRate, 1.5, accuracy: 1e-9)
        XCTAssertEqual(resolved.reload, 1, accuracy: 1e-9)
        XCTAssertEqual(resolved.statusChance, 0.2, accuracy: 1e-9)
        XCTAssertEqual(resolved.statusDuration, 9, accuracy: 1e-9)
        XCTAssertEqual(resolved.statusDamageBonus, 0.9, accuracy: 1e-9)
        XCTAssertEqual(resolved.factionBonus, 0.3, accuracy: 1e-9)
    }

    func testInitialStatusHasFiniteRemainingDuration() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = secondaryWeapon(attack)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9)
        let environment = EnvironmentEffects(initialStatuses: [
            InitialStatusEffect(type: "viral", stacks: 10, remainingDuration: 0.5)
        ])
        let result = Calculator().evaluate(DamageInput(weapon: weapon, enemy: enemy, level: 1,
                                                        options: Options(window: 1.1,
                                                                         environment: environment)))
        let health = result.attacks[0].layers.first { $0.layer == .health }

        // t=0 still has ten Viral stacks (4.25x = 425 damage); t=1 has
        // expired (100 damage). The input is not an infinite hidden target
        // modifier.
        XCTAssertEqual(health?.damage ?? 0, 525, accuracy: 1e-9)
    }

    func testInitialStatusJSONUsesFiniteDefaults() throws {
        let json = #"{"initialStatuses":[{"type":"viral","stacks":3}],"initialStatusStacks":{"corrosive":2}}"#
        let environment = try JSONDecoder().decode(EnvironmentEffects.self, from: Data(json.utf8))

        XCTAssertEqual(environment.initialStatuses.count, 1)
        XCTAssertEqual(environment.initialStatuses[0].remainingDuration,
                       Rules.statusBaseDuration, accuracy: 1e-9)
        XCTAssertEqual(environment.initialStatuses[0].heatArmorElapsed, 0, accuracy: 1e-9)
        XCTAssertEqual(environment.initialStatusStackCount(named: "viral"), 3, accuracy: 1e-9)
        XCTAssertEqual(environment.initialStatusStackCount(named: "corrosive"), 2, accuracy: 1e-9)
    }

    func testInitialHeatUsesProvidedArmorRampAgeWithoutInventingADot() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = secondaryWeapon(attack)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1,
                          health: 1e9, armor: 2700)
        let baseline = Calculator().evaluate(DamageInput(weapon: weapon, enemy: enemy, level: 1,
                                                          options: Options(window: 0.5)))
        let heat = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            options: Options(window: 0.5, environment: EnvironmentEffects(initialStatuses: [
                InitialStatusEffect(type: "heat", stacks: 1, remainingDuration: 6,
                                    heatArmorElapsed: 2)
            ]))
        ))
        let baselineDamage = baseline.attacks[0].layers.first { $0.layer == .health }?.damage ?? 0
        let heatedDamage = heat.attacks[0].layers.first { $0.layer == .health }?.damage ?? 0

        XCTAssertGreaterThan(heatedDamage, baselineDamage)
        XCTAssertEqual(heat.attacks[0].dotDamage, 0, accuracy: 1e-9)
    }
}
