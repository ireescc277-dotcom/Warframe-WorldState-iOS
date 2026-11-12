import XCTest
@testable import DamageKit

/// 灵化进化（Incarnon Genesis）把数值写进 `attacks` 的方式。
///
/// 口径来源：<https://wiki.warframe.com/w/Torid> 的 Evolutions 表，
/// 原文一律写 "Increase **Base** ..." —— 即加在基础值上的绝对量，不是相对百分比。
final class IncarnonTests: XCTestCase {

    private func enemy(_ hp: Double = 1e9) -> Enemy {
        Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: hp, armor: 0)
    }

    private func resolved(_ weapon: Weapon, build: Build) -> [ResolvedAttack] {
        let options = Options()
        let profile = EnemyProfile(enemy: enemy(), level: 1, options: options)
        return BuildResolver(weapon: weapon, build: build, options: options,
                             faction: profile.faction).resolveAll()
    }

    private func run(_ weapon: Weapon, window: Double = 20, build: Build = Build()) -> Result {
        var options = Options()
        options.window = window
        return Calculator().evaluate(DamageInput(weapon: weapon, enemy: enemy(), level: 1,
                                                 build: build, options: options))
    }

    private func healthDamage(_ result: Result, attack: Int = 0) -> Double {
        result.attacks[attack].layers.first(where: { $0.layer == .health })?.damage ?? 0
    }

    private func weaponWith(_ attack: Attack,
                            magazine: Double = 1,
                            incarnonMagazine: Double? = nil,
                            _ option: IncarnonTier.IncarnonOption) -> Weapon {
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: magazine, reloadTime: 0)
        weapon.incarnonMagazineSize = incarnonMagazine
        weapon.incarnon = [IncarnonTier(tier: 19, options: [option])]
        return weapon
    }

    // MARK: 数值

    func testFlatChangeDamageAddsToBase() {
        // EVO2 Final Fusillade："Increase Base Damage by +51"
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.toxin: 100])
        let weapon = weaponWith(attack, .init(name: "F", action: ["flat_change_dmg": .number(51)]))
        let out = resolved(weapon, build: Build(incarnonPerks: ["19:0"]))
        XCTAssertEqual(out[0].damage[.toxin] ?? 0, 151, accuracy: 1e-9)
    }

    func testFlatChangeDamageScalesWithDamageMods() {
        // 固定值加在基础伤害上，所以一样吃 Serration 的 +165%
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.toxin: 100])
        var weapon = weaponWith(attack, .init(name: "F", action: ["flat_change_dmg": .number(51)]))
        weapon.categories = ["primary-rifle"]
        let out = resolved(weapon, build: Build(mods: ["Serration"], incarnonPerks: ["19:0"]))
        XCTAssertEqual(out[0].damage[.toxin] ?? 0, 151 * 2.65, accuracy: 1e-4)
    }

    func testAddCritChanceIsAbsolutePercentagePoint() {
        // EVO4 Commodore's Fortune："Increase Base Critical Chance by +20%" → 15% + 20% = 35%
        let attack = Attack(name: "A", speed: 1, critChance: 15, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = weaponWith(attack, .init(name: "C", action: ["add_crit_chance": .number(0.2)]))
        let out = resolved(weapon, build: Build(incarnonPerks: ["19:0"]))
        XCTAssertEqual(out[0].critChance, 0.35, accuracy: 1e-9)
    }

    func testFlatStatusChanceIsAbsolutePercentagePoint() {
        // EVO4 Elemental Balance："Increase Base Status Chance by +34%" → 23% + 34% = 57%
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 23, damage: [.impact: 100])
        let weapon = weaponWith(attack, .init(name: "E", action: ["flat_status_chance": .number(0.34)]))
        let out = resolved(weapon, build: Build(incarnonPerks: ["19:0"]))
        XCTAssertEqual(out[0].statusChance, 0.57, accuracy: 1e-9)
    }

    func testFlatCritMultiplierIsAbsolute() {
        // "Increase Base Critical Damage Multiplier by +0.2x"
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = weaponWith(attack, .init(name: "M", action: ["flat_critmult": .number(0.2)]))
        let out = resolved(weapon, build: Build(incarnonPerks: ["19:0"]))
        // 基础暴伤先做 12 bit 量化（2.0 → 2.000488…），灵化的固定增量加在量化之后
        XCTAssertEqual(out[0].critMultiplier,
                       Rules.quantizeBaseCritDamage(2) + 0.2, accuracy: 1e-9)
    }

    func testIncarnonBaseActsAsDamageBonus() {
        // "+100% Melee Damage" 一类，进 +伤害% 加算池
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = weaponWith(attack, .init(name: "B", action: ["base": .number(1.0)]))
        let out = resolved(weapon, build: Build(incarnonPerks: ["19:0"]))
        XCTAssertEqual(out[0].damage[.impact] ?? 0, 200, accuracy: 1e-9)
    }

    // MARK: 弹匣

    func testAddMagazineSizeIsFlatAndBeforePercentageMods() {
        // EVO3 Extended Volley："Increase **Base** Magazine Capacity by +9" → (5+9)×(1+0.2)
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 5, reloadTime: 1)
        weapon.categories = ["primary-rifle"]
        weapon.incarnon = [IncarnonTier(tier: 20, options: [
            .init(name: "V", action: ["add_magazineSize": .number(9)])
        ])]
        let out = resolved(weapon, build: Build(mods: ["Wildfire"], incarnonPerks: ["20:0"]))
        XCTAssertEqual(out[0].magazine, 16.8, accuracy: 1e-9)
    }

    func testIncarnonFormMagazineIgnoresMods() {
        // "Incarnon Form's magazine is not affected by mods."
        let attack = Attack(name: "Incarnon Form", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100], isIncarnonForm: true)
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 5, reloadTime: 1)
        weapon.incarnonMagazineSize = 170
        weapon.categories = ["primary-rifle"]
        let out = resolved(weapon, build: Build(mods: ["Wildfire"]))
        XCTAssertEqual(out[0].magazine, 170, accuracy: 1e-9)
    }

    // MARK: 多重

    func testLastShotMultishotOnlyAppliesToLastShotInMagazine() {
        // "+3 Multishot on last shot in magazine"，弹匣 2、射速 1、无换弹时间
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        let plain = Weapon(name: "W", attacks: [attack], magazineSize: 2, reloadTime: 0)
        let withPerk = weaponWith(attack, magazine: 2, .init(name: "L", action: ["l_add_multishot": .number(3)]))

        let base = run(plain, window: 5)
        XCTAssertEqual(base.attacks[0].shots, 5, accuracy: 1e-9)
        // 5 发 × 100
        XCTAssertEqual(healthDamage(base), 500, accuracy: 1e-6)

        let boosted = run(withPerk, window: 5, build: Build(incarnonPerks: ["19:0"]))
        // 第 2、4 发各 +3 多重 → 3×100 + 2×400
        XCTAssertEqual(healthDamage(boosted), 1100, accuracy: 1e-6)
    }

    // MARK: 限定作用段

    func testTypeRestrictionKeepsPerkOffOtherAttacks() {
        // Commodore's Fortune 在 Torid 上只写 `Normal Attack`，不该作用到灵化形态
        var weapon = Weapon(name: "W",
                            attacks: [
                                Attack(name: "Grenade Impact", speed: 1, critChance: 15, critMultiplier: 2,
                                       statusChance: 0, damage: [.toxin: 100]),
                                Attack(name: "Incarnon Form", speed: 1, critChance: 29, critMultiplier: 3,
                                       statusChance: 0, damage: [.toxin: 51], isIncarnonForm: true)
                            ],
                            magazineSize: 5, reloadTime: 0)
        weapon.incarnon = [IncarnonTier(tier: 21, options: [
            .init(name: "Commodore's Fortune", type: ["Normal Attack"],
                  action: ["add_crit_chance": .number(0.2)])
        ])]
        let out = resolved(weapon, build: Build(incarnonPerks: ["21:0"]))
        XCTAssertEqual(out[0].critChance, 0.35, accuracy: 1e-9)
        XCTAssertEqual(out[1].critChance, 0.29, accuracy: 1e-9)
    }

    func testUnknownIncarnonActionIsReportedNotGuessed() {
        // 没实现的动作必须进 notes，不能悄悄当成没有
        let attack = Attack(name: "A", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = weaponWith(attack, .init(name: "X", action: ["some_unknown_key": .number(1)]))
        let out = resolved(weapon, build: Build(incarnonPerks: ["19:0"]))
        XCTAssertTrue(out[0].notes.contains { $0.contains("未实现的灵化动作") && $0.contains("some_unknown_key") },
                      "notes: \(out[0].notes)")
    }

    func testIncarnonConditionalUsesTheSameDataRuleAsAMod() {
        // Laetum's Lethal Rearmament is a conditional Incarnon option rather
        // than a `mods.json` slot Mod.  Its 3-stack rule is nevertheless data
        // in conditional-effects.json, so BuildResolver must not have a second
        // name-specific path or report WITH_COND.reloadTime as unsupported.
        let attack = Attack(name: "Normal Attack", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 10)
        weapon.incarnon = [IncarnonTier(tier: 20, options: [
            .init(name: "Lethal Rearmament: test", type: ["Normal Attack"],
                  action: ["WITH_COND": .object(["reloadTime": .number(0.9)])])
        ])]
        let options = Options(conditionalModStacks: ["Lethal Rearmament": 3])
        let profile = EnemyProfile(enemy: enemy(), level: 1, options: options)
        let out = BuildResolver(weapon: weapon, build: Build(incarnonPerks: ["20:0"]),
                                options: options, faction: profile.faction)
            .resolve(attack: attack)

        XCTAssertEqual(out.reload, 10 / 1.9, accuracy: 1e-12)
        XCTAssertFalse(out.notes.contains { $0.contains("WITH_COND.reloadTime") },
                       "notes: \(out.notes)")
    }
}
