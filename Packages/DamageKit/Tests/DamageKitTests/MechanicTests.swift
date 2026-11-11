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
        XCTAssertEqual(Rules.enemyArmorDR(netArmor: 1350), 0.45, accuracy: 1e-12)
        // 2700 是 90% 硬顶
        XCTAssertEqual(Rules.enemyArmorDR(netArmor: 5400), 5400.0 / 5700.0, accuracy: 1e-12)
    }

    func testSlashBypassesArmor() {
        let slash = Attack(name: "S", speed: 1, critChance: 0, critMultiplier: 1,
                           statusChance: 0, damage: [.slash: 100])
        let impact = Attack(name: "I", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "Armored", faction: "Neutral", baseLevel: 1, health: 1e6, armor: 2700)
        let s = healthDamage(run(Weapon(name: "A", attacks: [slash], magazineSize: 1, reloadTime: 0), enemy, window: 0.5))
        let i = healthDamage(run(Weapon(name: "B", attacks: [impact], magazineSize: 1, reloadTime: 0), enemy, window: 0.5))
        XCTAssertEqual(s, 100, accuracy: 1e-9)
        XCTAssertEqual(i, 10, accuracy: 1e-9)
    }

    func testArmorStripIncreasesDamage() {
        let attack = Attack(name: "I", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let enemy = Enemy(name: "Armored", faction: "Neutral", baseLevel: 1, health: 1e6, armor: 2700)
        var opts = Options()
        opts.armorStrip = 0.5
        let stripped = healthDamage(run(Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0),
                                        enemy, window: 0.5, options: opts))
        // 1350 护甲 → 45% 减伤 → 55 伤害
        XCTAssertEqual(stripped, 55, accuracy: 1e-6)
    }

    // MARK: 等级缩放

    func testGrineerScalingAtLevel100() {
        let base = Enemy(name: "Heavy Gunner", faction: "Grineer", baseLevel: 8,
                         health: 300, shield: 0, armor: 500)
        let p = EnemyProfile(enemy: base, level: 100, options: Options())
        // 健康曲线 f2 = 1 + 10.7332 × 92^0.72
        let expectedHealth = 300 * (1 + 10.7332 * pow(92.0, 0.72))
        XCTAssertEqual(p.health, expectedHealth, accuracy: 1e-6)
        // 护甲被夹到 2700
        XCTAssertEqual(p.armor, 2700, accuracy: 1e-9)
        XCTAssertEqual(p.armorDR, 0.9, accuracy: 1e-12)
    }

    func testSteelPathMultipliesStats() {
        let base = Enemy(name: "HG", faction: "Grineer", baseLevel: 8, health: 300, armor: 500)
        var opts = Options()
        opts.steelPath = true
        let p = EnemyProfile(enemy: base, level: 100, options: opts)
        // 等级 +100 → q = 192
        let expected = 300 * (1 + 10.7332 * pow(192.0, 0.72)) * Rules.steelPathStatMultiplier
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
        XCTAssertEqual(Rules.corrosiveArmorFactor(stacks: 99), 0.20, accuracy: 1e-12)
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
        // 四层是各自独立结算的（口径第 6 条），护盾在不在都不影响「生命层」那一列
        XCTAssertEqual(healthDamage(i), 100, accuracy: 1e-9)
    }

    func testSlashBleedTicksSixTimes() {
        let attack = Attack(name: "S", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.slash: 100])
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9, armor: 0)
        let result = run(Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0),
                         enemy, window: 7)
        // 1 发直伤 100 + 6 跳 × 35
        XCTAssertEqual(healthDamage(result), 100 + 6 * 35, accuracy: 1e-6)
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
        // 一个弹匣 10 发用 0.9s，再加 1s 换弹 → 单循环 1.9s，10s 内 55 发
        XCTAssertEqual(withReload.attacks[0].shots, 55, accuracy: 1e-9)
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
        let withPool = run(shared, enemy, window: 3)
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
        // 100 基础命中、+30% Bane：Bleed 每跳 = 命中总伤害 × 0.35 × 1.3²
        let attack = Attack(name: "S", speed: 0.01, critChance: 0, critMultiplier: 1,
                            statusChance: 100, damage: [.slash: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 100, reloadTime: 0)
        weapon.categories = ["primary-rifle"]
        let enemy = Enemy(name: "E", faction: "Grineer", baseLevel: 1, health: 1e9, armor: 0)
        let result = run(weapon, enemy, window: 7, build: Build(mods: ["Bane of Grineer"]))
        let direct = 100 * 1.3
        let perTick = 100 * 1.3 * 1.3 * 0.35
        XCTAssertEqual(healthDamage(result), direct + 6 * perTick, accuracy: 1e-6)
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
}
