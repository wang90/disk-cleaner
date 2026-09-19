import AppKit
import SwiftUI

/// 菜单栏小图标（AppKit `NSStatusItem` + `NSPopover` 实现）
///
/// 为什么不用 SwiftUI 的 `MenuBarExtra`：
/// 本机这套 Swift 工具链会为 `MenuBarExtra` 场景生成**递归的不透明类型描述符**，
/// App 启动时解析类型元数据会无限递归 → 栈溢出崩溃：
///     EXC_BAD_ACCESS (SIGSEGV) "Could not determine thread index for stack guard region"
/// 实测（每次全新启动）：带 MenuBarExtra 8 次里崩 1~3 次，去掉后连续 8 次全部正常；
/// 而 AppKit 的 NSStatusItem 连续 8 次启动全部正常。因此这里改用 AppKit。
@MainActor
final class MenuBarController: NSObject {

    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var timer: Timer?
    private weak var model: CleanerModel?

    /// App 启动后调用一次
    func attach(model: CleanerModel) {
        self.model = model

        // 用定时器同步菜单栏（1 秒一次，开销极小）。
        // 不用 Combine 的 sink 是为了避开 @MainActor 隔离带来的并发告警。
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sync()
            }
        }
        sync()
    }

    private func sync() {
        guard let model else { return }
        if model.showMenuBarExtra {
            installIfNeeded()
            updateButton()
        } else {
            uninstall()
        }
    }

    private func installIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item
    }

    private func uninstall() {
        guard let item = statusItem else { return }
        popover?.performClose(nil)
        popover = nil
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    private func updateButton() {
        guard let model, let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: model.menuBarSymbol, accessibilityDescription: "磁盘清理")
        image?.isTemplate = true
        button.image = image
        button.title = model.showMenuBarText ? " " + model.freeSpaceShort : ""
        button.toolTip = "磁盘清理 · 可用 \(Fmt.size(model.freeKB))（目标 \(model.targetGB) GB）"
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let model, let button = statusItem?.button else { return }

        if let pop = popover, pop.isShown {
            pop.performClose(sender)
            return
        }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = NSHostingController(rootView: MenuBarPanel(model: model))
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = pop
    }
}

/// 只负责在启动后把菜单栏图标装起来
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            MenuBarController.shared.attach(model: CleanerModel.shared)
        }
    }
}
