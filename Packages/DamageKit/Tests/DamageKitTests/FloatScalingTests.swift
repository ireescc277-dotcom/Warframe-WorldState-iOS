import Foundation
import XCTest
@testable import DamageKit

final class FloatScalingTests: XCTestCase {
    func testHighLevelCurveKeepsF32InterpolationAtEndpoint() {
        let curve = Rules.healthCurve(faction: "Corrupted")
        let actual = curve.multiplier(level: 999, baseLevel: 8)
        let q = Float(991)
        let f1 = Float(1) + Float(0.015) * powf(q, Float(2.1))
        let f2 = Float(1) + Float(10.7332) * powf(q, Float(0.685))
        let expected = Double(f1 + (f2 - f1) * Float(1))
        XCTAssertEqual(actual, expected, accuracy: 0)
        XCTAssertNotEqual(actual, Double(f2), "端点不能把完整 f32 插值缩写成 f2")
    }

    func testWebsiteHighLevelOverguardUsesEnemyBaseLevelAndDoubleCurve() {
        let q = 991.0 // Lv999 Corrupted Heavy Gunner has base level 8.
        let expected = 12 * (1 + 260 * pow(q, 0.9))
        let actual = EnemyProfile.websiteOverguard(base: 12, level: 999, baseLevel: 8)

        XCTAssertEqual(actual, expected, accuracy: 0)
    }
}
