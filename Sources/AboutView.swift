import SwiftUI
import AppKit

/// 独立的「关于本应用」窗口
/// 通过菜单 磁盘清理 → 关于 磁盘清理（⌘I 之外的标准位置）或设置里的按钮打开。
struct AboutView: View {
    @ObservedObject var model: CleanerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    features
                    safetyNote
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 500, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 头部
    private var header: some View {
        VStack(spacing: 10) {
            AppLogo(size: 88)

            HStack(spacing: 7) {
                Text("磁盘清理")
                    .font(.system(size: 22, weight: .semibold))
                if AppInfo.isBeta {
                    Text("BETA")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(Color.orange)
                }
            }

            HStack(spacing: 6) {
                Text("版本 \(AppInfo.displayVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if case .available(let latest, let url, _) = model.updateState {
                    Button {
                        model.openRelease(url)
                    } label: {
                        Text("有新版本 \(latest)")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.16)))
                            .foregroundStyle(Color.green)
                    }
                    .buttonStyle(.plain)
                    .help("点击前往下载")
                } else if case .upToDate = model.updateState {
                    Text("已是最新")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                        .foregroundStyle(.secondary)
                }
            }

            Text("原生 SwiftUI · 纯本地运行、不上传任何数据")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 22)
    }

    // MARK: - 功能
    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("功能")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(Self.featureList.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 17, alignment: .center)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 12, weight: .medium))
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private static let featureList: [(icon: String, title: String, detail: String)] = [
        ("internaldrive", "硬盘与内存一屏看完",
         "可用空间 / 目标、整盘用量、内存与压缩、Swap，数字口径与 macOS「储存空间」完全一致。"),
        ("chart.pie.fill", "macOS 风格的储存空间分类",
         "彩色堆叠条展示各分类占用；鼠标划入色块看精确大小，也可把数字直接标在条上。"),
        ("square.grid.2x2.fill", "逐个列出应用占用",
         "App 本体 + 用户数据（容器 / 缓存 / 支持文件），按大小排序，点击即可定位。"),
        ("layers", "三级清理，空间不够才动手",
         "安全缓存 → 开发缓存 → 用户数据（默认只报告）。达到目标立即停止，绝不「过度清理」。"),
        ("clock.arrow.circlepath", "后台自动保底",
         "登录时 + 每小时检查一次；空间充足时一秒退出，低于目标才开始清理。"),
    ]

    // MARK: - 安全说明
    private var safetyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("安全说明", systemImage: "checkmark.shield.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)

            Text("清理目标全部写在脚本白名单里，且必须位于你的主目录内；"
                 + "~/Documents、~/Desktop、~/Pictures、~/.ssh、~/Library/Keychains 等路径会被直接拒绝。"
                 + "只删除「超过 N 天没动过」的内容，超大日志是清空而不是删除，"
                 + "每个目录还有硬超时兜底。所有删除都会记录到 ~/Library/Logs/diskautoclean.log。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
    }

    // MARK: - 底部
    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                open(AppInfo.repoURL)
            } label: {
                Label("GitHub 仓库", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Button {
                open(AppInfo.releasesURL)
            } label: {
                Label("下载最新版", systemImage: "arrow.down.circle")
            }

            // 系统原生分享面板（邮件 / 信息 / AirDrop / 拷贝链接 …）
            ShareLink(item: URL(string: AppInfo.repoURL)!,
                      subject: Text("DiskCleaner"),
                      message: Text("原生 macOS 储存空间清理工具，自动保持至少 10GB 可用空间")) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            .help("分享 GitHub 链接")

            Spacer()

            Text("MIT License")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
