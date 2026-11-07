# WarframeWatch (SwiftUI / iOS / iPadOS / macOS)

基于原生 **Swift 5.9+ / SwiftUI** 完全重构的 **Warframe 世界状态看板 (Warframe World State Monitor)**。

本项目将原有 Web 端单页应用的所有功能（包括每日突击、执政官猎杀、虚空商人商品检索、限时警报、入侵对抗、虚空裂隙、全服目标、午夜电波、关注提醒、快照差异对比等）完整重写为高性能、纯原生的 Apple 风格应用程序。

---

## 📱 界面设计亮点 (Redesigned Native UI)

| 模块 | 设计思路与实现 |
| :--- | :--- |
| **虚空暗黑主题** | 采用 Warframe 经典深空底色 (`#0A0E17`) 与面板微光 (`#141D27`)，搭配奥罗金金 (`#E9C579`)、天诺青 (`#5FD0E0`)、护盾绿 (`#79C99A`)、警报红 (`#EC7B72`) 与莲花紫 (`#B39CE8`)。 |
| **实时倒计时组件** | 秒级心跳驱动，动态三态显色：正常状态（绿色）、临近1小时（奥罗金金）、已过期（警报红），并智能格式化天、时、分、秒。 |
| **突击三阶段英雄卡** | 阶段式导航展示：关卡节点、任务类型、突击异常词缀（如辐射灾害、能量减少），并附带战术攻略指南。 |
| **双向拔河对抗入侵进度条** | 自定义双向进度条，直观展示 Grineer / Corpus / Infested 阵营拉锯走势，左右分列双方支援奖励。 |
| **虚空商人全量检视器** | 专用 Sheet 弹窗，支持对 Baro Ki'Teer 50+ 项商品进行即时搜索、杜卡德金币与现金排序。 |
| **星标关注与本地提醒** | 一键将任意任务、特惠或突击加入清单；内置 `UNUserNotificationCenter`，在到期前 30 分钟通过系统通知唤醒玩家。 |
| **数据指纹差异对比 (Diff)** | 每次抓取新数据时自动生成指纹哈希，直观高亮新增任务 (`+`)、已下线任务 (`-`) 和指标变动 (`~` 如进度推进、库存剩余)。 |

---

## 🛠️ 项目工程结构

```
wf_worldstate_ios/
├── README.md
└── ios_app/
    ├── Package.swift                    # Swift Package 清单
    └── WarframeWatch/
        ├── WarframeWatchApp.swift       # 应用入口与外观全局配置
        ├── Theme/
        │   └── WFTheme.swift            # 调色板、圆角、阴影与渐变系统
        ├── Models/
        │   ├── MongoExtendedJSON.swift  # 核心：兼容 MongoDB $date, $oid 与长整型时间戳解析
        │   ├── WorldState.swift         # 根世界状态模型
        │   ├── FocusModels.swift        # 突击、执政官、虚空商人、每日特惠、全局增益
        │   ├── MissionModels.swift      # 裂隙、警报、入侵、风暴、全服目标
        │   ├── CommunityModels.swift    # 午夜电波、集团任务、商城促销、官方新闻
        │   ├── WatchItem.swift          # 关注收藏与提醒模型
        │   └── SnapshotDiff.swift       # 快照指纹与增量差异模型
        ├── Services/
        │   ├── DictionaryService.swift  # 完整中文词典 (节点/任务/派系/词缀/首领/物品规则)
        │   ├── NotificationService.swift# 原生 UNUserNotificationCenter 调度器
        │   ├── StorageService.swift     # UserDefaults 数据持久化 (收藏项与快照历史)
        │   └── WorldStateService.swift  # URLSession 异步抓取与离线兜底缓存
        ├── ViewModels/
        │   └── WorldStateViewModel.swift# 核心 ViewModel：秒级定时器、全局筛选、搜索与 Diff 计算
        ├── Views/
        │   ├── MainTabView.swift        # 底部 5 大 Tab 导航
        │   ├── Components/              # 通用原子组件 (倒计时、卡片、星标、进度条、标签)
        │   ├── Dashboard/               # 焦点看板 (KPI、突击卡片、虚空商人、特惠)
        │   ├── Missions/                # 任务列表 (裂隙纪元筛选、钢韧模式切换、入侵拔河)
        │   ├── Hub/                     # 社区与枢纽 (全服目标、午夜电波、新闻与促销)
        │   ├── Watchlist/               # 关注清单与实时数据变动对比
        │   └── Reference/               # 突击词缀指南、API 元数据与原始 JSON 检视器
        └── Resources/
            ├── DefaultDict.json         # 内置全量中文对照字典
            └── DefaultSnapshot.json     # 离线兜底快照数据 (确保开箱即用)
```

---

## 🚀 核心技术实现细节

### 1. MongoDB Extended JSON 智能解析器 (`WFDate` & `WFOID`)
官方 Warframe API 包含许多 MongoDB 扩展格式，如 `{"$date": {"$numberLong": "1793984400000"}}` 或秒级时间戳。通过编写自定义 `SingleValueDecodingContainer` 解析逻辑，支持：
- `{"$date": {"$numberLong": ...}}`
- `{"$date": 1793984400000}`
- 秒级 / 毫秒级原生数值
统一转换为 Swift 的 `Date` 类型，保证零崩溃解码。

### 2. 词条翻译与物品路径自适应引擎 (`DictionaryService`)
内置 WFCD 权威中文数据源，并实现自适应规则匹配：
- 节点：`SolNode129` -> `奥布山谷 (金星)`
- 任务：`MT_MOBILE_DEFENSE` -> `移动防御`
- 强化：`SORTIE_MODIFIER_HAZARD_RADIATION` -> `辐射灾害`
- 路径规则：`/Lotus/Types/Recipes/Weapons/WeaponParts/KarakWraithBarrel` -> `卡拉卡·亡魂 枪管`

### 3. 本地到期提醒通知 (`NotificationService`)
- 自动向 iOS 请求通知权限。
- 在每个关注条目的 `expiry` 前 30 分钟建立精确的本地触发器 (`UNTimeIntervalNotificationTrigger`)。
- 当用户取消关注时，自动清理队列中的待发送通知。

---

## 🖥️ 如何在 Xcode 中运行

1. 打开 **Xcode** (支持 Xcode 15 / 16+)。
2. 选择 **File -> Open...**，选择 `wf_worldstate_ios/ios_app` 目录（将自动识别为 Swift Package）或者新建一个 iOS App 工程后将 `WarframeWatch` 源码拖入。
3. 选择目标模拟器（如 `iPhone 16 Pro` 或 `iPad Pro`）。
4. 点击 **Run (⌘ + R)** 即可启动！
   - 应用内置了完整的离线快照，无网络环境下也能立即浏览完整界面。
   - 联网状态下可下拉刷新，从 `https://api.warframe.com/cdn/worldState.php` 获取最新世界状态。
