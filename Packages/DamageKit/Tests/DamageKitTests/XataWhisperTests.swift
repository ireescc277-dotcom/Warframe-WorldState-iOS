import XCTest
@testable import DamageKit

final class XataWhisperTests: XCTestCase {
    private let enemy = Enemy(name: "Neutral target", faction: "Neutral", health: 1e12, armor: 0)

    private func evaluate(_ effects: ScenarioEffects) -> AttackResult {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = Weapon(name: "Test rifle", attacks: [attack], magazineSize: 10,
                            reloadTime: 0, category: "primary")
        return Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            options: Options(window: 1, scenarioEffects: effects)
        )).attacks[0]
    }

    func testXataCreatesAnIndependentVoidHitWithoutChangingWeaponVector() throws {
        let output = evaluate(ScenarioEffects(values: [.xata: 0.5]))

        XCTAssertEqual(output.targetDirectDamage, 150, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(output.targetByType[DamageType.impact.rawValue]), 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(output.targetByType[DamageType.void.rawValue]), 50, accuracy: 1e-9)
    }

    func testXataUsesTheWebsiteFactionDoubleDipInsteadOfAnOrdinaryElementMultiplier() throws {
        let output = evaluate(ScenarioEffects(values: [.roar: 0.3, .xata: 0.5]))

        // Ordinary Impact receives Roar once: 100 × 1.3.  Xata's distinct
        // Void instance receives it twice: 100 × 0.5 × 1.3².
        XCTAssertEqual(try XCTUnwrap(output.targetByType[DamageType.impact.rawValue]), 130, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(output.targetByType[DamageType.void.rawValue]), 84.5, accuracy: 1e-9)
        XCTAssertEqual(output.targetDirectDamage, 214.5, accuracy: 1e-9)
    }
}
