import XCTest
@testable import DamageKit

/// 固定 fixture：输入在 `Fixtures/`。
///
/// 旧 expected 文件来自“护甲也是独立血池、每层各自重放”的旧模型，不能再拿来
/// 反向约束真实的防护链。具体机制由 FormulaOracleTests 的可手算公式向量验收；
/// 本文件负责检验真实数据能完整进入统一时间线且结果结构自洽。
final class FixtureTests: XCTestCase {

    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DamageKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DamageKit
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
    }

    static var dataRoot: URL { packageRoot.appendingPathComponent("server/site") }
    static var fixtures: URL { packageRoot.appendingPathComponent("Packages/DamageKit/Fixtures") }

    func testFixturesRunThroughOneDefenseTimeline() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.fixtures, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // 这里的职责是把仓库中声明的每个 JSON fixture 都跑一遍。fixture 是
        // 对拍案例的输入集合，不是一个固定产品清单；把数量写死会让新增案例
        // 本身变成一次测试失败，反而掩盖它是否真正进入了统一时间线。
        XCTAssertFalse(files.isEmpty, "至少应有一个 fixture")

        let store = DataStore(root: Self.dataRoot)
        let calculator = Calculator(store: store)

        for file in files {
            let request = try JSONDecoder().decode(DamageRequest.self,
                                                   from: Data(contentsOf: file))
            let actual = try calculator.evaluate(request)
            XCTAssertFalse(actual.attacks.isEmpty, "fixture 未产生攻击段: \(file.lastPathComponent)")

            for attack in actual.attacks {
                XCTAssertTrue(attack.dps.isFinite && attack.dps >= 0)
                XCTAssertTrue(attack.directDamage.isFinite && attack.directDamage >= 0)
                XCTAssertTrue(attack.dotDamage.isFinite && attack.dotDamage >= 0)
                XCTAssertTrue(attack.targetDps.isFinite && attack.targetDps >= 0)
                XCTAssertTrue(attack.targetDirectDps.isFinite && attack.targetDirectDps >= 0)
                XCTAssertTrue(attack.targetDirectDamage.isFinite && attack.targetDirectDamage >= 0)
                XCTAssertTrue(attack.targetDotDamage.isFinite && attack.targetDotDamage >= 0)

                // Armor is a modifier on Health, never a fourth damage pool.
                XCTAssertFalse(attack.layers.contains { $0.layer == .armor })
                XCTAssertEqual(Set(attack.layers.map(\.layer)).count, attack.layers.count)
                for layer in attack.layers {
                    XCTAssertTrue(layer.maxHP >= 0 && layer.damage >= 0)
                    XCTAssertTrue(layer.dps.isFinite)
                    if let ttk = layer.ttk { XCTAssertGreaterThanOrEqual(ttk, 0) }
                    if layer.layer == .health, layer.ttk != nil {
                        XCTAssertLessThanOrEqual(layer.damage, layer.maxHP + 1e-6)
                    }
                }
            }
        }
    }

    /// 量级检查（见任务书「验收」）：
    /// Torid 无 mod 打 Lv100 重型机枪手，单段 DPS 落在 50–200、20 秒内打不死。
    ///
    /// 这个只做真实数据的量级烟雾测试；精确机制交由手算 oracle 覆盖。
    func testToridMagnitudeCheck() throws {
        let store = DataStore(root: Self.dataRoot)
        let request = try JSONDecoder().decode(
            DamageRequest.self,
            from: Data(contentsOf: Self.fixtures.appendingPathComponent("01-torid-lv100.json")))
        let input = try request.resolve(using: store)
        let result = Calculator(store: store).evaluate(input)

        guard let grenade = result.attacks.first(where: { $0.attack == "Grenade Impact" }) else {
            return XCTFail("找不到 Grenade Impact 段")
        }
        let directDPS = grenade.directDamage / input.options.window
        XCTAssertGreaterThan(directDPS, 50)
        XCTAssertLessThan(directDPS, 200)

        let health = grenade.layers.first { $0.layer == .health }
        XCTAssertNil(health?.ttk, "20 秒内不应该打死 Lv100 重型机枪手")
        // Torid：弹匣 5、射速 1.5、装填 1.7s，窗口 20s。
        // 排程 = 5 发 @ 1/1.5 ≈ 0.667s 间隔，随后装填 1.7s，如此循环。
        // 每匣 5 发，20s 内正好 4 整匣 = 20 发。这里断言的是「窗口内实际发生的
        // 扣扳机次数」，不是「5 × 射速 × 窗口」的近似估算。
        XCTAssertEqual(grenade.shots, 20)
    }

    /// 同一输入两次必须逐位相等。
    func testFixtureDeterminism() throws {
        let store = DataStore(root: Self.dataRoot)
        let calculator = Calculator(store: store)
        let request = try JSONDecoder().decode(
            DamageRequest.self,
            from: Data(contentsOf: Self.fixtures.appendingPathComponent("04-soma-viral-heat.json")))
        let input = try request.resolve(using: store)
        let a = calculator.evaluate(input)
        let b = calculator.evaluate(input)
        XCTAssertEqual(a, b)
    }
}
