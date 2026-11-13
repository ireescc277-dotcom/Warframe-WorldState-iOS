import Foundation
import XCTest

@testable import WarframeWatch

@MainActor
final class NativeDamageCalculatorModelTests: XCTestCase {
    private func frame(
        id: String,
        name: String,
        abilityName: String,
        strengthBonus: Double = 0
    ) throws -> InventoryData.OwnedWarframe {
        let upgrade: [[String: Any]]
        if strengthBonus == 0 {
            upgrade = []
        } else {
            upgrade = [[
                "s": 0,
                "n": "Intensify",
                "st": [[
                    "l": "+\(Int(strengthBonus * 100))% Ability Strength",
                    "v": strengthBonus,
                    "k": "base",
                ]],
            ]]
        }
        let object: [String: Any] = [
            "id": id,
            "z": name,
            "a": [["o": 3, "n": abilityName]],
            "cfg": [["l": "A", "u": upgrade]],
            "sh": [],
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(InventoryData.OwnedWarframe.self, from: data)
    }

    func testSelfOnlyAbilityIsNeverExternalCandidate() throws {
        let saryn = try frame(id: "saryn", name: "Saryn", abilityName: "Toxic Lash")

        let selfCandidates = WarframeWeaponBuffResolver.candidates(
            for: saryn,
            configIndex: 0,
            audience: .selfOnly
        )
        let externalCandidates = WarframeWeaponBuffResolver.candidates(
            for: saryn,
            configIndex: 0,
            audience: .selfAndAllies
        )

        XCTAssertEqual(selfCandidates.map(\.id), ["scenario-toxic-lash"])
        XCTAssertTrue(externalCandidates.isEmpty)
    }

    func testExternalBuffUsesCastersOwnConfigurationStrength() throws {
        let current = try frame(id: "current", name: "Current", abilityName: "Toxic Lash")
        let ally = try frame(
            id: "ally",
            name: "Rhino",
            abilityName: "Roar",
            strengthBonus: 0.30
        )

        let roar = try XCTUnwrap(WarframeWeaponBuffResolver.candidates(
            for: ally,
            configIndex: 0,
            audience: .selfAndAllies
        ).first(where: { $0.id == "scenario-roar" }))
        let resolved = WarframeWeaponBuffResolver.resolve(roar, caster: ally, configIndex: 0)
        let effectValue = try XCTUnwrap(resolved.scenarioEffect?.value)

        XCTAssertEqual(WarframeStrengthResolver.resolve(current, configIndex: 0).multiplier, 1)
        XCTAssertEqual(resolved.strength.multiplier, 1.30, accuracy: 0.000_001)
        XCTAssertEqual(effectValue, 0.65, accuracy: 0.000_001)
    }

    func testCurrentSelfBuffAndExternalSquadBuffAreBothRetained() throws {
        let current = try frame(id: "current", name: "Saryn", abilityName: "Toxic Lash")
        let ally = try frame(
            id: "ally",
            name: "Rhino",
            abilityName: "Roar",
            strengthBonus: 0.30
        )
        let model = NativeDamageCalculatorModel(
            initialOwnedWarframe: current,
            availableWarframes: [current, ally]
        )
        model.setCurrentWarframeBuff("scenario-toxic-lash", active: true)

        var draft = NativeExternalWarframeBuffDraft(casterID: ally.id)
        draft.candidateID = "scenario-roar"
        model.externalWarframeBuffs = [draft]

        // Toxic Lash is self-only, while this Roar comes from the other
        // caster's 130% Strength configuration. They are distinct active
        // effects and must coexist in the calculation input.
        XCTAssertEqual(model.resolvedScenarioEffects.value(for: .toxicLash), 0.30,
                       accuracy: 0.000_001)
        XCTAssertEqual(model.resolvedScenarioEffects.value(for: .roar), 0.65,
                       accuracy: 0.000_001)
    }

    func testCurrentFrameCannotRemainAnExternalCaster() throws {
        let current = try frame(id: "current", name: "Current", abilityName: "Toxic Lash")
        let ally = try frame(id: "ally", name: "Rhino", abilityName: "Roar")
        let model = NativeDamageCalculatorModel(
            initialOwnedWarframe: current,
            availableWarframes: [current, ally]
        )

        XCTAssertEqual(model.availableExternalWarframes.map(\.id), ["ally"])

        var draft = NativeExternalWarframeBuffDraft(casterID: ally.id)
        draft.candidateID = "scenario-roar"
        model.externalWarframeBuffs = [draft]
        XCTAssertEqual(model.externalCaster(for: draft)?.id, ally.id)

        model.selectCurrentWarframe(ally.id)

        XCTAssertEqual(model.currentWarframe?.id, ally.id)
        XCTAssertEqual(model.availableExternalWarframes.map(\.id), ["current"])
        XCTAssertNil(model.externalWarframeBuffs[0].casterID)
        XCTAssertNil(model.externalWarframeBuffs[0].candidateID)
        XCTAssertNil(model.externalCaster(for: model.externalWarframeBuffs[0]))
    }

    func testSameSquadBuffUsesStrongestSourceRatherThanDoubleCounting() throws {
        let current = try frame(
            id: "current",
            name: "Current Rhino",
            abilityName: "Roar",
            strengthBonus: 0.20
        )
        let ally = try frame(
            id: "ally",
            name: "Ally Rhino",
            abilityName: "Roar",
            strengthBonus: 0.30
        )
        let model = NativeDamageCalculatorModel(
            initialOwnedWarframe: current,
            availableWarframes: [current, ally]
        )
        model.setCurrentWarframeBuff("scenario-roar", active: true)

        var draft = NativeExternalWarframeBuffDraft(casterID: ally.id)
        draft.candidateID = "scenario-roar"
        model.externalWarframeBuffs = [draft]

        // Player Roar resolves to 50% * 1.20 = 60%; ally Roar resolves to
        // 50% * 1.30 = 65%.  These are the same non-stacking squad effect, so
        // DamageKit receives the stronger 65% value, not their 125% sum.
        XCTAssertEqual(model.resolvedScenarioEffects.value(for: .roar), 0.65, accuracy: 0.000_001)
    }

    func testNonDamageInventoryCardStaysVisibleWithoutBecomingAnUnresolvedFormula() throws {
        let json = """
        {
          "l": "A",
          "s": ["Hush"],
          "sm": [{"r": 0, "m": 3}],
          "u": [],
          "nd": [{
            "s": 0,
            "n": "Hush",
            "m": 3,
            "why": "只降低敌人听到枪声的概率；不直接改变本次命中的伤害数值"
          }],
          "exact": true,
          "issues": []
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(InventoryData.OwnedWeapon.Config.self, from: json)

        XCTAssertTrue(config.isExactImport)
        XCTAssertTrue(config.unresolvedUpgrades.isEmpty)
        XCTAssertEqual(config.normalizedSlots[0], "Hush")
        XCTAssertEqual(config.nonDamageUpgrades.count, 1)
        XCTAssertEqual(config.nonDamageUpgrades[0].name, "Hush")
        XCTAssertNil(config.nonDamageUpgrades[0].rank)
        XCTAssertEqual(config.nonDamageUpgrades[0].maxRank, 3)
    }

    func testImportedCompletedElementRivenStaysInTheElementGroup() throws {
        let json = """
        {
          "name": "Corican",
          "elements": {"corrosive": 1.0969}
        }
        """.data(using: .utf8)!
        let imported = try JSONDecoder().decode(
            InventoryData.OwnedWeapon.ImportedRiven.self,
            from: json
        )

        var draft = NativeRivenDraft(imported: imported)
        XCTAssertTrue(draft.selectedStats.contains(.corrosive))
        XCTAssertEqual(draft.value(for: .corrosive), 109.69, accuracy: 0.000_001)
        XCTAssertEqual(draft.resolved?.elements?["corrosive"] ?? 0, 1.0969, accuracy: 0.000_001)

        draft.setValue(87.5, for: .gas)
        XCTAssertTrue(draft.selectedStats.contains(.gas))
        XCTAssertEqual(draft.resolved?.elements?["gas"] ?? 0, 0.875, accuracy: 0.000_001)
    }

    func testImportedRivenTimingStatsAndDisplayOnlyTermsStaySeparate() throws {
        let json = """
        {
          "name": "Scopebin",
          "magazineSize": 0.42,
          "meleeComboEfficiency": 0.50,
          "displayOnly": [{
            "tag": "WeaponZoomFovMod",
            "label": "变焦",
            "value": 0.18
          }]
        }
        """.data(using: .utf8)!
        let imported = try JSONDecoder().decode(
            InventoryData.OwnedWeapon.ImportedRiven.self,
            from: json
        )

        let draft = NativeRivenDraft(imported: imported)
        XCTAssertTrue(draft.selectedStats.contains(.magazineSize))
        XCTAssertTrue(draft.selectedStats.contains(.meleeComboEfficiency))
        XCTAssertEqual(draft.value(for: .magazineSize), 42, accuracy: 0.000_001)
        XCTAssertEqual(draft.value(for: .meleeComboEfficiency), 50, accuracy: 0.000_001)
        XCTAssertEqual(draft.resolved?.magazineSize ?? 0, 0.42, accuracy: 0.000_001)
        XCTAssertEqual(draft.resolved?.meleeComboEfficiency ?? 0, 0.50, accuracy: 0.000_001)
        XCTAssertEqual(draft.displayOnlyEffects.map(\.tag), ["WeaponZoomFovMod"])
        XCTAssertEqual(draft.displayOnlyEffects.map(\.value), [0.18])
    }
}
