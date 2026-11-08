# WarframeWatch (iOS 原生世界状态与监控)

Warframe 实时世界状态监控 iOS 原生 App（SwiftUI），由原先的单文件 `warframe-worldstate.html` 重写而来。

代码仓库：[GitHub - ireescc277-dotcom/Warframe-WorldState-iOS](https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS)  
本地工程目录：`C:\WarframeWorldState`

---

## 快速安装 (IPA)

目前已编译打包未签名 IPA，不需要开 Xcode 即可直接安装：

1. **局域网直接下载（同一 WiFi 下手机浏览器打开）**：
   - 链接：`http://192.168.0.112:8080/WarframeWatch-unsigned.ipa`
   - 或者桌面文件：`C:\Users\LocalAdmin\Desktop\WarframeWatch-v1.0.9.ipa`
2. **GitHub Releases**：
   - [v1.0.9 页面下载](https://github.com/ireescc277-dotcom/Warframe-WorldState-iOS/releases/tag/v1.0.9)
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

- **云端自动打包**：每次推送到 GitHub 或打 Git Tag（如 `v1.0.9`），GitHub Actions 会自动运行 Swift 测试、通过真机/模拟器构建并发布 Release，产出未签名 `.ipa`。
- **本地打开调试**：
  - Windows 环境已生成完整工程结构，可通过 VS Code 或 Git 维护。
  - macOS 环境下执行 `xcodegen generate` 即可生成 `WarframeWatch.xcodeproj` 直接真机调试。
