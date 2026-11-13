import Foundation
import XCTest
@testable import DamageKit

/// The app normally receives a normalized inventory payload, but the pure
/// Swift adapter remains the authority for reading a DE-shaped snapshot.
/// Keep one compact fixture here so a newly added Riven tag cannot become a
/// Python-only feature by accident.
final class InventoryAdapterTests: XCTestCase {

    private static var dataRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DamageKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DamageKit
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("server/site")
    }

    func testDEStyleRivenAmmoEfficiencyReachesTheSwiftBuild() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("damagekit-riven-ammo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshotURL = root.appendingPathComponent("snapshot.json")
        let gameDataURL = root.appendingPathComponent("gamedata.json")
        let fingerprint: [String: Any] = [
            "lvl": 8,
            "buffs": [["Tag": "WeaponAmmoEfficiency", "Value": 1_073_741_823]],
            "curses": []
        ]
        let fingerprintData = try JSONSerialization.data(withJSONObject: fingerprint)
        let fingerprintText = try XCTUnwrap(String(data: fingerprintData, encoding: .utf8))
        let snapshot: [String: Any] = [
            "LongGuns": [[
                "ItemId": ["$oid": "test-bramma"],
                "ItemType": "/Lotus/Weapons/Test/KuvaBramma",
                "Configs": [["Upgrades": ["test-riven"]]]
            ]],
            "Upgrades": [[
                "ItemId": ["$oid": "test-riven"],
                "ItemType": "/Lotus/Upgrades/Mods/Randomized/LotusRifleRandomModRare",
                "UpgradeFingerprint": fingerprintText
            ]]
        ]
        let gameData: [String: Any] = [
            "weapons": [
                "/Lotus/Weapons/Test/KuvaBramma": ["n": "Kuva Bramma", "om": 1.2]
            ],
            "mods": [:],
            "rivenTags": [
                "LotusRifleRandomModRare": [[
                    "tag": "WeaponAmmoEfficiency", "value": 0.01,
                    "prefix": "thrifty", "suffix": "rounds"
                ]]
            ]
        ]
        try JSONSerialization.data(withJSONObject: snapshot).write(to: snapshotURL)
        try JSONSerialization.data(withJSONObject: gameData).write(to: gameDataURL)

        let imported = try InventoryAdapter(snapshotURL: snapshotURL, gameDataURL: gameDataURL)
            .resolve(OwnedWeaponReference(snapshot: "unit", weaponId: "test-bramma"),
                     using: DataStore(root: Self.dataRoot))
        let riven = try XCTUnwrap(imported.build.riven)

        XCTAssertNotNil(riven.ammoEfficiency)
        XCTAssertGreaterThan(try XCTUnwrap(riven.ammoEfficiency), 0)
    }
}
