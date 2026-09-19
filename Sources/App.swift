import SwiftUI

@main
struct DiskCleanerApp: App {
    // 菜单栏图标由 AppKit 的 MenuBarController 负责（见该文件顶部注释）
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = CleanerModel.shared
    @Environment(\.openWindow) private var openWindow

    /// Dev/screenshot modes. Accepts either a launch argument or the env var
    /// `DISKCLEANER_UI=settings|about|demo` (env vars survive `open -n App.app`).
    static var uiMode: String? {
        if let v = ProcessInfo.processInfo.environment["DISKCLEANER_UI"], !v.isEmpty { return v }
        if CommandLine.arguments.contains("--settings-only") { return "settings" }
        if CommandLine.arguments.contains("--about-only") { return "about" }
        if CommandLine.arguments.contains("--demo") { return "demo" }
        return nil
    }

    /// `--settings-only` / `--about-only` render those pages as the window content
    /// (used for docs screenshots; normally they are a sheet / a separate window).
    @ViewBuilder
    private var rootView: some View {
        switch DiskCleanerApp.uiMode {
        case "settings":
            SettingsView(model: model)
                .frame(width: 640, height: 660)
        case "about":
            AboutView(model: model)
        default:
            ContentView(model: model)
                .frame(minWidth: 900, idealWidth: 1000, minHeight: 620, idealHeight: 780)
        }
    }

    private var windowWidth: CGFloat {
        switch DiskCleanerApp.uiMode {
        case "settings": return 680
        case "about":    return 500
        default:         return 1000
        }
    }

    private var windowHeight: CGFloat {
        switch DiskCleanerApp.uiMode {
        case "settings": return 720
        case "about":    return 620
        default:         return 800
        }
    }

    var body: some Scene {
        WindowGroup("磁盘清理", id: "main") {
            rootView
                .preferredColorScheme(model.theme.colorScheme)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: windowWidth, height: windowHeight)
        .commands {
            AppCommands(model: model)
        }

        // 独立的「关于」窗口（可同时开着主窗口）
        WindowGroup("关于 磁盘清理", id: "about") {
            AboutView(model: model)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // 菜单栏常驻小图标由 AppKit 的 MenuBarController 实现
        // （SwiftUI 的 MenuBarExtra 在这套工具链上会随机启动崩溃，见该文件注释）
    }
}

/// 菜单命令单独放在一个 `Commands` 结构体里。
///
/// 踩过的坑：如果直接把这些 Button + `.keyboardShortcut(...)` 写在
/// `App.body` 的 `.commands { }` 里，本机这套 Swift 工具链会为
/// `View.keyboardShortcut(_:)` 生成**递归的不透明类型**，运行时解析类型元数据
/// 时栈溢出崩溃：
///     EXC_BAD_ACCESS / SIGSEGV "Could not determine thread index for stack guard region"
///     栈顶反复出现 View.keyboardShortcut(_:)
/// 抽成独立的 Commands 类型后即可正常，功能与快捷键完全不变。
struct AppCommands: Commands {
    /// 故意用 `let` 而不是 `@ObservedObject`：菜单只要订阅了模型，
    /// 模型一变化（启动时 bootstrap 会连续更新十几次）SwiftUI 就要重建整棵菜单，
    /// 在本机这套工具链上会触发 _makeView 的无限递归 → 栈溢出崩溃。
    /// 改成不订阅后菜单内容是静态的，菜单项照常工作。
    let model: CleanerModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // 保留系统默认的「新建窗口」(⌘N)，这样用户关掉主窗口后还能再打开

        // 标准位置：「磁盘清理」菜单 →「关于 磁盘清理」
        CommandGroup(replacing: .appInfo) {
            Button("关于 磁盘清理") {
                openWindow(id: "about")
            }
        }

        CommandMenu("操作") {
            Button("刷新状态") {
                Task { await model.refreshStatus() }
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("重新扫描") {
                Task { await model.scan() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("开始清理") {
                Task { await model.clean() }
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("显示 / 隐藏日志") {
                model.showLogs.toggle()
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("储存空间统计") {
                Task { await model.scanStorage() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}
