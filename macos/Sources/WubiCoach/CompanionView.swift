import SwiftUI
import WubiCore

struct CompanionView: View {
    @ObservedObject var model: AppModel
    private let ink = Color(red: 0.12, green: 0.20, blue: 0.19)
    private let accent = Color(red: 0, green: 0.49, blue: 0.45)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("五笔伴学").font(.system(size: 27, weight: .bold))
                        Text("WUBI COMPANION / 86 版 · 离线联想").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(model.pinned ? "● 已置顶" : "○ 置顶") { model.pinned.toggle() }
                    Button(model.paused || model.manual ? "▶ 继续" : "Ⅱ 暂停") { model.togglePause() }
                    Button(model.codeEnabled ? "编码提示：开" : "编码提示：关") { model.codeEnabled.toggle() }
                    Button("手动 / 查字") { model.onManual?() }
                    Button("权限") { model.requestPermissions() }
                    Button("帮助") { model.onHelp?() }
                }.buttonStyle(.bordered)

                if !model.permissions.isEmpty {
                    Text(model.permissions + "。请在系统设置 → 隐私与安全性中开启对应权限。")
                        .font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if model.keyboardVisible { keyboardView }
                    else { candidateView }
                }.frame(height: 410)
                Text("按住 F8 切换字根键盘，松开恢复候选；窗口大小不变。Control+Option+W 暂停 / 继续；Control+Option+T 置顶。")
                    .font(.caption).foregroundColor(.secondary)
            }.padding(20)
        }.foregroundColor(ink).background(Color(red: 0.95, green: 0.96, blue: 0.94))
            .frame(minWidth: 960, minHeight: 450)
            .environment(\.colorScheme, .light)
    }

    private var candidateView: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.status).font(.caption).foregroundColor(accent)
                HStack {
                    Text(model.context.isEmpty ? "光标前暂无文字。" : model.context.replacingOccurrences(of: "\n", with: " ↵ "))
                        .lineLimit(2).textSelection(.disabled)
                    if !model.prefix.isEmpty {
                        Text("│ 正在输入：\(model.prefix)").fontWeight(.semibold).foregroundColor(accent)
                    }
                }.font(.system(size: 15))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(Color(red: 0.89, green: 0.94, blue: 0.91)).cornerRadius(12)

            HStack {
                Text("接下来，可能想打…").font(.headline)
                Spacer()
                Text("\(model.engine.characters.count) 字 · \(model.engine.phraseCount) 词").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Text("排序").frame(width: 35)
                Text("汉字").frame(width: 50)
                Text("完整编码").frame(width: 90, alignment: .leading)
                Text("简码").frame(width: 100, alignment: .leading)
                Text("取码字根 / 识别码").frame(width: 240, alignment: .leading)
                Text("联想依据").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption).foregroundColor(.secondary).padding(.horizontal, 12)
            VStack(spacing: 4) {
                if model.candidates.isEmpty {
                    Text("当前编码没有匹配字，请退格或按回车清空编码。")
                        .foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                ForEach(Array(model.candidates.enumerated()), id: \.element.id) { index, candidate in
                    Button { model.selected = candidate } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1)).font(.caption).foregroundColor(.secondary).frame(width: 35)
                            Text(candidate.info.character).font(.system(size: 26, weight: .semibold)).frame(width: 50)
                            Text(candidate.info.code).font(.system(size: 17, weight: .bold, design: .monospaced)).foregroundColor(accent).frame(width: 90, alignment: .leading)
                            Text(candidate.info.shortCode.isEmpty ? "—" : candidate.info.shortCode).font(.caption).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
                            Group {
                                if candidate.info.units.isEmpty { Text("暂无拆分资料").font(.caption) }
                                else { Text(candidate.info.units).font(.custom(model.rootFontName, size: 25)).tracking(2) }
                            }.frame(width: 240, alignment: .leading)
                            Text(candidate.reason).font(.caption).foregroundColor(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.horizontal, 12).padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .background(model.selected?.id == candidate.id ? Color(red: 0.88, green: 0.94, blue: 0.90) : .white)
                        .cornerRadius(8).help(candidate.info.explanation)
                }
            }.frame(minHeight: 220, alignment: .top)
            Text(detail).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(Color(red: 0.85, green: 0.92, blue: 0.88)).cornerRadius(9)
        }
    }

    private var keyboardView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("字根键盘 · 基本字根").font(.headline)
                Spacer()
                ForEach(["GFDSA", "HJKLM", "TREWQ", "YUIOP", "NBVCX"], id: \.self) { zone in
                    Text(zone).font(.caption2).foregroundColor(zoneColor(String(zone.prefix(1))))
                }
            }
            VStack(spacing: 6) {
                ForEach(["QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"], id: \.self) { row in
                    HStack(spacing: 6) { ForEach(row.map(String.init), id: \.self) { key in keyCap(key) } }
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
                Text(key).font(.system(size: 17, weight: .bold)).foregroundColor(zoneColor(key))
                Spacer()
                Text(Self.names[key] ?? "学习键").font(.caption2).foregroundColor(.secondary)
            }
            if key == "Z" { Text("万能查询").font(.caption).foregroundColor(.secondary) }
            else { Text(model.engine.keyboardRoots[key] ?? "").font(.custom(model.rootFontName, size: 14))
                    .lineSpacing(2).frame(maxWidth: .infinity, alignment: .topLeading) }
            Spacer(minLength: 0)
        }.padding(7).frame(width: 84, height: 108, alignment: .topLeading)
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

struct ManualView: View {
    @ObservedObject var model: AppModel
    @State var context: String
    @State var prefix: String
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("手动上下文 / 查字").font(.title2.bold())
            Text("输入上下文来预测，或输入一个汉字查询拆分。").foregroundColor(.secondary)
            TextEditor(text: $context).font(.system(size: 18)).frame(height: 120).border(Color.gray.opacity(0.3))
            TextField("正在输入的五笔字母，例如 r / ru（可留空）", text: $prefix)
            HStack {
                Button("预测下一字") { if model.applyManual(context: context, prefix: prefix, lookup: false) { onFinish() } }
                Button("查单字") { if model.applyManual(context: context, prefix: "", lookup: true) { onFinish() } }
                Spacer()
                Button("关闭") { onFinish() }
            }.buttonStyle(.bordered)
            Text(model.status).font(.caption).foregroundColor(.secondary)
            Text("点击主窗口的「继续」恢复跨应用读取。").font(.caption).foregroundColor(.secondary)
        }.padding(20).frame(width: 510)
    }
}
