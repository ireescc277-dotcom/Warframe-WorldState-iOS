import Foundation
import DamageKit

// damagekit-cli
//   用法：
//     damagekit-cli <input.json> [--data-root <dir>] [--compact] [--timing]
//     damagekit-cli --list-mods
//     damagekit-cli --list-weapons | --list-enemies
//
// 输入格式见 README。输出是稳定排序的 JSON（同一输入逐字节相同）。

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("error: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
var inputPath: String?
var dataRoot = "web/app/site"
var compact = false
var showTiming = false
var listMode: String?
var dumpResolved = false
var repeatCount = 1

var i = 0
while i < args.count {
    let a = args[i]
    switch a {
    case "--data-root":
        i += 1
        guard i < args.count else { fail("--data-root 需要一个路径") }
        dataRoot = args[i]
    case "--compact":
        compact = true
    case "--timing":
        showTiming = true
    case "--dump-resolved":
        dumpResolved = true
    case "--repeat":
        i += 1
        guard i < args.count, let n = Int(args[i]) else { fail("--repeat 需要一个整数") }
        repeatCount = max(1, n)
    case "--list-mods":
        listMode = "mods"
    case "--list-weapons":
        listMode = "weapons"
    case "--list-enemies":
        listMode = "enemies"
    case "--help", "-h":
        print("""
        damagekit-cli <input.json> [--data-root <dir>] [--compact] [--timing]
        damagekit-cli --list-mods | --list-weapons | --list-enemies
        """)
        exit(0)
    default:
        if a.hasPrefix("-") { fail("未知参数 \(a)") }
        inputPath = a
    }
    i += 1
}

let store = DataStore(root: URL(fileURLWithPath: dataRoot))

if let listMode {
    let names: [String]
    switch listMode {
    case "mods":
        names = ModLibrary.shared.definitions.map(\.name).sorted()
    case "weapons":
        names = (try? store.weaponNames()) ?? []
    default:
        names = (try? store.enemyNames()) ?? []
    }
    print(names.joined(separator: "\n"))
    exit(0)
}

guard let inputPath else { fail("缺少输入文件，-h 看用法") }
guard let raw = FileManager.default.contents(atPath: inputPath) else {
    fail("读不到文件 \(inputPath)")
}

let decoder = JSONDecoder()
let request: DamageRequest
do {
    request = try decoder.decode(DamageRequest.self, from: raw)
} catch {
    fail("输入 JSON 解析失败: \(error)")
}

let calculator = Calculator(store: store)

if dumpResolved {
    let input = try calculator.store.map { try request.resolve(using: $0) } ?? request.resolve(using: nil)
    for r in calculator.resolvedAttacks(input) {
        let dmg = r.damage.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\(String(format: "%.2f", $0.value))" }
            .joined(separator: " ")
        print("[\(r.name)] dmg: \(dmg)")
        print("  cc=\(String(format: "%.4f", r.critChance)) cdm=\(String(format: "%.3f", r.critMultiplier)) sc=\(String(format: "%.4f", r.statusChance)) ms=\(String(format: "%.3f", r.multishot)) rate=\(String(format: "%.3f", r.fireRate))")
        print("  faction=\(r.factionBonus) statusDmg=\(r.statusDamageBonus) headshot=\(r.headshotMultiplier) mag=\(r.magazine) reload=\(r.reload) lastShotMs=\(r.lastShotMultishot)")
        if !r.notes.isEmpty { print("  notes=\(r.notes)") }
    }
    exit(0)
}

// 先把数据装上（武器 / 敌人 / mod），计时只算纯计算 ——
// 验收里的「不加载数据 < 5ms」指的就是这一段。
let input: DamageInput
do {
    input = try request.resolve(using: store)
} catch {
    fail("输入解析失败: \(error)")
}

var result = calculator.evaluate(input)
var elapsed = 0.0
if repeatCount > 1 {
    let started = Date()
    for _ in 0..<repeatCount { result = calculator.evaluate(input) }
    elapsed = Date().timeIntervalSince(started) / Double(repeatCount)
} else {
    let started = Date()
    result = calculator.evaluate(input)
    elapsed = Date().timeIntervalSince(started)
}

let encoder = JSONEncoder()
encoder.outputFormatting = compact ? [.sortedKeys] : [.sortedKeys, .prettyPrinted]
guard let out = try? encoder.encode(result) else { fail("结果序列化失败") }
FileHandle.standardOutput.write(out)
FileHandle.standardOutput.write("\n".data(using: .utf8)!)

if showTiming {
    let ms = String(format: "%.2f", elapsed * 1000)
    FileHandle.standardError.write("elapsed: \(ms) ms\n".data(using: .utf8)!)
}
