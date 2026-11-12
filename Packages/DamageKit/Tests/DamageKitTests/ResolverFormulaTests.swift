import XCTest
@testable import DamageKit

final class ResolverFormulaTests: XCTestCase {
    private let neutral = FactionProfile.neutral

    private static var siteDataRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DamageKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DamageKit
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("web/app/site")
    }

    func testDirectComponentsUseModdedBaseOverThirtyTwoQuantization() {
        let attack = Attack(name: "Quantized", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 1, .puncture: 0.02])
        let weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0)
        let resolved = BuildResolver(weapon: weapon, build: Build(), options: Options(), faction: neutral)
            .resolve(attack: attack)

        // The mission grid is Modded Base / 32, evaluated as f32.  The direct
        // vector therefore differs from the unquantized source vector, while
        // the DOT seed remains the unquantized Modded Base Damage.
        let scale = Float(1.02) / 32
        XCTAssertEqual(resolved.damage[.impact] ?? 0, Double(Float(31) * scale), accuracy: 1e-7)
        XCTAssertEqual(resolved.damage[.puncture] ?? 0, Double(scale), accuracy: 1e-7)
        XCTAssertEqual(resolved.dotBaseDamage, 1.02, accuracy: 1e-12)
    }

    func testBratonUsesSameRawSiteVectorButMissionThirtySecondGrid() throws {
        // The native data root is an exact mirror of server/site.  Keep this
        // regression tied to an actual weapon whose site calculator currently
        // takes a different /16 path, rather than an invented vector.
        let weapon = try DataStore(root: Self.siteDataRoot).weapon(named: "Braton")
        let attack = try XCTUnwrap(weapon.attacks.first { $0.name == "Normal Attack" })
        XCTAssertEqual(try XCTUnwrap(attack.damage[.impact]), 7.92, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(attack.damage[.puncture]), 7.92, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(attack.damage[.slash]), 8.16, accuracy: 1e-12)

        let resolved = BuildResolver(weapon: weapon, build: Build(), options: Options(), faction: neutral)
            .resolve(attack: attack)
        // 24 / 32 = 0.75. Every component is nearest to 11 grid steps:
        // 7.92 / .75 and 8.16 / .75 both round to 11, hence 8.25 each.
        XCTAssertEqual(resolved.dotBaseDamage, 24, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(resolved.damage[.impact]), 8.25, accuracy: 1e-7)
        XCTAssertEqual(try XCTUnwrap(resolved.damage[.puncture]), 8.25, accuracy: 1e-7)
        XCTAssertEqual(try XCTUnwrap(resolved.damage[.slash]), 8.25, accuracy: 1e-7)
    }

    func testMissionQuantizationAcrossRifleSecondaryShotgunAndMelee() throws {
        // The JS website probe locks the same four raw source vectors against
        // its /16 branch. Keep the Swift side independently tied to the
        // /32 mission grid for multiple weapon classes, rather than only
        // relying on Braton as a single illustrative weapon.
        let expected: [(weapon: String, values: [DamageType: Double])] = [
            (
                "Lex Prime",
                [.impact: 14.0625, .slash: 14.0625, .puncture: 121.875]
            ),
            (
                "Hek",
                [.impact: 11.71875, .slash: 14.0625, .puncture: 49.21875]
            ),
            (
                "Skana",
                [.impact: 18.75, .slash: 82.5, .puncture: 18.75]
            ),
        ]
        let store = DataStore(root: Self.siteDataRoot)
        for item in expected {
            let weapon = try store.weapon(named: item.weapon)
            let attack = try XCTUnwrap(weapon.attacks.first { $0.name == "Normal Attack" })
            let resolved = BuildResolver(weapon: weapon, build: Build(), options: Options(), faction: neutral)
                .resolve(attack: attack)
            for (type, value) in item.values {
                XCTAssertEqual(try XCTUnwrap(resolved.damage[type]), value, accuracy: 1e-7,
                               "\(item.weapon) \(type.rawValue) must use Modded Base / 32")
            }
        }
    }

    func testAcuityAppliesOnlyAtWeakPointAndUsesItsOwnPools() {
        let attack = Attack(name: "Acuity", speed: 1, critChance: 40, critMultiplier: 2,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "W", attacks: [attack], magazineSize: 1, reloadTime: 0)
        weapon.categories = ["primary-rifle"]
        let build = Build(mods: ["Primary Acuity"])

        var weakHead = Options()
        weakHead.headshot = true
        weakHead.weakPoint = true
        let applied = BuildResolver(weapon: weapon, build: build, options: weakHead, faction: neutral)
            .resolve(attack: attack)
        // 40% base CC × (1 + 350%) and a normal 3x head weak point plus
        // Acuity's 1.5 × 350% body-part term.
        XCTAssertEqual(applied.critChance, 1.8, accuracy: 1e-12)
        XCTAssertEqual(applied.headshotMultiplier, 8.25, accuracy: 1e-12)

        var ordinaryHead = Options()
        ordinaryHead.headshot = true
        let notApplied = BuildResolver(weapon: weapon, build: build, options: ordinaryHead, faction: neutral)
            .resolve(attack: attack)
        XCTAssertEqual(notApplied.critChance, 0.4, accuracy: 1e-12)
        XCTAssertEqual(notApplied.headshotMultiplier, 3, accuracy: 1e-12)
    }

    func testConditionalVulnerableStatusDamageIsReportedRatherThanMadePermanent() {
        let attack = Attack(name: "Hate", speed: 1, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.slash: 100])
        let weapon = Weapon(name: "Hate", attacks: [attack], magazineSize: 1, reloadTime: 0)
        let resolved = BuildResolver(weapon: weapon, build: Build(mods: ["Burning Hate"]),
                                     options: Options(), faction: neutral)
            .resolve(attack: attack)

        XCTAssertEqual(resolved.statusDamageBonus, 0, accuracy: 1e-12)
        XCTAssertTrue(resolved.notes.contains { $0.contains("vuln_status_damage") })
    }
}
