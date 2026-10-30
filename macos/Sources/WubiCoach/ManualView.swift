import AppKit
import SwiftUI
import WubiCore

/// A dedicated editor keeps the pinyin field Roman without altering other fields.
final class ManualWindow: NSWindow, NSWindowDelegate {
    private let romanEditor: RomanFieldEditor = {
        let editor = RomanFieldEditor()
        editor.isFieldEditor = true
        editor.inputContext?.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
        return editor
    }()

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        client is PinyinSearchField ? romanEditor : nil
    }
}

private final class RomanFieldEditor: NSTextView {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers.isEmpty, let text = event.charactersIgnoringModifiers,
           !text.isEmpty, text.lowercased().utf8.allSatisfy({ (97...122).contains($0) }) {
            // Insert letters directly instead of invoking an installed Chinese IME.
            insertText(text, replacementRange: selectedRange())
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class PinyinSearchField: NSTextField {}

private struct PinyinInput: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = PinyinSearchField()
        field.placeholderString = "输入拼音，例如 shi、zhong、lv"
        field.font = .systemFont(ofSize: 18)
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.setAccessibilityLabel("单字拼音")
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PinyinInput
        init(_ parent: PinyinInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit(); return true }
            return false
        }
    }
}

struct ManualView: View {
    @ObservedObject var model: AppModel
    @State var context: String
    @State var prefix: String
    var onFinish: () -> Void
    @State private var query = ""
    @State private var results: [PinyinCharacter] = []
    @State private var selected: PinyinCharacter?
    private let accent = Color(red: 0, green: 0.49, blue: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("手动 / 查字").font(.title2.bold())
            Text("内置离线拼音 · 只查单字，不需要切换系统输入法").font(.callout).foregroundColor(.secondary)
            TabView {
                pinyinView.tabItem { Text("拼音查字") }
                contextView.tabItem { Text("上下文 / 汉字查码") }
            }
            Text("返回其他应用后自动继续读取；原本已暂停时保持暂停。").font(.caption).foregroundColor(.secondary)
        }.padding(20).frame(width: 620, height: 560)
            .environment(\.colorScheme, .light)
    }

    private var pinyinView: some View {
        VStack(alignment: .leading, spacing: 10) {
            PinyinInput(text: $query, onSubmit: applySelection).frame(height: 32)
                .onChange(of: query) { value in
                    results = model.engine.pinyin.search(value)
                    selected = results.first
                }
            Text(resultMessage).font(.caption).foregroundColor(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                        ForEach(results) { item in
                            Button { selected = item } label: {
                                Text(item.character).font(.system(size: 27)).frame(maxWidth: .infinity).frame(height: 38)
                                    .background(selected?.id == item.id ? accent.opacity(0.15) : Color.white)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected?.id == item.id ? accent : Color.gray.opacity(0.15)))
                            }.buttonStyle(.plain).id(item.id)
                                .accessibilityLabel("\(item.character)，\(item.readings.joined(separator: "、"))")
                        }
                    }.padding(2)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: query) { _ in if let first = results.first { proxy.scrollTo(first.id, anchor: .top) } }
            }
            selectionDetail.frame(height: 100, alignment: .topLeading)
            HStack {
                Text("不分声调 · ü 用 v · 完整拼音匹配").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("查看五笔", action: applySelection).buttonStyle(.borderedProminent).tint(accent)
                    .disabled(selected.flatMap { model.engine.lookup(character: $0.character) } == nil)
                Button("关闭", action: onFinish).keyboardShortcut(.cancelAction)
            }
        }.padding(12)
    }

    private var resultMessage: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "输入一个完整拼音，显示全部同音单字；点击汉字预览，回车查看五笔。" }
        if results.isEmpty { return "暂无匹配单字，请输入一个完整拼音（例如 ni，不是 nihao）。" }
        return "\(PinyinIndex.normalize(query)) · 共 \(results.count) 个单字 · 常用字优先，可滚动查看全部"
    }

    private var selectionDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let item = selected {
                HStack(spacing: 12) {
                    Text(item.character).font(.system(size: 30, weight: .semibold))
                    Text(item.readings.joined(separator: " / ")).foregroundColor(.secondary)
                    if let info = model.engine.lookup(character: item.character) {
                        Text(info.code).font(.system(size: 19, weight: .bold, design: .monospaced)).foregroundColor(accent)
                        Text("简码 \(info.shortCode.isEmpty ? "—" : info.shortCode)").font(.caption)
                        Text(info.units.isEmpty ? "暂无拆分资料" : (info.identification.isEmpty ? info.units : String(info.units.dropLast())))
                            .font(.custom(model.rootFontName, size: 25))
                        if !info.identification.isEmpty {
                            Text("识别码 \(info.code.suffix(1))").font(.caption).foregroundColor(accent)
                        }
                    }
                }
                if let info = model.engine.lookup(character: item.character) { Text(info.explanation).font(.caption).fixedSize(horizontal: false, vertical: true) }
                else { Text("当前五笔词库未收录此字；仍保留在拼音结果中。").font(.caption).foregroundColor(.secondary) }
            } else {
                Text("选择一个汉字，查看五笔完整码、简码和字根。").font(.callout).foregroundColor(.secondary)
            }
        }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(accent.opacity(0.07)).cornerRadius(8)
    }

    private func applySelection() {
        guard let item = selected, model.engine.lookup(character: item.character) != nil else { return }
        if model.applyManual(context: item.character, prefix: "", lookup: true) { onFinish() }
    }

    private var contextView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("输入上下文来预测，或输入一个汉字查询拆分。").foregroundColor(.secondary)
            TextEditor(text: $context).font(.system(size: 18)).frame(maxHeight: .infinity).border(Color.gray.opacity(0.3))
            TextField("正在输入的五笔字母，例如 r / ru（可留空）", text: $prefix)
            HStack {
                Button("预测下一字") { if model.applyManual(context: context, prefix: prefix, lookup: false) { onFinish() } }
                Button("查单字") { if model.applyManual(context: context, prefix: "", lookup: true) { onFinish() } }
                Spacer()
                Button("关闭", action: onFinish)
            }.buttonStyle(.bordered)
            Text(model.status).font(.caption).foregroundColor(.secondary)
        }.padding(12)
    }
}
