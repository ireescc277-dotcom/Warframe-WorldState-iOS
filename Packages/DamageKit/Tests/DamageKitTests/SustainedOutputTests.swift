import XCTest
@testable import DamageKit

final class SustainedOutputTests: XCTestCase {
    func testOutputKeepsRunningAfterTargetDiesButLayersStop() throws {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1)
        let result = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1, options: Options(window: 3)
        ))
        let output = result.attacks[0]

        // t=0, 1, 2 三发都属于 3 秒射击窗口；这不是把一发打死的 100 再除以 3。
        XCTAssertEqual(output.shots, 3, accuracy: 1e-12)
        XCTAssertEqual(output.directDamage, 300, accuracy: 1e-9)
        XCTAssertEqual(output.dps, 100, accuracy: 1e-9)
        XCTAssertEqual(output.targetDirectDamage, 300, accuracy: 1e-9)
        XCTAssertEqual(output.targetDotDamage, 0, accuracy: 1e-9)
        XCTAssertEqual(output.targetDps, 100, accuracy: 1e-9)
        let health = try XCTUnwrap(output.layers.first { $0.layer == .health })
        XCTAssertEqual(health.damage, 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(health.ttk), 0, accuracy: 1e-9)
    }

    func testTargetDpsIncludesTargetSideViralWithoutChangingRawDps() {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 10, reloadTime: 0)
        let enemy = Enemy(name: "E", faction: "Neutral", baseLevel: 1, health: 1e9)
        let result = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            options: Options(window: 3, externalViralStacks: 1)
        ))
        let output = result.attacks[0]

        XCTAssertEqual(output.dps, 100, accuracy: 1e-9)
        XCTAssertEqual(output.targetDirectDamage, 600, accuracy: 1e-9)
        XCTAssertEqual(output.targetDps, 200, accuracy: 1e-9)
    }
}
