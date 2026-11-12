import Foundation
import DamageKit

// damagekit-cli
//   用法：
//     damagekit-cli <input.json|-> [--data-root <dir>] [--compact] [--timing]
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
var dataRoot: String?
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
        damagekit-cli <input.json|-> [--data-root <dir>] [--compact] [--timing]
        damagekit-cli --list-mods | --list-weapons | --list-enemies
        传入 - 时，从标准输入读取请求 JSON。
        """)
        exit(0)
    default:
        if a == "-" {
            inputPath = a
            i += 1
            continue
        }
        if a.hasPrefix("-") { fail("未知参数 \(a)") }
        inputPath = a
    }
    i += 1
}

func discoverStore(explicitRoot: String?) -> DataStore? {
    if let explicitRoot {
        return DataStore(root: URL(fileURLWithPath: explicitRoot))
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    return DataStore.discoverRoot(startingAt: cwd).map(DataStore.init(root:))
}

func requireStore(explicitRoot: String?) -> DataStore {
    guard let store = discoverStore(explicitRoot: explicitRoot),
          DataStore.hasRequiredData(at: store.root) else {
        if let explicitRoot {
            fail("数据目录无效: \(explicitRoot)（需要 weapons-list.json 和 data/json/enemies-min.json）")
        }
        fail("找不到离线数据目录；请传入 --data-root <web/app/site>")
    }
    return store
}

if let listMode {
    let names: [String]
    switch listMode {
    case "mods":
        names = ModLibrary.shared.definitions.map(\.name).sorted()
    case "weapons":
        do {
            names = try requireStore(explicitRoot: dataRoot).weaponNames()
        } catch {
            fail("读取武器列表失败: \(error)")
        }
    default:
        do {
            names = try requireStore(explicitRoot: dataRoot).enemyNames()
        } catch {
            fail("读取敌人列表失败: \(error)")
        }
    }
    print(names.joined(separator: "\n"))
    exit(0)
}

guard let inputPath else { fail("缺少输入文件，-h 看用法") }
let raw: Data
if inputPath == "-" {
    raw = FileHandle.standardInput.readDataToEndOfFile()
} else {
    guard let fileData = FileManager.default.contents(atPath: inputPath) else {
        fail("读不到文件 \(inputPath)")
    }
    raw = fileData
}

let decoder = JSONDecoder()
let request: DamageRequest
do {
    request = try decoder.decode(DamageRequest.self, from: raw)
} catch {
    fail("输入 JSON 解析失败: \(error)")
}

// 只有名称引用需要离线数据；完整内嵌对象是公开 API，应能独立计算。
let needsStore = request.weapon?.reference != nil || request.ownedWeapon != nil || request.enemy.reference != nil
let store = needsStore ? requireStore(explicitRoot: dataRoot) : nil
let calculator = Calculator(store: store)

let input: DamageInput
do {
    input = try request.resolve(using: store)
} catch {
    fail("输入解析失败: \(error)")
}

if dumpResolved {
    for r in calculator.resolvedAttacks(input) {
        let dmg = r.damage.sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\(String(format: "%.2f", $0.value))" }
            .joined(separator: " ")
        print("[\(r.name)] dmg: \(dmg)")
        print("  cc=\(String(format: "%.4f", r.critChance)) cdm=\(String(format: "%.3f", r.critMultiplier)) sc=\(String(format: "%.4f", r.statusChance)) ms=\(String(format: "%.3f", r.multishot)) rate=\(String(format: "%.3f", r.fireRate))")
        print("  faction=\(r.factionBonus) statusDmg=\(r.statusDamageBonus) headshot=\(r.headshotMultiplier) mag=\(r.magazine) reload=\(r.reload) lastShotMs=\(r.lastShotMultishot)")
        // 直接伤害的逐状态乘子：这三项决定 Galvanized Shot / Gun CO 那一路。
        print("  perStatusType=\(r.directDamagePerStatusType) baseDmgMult=\(r.baseDamageMultiplier) coMult=\(r.conditionalDamageIsMultiplicative)")
        print("  nonCritBonus=\(r.nonCriticalDamageBonus) nonCritChance=\(r.nonCriticalDamageChance) doubleCrit=\(r.doubleCritChance) slashOnCrit=\(r.slashOnCriticalChance)")
        print("  dotBase=\(r.dotBaseDamage) dotElem=\(r.dotElementBonuses) dotStatus=\(r.dotStatusBonuses)")
        if !r.notes.isEmpty { print("  notes=\(r.notes)") }
    }
    exit(0)
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
