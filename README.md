# WarframeWatch (iOS 原生世界状态与监控)

Warframe 实时世界状态监控 iOS 原生 App（SwiftUI），由原先的单文件 `warframe-worldstate.html` 重写而来。

代码仓库：[GitHub - ireescc277-dotcom/Warframe-WorldState-iOS](https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS)  
本地工程目录：`C:\WarframeWorldState`

---

## 快速安装 (IPA)

目前已编译打包未签名 IPA，不需要开 Xcode 即可直接安装：

1. **直接下载（手机浏览器打开即可）**：
   - `https://data.ireescc.com/wf/app/WarframeWatch-v1.5.1.ipa`
2. **GitHub Releases**：[v1.5.1](https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS/releases/tag/v1.5.1)
3. **安装方式**：
   - **TrollStore (巨魔)**：直接分享到 TrollStore 点击 Install，永不过期。
   - **自签 / 证书**：导入爱思助手、SideStore、AltStore 或使用自备个人证书签名安装。

---

## 主要功能

### 1. 监控与关注
- **确定性周期**：希图斯（夜灵平野）昼夜、奥布山谷冷暖、虚空商人（Baro Ki'Teer）到达、突击与执政官猎杀重置。
- **提醒（本地通知）**：蹲守页的「开打提醒」开关打开后：
  - 仲裁、周期、重置这类时间确定的事件，按排程提前 5 分钟注册本地通知，**App 关掉也会响**；星标的社区目标提前 30 分钟。
  - 裂隙、入侵、风暴没有排程，只能刷新到才知道，所以退到后台时才会补一条；后台刷新由系统调度，不保证频率。
  - 全部走 `UNUserNotificationCenter` 本地通知，不需要 VPS 推送、不需要 APNs。
- **服务器端监控（推送）**：本地通知覆盖不到裂隙/入侵/风暴，这部分交给 VPS：
  - `wf-notify.service` 读 recorder 每 120 秒采集的同一个 SQLite 库，把新出现的事件和蹲守路径做前缀匹配，命中就推手机。
  - 在 App 的蹲守页勾选目标即可，选择会在 1.5 秒防抖后自动 POST 到 VPS，两边用同一套路径。
  - 推送通道走 [ntfy](https://ntfy.sh)（装 App 订阅一个 topic 即可）或 Bark（更稳，需要设备 key）；不需要 Apple 开发者账号。
- **随机事件监控**：
  - 核心奖励：Orokin 催化剂、Orokin 反应堆、Forma、特殊功能槽连接器、裂罅碎石、卡瓦特基因、泥丸（Nitain 萃取物）、奥罗金电池、突变原聚合物、电磁盒、爆燃安瓿，以及亡魂/破坏者武器部件入侵。
  - 裂隙全量过滤：古纪、前纪、中纪、后纪、安魂、全能 × 捕获/灭绝/救援/防御/生存/移动防御/中断 × 普通 / 钢铁之路。
- **界面精简**：
  - 去除重复的多层嵌套滚动条与无意义切页，顶栏只保留搜索框与 `[★ 仅看关注]` 开关。

### 2. 官方简中校对
所有派系、模式、关卡节点与物品名称严格统一为 Digital Extremes 官方简体中文标准：
- 模式：`钢铁之路`（不使用任何误译名称）。
- 阵营：`Corpus`、`Grineer`、`Infested`、`堕落者`、`Sentient`、`低语者`、`合一众`、`Tenno`。
- 任务：`升腾`、`无尽捕获`、`资源回收` 等。

### 3. 资产（背包与行情）
把库存当资产看，而不是待办清单。三个分段：

- **套装**：162 个 Prime 装备按「完整制作包」聚合（战甲 4 件：蓝图 / 机体 / 头部神经光元 / 系统；武器 3–5 件）。标出已成套、可制造、缺几件，以及每套的余件可变现价值。点开看四个部件的持有数、市场价、Ducats，以及「整卖还是拆卖」的差额。
- **遗物**：76 个代号 × 四档精炼的持有量、market 价、能补几个还没凑齐的套装。
- **Aya**：当期 Varzia 用 Aya 换的遗物，带市场价和「是否已有」。

**数据从哪来**（全部离线，零网络请求、不碰游戏进程）：

| 项 | 来源 |
| :--- | :--- |
| 背包 | `%LocalAppData%\AlecaFrame\lastData.dat`，AES-128-CBC，key 由 Sainan/alecaframe-inventory-parser 公开，本地解密 |
| 价格 | `api.warframe.market/v2`，按 `gameRef` 与背包的 `/Lotus/...` uniqueName 精确匹配 |
| Ducats | AlecaFrame 字典里的 `Components.json`（`primeSellingPrice`） |
| Aya | `api.warframestat.us/pc` 的 `vaultTrader.inventory`（`credits=1` 的条目） |

价格只取**在线卖家的最低价**。market 的卖单最低价里有 1p 钓鱼单，用它会把 Lavos Prime 整套算成 1p。

**刷新数据**（在电脑上跑，产物推到 VPS，不进仓库）：

```bash
python scripts/wf_inventory.py read      # 解密 lastData.dat → data/inventory/
python scripts/build_inventory_view.py   # 生成 view.json 与网页版 view.html
python scripts/wf_market.py items        # 拉 market 商品目录
python scripts/wf_market.py sync         # 抓价格（首次约 2.5 分钟）
python scripts/fetch_icons.py            # 套装/遗物缩略图 → Asset Catalog
python scripts/build_app_inventory.py    # 合并 → WarframeWatch/Resources/InventoryData.json
python scripts/build_arb_schedule.py     # 仲裁排程（browse.wf）→ data/world/arb.json
python scripts/wf_publish.py             # 推到 VPS，App 启动时从这里拉
```

`wf_market.py sync --missing` 只补没抓过的，日常刷新用它。价格是快照，App 顶部会显示快照时间。

**仲裁为什么不用概率**：仲裁的轮换表（`browse.wf/arbys.txt`）是确定性的，每小时一场，已经排到 2029 年。所以 App 显示的是「现在这场是谁、还剩多久」和「下一场几点」，不是「24 小时内出现的概率」。顺带一提，`api.warframestat.us/pc/arbitration` 现在永远返回 `SolNode000` 占位（activation 1970、expiry +275760），已经不能用了，排程是唯一可靠来源。

**抓价有限速**：官方文档写明公共 API 是 3 req/s，契约类端点只有 10~20 req/min，规则页还要求 User-Agent 可识别、要求缓存而非紧密轮询。这里主动压到配额的一半——任意两次请求之间至少隔 0.55 秒（加 0~0.2 秒抖动）、并发 2，全量 835 件约 9 分钟；遇到 429 优先按 `Retry-After` 退避。别把 `--workers` 调大。

**不想手动跑就交给监听**：

```bash
python scripts/wf_watch.py            # 常驻，10 秒看一眼 lastData.dat
python scripts/wf_watch.py --once     # 立刻同步一次
```

文件一变就走完整条链路（解密 → 重建 → 打包数据 → 推 VPS）。AlecaFrame 每几十秒重写一次这个文件，所以脚本要求 `(mtime, size)` 连续两次采样一致才动手，避免读到写了一半的内容。**背包是 10 秒轮询、变化即同步**，与价格无关。

价格单独一条线，跑在独立线程里：每 12 小时检查一次，其中每 24 小时全量重抓（835 件约 9 分钟），其余时候只补缺。刷价期间照样盯背包，不会被拖住；刷完立刻重建一次并发布。`--market-every 0` 关掉价格这条线。

Windows 上不用双击：已经注册了计划任务 `WarframeWatch Sync`（登录时启动、崩了自动重启），也可以手动 `scripts/wf_watch.cmd`，日志在 `data/watch.log`。

> App 资产页顶部显示的「背包 MM-dd HH:mm」是游戏自己写的 `LastInventorySync`，不是同步时间。人不进游戏，这个时间就不会动；数据本身仍是每次变化都推。

凭据放 `.env.local`（已 gitignore）：

```
WF_VPS_HOST=...
WF_VPS_PASS=...
WF_PUBLISH_TOKEN=...
WF_PUBLISH_BASE=https://data.ireescc.com
```

**账号数据不随 App 发布**：`InventoryData.json` 里有白金、星币和每件部件的持有数，等同账号信息，所以文件在 `.gitignore` 里。仓库只提交 `InventoryData.sample.json`（裁到 14 套 / 12 个遗物、余额归零），CI 打包时复制成正式名。真数据推到 VPS 后，App 用 CI 从 secret `INVENTORY_URL` 注入的地址去拉，缓存在本机；拉不到就用手里那份。

---

## 本地代码目录结构

```
C:\WarframeWorldState\
├── README.md                      # 本说明文档
├── warframe-worldstate.html       # 原版 Web 监控单页
├── project.yml                    # XcodeGen 工程配置文件
├── Package.swift                  # Swift 依赖与构建配置
├── WarframeWatch/                 # iOS 源码目录
│   ├── WarframeWatchApp.swift     # App 入口
│   ├── Models/                    # 数据模型（世界状态、监控矩阵、历史记录）
│   ├── ViewModels/                # 视图逻辑（轮询刷新、关注流过滤）
│   ├── Views/                     # SwiftUI 视图（大盘、任务列表、监控页、设置）
│   ├── Services/                  # 网络请求、官方中文词典、本地通知、本地存储
│   └── Resources/                 # 离线快照与官方中文对照字典
├── Tests/                         # 单元测试（模型解析、词典查找）
├── scripts/                       # 自动化验证脚本（CI 解码测试、VPS 监控）
└── .github/workflows/             # GitHub Actions 自动化编译打包流水线
```

---

## 编译与打包

- **云端自动打包**：每次推送到 GitHub 或打 Git Tag（如 `v1.1.0`），GitHub Actions 会自动运行 Swift 测试、通过真机/模拟器构建并发布 Release，产出未签名 `.ipa`。
- **本地打开调试**：
  - Windows 环境已生成完整工程结构，可通过 VS Code 或 Git 维护。
  - macOS 环境下执行 `xcodegen generate` 即可生成 `WarframeWatch.xcodeproj` 直接真机调试。

---

## iOS 军械库与原生伤害计算

App 内的「军械库」不是全武器数据库的快捷入口。它先读账号快照，再按游戏里的装备关系展示：

- **战甲与武器**：来自 `LoadOutPresets.NORMAL`。战甲、主武器、副武器、近战和重型武器各自保留快照记录的 A/B/C 配置。
- **同伴**：来自 `LoadOutPresets.SENTINEL`。同伴本体与同伴武器分别显示；宠物武器在账号快照的 `SpecialItems` 中，而不一定在 `SentinelWeapons` 中。
- **物品**：来自 `EquippedGear`，按装备轮槽位顺序显示。只有快照的消耗品堆栈记录了数量时才显示数量；没有数量记录的部署器不会被写成“1 个”。
- **Archwing**：来自 `LoadOutPresets.ARCHWING`，其中 Archwing 本体、Archgun 和 Arch-melee 各有独立 A/B/C 配置。

这三类预设在账号数据中是三套独立记录。页面把它们放在同一个军械库总览中，方便像游戏内军械库一样查看；但不会把它们说成 DE 已经记录为同一套联动配置。

点武器后先进入配置页，再进入计算器。计算器带入该武器配置和当前战甲配置：

- 当前战甲的技能、Mod、赋能和执政官石只来自所选战甲实例及其 A/B/C 配置。
- 外部战甲 Buff 仍然保留为另一名施法者：选择外部施法者及其 A/B/C 配置后加入。它不会覆盖当前战甲，也不会和当前战甲共用一个手填“技能强度”。
- 同伴、Archwing 本体和同伴武器的配置页会显示每张已装 Mod/赋能的实际等级。只有已经有原生伤害规则的效果才会加入计算结果；其余卡保留名称和等级供核对，不会被猜成满级或任意伤害词条。

账号快照有时只在配置槽位里记录 Mod 类型，没有记录具体是哪一张卡。若背包里同名卡等级不唯一，App 会直接显示“等级未确认”，并且不把它算作满级或自动增伤。

---

## 伤害计算（Web，前后端分离）

线上地址：<https://data.ireescc.com/dps/>

前一版 `web/dps/` 是把数据和公式全塞进一个 HTML 的单文件版（仍然可用，离线双击即开）。
现在拆成三层，公式只有一份：

| 层 | 位置 | 干什么 |
| --- | --- | --- |
| 数据 | `scripts/build_dpsapp.py` → `server/data/payload.json` | 读 DE 导出 + 本机 lastData，产出武器/mod/敌人/灵化/紫卡 |
| 计算 | `server/engine.js` | 纯函数内核，服务端和页面共用；`scripts/dps_parity.js` 逐值对拍 |
| 接口 | `server/api.js` | Node 24，127.0.0.1:8793，另兼静态文件 |
| 前端 | `web/app/` | 只做界面与状态，所有数字走 `./api/*` |

接口：`/api/meta`、`/api/weapon?uid=`、`/api/mods?cat=`、`/api/calc`（POST）、`/api/rank`（POST）、`/api/health`。

```bash
python scripts/build_dpsapp.py                      # 重建数据（同时写 data.js 和 payload.json）
node server/api.js                                  # 本地起服务 → http://127.0.0.1:8793/
node scripts/dps_api_test.js http://127.0.0.1:8793  # 接口自检
node scripts/dps_ui_check.js http://127.0.0.1:8793/ # 无头浏览器量布局、点交互、截图

WF_VPS_HOST=... WF_VPS_PASS=... python scripts/wf_deploy_dps.py
WF_VPS_HOST=... WF_VPS_PASS=... python scripts/wf_deploy_dps.py --payload-only   # 只换数据
```

服务端 `/srv/wf-dps/{server,server/data,web/app}`，systemd 单元 `wf-dps.service`，
nginx 只加一条 `location /dps/` 反代到 8793（`/etc/nginx/snippets/wf-dps.conf`）。
payload 换了不用重启：api.js 按文件 mtime 自动重载。

### 条件选项

口径对着 <https://warframe-damage.com/zh/> 的「更多选项」做的，分组和默认值一致：

| 组 | 项 | 参数 | 生效方式 |
| --- | --- | --- | --- |
| 外部条件 | 外部病毒 | 1-10 层 | 叠加到敌人身上的病毒层数上限 |
| | 技能强度 | 0-1000%，默认 100 | 缩放下列三个技能 buff |
| | 爆头 | 开关 | 总伤 ×2 |
| | 减少目标防御 | 0-99% | 护甲乘 (1-p) |
| | 连续射击/攻击时间 | 1-60 秒，默认 20 | 状态推演窗口 |
| 近战 / 连击 | 潜行加成 | 开关 | 暴击倍率 +7（1 倍时变 7），近战限定 |
| | 轻攻击连击倍数 | 1-13 | 近战总伤乘该倍率 |
| | 狙击连击倍数 | 1.5-100 | 总伤乘该倍率 |
| 战甲 / 技能 | 战吼 (Rhino) | 百分比 | 并入阵营倍率（有阵营 mod 时相加） |
| | 黯然失色 (Mirage) | 百分比 | 独立乘区 |
| | 真理密语 (Xaku) | 百分比 | 按总伤挂一段虚空伤害 |
| | 剧毒鞭笞 (Saryn) | 百分比 | 按总伤挂一段毒素伤害 |
| | 消化滋养 (Grendel) | 百分比 | 按总伤挂一段病毒伤害 |
| | 绝对增加暴击几率 | 百分比 | 暴击率绝对值相加 |
| | Madurai | 开关 | 物理三系 ×1.3 |

0 表示该项关闭（数值框保留上次填的数）。`scripts/dps_snapshot.js` 可以导出默认参数下
全部配卡的 burst/dps/ttk 快照，用来确认改动没有污染默认结果。

那个站还有三项依赖条件型 MOD 的数值（异况超量按乘法、手动指定敌人身上状态数、
所有 MOD 条件默认满足），本地 MOD 表还解析不出这些字段，暂时没放进来。
近战重击也缺动作倍率数据，同样没做。
