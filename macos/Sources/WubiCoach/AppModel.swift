import AppKit
import ApplicationServices
import CoreText
import SwiftUI
import WubiCore

final class AppModel: ObservableObject {
    let engine: LearningEngine
    let dataDirectory: URL
    let rootFontName: String
    @Published private(set) var context = ""
    @Published private(set) var prefix = ""
    @Published private(set) var status = "等待其他应用的输入框"
    @Published private(set) var candidates: [WubiCandidate] = []
    @Published var selected: WubiCandidate?
    @Published var keyboardVisible = false
    @Published var pinned = true { didSet { onPinChanged?(pinned) } }
    @Published var codeEnabled = true { didSet { updateCandidates() } }
    @Published private(set) var paused = false
    @Published private(set) var permissions = ""
    @Published private(set) var shortcutStatus = "正在注册全局快捷键"
    @Published private(set) var shortcutsReady = false
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var inputMonitoringGranted = CGPreflightListenEventAccess()
    @Published private(set) var permissionActionMessage = ""
    @Published private(set) var needsEditorAccessibility = false
    var onPinChanged: ((Bool) -> Void)?
    var onManual: (() -> Void)?
    var onHelp: (() -> Void)?
    var onPermissions: (() -> Void)?

    private let monitor = KeyMonitor()
    private let reader = ContextReader()
    private let queue = DispatchQueue(label: "org.wubicoach.context", qos: .utility)
    private var timer: Timer?
    private var busy = false
    private var generation = 0
    private var refreshAfterPreview = false
    private var pending = PendingCode()
    private var keyQueue: [CodeKey] = []
    private var allowedPID: pid_t = 0
    private var focusID = ""
    private var lastSample = Date.distantPast

    init(dataDirectory: URL) throws {
        self.dataDirectory = dataDirectory
        engine = try LearningEngine(dataDirectory: dataDirectory)
        let fontURL = dataDirectory.appendingPathComponent("roots.ttf") as CFURL
        CTFontManagerRegisterFontsForURL(fontURL, .process, nil)
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor],
           let descriptor = descriptors.first,
           let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
            rootFontName = name
        } else { throw NSError(domain: "WubiCoach", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法加载 roots.ttf 字根字体"]) }
        updateCandidates()
    }

    func start() {
        monitor.onKey = { [weak self] key, pid in
            guard let self = self, !self.paused,
                  pid == self.allowedPID, Date().timeIntervalSince(self.lastSample) < 1 else { return }
            if self.keyQueue.count >= 32 { self.keyQueue.removeAll(); self.pending.clear() }
            self.keyQueue.append(key)
        }
        monitor.onShortcut = { [weak self] letter in
            if letter == "W" { self?.togglePause() } else { self?.pinned.toggle() }
        }
        monitor.onKeyboardVisibility = { [weak self] visible in self?.keyboardVisible = visible }
        monitor.start()
        timer = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in self?.poll() }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        poll()
    }

    func stop() { timer?.invalidate(); timer = nil; monitor.stop(); clearCapture() }

    func togglePause() {
        paused.toggle()
        generation += 1; clearCapture(); context = ""; prefix = ""
        status = paused ? "已暂停 · 上下文和编码已清除" : "等待其他应用的输入框"
        updateCandidates()
    }

    func beginManual() {
        generation += 1; clearCapture()
    }

    @discardableResult func applyManual(context: String, prefix: String, lookup: Bool) -> Bool {
        if lookup && engine.lookup(character: context.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
            status = "请输入一个已收录的汉字"; return false
        }
        generation += 1; clearCapture(); refreshAfterPreview = true
        self.context = String(context.suffix(80)); self.prefix = PendingCode.normalize(prefix)
        if lookup {
            guard let info = engine.lookup(character: context.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                status = "请输入一个已收录的汉字"; return false
            }
            self.prefix = ""; candidates = [WubiCandidate(info: info, reason: "单字查询")]; selected = candidates.first
        } else { updateCandidates() }
        status = paused ? "手动查询 · 自动读取已暂停" : "手动查询 · 返回其他应用后自动继续读取"
        return true
    }

    func requestPermissions() {
        refreshPermissions()
        onPermissions?()
    }

    func refreshPermissions() { poll() }

    func openEditorAccessibilitySettings() {
        _ = NSWorkspace.shared.open(URL(string: "vscode://settings/editor.accessibilitySupport")!)
    }

    func openPermissionSettings(_ section: PermissionSection) {
        if section == .accessibility, !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } else if section == .inputMonitoring, !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        // Open the pane even when macOS no longer repeats its permission prompt.
        let workspace = NSWorkspace.shared
        if workspace.open(section.settingsURL) || workspace.open(section.legacySettingsURL) {
            permissionActionMessage = "已打开\(section.title)设置，请在列表中开启五笔伴学。"
        } else if workspace.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) {
            permissionActionMessage = "请在系统设置 → 隐私与安全性 → \(section.title)中开启五笔伴学。"
        } else {
            permissionActionMessage = "无法自动打开系统设置，请手动进入隐私与安全性 → \(section.title)。"
        }
        refreshPermissions()
    }

    private func poll() {
        let accessibility = AXIsProcessTrusted()
        accessibilityGranted = accessibility
        inputMonitoringGranted = CGPreflightListenEventAccess()
        monitor.start()
        shortcutStatus = monitor.shortcutStatus
        shortcutsReady = monitor.shortcutsReady
        let missing = [accessibility ? nil : "辅助功能", inputMonitoringGranted ? nil : "输入监控"].compactMap { $0 }
        permissions = !missing.isEmpty ? "未授权：" + missing.joined(separator: "、") + " · 点击「权限」设置" :
            (!monitor.installed ? "输入监听未启动 · 请重启应用" : "")
        guard !paused else { return }
        guard accessibility else { unavailable(permissions); return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let pid = front.processIdentifier
        if allowedPID != 0 && allowedPID != pid { clearCapture(); prefix = ""; context = ""; updateCandidates() }
        if Date().timeIntervalSince(lastSample) > 1 { allowedPID = 0; keyQueue.removeAll(); pending.clear() }
        guard !busy else { return }
        busy = true
        let revision = generation
        let source = front.localizedName ?? "其他应用"
        queue.async { [weak self] in
            guard let self = self else { return }
            let snapshot = self.reader.read(processID: pid)
            DispatchQueue.main.async {
                self.busy = false
                guard self.generation == revision, !self.paused,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                self.apply(snapshot, source: source)
            }
        }
    }

    private func apply(_ snapshot: ContextSnapshot, source: String) {
        guard snapshot.available else {
            unavailable(source + " · " + snapshot.status, needsEditorAccessibility: snapshot.needsEditorAccessibility)
            return
        }
        needsEditorAccessibility = false
        if focusID != snapshot.focusID { clearCapture() }
        focusID = snapshot.focusID; allowedPID = snapshot.processID; lastSample = Date()
        for key in keyQueue { pending.consume(key) }; keyQueue.removeAll()
        let text = pending.reconcile(context: snapshot.text)
        let nextPrefix = pending.code
        status = source + " · " + snapshot.status + (nextPrefix.isEmpty ? "" : " · 按键推测")
        if refreshAfterPreview || context != text || prefix != nextPrefix {
            refreshAfterPreview = false
            context = text; prefix = nextPrefix; updateCandidates()
        }
    }

    private func unavailable(_ message: String, needsEditorAccessibility: Bool = false) {
        self.needsEditorAccessibility = needsEditorAccessibility
        clearCapture(); status = message
        if !context.isEmpty || !prefix.isEmpty { context = ""; prefix = ""; updateCandidates() }
    }

    private func clearCapture() { pending.clear(); keyQueue.removeAll(); allowedPID = 0; focusID = ""; lastSample = .distantPast }

    private func updateCandidates() {
        candidates = engine.predict(context: context, codePrefix: codeEnabled ? prefix : "")
        selected = candidates.first
    }
}
