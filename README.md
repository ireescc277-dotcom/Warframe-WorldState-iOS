# WarframeWatch (iOS 原生世界状态与监控)

Warframe 实时世界状态监控 iOS 原生 App（SwiftUI），由原先的单文件 `warframe-worldstate.html` 重写而来。

代码仓库：[GitHub - ireescc277-dotcom/Warframe-WorldState-iOS](https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS)  
本地工程目录：`C:\WarframeWorldState`

---

## 快速安装 (IPA)

目前已编译打包未签名 IPA，不需要开 Xcode 即可直接安装：

1. **直接下载（手机浏览器打开即可）**：
   - `https://data.ireescc.com/wf/app/WarframeWatch-v1.2.0.ipa`
2. **GitHub Releases**：[v1.2.0](https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS/releases/tag/v1.2.0)
3. **安装方式**：
   - **TrollStore (巨魔)**：直接分享到 TrollStore 点击 Install，永不过期。
   - **自签 / 证书**：导入爱思助手、SideStore、AltStore 或使用自备个人证书签名安装。

---

## 主要功能

### 1. 监控与关注
- **确定性周期**：希图斯（夜灵平野）昼夜、奥布山谷冷暖、虚空商人（Baro Ki'Teer）到达、突击与执政官猎杀重置。
  - *通知机制*：点击星标关注后，直接注册 iOS 本地通知（`UNUserNotificationCenter`），到期前在手机本地提醒，不需要任何 VPS 服务器或第三方推送软件。
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
python scripts/wf_publish.py             # 推到 VPS，App 启动时从这里拉
```

`wf_market.py sync --missing` 只补没抓过的，日常刷新用它。价格是快照，App 顶部会显示快照时间。

**抓价有限速**：官方文档写明公共 API 是 3 req/s，契约类端点只有 10~20 req/min，规则页还要求 User-Agent 可识别、要求缓存而非紧密轮询。这里主动压到配额的一半——任意两次请求之间至少隔 0.55 秒（加 0~0.2 秒抖动）、并发 2，全量 835 件约 9 分钟；遇到 429 优先按 `Retry-After` 退避。别把 `--workers` 调大。

**不想手动跑就交给监听**：

```bash
python scripts/wf_watch.py            # 常驻，10 秒看一眼 lastData.dat
python scripts/wf_watch.py --once     # 立刻同步一次
```

文件一变就走完整条链路（解密 → 重建 → 打包数据 → 推 VPS）。AlecaFrame 每几十秒重写一次这个文件，所以脚本要求 `(mtime, size)` 连续两次采样一致才动手，避免读到写了一半的内容。价格不跟着背包变化重抓，默认 12 小时补一次缺（`--market-every 0` 关掉）。Windows 上双击 `scripts/wf_watch.cmd` 即可在后台跑，日志在 `data/watch.log`。

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
