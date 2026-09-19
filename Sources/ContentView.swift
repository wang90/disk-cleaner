import SwiftUI
import AppKit

// MARK: - 主界面

struct ContentView: View {
    @ObservedObject var model: CleanerModel

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    StatusCard(model: model)
                    StorageCard(model: model)
                    ActionCard(model: model)
                    CategoryCard(model: model)
                    AppsCard(model: model)
                }
                .padding(20)
                .frame(maxWidth: 1020)
                .frame(maxWidth: .infinity)
            }
            Divider()
            if model.showLogs {
                LogPanel(model: model)
            } else {
                HStack {
                    Button {
                        model.showLogs = true
                    } label: {
                        Label("显示运行日志", systemImage: "terminal")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            AppLogo(size: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("磁盘清理").font(.system(size: 15, weight: .semibold))
                    Text("BETA")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(Color.orange)
                        .help("1.0.0 beta：功能可用，但可能仍有一些问题")
                }
                Text("自动保持至少 \(model.targetGB) GB 可用空间")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider().frame(height: 26)

            HStack(spacing: 8) {
                if model.isScanning {
                    Pill(icon: "arrow.triangle.2.circlepath", text: "扫描中…", color: .secondary)
                } else {
                    Pill(icon: model.isTargetMet ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                         text: model.isTargetMet ? "空间充足" : "低于目标",
                         color: model.isTargetMet ? .green : .orange)
                }
                Pill(icon: "internaldrive",
                     text: "\(Fmt.size(model.diskUsedKB)) / \(Fmt.size(model.diskTotalKB))",
                     color: .blue)
                Pill(icon: "memorychip", text: Fmt.memSize(model.memUsedKB), color: .purple)
            }

            Spacer()

            Button {
                Task { await model.refreshStatus() }
            } label: {
                Image(systemName: "gauge.with.dots.needle.67percent")
            }
            .help("刷新状态")
            .disabled(model.isCleaning)

            Button {
                Task { await model.scan() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新扫描占用")
            .disabled(model.isScanning || model.isCleaning)

            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.bar)
    }
}

// MARK: - 状态卡片

struct StatusCard: View {
    @ObservedObject var model: CleanerModel

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            // ---- 主指标：可用空间 / 目标 ----
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("可用空间").font(.subheadline).foregroundStyle(.secondary)
                    StatusBadge(text: model.isTargetMet ? "已达标" : "需要清理",
                                color: model.isTargetMet ? .green : .orange)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.size(model.freeKB))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ 目标 \(model.targetGB) GB")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Bar(value: model.freeRatio, tint: barTint)
                Text(model.isTargetMet
                     ? "空间充足，后台任务不会做任何清理。"
                     : "距离目标还差 \(Fmt.size(model.neededKB))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().frame(height: 108)

            // ---- 内存 ----
            VStack(alignment: .leading, spacing: 8) {
                Label("内存", systemImage: "memorychip")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("已用 \(Fmt.memSize(model.memUsedKB)) / 共 \(Fmt.memSize(model.memTotalKB))")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Bar(value: model.memUsedRatio,
                    tint: model.memUsedRatio > 0.9 ? .red : .purple)
                Text(memoryDetail)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 300, alignment: .leading)
        }
        .card()
    }

    private var memoryDetail: String {
        var s = "可回收 \(Fmt.memSize(model.memAvailKB)) · 压缩 \(Fmt.memSize(model.memCompressedKB))"
        if model.swapUsedKB > 0 {
            s += " · Swap \(Fmt.memSize(model.swapUsedKB))"
        }
        return s
    }

    private var barTint: Color {
        if model.isTargetMet { return .green }
        return model.freeRatio < 0.5 ? .red : .orange
    }
}

// MARK: - 储存空间卡片（macOS 风格）

struct StorageCard: View {
    @ObservedObject var model: CleanerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("储存空间", systemImage: "chart.pie.fill").font(.headline)
                if model.storageLoaded {
                    Text("共 \(Fmt.size(model.storageTotalKB))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.hasLimitedCategories {
                    Button {
                        model.requestPermissions()
                    } label: {
                        Label("申请权限", systemImage: "lock.open.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("有分类读不全，点击申请访问权限")
                }
                if model.isScanningStorage {
                    ProgressView().controlSize(.small)
                    Text("统计中…").font(.caption).foregroundStyle(.secondary)
                }
                if model.storageLoaded {
                    Toggle(isOn: $model.showStorageLabels) {
                        Label("数值", systemImage: "textformat.123")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("在色块上显示 / 隐藏具体大小（鼠标悬停始终会显示）")
                }
                Button {
                    Task { await model.scanStorage() }
                } label: {
                    Label(model.storageLoaded ? "重新统计" : "扫描储存空间",
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(model.isScanningStorage)
            }

            if model.categories.isEmpty {
                VStack(spacing: 6) {
                    Text(model.isScanningStorage ? "正在按 macOS 的方式统计各分类…" : "点击「扫描储存空间」查看每个硬盘的内容分布")
                        .foregroundStyle(.secondary)
                    Text("首次统计需要扫描 ~/Library、/Applications 等目录，约 1 分钟")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                StackedBar(categories: model.categories,
                           totalKB: model.storageTotalKB,
                           showLabels: model.showStorageLabels)
                LegendGrid(categories: model.categories) { model.requestPermissions() }

                Divider()

                Text("硬盘").font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(model.volumes) { vol in
                        VolumeRow(volume: vol) { model.reveal(vol.mount) }
                    }
                }
            }

            if !model.volumes.isEmpty && model.categories.isEmpty {
                Divider()
                Text("硬盘").font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(model.volumes) { vol in
                        VolumeRow(volume: vol) { model.reveal(vol.mount) }
                    }
                }
            }
        }
        .card()
    }
}

struct StackedBar: View {
    let categories: [StorageCategory]
    let totalKB: Int
    var showLabels: Bool = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(categories) { cat in
                    segment(cat, width: geo.size.width)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 24)
    }

    @ViewBuilder
    private func segment(_ cat: StorageCategory, width: CGFloat) -> some View {
        let raw = totalKB > 0 ? width * Double(cat.kb) / Double(totalKB) : 0
        // 留 1pt 间隙，但保证再小的色块也有可悬停的面积
        let segW: CGFloat = raw <= 0 ? 0 : max(raw - 1, 0.75)

        ZStack {
            Rectangle().fill(color(for: cat.key))

            if showLabels && segW > 44 {
                Text(Fmt.size(cat.kb))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: segW - 6)
            }
        }
        .frame(width: segW)
        // 鼠标划入显示这一段的名称 / 大小 / 占比（与「数值」开关无关）
        .contentShape(Rectangle())
        .help(tooltip(cat))
    }

    private func tooltip(_ cat: StorageCategory) -> String {
        let pct = totalKB > 0 ? Double(cat.kb) * 100 / Double(totalKB) : 0
        var s = String(format: "%@  %@（占 %.1f%%）", cat.label, Fmt.size(cat.kb), pct)
        if !cat.readOK && cat.key != "free" {
            s += " · 读取受限，点击可申请权限"
        }
        return s
    }
}

struct LegendGrid: View {
    let categories: [StorageCategory]
    var onPermission: () -> Void = {}

    private let columns = [GridItem(.adaptive(minimum: 168), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(categories) { cat in
                let limited = !cat.readOK && cat.key != "free"
                Button {
                    if limited { onPermission() }
                } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(color(for: cat.key))
                            .frame(width: 10, height: 10)
                        Text(cat.label).font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(limited ? "需授权" : Fmt.size(cat.kb))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(limited ? Color.orange : Color.secondary)
                        if limited {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(limited ? "该分类读取受限，点击申请访问权限" : cat.label)
            }
        }
    }
}

struct VolumeRow: View {
    let volume: VolumeInfo
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volume.boot == true ? "internaldrive.fill" : "externaldrive.fill")
                .foregroundStyle(volume.boot == true ? Color.accentColor : Color.teal)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(volume.name).fontWeight(.medium).lineLimit(1)
                    if volume.boot == true {
                        Text("启动盘")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(volume.mount)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Text("\(Fmt.size(volume.usedKB)) / \(Fmt.size(volume.totalKB))")
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Bar(value: volume.usedRatio, tint: volume.usedRatio > 0.9 ? .red : .blue)
                .frame(width: 150)
            Text("可用 \(Fmt.size(volume.availKB))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onReveal)
        .help("点击在 Finder 中打开：\(volume.mount)")
    }
}

/// 分类配色（跟 macOS 储存空间类似的思路）
func storageColor(for key: String) -> Color {
    switch key {
    case "apps":    return .blue
    case "docs":    return .indigo
    case "down":    return .cyan
    case "photos":  return .pink
    case "music":   return .purple
    case "movies":  return .orange
    case "mail":    return .teal
    case "dev":     return .mint
    case "appdata": return .brown
    case "caches":  return .yellow
    case "system":  return .gray
    case "free":    return Color.secondary.opacity(0.25)
    default:        return .blue
    }
}

private func color(for key: String) -> Color { storageColor(for: key) }

// MARK: - 应用占用卡片

struct AppsCard: View {
    @ObservedObject var model: CleanerModel

    private var maxKB: Int { max(1, model.apps.map(\.totalKB).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("应用占用", systemImage: "square.grid.2x2.fill").font(.headline)
                if model.appsLoaded {
                    Text("共 \(model.apps.count) 个 · 合计 \(Fmt.size(model.apps.reduce(0) { $0 + $1.totalKB }))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isScanningApps {
                    ProgressView().controlSize(.small)
                    Text("统计中…").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.scanApps() }
                } label: {
                    Label("重新统计", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isScanningApps || model.isCleaning)
            }

            if model.apps.isEmpty {
                Text(model.isScanningApps ? "正在统计应用占用…" : "暂无数据")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.apps.prefix(60)) { app in
                        AppRow(app: app, maxKB: maxKB,
                               onReveal: { model.reveal(app.path) },
                               onManage: { Task { await model.loadAppDetail(app) } })
                    }
                }
            }
        }
        .card()
        .sheet(item: $model.detailApp) { _ in
            AppDetailView(model: model)
        }
        .onChange(of: model.detailApp) { app in
            if app == nil { model.closeAppDetail() }
        }
    }
}

struct AppRow: View {
    let app: AppItem
    let maxKB: Int
    let onReveal: () -> Void
    var onManage: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).fontWeight(.medium).lineLimit(1)
                Text(Fmt.tilde(app.path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Text("数据 \(Fmt.size(app.dataKB))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)

            Bar(value: Double(app.totalKB) / Double(maxKB), tint: .indigo)
                .frame(width: 110)

            Text(Fmt.size(app.totalKB))
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .trailing)

            Button {
                onManage()
            } label: {
                Image(systemName: "slider.horizontal.below.rectangle")
            }
            .buttonStyle(.borderless)
            .help("管理该应用的数据（选择性清理）")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onReveal)
        .help("点击在 Finder 中显示：\(app.path)")
    }
}

// MARK: - 操作卡片

struct ActionCard: View {
    @ObservedObject var model: CleanerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("清理设置", systemImage: "slider.horizontal.3").font(.headline)
                Spacer()
                if model.isCleaning {
                    Text("清理中…").font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目标可用空间").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $model.targetGB) {
                        ForEach([5, 10, 15, 20, 30, 50], id: \.self) { Text("\($0) GB").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("清理等级").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $model.maxTier) {
                        Text("1 安全").tag(1)
                        Text("2 开发缓存").tag(2)
                        Text("3 用户数据").tag(3)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
                Spacer()
            }

            if model.maxTier >= 3 {
                Toggle("允许清理废纸篓 / iOS 备份 / 旧下载（第 3 级属于个人数据）",
                       isOn: $model.allowUserData)
                    .toggleStyle(.checkbox)
                    .font(.callout)
            }

            HStack(spacing: 24) {
                Toggle("演练模式（不真正删除）", isOn: $model.dryRun).toggleStyle(.switch)
                Toggle("深度清理（忽略目标）", isOn: $model.deepClean).toggleStyle(.switch)
                Toggle("顺带释放内存", isOn: $model.purgeMemory).toggleStyle(.switch)
            }
            .font(.callout)

            HStack(spacing: 14) {
                Button {
                    Task { await model.clean() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isCleaning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: model.dryRun ? "eye" : "sparkles")
                        }
                        Text(model.dryRun ? "模拟清理" : "开始清理").fontWeight(.semibold)
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isCleaning || model.scriptURL == nil)

                if model.isCleaning {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: model.progress).frame(width: 200)
                        Text("已释放 \(Fmt.size(model.freedKB))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let banner = model.banner {
                    Text(banner).font(.callout).foregroundStyle(.green)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Toggle("后台自动清理", isOn: Binding(
                        get: { model.autoCleanInstalled },
                        set: { value in Task { await model.setAutoClean(value) } }
                    ))
                    .toggleStyle(.switch)
                    Text(model.autoCleanInstalled ? "登录时 + 每小时检查" : "已关闭")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }
}

// MARK: - 清理项列表

struct CategoryCard: View {
    @ObservedObject var model: CleanerModel

    private var maxKB: Int { max(1, model.items.map(\.kb).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("清理项占用", systemImage: "chart.bar.fill").font(.headline)
                Spacer()
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isScanning || model.isCleaning)
            }

            if model.items.isEmpty {
                Text(model.isScanning ? "正在扫描…" : "暂无数据")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 2) {
                    ForEach(model.items) { item in
                        CategoryRow(item: item, maxKB: maxKB,
                                    onReveal: { model.reveal(item.path) },
                                    onPermission: { model.requestPermissions() })
                    }
                }
            }
        }
        .card()
    }
}

final class HoverState: ObservableObject {
    @Published var isHovering = false
}

struct CategoryRow: View {
    let item: ScanItem
    let maxKB: Int
    let onReveal: () -> Void
    var onPermission: () -> Void = {}

    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).fontWeight(.medium)
                    Text("L\(item.tier) \(item.tierName)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(tint.opacity(0.15)))
                        .foregroundStyle(tint)
                }
                Text(Fmt.tilde(item.path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            if item.readOK {
                Bar(value: Double(item.kb) / Double(maxKB), tint: tint)
                    .frame(width: 150)
            } else {
                Spacer().frame(width: 150)
            }

            Text(item.bytesText)
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(item.readOK ? Color.secondary : Color.orange)
                .frame(width: 82, alignment: .trailing)
                .help(item.readOK ? "" : "该目录受系统保护，需在「完全磁盘访问权限」中授权后重新扫描")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(hover.isHovering ? Color.primary.opacity(0.05) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover.isHovering = $0 }
        .onTapGesture { item.readOK ? onReveal() : onPermission() }
        .help(item.readOK ? "点击在 Finder 中显示：\(item.path)" : "该目录读取受限，点击申请访问权限")
    }

    private var tint: Color {
        switch item.tier {
        case 1: return .green
        case 2: return .blue
        default: return .orange
        }
    }

    private var icon: String {
        switch item.tier {
        case 1: return "shippingbox"
        case 2: return "hammer"
        default: return "person.crop.circle"
        }
    }
}

// MARK: - 日志面板

struct LogPanel: View {
    @ObservedObject var model: CleanerModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("运行日志", systemImage: "terminal").font(.subheadline)
                Text("共 \(model.logs.count) 行").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清空") { model.clearLogs() }.buttonStyle(.borderless)
                Button {
                    model.showLogs = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("收起")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.logs) { entry in
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(for: entry.kind))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .frame(height: 168)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.logs.count) { _ in
                    if let last = model.logs.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func color(for kind: CleanerModel.LogEntry.Kind) -> Color {
        switch kind {
        case .plain: return .primary
        case .info:  return .secondary
        case .ok:    return .green
        case .warn:  return .orange
        case .err:   return .red
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // ---- 标题栏 ----
            HStack(spacing: 10) {
                Label("设置", systemImage: "gearshape.fill").font(.headline)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    appearanceSection
                    menuBarSection
                    autoCleanSection
                    filesSection
                    aboutLinkSection
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 660)
    }

    // MARK: 外观
    private var appearanceSection: some View {
        SettingsGroup(title: "外观", icon: "paintbrush.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $model.theme) {
                    ForEach(AppTheme.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 10) {
                    ForEach(AppTheme.allCases) { t in
                        themeSwatch(t)
                    }
                    Spacer()
                }

                Text("选择「深色 / 浅色」会覆盖系统外观；「跟随系统」由 macOS 的 外观 设置决定。选择会被记住。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func themeSwatch(_ t: AppTheme) -> some View {
        let selected = model.theme == t
        let scheme: ColorScheme = (t == .dark) ? .dark
            : (t == .light ? .light : (model.theme == .dark ? .dark : .light))
        return VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
                    .frame(width: 74, height: 46)
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scheme == .dark ? Color(white: 0.34) : Color(white: 0.85))
                        .frame(width: 52, height: 6)
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.accentColor).frame(width: 20, height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(scheme == .dark ? Color(white: 0.34) : Color(white: 0.85))
                            .frame(width: 29, height: 6)
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(scheme == .dark ? Color(white: 0.28) : Color(white: 0.9))
                        .frame(width: 52, height: 14)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: selected ? 2 : 1)
            )
            HStack(spacing: 3) {
                Image(systemName: t.icon).font(.system(size: 9))
                Text(t.label).font(.system(size: 10))
            }
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.theme = t }
    }

    // MARK: 菜单栏
    private var menuBarSection: some View {
        SettingsGroup(title: "菜单栏", icon: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("在菜单栏显示小图标", isOn: $model.showMenuBarExtra)
                Toggle("图标旁显示可用空间数字", isOn: $model.showMenuBarText)
                    .disabled(!model.showMenuBarExtra)
                Text("点击菜单栏图标可随时查看可用空间、硬盘与内存占用，并能直接打开主窗口或开始清理。"
                     + "空间低于目标时图标会变成感叹号。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 自动清理
    private var autoCleanSection: some View {
        SettingsGroup(title: "后台自动清理", icon: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { model.autoCleanInstalled },
                    set: { value in Task { await model.setAutoClean(value) } }
                )) {
                    Text("登录时 + 每小时自动检查一次")
                }

                HStack(spacing: 6) {
                    Text("使用的参数：").font(.caption).foregroundStyle(.secondary)
                    Pill(icon: "target", text: "\(model.targetGB) GB", color: .blue)
                    Pill(icon: "list.number", text: "等级 \(model.maxTier)", color: .teal)
                    if model.maxTier >= 3 && model.allowUserData {
                        Pill(icon: "person.crop.circle", text: "含用户数据", color: .orange)
                    }
                }

                Text("空间充足时会立刻退出、不做任何删除；只有低于目标才会开始清理，并在达标后立即停止。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 关于（入口，详细内容在独立的「关于」窗口里）
    private var aboutLinkSection: some View {
        SettingsGroup(title: "关于", icon: "info.circle.fill") {
            HStack(alignment: .center, spacing: 14) {
                AppLogo(size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("磁盘清理").font(.system(size: 15, weight: .semibold))
                        if AppInfo.isBeta {
                            Text("BETA")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                .foregroundStyle(Color.orange)
                        }
                    }
                    Text("版本 \(AppInfo.displayVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("功能说明、安全设计与相关链接都在独立的「关于」窗口里")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    openAbout()
                } label: {
                    Label("打开「关于」", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.small)
            }
        }
    }

    /// 打开独立的「关于」窗口（菜单 磁盘清理 → 关于 磁盘清理 是同一个入口）
    private func openAbout() {
        dismiss()
        DispatchQueue.main.async {
            openWindow(id: "about")
        }
    }

    // MARK: 文件
    private var filesSection: some View {
        SettingsGroup(title: "文件位置", icon: "folder.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text("清理脚本").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.scriptURL?.path ?? "未找到")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: 380, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Button {
                        model.openLogFile()
                    } label: {
                        Label("打开清理日志", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        if let s = model.scriptURL { model.reveal(s.path) }
                    } label: {
                        Label("显示脚本", systemImage: "folder")
                    }
                    .disabled(model.scriptURL == nil)
                    Button {
                        model.revealAppInFinder()
                    } label: {
                        Label("显示本应用", systemImage: "app.dashed")
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - 设置页小组件

struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct AppLogo: View {
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: "internaldrive.fill")
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.teal],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
            )
            .shadow(color: Color.accentColor.opacity(0.22), radius: 3, y: 1)
    }
}

struct Pill: View {
    let icon: String
    let text: String
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.13)))
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

// MARK: - 通用小组件

struct Bar: View {
    var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(6, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 10)
        .animation(.easeInOut(duration: 0.4), value: value)
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }
}

extension View {
    func card() -> some View {
        self
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
            .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }
}
