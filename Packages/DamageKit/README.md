# DamageKit

Warframe 伤害计算核心，纯 Swift，无 UIKit / WebView / 随机数，运行时不发网络请求。

**这是重新实现的，不是移植**：计算逻辑全部按 wiki 规则从零建模，没有把任何现成实现
搬进 Swift。用的只有 `web/app/site` 下的武器/敌人 JSON 和 `min.js` 里 `modsProps`
这份**数据**（由 `scripts/export_mods.js` 导出成 `mods.json`，见该脚本）。

> 说明：开发过程中曾为了排查一处数值差异读过 `min.js` 的函数实现，也拿它跑过对比。
> 那些对比结论**不构成实现依据，已作废**；本文件里所有规则都以「规则来源」一节的
> wiki 链接为准。相关临时脚本已删除。

```

Packages/DamageKit/
  Package.swift
  Sources/DamageKit/         核心库
  Sources/damagekit-cli/     读 JSON → 出 JSON 的可执行 target
  Tests/DamageKitTests/      48 个用例
  Fixtures/                  10 组固定输入 + 期望值
```

## 怎么跑

```bash
cd Packages/DamageKit

# 测试
bash ../../scripts/swiftw.sh test

# CLI（在仓库根目录跑）
bash scripts/swiftw.sh run --package-path Packages/DamageKit damagekit-cli \
  Packages/DamageKit/Fixtures/02-torid-mods.json --data-root web/app/site --pretty

# 只看装配后的中间量，排查「为什么是这个数」
... damagekit-cli <input.json> --dump-resolved

# 计时：先加载数据，再算 N 次取平均
... damagekit-cli <input.json> --repeat 50 --timing
```

`scripts/swiftw.sh` 是个薄包装：Windows 上 Swift 5.x 的 `ProcessEnvironment`
遇到 `HTTP_PROXY` 和 `http_proxy` 同时存在会直接 fatalError，包装脚本先清掉小写副本；
它同时负责设置 `SDKROOT`（`swift build` 不设会报 "unable to load standard library"）。

## 输入

```jsonc
{
  "weapon": "Torid",            // 也可以是完整的 weapon 对象
  "enemy":  "Heavy Gunner",     // 也可以是完整的 enemy 对象
  "level": 100,
  "build": {
    "mods": ["Serration", "Split Chamber"],   // 名字必须能在 mods.json 里找到
    "riven": {                                // 可选
      "damage": 1.65, "multishot": 0.9, "critChance": 1.2,
      "critDamage": 0.9, "statusChance": 0.6,
      "elements": { "heat": 0.9 }, "faction": 0.3
    },
    "incarnonPerks": ["19:0"]                 // "进化等级:选项序号"
  },
  "options": {
    "window": 20,              // 时间窗口（秒），1–60
    "steelPath": false,        // 等级 +100，生命/护盾/护甲 ×2.5
    "eximus": false,           // 卓越者独立生命曲线
    "squadSize": 1,            // 目前只做记录，未参与计算
    "armorStrip": 0,           // 外部削甲 0–1
    "externalViralStacks": 0,  // 开打前已有的病毒层数 0–10
    "headshot": false,
    "headshotMultiplier": 2.0,
    "distance": null,          // 给值才计算 falloff，不给按满伤害
    "weakPoint": false,        // Primary Acuity 这类条件 mod 用
    "warframe": {              // 战甲 buff，全部是小数
      "damageBonus": 0, "critChanceBonus": 0, "critDamageBonus": 0,
      "multishotBonus": 0, "fireRateBonus": 0,
      "statusDamageBonus": 0, "factionBonus": 0
    }
  }
}
```

mod 数据来自 `Resources/mods.json`（588 条，由 `node scripts/export_mods.js` 从
`min.js` 的 `modsProps` 数组做括号配对导出）。mod 与武器的兼容性按 `tags` 判定，
`tags` 既能是武器类别（`primary-rifle`）也能是具体武器名（`RIPKAS`），两边都归一化处理。

## 输出

```jsonc
{
  "weapon": "Torid", "enemy": "Heavy Gunner", "level": 100, "window": 20,
  "enemyStats": { "health": 83817.5, "armor": 2700, "shield": 0, "overguard": 0, "armorDR": 0.9 },
  "attacks": [
    {
      "attack": "Grenade Impact",
      "shots": 24,               // 窗口内实际打出的发数（多重射击按期望折算前的发数）
      "dps": 216.7,              // 该段**未减伤**的原始输出 ÷ W
      "directDamage": 2760.2,    // 原始直伤
      "dotDamage": 1573.9,       // 原始状态伤害
      "rawByType": { "toxin": 4334.1 },   // 未减免伤害，按类型分解
      "layers": [                // 四层各自独立，互不相加
        { "layer": "health", "maxHP": 83817.5, "damage": 433.4, "dps": 21.7,
          "byType": { "toxin": 433.4 }, "ttk": null },
        { "layer": "armor",  "maxHP": 2700,    "damage": 4334.1, "dps": 216.7,
          "byType": { "toxin": 4334.1 }, "ttk": 13.1 }
      ],
      "procs": { "poison": 5.52 },
      "notes": []
    }
  ],
  "notes": ["护甲已顶到 2700 上限（90% 减伤）"]
}
```

字段口径：

- `shots`：窗口内实际触发的发数，换弹时间真实扣除。
- `dps`：该段的**武器侧**输出 ÷ W。含 mod、暴击期望、多重、爆头；
  **不含**敌人侧的三项——派系倍率（×1.5/×0.5）、元素抗性、护甲/护盾减伤。
  每层的有效 DPS 在 `layers[].dps`。
- `ttk`：该层累计伤害第一次达到该层血量的时刻；窗口内打不到就是 `null`。
- `byType` / `rawByType`：伤害全程以「类型 → 数值」的向量累积，只在写结果时求和。
  某个类型被免疫或被抗性归零时，它在这张表里是 `0`，其余类型不受影响——
  不需要把总和拆回来重算。`byType` 是扣完减伤后的实际伤害，`rawByType` 是扣减伤前。
- `layers` 只输出血量 > 0 的层。`armor` 层按「护甲值池」处理，**不吃护甲减伤**
  （否则会和生命层重复计算），所有伤害类型对它一视同仁。

## 计算口径

1. 时间窗口 W 默认 20s；严格小于 W 的事件才计入，因此 DPS 不会超过「单发 × 射速」。
2. 每段攻击独立成账，各段各自 DPS / TTK。
3. 同一次开火产生的多段（武器 JSON 的 `comb`，例如 Torid 的 `[[0,1]]`）
   **共享同一个状态池**：A 段挂的病毒层会抬高 B 段的伤害；射速仍按各自 `speed`。
4. 逐发结算，状态按自己的持续时间和 tick 间隔独立推进。
5. 生命 / 护甲 / 护盾 / 超宏四层独立结算，各自抗性与减伤不同。
6. **伤害按类型分别记账，不提前求和**：每段攻击维护一张「类型 → 数值」的表，
   武器侧的 mod / 暴击期望 / 多重先落在这张表上，敌人侧的派系倍率、元素抗性、
   减伤再逐个类型作用。求和只发生在写结果时。所以遇到「某类型被免疫」时，
   把那一项算成 0 即可，其余类型不受影响，不需要把总和拆回来重算。
7. 全期望值：暴击用 `1 + CC × (CDM − 1)`（对橙暴红暴同样成立），
   触发用 `状态几率 × 多重射击 × 伤害占比`，**没有任何随机抽样**。
   为保证逐位可复现，所有伤害字典都按固定的 `DamageType.allCases` 顺序遍历
   （Swift 的 Dictionary 迭代顺序受哈希种子影响，直接累加会出现最后一位差异）。

## 规则来源

每一处数值都在 `Rules.swift` 的注释里标了出处。核心几条：

| 机制 | 结论 | 出处 |
|---|---|---|
| 暴击期望 | `1 + CC × (CDM−1)`，橙暴/红暴不改变均值 | wiki /Critical_Hit |
| 基础暴伤量化 | `floor(clamp(x,0,32)×4095/32+0.5) × 32/4095` | wiki /Critical_Hit#Quantization |
| 伤害类型修正 | Update 36.0 起按**派系**判，易伤 ×1.5 / 抗性 ×0.5 | wiki /Damage |
| 元素合并 | 按 Mod 槽位顺序两两合并，固有元素排最后 | wiki /Damage |
| 触发类型 | 按各类型伤害占比重抽，物理**无** 4× 权重 | wiki /Status_Effect |
| 状态伤害 | Slash 35%、Heat/Toxin/Electricity/Gas 50%，6 跳 | wiki /Damage、/Status_Effect |
| tick 相位 | Slash/Heat/Toxin 延迟 1s 起跳；Electricity/Gas 立刻起跳 | wiki /Status_Effect |
| 派系加成 | 对 DOT 二次结算 `(1+Bane)²` | wiki /Status_Effect（Bleed 示例算式）|
| 病毒 | 首层 +100%，每层 +25%，10 层 +325% | wiki /Damage/Viral_Damage |
| 腐蚀 | 首层 −26%，每层 −6%，10 层 −80% | wiki /Damage/Corrosive_Damage |
| 火焰 | 每跳 50%，2 秒内最多剥 50% 护甲 | wiki /Damage/Heat_Damage |
| 敌人护甲减伤 | `0.9 × armor / 2700`（≠ armor/(armor+300)） | wiki /Armor#Enemy_Damage_Reduction_Formula |
| 等级缩放 | 两端点曲线 + smoothstep，q∈[70,80] 过渡 | wiki /Enemy_Level_Scaling |
| 钢铁之路 | 等级 +100，生命/护盾 ×2.5 | wiki /The_Steel_Path |
| 多重射击 | 每弹丸独立掷暴击与触发 | wiki /Multishot |
| 灵化"Base"加成 | 一律加在**基础值**上的绝对量（+20% 暴率是 15→35，不是 ×1.2） | wiki /Torid（Evolutions 表）|
| 灵化固定伤害 | "Increase Base Damage by +51" 加进基础伤害，再吃 +伤害% 与元素 mod | wiki /Torid EVO2 |
| 灵化固定弹匣 | "Increase **Base** Magazine Capacity by +9"，先加固定值再吃 +弹匣% | wiki /Torid EVO3 |
| 灵化形态弹匣 | 灵化形态的弹匣不吃任何 mod（含灵化的 +9） | wiki /Torid（Overview）|
| 灵化多重 | "+3 Multishot on last shot in magazine" 只作用弹匣最后一发 | wiki /Torid EVO2 |
| 灵化作用段 | 选项的 `type` 与 `attacks[].name` 同名空间，空数组表示不限 | 数据字段 `incarnon[].type` |

等级缩放用的系数（`q = 当前等级 − 基础等级`）：

```
Health  Grineer/Scaldra  1 + 0.015q^2.12   →  1 + 10.7332q^0.72
        Corpus           1 + 0.015q^2.12   →  1 + 13.4165q^0.55
        Infested         1 + 0.0225q^2.12  →  1 + 16.0998q^0.72
        Corrupted        1 + 0.015q^2.1    →  1 + 10.7332q^0.685
        Murmur/Sentient  1 + 0.015q^2      →  1 + 10.7332q^0.5
        Techrot          1 + 0.02q^2.12    →  1 + 15.0998q^0.7
Shield  Corpus           1 + 0.02q^1.76    →  1 + 2q^0.76
        Corrupted        1 + 0.02q^1.75    →  1 + 2q^0.75
        Grineer/Sentient 1 + 0.02q^1.75    →  1 + 1.6q^0.75
        Techrot          1 + 0.02q^1.76    →  1 + 3.5q^0.76
Armor   全阵营            1 + 0.005q^1.75   →  1 + 0.4q^0.75
```

## 量级检查（任务书「验收」第 4 条）

Torid 无 mod 打 Lv100 重型机枪手（`Fixtures/01-torid-lv100.json`）：

| 指标 | 实测 |
|---|---|
| Grenade Impact 直伤 DPS | 138.0（任务书区间 50–200 ✅）|
| Grenade Impact 含 DOT 的 DPS | 216.7（略高于上沿）|
| 生命层 TTK | 20 秒内打不死 ✅（血量 83,818，20s 只打掉 433）|

含 DOT 的 216.7 高于参考区间，原因是规则本身：Toxin proc 每层 6 跳 × 50% = 300%
基础伤害，Torid 23% 触发率相当于 +69% 输出。按任务书「以规则为准，不要反过来调系数去凑」
保留，只在这里改口径说明。

## 性能

Release 构建，Windows / x86_64，数据已加载，`--repeat 50` 取平均：

| 场景 | 单次 |
|---|---|
| Torid（3 段，160+24+18 发，4 层） | 0.48 ms |
| Torid + 灵化 4 级进化 | 0.38 ms |
| Soma（3 段，212 发 + 流血/燃烧 DOT） | 4.1–5.1 ms |
| Ignis（2 段，火焰 DOT 拉满层） | 0.32 ms |
| 含数据加载（读 Torid.json + 497 条敌人表） | 16–20 ms |

Soma 这一档贴着 5 ms 上限：账本按「段 × 类型」用定长数组存（不是每发复制字典），
但 212 发 × 6 类型 × 2 层再加上每层各自跑一遍 DOT，仍然是这个量级。

## 已知不支持的项

不是「忘了」，是**没有把握**，所以留成显式缺口而不是猜一个数：

1. **mod 动作**：`mods.json` 的 `action` 有 93 种键，引擎实现的是
   `base / element / phys / crit_chance / crit_mult / status_chance /
   absolute_status_chance / multishot / speed / reloadTime / magazineSize /
   status_damage / status_duration / SMITE / mult_for_head / addViral / addMagnetic /
   addRadiation / set_speed_to_default / WITH_COND（headshot_mult、crit_chance_weakp、
   set_mutishot_to_default）`。其余（`base_per_status`、`double_crit`、`FOR_WEAPON`
   按武器类别覆盖、套装加成、`add_slash_on_impact` 等）会在输出的 `notes` 里点名。
2. **灵化进化**：已实现 `add_crit_chance / flat_crit_chance / flat_status_chance /
   flat_critmult / flat_change_dmg / add_magazineSize / base / flat_multishot /
   l_add_multishot`，并且按选项的 `type` 限定作用段。
   未实现的仍是条件型（`WITH_COND`：护甲 > 450、有超宏、击杀后、弹匣最后一发以外的时机）
   和改变机制的（`base_per_status`、`beam_length`、`initialCombo` 等），
   会在 `notes` 里按「未实现的灵化动作: …」或「灵化的条件加成未实现: <进化名>」点名。
3. **`squadSize`**：字段保留但未参与任何计算。
4. **蓄力武器**：`charge_time` 没有进射速模型。

## 待确认项

以下数值/口径**没有在 wiki 上核到明确表述**，实现里选了一个可解释的版本，
留在这里等实测或更强的来源：

1. **物理伤害的触发权重**：Damage 2.0 时代物理类型有 4× 权重，
   现版本 wiki 只写「按伤害占比」，按无权重实现（`Rules.physicalProcWeight = 1.0`）。
2. **超宏（overguard）**：`enemies-min.json` 里只有 4 个敌人带这个字段，
   且值很小（2 / 10 / 15 / 22），与生命不同量级，这里按「生命的倍数」解释。
3. **子派系抗性**：Kuva Grineer / Corpus Amalgam / Deimos Infested 只被说明
   「与母派系不同」但没给具体值，按母派系处理。
4. **Techrot / Scaldra 抗性**：Damage 页面未收录，按中性处理。
5. **爆头倍率**：按 2.0 的通用值，不同武器类别实际有差异，可用
   `options.headshotMultiplier` 覆盖。
6. **钢铁之路是否加成护甲**：官方 patch notes 早期写「生命+护甲+护盾 ×2.5」，
   wiki 的 Enemy Level Scaling 页面写「不再提升护甲」。按后者实现，
   且护甲本来就顶到 2700 上限，影响面很小。
7. **`armor` 层怎么定义**：需求文档要求「生命 / 护甲 / 护盾 / 超宏四层分开算」，
   但游戏里没有「护甲血条」这种东西——护甲的作用是减伤，不是一个可以被单独打空的池子。
   这里的解释是：把缩放后的护甲值当成一条独立血池，且这一层不吃护甲减伤
   （否则同一份护甲既当血条又当减伤，会重复计算）。这个建模选择没有 wiki 依据，
   属于为了让四层都能出数而做的约定。如果实际要用的是「打带护甲敌人的真实伤害」，
   应该看 `health` 层，不是 `armor` 层。
8. **多段共享状态池时的射速**：`comb` 成对的两段在真实游戏里是同一发产生的，
   这里仍按各自 `speed` 排时刻，只共享状态池。
9. **灵化的 `base` 是加算还是乘算**：Torid 的 Plentiful Mayhem 页明确写
   "Damage bonus from multishot consuming ammo is **multiplicative** to base damage
   bonuses like Serration"；但 Ack & Brunt 的 "Incarnon Form: +100% Melee Damage"
   这类写法是普通的 +伤害%（与压迫点加算）。`base` 统一按加算处理，
   因此 Torid 那一档会偏低约 30%（Serration 在身时 3.25× vs 正确的 4.24×）。
   要分开得靠逐条进化名的例外表，暂时不做。
10. **`Normal Attack` 的匹配**：`type` 里写 `Normal Attack` 的选项，遇到 Torid 这种
    没有同名攻击段的武器（段名是 `Grenade Impact` / `Poison Cloud`）时，
    按「非灵化形态」理解。若游戏实际只作用于"左键普攻"而非爆炸段，这里会偏高。
11. **灵化形态弹匣的换算**：`incMagazineSize`（Torid = 170）是整条灵化弹药的池子，
    而游戏里是「每次充能 34 发、最多 170」。这里当作弹匣用、并配 `reloadTime`，
    射速节奏与真实切换/耗尽行为不完全一致，20s 窗口内影响有限。
12. **固定伤害摊到多类型武器上**：`flat_change_dmg` 按该段原有伤害构成等比例摊开
    （Braton 这种 I/P/S 混合的武器会各得一份）。同一把武器的每个攻击段都各自加一份，
    包括毒云这类独立段。

## 与 App 的关系

App 里的计算器现在是 `WarframeWatch/Views/Arsenal/DamageCalcView.swift` 的 WKWebView 壳，
跑的是下载来的网页脚本。要换成 DamageKit，得在 App 里加一个调用 Swift 包的入口，
把这个壳替掉。这次没有改 App。

DamageKit 是确定性模型：同一输入两次结果逐位相同，不抽样。这一点和当前的壳不一样，
替换时要一起换掉「结果会浮动」这个预期。
