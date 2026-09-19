# DiskCleaner 磁盘清理

**原生 macOS 储存空间清理工具：带图形界面，自动保持至少 10GB 可用空间。**

DiskCleaner 会告诉你磁盘空间到底去哪了（整盘 + macOS「储存空间」风格分类），
列出每个应用占用了多少空间，并在后台安静地清理可重建的缓存与日志，
让你的 Mac 不会因为磁盘写满而卡住。

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](#环境要求)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

> English documentation: **[README.md](README.md)**

---

## 截图

**主界面** —— 可用空间/目标、硬盘与内存概览、macOS 风格储存空间分类（鼠标悬停看大小）、
以及每个应用的占用：

![DiskCleaner 主界面](docs/images/main-window.png)

**设置** —— 主题（跟随系统 / 浅色 / 深色）、后台自动清理、关于：

![DiskCleaner 设置](docs/images/settings.png)

---

## 功能

- **不再爆盘** —— 后台任务每小时检查一次，只有低于目标（默认 **10GB**）才清理，
  达到目标立刻停止，绝不"过度清理"。
- **看清空间去哪了** —— macOS「储存空间」风格彩色堆叠条：应用程序、文稿与桌面、下载、
  照片、音乐、影片、邮件与信息、开发者缓存、应用数据、系统与应用缓存、系统数据与其它、可用。
  **鼠标划入任意色块**显示精确大小；点 **123** 按钮可把数字直接标在色块上。
- **每个应用占用** —— App 本体 **+ 它的用户数据**（`~/Library/Containers`、
  `~/Library/Caches`、`~/Library/Application Support`），按大小排序，点击定位到 Finder。
- **数字和系统一致** —— 磁盘用十进制（`245.1 GB`，与 macOS 显示完全相同），
  内存用二进制（`16 GB`），符合 Apple 的两套惯例。
- **三级清理** —— 安全缓存 → 开发缓存 → 用户数据（默认只报告）。
- **零依赖** —— 纯 SwiftUI + 一个 shell 脚本，不需要 Homebrew / Python，
  只用系统自带的 Command Line Tools 即可编译。
- **纯本地** —— 不联网、不上传任何数据。
- **通用二进制** —— Apple Silicon 与 Intel 都能跑。

---

## 安装

### 直接下载

到 **[Releases](https://github.com/wang90/disk-cleaner/releases)** 下载 `DiskCleaner-v1.0.0-macos-universal.zip`
（标记为 *Pre-release*，即测试版），解压后把 `DiskCleaner.app` 拖进「应用程序」。

发布包是 **ad-hoc 签名**（未公证），首次打开会提示
*"Apple 无法验证 DiskCleaner 是否包含恶意软件"*，这是正常的 ——
看下面的 [Gatekeeper](#gatekeeper-首次打开被拦截) 十秒解决。

### 从源码构建

要求：macOS 14+，只需 **Command Line Tools**（不需要完整 Xcode）。

```bash
git clone https://github.com/wang90/disk-cleaner.git
cd disk-cleaner
./build.command          # 编译 DiskCleaner.app（通用二进制）并打开
```

`build.command` 只用 macOS 自带工具：`swiftc`、`sips`、`iconutil`、`codesign`、`lipo`。

如果提示缺少 `swiftc`：

```bash
xcode-select --install
```

---

## 使用

### 图形界面

打开 `DiskCleaner.app`：

| 控件 | 作用 |
|---|---|
| **目标** | 要保证的可用空间（5 / 10 / 15 / 20 / 30 / 50 GB） |
| **等级** | 1 安全（缓存/日志）· 2 开发缓存 · 3 用户数据 |
| **演练模式** | 只显示"会删什么"，不真正删除（默认开启） |
| **深度清理** | 忽略"空间已达标"，把所选等级完整清一遍 |
| **顺带释放内存** | 额外执行 `purge` 回收非活跃内存 |
| **后台自动清理** | 安装 LaunchAgent：登录时 + 每小时检查 |
| **123 按钮** | 在色块上显示/隐藏数字（鼠标悬停始终有效） |
| **点击某一行** | 在 Finder 中显示该目录；若是受限目录则申请权限 |
| **⚙️ 设置** | 主题（跟随系统 / 浅色 / 深色）、后台自动清理、文件位置 |
| **关于窗口** | 菜单栏 **磁盘清理 → 关于 磁盘清理**，或设置底部的按钮。独立窗口，展示功能说明、安全设计与相关链接 |
| **菜单栏小图标** | 随时点击查看可用空间 / 硬盘 / 内存，并有打开主窗口、清理、退出等快捷操作。可在 设置 → 菜单栏 里开关和配置 |

快捷键：`⌘R` 刷新 · `⇧⌘R` 重新扫描 · `⌘K` 清理 · `⌘L` 日志 · `⇧⌘S` 储存空间统计。

### 命令行

图形界面只是 `scripts/diskautoclean.sh` 的前端，脚本可以单独使用：

```bash
./scripts/diskautoclean.sh --status              # 磁盘 + 内存总览
./scripts/diskautoclean.sh --scan                # 各清理项占用
./scripts/diskautoclean.sh --apps                # 每个应用占用（Top 40）
./scripts/diskautoclean.sh --storage             # macOS 风格分类统计
./scripts/diskautoclean.sh --volumes             # 每个硬盘/卷（JSON）
./scripts/diskautoclean.sh --dry-run --force     # 演练一次完整清理
./scripts/diskautoclean.sh --target 20G          # 保持 20GB 可用
./scripts/diskautoclean.sh --quiet               # 给 cron / launchd 用
./scripts/diskautoclean.sh --help
```

所有查询模式都支持 `--json`，方便脚本化：

```bash
./scripts/diskautoclean.sh --status --json | jq .
```

---

## 工作原理

每次运行都遵循同一套逻辑：

```
读取可用空间 ──► 已经 ≥ 目标？ ──是──► 什么都不做，退出（约 1 秒）
                     │否
                     ▼
          按等级 1 → 2 → 3 清理
                     │
        每删一项就重新检查可用空间
                     │
        达到目标 ──► 立即停止（绝不过度清理）
```

| 等级 | 清理内容 | 风险 | 默认 |
|---|---|---|---|
| **1** | `~/Library/Caches`(>14天)、`~/.cache`(>14天)、Xcode DerivedData、模拟器缓存、崩溃报告(>7天)、**清空 >200MB 的超大日志** | 极低，软件会自动重建 | ✅ |
| **2** | npm / npx / pnpm / pip / Homebrew / Go / TypeScript / Yarn / uv / Electron / Playwright 缓存、Cargo、Gradle、旧 iOS 设备支持文件 | 低，需要时重新下载 | ✅ |
| **3** | Xcode 归档、iPhone/iPad 本机备份、废纸篓、`~/Downloads`(>90天) | 你的个人数据 | ❌ 只报告 |

第 3 级**必须**显式加 `--user-data` 才会真的删除。

超大日志（比如 20GB 的 `gateway.log`）是**清空内容而不是删除文件**，
这样正在写日志的进程不受影响，空间却立刻释放。

---

## 应用数据管理（含聊天记录）

应用列表里每一行右边都有一个 ⚙︎ 按钮，点开就是该应用的数据管理器：

```
┌ 微信 ──────────────────────────── com.tencent.xinWeChat ── 4.1 GB ─┐
│ ✅ 可以安全清理        缓存与日志，应用会自动重建                    │
│   ☑ Cache                       缓存      766 MB                   │
│   ☑ Code Cache                  缓存      194 MB                   │
│ ⚠️ 需要谨慎            可能含聊天记录、数据库、登录状态，删除不可恢复  │
│   ☐ Message                     用户数据  1.2 GB    🔒              │
│   ☐ History                     用户数据   18 MB    🔒              │
│   [ ] 我了解风险，允许选择上面这些项目                               │
│ 已选 2 项   960 MB                              [ 删除选中项 ]      │
└────────────────────────────────────────────────────────────────────┘
```

**分类规则**（按文件夹名字判断）

| 分类 | 匹配的名字 | 默认 |
|---|---|---|
| `缓存` | 含 `cache`、`tmp`、`temp`、`sparkle`、`shipit` 等 | ☑ 自动勾选 |
| `日志` | 含 `log`、`crashreport`、`diagnostic` | ☑ 自动勾选 |
| `用户数据` | 含 `message`、`chat`、`session`、`history`、`contact`、`storage`、`.db`、`sqlite`、`backup` 等 | 🔒 锁定 |
| `未知` | 其它一切 | 🔒 锁定 |

> ⚠️ **这只是按名字猜的，不保证准确。** 没有任何程序能靠文件名 100% 分辨"聊天数据库"和"缓存"。
> 没匹配上的一律按「未知」锁住。**删除聊天记录不可恢复，请先备份。**
> 工具**永远不会**自动碰这些用户数据——它们不在任何自动清理等级里。

**几点说明**

- macOS 的 TCC 会保护应用容器。如果读不到某个应用的数据目录，请在
  **设置 → 权限** 里给它「完全磁盘访问权限」，然后重新打开数据管理器。
- 有些应用会把数据放在 `~/Library` 之外（微信允许把聊天文件存到你自选的目录）。
  DiskCleaner 只扫描主目录下的标准位置，**不会**到处去找。
- 真正的删除由 `diskautoclean.sh --app-clean <路径>…` 执行，它会再次校验每个路径
  都在 `$HOME` 内且不在受保护列表里——所以即使界面有 bug，也删不掉
  `~/Documents`、`~/Library/Keychains` 这类东西。

## 安全设计

因为要能无人值守地跑，删除逻辑被设计得尽量"无聊"：

- **白名单机制**：所有清理目标都写死在脚本里，且必须位于你的主目录内。
- **受保护路径**：`~/Documents`、`~/Desktop`、`~/Pictures`、`~/Movies`、`~/Music`、
  `~/.ssh`、`~/Library/Keychains`，以及 `/System`、`/Library`、`/Applications`、`/usr` …
  即使规则写错也会被直接拒绝。
- **按时间判断**：只删"超过 N 天没动过"的内容，正在使用的缓存不会被动。
- **文件名安全**：用 `find -print0` + `read -d ''`，再奇怪的文件名也不会误删。
- **硬超时**：任何 `du` 卡住（失效网络卷、权限弹窗）都会在超时后被杀掉
  （脚本默认 40 秒，App 内 25 秒），扫描永远不会挂死。
- **拒绝 root**：除非显式加 `--allow-root`，否则不会以 root 运行。
- **单实例**：锁目录避免定时任务重入。
- **完整日志**：删了什么全部记录在 `~/Library/Logs/diskautoclean.log`。

---

## 权限说明

macOS 出于隐私保护会限制部分目录。DiskCleaner 会把它们标成
**「需授权 / permission needed」**，而不是报错退出 —— 这是正常现象，
不影响清理它有权限读的缓存。

点击界面上任何带锁标记的条目，它会：

1. 用 App 本体的身份去读 `~/Documents`、`~/Desktop`、`~/Downloads`、`/Volumes`，
   从而触发 macOS 的标准授权弹窗；
2. 打开 **系统设置 → 隐私与安全性 → 完全磁盘访问权限**；
3. 在 Finder 中选中 `DiskCleaner.app`，方便你直接拖进列表。

macOS 不允许 App 给自己授权，所以第 2、3 步必须由你手动完成。

---

## 后台自动清理

在界面上打开「后台自动清理」（设置里也有），会写入：

- `~/Library/Application Support/DiskAutoClean/diskautoclean.sh`
- `~/Library/LaunchAgents/com.local.diskautoclean.plist`
  （`RunAtLoad` + `StartInterval 3600`）

检查是否在运行：

```bash
launchctl list | grep diskautoclean
tail -f ~/Library/Logs/diskautoclean.log
```

### Gatekeeper 首次打开被拦截

发布包是 ad-hoc 签名，下载后会被加上隔离属性。两种解决办法：

- **右键 → 打开**，在弹出的对话框里再点一次「打开」；
- 或者直接去掉隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/DiskCleaner.app
```

正式签名 + 公证需要 Apple 开发者账号；如果你有，欢迎给发布流程提 PR。

---

## 项目结构

```
disk-cleaner/
├── Sources/                 # SwiftUI 应用
│   ├── App.swift            # @main、菜单、开发/截图模式
│   ├── ContentView.swift    # 仪表盘、储存空间条、设置页
│   ├── CleanerModel.swift   # 状态、扫描/清理、LaunchAgent、权限申请
│   ├── Models.swift         # Codable 数据结构、格式化、主题
│   └── Shell.swift          # 子进程封装（流式 + 捕获）
├── Resources/Info.plist
├── scripts/
│   └── diskautoclean.sh     # 整个清理引擎（bash）
├── tools/make_icon.py       # 生成应用图标（纯标准库）
├── docs/images/             # 截图
├── build.command            # 编译 .app
└── release.command          # 编译 + 打 zip + sha256 到 dist/
```

App 与脚本之间通过一套很小的 JSON 协议通信
（`--status --json`、`--scan --json`、`--apps --json`、`--storage --json`），
清理过程中消费 `@@` 前缀的进度行。

---

## 路线图

- [ ] **界面英文化**（目前只有简体中文）
- [ ] 为 JSON 协议补单元测试
- [ ] 「清理某个应用的数据」一键操作
- [ ] 用户自定义排除列表（永不清理的路径）
- [ ] GitHub Actions 自动签名 + 公证
- [ ] Homebrew Cask

---

## 参与贡献

欢迎提 Issue 和 PR，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。
如果要新增清理目标，请把它放到**正确的等级**，并注意不要破坏受保护路径规则。

## 许可证

[MIT](LICENSE) © 2026 wang90

## 致谢

- 图标由 `tools/make_icon.py` 程序化生成（无图片素材、无第三方依赖）。
- 用 SwiftUI 和大量 `du` 写成。
