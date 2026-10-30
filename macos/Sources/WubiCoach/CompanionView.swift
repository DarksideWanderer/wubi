import SwiftUI
import WubiCore

enum CompanionLayout {
    static let width: CGFloat = 800
    static let height: CGFloat = 420
    static let contentHeight: CGFloat = 328
}

struct CompanionView: View {
    @ObservedObject var model: AppModel
    private let ink = Color(red: 0.12, green: 0.20, blue: 0.19)
    private let accent = Color(red: 0, green: 0.49, blue: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("五笔伴学").font(.system(size: 21, weight: .bold))
                    Text("86 版 · 离线联想").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(model.pinned ? "● 已置顶" : "○ 置顶") { model.pinned.toggle() }
                Button(model.paused ? "▶ 继续" : "Ⅱ 暂停") { model.togglePause() }
                Button(model.codeEnabled ? "编码：开" : "编码：关") { model.codeEnabled.toggle() }
                Button("手动 / 查字") { model.onManual?() }
                Button("权限") { model.requestPermissions() }
                Button("帮助") { model.onHelp?() }.help(model.shortcutStatus)
            }.buttonStyle(.bordered).controlSize(.small).font(.system(size: 12))

            if !model.permissions.isEmpty {
                Text(model.permissions)
                    .font(.system(size: 11)).foregroundColor(.orange).lineLimit(1).help(model.permissions)
            }
            Group {
                if model.keyboardVisible { keyboardView }
                else { candidateView }
            }.frame(height: CompanionLayout.contentHeight, alignment: .top)
        }.padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minWidth: CompanionLayout.width, maxWidth: .infinity, minHeight: CompanionLayout.height, maxHeight: .infinity, alignment: .topLeading)
            .foregroundColor(ink).background(Color(red: 0.95, green: 0.96, blue: 0.94))
            .environment(\.colorScheme, .light)
    }

    private var candidateView: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(model.status).font(.system(size: 10)).foregroundColor(accent).lineLimit(1).help(model.status)
                    if model.needsEditorAccessibility {
                        Spacer(minLength: 4)
                        Button("编辑器设置") { model.openEditorAccessibilitySettings() }
                            .font(.system(size: 10)).controlSize(.mini)
                    }
                }
                HStack {
                    Text(model.context.isEmpty ? "光标前暂无文字。" : model.context.replacingOccurrences(of: "\n", with: " ↵ "))
                        .lineLimit(1).textSelection(.disabled)
                    if !model.prefix.isEmpty {
                        Text("│ 正在输入：\(model.prefix)").fontWeight(.semibold).foregroundColor(accent)
                    }
                }.font(.system(size: 13))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                .background(Color(red: 0.89, green: 0.94, blue: 0.91)).cornerRadius(12)

            HStack(spacing: 12) {
                Text(model.preferenceNotice.isEmpty ? "个人偏好 · 不足时按常规补齐" : "偏好不可用 · 常规补齐")
                    .help(model.preferenceNotice.isEmpty ? "点击候选与确认上屏的新字会保存在本机，作为个人偏好。" : model.preferenceNotice)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("常规联想 · 已排除左侧").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.system(size: 11, weight: .semibold))
            if model.candidates.isEmpty {
                Text("当前编码没有匹配字，请退格或按回车清空编码。")
                    .font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 231, alignment: .topLeading)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    candidateColumn(items: model.preferredCandidates, start: 0)
                    candidateColumn(items: model.regularCandidates, start: 9)
                }
            }
            Text(detail).font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .padding(6).background(Color(red: 0.85, green: 0.92, blue: 0.88)).cornerRadius(9)
        }
    }

    private func candidateColumn(items: [WubiCandidate], start: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("序").frame(width: 20)
                Text("字").frame(width: 28)
                Text("完整码").frame(width: 52, alignment: .leading)
                Text("简码").frame(width: 64, alignment: .leading)
                Text("取码字根 / 识别码").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.system(size: 10)).foregroundColor(.secondary).padding(.horizontal, 4)
            VStack(spacing: 2) {
                ForEach(0..<9, id: \.self) { offset in
                    let index = start + offset
                    if offset < items.count {
                        let candidate = items[offset]
                        Button { model.select(candidate) } label: {
                            HStack(spacing: 4) {
                                Text(String(format: "%02d", index + 1)).font(.system(size: 10)).foregroundColor(.secondary).frame(width: 20)
                                Text(candidate.info.character).font(.system(size: 19, weight: .semibold)).frame(width: 28)
                                Text(candidate.info.code).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(accent).frame(width: 52, alignment: .leading)
                                Text(candidate.info.shortCode.isEmpty ? "—" : candidate.info.shortCode).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1).frame(width: 64, alignment: .leading)
                                Group {
                                    if candidate.info.units.isEmpty { Text("暂无拆分").font(.system(size: 10)) }
                                    else { Text(candidate.info.units).font(.custom(model.rootFontName, size: 18)).tracking(1) }
                                }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(height: 22).padding(.horizontal, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .background(model.selected?.id == candidate.id ? Color(red: 0.88, green: 0.94, blue: 0.90) : .white)
                            .cornerRadius(5).help(candidate.info.explanation)
                    } else { Color.clear.frame(height: 22).accessibilityHidden(true) }
                }
            }.frame(height: 214, alignment: .top)
        }.frame(maxWidth: .infinity)
    }

    private var keyboardView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("字根键盘 · 基本字根").font(.system(size: 12, weight: .semibold))
                Spacer()
                ForEach(["GFDSA", "HJKLM", "TREWQ", "YUIOP", "NBVCX"], id: \.self) { zone in
                    Text(zone).font(.caption2).foregroundColor(zoneColor(String(zone.prefix(1))))
                }
            }
            VStack(spacing: 4) {
                ForEach(["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"], id: \.self) { row in
                    HStack(spacing: 4) { ForEach(row.map(String.init), id: \.self) { key in keyCap(key) } }
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var detail: String {
        guard let candidate = model.selected else { return "暂无匹配候选。" }
        return "\(candidate.info.character)   \(candidate.info.code.map(String.init).joined(separator: " → "))     \(candidate.info.explanation)"
    }

    private func keyCap(_ key: String) -> some View {
        let highlighted = model.selected?.info.code.contains(key) ?? false
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(key).font(.system(size: 14, weight: .bold)).foregroundColor(zoneColor(key))
                Spacer()
                Text(Self.names[key] ?? "学习键").font(.caption2).foregroundColor(.secondary)
            }
            if key == "Z" { Text("万能查询").font(.caption).foregroundColor(.secondary) }
            else { Text(model.engine.keyboardRoots[key] ?? "").font(.custom(model.rootFontName, size: 12))
                    .lineSpacing(1).frame(maxWidth: .infinity, alignment: .topLeading) }
            Spacer(minLength: 0)
        }.padding(6).frame(width: 70, height: 88, alignment: .topLeading)
            .background(highlighted ? Color(red: 0.86, green: 0.95, blue: 0.90) : .white)
            .cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(highlighted ? accent : Color.gray.opacity(0.2), lineWidth: highlighted ? 2 : 1))
            .help(Self.mnemonics[key] ?? "Z：学习键，用法取决于输入法")
    }

    private func zoneColor(_ key: String) -> Color {
        if "GFDSA".contains(key) { return Color(red: 0.67, green: 0.40, blue: 0.18) }
        if "HJKLM".contains(key) { return Color(red: 0.20, green: 0.48, blue: 0.60) }
        if "TREWQ".contains(key) { return Color(red: 0.27, green: 0.50, blue: 0.35) }
        if "YUIOP".contains(key) { return Color(red: 0.54, green: 0.40, blue: 0.60) }
        return Color(red: 0.67, green: 0.39, blue: 0.44)
    }

    private static let names = Dictionary(uniqueKeysWithValues: zip(Array("ABCDEFGHIJKLMNOPQRSTUVWXY").map(String.init), Array("工子又大月土王目水日口田山已火之金白木禾立女人幺言").map(String.init)))
    private static let mnemonics: [String: String] = [
        "A":"工戈草头右框七", "B":"子耳了也框向上", "C":"又巴马，丢矢矣", "D":"大犬三羊古石厂",
        "E":"月彡乃用家衣底", "F":"土士二干十寸雨", "G":"王旁青头戋五一", "H":"目具上止卜虎皮",
        "I":"水旁兴头小倒立", "J":"日早两竖与虫依", "K":"口与川，字根稀", "L":"田甲方框四车力",
        "M":"山由贝，下框几", "N":"已半巳满不出己，左框折尸心和羽", "O":"火业头，四点米",
        "P":"之字军盖建道底", "Q":"金勺缺点无尾鱼，犬旁留儿一点夕", "R":"白手看头三二斤", "S":"木丁西",
        "T":"禾竹一撇双人立，反文条头共三一", "U":"立辛两点六门疒", "V":"女刀九臼山朝西",
        "W":"人和八，三四里", "X":"慈母无心弓和匕，幼无力", "Y":"言文方广在四一，高头一捺谁人去"
    ]
}
