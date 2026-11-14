import XCTest
@testable import DamageKit

final class MeleeExposureTests: XCTestCase {

    private func resolve(casts: Double, conditionalStepScale: Double? = nil) -> ResolvedAttack {
        let attack = Attack(name: "Strike", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "Melee", attacks: [attack], magazineSize: 0)
        weapon.categories = ["melee"]
        let build = Build(slottedMods: [
            SlottedMod(slot: 10, name: "Melee Exposure",
                       conditionalStepScale: conditionalStepScale)
        ])
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

    func testLowerRankMeleeExposureNeedsMoreCastsButKeepsTheSameCap() {
        // The source record for rank 4 says +50% per ability cast while the
        // rank-5 card says +60%; both explicitly retain a +240% cap.  Thus
        // four casts are +200%, and the fifth reaches (rather than lowers)
        // the normal full-rank cap.
        let rankFourAfterFourCasts = resolve(casts: 4, conditionalStepScale: 5.0 / 6.0)
        let rankFourAfterFiveCasts = resolve(casts: 5, conditionalStepScale: 5.0 / 6.0)
        let fullRankAfterFourCasts = resolve(casts: 4)

        XCTAssertEqual(rankFourAfterFourCasts.damage[.corrosive] ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(rankFourAfterFiveCasts.damage[.corrosive] ?? 0,
                       fullRankAfterFourCasts.damage[.corrosive] ?? 0,
                       accuracy: 1e-9)
        XCTAssertEqual(rankFourAfterFiveCasts.damage[.corrosive] ?? 0, 240.625, accuracy: 1e-9)
    }

    func testRankOneMeleeExposureReachesTheUnchangedCapOnTheTwelfthCast() {
        // The equipped account card is rank 1: its source text says +20% per
        // cast, versus +60% at rank 5, while both ranks state a +240% cap.
        let rankOneAfterElevenCasts = resolve(casts: 11, conditionalStepScale: 1.0 / 3.0)
        let rankOneAfterTwelveCasts = resolve(casts: 12, conditionalStepScale: 1.0 / 3.0)
        let fullRankAfterFourCasts = resolve(casts: 4)

        XCTAssertLessThan(rankOneAfterElevenCasts.damage[.corrosive] ?? 0,
                          fullRankAfterFourCasts.damage[.corrosive] ?? 0)
        XCTAssertEqual(rankOneAfterTwelveCasts.damage[.corrosive] ?? 0,
                       fullRankAfterFourCasts.damage[.corrosive] ?? 0,
                       accuracy: 1e-9)
    }
}
