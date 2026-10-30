import AppKit
import SwiftUI
import WubiCore

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel?
    private var panel: CompanionPanel?
    private var manualWindow: NSWindow?
    private var permissionsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let model = try AppModel(dataDirectory: try locateData())
            self.model = model
            let panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: CompanionLayout.width, height: CompanionLayout.height),
                                       styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            panel.contentMinSize = NSSize(width: CompanionLayout.width, height: CompanionLayout.height)
            panel.title = "五笔伴学 · 86版"
            panel.contentView = ClickableHostingView(rootView: CompanionView(model: model))
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.center(); panel.orderFrontRegardless()
            self.panel = panel
            model.onPinChanged = { [weak panel] pinned in panel?.level = pinned ? .floating : .normal }
            model.onManual = { [weak self] in self?.showManual() }
            model.onHelp = { [weak self] in self?.showHelp() }
            model.onPermissions = { [weak self] in self?.showPermissions() }
            installMenu(); model.start()
        } catch {
            let alert = NSAlert()
            alert.messageText = "五笔伴学启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
    func applicationDidBecomeActive(_ notification: Notification) { model?.refreshPermissions() }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === panel { NSApp.terminate(nil) }
    }

    @objc private func showPanel() { panel?.deminiaturize(nil); panel?.orderFrontRegardless() }
    @objc private func togglePause() { model?.togglePause() }
    @objc private func togglePin() { model?.pinned.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }


    private func installMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "五笔"
        let menu = NSMenu()
        for (title, selector) in [("显示悬浮窗", #selector(showPanel)), ("暂停 / 继续", #selector(togglePause)),
                                  ("切换置顶", #selector(togglePin)), ("退出五笔伴学", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        statusItem?.menu = menu
    }

    private func showManual() {
        guard let model = model else { return }
        if let window = manualWindow, window.isVisible { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        model.beginManual()
        let window = ManualWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "手动上下文 / 查字"
        window.level = .floating; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ManualView(model: model, context: model.context, prefix: model.prefix,
                                                               onFinish: { [weak window] in window?.close() }))
        manualWindow = window
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }

    private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "五笔伴学 · macOS"
        alert.informativeText = "在其他应用中输入中文，上屏后读取光标前最多 80 字。按字母维护当前五笔编码，例如「直 + R」预测「接 · RUVG」。退格删除一位；回车、空格、数字选词和导航键清空。\n\n全局快捷键独立于读取权限，在其他应用前台也可使用；窗口底部显示注册状态。读取文字和编码时，请点击「权限」，在系统设置 → 隐私与安全性中授权辅助功能和输入监控；授权后可重启应用。受保护输入和密码框不参与预测。\n\n按住 \(HoldKeyboardShortcut.label) 查看字根键盘，松开任一组合键恢复候选；主窗口不滚动。候选点击不抢输入焦点，手动窗口可以输入文字。按键推测无法完整还原输入法内部候选列表和自定义上屏规则。\n\nControl+Option+W 暂停 / 继续\nControl+Option+T 切换置顶\n\n关闭主窗口即退出。词库、字体及许可见随附 THIRD-PARTY.md。"
        alert.addButton(withTitle: "知道了")
        alert.addButton(withTitle: "打开系统设置")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    private func showPermissions() {
        guard let model = model else { return }
        if let window = permissionsWindow, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Permission controls need an ordinary key window; the companion panel
        // deliberately cannot take keyboard focus from the user's editor.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "五笔伴学 · 权限设置"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PermissionsView(model: model,
                                            onFinish: { [weak window] in window?.close() }))
        permissionsWindow = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func locateData() throws -> URL {
        let manager = FileManager.default
        let cwd = URL(fileURLWithPath: manager.currentDirectoryPath)
        let directories = [Bundle.main.resourceURL?.appendingPathComponent("data"),
                           cwd.appendingPathComponent("data"), cwd.appendingPathComponent("../data")]
        if let found = directories.compactMap({ $0 }).first(where: { manager.fileExists(atPath: $0.appendingPathComponent("decomposition.tsv").path) }) { return found }
        throw NSError(domain: "WubiCoach", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到 data 目录，请用 macos/build.sh 构建完整 .app。"])
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
