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
}

/// Runs on a serial background queue; no Accessibility calls occur inside the event tap.
final class ContextReader {
    func read(processID: pid_t) -> ContextSnapshot {
        var result = ContextSnapshot(processID: processID)
        guard AXIsProcessTrusted() else { result.status = "需要辅助功能权限"; return result }
        guard !IsSecureEventInputEnabled() else { result.status = "安全输入已开启 · 暂停读取"; return result }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.25)
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
           let value = text as? String {
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
        result.status = "实时读取 · 光标前最多 80 字"
        result.available = true
        return result
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
