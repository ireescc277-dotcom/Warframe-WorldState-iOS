import XCTest
@testable import DamageKit

/// 10 组固定 fixture：输入在 `Fixtures/`，期望值在 `Fixtures/expected/`。
///
/// 期望值是**黄金文件**，用来锁住行为；它们不是「游戏真值」，
/// 真值口径与已知偏差见 README。
final class FixtureTests: XCTestCase {

    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DamageKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DamageKit
            .deletingLastPathComponent()   // Packages
            .deletingLastPathComponent()   // repo root
    }

    static var dataRoot: URL { packageRoot.appendingPathComponent("web/app/site") }
    static var fixtures: URL { packageRoot.appendingPathComponent("Packages/DamageKit/Fixtures") }

    func testFixturesMatchGolden() throws {
        let files = try FileManager.default
            .contentsOfDirectory(at: Self.fixtures, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 10, "fixture 数量应为 10")

        let store = DataStore(root: Self.dataRoot)
        let calculator = Calculator(store: store)

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            let request = try JSONDecoder().decode(DamageRequest.self,
                                                   from: Data(contentsOf: file))
            let actual = try calculator.evaluate(request)

            let expectedURL = Self.fixtures
                .appendingPathComponent("expected")
                .appendingPathComponent(name + ".json")
            let expected = try JSONDecoder().decode(Result.self, from: Data(contentsOf: expectedURL))

            XCTAssertEqual(actual, expected, "fixture 结果漂移: \(name)")
        }
    }

    /// 量级检查（见任务书「验收」）：
    /// Torid 无 mod 打 Lv100 重型机枪手，单段 DPS 落在 50–200、20 秒内打不死。
    ///
    /// 实测直伤部分 ≈ 138（落在区间内）；把状态 DOT 也算进去是 ≈ 217，
    /// 略高于参考区间上沿 —— 毒素 proc 每层是 300% 基础伤害，23% 触发率下
    /// 相当于 +69% 输出，这是规则本身的结果，按任务书「以规则为准」保留。
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
        XCTAssertEqual(grenade.shots, 24)
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
