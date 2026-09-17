import SwiftUI

@main
struct DiskCleanerApp: App {
    @StateObject private var model = CleanerModel()

    /// Dev/screenshot modes. Accepts either a launch argument or the env var
    /// `DISKCLEANER_UI=settings|demo` (env vars survive `open -n App.app`).
    static var uiMode: String? {
        if let v = ProcessInfo.processInfo.environment["DISKCLEANER_UI"], !v.isEmpty { return v }
        if CommandLine.arguments.contains("--settings-only") { return "settings" }
        if CommandLine.arguments.contains("--demo") { return "demo" }
        return nil
    }

    /// `--settings-only` / `DISKCLEANER_UI=settings` renders the Settings page as
    /// the window content (used for docs screenshots; normally it is a sheet).
    @ViewBuilder
    private var rootView: some View {
        if DiskCleanerApp.uiMode == "settings" {
            SettingsView(model: model)
                .frame(width: 640, height: 660)
        } else {
            ContentView(model: model)
                .frame(minWidth: 900, idealWidth: 1000, minHeight: 620, idealHeight: 780)
        }
    }

    var body: some Scene {
        WindowGroup("磁盘清理") {
            rootView
                .preferredColorScheme(model.theme.colorScheme)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: DiskCleanerApp.uiMode == "settings" ? 680 : 1000,
                     height: DiskCleanerApp.uiMode == "settings" ? 720 : 800)
        .commands {
            CommandGroup(replacing: .newItem) { }

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
            }
        }
    }
}
