import AppKit
import ApplicationServices
import Carbon
import WubiCore

struct ContextSnapshot {
    var text = ""
    var status = ""
    var processID: pid_t = 0
    var focusID = ""
    var available = false
    var needsEditorAccessibility = false
}

/// Runs on a serial background queue; no Accessibility calls occur inside the event tap.
final class ContextReader {
    private var requestedAccessibility = Set<pid_t>()

    func read(processID: pid_t) -> ContextSnapshot {
        var result = ContextSnapshot(processID: processID)
        guard AXIsProcessTrusted() else { result.status = "需要辅助功能权限"; return result }
        guard !IsSecureEventInputEnabled() else { result.status = "安全输入已开启 · 暂停读取"; return result }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
        if requestedAccessibility.insert(processID).inserted {
            // Electron documents this attribute for third-party accessibility
            // clients. Request its text tree once per process, never every poll.
            _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        guard let rawFocus = attribute(application, kAXFocusedUIElementAttribute),
              CFGetTypeID(rawFocus) == AXUIElementGetTypeID() else {
            result.status = "等待输入框获得焦点"; return result
        }
        let focus = rawFocus as! AXUIElement
        var owner: pid_t = 0
        AXUIElementGetPid(focus, &owner)
        guard owner == processID else { result.status = "输入焦点正在切换"; return result }
        AXUIElementSetMessagingTimeout(focus, 0.25)
        // Password fields and secure ancestors must be checked before requesting any text.
        var ancestor: AXUIElement? = focus
        for _ in 0..<6 {
            guard let element = ancestor else { break }
            AXUIElementSetMessagingTimeout(element, 0.25)
            if (attribute(element, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole {
                result.status = "密码输入框 · 已停止读取"; return result
            }
            if let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() {
                ancestor = (parent as! AXUIElement)
            } else { ancestor = nil }
        }
        let labels = [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute]
            .compactMap { attribute(focus, $0) as? String }.joined(separator: " ").lowercased()
        if labels.contains("无法访问编辑器") || labels.contains("editor content cannot be accessed") ||
            labels.contains("screen reader optimized mode") || labels.contains("屏幕阅读器优化模式") {
            result.status = "编辑器未开放文本 · 请将 VS Code 的 Editor: Accessibility Support 设为 On"
            result.needsEditorAccessibility = true
            return result
        }
        guard let rangeValue = attribute(focus, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            result.status = "此输入框未提供光标位置 · 可使用手动上下文"; return result
        }
        var selection = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection), selection.location >= 0 else {
            result.status = "无法取得光标位置"; return result
        }
        var wanted = CFRange(location: max(0, selection.location - 80), length: min(80, selection.location))
        var text: CFTypeRef?
        if let parameter = AXValueCreate(.cfRange, &wanted),
           AXUIElementCopyParameterizedAttributeValue(focus, kAXStringForRangeParameterizedAttribute as CFString, parameter, &text) == .success,
           let value = text as? String, !value.isEmpty || wanted.length == 0 {
            result.text = value
        } else if let value = attribute(focus, kAXValueAttribute) as? String {
            let string = value as NSString
            guard selection.location <= string.length else { result.status = "光标位置已变化"; return result }
            result.text = string.substring(with: NSRange(location: wanted.location, length: wanted.length))
        } else {
            result.status = "此输入框未开放文本内容 · 可使用手动上下文"; return result
        }
        // Recheck focus so a slow AX request cannot publish another input field's stale text.
        guard let current = attribute(application, kAXFocusedUIElementAttribute), CFEqual(rawFocus, current) else {
            result.status = "输入焦点已变化"; result.text = ""; return result
        }
        result.focusID = "\(processID):\(CFHash(focus))"
        result.text = result.text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\0", with: "")
        guard wanted.length == 0 || !result.text.isEmpty else {
            result.status = "编辑器未返回光标前的文字 · 可使用手动上下文"
            return result
        }
        result.status = "实时读取 · 光标前最多 80 字"
        result.available = true
        return result
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
