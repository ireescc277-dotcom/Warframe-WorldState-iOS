import XCTest
@testable import DamageKit

final class ToxicLashTests: XCTestCase {
    private let enemy = Enemy(name: "Neutral target", faction: "Neutral", health: 1e12, armor: 0)

    private func evaluate(category: String = "primary", effects: ScenarioEffects) -> AttackResult {
        let attack = Attack(name: "Hit", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        let weapon = Weapon(name: "Test weapon", attacks: [attack], magazineSize: 1,
                            reloadTime: 100, category: category)
        return Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            options: Options(window: 8, scenarioEffects: effects)
        )).attacks[0]
    }

    func testToxicLashAddsAnIndependentRoundedDirectHitAndSevenTicks() {
        let output = evaluate(effects: ScenarioEffects(values: [.toxicLash: 0.3]))

        XCTAssertEqual(output.shots, 1, accuracy: 1e-12)
        XCTAssertEqual(output.targetDirectDamage, 130, accuracy: 1e-9)
        XCTAssertEqual(output.targetDotDamage, 105, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(output.targetByType[DamageType.toxin.rawValue]), 135, accuracy: 1e-9)
    }

    func testToxicLashUsesItsMeleeCoefficientInTheCore() {
        let output = evaluate(category: "Melee", effects: ScenarioEffects(values: [.toxicLash: 0.3]))

        XCTAssertEqual(output.targetDirectDamage, 160, accuracy: 1e-9)
        XCTAssertEqual(output.targetDotDamage, 210, accuracy: 1e-9)
    }

    func testToxicLashFactionStagesAndPerInstanceRoundingAreSeparateFromRoar() {
        let output = evaluate(effects: ScenarioEffects(values: [.roar: 0.3, .toxicLash: 0.3]))

        // Ordinary hit: 100 × 1.3.  Lash direct: ceil(100 × 1.3² × 0.3).
        // Lash tick: ceil(100 × 1.3³ × 0.3 × 0.5), seven times.
        XCTAssertEqual(output.targetDirectDamage, 181, accuracy: 1e-9)
        XCTAssertEqual(output.targetDotDamage, 231, accuracy: 1e-9)
    }
}
