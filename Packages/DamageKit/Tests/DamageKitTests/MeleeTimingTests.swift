import XCTest
@testable import DamageKit

final class MeleeTimingTests: XCTestCase {
    func testSwordDefaultSequenceExpandsIntoWebsiteEquivalentContacts() {
        let attack = Attack(name: "Normal Attack", speed: 0.833, critChance: 0,
                            critMultiplier: 1, statusChance: 0, damage: [.slash: 120])
        var weapon = Weapon(name: "Skana", attacks: [attack], magazineSize: 1,
                            reloadTime: 0, category: "Melee")
        weapon.categories = ["weapon", "melee", "melee-sword"]
        weapon.compTags = ["SWORDS_STANCE", "SKANA"]
        let resolved = BuildResolver(weapon: weapon, build: Build(), options: Options(window: 20),
                                     faction: .grineer).resolveAll()[0]
        let enemy = Enemy(name: "E", faction: "Grineer", health: 1e12, armor: 0)
        let profile = EnemyProfile(enemy: enemy, level: 1, options: Options(window: 20))
        let schedule = WeaponSimulator(segments: [resolved], enemy: profile,
                                       options: Options(window: 20)).shotSchedule(for: resolved)

        // 20 seconds × four sword contacts / (1.9 / 0.833) = 35.07, rounded
        // to the 35 contact events used by the local website's default stance.
        XCTAssertEqual(schedule.count, 35)
        XCTAssertEqual(try XCTUnwrap(schedule.first).time, 0, accuracy: 1e-12)
        XCTAssertEqual(schedule[1].time, 20.0 / 35.0, accuracy: 1e-12)
        XCTAssertTrue(schedule.allSatisfy { $0.damageMultiplier == 1 && $0.forcedStatuses.isEmpty })
    }

    func testEquippedStanceUsesTheSelectedComboData() throws {
        let stance = try XCTUnwrap(ModLibrary.shared.mod(named: "Crimson Dervish"))
        let combos = MeleeStanceLibrary.combos(
            in: stance,
            orderedNames: ModLibrary.shared.stanceComboNames(for: stance.name)
        )
        XCTAssertEqual(combos.map(\.name), ["Twisting Flurry", "Crimson Orbit", "Coiling Impale"])

        let attack = Attack(name: "Normal Attack", speed: 0.833, critChance: 0,
                            critMultiplier: 1, statusChance: 0, damage: [.slash: 120])
        var weapon = Weapon(name: "Skana", attacks: [attack], magazineSize: 1,
                            reloadTime: 0, category: "Melee")
        weapon.categories = ["weapon", "melee", "melee-sword"]
        weapon.compTags = ["SWORDS_STANCE", "SKANA"]
        let build = Build(slottedMods: [SlottedMod(slot: 9, name: "Crimson Dervish")],
                          stanceCombo: "Twisting Flurry")
        let resolved = BuildResolver(weapon: weapon, build: build, options: Options(window: 20),
                                     faction: .grineer).resolveAll()[0]
        let sequence = try XCTUnwrap(resolved.meleeSequence)
        XCTAssertEqual(sequence.cycleDuration, 2, accuracy: 1e-12)
        XCTAssertEqual(sequence.hitMultipliers, [3, 3, 2, 2, 4])
        XCTAssertEqual(sequence.normalizedStatuses, ["", "", "", "impact", ""])
        XCTAssertFalse(resolved.notes.contains { $0.contains("stances") })

        let enemy = Enemy(name: "E", faction: "Grineer", health: 1e12, armor: 0)
        let profile = EnemyProfile(enemy: enemy, level: 1, options: Options(window: 20))
        let schedule = WeaponSimulator(segments: [resolved], enemy: profile,
                                       options: Options(window: 20)).shotSchedule(for: resolved)

        // Website contract: round(20 * 5 / (2 / 0.833)) = 42 contacts.
        XCTAssertEqual(schedule.count, 42)
        XCTAssertEqual(Array(schedule.prefix(5).map(\.damageMultiplier)), [3, 3, 2, 2, 4])
        XCTAssertEqual(schedule[3].forcedStatuses, ["impact"])
    }

    func testHeavyAttackUsesSourceSequenceWindUpAndHeavyOnlyModActions() throws {
        let attack = Attack(name: "Normal Attack", speed: 1, critChance: 10,
                            critMultiplier: 2, statusChance: 20, damage: [.slash: 100])
        var weapon = Weapon(name: "Skana", attacks: [attack], magazineSize: 1,
                            reloadTime: 0, windUp: 0.5, category: "Melee")
        weapon.categories = ["weapon", "melee", "melee-sword"]
        weapon.compTags = ["SWORDS_STANCE", "SKANA"]
        let options = Options(window: 20, heavyAttack: true,
                              heavyAttackStartingCombo: 12,
                              meleeComboMultiplier: 1)
        let build = Build(mods: ["Killing Blow", "Dreamer's Wrath", "Empowered Blades"])
        let resolved = try XCTUnwrap(BuildResolver(weapon: weapon, build: build, options: options,
                                                    faction: .grineer).resolveAll().first)
        let sequence = try XCTUnwrap(resolved.meleeSequence)

        // `default_MeleeStances.SWORDS_STANCE.heavy` comes from the exported
        // site data. Killing Blow's +60% wind-up speed is applied to the
        // weapon timing, not hard-coded in a view.
        XCTAssertEqual(sequence.cycleDuration, 3, accuracy: 1e-12)
        XCTAssertEqual(sequence.hitMultipliers, [5, 5])
        XCTAssertEqual(sequence.windUp, 0.5 / 1.6, accuracy: 1e-12)
        XCTAssertTrue(resolved.isHeavyMeleeAttack)

        // Heavy-only Mod actions must not leak into normal attacks.
        XCTAssertEqual(resolved.critMultiplier, Rules.quantizeBaseCritDamage(2) * 1.32,
                       accuracy: 1e-12)
        XCTAssertEqual(resolved.statusChance, 0.2 * 1.6, accuracy: 1e-12)

        let enemy = Enemy(name: "E", faction: "Grineer", health: 1e12, armor: 0)
        let profile = EnemyProfile(enemy: enemy, level: 1, options: options)
        let schedule = WeaponSimulator(segments: [resolved], enemy: profile,
                                       options: options).shotSchedule(for: resolved)
        // round(20 * 2 / (3 / 1 + 0.5 / 1.6)) = 12 contacts. The first heavy
        // pair has the chosen 12x combo; the no-efficiency follow-up pairs
        // fall back to 1x exactly as the source contact timeline does.
        XCTAssertEqual(schedule.count, 12)
        XCTAssertEqual(Array(schedule.prefix(2).map(\.damageMultiplier)), [60, 60])
        XCTAssertEqual(Array(schedule.dropFirst(2).prefix(2).map(\.damageMultiplier)), [5, 5])
        XCTAssertEqual(Array(schedule.prefix(2).map(\.comboMultiplier)), [12, 12])
        XCTAssertEqual(Array(schedule.dropFirst(2).prefix(2).map(\.comboMultiplier)), [1, 1])
    }

    func testAllConditionsUsesRawComboActionsWithoutModNameBranching() throws {
        let attack = Attack(name: "Normal Attack", speed: 1, critChance: 20,
                            critMultiplier: 2, statusChance: 25, damage: [.slash: 100])
        var weapon = Weapon(name: "Skana", attacks: [attack], category: "Melee")
        weapon.categories = ["weapon", "melee", "melee-sword"]
        weapon.compTags = ["SWORDS_STANCE", "SKANA"]
        let build = Build(mods: ["Blood Rush", "Weeping Wounds"])

        let enabled = try XCTUnwrap(BuildResolver(
            weapon: weapon, build: build,
            options: Options(window: 20, allModConditionsMet: true, meleeComboMultiplier: 12),
            faction: .grineer
        ).resolveAll().first)
        XCTAssertEqual(enabled.critChancePerCombo, 0.4, accuracy: 1e-12)
        XCTAssertEqual(enabled.statusChancePerCombo, 0.4, accuracy: 1e-12)
        XCTAssertFalse(enabled.notes.contains { $0.contains("WITH_COND.crit_chance_per_combo") })
        XCTAssertFalse(enabled.notes.contains { $0.contains("WITH_COND.status_chance_by_combo") })

        let disabled = try XCTUnwrap(BuildResolver(
            weapon: weapon, build: build,
            options: Options(window: 20, allModConditionsMet: false, meleeComboMultiplier: 12),
            faction: .grineer
        ).resolveAll().first)
        XCTAssertEqual(disabled.critChancePerCombo, 0, accuracy: 1e-12)
        XCTAssertEqual(disabled.statusChancePerCombo, 0, accuracy: 1e-12)
    }
}
