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
    @Published private(set) var manual = false
    @Published private(set) var permissions = ""
    var onPinChanged: ((Bool) -> Void)?
    var onManual: (() -> Void)?
    var onHelp: (() -> Void)?

    private let monitor = KeyMonitor()
    private let reader = ContextReader()
    private let queue = DispatchQueue(label: "org.wubicoach.context", qos: .utility)
    private var timer: Timer?
    private var busy = false
    private var generation = 0
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
            guard let self = self, !self.paused, !self.manual,
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
        if manual { manual = false; paused = false } else { paused.toggle() }
        generation += 1; clearCapture(); context = ""; prefix = ""
        status = paused ? "已暂停 · 上下文和编码已清除" : "等待其他应用的输入框"
        updateCandidates()
    }

    func beginManual() {
        manual = true; generation += 1; clearCapture()
        status = "手动上下文 · 点击继续恢复跨应用读取"
    }

    @discardableResult func applyManual(context: String, prefix: String, lookup: Bool) -> Bool {
        manual = true; paused = false; generation += 1; clearCapture()
        self.context = String(context.suffix(80)); self.prefix = PendingCode.normalize(prefix)
        if lookup {
            guard let info = engine.characters[context.trimmingCharacters(in: .whitespacesAndNewlines)] else {
                status = "请输入一个已收录的汉字"; return false
            }
            self.prefix = ""; candidates = [WubiCandidate(info: info, reason: "单字查询")]; selected = candidates.first
        } else { updateCandidates() }
        status = "手动上下文 · 点击继续恢复跨应用读取"
        return true
    }

    func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
        monitor.start(); poll()
    }

    private func poll() {
        let accessibility = AXIsProcessTrusted()
        monitor.start()
        permissions = !accessibility ? "需要辅助功能权限：读取其他应用的光标上下文" :
            (!monitor.installed ? "需要输入监控权限：监听五笔字母；授权后可重启应用" : "")
        guard !paused, !manual else { return }
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
                guard self.generation == revision, !self.paused, !self.manual,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                self.apply(snapshot, source: source)
            }
        }
    }

    private func apply(_ snapshot: ContextSnapshot, source: String) {
        guard snapshot.available else { unavailable(source + " · " + snapshot.status); return }
        if focusID != snapshot.focusID { clearCapture() }
        focusID = snapshot.focusID; allowedPID = snapshot.processID; lastSample = Date()
        for key in keyQueue { pending.consume(key) }; keyQueue.removeAll()
        let text = pending.reconcile(context: snapshot.text)
        let nextPrefix = pending.code
        status = source + " · " + snapshot.status + (nextPrefix.isEmpty ? "" : " · 按键推测")
        if context != text || prefix != nextPrefix {
            context = text; prefix = nextPrefix; updateCandidates()
        }
    }

    private func unavailable(_ message: String) {
        clearCapture(); status = message
        if !context.isEmpty || !prefix.isEmpty { context = ""; prefix = ""; updateCandidates() }
    }

    private func clearCapture() { pending.clear(); keyQueue.removeAll(); allowedPID = 0; focusID = ""; lastSample = .distantPast }

    private func updateCandidates() {
        candidates = engine.predict(context: context, codePrefix: codeEnabled ? prefix : "")
        selected = candidates.first
    }
}
