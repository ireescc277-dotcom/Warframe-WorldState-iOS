import XCTest
@testable import DamageKit

final class MeleeExposureTests: XCTestCase {

    private func resolve(casts: Double) -> ResolvedAttack {
        let attack = Attack(name: "Strike", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "Melee", attacks: [attack], magazineSize: 0)
        weapon.categories = ["melee"]
        let build = Build(slottedMods: [SlottedMod(slot: 10, name: "Melee Exposure")])
        let options = Options(conditionalModStacks: ["Melee Exposure": casts])
        return BuildResolver(weapon: weapon, build: build, options: options,
                             faction: .neutral).resolve(attack: attack)
    }

    func testMeleeExposureUsesAbilityCastsAsItsFourStepCondition() {
        let rule = ModLibrary.shared.conditionalRule(named: "Melee Exposure")
        let twoCasts = resolve(casts: 2)
        let fourCasts = resolve(casts: 4)

        // The source effect is +60% completed Corrosive damage per cast. It
        // therefore contributes +120% after two casts and +240% after four;
        // this is an independent Corrosive component, not a pair of ordinary
        // element cards that can be recombined by an arbitrary slot order.
        // The resolved direct vector is then quantized on the game's Modded
        // Base / 32 grid: 120 -> 118.75 and 240 -> 240.625 for this 100-base
        // fixture.
        XCTAssertEqual(twoCasts.damage[.impact] ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(twoCasts.damage[.corrosive] ?? 0, 118.75, accuracy: 1e-9)
        XCTAssertEqual(fourCasts.damage[.corrosive] ?? 0, 240.625, accuracy: 1e-9)
        XCTAssertEqual(rule?.maxStacks ?? -1, 4)
        XCTAssertEqual(rule?.inputLabel ?? "", "次技能施放")
    }

    func testMeleeExposureDoesNotApplyBeforeAnyAbilityCast() {
        let resolved = resolve(casts: 0)

        XCTAssertNil(resolved.damage[.corrosive])
        XCTAssertEqual(resolved.damage[.impact] ?? 0, 100, accuracy: 1e-9)
    }
}
