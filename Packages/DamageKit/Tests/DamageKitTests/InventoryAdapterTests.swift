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

    func testDEStyleRankedAndArcaneSlotsReachSwiftSlottedBuild() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("damagekit-ranked-adapter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshotURL = root.appendingPathComponent("snapshot.json")
        let gameDataURL = root.appendingPathComponent("gamedata.json")
        let snapshot: [String: Any] = [
            "Pistols": [[
                "ItemId": ["$oid": "test-lex"],
                "ItemType": "/Lotus/Weapons/Test/LexPrime",
                "Configs": [[
                    "Upgrades": [
                        "mod-gunslinger-r4",
                        "mod-hush-r0",
                        "", "", "", "", "", "", "",
                        "arcane-merciless-r5"
                    ]
                ]]
            ]],
            "Upgrades": [
                [
                    "ItemId": ["$oid": "mod-gunslinger-r4"],
                    "ItemType": "/Lotus/Upgrades/Mods/Pistol/WeaponFireRateMod",
                    "UpgradeFingerprint": "{\"lvl\":4}"
                ],
                [
                    "ItemId": ["$oid": "mod-hush-r0"],
                    "ItemType": "/Lotus/Upgrades/Mods/Rifle/WeaponNoiseReductionMod",
                    "UpgradeFingerprint": "{\"lvl\":0}"
                ],
                [
                    "ItemId": ["$oid": "arcane-merciless-r5"],
                    "ItemType": "/Lotus/Upgrades/CosmeticEnhancers/Offensive/SecondaryDamageOnKill",
                    "UpgradeFingerprint": "{\"lvl\":5}"
                ]
            ]
        ]
        let gameData: [String: Any] = [
            "weapons": [
                "/Lotus/Weapons/Test/LexPrime": ["n": "Lex Prime", "om": 1.0]
            ],
            "mods": [
                "/Lotus/Upgrades/Mods/Pistol/WeaponFireRateMod": [
                    "n": "Gunslinger",
                    "mx": 5,
                    "lv": [
                        ["+12% Fire Rate"],
                        ["+24% Fire Rate"],
                        ["+36% Fire Rate"],
                        ["+48% Fire Rate"],
                        ["+60% Fire Rate"],
                        ["+72% Fire Rate"]
                    ]
                ],
                "/Lotus/Upgrades/Mods/Rifle/WeaponNoiseReductionMod": [
                    "n": "Hush",
                    "mx": 3,
                    "lv": [
                        ["Reduces the chance an enemy will hear gunfire by 25%."],
                        ["Reduces the chance an enemy will hear gunfire by 50%."],
                        ["Reduces the chance an enemy will hear gunfire by 75%."],
                        ["Reduces the chance an enemy will hear gunfire by 100%."]
                    ]
                ]
            ],
            "rivenTags": [:]
        ]
        try JSONSerialization.data(withJSONObject: snapshot).write(to: snapshotURL)
        try JSONSerialization.data(withJSONObject: gameData).write(to: gameDataURL)

        let imported = try InventoryAdapter(snapshotURL: snapshotURL, gameDataURL: gameDataURL)
            .resolve(OwnedWeaponReference(snapshot: "unit", weaponId: "test-lex"),
                     using: DataStore(root: Self.dataRoot))

        XCTAssertEqual(imported.build.slottedMods.count, 3)
        XCTAssertEqual(imported.build.slottedMods[0].slot, 0)
        XCTAssertEqual(imported.build.slottedMods[0].name, "Gunslinger")
        XCTAssertEqual(try XCTUnwrap(imported.build.slottedMods[0].actionScale), 60.0 / 72.0,
                       accuracy: 1e-12)
        // Gun Arcane stored at raw DE index 9 maps to DamageKit Arcane slot 10.
        XCTAssertEqual(imported.build.slottedMods[2].slot, 10)
        XCTAssertEqual(imported.build.slottedMods[2].name, "Secondary Merciless")

        let resolved = BuildResolver(weapon: imported.weapon, build: imported.build,
                                     options: Options(), faction: .neutral)
            .resolve(attack: imported.weapon.attacks[0])
        // Base Lex Prime speed 2.08 -> 2.08 * (1 + 0.60) = 3.328 (not max 72%).
        XCTAssertEqual(resolved.fireRate, imported.weapon.attacks[0].speed * 1.60, accuracy: 1e-9)
    }

    func testDEStyleRankedConditionalStepScaleAndUnprovenRankRejection() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("damagekit-cond-adapter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshotURL = root.appendingPathComponent("snapshot.json")
        let gameDataURL = root.appendingPathComponent("gamedata.json")
        let snapshot: [String: Any] = [
            "Melee": [
                [
                    "ItemId": ["$oid": "test-skana-good"],
                    "ItemType": "/Lotus/Weapons/Test/Skana",
                    "Configs": [["Upgrades": ["exposure-r4"]]]
                ],
                [
                    "ItemId": ["$oid": "test-skana-bad"],
                    "ItemType": "/Lotus/Weapons/Test/Skana",
                    "Configs": [["Upgrades": ["unproven-r2"]]]
                ]
            ],
            "Upgrades": [
                [
                    "ItemId": ["$oid": "exposure-r4"],
                    "ItemType": "/Lotus/Upgrades/CosmeticEnhancers/Offensive/CorrosiveMeleePerAbilityCast",
                    "UpgradeFingerprint": "{\"lvl\":4}"
                ],
                [
                    "ItemId": ["$oid": "unproven-r2"],
                    "ItemType": "/Lotus/Upgrades/Mods/Melee/UnprovenCrit",
                    "UpgradeFingerprint": "{\"lvl\":2}"
                ]
            ]
        ]
        let gameData: [String: Any] = [
            "weapons": ["/Lotus/Weapons/Test/Skana": ["n": "Skana", "om": 1.0]],
            "mods": [
                "/Lotus/Upgrades/CosmeticEnhancers/Offensive/CorrosiveMeleePerAbilityCast": [
                    "n": "Melee Exposure",
                    "mx": 5,
                    "lv": [
                        ["On Ability Cast: Gain +10% Corrosive Damage for 25s. Stacks up to 240%."],
                        ["On Ability Cast: Gain +20% Corrosive Damage for 25s. Stacks up to 240%."],
                        ["On Ability Cast: Gain +30% Corrosive Damage for 25s. Stacks up to 240%."],
                        ["On Ability Cast: Gain +40% Corrosive Damage for 25s. Stacks up to 240%."],
                        ["On Ability Cast: Gain +50% Corrosive Damage for 25s. Stacks up to 240%."],
                        ["On Ability Cast: Gain +60% Corrosive Damage for 25s. Stacks up to 240%."]
                    ]
                ],
                "/Lotus/Upgrades/Mods/Melee/UnprovenCrit": [
                    "n": "True Steel",
                    "mx": 5,
                    "lv": []
                ]
            ],
            "rivenTags": [:]
        ]
        try JSONSerialization.data(withJSONObject: snapshot).write(to: snapshotURL)
        try JSONSerialization.data(withJSONObject: gameData).write(to: gameDataURL)

        let adapter = InventoryAdapter(snapshotURL: snapshotURL, gameDataURL: gameDataURL)
        let store = DataStore(root: Self.dataRoot)

        let good = try adapter.resolve(OwnedWeaponReference(snapshot: "unit", weaponId: "test-skana-good"),
                                       using: store)
        XCTAssertEqual(good.build.slottedMods.first?.name, "Melee Exposure")
        XCTAssertEqual(try XCTUnwrap(good.build.slottedMods.first?.conditionalStepScale),
                       50.0 / 60.0, accuracy: 1e-12)

        XCTAssertThrowsError(
            try adapter.resolve(OwnedWeaponReference(snapshot: "unit", weaponId: "test-skana-bad"),
                                using: store)
        ) { error in
            guard case InventoryAdapterError.unsupportedModRank(let name, 2, 5) = error else {
                return XCTFail("Expected unsupportedModRank, got \(error)")
            }
            XCTAssertEqual(name, "True Steel")
        }
    }

    func testVinquibusModesAndArchgunAtmoModeResolveToSiteWeapons() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("inventory-adapter-weapons-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshotURL = dir.appendingPathComponent("snapshot.json")
        let gameDataURL = dir.appendingPathComponent("gamedata.json")
        let snapshot: [String: Any] = [
            "LongGuns": [[
                "ItemId": ["$oid": "test-vinq-rifle"],
                "ItemType": "/Lotus/Weapons/Tenno/Bayonet/TnBayonetRifleWeapon",
                "Configs": [["Upgrades": []]]
            ]],
            "Melee": [[
                "ItemId": ["$oid": "test-vinq-melee"],
                "ItemType": "/Lotus/Weapons/Tenno/Bayonet/TnBayonetMeleeWeapon",
                "Configs": [["Upgrades": []]]
            ]],
            "SpaceGuns": [[
                "ItemId": ["$oid": "test-mausolon"],
                "ItemType": "/Lotus/Weapons/Tenno/Archwing/Primary/ThanoTechArchLongGun/ThanoTechLongGun",
                "Configs": [["Upgrades": []]]
            ]],
            "Upgrades": []
        ]
        let gameData: [String: Any] = [
            "weapons": [
                "/Lotus/Weapons/Tenno/Bayonet/TnBayonetRifleWeapon": ["n": "Vinquibus", "om": 1.2],
                "/Lotus/Weapons/Tenno/Archwing/Primary/ThanoTechArchLongGun/ThanoTechLongGun": ["n": "Mausolon", "om": 0.8]
            ],
            "mods": [:],
            "rivenTags": [:]
        ]
        try JSONSerialization.data(withJSONObject: snapshot).write(to: snapshotURL)
        try JSONSerialization.data(withJSONObject: gameData).write(to: gameDataURL)

        let adapter = InventoryAdapter(snapshotURL: snapshotURL, gameDataURL: gameDataURL)
        let store = DataStore(root: Self.dataRoot)

        let rifle = try adapter.resolve(OwnedWeaponReference(snapshot: "unit", weaponId: "test-vinq-rifle"),
                                        using: store)
        XCTAssertEqual(rifle.weapon.name, "Vinquibus (Rifle)")

        let melee = try adapter.resolve(OwnedWeaponReference(snapshot: "unit", weaponId: "test-vinq-melee"),
                                        using: store)
        XCTAssertEqual(melee.weapon.name, "Vinquibus (Melee)")

        let mausolon = try adapter.resolve(OwnedWeaponReference(snapshot: "unit", weaponId: "test-mausolon"),
                                           using: store)
        XCTAssertEqual(mausolon.weapon.name, "Mausolon (Atmo-mode)")
    }
}
