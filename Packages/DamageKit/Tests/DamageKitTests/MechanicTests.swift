import Foundation
import XCTest
@testable import DamageKit

/// 每条机制一个用例，用的都是"能手算"的构造。
final class MechanicTests: XCTestCase {

    private func run(_ weapon: Weapon, _ enemy: Enemy, level: Int = 1,
                     window: Double = 20, options: Options? = nil,
                     build: Build = Build()) -> Result {
        var opts = options ?? Options()
        opts.window = window
        let input = DamageInput(weapon: weapon, enemy: enemy, level: level,
                                build: build, options: opts)
        return Calculator().evaluate(input)
    }

    private func healthDamage(_ result: Result, attack: Int = 0) -> Double {
        result.attacks[attack].layers.first(where: { $0.layer == .health })?.damage ?? 0
    }

    private func ttk(_ result: Result, layer: Layer, attack: Int = 0) -> Double? {
        result.attacks[attack].layers.first(where: { $0.layer == layer })?.ttk
    }

    // MARK: 暴击

    func testCritTierExpectation() {
        // 100% 暴率 / 2× 暴伤 = 每发都暴击 → 2.0
        XCTAssertEqual(Rules.expectedCritMultiplier(critChance: 1.0, critDamage: 2.0), 2.0, accuracy: 1e-12)
        // 200% 暴率 = 必定橙暴，倍率 3.0（1 + 2×(2-1)）
        XCTAssertEqual(Rules.expectedCritMultiplier(critChance: 2.0, critDamage: 2.0), 3.0, accuracy: 1e-12)
        // 50% 暴率 = 期望 1.5
        XCTAssertEqual(Rules.expectedCritMultiplier(critChance: 0.5, critDamage: 2.0), 1.5, accuracy: 1e-12)
    }

    func testCriticalHeadshotUsesItsOwnCritFormula() {
        // 标准头部 3x；30% 暴率、2x 暴伤时：3 × (1 + .3 × (2×2−1)) = 5.7。
        XCTAssertEqual(Rules.expectedCriticalHeadshotMultiplier(critChance: 0.3,
                                                                 critDamage: 2,
                                                                 headshotMultiplier: 3),
                       5.7, accuracy: 1e-12)
        XCTAssertEqual(Options().headshotMultiplier, 3, accuracy: 1e-12)
    }

    func testCritDamageQuantization() {
        // 2.0 能被 32/4095 整除到 256 码，几乎无误差
        XCTAssertEqual(Rules.quantizeBaseCritDamage(2.0), 2.0, accuracy: 1e-3)
        // 上界被 clamp 到 32
        XCTAssertEqual(Rules.quantizeBaseCritDamage(99), 32.0, accuracy: 1e-9)
    }

    // MARK: 元素合并

    func testElementMergeDuplicateCoalesces() {
        // 两个 Heat 先合并成一个 Heat，再和 Toxin 组成 Gas
        let merged = BuildResolver.mergeElements(base: [:], mods: [(.heat, 50), (.heat, 50), (.toxin, 100)])
        XCTAssertEqual(merged[.gas] ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(merged.count, 1)
    }

    func testElementMergeRespectsSlotOrder() {
        // 顺序不同，结果不同：Toxin+Electricity = Corrosive，Heat+Cold = Blast
        let a = BuildResolver.mergeElements(base: [:], mods: [(.toxin, 100), (.electricity, 100), (.heat, 100), (.cold, 100)])
        XCTAssertEqual(a[.corrosive] ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(a[.blast] ?? 0, 200, accuracy: 1e-9)

        let b = BuildResolver.mergeElements(base: [:], mods: [(.heat, 100), (.cold, 100), (.toxin, 100), (.electricity, 100)])
        XCTAssertEqual(b[.blast] ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(b[.corrosive] ?? 0, 200, accuracy: 1e-9)
    }

    // MARK: 派系

    func testFactionVulnerability() {
        XCTAssertEqual(FactionProfile.grineer.multiplier(for: .corrosive), 1.5, accuracy: 1e-12)
        XCTAssertEqual(FactionProfile.grineer.multiplier(for: .heat), 1.0, accuracy: 1e-12)
        XCTAssertEqual(FactionProfile.sentient.multiplier(for: .corrosive), 0.5, accuracy: 1e-12)
        XCTAssertEqual(FactionProfile.orokin.multiplier(for: .radiation), 0.5, accuracy: 1e-12)
    }

    func testFactionNameNormalization() {
        XCTAssertEqual(FactionProfile.resolve(rawFaction: " Infested").canonical, "Infested")
        XCTAssertEqual(FactionProfile.resolve(rawFaction: "Infestation").canonical, "Infested")
        XCTAssertEqual(FactionProfile.resolve(rawFaction: "Kuva Grineer").canonical, "Grineer")
        XCTAssertEqual(FactionProfile.resolve(rawFaction: "Corpus Amalgam").canonical, "Corpus")
    }

    func testVulnerableFactionTakesMoreDamage() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.corrosive: 100])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0)
        let grineer = Enemy(name: "G", faction: "Grineer", baseLevel: 1, health: 1e6, armor: 0)
        let corpus = Enemy(name: "C", faction: "Corpus", baseLevel: 1, health: 1e6, armor: 0)
        let a = healthDamage(run(weapon, grineer, window: 0.5))
        let b = healthDamage(run(weapon, corpus, window: 0.5))
        XCTAssertEqual(a, b * 1.5, accuracy: 1e-6)
    }

    // MARK: 护甲

    func testArmorReductionAndClamp() {
        // 标准 NPC 护甲公式：0.9 × sqrt(armor / 2700)。
        XCTAssertEqual(Rules.enemyArmorDR(netArmor: 1350), 0.9 * sqrt(0.5), accuracy: 1e-6)
        // 2700 是 90% 硬顶
        XCTAssertEqual(Rules.enemyArmorDR(netArmor: 5400), 5400.0 / 5700.0, accuracy: 1e-6)
    }

    func testDirectSlashDoesNotBypassArmor() {
        let slash = Attack(name: "S", speed: 1, critChance: 0, critMultiplier: 1,
                           statusChance: 0, damage: [.slash: 100])
        let impact = Attack(name: "I", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "Armored", faction: "Neutral", baseLevel: 1, health: 1e6, armor: 2700)
        let s = healthDamage(run(Weapon(name: "A", attacks: [slash], magazineSize: 1, reloadTime: 0), enemy, window: 0.5))
        let i = healthDamage(run(Weapon(name: "B", attacks: [impact], magazineSize: 1, reloadTime: 0), enemy, window: 0.5))
        // 绕甲的是 Slash proc 产生的 Cinematic DOT，而不是直击 Slash。
        XCTAssertEqual(s, 10, accuracy: 1e-5)
        XCTAssertEqual(i, 10, accuracy: 1e-5)
    }

    func testArmorStripIncreasesDamage() {
        let attack = Attack(name: "I", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "Armored", faction: "Neutral", baseLevel: 1, health: 1e6, armor: 2700)
        var opts = Options()
        opts.armorStrip = 0.5
        let stripped = healthDamage(run(Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0),
                                        enemy, window: 0.5, options: opts))
        // 1350 护甲 → 0.9 × sqrt(0.5) 减伤。
        XCTAssertEqual(stripped, 100 * (1 - Rules.enemyArmorDR(netArmor: 1350)), accuracy: 1e-6)
    }

    // MARK: 等级缩放

    func testGrineerScalingAtLevel100() {
        let base = Enemy(name: "Heavy Gunner", faction: "Grineer", baseLevel: 8,
                         health: 300, shield: 0, armor: 500)
        let p = EnemyProfile(enemy: base, level: 100, options: Options())
        // Checked-in website branch: f2 = 1 + 24 × 92^0.72 × sqrt(5) / 5,
        // then retain two decimal places and round the displayed target value.
        let q = 92.0
        let multiplier = 1 + 24 * pow(q, 0.72) * sqrt(5) / 5
        let expectedHealth = ((300 * multiplier * 100).rounded() / 100).rounded()
        XCTAssertEqual(p.health, expectedHealth, accuracy: 1e-6)
        // 护甲被夹到 2700
        XCTAssertEqual(p.armor, 2700, accuracy: 1e-9)
        XCTAssertEqual(p.armorDR, 0.9, accuracy: 1e-6)
    }

    func testSteelPathMultipliesStats() {
        let base = Enemy(name: "HG", faction: "Grineer", baseLevel: 8, health: 300, armor: 500)
        var opts = Options()
        opts.steelPath = true
        let p = EnemyProfile(enemy: base, level: 100, options: opts)
        // Website first multiplies the floored base health by 2.5, then uses
        // the same normal target curve and display rounding.
        let q = 92.0
        let multiplier = 1 + 24 * pow(q, 0.72) * sqrt(5) / 5
        let expected = ((2.5 * 300 * multiplier * 100).rounded() / 100).rounded()
        XCTAssertEqual(p.health, expected, accuracy: 1e-6)
    }

    // MARK: 状态

    func testViralStackCurve() {
        XCTAssertEqual(Rules.viralMultiplier(stacks: 0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(Rules.viralMultiplier(stacks: 1), 2.0, accuracy: 1e-12)
        XCTAssertEqual(Rules.viralMultiplier(stacks: 2), 2.25, accuracy: 1e-12)
        XCTAssertEqual(Rules.viralMultiplier(stacks: 10), 4.25, accuracy: 1e-12)
        XCTAssertEqual(Rules.viralMultiplier(stacks: 99), 4.25, accuracy: 1e-12)
    }

    func testCorrosiveArmorCurve() {
        XCTAssertEqual(Rules.corrosiveArmorFactor(stacks: 1), 0.74, accuracy: 1e-12)
        XCTAssertEqual(Rules.corrosiveArmorFactor(stacks: 10), 0.20, accuracy: 1e-12)
        XCTAssertEqual(Rules.corrosiveArmorFactor(stacks: 13), 0.02, accuracy: 1e-12)
        XCTAssertEqual(Rules.corrosiveArmorFactor(stacks: 14), 0, accuracy: 1e-12)
        XCTAssertEqual(Rules.corrosiveArmorFactor(stacks: 99), 0, accuracy: 1e-12)
    }

    func testViralProcDoublesHealthDamage() {
        let attack = Attack(name: "V", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.viral: 100])
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e6, armor: 0)
        let result = run(Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0),
                         enemy, window: 1.5)
        // 第 1 发 100（自身挂层前），第 2 发 ×2 → 200，共 300
        XCTAssertEqual(healthDamage(result), 300, accuracy: 1e-6)
        // 窗口 1.5s 内两发，各触发一次
        XCTAssertEqual(result.attacks[0].procs["virus"] ?? 0, 2, accuracy: 1e-9)
    }

    func testToxinBypassesShield() {
        let toxin = Attack(name: "T", speed: 1, critChance: 0, critMultiplier: 1,
                           statusChance: 0, damage: [.toxin: 100])
        let impact = Attack(name: "I", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "Shielded", faction: "Neutral", baseLevel: 1,
                          health: 1e6, shield: 1000, armor: 0)
        let t = run(Weapon(name: "A", attacks: [toxin], magazineSize: 1, reloadTime: 0), enemy, window: 0.5)
        let i = run(Weapon(name: "B", attacks: [impact], magazineSize: 1, reloadTime: 0), enemy, window: 0.5)
        XCTAssertEqual(t.attacks[0].layers.first { $0.layer == .shield }?.damage ?? 0, 0, accuracy: 1e-9)
        XCTAssertEqual(healthDamage(t), 100, accuracy: 1e-9)
        XCTAssertEqual(i.attacks[0].layers.first { $0.layer == .shield }?.damage ?? 0, 100, accuracy: 1e-9)
        // 普通伤害先被仍存在的护盾完全吸收，不能再同时伤及生命。
        XCTAssertEqual(healthDamage(i), 0, accuracy: 1e-9)
    }

    func testSlashBleedTicksSixTimes() {
        let attack = Attack(name: "S", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.slash: 100])
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let result = run(Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0),
                         enemy, window: 7)
        // Each independent Slash stack uses the exact `(seed + 1)` accumulator.
        XCTAssertEqual(healthDamage(result), 100 + 6 * 35.35, accuracy: 1e-4)
    }

    func testHeatStripReducesArmorOverTime() {
        // 火焰状态会在 2 秒内剥掉最多 50% 护甲
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.heat: 50])
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 2700)
        let result = run(Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0),
                         enemy, window: 4)
        // 只看直伤部分：第 1 发 5，之后护甲被剥，直伤逐步升高
        XCTAssertGreaterThan(result.attacks[0].directDamage, 50 * 4 * 0.1)
    }

    // MARK: 多重射击与触发

    func testMultishotScalesDamageAndProcs() {
        let attack = Attack(name: "M", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 50, damage: [.impact: 100], multishot: 2)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let result = run(Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0),
                         enemy, window: 0.5)
        XCTAssertEqual(healthDamage(result), 200, accuracy: 1e-9)
        // 期望触发 = 0.5 × 2 = 1
        XCTAssertEqual(result.attacks[0].procs["knockback"] ?? 0, 1, accuracy: 1e-9)
    }

    func testProcTypeFollowsDamageWeight() {
        let attack = Attack(name: "P", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.impact: 75, .slash: 25])
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let result = run(Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0),
                         enemy, window: 0.5)
        XCTAssertEqual(result.attacks[0].procs["knockback"] ?? 0, 0.75, accuracy: 1e-9)
        XCTAssertEqual(result.attacks[0].procs["bleed"] ?? 0, 0.25, accuracy: 1e-9)
    }

    // MARK: 时间轴

    func testTTKAndWindow() {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 500, armor: 0)
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        // 第 1/2/3/4/5 发分别在 0/1/2/3/4 秒，累计 500 在 t=4
        XCTAssertEqual(ttk(run(weapon, enemy, window: 20), layer: .health), 4.0)
        XCTAssertNil(ttk(run(weapon, enemy, window: 3), layer: .health))
    }

    func testReloadCostsRealTime() {
        let attack = Attack(name: "H", speed: 10, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 10])
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let noReload = run(Weapon(name: "A", attacks: [attack], magazineSize: 1000, reloadTime: 0),
                           enemy, window: 10)
        let withReload = run(Weapon(name: "B", attacks: [attack], magazineSize: 10, reloadTime: 1),
                             enemy, window: 10)
        XCTAssertEqual(noReload.attacks[0].dps, 100, accuracy: 1e-6)
        XCTAssertLessThan(withReload.attacks[0].dps, noReload.attacks[0].dps)
        // 自动空仓换弹先有一个 1/射速的 reload delay：最后一发在 0.9s，
        // 0.1s 后才开始 1s 换弹。每轮从 t=0 到 t=2，共 10 发；10 秒内 50 发。
        XCTAssertEqual(withReload.attacks[0].shots, 50, accuracy: 1e-9)
    }

    // MARK: 多段共享状态池

    func testSharedStatusPoolBetweenSegments() {
        let viral = Attack(name: "Viral", speed: 2, critChance: 0, critMultiplier: 1,
                           statusChance: 100, damage: [.viral: 10])
        let impact = Attack(name: "Impact", speed: 2, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        // 共享池
        var shared = Weapon(name: "Shared", attacks: [viral, impact],
                            magazineSize: 100, reloadTime: 0)
        shared.comb = [[0, 1]]
        let withPool = run(shared, enemy, window: 3,
                           options: Options(combinedAttackGroups: [[0, 1]]))
        // 不共享
        let alone = Weapon(name: "Alone", attacks: [viral, impact],
                           magazineSize: 100, reloadTime: 0)
        let withoutPool = run(alone, enemy, window: 3)
        XCTAssertGreaterThan(healthDamage(withPool, attack: 1), healthDamage(withoutPool, attack: 1))
    }

    // MARK: 装配

    func testSerrationScalesBaseDamage() throws {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0)
        weapon.categories = ["primary-rifle"]
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let plain = run(weapon, enemy, window: 1)
        let modded = run(weapon, enemy, window: 1, build: Build(mods: ["Serration"]))
        XCTAssertEqual(healthDamage(modded), healthDamage(plain) * 2.65, accuracy: 1e-6)
    }

    func testBaneDoubleDipsOnDots() throws {
        // Bane is applied in the seed and again after the exact +1 accumulator.
        let attack = Attack(name: "S", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.slash: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        weapon.categories = ["primary-rifle"]
        let enemy = Enemy(name: "E", faction: "Grineer", baseLevel: 1, health: 1e9, armor: 0)
        let result = run(weapon, enemy, window: 7, build: Build(mods: ["Bane of Grineer"]))
        let direct = 100 * 1.3
        let perTick = (100 * 1.3 + 1) * 1.3 * 0.35
        XCTAssertEqual(healthDamage(result), direct + 6 * perTick, accuracy: 1e-4)
    }

    func testConditionalHeadshotModOnlyAppliesOnHeadshot() throws {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0)
        weapon.categories = ["primary-rifle"]
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let build = Build(mods: ["Primary Acuity"])
        var body = Options()
        body.headshot = false
        let bodyShot = run(weapon, enemy, window: 1, options: body, build: build)
        var head = Options()
        head.headshot = true
        let headShot = run(weapon, enemy, window: 1, options: head, build: build)
        XCTAssertGreaterThan(healthDamage(headShot), healthDamage(bodyShot))
    }

    // MARK: 紫卡

    func testRivenAddsStats() throws {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let riven = Riven(damage: 1.0, multishot: 0.5)
        let result = run(weapon, enemy, window: 1, build: Build(riven: riven))
        // 100 × (1+1.0) × (1+0.5)
        XCTAssertEqual(healthDamage(result), 300, accuracy: 1e-6)
    }

    func testRivenReloadSpeedChangesReloadCycle() throws {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 2)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let riven = Riven(reloadSpeed: 1)
        let result = run(weapon, enemy, window: 3, build: Build(riven: riven))
        // t=0, 2：100% 装填速度将 2s 换弹缩成 1s，但自动换弹前仍有 1s
        // reload delay；3 秒窗口的右端不计入。
        XCTAssertEqual(result.attacks[0].shots, 2, accuracy: 1e-9)
    }

    func testRivenMagazineSizeChangesReloadCycle() throws {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 2)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)

        let baseline = run(weapon, enemy, window: 5)
        let enlarged = run(weapon, enemy, window: 5,
                           build: Build(riven: Riven(magazineSize: 1)))

        // Default magazine 1: t=0 and t=3.  The +100% Riven makes magazine 2,
        // so t=0, t=1, then reload and t=4 are all inside this window.
        XCTAssertEqual(baseline.attacks[0].shots, 2, accuracy: 1e-9)
        XCTAssertEqual(enlarged.attacks[0].shots, 3, accuracy: 1e-9)
    }

    func testRivenAmmoEfficiencyExtendsAnOrdinaryMagazineBeforeReload() throws {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 2, reloadTime: 1)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let options = Options(window: 7)

        let baseline = BuildResolver(weapon: weapon, build: Build(), options: options,
                                     faction: .neutral).resolve(attack: attack)
        let efficient = BuildResolver(weapon: weapon,
                                      build: Build(riven: Riven(ammoEfficiency: 0.5)),
                                      options: options, faction: .neutral).resolve(attack: attack)
        let profile = EnemyProfile(enemy: enemy, level: 1, options: options)
        let baselineSchedule = WeaponSimulator(segments: [baseline], enemy: profile, options: options)
            .shotSchedule(for: baseline)
        let efficientSchedule = WeaponSimulator(segments: [efficient], enemy: profile, options: options)
            .shotSchedule(for: efficient)

        XCTAssertEqual(efficient.ammoEfficiency, 0.5, accuracy: 1e-12)
        // 2 rounds become 4 effective shots: the reload moves from after
        // t=1 to after t=3, with the existing reload-delay rule preserved.
        XCTAssertEqual(baselineSchedule.map(\.time), [0, 1, 3, 4, 6])
        XCTAssertEqual(efficientSchedule.map(\.time), [0, 1, 2, 3, 5, 6])
    }

    func testRivenAmmoEfficiencyCapsAtSeventyFivePercent() {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 1)
        let resolved = BuildResolver(weapon: weapon,
                                     build: Build(riven: Riven(ammoEfficiency: 1)),
                                     options: Options(), faction: .neutral)
            .resolve(attack: attack)

        XCTAssertEqual(resolved.ammoEfficiency, 0.75, accuracy: 1e-12)
    }

    func testConditionalAmmoEfficiencyAndInfiniteAmmoRemainDistinct() {
        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1])
        var primary = Weapon(name: "Primary", attacks: [attack], magazineSize: 2, reloadTime: 1)
        primary.categories = ["primary", "primary-rifle"]
        let ordinary = BuildResolver(weapon: primary, build: Build(mods: ["Primary Crux"]),
                                     options: Options(), faction: .neutral).resolve(attack: attack)

        var viper = Weapon(name: "Viper", attacks: [attack], magazineSize: 1, reloadTime: 1)
        viper.categories = ["secondary"]
        let infinite = BuildResolver(weapon: viper, build: Build(mods: ["Skull Shots"]),
                                     options: Options(), faction: .neutral).resolve(attack: attack)

        XCTAssertEqual(ordinary.ammoEfficiency, 0.6, accuracy: 1e-12)
        XCTAssertFalse(ordinary.hasInfiniteAmmo)
        XCTAssertEqual(infinite.ammoEfficiency, 0, accuracy: 1e-12)
        XCTAssertTrue(infinite.hasInfiniteAmmo)
        let options = Options(window: 3)
        let profile = EnemyProfile(enemy: Enemy(name: "E", faction: "Neutral", health: 1e9),
                                   level: 1, options: options)
        let schedule = WeaponSimulator(segments: [infinite], enemy: profile, options: options)
            .shotSchedule(for: infinite)
        XCTAssertEqual(schedule.map(\.time), [0, 1, 2])
    }

    func testRivenHeavyComboEfficiencyReachesTheHeavySchedule() throws {
        let attack = Attack(name: "Normal Attack", speed: 1, critChance: 0,
                            critMultiplier: 1, statusChance: 0, damage: [.slash: 10])
        var weapon = Weapon(name: "Skana", attacks: [attack], category: "Melee")
        weapon.categories = ["weapon", "melee", "melee-sword"]
        weapon.compTags = ["SWORDS_STANCE", "SKANA"]
        let options = Options(window: 20, heavyAttack: true, heavyAttackStartingCombo: 12)
        let resolved = try XCTUnwrap(BuildResolver(
            weapon: weapon,
            build: Build(riven: Riven(meleeComboEfficiency: 0.5)),
            options: options,
            faction: .grineer
        ).resolveAll().first)

        XCTAssertEqual(resolved.heavyComboEfficiency, 0.5, accuracy: 1e-12)
        let enemy = Enemy(name: "E", faction: "Grineer", health: 1e12, armor: 0)
        let schedule = WeaponSimulator(
            segments: [resolved], enemy: EnemyProfile(enemy: enemy, level: 1, options: options),
            options: options
        ).shotSchedule(for: resolved)
        // One pair of heavy contacts consumes combo at a time. At 50%
        // efficiency the 12x opening pair becomes a 6x pair, rather than
        // falling straight to 1x as it would with no efficiency.
        XCTAssertEqual(Array(schedule.prefix(4).map(\.comboMultiplier)), [12, 12, 6, 6])
    }

    func testRivenCompletedCorrosiveStaysOneCompletedDamageComponent() {
        let attack = Attack(name: "Riven Corrosive", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "Rifle", attacks: [attack], magazineSize: 1, reloadTime: 0)
        weapon.categories = ["primary-rifle"]

        let resolved = BuildResolver(weapon: weapon,
                                     build: Build(riven: Riven(elements: ["corrosive": 1])),
                                     options: Options(), faction: .neutral)
            .resolve(attack: attack)

        XCTAssertEqual(resolved.damage[.impact] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(resolved.damage[.corrosive] ?? 0, 100, accuracy: 1e-9)
        // This Riven term is not two primary elements placed in an arbitrary
        // slot order, so it cannot be turned into another combination.
        XCTAssertNil(resolved.damage[.electricity])
        XCTAssertNil(resolved.damage[.toxin])
    }

    // MARK: 灵化

    func testIncarnonFormUsesIncarnonMagazine() throws {
        let attack = Attack(name: "Incarnon Form", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 10], isIncarnonForm: true)
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 2, reloadTime: 5)
        weapon.incarnonMagazineSize = 100
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let result = run(weapon, enemy, window: 10)
        // 没有换弹 → t=0...9 共 10 发
        XCTAssertEqual(result.attacks[0].shots, 10, accuracy: 1e-9)
    }

    // MARK: 确定性

    func testSameInputSameResult() {
        let attack = Attack(name: "H", speed: 3, critChance: 37, critMultiplier: 2.4,
                            statusChance: 45, damage: [.impact: 20, .slash: 30, .heat: 50])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 12, reloadTime: 1.2)
        let enemy = Enemy(name: "E", faction: "Grineer", baseLevel: 8, health: 2000, armor: 400)
        let input = DamageInput(weapon: weapon, enemy: enemy, level: 80)
        let calc = Calculator()
        XCTAssertEqual(calc.evaluate(input), calc.evaluate(input))
    }

    // MARK: 按类型保留

    /// 目标对热免疫时，热这一条应当是 0，冲击照常结算。
    /// 这条用例锁的是「伤害向量不提前求和」——否则免疫只能靠把总和拆回来实现。
    func testImmuneTypeStaysZeroInVector() {
        var enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e6)
        // `elemRes` 表示减伤比例；1 才是完全免疫。
        enemy.elemRes = ["heat": 1]

        let attack = Attack(name: "H", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 50, .heat: 50])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100)
        let result = run(weapon, enemy, window: 1)

        let health = result.attacks[0].layers.first { $0.layer == .health }!
        XCTAssertEqual(health.byType["heat"] ?? -1, 0, accuracy: 1e-12)
        XCTAssertEqual(health.byType["impact"] ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(health.damage, 50, accuracy: 1e-9)
        // 未减免的那张表里两条都在，方便看出是「免疫」而不是「没有这种伤害」。
        XCTAssertEqual(result.attacks[0].rawByType["heat"] ?? 0, 50, accuracy: 1e-9)
        XCTAssertEqual(result.attacks[0].rawByType["impact"] ?? 0, 50, accuracy: 1e-9)
    }
}
