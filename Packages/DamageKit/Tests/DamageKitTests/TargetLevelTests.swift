import Foundation
import XCTest
@testable import DamageKit

final class TargetLevelTests: XCTestCase {
    func testExplicitTargetLevelIsNotRaisedTwiceOnSteelPath() {
        let enemy = Enemy(name: "E", faction: "Grineer", baseLevel: 8, health: 700, armor: 500)
        let profile = EnemyProfile(enemy: enemy, level: 999,
                                   options: Options(steelPath: true, eximus: true))
        let q = 991.0
        let eximusHealth = 6 * (1 + 24 * sqrt(5) / 5 * pow(q, 0.5))
        let expectedHealth = (2.5 * 700 * eximusHealth).rounded()
        let expectedOverguard = 12 * (1 + 260 * pow(q, 0.9))

        XCTAssertEqual(profile.health, expectedHealth, accuracy: 1e-4)
        XCTAssertEqual(profile.overguard, expectedOverguard, accuracy: 1e-4)
    }
}
