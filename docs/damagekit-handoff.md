# DamageKit 工作交接

更新日期：2026-11-13

仓库：`C:\WarframeWorldState`

分支：`codex/damagekit-native`
当前代码提交：[`269ce16`](https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS/commit/269ce16cbba076be42ca27c03488023ae3d04c26)（Import Riven ammo efficiency into sustained fire）

这份文件记录的是当前可接手的工程状态，不把“已有代码”说成“已经完整还原游戏”。接手时先看这里，再看对应测试和代码；不要只根据 README 或一次网页计算结果判断伤害模型正确。

## 一句话目标

把 Warframe 的账号军械库、整套配置和伤害计算做进上级 iOS App：用户按游戏里的方式选战甲、武器、Mod、赋能、执政官石、同伴和外部增益；计算结果逐项与 warframe-damage 对照，差异应小于 5%，否则要能指出网站的哪条规则错了并给出证据。

最终运行时必须是纯 Swift；不能用 WebView 或 JavaScript 作为计算器。比较网站、读取其静态数据、运行校验脚本可以留在开发/测试阶段，但绝不能成为 App 的运行依赖。

## 当前已确认的内容

### 1. 伤害核心和 App 的接线

- 纯 Swift 核心在 `Packages/DamageKit/Sources/DamageKit/`，测试在 `Packages/DamageKit/Tests/DamageKitTests/`。
- App 侧的计算器入口和配置组装在：
  - `WarframeWatch/Views/Arsenal/NativeDamageCalculatorModel.swift`
  - `WarframeWatch/Views/Arsenal/NativeDamageCalculatorView.swift`
  - `WarframeWatch/Models/InventoryModel.swift`
- 当前战甲自己施放的技能与外部战甲施放、且能作用队友的技能是两套来源，可以同时存在：
  - 当前战甲的技能只从当前所选战甲配置读取；
  - 外部施法者从另一套已拥有战甲配置读取；
  - 当前这一个实例不会又被当作外部施法者重复计入。
- 用户不应手填“技能强度”这种已经能由战甲 Mod、石头和赋能推导的中间值。它应当是配置计算出的结果；技能开关仍可保留，用于选择当下是否施放以及外部 Buff。

### 2. 紫卡的弹药效率已经进入计算

本次提交补上了以前只显示、却没有参与持续射击计算的紫卡 `WeaponAmmoEfficiency`：

- DE 形状的背包快照由 `InventoryAdapter.swift` 读取；当前 App 的快照构建脚本也会把它写成 `ammoEfficiency`。
- 正弹药效率按游戏当前上限封顶为 75%；负弹药效率会增加每次射击的耗弹，不能被错误地当成正值或忽略。
- 普通攻击根据弹匣、每发耗弹和弹药效率排出实际射击/换弹时间；光束武器默认每发耗弹为 0.5，攻击数据显式给出 `ammoCost` 时优先使用显式值。
- 满弹药效率（游戏意义上的无限弹药）与“+100% 弹药效率”分开表达，不能用一个百分比混在一起。
- 弓类攻击不因弹药效率而减少每箭之间的拉弓/装填时间。这个结论有 Wiki 和实际排程测试支撑。
- UI 中此词条显示为“弹药效率”，归入“弹匣、弹药与连击”，不再作为未映射词条。

相关文件：

- `Packages/DamageKit/Sources/DamageKit/Model.swift`
- `Packages/DamageKit/Sources/DamageKit/BuildResolver.swift`
- `Packages/DamageKit/Sources/DamageKit/WeaponSimulator.swift`
- `Packages/DamageKit/Sources/DamageKit/InventoryAdapter.swift`
- `scripts/build_app_inventory.py`
- `WarframeWatch/Models/InventoryModel.swift`
- `WarframeWatch/Views/Arsenal/NativeDamageCalculatorModel.swift`

### 3. 已经证明的一处网站错误：Kuva Bramma 的弓时间线

Kuva Bramma 的源数据是：1 发弹匣、0.6 秒换弹、0.4 秒蓄力。正确的 20 秒射击时刻为：

```text
0.4, 1.4, 2.4, …, 19.4  （共 20 发）
```

warframe-damage 的现有排程会把弓的换弹时间多加一次，得到：

```text
0.4, 2.0, 3.6, …, 19.6  （共 13 发）
```

因此这个分歧不是“近似”或“随机误差”，而是网站的弓类时间线多算了一段换弹。项目保留了可复现的拆解和反事实测试：

- `Packages/DamageKit/Parity/website-cases.json`
- `scripts/verify_website_bow_timeline_probe.js`
- `scripts/verify_website_bow_timeline_counterfactual.js`
- `scripts/probe_bramma_layers.js`

可参考的规则来源：

- [Warframe Wiki：Ability Strength / Energized Munitions](https://wiki.warframe.com/w/Ability_Strength)——75% 弹药效率的分数耗弹说明，并明确弓每箭仍有换弹/装填间隔。
- [DE Dev Workshop：Ammo Efficiency Changes](https://forums.warframe.com/topic/1529475-dev-workshop-ammo-efficiency-changes-riven-disposition-retirement/)——正弹药效率上限 75%，以及“无限弹药”和普通弹药效率的区分。

> 注意：这只证明了这一条网站分支错误。它不证明整个网站错误，也不证明 DamageKit 已经对所有武器正确。

### 4. 已运行的本地验证

在本次提交后已经通过：

- `swift test`：175 个 DamageKit 测试通过。
- `python -X utf8 scripts/test_build_app_inventory.py`：18 个快照构建测试通过。
- `python -m py_compile scripts/wf_gamedata.py scripts/build_app_inventory.py scripts/test_build_app_inventory.py`：通过。
- `swiftc -parse WarframeWatch/Models/InventoryModel.swift WarframeWatch/Views/Arsenal/NativeDamageCalculatorModel.swift WarframeWatch/Views/Arsenal/NativeDamageCalculatorView.swift`：通过。
- 使用私有账号快照实际跑过 `build_app_inventory.py`：一把当前拥有的 Kuva Bramma 配置中的紫卡弹药效率已进入规范化输出，且不再标为未映射。快照内容没有写入 Git，也不应写入文档或提交。

GitHub Actions 本次运行：<https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS/actions/runs/43357676158>。

写本文件时，第一项 “Swift Runtime & Data Decoding Tests” 已成功；后续 iOS 模拟器视觉检查和打包结果应以 Actions 页面实时状态为准，不能把本文件中的时间点当作最终构建结论。

## 数据来源和边界

### 游戏静态数据

- 武器、敌人与索引数据在 `web/app/site/` 下；DamageKit 的源数据和测试会从该仓库数据构造输入。
- Mod 原始数据来自项目已保存的数据导出。运行时不能联网补数据。
- `docs/damagekit-prompt.md` 是最初的实现约束。它禁止把现有 JS 计算器搬进产品；这个约束仍然有效。

目前的网页对照脚本会读取网页实现，用来定位“网站和 Swift 为何不同”。这只能作为开发期证据工具。接手时应审查：产品 Swift 目标不得导入、执行或依赖这些 JS 文件。

### 账号数据

已决定的来源是 AlecaFrame/Overwolf 在本机留下的账号快照，而不是由本 App 直接反复调用 DE 库存接口，也不是读游戏内存。

原因不是说 DE 接口一定不能用，而是当前没有足够证据证明高频直接调用的风险、登录竞争和限流行为；用户明确希望先避免让 App 依赖这种不确定路径。不要擅自恢复直接 DE 请求。

当前链路：

```text
AlecaFrame/Overwolf 本地快照
        ↓
data/inventory/ 中的私有快照（Git 忽略）
        ↓
scripts/build_app_inventory.py 规范化并导出 App 可读数据
        ↓
iOS 的背包/军械库/计算器界面
```

`InventoryAdapter.swift` 已有直接把 DE 形状快照映射为核心模型的测试路径；但 App 的正式生产链路目前仍依赖上述 Python 规范化步骤。因此不要把“有 Swift Adapter”写成“生产环境已经完全纯 Swift 导入账号数据”。

### 快照刷新与版本链路（代码已实现，部署状态另验）

用户要求的不是单一“刷新时间”，而是可追溯的内容版本。当前工作树已经实现了这条链路：

```text
AlecaFrame 的 lastData.dat 变化
        ↓  （连续两次采样稳定后才读取）
scripts/wf_watch.py
        ↓
wf_inventory.py → build_inventory_view.py → build_app_inventory.py
        ↓  （源快照哈希必须等于 App payload 的 sourceHash）
scripts/wf_publish.py
        ↓  （上传不可变 payload，VPS 校验 SHA-256 后原子切换 manifest）
iOS InventoryFeed
        ↓  （校验 manifest、字节数、SHA-256 和 sourceHash 后才切换显示）
App 中的资产、军械库和计算器
```

具体保证如下：

1. `scripts/wf_watch.py` 监听 AlecaFrame 本地文件，先等待 `(mtime, size)` 稳定，再构建；它不会在文件正被重写时把半份数据当作新版本。
2. 每次同步写 `data/inventory/sync_receipt.json`，逐段记录 `sourceRead`、`inventoryView`、`appPayload`、`published` 的成功/失败、时间和哈希，不记录原始背包内容、凭据或物品实例 ID。
3. `scripts/wf_publish.py` 用内容哈希命名 payload；VPS 回读其 SHA-256 成功后，才原子替换很小的 `inventory.json` manifest。`publishedAt` 因而对应 manifest 指向的那一份确切字节，而不是某次构建开始或按钮点击时间。
4. `InventoryFeed.refresh()` 不会因为用户再次下拉就刷新显示时间；只有 `snapshotId/contentHash` 变了，且 payload 的字节数、SHA-256、JSON 与 `sourceHash` 都通过验证，才写入 payload 后更新 manifest 指针和界面。
5. `AssetsView` 显示“背包源 / 已发布 / 价格”三个独立时间；拉取失败时继续显示已验证缓存并显示离线标志，不伪装成新数据。

本次检查中，现有 `sync_receipt.json` 的四个阶段均为成功，且现有 `publish_receipt.json` 记录了一次成功发布。这证明本地工作树不是只有设计文档；不过每次排查“内容旧”仍要查看该次的 receipt、VPS manifest 和 App 当前 manifest，不能用一份历史成功回执替代实时检查。

## 产品和界面决策（接手时不要重新猜）

1. **军械库是一整套配置，不是一把武器的孤立计算器。** 主页面应围绕战甲、主武器、副武器、近战、同伴；后续再纳入物品和空战。它们可以互相影响。
2. **“已拥有列表”和“全物品目录”要分开。** 打开武器页面先显示背包中的武器；需要查全武器时再进入目录/搜索，不要用“所有武器列表”替换“我的武器”。
3. **层级应贴近游戏。** 选中一把拥有的武器后先进入它的配置；计算结果可在配置页预览，再进入详细计算页面。不要一点击物品就丢进空白通用计算器。
4. **输入应是游戏中的装备操作。** 用户装 Mod、石头、赋能、选择形态/攻击段、开关当前技能或外部 Buff；不要让用户输入由这些数据可推导的“武器伤害”“技能强度”等中间面板数。
5. **当前战甲与外部 Buff 都保留。** 前者从当前军械库配置派生；后者可选另一战甲/同伴/环境的可共享效果。二者不是二选一。
6. **紫卡词条按同级属性展示。** 元素伤害应在元素类，弹药效率在弹药类；不要把某个紫卡词条伪装成独立的武器面板参数或塞进“任意元素”。
7. **执政官石属于战甲配置。** 不应出现在武器属性层。灵化形态应只有一个清楚的启动状态，进化节点要与它一致；避免重复而含义不同的开关。
8. **文案使用正常中文。** 需要图片、中文名、搜索和可理解的单位/数量。不要用“执行路径缺口”“待确认项”这类不说明具体问题的词。尚未支持时必须直接写明是哪一个效果、哪一种攻击或哪一个数据字段没有计算。

## 还没有完成的事（按优先级）

### P0：把“计算正确”继续扩展成可复现的证据

已有基线不是一把武器：`Packages/DamageKit/Parity/website-cases.json` 当前有 34 条严格对照夹具，`compare_damagekit.js --strict --summary` 会在 CI 中运行。它已经覆盖自动步枪、手枪、霰弹、多段爆炸、近战、光束、弓、狙击、显赫武器、Laetum 灵化、Kuva Tonkor（赤毒征服榴炮，**不是** Kuva Zarr）、Kuva Bramma、状态、外部技能、灵化、赋能及部分自定义状态。当前远端 CI 的“Run complete website parity suite”已经通过。

接下来不能把这 34 条理解成“全部完成”，而应当：

1. 为用户自己的完整配置增加同样的对照夹具：攻击段、Mod 名称和实际等级、紫卡数值、赋能状态、灵化状态、战甲/同伴/外部 Buff、目标属性和等级都必须明确记录。
2. 对每条夹具保存绝对伤害、20 秒 DPS、每层伤害、实际射击/换弹时间线与状态伤害。差异小于 5% 才能标为数值通过；超过 5% 必须定位到公式、源数据或网站分支。
3. 对网站已知分歧单列“网站错误证据”，不要为了让数字相等把系数硬编码进输入层，也不要以一条夹具通过宣布完整模型完成。

### P0：敌人等级曲线仍不是独立重建

`Packages/DamageKit/Sources/DamageKit/EnemyProfile.swift` 当前以 Swift 执行了 warframe-damage 的 `showEnemy/correctEnemyLvl` 目标分支，包括其显示取整、卓越者和超宏分支。它满足“App 运行时不执行 JS”，也使网站对照可复现；但**它不能作为游戏真实等级曲线已被独立证明的证据**。网站与 Swift 同源时，即使数值完全相同，也只能证明翻译没有变形。

用户提供过一个 Wiki 报告：在 Simulacrum 生成 100 级和 145 级 Corrupted Heavy Gunner Eximus 时，Wiki 选择 107 和 152 级才与实测超宏值对齐。这提示可能存在敌人等级显示或缩放偏移，但只有一份玩家报告，不足以直接改公式。

已有的独立线索是：Warframe Wiki 的 Enemy Level Scaling/Eximus 页面说明基础属性按“基础值 × 等级差曲线”缩放、卓越者有单独的生命/护盾/护甲缩放，Corrupted Heavy Gunner 的基础等级为 8、基础生命 700、护甲 500；Wiki 同时说明卓越者与普通敌人以相同显示等级生成。它们能约束模型，却尚不足以解释“100 对应 107”的原因。

下一步：用官方补丁/数据字段、Wiki 公式、至少一份独立实测互相核对；若仍无法闭合，用户可以在游戏内测 120 级以下。记录原始截图、目标、等级、是否卓越者、钢铁之路和测量方式。达到证据标准后，应把 `EnemyProfile` 从“网站分支翻译”改成有来源、可单独验证的游戏公式，并保留网站差异为对照结果；在那之前，不要把等级曲线写成“已证实正确”或“已证实错误”。

### P1：补齐当前模型明确保留的边界

- `ammoCost: "all"` 的攻击在叠加分数弹药效率或无限弹药时，目前只给出一次按键的保守基线，不伪造普通弹匣时间线。需要把这类“清空弹匣”攻击独立建成状态机，再加入对照测试。
- 除已测试路径之外，条件 Mod、武器赋能、灵化节点、同伴 Mod、环境 Buff、特殊攻击段和状态交互仍要逐项与来源/网站/实测闭合。
- 不要把“输入能选到”当作“已正确计算”；每一种效果都要有来源、解析、计算、输出和测试五项证据。

### P1：完成军械库的前端重构

当前 UI 仍需要按上面的产品决策调整，尤其是：

- 背包优先的武器首页；
- 配置页与详细计算页分层；
- 战甲 Mod、石头、赋能、宠物 Mod 与外部环境 Buff 的分类；
- 灵化、石头和中文字体/对齐问题；
- 图片、中文搜索与结果预览；
- 紫卡新词条和元素词条的完整可见、可编辑、可验证展示。

### P2：资产/市场页面的文字和单位

“遗物 90 代号”“每张是什么单位”“一套缺 5 套”“已制成 77/162”“物品换杜卡德金币/白金汇总”这些表述和统计口径尚未厘清。不要继续使用让用户猜分类机制的写法；逐项写明计数对象、分母和价格范围后再改界面。

## 接手前先运行的命令

以下命令不会请求 DE 账号接口，也不会修改私有快照。PowerShell 示例：

```powershell
Set-Location C:\WarframeWorldState\Packages\DamageKit
swift test --scratch-path C:\Users\LocalAdmin\AppData\Local\Temp\damagekit-handoff-test

Set-Location C:\WarframeWorldState
python -X utf8 scripts/test_build_app_inventory.py
python -m py_compile scripts/wf_gamedata.py scripts/build_app_inventory.py scripts/test_build_app_inventory.py

node scripts/verify_website_bow_timeline_counterfactual.js --verify
gh run view 43357676158 --repo ireescc277-dotcom/Warframe-WorldState-iOS --json status,conclusion,jobs,url
```

若需要只检查 Swift UI 文件的语法：

```powershell
Set-Location C:\WarframeWorldState
swiftc -parse WarframeWatch/Models/InventoryModel.swift `
  WarframeWatch/Views/Arsenal/NativeDamageCalculatorModel.swift `
  WarframeWatch/Views/Arsenal/NativeDamageCalculatorView.swift
```

## Git 与私有数据注意事项

- 目前工作树里有用户此前留下的大量未跟踪文件，包括私有快照样本、JSON、网页资料和 `docs/`。它们不是本次提交的副产品，不能用 `git add .` 一并提交。
- 账号快照、账号 ID、紫卡名称/数值和任何凭据都不应进入 Git、日志或交接文档。
- 当前提交只包含源代码和测试。若要提交本交接文档，必须显式只添加 `docs/damagekit-handoff.md`，然后重新跑 CI；不要因为提交文档顺手清理或覆盖用户的未跟踪文件。
- 最新 Actions 运行对应 `269ce16`；在它结束前再推送会触发新的 CI。先看该运行结果，再决定是否推送交接文档。

## 原始需求与后续决策的优先顺序

`docs/damagekit-prompt.md` 规定了纯 Swift 核心、确定性计算、逐发时间线、分层血量、测试和数据来源的底线。后续用户明确增加/修正的要求优先于其中的早期范围描述：

- 目标已经从“只交付 Package + CLI”扩展为集成上级 iOS App 的军械库和配置体验；
- 数据导入先走 AlecaFrame/Overwolf 本机快照，不直接由 App 调 DE API；
- 不把 README 当作成果，不以“近似/未知”掩盖可以验证的规则；
- 不得把 Kuva Tonkor 混称为 Kuva Zarr；
- 与网站不一致时先做可重现实验和来源核验，再下结论。

接手后的第一项实际工作应是：选一套已保存的、完整可描述的武器配置，先完成“导入数据 → App 配置页 → DamageKit 输入 → 网站对照/分歧解释”的一条端到端证据链，然后按武器类型扩展，而不是先继续堆新的 UI 或猜新的公式。
