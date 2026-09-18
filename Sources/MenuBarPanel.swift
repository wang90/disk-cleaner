import SwiftUI
import AppKit

/// 菜单栏小图标点开后弹出的面板：快速查看当前储存空间 / 内存使用量
struct MenuBarPanel: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                freeSpaceBlock
                Divider()
                usageRows
            }
            .padding(14)
            Divider()
            actions
        }
        .frame(width: 310)
        .task { await model.refreshStatus() }
    }

    // MARK: 头部
    private var header: some View {
        HStack(spacing: 8) {
            AppLogo(size: 22)
            Text("磁盘清理").font(.system(size: 13, weight: .semibold))
            if AppInfo.isBeta {
                Text("BETA")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(Color.orange)
            }
            Spacer()
            if model.isScanning || model.isCleaning {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await model.refreshStatus() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    // MARK: 可用空间
    private var freeSpaceBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("可用空间").font(.caption).foregroundStyle(.secondary)
                Spacer()
                StatusBadge(text: model.isTargetMet ? "已达标" : "低于目标",
                            color: model.isTargetMet ? .green : .orange)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.size(model.freeKB))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("/ 目标 \(model.targetGB) GB")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Bar(value: model.freeRatio, tint: barTint)

            Text(model.isTargetMet
                 ? "空间充足，后台任务不会做任何清理。"
                 : "距离目标还差 \(Fmt.size(model.neededKB))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: 硬盘 / 内存
    private var usageRows: some View {
        VStack(spacing: 9) {
            usageRow(icon: "internaldrive",
                     title: "硬盘",
                     detail: "\(Fmt.size(model.diskUsedKB)) / \(Fmt.size(model.diskTotalKB))",
                     value: model.diskUsedRatio,
                     tint: model.diskUsedRatio > 0.9 ? .red : .blue)

            usageRow(icon: "memorychip",
                     title: "内存",
                     detail: "\(Fmt.memSize(model.memUsedKB)) / \(Fmt.memSize(model.memTotalKB))",
                     value: model.memUsedRatio,
                     tint: model.memUsedRatio > 0.9 ? .red : .purple)

            if model.swapUsedKB > 0 {
                usageRow(icon: "arrow.left.arrow.right",
                         title: "Swap",
                         detail: "\(Fmt.memSize(model.swapUsedKB)) / \(Fmt.memSize(model.swapTotalKB))",
                         value: model.swapTotalKB > 0 ? Double(model.swapUsedKB) / Double(model.swapTotalKB) : 0,
                         tint: .gray)
            }
        }
    }

    private func usageRow(icon: String, title: String, detail: String,
                          value: Double, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(title).font(.caption)
                Spacer()
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Bar(value: value, tint: tint)
        }
    }

    // MARK: 操作
    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                openMainWindow()
            } label: {
                Label("打开主窗口", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)

            Button {
                Task { await model.clean() }
            } label: {
                Label(model.dryRun ? "模拟清理" : "开始清理",
                      systemImage: model.dryRun ? "eye" : "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .disabled(model.isCleaning || model.scriptURL == nil)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .controlSize(.small)
            .help("退出磁盘清理")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var barTint: Color {
        if model.isTargetMet { return .green }
        return model.freeRatio < 0.5 ? .red : .orange
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        // 兜底：如果窗口没有被带到前台，直接找出来显示
        DispatchQueue.main.async {
            if let w = NSApp.windows.first(where: { $0.title == "磁盘清理" }) {
                w.makeKeyAndOrderFront(nil)
            }
        }
    }
}
