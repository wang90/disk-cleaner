import Foundation
import AppKit

@MainActor
final class CleanerModel: ObservableObject {

    // MARK: - 磁盘 / 内存状态
    @Published var freeKB: Int = 0
    @Published var diskTotalKB: Int = 0
    @Published var diskUsedKB: Int = 0
    @Published var diskAvailKB: Int = 0
    @Published var memTotalKB: Int = 0
    @Published var memAvailKB: Int = 0
    @Published var memCompressedKB: Int = 0
    @Published var memWiredKB: Int = 0
    @Published var swapTotalKB: Int = 0
    @Published var swapUsedKB: Int = 0
    @Published var volumes: [VolumeInfo] = []

    // MARK: - 扫描结果
    @Published var items: [ScanItem] = []
    @Published var isScanning = false
    @Published var isCleaning = false

    // MARK: - 应用占用
    @Published var apps: [AppItem] = []
    @Published var isScanningApps = false
    @Published var appsLoaded = false

    // MARK: - 储存空间分类
    @Published var categories: [StorageCategory] = []
    @Published var storageTotalKB: Int = 0
    @Published var isScanningStorage = false
    @Published var storageLoaded = false

    // MARK: - 清理进度
    @Published var logs: [LogEntry] = []
    @Published var progress: Double = 0
    @Published var freedKB: Int = 0
    @Published var lastResultFreedKB: Int = 0
    @Published var lastResultCount: Int = 0
    @Published var banner: String?

    // MARK: - 用户设置
    @Published var targetGB: Int = 10 { didSet { save() } }
    @Published var maxTier: Int = 2 { didSet { save() } }
    @Published var dryRun: Bool = true { didSet { save() } }
    @Published var deepClean: Bool = false { didSet { save() } }
    @Published var purgeMemory: Bool = false { didSet { save() } }
    @Published var allowUserData: Bool = false { didSet { save() } }
    /// 是否在储存空间色块上直接显示数字（鼠标悬停提示始终有效）
    @Published var showStorageLabels: Bool = false { didSet { save() } }
    /// 外观主题
    @Published var theme: AppTheme = .system { didSet { save() } }

    // MARK: - 自动清理
    @Published var autoCleanInstalled = false
    @Published var showSettings = false
    @Published var showLogs = true

    // MARK: - 脚本位置
    @Published var scriptURL: URL?
    @Published var scriptMissing = false

    private var didBootstrap = false

    struct LogEntry: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case plain, info, ok, warn, err }
    }

    // MARK: - 派生状态
    var targetKB: Int { max(1, targetGB) * 1024 * 1024 }
    var isTargetMet: Bool { freeKB >= targetKB }
    var neededKB: Int { max(0, targetKB - freeKB) }
    var freeRatio: Double { min(1, Double(freeKB) / Double(targetKB)) }

    var diskUsedRatio: Double {
        diskTotalKB > 0 ? min(1, Double(diskUsedKB) / Double(diskTotalKB)) : 0
    }
    var memUsedKB: Int { max(0, memTotalKB - memAvailKB) }
    var memUsedRatio: Double {
        memTotalKB > 0 ? min(1, Double(memUsedKB) / Double(memTotalKB)) : 0
    }

    /// 是否有读不全的储存空间分类（用来显示「申请权限」按钮）
    var hasLimitedCategories: Bool {
        categories.contains { !$0.readOK && $0.key != "free" }
    }

    var plistPath: String { NSHomeDirectory() + "/Library/LaunchAgents/com.local.diskautoclean.plist" }
    var supportDir: String { NSHomeDirectory() + "/Library/Application Support/DiskAutoClean" }

    // MARK: - 启动
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        load()
        scriptURL = Self.locateScript()
        scriptMissing = (scriptURL == nil)
        if scriptMissing {
            appendLog("找不到 diskautoclean.sh，请先运行 install.command 或从源码目录启动。", .err)
        }
        refreshAutoCleanState()

        // Dev/screenshot helpers: `--settings` opens the settings sheet on launch,
        // `--demo` also pre-loads the storage breakdown and shows bar labels.
        let mode = DiskCleanerApp.uiMode

        await refreshStatus()
        if scriptURL != nil {
            await scan()
            await scanApps()
            if mode == "demo" {
                await scanStorage()
                showStorageLabels = true
            }
        }
    }

    static func locateScript() -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("diskautoclean.sh"))
        }
        let exeDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("diskautoclean.sh"))
        candidates.append(exeDir.deletingLastPathComponent().appendingPathComponent("diskautoclean.sh"))
        candidates.append(exeDir.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("diskautoclean.sh"))
        // Running from a repo checkout (.build/DiskCleaner → scripts/diskautoclean.sh)
        candidates.append(exeDir.deletingLastPathComponent().appendingPathComponent("scripts/diskautoclean.sh"))
        candidates.append(exeDir.appendingPathComponent("scripts/diskautoclean.sh"))
        candidates.append(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/DiskAutoClean/diskautoclean.sh"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/diskautoclean.sh"))
        candidates.append(URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/diskautoclean.sh"))
        for c in candidates where fm.isReadableFile(atPath: c.path) { return c }
        return nil
    }

    // MARK: - 刷新状态 / 扫描
    func refreshStatus() async {
        guard let script = scriptURL else { return }
        let (code, out) = await Shell.capture(script: script, args: ["--status", "--json"])
        guard code == 0, let data = out.data(using: .utf8),
              let payload = try? JSONDecoder().decode(StatusPayload.self, from: data) else { return }
        freeKB = payload.freeKB
        diskTotalKB = payload.diskTotalKB
        diskUsedKB = payload.diskUsedKB
        diskAvailKB = payload.diskAvailKB
        memTotalKB = payload.memTotalKB
        memAvailKB = payload.memAvailKB
        memCompressedKB = payload.memCompressedKB
        memWiredKB = payload.memWiredKB
        swapTotalKB = payload.swapTotalKB
        swapUsedKB = payload.swapUsedKB
        if let vols = payload.volumes { volumes = vols }
    }

    // MARK: - 储存空间分类
    func scanStorage() async {
        guard let script = scriptURL, !isScanningStorage else { return }
        isScanningStorage = true
        appendLog("正在统计储存空间分类（需要扫描各主要目录，约 1 分钟）…", .info)
        let (code, out) = await Shell.capture(script: script,
                                              args: ["--storage", "--json"],
                                              extraEnv: ["DISKAUTOCLEAN_KB_TIMEOUT": "25"])
        isScanningStorage = false
        guard code == 0, let data = out.data(using: .utf8),
              let payload = try? JSONDecoder().decode(StoragePayload.self, from: data) else {
            appendLog("储存空间统计失败。", .err)
            return
        }
        categories = payload.categories
        storageTotalKB = payload.totalKB
        storageLoaded = true
        appendLog("储存空间统计完成：已用 \(Fmt.size(payload.usedKB)) / 共 \(Fmt.size(payload.totalKB))。", .ok)

        let partial = payload.categories.filter { !$0.readOK && $0.key != "free" }
        if !partial.isEmpty {
            appendLog("部分分类因权限读不全：\(partial.map(\.label).joined(separator: "、"))（已标 ⚠︎）", .warn)
        }
    }

    func scan() async {
        guard let script = scriptURL, !isScanning else { return }
        isScanning = true
        appendLog("正在扫描磁盘占用（首次可能需要十几秒）…", .info)
        let (code, out) = await Shell.capture(script: script,
                                              args: ["--scan", "--json"],
                                              extraEnv: ["DISKAUTOCLEAN_KB_TIMEOUT": "25"])
        isScanning = false
        guard code == 0, let data = out.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ScanPayload.self, from: data) else {
            appendLog("扫描失败，请检查脚本是否可执行。", .err)
            return
        }
        items = payload.items
        freeKB = payload.freeKB
        appendLog("扫描完成：共 \(payload.items.count) 项，可读取部分合计 \(Fmt.size(payload.totalKB))。", .ok)

        let blocked = payload.items.filter { !$0.readOK }
        if !blocked.isEmpty {
            let names = blocked.map(\.label).joined(separator: "、")
            appendLog("有 \(blocked.count) 个目录读取受限：\(names)", .warn)
            appendLog("如需统计这些位置，请在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中授权本应用。", .warn)
        }
    }

    // MARK: - 应用占用
    func scanApps() async {
        guard let script = scriptURL, !isScanningApps else { return }
        isScanningApps = true
        appendLog("正在统计各应用占用（应用本体 + 用户数据）…", .info)
        let (code, out) = await Shell.capture(script: script,
                                              args: ["--apps", "--json"],
                                              extraEnv: ["DISKAUTOCLEAN_APP_TIMEOUT": "12",
                                                         "DISKAUTOCLEAN_KB_TIMEOUT": "20"])
        isScanningApps = false
        guard code == 0, let data = out.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AppsPayload.self, from: data) else {
            appendLog("应用占用统计失败。", .err)
            return
        }
        apps = payload.apps.sorted { $0.totalKB > $1.totalKB }
        appsLoaded = true
        let totalKB = apps.reduce(0) { $0 + $1.totalKB }
        appendLog("已统计 \(apps.count) 个应用，合计 \(Fmt.size(totalKB))。", .ok)
    }

    // MARK: - 清理
    func clean() async {
        guard let script = scriptURL, !isCleaning else { return }
        isCleaning = true
        freedKB = 0
        progress = 0
        lastResultFreedKB = 0
        lastResultCount = 0
        banner = nil
        logs.removeAll()

        var args = ["--target", "\(targetGB)G", "--max-tier", "\(maxTier)", "--machine"]
        if dryRun { args.append("--dry-run") }
        if deepClean { args.append("--force") }
        if purgeMemory { args.append("--purge-memory") }
        if maxTier >= 3 && allowUserData { args.append("--user-data") }

        appendLog(dryRun ? "=== 模拟清理（不会真正删除）===" : "=== 开始清理 ===", .info)
        appendLog("目标：保持 \(targetGB) GB 可用；最高等级：\(maxTier)", .info)

        _ = await Shell.stream(script: script, args: args) { [weak self] line in
            DispatchQueue.main.async { self?.handle(line: line) }
        }

        isCleaning = false
        progress = isTargetMet ? 1 : progress
        await refreshStatus()

        if dryRun {
            banner = "模拟完成，预计可释放 \(Fmt.size(freedKB))"
        } else {
            banner = "已释放 \(Fmt.size(freedKB))，现在可用 \(Fmt.size(freeKB))"
            appendLog(banner ?? "", .ok)
            await scan()
        }
    }

    private func handle(line: String) {
        if line.hasPrefix("@@") {
            let parts = line.dropFirst(2).components(separatedBy: "\t")
            guard let key = parts.first else { return }
            switch key {
            case "FREE_BEFORE":
                if parts.count > 1, let v = Int(parts[1]) { freeKB = v }
            case "TIER":
                if parts.count > 1 { appendLog("▶ 开始第 \(parts[1]) 级清理", .info) }
            case "FREED":
                if parts.count > 2, let kb = Int(parts[1]) {
                    freedKB += kb
                    let path = Fmt.tilde(parts[2])
                    appendLog("  ✓ \(path)  \(Fmt.size(kb))", .ok)
                    if neededKB > 0 { progress = min(1, Double(freedKB) / Double(neededKB)) }
                }
            case "DONE":
                if parts.count > 2 {
                    lastResultFreedKB = Int(parts[1]) ?? freedKB
                    lastResultCount = Int(parts[2]) ?? 0
                }
            default:
                break
            }
            return
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appendLog(trimmed, .plain)
    }

    func appendLog(_ text: String, _ kind: LogEntry.Kind) {
        logs.append(LogEntry(text: text, kind: kind))
        if logs.count > 600 { logs.removeFirst(logs.count - 600) }
    }

    func clearLogs() { logs.removeAll() }

    // MARK: - 自动清理（LaunchAgent）
    func refreshAutoCleanState() {
        autoCleanInstalled = FileManager.default.fileExists(atPath: plistPath)
    }

    func setAutoClean(_ on: Bool) async {
        if on { await installAutoClean() } else { await uninstallAutoClean() }
    }

    private func installAutoClean() async {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: supportDir, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o755])
            guard let src = scriptURL else { throw NSError(domain: "diskcleaner", code: 1) }
            let dstPath = supportDir + "/diskautoclean.sh"
            if fm.fileExists(atPath: dstPath) { try fm.removeItem(atPath: dstPath) }
            try fm.copyItem(atPath: src.path, toPath: dstPath)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstPath)

            try fm.createDirectory(atPath: NSHomeDirectory() + "/Library/LaunchAgents",
                                   withIntermediateDirectories: true)
            let xml = Self.plistXML(script: dstPath, home: NSHomeDirectory(),
                                    target: targetGB, tier: maxTier)
            try xml.write(toFile: plistPath, atomically: true, encoding: .utf8)

            let uid = String(getuid())
            await Shell.runTool("/bin/launchctl", ["bootout", "gui/\(uid)", plistPath])
            let code = await Shell.runTool("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
            if code != 0 {
                _ = await Shell.runTool("/bin/launchctl", ["load", "-w", plistPath])
            }
            _ = await Shell.runTool("/bin/launchctl", ["enable", "gui/\(uid)/com.local.diskautoclean"])
            autoCleanInstalled = true
            appendLog("✅ 已开启后台自动清理：登录时 + 每小时检查一次。", .ok)
        } catch {
            autoCleanInstalled = false
            appendLog("开启后台自动清理失败：\(error.localizedDescription)", .err)
        }
    }

    private func uninstallAutoClean() async {
        let fm = FileManager.default
        let uid = String(getuid())
        _ = await Shell.runTool("/bin/launchctl", ["bootout", "gui/\(uid)", plistPath])
        if fm.fileExists(atPath: plistPath) { try? fm.removeItem(atPath: plistPath) }
        autoCleanInstalled = false
        appendLog("已关闭后台自动清理。", .info)
    }

    private static func plistXML(script: String, home: String, target: Int, tier: Int) -> String {
        let userData = tier >= 3 ? "<string>--user-data</string>" : ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.local.diskautoclean</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(script)</string>
                <string>--quiet</string>
                <string>--target</string>
                <string>\(target)G</string>
                <string>--max-tier</string>
                <string>\(tier)</string>
                \(userData)
            </array>
            <key>RunAtLoad</key><true/>
            <key>StartInterval</key><integer>3600</integer>
            <key>ProcessType</key><string>Background</string>
            <key>LowPriorityIO</key><true/>
            <key>Nice</key><integer>5</integer>
            <key>StandardOutPath</key><string>\(home)/Library/Logs/diskautoclean.launchd.log</string>
            <key>StandardErrorPath</key><string>\(home)/Library/Logs/diskautoclean.launchd.log</string>
        </dict>
        </plist>
        """
    }

    // MARK: - 打开 / 显示
    func reveal(_ path: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            let parent = (path as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: parent) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parent)
            }
        }
    }

    func openLogFile() {
        let p = NSHomeDirectory() + "/Library/Logs/diskautoclean.log"
        if FileManager.default.fileExists(atPath: p) {
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        } else {
            reveal(p)
        }
    }

    // MARK: - 权限申请
    /// 点击「无权限」条目时调用：
    ///   1) 由 App 本体去读 文稿/桌面/下载/宗卷 → 触发系统授权弹窗
    ///   2) 打开「完全磁盘访问权限」设置面板，并在 Finder 里选中本 App（方便拖进去）
    /// 注意：读取受保护目录会阻塞等待用户点选，所以必须放到后台线程，否则界面会卡死。
    func requestPermissions() {
        appendLog("正在申请磁盘访问权限…", .info)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let home = NSHomeDirectory()
            let targets: [(String, String)] = [
                ("文稿", home + "/Documents"),
                ("桌面", home + "/Desktop"),
                ("下载", home + "/Downloads"),
                ("外接硬盘", "/Volumes"),
            ]
            var requested: [String] = []
            for (name, path) in targets {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                // 真正读一次，macOS 才会弹授权框（没有权限时这里会阻塞等待）
                _ = try? FileManager.default.contentsOfDirectory(atPath: path)
                requested.append(name)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                if requested.isEmpty {
                    self.appendLog("没有找到需要授权的目录。", .plain)
                } else {
                    self.appendLog("已请求访问：\(requested.joined(separator: "、"))。若弹出系统对话框，请选择「好」。", .ok)
                }
                self.appendLog("更深的目录（如 ~/Library/Mail、其它 App 的容器）需要「完全磁盘访问权限」：已为你打开设置面板，把「磁盘清理」拖进列表并打勾，然后回来点「重新统计」。", .warn)
                self.openFullDiskAccessSettings()
                self.revealAppInFinder()
            }
        }
    }

    /// 打开「系统设置 → 隐私与安全性 → 完全磁盘访问权限」
    func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for c in candidates {
            if let url = URL(string: c), NSWorkspace.shared.open(url) { return }
        }
        appendLog("无法自动打开系统设置，请手动前往：系统设置 → 隐私与安全性 → 完全磁盘访问权限", .warn)
    }

    /// 在 Finder 中选中本 App，方便直接拖进权限列表
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    // MARK: - 偏好设置
    private func save() {
        let d = UserDefaults.standard
        d.set(targetGB, forKey: "targetGB")
        d.set(maxTier, forKey: "maxTier")
        d.set(dryRun, forKey: "dryRun")
        d.set(deepClean, forKey: "deepClean")
        d.set(purgeMemory, forKey: "purgeMemory")
        d.set(allowUserData, forKey: "allowUserData")
        d.set(showStorageLabels, forKey: "showStorageLabels")
        d.set(theme.rawValue, forKey: "theme")
    }

    private func load() {
        let d = UserDefaults.standard
        if d.object(forKey: "targetGB") != nil { targetGB = d.integer(forKey: "targetGB") }
        if d.object(forKey: "maxTier") != nil { maxTier = d.integer(forKey: "maxTier") }
        if d.object(forKey: "dryRun") != nil { dryRun = d.bool(forKey: "dryRun") }
        if d.object(forKey: "deepClean") != nil { deepClean = d.bool(forKey: "deepClean") }
        if d.object(forKey: "purgeMemory") != nil { purgeMemory = d.bool(forKey: "purgeMemory") }
        if d.object(forKey: "allowUserData") != nil { allowUserData = d.bool(forKey: "allowUserData") }
        if d.object(forKey: "showStorageLabels") != nil { showStorageLabels = d.bool(forKey: "showStorageLabels") }
        if let raw = d.string(forKey: "theme"), let t = AppTheme(rawValue: raw) { theme = t }
    }
}
