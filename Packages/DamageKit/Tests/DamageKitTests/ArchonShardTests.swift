import XCTest
@testable import DamageKit

final class ArchonShardTests: XCTestCase {
    private func corrosiveWeapon() -> Weapon {
        Weapon(
            name: "Shard test weapon",
            attacks: [Attack(name: "Hit", speed: 20, critChance: 0, critMultiplier: 1,
                             statusChance: 100, damage: [.corrosive: 100])],
            magazineSize: 100,
            reloadTime: 0,
            category: "primary"
        )
    }

    func testEmeraldShardSlotsContributeTheirRawStackCapActions() {
        let weapon = corrosiveWeapon()
        let build = Build(slottedMods: [
            SlottedMod(slot: 23, name: "Incr. max stacks of Corrosion +2"),
            SlottedMod(slot: 24, name: "Incr. max stacks of Corrosion +3"),
        ])
        let resolved = BuildResolver(weapon: weapon, build: build, options: Options(),
                                     faction: .neutral).resolveAll()[0]

        XCTAssertEqual(resolved.corrosiveStackCapBonus, 5, accuracy: 1e-12)
        XCTAssertFalse(resolved.notes.contains { $0.contains("incMaxStacks_Corrosion") })
    }

    func testShardSlotsProduceTheSameCorrosionCapAsExplicitEnvironmentValue() {
        let weapon = corrosiveWeapon()
        let enemy = Enemy(name: "Armor target", faction: "Neutral", health: 1e12, armor: 2700)
        let shardBuild = Build(slottedMods: [
            SlottedMod(slot: 23, name: "Incr. max stacks of Corrosion +2"),
            SlottedMod(slot: 24, name: "Incr. max stacks of Corrosion +3"),
        ])
        let fromSlots = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1, build: shardBuild,
            options: Options(window: 2)
        )).attacks[0]
        let fromLegacyInput = Calculator().evaluate(DamageInput(
            weapon: weapon, enemy: enemy, level: 1,
            options: Options(window: 2, corrosiveStackCapBonus: 5)
        )).attacks[0]

        XCTAssertEqual(fromSlots.targetDirectDamage, fromLegacyInput.targetDirectDamage,
                       accuracy: 1e-9)
        XCTAssertEqual(fromSlots.targetDps, fromLegacyInput.targetDps, accuracy: 1e-9)
    }

    func testShardDefinitionIsRejectedOutsideAnArchonShardSlot() {
        let weapon = corrosiveWeapon()
        let build = Build(slottedMods: [
            SlottedMod(slot: 0, name: "Incr. max stacks of Corrosion +2"),
        ])
        let resolved = BuildResolver(weapon: weapon, build: build, options: Options(),
                                     faction: .neutral).resolveAll()[0]

        XCTAssertEqual(resolved.corrosiveStackCapBonus, 0, accuracy: 1e-12)
        XCTAssertTrue(resolved.notes.contains { $0.contains("不兼容") })
    }
}
