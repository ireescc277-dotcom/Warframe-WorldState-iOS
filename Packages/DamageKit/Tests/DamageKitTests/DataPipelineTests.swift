import XCTest
@testable import DamageKit

/// 输入数据、装配约束和文件查找的回归测试。
/// 这些都是公式进入模拟器之前必须保持确定性的边界。
final class DataPipelineTests: XCTestCase {

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DamageKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DamageKit
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
    }

    private static var dataRoot: URL {
        packageRoot.appendingPathComponent("server/site")
    }

    func testEnemyRoundTripsThroughItsOwnCodableRepresentation() throws {
        var original = Enemy(name: "Inline", faction: "Neutral", baseLevel: 7,
                             health: 100, shield: 25, armor: 50, overguard: 75,
                             innateDR: ["health": 0.1], statusImmune: ["heat", "viral"])
        original.elemRes = ["heat": 0.8]
        original.maxProcStacks = 4
        original.eximusDisabled = true
        original.showPartyCount = true

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Enemy.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }

    func testEnemyAlsoAcceptsPlainInlineNumbers() throws {
        let json = """
        {
          "name": "Inline", "faction": "Neutral", "b_lvl": 1,
          "health": 100, "shield": 20, "armor": 30, "overguard": 40,
          "immun": { "status": ["heat"] }, "showPartyCount": true
        }
        """.data(using: .utf8)!

        let enemy = try JSONDecoder().decode(Enemy.self, from: json)
        XCTAssertEqual(enemy.health, 100)
        XCTAssertEqual(enemy.shield, 20)
        XCTAssertEqual(enemy.armor, 30)
        XCTAssertEqual(enemy.overguard, 40)
        XCTAssertEqual(enemy.statusImmune, ["heat"])
        XCTAssertTrue(enemy.showPartyCount)
    }

    func testWebsiteEnemyPartyCapabilitySurvivesDataStoreDecoding() throws {
        let store = DataStore(root: Self.dataRoot)
        let demolisher = try store.enemy(named: "Demolisher Anti MOA")

        XCTAssertTrue(demolisher.showPartyCount)
        XCTAssertEqual(demolisher.health, 2_000)
        XCTAssertEqual(demolisher.shield, 800)
    }

    func testCanonicalServerSiteWorksWithoutGeneratedBrowserIndex() throws {
        // A clean checkout intentionally has no ignored `web/app/site` bundle.
        // The CLI and CI must therefore be able to use the checked-in website
        // source directly, including its weapons.json dictionary manifest.
        XCTAssertTrue(DataStore.hasRequiredData(at: Self.dataRoot))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: Self.dataRoot.appendingPathComponent("weapons-list.json").path
        ))
        XCTAssertEqual(DataStore.defaultRoot(relativeTo: Self.packageRoot), Self.dataRoot)

        let store = DataStore(root: Self.dataRoot)
        let names = try store.weaponNames()
        XCTAssertTrue(names.contains("Kuva Tonkor"))
        XCTAssertTrue(names.contains("Laetum"))

        let packageDirectory = Self.packageRoot.appendingPathComponent("Packages/DamageKit")
        XCTAssertEqual(
            try XCTUnwrap(DataStore.discoverRoot(startingAt: packageDirectory)).standardizedFileURL,
            Self.dataRoot.standardizedFileURL
        )
    }

    func testForceProcsDecodeFromBothObservedShapes() throws {
        let common = """
        "name":"A","speed":1,"crit_chance":0,"crit_mult":1,
        "status_chance":0,"damage":{"impact":1}
        """
        let topLevel = "{\(common),\"force_procs\":[\"impact\"]}".data(using: .utf8)!
        let nested = "{\(common),\"unique\":{\"force_procs\":[\"heat\",\"slash\"]}}"
            .data(using: .utf8)!

        XCTAssertEqual(try JSONDecoder().decode(Attack.self, from: topLevel).forceProcs, ["impact"])
        XCTAssertEqual(try JSONDecoder().decode(Attack.self, from: nested).forceProcs, ["heat", "slash"])
    }

    func testDataStoreFindsPunctuationNormalizedWeaponNamesAndDecodesThalys() throws {
        let store = DataStore(root: Self.dataRoot)
        XCTAssertEqual(try store.weapon(named: "Ack & Brunt").name, "Ack & Brunt")
        XCTAssertEqual(try store.weapon(named: "Lizzie (Temple)").name, "Lizzie (Temple)")

        let thalys = try store.weapon(named: "Thalys")
        let slam = try XCTUnwrap(thalys.attacks.first { $0.name == "Slam" })
        XCTAssertEqual(slam.forceProcs, ["impact"])
    }

    private func resolve(_ mods: [String]) -> ResolvedAttack {
        let attack = Attack(name: "Hit", speed: 10, critChance: 0, critMultiplier: 1,
                            statusChance: 0, damage: [.impact: 100])
        var weapon = Weapon(name: "Test Rifle", attacks: [attack])
        weapon.categories = ["primary-rifle"]
        return BuildResolver(weapon: weapon, build: Build(mods: mods), options: Options(),
                             faction: .neutral).resolve(attack: attack)
    }

    func testConflictingModsDoNotEnterTheAggregate() {
        let resolved = resolve(["Serration", "Amalgam Serration"])
        XCTAssertEqual(resolved.totalDamage, 265, accuracy: 1e-9)
        XCTAssertTrue(resolved.notes.contains("互斥 mod 被忽略: Amalgam Serration"))
    }

    func testDuplicateModsDoNotEnterTheAggregateTwice() {
        let resolved = resolve(["Serration", "serration"])
        XCTAssertEqual(resolved.totalDamage, 265, accuracy: 1e-9)
        XCTAssertTrue(resolved.notes.contains("重复 mod 被忽略: Serration"))
    }

    func testSetSpeedToDefaultLocksFireRate() {
        let resolved = resolve(["Vile Acceleration", "Semi-Rifle Cannonade"])
        XCTAssertEqual(resolved.fireRate, 10, accuracy: 1e-9)
    }
}
