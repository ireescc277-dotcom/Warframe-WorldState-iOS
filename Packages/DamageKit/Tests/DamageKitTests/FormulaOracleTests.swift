import XCTest
@testable import DamageKit

/// 这些例子来自可手算的已知机制，而不是由当前实现生成的 golden 文件。
final class FormulaOracleTests: XCTestCase {

    private func run(_ weapon: Weapon, _ enemy: Enemy, options: Options) -> Result {
        Calculator().evaluate(DamageInput(weapon: weapon, enemy: enemy, level: 1,
                                          options: options))
    }

    private func layerDamage(_ result: Result, attack: Int = 0, layer: Layer) -> Double {
        result.attacks[attack].layers.first(where: { $0.layer == layer })?.damage ?? 0
    }

    private func dotDamage(_ result: Result, attack: Int = 0) -> Double {
        result.attacks[attack].dotDamage
    }

    func testOrdinaryHitDoesNotDamageHealthWhileShieldRemains() {
        let attack = Attack(name: "Impact", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        let enemy = Enemy(name: "Shielded", faction: "Neutral", health: 1_000, shield: 1_000)
        let result = run(weapon, enemy, options: Options(window: 0.5))

        XCTAssertEqual(layerDamage(result, layer: .shield), 100, accuracy: 1e-9)
        XCTAssertEqual(layerDamage(result, layer: .health), 0, accuracy: 1e-9)
    }

    func testEnemyShieldGateUsesFivePercentUnlessWeakPointBypassesIt() {
        let attack = Attack(name: "Impact", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 300])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        let enemy = Enemy(name: "Shielded", faction: "Neutral", health: 1_000, shield: 100)
        let normal = run(weapon, enemy, options: Options(window: 0.5))
        let weakPoint = run(weapon, enemy, options: Options(window: 0.5, weakPoint: true))

        XCTAssertEqual(layerDamage(normal, layer: .shield), 100, accuracy: 1e-9)
        XCTAssertEqual(layerDamage(normal, layer: .health), 10, accuracy: 1e-9)
        XCTAssertEqual(layerDamage(weakPoint, layer: .health), 200, accuracy: 1e-9)
    }

    func testImmediateStatusDamageIsASeparateShieldGateInstance() {
        // Electricity ticks at t=0.  It is an additional status-damage instance,
        // so it is not reduced to 5% merely because the direct hit broke shields.
        let attack = Attack(name: "Gate + electric", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 300], forceProcs: ["electricity"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        let enemy = Enemy(name: "Shielded", faction: "Neutral", health: 1_000, shield: 100)
        let result = run(weapon, enemy, options: Options(window: 0.5))

        // Direct overflow: (300 - 100) × 5% = 10.  Electricity has its own
        // exact `(seed + 1)` tick group: (300 + 1) × 50% = 150.5.
        XCTAssertEqual(layerDamage(result, layer: .health), 160.5, accuracy: 1e-6)
    }

    func testEximusGetsItsKnownBaseOverguardAtBaseLevel() {
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 100)
        let profile = EnemyProfile(enemy: enemy, level: 1, options: Options(eximus: true))

        XCTAssertEqual(profile.overguard, 12, accuracy: 1e-12)
    }

    func testElementResistanceValueIsReductionNotRemainingDamageMultiplier() {
        var enemy = Enemy(name: "E", faction: "Neutral", health: 100)
        enemy.elemRes = ["heat": 0.75]
        let profile = EnemyProfile(enemy: enemy, level: 1, options: Options())

        XCTAssertEqual(profile.elementalResistance(.heat), 0.25, accuracy: 1e-12)
        XCTAssertEqual(profile.elementalResistance(.impact), 1, accuracy: 1e-12)
    }

    func testBurstDoesNotCreateRoundsPastMagazineCapacity() {
        let attack = Attack(name: "Burst", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1], burstCount: 3, burstDelay: 0.1)
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 2, reloadTime: 2)
        let options = Options(window: 1)
        let resolved = BuildResolver(weapon: weapon, build: Build(), options: options,
                                     faction: .neutral).resolve(attack: attack)
        let profile = EnemyProfile(enemy: Enemy(name: "E", faction: "Neutral", health: 100),
                                   level: 1, options: options)
        let schedule = WeaponSimulator(segments: [resolved], enemy: profile, options: options)
            .shotSchedule(for: resolved)

        XCTAssertEqual(schedule.count, 2)
        XCTAssertEqual(schedule[0].time, 0, accuracy: 1e-12)
        XCTAssertEqual(schedule[1].time, 0.1, accuracy: 1e-12)
    }

    func testBowChargeScheduleUsesChargePlusReloadWithoutOrdinaryReloadDelay() {
        let attack = Attack(name: "Charged Shot", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1], chargeTime: 0.5)
        var weapon = Weapon(name: "Bow", attacks: [attack], magazineSize: 1, reloadTime: 0.7)
        weapon.categories = ["primary-bow"]
        let options = Options(window: 3)
        let resolved = BuildResolver(weapon: weapon, build: Build(), options: options,
                                     faction: .neutral).resolve(attack: attack)
        let profile = EnemyProfile(enemy: Enemy(name: "E", faction: "Neutral", health: 100),
                                   level: 1, options: options)
        let schedule = WeaponSimulator(segments: [resolved], enemy: profile, options: options)
            .shotSchedule(for: resolved)

        XCTAssertEqual(resolved.chargeTime, 0.5, accuracy: 1e-12)
        XCTAssertEqual(schedule.count, 3)
        XCTAssertEqual(schedule[0].time, 0.5, accuracy: 1e-12)
        XCTAssertEqual(schedule[1].time, 1.7, accuracy: 1e-12)
        XCTAssertEqual(schedule[2].time, 2.9, accuracy: 1e-12)
    }

    func testKuvaBrammaBowCycleUsesOneChargeAndOneReloadPerArrow() {
        // Kuva Bramma's current data: charge time 0.40 s, reload time 0.60 s,
        // magazine size 1.  For a bow, each complete arrow cycle is exactly
        // charge + reload, not that cycle followed by a second reload delay.
        let attack = Attack(name: "Radial Attack", speed: 0.667, critChance: 35,
                            critMultiplier: 2.1, statusChance: 21,
                            damage: [.blast: 839], chargeTime: 0.4)
        var weapon = Weapon(name: "Kuva Bramma", attacks: [attack], magazineSize: 1,
                            reloadTime: 0.6)
        weapon.categories = ["primary-bow"]
        let options = Options(window: 20)
        let resolved = BuildResolver(weapon: weapon, build: Build(), options: options,
                                     faction: .neutral).resolve(attack: attack)
        let profile = EnemyProfile(enemy: Enemy(name: "E", faction: "Neutral", health: 100),
                                   level: 1, options: options)
        let schedule = WeaponSimulator(segments: [resolved], enemy: profile, options: options)
            .shotSchedule(for: resolved)

        XCTAssertEqual(schedule.count, 20)
        XCTAssertEqual(schedule[0].time, 0.4, accuracy: 1e-12)
        XCTAssertEqual(schedule[1].time, 1.4, accuracy: 1e-12)
        XCTAssertEqual(schedule[19].time, 19.4, accuracy: 1e-12)
    }

    func testOrdinaryChargeScheduleIncludesChargeAndShotDelay() {
        let attack = Attack(name: "Charged Shot", speed: 2, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1], chargeTime: 0.5)
        var weapon = Weapon(name: "Charge rifle", attacks: [attack], magazineSize: 2, reloadTime: 1)
        weapon.categories = ["primary-rifle"]
        let options = Options(window: 4)
        let resolved = BuildResolver(weapon: weapon, build: Build(), options: options,
                                     faction: .neutral).resolve(attack: attack)
        let profile = EnemyProfile(enemy: Enemy(name: "E", faction: "Neutral", health: 100),
                                   level: 1, options: options)
        let schedule = WeaponSimulator(segments: [resolved], enemy: profile, options: options)
            .shotSchedule(for: resolved)

        XCTAssertEqual(schedule.count, 3)
        XCTAssertEqual(schedule[0].time, 0.5, accuracy: 1e-12)
        XCTAssertEqual(schedule[1].time, 1.5, accuracy: 1e-12)
        XCTAssertEqual(schedule[2].time, 3.5, accuracy: 1e-12)
    }

    func testBowChargeTimeUsesItsExplicitDataSpeedBonus() {
        let attack = Attack(name: "Charged Shot", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1], chargeTime: 0.5)
        var weapon = Weapon(name: "Bow", attacks: [attack], magazineSize: 1, reloadTime: 0.7)
        weapon.categories = ["primary-bow"]
        let out = BuildResolver(weapon: weapon, build: Build(mods: ["Speed Trigger"]),
                                options: Options(), faction: .neutral).resolve(attack: attack)

        // Primary-bow's FOR_WEAPON entry is +120% charge speed, replacing
        // the generic +60% entry: 0.5 / (1 + 1.2).
        XCTAssertEqual(out.chargeTime, 0.5 / 2.2, accuracy: 1e-12)
    }

    func testSimultaneousCombinedSegmentsDoNotDependOnArrayOrder() {
        let viral = Attack(name: "Viral", speed: 1, critChance: 0, critMultiplier: 1,
                           statusChance: 100, damage: [.viral: 100])
        let impact = Attack(name: "Impact", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "E", faction: "Neutral", health: 10_000)
        let options = Options(window: 0.5, combinedAttackGroups: [[0, 1]])

        var viralFirst = Weapon(name: "Viral first", attacks: [viral, impact], magazineSize: 10)
        viralFirst.comb = [[0, 1]]
        var impactFirst = Weapon(name: "Impact first", attacks: [impact, viral], magazineSize: 10)
        impactFirst.comb = [[0, 1]]

        let a = run(viralFirst, enemy, options: options)
        let b = run(impactFirst, enemy, options: options)
        let totalA = layerDamage(a, attack: 0, layer: .health) + layerDamage(a, attack: 1, layer: .health)
        let totalB = layerDamage(b, attack: 0, layer: .health) + layerDamage(b, attack: 1, layer: .health)

        XCTAssertEqual(totalA, totalB, accuracy: 1e-9)
    }

    func testAttackSegmentsAreOnlyCombinedWhenTheUserSelectsThatWebsiteOption() {
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1])
        var weapon = Weapon(name: "Two segments", attacks: [attack, attack], magazineSize: 1)
        weapon.comb = [[0, 1]]

        XCTAssertEqual(Calculator.groups(weapon: weapon, count: 2, selected: []), [[0], [1]])
        XCTAssertEqual(Calculator.groups(weapon: weapon, count: 2, selected: [[1, 0]]), [[0, 1]])
        XCTAssertEqual(Calculator.groups(weapon: weapon, count: 2, selected: [[0, 2]]), [[0], [1]])
    }

    func testExplicitRivenSlotPreservesElementOrder() {
        let attack = Attack(name: "Element order", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "Rifle", attacks: [attack], magazineSize: 1)
        weapon.categories = ["primary-rifle"]
        let riven = Riven(elements: ["toxin": 0.9])

        let slotted = Build(
            slottedMods: [
                SlottedMod(slot: 0, name: "Hellfire"),
                SlottedMod(slot: 2, name: "Stormbringer")
            ],
            riven: riven,
            rivenSlot: 1
        )
        let slottedResult = BuildResolver(weapon: weapon, build: slotted,
                                          options: Options(), faction: .neutral)
            .resolve(attack: attack)
        XCTAssertNotNil(slottedResult.damage[.gas])
        XCTAssertNotNil(slottedResult.damage[.electricity])
        XCTAssertNil(slottedResult.damage[.radiation])

        let legacy = Build(mods: ["Hellfire", "Stormbringer"], riven: riven)
        let legacyResult = BuildResolver(weapon: weapon, build: legacy,
                                         options: Options(), faction: .neutral)
            .resolve(attack: attack)
        XCTAssertNotNil(legacyResult.damage[.radiation])
        XCTAssertNotNil(legacyResult.damage[.toxin])
        XCTAssertNil(legacyResult.damage[.gas])
    }

    func testGalvanizedShotSeesEarlierMultishotProjectileStatus() {
        // Two guaranteed projectiles from one trigger. The first Viral pellet
        // has no pre-existing status (100); it then establishes Viral before
        // pellet two, which receives Galvanized Shot's +120% (220).
        var attack = Attack(name: "Sequential pellets", speed: 0.01,
                            critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.viral: 100])
        attack.multishot = 2
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        weapon.categories = ["secondary"]
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9)
        let options = Options(window: 0.5,
                              conditionalModStacks: ["Galvanized Shot": 3])
        let result = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            build: Build(mods: ["Galvanized Shot"]), options: options))

        XCTAssertEqual(result.attacks[0].directDamage, 320, accuracy: 1e-6)
    }

    func testGalvanizedShotIsAdditiveWithBaseDamagePool() {
        // Anemic Agility puts the ordinary base-damage pool at 0.85x.  Once
        // projectile one has applied Viral, projectile two must be
        // 100 × (0.85 + 1.20) = 205, not 100 × 0.85 × 2.20 = 187.
        var attack = Attack(name: "Gun CO pool", speed: 0.01,
                            critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.viral: 100])
        attack.multishot = 2
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        weapon.categories = ["secondary"]
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9)
        let result = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            build: Build(mods: ["Anemic Agility", "Galvanized Shot"]),
            options: Options(window: 0.5,
                             conditionalModStacks: ["Galvanized Shot": 3])
        ))

        XCTAssertEqual(result.attacks[0].directDamage, 290, accuracy: 1e-6)
    }

    func testConditionalDamageUsesMultiplicativeExceptionWhenDataMarksIt() {
        // A data-marked exceptional attack keeps Gun CO outside the ordinary
        // base-damage pool.  This guards the `isCoMult` branch while ordinary
        // guns continue to use the additive test above.
        var attack = Attack(name: "Gun CO exception", speed: 0.01,
                            critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.viral: 100])
        attack.multishot = 2
        attack.conditionalDamageIsMultiplicative = true
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        weapon.categories = ["secondary"]
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9)
        let result = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            build: Build(mods: ["Anemic Agility", "Galvanized Shot"]),
            options: Options(window: 0.5,
                             conditionalModStacks: ["Galvanized Shot": 3])
        ))

        // 85 + (85 × 2.20) = 272.  The normal additive branch is 290.
        XCTAssertEqual(result.attacks[0].directDamage, 272, accuracy: 1e-6)
    }

    func testPerStatusDamageRulesAreDataDrivenForAllFourMods() {
        // All four raw Mods carry the same `base_per_status` field, but their
        // activation semantics differ.  These assertions deliberately inspect
        // the resolved value rather than a name-specific code path:
        // CO is always active; Aptitude/Savvy have two kill stacks; Shot has
        // three.  The values are declared in conditional-effects.json.
        let normal = Attack(name: "Direct", speed: 1, critChance: 0,
                            critMultiplier: 1, statusChance: 0, damage: [.impact: 100])
        let area = Attack(name: "Radius", speed: 1, critChance: 0,
                          critMultiplier: 1, statusChance: 0, damage: [.impact: 100],
                          shotType: "AoE")
        func value(mod: String, category: String, attack: Attack,
                   stacks: Double = 0) -> Double {
            var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
            weapon.categories = [category]
            return BuildResolver(weapon: weapon, build: Build(mods: [mod]),
                                 options: Options(conditionalModStacks: [mod: stacks]),
                                 faction: .neutral)
                .resolve(attack: attack)
                .directDamagePerStatusType
        }

        XCTAssertEqual(value(mod: "Condition Overload", category: "melee", attack: normal),
                       0.8, accuracy: 1e-12)
        XCTAssertEqual(value(mod: "Galvanized Aptitude", category: "primary-rifle",
                             attack: normal, stacks: 2), 0.8, accuracy: 1e-12)
        XCTAssertEqual(value(mod: "Galvanized Savvy", category: "primary-shotgun",
                             attack: normal, stacks: 2), 0.8, accuracy: 1e-12)
        XCTAssertEqual(value(mod: "Galvanized Shot", category: "secondary",
                             attack: normal, stacks: 1), 0.4, accuracy: 1e-12)
        XCTAssertEqual(value(mod: "Galvanized Shot", category: "secondary",
                             attack: normal, stacks: 3), 1.2, accuracy: 1e-12)

        // This is a rule-data exclusion, not a `Galvanized Shot` conditional in
        // BuildResolver: all CO-family effects exclude a radial AoE segment.
        XCTAssertEqual(value(mod: "Galvanized Shot", category: "secondary",
                             attack: area, stacks: 3), 0, accuracy: 1e-12)
    }

    func testConditionOverloadUsesPreexistingStatusWithoutAStackInput() {
        let attack = Attack(name: "Melee hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        weapon.categories = ["melee"]
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9)
        let primedTarget = EnvironmentEffects(initialStatuses: [
            InitialStatusEffect(type: "heat", stacks: 1, remainingDuration: 6)
        ])
        let result = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            build: Build(mods: ["Condition Overload"]),
            options: Options(window: 0.1, environment: primedTarget)
        ))

        XCTAssertEqual(result.attacks[0].directDamage, 180, accuracy: 1e-6)
    }

    func testManualStatusTypeCountOverridesOnlyCOQuery() {
        let attack = Attack(name: "Pistol hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        weapon.categories = ["secondary"]
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9)
        let result = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            build: Build(mods: ["Galvanized Shot"]),
            options: Options(window: 0.1,
                             conditionalModStacks: ["Galvanized Shot": 3],
                             manualStatusTypeCount: 5)
        ))

        // 100 × (1 + 5 × 120%) = 700.  There is no real Viral/Corrosive
        // status in this input, so this specifically proves an override of
        // CO's status-type query rather than a fabricated target-state effect.
        XCTAssertEqual(result.attacks[0].directDamage, 700, accuracy: 1e-6)
    }

    func testSlashDotUsesModdedBaseNotElementalOrPhysicalDamage() {
        // Wiki's exact tick-group formula adds one to the full-precision seed.
        // The forced proc keeps
        // this a formula test rather than a random-status test.
        let attack = Attack(name: "Slash oracle", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.puncture: 100], forceProcs: ["slash"])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        weapon.categories = ["primary-rifle"]
        let enemy = Enemy(name: "E", faction: "Grineer", health: 1e9)
        let result = run(weapon, enemy,
                         options: Options(window: 7))

        // The calculator needs the build to supply the three known modifiers.
        let built = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            build: Build(mods: ["Serration", "Bane of Grineer", "Rifle Elementalist"]),
            options: Options(window: 7)))
        XCTAssertEqual(result.attacks[0].procs["bleed"] ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(built.attacks[0].procs["bleed"] ?? 0, 1, accuracy: 1e-12)
        var perTick = Rules.f32(Rules.f32(100 * 2.65 * 1.3) + 1)
        perTick = Rules.f32(perTick * 0.35)
        perTick = Rules.f32(perTick * 1.9)
        perTick = Rules.f32(perTick * 1.3)
        XCTAssertEqual(dotDamage(built), 6 * perTick, accuracy: 1e-4)
    }

    func testToxinDotAppliesItsOwnElementBonusAndFactionDoubleDip() {
        // Same published vector as the Slash test, now with Infected Clip +90%.
        let attack = Attack(name: "Toxin oracle", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.puncture: 100], forceProcs: ["toxin"])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        weapon.categories = ["primary-rifle"]
        let enemy = Enemy(name: "E", faction: "Grineer", health: 1e9)
        let result = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            build: Build(mods: ["Serration", "Bane of Grineer", "Rifle Elementalist", "Infected Clip"]),
            options: Options(window: 7)))

        XCTAssertEqual(result.attacks[0].procs["poison"] ?? 0, 1, accuracy: 1e-12)
        var perTick = Rules.f32(Rules.f32(100 * 2.65 * 1.3) + 1)
        perTick = Rules.f32(perTick * 0.5)
        perTick = Rules.f32(perTick * 1.9) // Toxin element bonus
        perTick = Rules.f32(perTick * 1.9) // status-damage bonus
        perTick = Rules.f32(perTick * 1.3)
        XCTAssertEqual(dotDamage(result), 6 * perTick, accuracy: 1e-4)
    }

    func testDamagingStatusStillExistsWhileEnemyOverguardIsUp() {
        let attack = Attack(name: "Bleed through OG", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 10], forceProcs: ["slash"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9, overguard: 1_000)
        let result = run(weapon, enemy, options: Options(window: 1.5))

        XCTAssertEqual(result.attacks[0].procs["bleed"] ?? 0, 1, accuracy: 1e-12)
        XCTAssertGreaterThan(layerDamage(result, layer: .overguard), 10)
        XCTAssertEqual(layerDamage(result, layer: .health), 0, accuracy: 1e-12)
    }

    func testVoidGetsKnownOverguardMultiplier() {
        let attack = Attack(name: "Void", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.void: 100])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9, overguard: 1_000)
        let result = run(weapon, enemy, options: Options(window: 0.5))

        XCTAssertEqual(layerDamage(result, layer: .overguard), 150, accuracy: 1e-12)
    }

    func testHeatArmorStripUsesKnownStepsWithoutReprocAcceleration() {
        // Heat starts after the first hit.  At the next two 0.5s-spaced hits,
        // armor is stripped by exactly 15% then 30%; the second Heat proc must
        // refresh duration without skipping a stage.
        let attack = Attack(name: "Heat ramp", speed: 2, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100, .heat: 1],
                            forceProcs: ["heat"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9, armor: 2700)
        let result = run(weapon, enemy, options: Options(window: 1.1))
        let impact = result.attacks[0].layers.first(where: { $0.layer == .health })?.byType["impact"] ?? 0

        // Direct components are quantized on a 101 Modded Base (the 1 Heat
        // component rounds to zero; the 100 Impact component rounds to 101).
        let expected = 101 * (1 - Rules.enemyArmorDR(netArmor: 2700))
            + 101 * (1 - Rules.enemyArmorDR(netArmor: 2700 * 0.85))
            + 101 * (1 - Rules.enemyArmorDR(netArmor: 2700 * 0.70))
        XCTAssertEqual(impact, expected, accuracy: 1e-5)
    }

    func testHeatRefreshesOneConsolidatedTickGroup() {
        // A second Heat at t=5 refreshes the original group through t=11.  The
        // group has one +1 accumulator, not two independent timers.
        let attack = Attack(name: "Heat refresh", speed: 0.2, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100], forceProcs: ["heat"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9)
        let result = run(weapon, enemy, options: Options(window: 11.5))

        // t=1...5: one 100 seed; t=6...10: two seeds; the shot at t=10
        // then refreshes a three-seed group for its t=11 tick.
        let expected = 5 * 50.5 + 5 * 100.5 + 150.5
        XCTAssertEqual(dotDamage(result), expected, accuracy: 1e-4)
    }

    func testFiniteHeatCapReplacesTheOldestContribution() {
        let attack = Attack(name: "Heat cap", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100], forceProcs: ["heat"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100)
        var enemy = Enemy(name: "Capped", faction: "Neutral", health: 1e9)
        enemy.maxProcStacks = 1
        let result = run(weapon, enemy, options: Options(window: 2.5))

        // The t=1 reproc replaces rather than adds: t=1 and t=2 each remain
        // a one-seed 50.5 tick, not a 100.5 two-seed tick.
        XCTAssertEqual(dotDamage(result), 2 * 50.5, accuracy: 1e-4)
    }

    func testElectricitySamePulseUsesOneAccumulatorBonus() {
        // Both attack segments create Electricity on the same t=0 pulse.  The
        // published tick-group rule is `(100 + 100 + 1) × 50%`, not two
        // separate `(100 + 1) × 50%` events.
        let a = Attack(name: "Electric A", speed: 0.01, critChance: 0, critMultiplier: 1,
                       statusChance: 0, damage: [.impact: 100], forceProcs: ["electricity"])
        let b = Attack(name: "Electric B", speed: 0.01, critChance: 0, critMultiplier: 1,
                       statusChance: 0, damage: [.impact: 100], forceProcs: ["electricity"])
        var weapon = Weapon(name: "Pulse", attacks: [a, b], magazineSize: 10)
        weapon.comb = [[0, 1]]
        let result = run(weapon, Enemy(name: "E", faction: "Neutral", health: 1e9),
                         options: Options(window: 0.5, combinedAttackGroups: [[0, 1]]))

        XCTAssertEqual(result.attacks[0].procs["tesla"] ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(result.attacks[1].procs["tesla"] ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(dotDamage(result, attack: 0) + dotDamage(result, attack: 1),
                       100.5, accuracy: 1e-4)
    }

    func testGasSamePulseUsesOneAccumulatorBonusButKeepsPerInstanceTimers() {
        // Gas has distinct status instances, but a shared tick pulse: two
        // equal seeds therefore make `(100 + 100 + 1) × 50%`, not two 50.5s.
        let a = Attack(name: "Gas A", speed: 0.01, critChance: 0, critMultiplier: 1,
                       statusChance: 0, damage: [.impact: 100], forceProcs: ["gas"])
        let b = Attack(name: "Gas B", speed: 0.01, critChance: 0, critMultiplier: 1,
                       statusChance: 0, damage: [.impact: 100], forceProcs: ["gas"])
        var weapon = Weapon(name: "Gas pulse", attacks: [a, b], magazineSize: 10)
        weapon.comb = [[0, 1]]
        let result = run(weapon, Enemy(name: "E", faction: "Neutral", health: 1e9),
                         options: Options(window: 0.5, combinedAttackGroups: [[0, 1]]))

        XCTAssertEqual(result.attacks[0].procs["gasCloud"] ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(result.attacks[1].procs["gasCloud"] ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(dotDamage(result, attack: 0) + dotDamage(result, attack: 1),
                       100.5, accuracy: 1e-4)
    }

    func testGasDifferentPulseKeepsItsOwnTimer() {
        // Two Gas instances half a second apart do not turn into a Heat-style
        // refreshable timer.  Their immediate pulses remain separate; only the
        // first instance has reached its second pulse by t=1.
        let attack = Attack(name: "Gas phase", speed: 2, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100], forceProcs: ["gas"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 2, reloadTime: 100)
        let result = run(weapon, Enemy(name: "E", faction: "Neutral", health: 1e9),
                         options: Options(window: 1.1))

        XCTAssertEqual(dotDamage(result), 3 * 50.5, accuracy: 1e-4)
    }

    func testTeslaBreakCanQueueMagneticForcedTeslaAtTheSameTimestamp() {
        // The first direct hit leaves 50 Shield and applies Magnetic.  Its
        // immediate Electricity tick then breaks the shield, so the break
        // must enqueue (rather than lose) the extra 3% forced Electricity.
        let attack = Attack(name: "Tesla break", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100],
                            forceProcs: ["magnetic", "electricity"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100)
        let enemy = Enemy(name: "Shield", faction: "Neutral", health: 1e9, shield: 150)
        let result = run(weapon, enemy, options: Options(window: 6.5))

        XCTAssertEqual(result.attacks[0].procs["tesla"] ?? 0, 2, accuracy: 1e-12)
        XCTAssertEqual(dotDamage(result), 6 * 50.5 + 0.03 * 150, accuracy: 1e-4)
    }

    func testMagneticBreakCreatesThreePercentElectricityForBothProtectionLayers() {
        // The first hit leaves 50 protection and applies Magnetic.  The next
        // hit sees one stack, breaks the layer, and produces exactly 3% of its
        // maximum value as a six-tick forced Electricity status.
        let attack = Attack(name: "Magnetic", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100], forceProcs: ["magnetic"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 2, reloadTime: 100)

        for enemy in [
            Enemy(name: "Shield", faction: "Neutral", health: 1e9, shield: 150),
            Enemy(name: "Overguard", faction: "Neutral", health: 1e9, overguard: 150)
        ] {
            let result = run(weapon, enemy, options: Options(window: 7.1))
            XCTAssertEqual(result.attacks[0].procs["tesla"] ?? 0, 1, accuracy: 1e-12,
                           "\(enemy.name) should emit its forced Electricity status")
            XCTAssertEqual(dotDamage(result), 4.5, accuracy: 1e-4,
                           "\(enemy.name) break should be 3% of its 150 maximum")
        }
    }

    func testMagneticBreakUsesMagneticApplierModifiersNotBaseDamage() {
        // Serration must not appear in this result.  Electricity applies once;
        // status damage and faction each apply twice; duration multiplies the
        // total at the end.  All of those modifiers belong to the Magnetic
        // applier, not to the direct hit that happens to finish the shield.
        let attack = Attack(name: "Magnetic source", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100], forceProcs: ["magnetic"])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 2, reloadTime: 100)
        weapon.categories = ["primary-rifle"]
        let enemy = Enemy(name: "G", faction: "Grineer", health: 1e9, shield: 1_000)
        let build = Build(mods: ["Serration", "Stormbringer", "Rifle Elementalist",
                                 "Continuous Misery", "Bane of Grineer"])
        let result = Calculator().evaluate(DamageInput(weapon: weapon, enemy: enemy, level: 1,
                                                        build: build, options: Options(window: 13)))

        let expected = 0.03 * 1_000 * 1.9 * 1.9 * 1.9 * 1.3 * 1.3 * 2
        XCTAssertEqual(result.attacks[0].procs["tesla"] ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(dotDamage(result), expected, accuracy: 1e-3)
    }

    func testStatusDamageReductionAppliesOnlyToTheDotEvent() {
        let attack = Attack(name: "Status DR", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100], forceProcs: ["slash"])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9,
                          innateDR: ["status": 0.5])
        let result = run(weapon, enemy, options: Options(window: 7))

        XCTAssertEqual(result.attacks[0].directDamage, 100, accuracy: 1e-9)
        XCTAssertEqual(layerDamage(result, layer: .health), 100 + 6 * 35.35 * 0.5, accuracy: 1e-4)
    }

    func testColdAndPunctureModifyFollowingWeaponHits() {
        let cold = Attack(name: "Cold", speed: 1, critChance: 100, critMultiplier: 2,
                          statusChance: 0, damage: [.impact: 100], forceProcs: ["cold"])
        let puncture = Attack(name: "Puncture", speed: 1, critChance: 0, critMultiplier: 2,
                              statusChance: 0, damage: [.impact: 100], forceProcs: ["puncture"])
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9)
        let coldResult = run(Weapon(name: "C", attacks: [cold], magazineSize: 100), enemy,
                             options: Options(window: 1.5))
        let punctureResult = run(Weapon(name: "P", attacks: [puncture], magazineSize: 100), enemy,
                                 options: Options(window: 1.5))

        // First shot establishes status; its next weapon hit sees one stack.
        let baseCDM = Rules.quantizeBaseCritDamage(2)
        let coldExpected = 100 * Rules.expectedCritMultiplier(critChance: 1, critDamage: baseCDM)
            + 100 * Rules.expectedCritMultiplier(critChance: 1, critDamage: baseCDM + 0.1)
        let punctureExpected = 100
            + 100 * Rules.expectedCritMultiplier(critChance: 0.05, critDamage: baseCDM)
        XCTAssertEqual(layerDamage(coldResult, layer: .health), coldExpected, accuracy: 1e-6)
        XCTAssertEqual(layerDamage(punctureResult, layer: .health), punctureExpected, accuracy: 1e-6)
    }

    func testArmorLeavesOnePointMinimumPerPositiveDamageType() {
        let attack = Attack(name: "Minimum", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 0.01])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10)
        let enemy = Enemy(name: "E", faction: "Neutral", health: 1e9, armor: 2700)
        let result = run(weapon, enemy, options: Options(window: 0.5))

        XCTAssertEqual(layerDamage(result, layer: .health), 1, accuracy: 1e-9)
    }
}
