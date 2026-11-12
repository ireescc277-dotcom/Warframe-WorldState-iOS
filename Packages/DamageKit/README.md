# DamageKit

`DamageKit` 是 WarframeWatch 伤害计算器使用的纯 Swift 计算库。它接收武器、配卡、目标和战斗条件，返回同一时间窗口内的直伤、持续伤害、各防御层实际承伤与击杀时间。

WarframeWatch 的伤害页是原生 SwiftUI 页面：选择器把用户选项转换为 `DamageInput`，随后直接调用 `Calculator.evaluate(_:)`。iOS 路径不启动本地 HTTP 服务、不嵌入网页，也不执行网站 JavaScript。

## 在 App 中可填写的内容

伤害页会把下列内容交给这个库计算：

- 武器、攻击段及可组合的攻击段；武器和敌人均可按中文或英文搜索。
- 敌人、等级、钢铁之路、卓越者和小队人数。
- 武器 Mod、紫卡、近战架势、灵化选项与碎片。
- 命中头部/弱点、连击、蓄力、距离、状态层数和计算窗口。
- 战甲 Mod/赋能、同伴 Mod，以及命名或手工录入的环境 Buff。

界面只负责选择名称、开关和显示单位；伤害公式不写在输入界面里。所有 Mod、状态、目标和环境效果的结算位置都在 `DamageKit` 中，因此手动填写与 App 选择走同一套计算。

## 计算过程

1. `BuildResolver` 把武器、配卡、紫卡、架势、灵化、碎片和外部效果合成为每个攻击段的伤害、暴击、状态、射速、装填与攻击行为。
2. `EnemyProfile` 根据目标、等级和目标选项生成生命、护盾、护甲和超宏。
3. `WeaponSimulator` 按攻击时间线处理命中、弹匣/装填/蓄力、直伤、状态效果、持续伤害和动态目标状态。
4. `Calculator` 汇总每个攻击段与 `Overguard → Shield → Health` 三层的结果。

`directDamage` 和 `dotDamage` 是整个窗口内、减伤前的武器输出；`layers` 是目标实际承受的伤害和各层 TTK。`targetDirectDamage`、`targetDotDamage` 与 `targetDps` 使用同一条目标状态时间线，但不因这一个目标先死亡而截断，适合比较不同构筑的持续输出。

## 敌人等级曲线

当前的目标等级、卓越者、超宏、钢铁之路和小队生命计算，按检入仓库的 `warframe-damage` 源码直接翻译。

要逐项核对这一移植，可对照：

- 网站原实现：`../../server/site/min.js` 中的 `showEnemy` 和 `correctEnemyLvl`。
- Swift 实现：`Sources/DamageKit/EnemyProfile.swift`。
- 固定状态对照：`node ../../scripts/compare_target_states.js`。

该命令逐一比较健康、护盾、护甲、超宏和小队生命倍率；它的作用是保证两份源码在相同输入下得出相同目标面板。

## 本地使用

```powershell
Set-Location C:\WarframeWorldState\Packages\DamageKit

# Swift 单元测试
swift test -j 1

# 计算一个 JSON 输入
swift run -c debug damagekit-cli Fixtures\02-torid-mods.json `
  --data-root C:\WarframeWorldState\server\site --compact

# 查看配卡解析后的攻击参数，不运行时间线
swift run -c debug damagekit-cli Fixtures\02-torid-mods.json `
  --data-root C:\WarframeWorldState\server\site --dump-resolved
```

`damagekit-cli` 还支持 `--list-weapons`、`--list-enemies`、`--list-mods`、`--timing` 和 `--repeat N`。不传 `--data-root` 时，它会从当前目录向上寻找受版本控制的 `server/site`；仅为旧开发目录兼容，才回退到生成的 `web/app/site`。

## 与 warframe-damage 对照

开发时使用两类检查：

```powershell
# 只检查目标面板/等级曲线是否逐项一致
node ../../scripts/compare_target_states.js

# 运行武器、攻击形态、Mod、状态、Buff 和目标的完整对照集
node ../../scripts/compare_damagekit.js --strict --summary
```

对照用例保存在 `Parity/website-cases.json`。每个用例保存网站输入、目标输出字段和误差阈值；如果网站的队列展示行为与其可复现的状态时间线不同，用例会保存对应的源码分支与规则链接，而不会把两种口径伪装成数值相同。

## 数据与源码位置

- 核心计算：`Sources/DamageKit/`
- 离线 Mod 与架势资料：`Sources/DamageKit/Resources/`
- App 原生页面：`../../WarframeWatch/Views/Arsenal/NativeDamageCalculatorView.swift`
- App 输入适配：`../../WarframeWatch/Views/Arsenal/NativeDamageCalculatorModel.swift`
- App 本地武器、翻译与图标资料：`../../ios/DamageData/`
- 网站对照源码和资料：`../../server/site/`
