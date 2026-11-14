import Foundation
import XCTest
@testable import DamageKit

/// Regression cases for the checked-in warframe-damage target implementation.
final class EnemyScalingFormulaTests: XCTestCase {
    func testWebsiteOverguardUsesEnemyBaseLevel() {
        // Website `getEnemyOverguard`: q is target level minus enemy base level.
        let enemy = Enemy(name: "E", faction: "Grineer", baseLevel: 30, health: 100)
        let profile = EnemyProfile(enemy: enemy, level: 50, options: Options(eximus: true))
        let expected = 12 * (1 + 0.0015 * pow(20.0, 4.0))

        XCTAssertEqual(profile.overguard, expected, accuracy: 1e-6)
    }

    func testWebsiteEximusCurveReplacesNormalFactionCurve() {
        // At level 30, the website does not use Corpus's ordinary curve after
        // making an Eximus. It directly rounds each independent Eximus branch.
        let enemy = Enemy(name: "E", faction: "Corpus", baseLevel: 1,
                          health: 100, shield: 100, armor: 100)
        let profile = EnemyProfile(enemy: enemy, level: 30, options: Options(eximus: true))
        let q = 29.0
        let band = 1.25 + 0.125 * 5
        let expectedHealth = (100 * band * (1 + 0.015 * pow(q, 2))).rounded()
        let expectedShield = (100 * band * (1 + 0.02 * pow(q, 1.75))).rounded()
        let expectedArmor = (100 * (1 + 0.0125 * 5)
            * (1 + 0.005 * pow(q, 1.75))).rounded()

        XCTAssertEqual(profile.health, expectedHealth, accuracy: 1e-5)
        XCTAssertEqual(profile.shield, expectedShield, accuracy: 1e-5)
        XCTAssertEqual(profile.armor, expectedArmor, accuracy: 1e-5)
    }

    func testWebsiteUsesRawFactionForTargetCurve() {
        let enemy = Enemy(name: "A", faction: "Anarch", baseLevel: 1, health: 100)
        let profile = EnemyProfile(enemy: enemy, level: 100, options: Options())
        let q = 99.0
        let websiteDefaultLateHealth = 1 + 24 * sqrt(q) * sqrt(5) / 5
        let expected = ((100 * websiteDefaultLateHealth * 100).rounded() / 100).rounded()

        XCTAssertEqual(profile.faction.canonical, "Anarchs")
        XCTAssertEqual(profile.health, expected, accuracy: 1e-5)
    }

    func testPartyCountOnlyScalesHealthForEnemiesThatExposeIt() {
        let eligible = Enemy(name: "Demolisher", faction: "Corpus", baseLevel: 1,
                             health: 2_000, shield: 800, armor: 100,
                             showPartyCount: true)
        let ineligible = Enemy(name: "Crewman", faction: "Corpus", baseLevel: 1,
                               health: 2_000, shield: 800, armor: 100)
        let options = Options(squadSize: 4)
        let eligibleProfile = EnemyProfile(enemy: eligible, level: 100, options: options)
        let singleProfile = EnemyProfile(enemy: eligible, level: 100, options: Options(squadSize: 1))
        let ineligibleProfile = EnemyProfile(enemy: ineligible, level: 100, options: options)
        let ineligibleSingle = EnemyProfile(enemy: ineligible, level: 100, options: Options(squadSize: 1))

        XCTAssertEqual(eligibleProfile.health, singleProfile.health * 3, accuracy: 1e-6)
        XCTAssertEqual(eligibleProfile.shield, singleProfile.shield, accuracy: 1e-6)
        XCTAssertEqual(eligibleProfile.armor, singleProfile.armor, accuracy: 1e-6)
        XCTAssertEqual(ineligibleProfile.health, ineligibleSingle.health, accuracy: 1e-6)
        XCTAssertEqual(EnemyProfile.partyHealthMultiplier(squadSize: 2), 1.5, accuracy: 0)
        XCTAssertEqual(EnemyProfile.partyHealthMultiplier(squadSize: 3), 2, accuracy: 0)
        XCTAssertEqual(EnemyProfile.partyHealthMultiplier(squadSize: 4), 3, accuracy: 0)
    }

    func testPublishedSubfactionDamageMatrices() {
        let kuva = FactionProfile.resolve(rawFaction: "Kuva Grineer")
        XCTAssertEqual(kuva.multiplier(for: .impact), 1.5, accuracy: 1e-12)
        XCTAssertEqual(kuva.multiplier(for: .corrosive), 1.5, accuracy: 1e-12)
        XCTAssertEqual(kuva.multiplier(for: .heat), 0.5, accuracy: 1e-12)

        let amalgam = FactionProfile.resolve(rawFaction: "Corpus Amalgam")
        XCTAssertEqual(amalgam.multiplier(for: .electricity), 1.5, accuracy: 1e-12)
        XCTAssertEqual(amalgam.multiplier(for: .magnetic), 1.5, accuracy: 1e-12)
        XCTAssertEqual(amalgam.multiplier(for: .blast), 0.5, accuracy: 1e-12)

        let deimos = FactionProfile.resolve(rawFaction: "Deimos Infested")
        XCTAssertEqual(deimos.multiplier(for: .blast), 1.5, accuracy: 1e-12)
        XCTAssertEqual(deimos.multiplier(for: .gas), 1.5, accuracy: 1e-12)
        XCTAssertEqual(deimos.multiplier(for: .viral), 0.5, accuracy: 1e-12)

        let scaldra = FactionProfile.resolve(rawFaction: "Scaldra")
        XCTAssertEqual(scaldra.multiplier(for: .impact), 1.5, accuracy: 1e-12)
        XCTAssertEqual(scaldra.multiplier(for: .gas), 0.5, accuracy: 1e-12)

        let techrot = FactionProfile.resolve(rawFaction: "Techrot")
        XCTAssertEqual(techrot.multiplier(for: .gas), 1.5, accuracy: 1e-12)
        XCTAssertEqual(techrot.multiplier(for: .cold), 0.5, accuracy: 1e-12)

        let anarch = FactionProfile.resolve(rawFaction: "Anarch")
        XCTAssertEqual(anarch.multiplier(for: .impact), 1.5, accuracy: 1e-12)
        XCTAssertEqual(anarch.multiplier(for: .electricity), 1.5, accuracy: 1e-12)
        XCTAssertEqual(anarch.multiplier(for: .radiation), 0.5, accuracy: 1e-12)
    }

    private static var dataRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("server/site")
    }

    func testCorruptedHeavyGunnerUsesSourceBaseLevelEightAndJadeShadowsArmorClamp() throws {
        let store = DataStore(root: Self.dataRoot)
        let gunner = try store.enemy(named: "Corrupted Heavy Gunner")
        XCTAssertEqual(gunner.baseLevel, 8)
        XCTAssertEqual(gunner.health, 700, accuracy: 1e-9)
        XCTAssertEqual(gunner.armor, 500, accuracy: 1e-9)

        // At level 100 (`q = 100 - 8 = 92`), Orokin late health/armor curves put
        // armor well above 2700 before the Update 36 Jade Shadows cap clamps it to 2700 (90% DR).
        let l100Normal = EnemyProfile(enemy: gunner, level: 100, options: Options())
        let l100Steel = EnemyProfile(enemy: gunner, level: 100, options: Options(steelPath: true))
        let l145Eximus = EnemyProfile(enemy: gunner, level: 145,
                                      options: Options(steelPath: true, eximus: true))

        XCTAssertEqual(l100Normal.level, 100)
        XCTAssertEqual(l100Normal.armor, 2700, accuracy: 1e-9)
        XCTAssertEqual(l100Normal.armorDR, 0.9, accuracy: 1e-6)
        XCTAssertEqual(l100Steel.health, l100Normal.health * 2.5, accuracy: 5)
        XCTAssertEqual(l100Steel.armor, 2700, accuracy: 1e-9)
        XCTAssertGreaterThan(l145Eximus.overguard, 0)

        // Non-zero base armor is clamped up to the Jade Shadows floor of 200 at low level;
        // zero armor remains zero.
        let lowArmorEnemy = Enemy(name: "Low", faction: "Grineer", baseLevel: 1,
                                  health: 100, armor: 50)
        let unarmoredEnemy = Enemy(name: "Unarmored", faction: "Corpus", baseLevel: 1,
                                   health: 100, armor: 0)
        XCTAssertEqual(EnemyProfile(enemy: lowArmorEnemy, level: 1, options: Options()).armor,
                       200, accuracy: 1e-9)
        XCTAssertEqual(EnemyProfile(enemy: unarmoredEnemy, level: 1, options: Options()).armor,
                       0, accuracy: 1e-9)
    }

    func testWebsiteOverguardBoundaryAtQ44ToQ51() {
        // `websiteOverguard` switches from early (`1 + 0.0015 * q^4`) to late
        // (`1 + 260 * q^0.9`) at `q = 45`, because in `min.js` `eOGTrans` already
        // evaluates to the late curve across q = 45...50 and >50.
        let base = 12.0
        let q44 = EnemyProfile.websiteOverguard(base: base, level: 52, baseLevel: 8)
        let q45 = EnemyProfile.websiteOverguard(base: base, level: 53, baseLevel: 8)
        let q50 = EnemyProfile.websiteOverguard(base: base, level: 58, baseLevel: 8)
        let q51 = EnemyProfile.websiteOverguard(base: base, level: 59, baseLevel: 8)

        XCTAssertEqual(q44, base * (1 + 0.0015 * pow(44.0, 4)), accuracy: 1e-6)
        XCTAssertEqual(q45, base * (1 + 260.0 * pow(45.0, 0.9)), accuracy: 1e-6)
        XCTAssertEqual(q50, base * (1 + 260.0 * pow(50.0, 0.9)), accuracy: 1e-6)
        XCTAssertEqual(q51, base * (1 + 260.0 * pow(51.0, 0.9)), accuracy: 1e-6)
    }
}
