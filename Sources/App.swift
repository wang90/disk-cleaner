import SwiftUI

@main
struct DiskCleanerApp: App {
    @StateObject private var model = CleanerModel()
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
            CommandGroup(replacing: .newItem) { }

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

                Button(model.dryRun ? "模拟清理" : "开始清理") {
                    Task { await model.clean() }
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model.isCleaning || model.scriptURL == nil)

                Button(model.showLogs ? "隐藏日志" : "显示日志") {
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

        // 独立的「关于」窗口（可同时开着主窗口）
        // 注意：这里必须用 WindowGroup 而不是 Window —— 实测在 macOS 上
        // 只要声明了 Window 场景，MenuBarExtra 就不会出现在菜单栏里。
        WindowGroup("关于 磁盘清理", id: "about") {
            AboutView(model: model)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // 菜单栏常驻小图标：点击查看当前储存空间 / 内存使用量
        // 用 isInserted 绑定控制显隐（SceneBuilder 不支持 if）
        MenuBarExtra(isInserted: $model.showMenuBarExtra) {
            MenuBarPanel(model: model)
                .preferredColorScheme(model.theme.colorScheme)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.menuBarSymbol)
                if model.showMenuBarText {
                    Text(model.freeSpaceShort)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
