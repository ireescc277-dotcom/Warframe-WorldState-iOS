import XCTest
@testable import DamageKit

final class CoreTests: XCTestCase {

    func testElementMergePairsInOrder() {
        // Heat 在前、Toxin 在后 → Gas；Cold 落单。
        let merged = BuildResolver.mergeElements(
            base: [.slash: 10],
            mods: [(.heat, 90), (.toxin, 90), (.cold, 90)]
        )
        XCTAssertEqual(merged[.gas] ?? 0, 180, accuracy: 1e-9)
        XCTAssertEqual(merged[.cold] ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(merged[.slash] ?? 0, 10, accuracy: 1e-9)
    }

    func testInnateElementCombinesLast() {
        // 固有 Toxin + mod Electricity → Corrosive
        let merged = BuildResolver.mergeElements(base: [.toxin: 100], mods: [(.electricity, 100)])
        XCTAssertEqual(merged[.corrosive] ?? 0, 200, accuracy: 1e-9)
        XCTAssertNil(merged[.toxin])
        XCTAssertNil(merged[.electricity])
    }

    func testCritExpectationIsLinearAboveHundred() {
        // 150% 暴率 / 2.0 暴伤 → 期望 1 + 1.5 × 1 = 2.5
        let m = Rules.expectedCritMultiplier(critChance: 1.5, critDamage: 2.0)
        XCTAssertEqual(m, 2.5, accuracy: 1e-12)
        // 无暴击 → 1.0
        XCTAssertEqual(Rules.expectedCritMultiplier(critChance: 0, critDamage: 5), 1.0, accuracy: 1e-12)
    }

    func testEnemyArmorReduction() {
        // 2700 护甲 → 90%
        XCTAssertEqual(Rules.enemyArmorDR(netArmor: 2700), 0.9, accuracy: 1e-12)
        XCTAssertEqual(Rules.enemyArmorDR(netArmor: 0), 0, accuracy: 1e-12)
        // 超过 2700 切回 armor/(armor+300)
        XCTAssertEqual(Rules.enemyArmorDR(netArmor: 3000), 3000.0 / 3300.0, accuracy: 1e-12)
    }

    func testDeterminism() throws {
        let enemy = Enemy(name: "Test", faction: "Grineer", baseLevel: 8,
                          health: 300, shield: 0, armor: 500)
        let attack = Attack(name: "Hit", speed: 2, critChance: 30, critMultiplier: 2.2,
                            statusChance: 20, damage: [.impact: 50, .slash: 25, .toxin: 25],
                            multishot: 1)
        let weapon = Weapon(name: "TestGun", attacks: [attack], magazineSize: 10, reloadTime: 1.5)
        let input = DamageInput(weapon: weapon, enemy: enemy, level: 60)
        let calc = Calculator()
        let a = calc.evaluate(input)
        let b = calc.evaluate(input)
        XCTAssertEqual(a, b)
    }
}
