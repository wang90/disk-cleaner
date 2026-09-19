import SwiftUI
import AppKit

/// 单个应用的「数据明细 / 选择性清理」面板
///
/// 安全设计：
///   · 缓存 / 日志默认勾选（可重建）
///   · 用户数据 / 未知项**默认禁止勾选**，必须显式打开「我了解风险」开关
///   · 勾选项里一旦包含用户数据，删除前还要再确认一次
///   · 真正的删除由 diskautoclean.sh 执行，仍然走白名单 + 受保护路径检查
struct AppDetailView: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = DetailUIState()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isLoadingDetail {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取数据明细…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = model.appDetail {
                ZStack {
                    content(detail)
                    if model.isCleaningAppData {
                        cleaningOverlay
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: model.isCleaningAppData)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("没有找到该应用的数据目录")
                        .foregroundStyle(.secondary)
                    Text("可能是它没有独立数据目录，或者当前没有磁盘访问权限。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .frame(width: 640, height: 640)
        .alert("确定要删除吗？", isPresented: $ui.confirmDelete) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                Task { await model.cleanSelectedAppData() }
            }
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        let n = model.detailSelection.count
        let size = Fmt.size(model.detailSelectedKB)
        if model.detailHasRiskySelection {
            return "将删除 \(n) 项、共 \(size)。\n\n其中包含「用户数据 / 未知」项目 —— 可能含有聊天记录、数据库或登录状态，删除后无法恢复。"
        }
        return "将删除 \(n) 项缓存 / 日志，共 \(size)。这些内容会在应用下次运行时自动重建。"
    }

    // MARK: 头部
    private var header: some View {
        HStack(spacing: 12) {
            if let app = model.detailApp {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.system(size: 16, weight: .semibold))
                    Text(model.appDetail?.bundleID ?? app.bundleID ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("应用数据").font(.headline)
            }

            Spacer()

            if let detail = model.appDetail {
                let total = detail.items.reduce(0) { $0 + $1.kb }
                Text("共 \(Fmt.size(total))")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Button {
                if let app = model.detailApp { Task { await model.loadAppDetail(app) } }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新读取")
            .disabled(model.isLoadingDetail || model.isCleaningAppData)

            Button("完成") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    // MARK: 内容
    private func content(_ detail: AppDetailPayload) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                safeSection(detail)
                riskySection(detail)
                if detail.items.isEmpty {
                    Text("这个应用没有可清理的数据项。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
    }

    private func safeSection(_ detail: AppDetailPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "checkmark.seal.fill", color: .green,
                          title: "可以安全清理",
                          subtitle: "缓存与日志，应用会自动重建")
            if detail.safeItems.isEmpty {
                emptyRow("没有缓存或日志")
            } else {
                ForEach(detail.safeItems) { item in
                    row(item, locked: false)
                }
            }
        }
    }

    private func riskySection(_ detail: AppDetailPayload) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "exclamationmark.triangle.fill", color: .orange,
                          title: "需要谨慎",
                          subtitle: "可能包含聊天记录、数据库、登录状态 —— 删除后不可恢复")

            if detail.riskyItems.isEmpty {
                emptyRow("没有这一类项目")
            } else {
                ForEach(detail.riskyItems) { item in
                    row(item, locked: !model.allowRiskyDeletion)
                }

                Toggle(isOn: $model.allowRiskyDeletion) {
                    Text("我了解风险，允许选择上面这些项目")
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
                .padding(.top, 4)

                if model.allowRiskyDeletion {
                    Text("⚠️ 删除聊天记录 / 数据库属于不可恢复操作，请确认已经备份。真正的删除还会再弹一次确认。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sectionHeader(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).padding(.leading, 22)
    }

    private func row(_ item: AppDataItem, locked: Bool) -> some View {
        let selected = model.detailSelection.contains(item.path)
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected },
                set: { on in
                    if on { model.detailSelection.insert(item.path) }
                    else { model.detailSelection.remove(item.path) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(locked || model.isCleaningAppData)

            Image(systemName: item.isSafe ? "shippingbox" : "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(item.isSafe ? Color.green : Color.orange)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.label).fontWeight(.medium)
                    Text(item.kindText)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(kindColor(item).opacity(0.15)))
                        .foregroundStyle(kindColor(item))
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Fmt.tilde(item.path))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(Fmt.size(item.kb))
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 7)
            .fill(selected ? Color.accentColor.opacity(0.07) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !locked, !model.isCleaningAppData else { return }
            if selected { model.detailSelection.remove(item.path) }
            else { model.detailSelection.insert(item.path) }
        }
        .help(item.path)
    }

    private func kindColor(_ item: AppDataItem) -> Color {
        item.isSafe ? .green : (item.kind == "userdata" ? .orange : .gray)
    }

    // MARK: 清理中的 loading 浮层
    private var cleaningOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("正在清理…")
                .font(.headline)

            if model.appCleanTotal > 0 {
                Text("\(model.appCleanDone) / \(model.appCleanTotal) 项")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(model.appCleanDone),
                             total: Double(max(1, model.appCleanTotal)))
                    .frame(width: 230)
            }

            if !model.appCleanCurrent.isEmpty {
                Text(model.appCleanCurrent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 340)
            }

            Text("删除过程中请不要关闭窗口")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(26)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 4)
        .transition(.opacity)
    }

    // MARK: 底部
    private var footer: some View {
        HStack(spacing: 12) {
            if model.isCleaningAppData {
                ProgressView().controlSize(.small)
                Text("正在清理 \(model.appCleanDone)/\(model.appCleanTotal) 项…")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text("已选 \(model.detailSelection.count) 项")
                    .font(.callout).foregroundStyle(.secondary)
                Text(Fmt.size(model.detailSelectedKB))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }

            Spacer()

            Button {
                if model.detailHasRiskySelection { ui.confirmDelete = true }
                else { Task { await model.cleanSelectedAppData() } }
            } label: {
                if model.isCleaningAppData {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("清理中…")
                    }
                } else {
                    Label("删除选中项", systemImage: "trash")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(model.detailHasRiskySelection ? .red : .accentColor)
            .disabled(model.detailSelection.isEmpty || model.isCleaningAppData)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

final class DetailUIState: ObservableObject {
    @Published var confirmDelete = false
}
