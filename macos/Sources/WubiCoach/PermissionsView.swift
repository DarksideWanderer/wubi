import AppKit
import SwiftUI

enum PermissionSection {
    case accessibility, inputMonitoring

    var title: String { self == .accessibility ? "辅助功能" : "输入监控" }
    private var anchor: String { self == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent" }
    var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)")!
    }
    var legacySettingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

struct PermissionsView: View {
    @ObservedObject var model: AppModel
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("权限设置").font(.title2.bold())
            Text("开启以下权限，才能读取其他应用的文字并识别待输入编码。全局字根快捷键无需这些权限。")
                .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            permissionRow(.accessibility, granted: model.accessibilityGranted,
                          description: "读取输入框中的文字和光标位置。", symbol: "accessibility")
            permissionRow(.inputMonitoring, granted: model.inputMonitoringGranted,
                          description: "识别当前输入的五笔字母。", symbol: "keyboard")
            Text("在设置列表中开启五笔伴学；未显示时可点“+”添加本应用。返回此窗口后，状态会自动更新。输入监控若提示重启，请退出后重新打开应用。")
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if !model.permissionActionMessage.isEmpty {
                Text(model.permissionActionMessage).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                Button("在访达中显示本应用") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                Spacer()
                Button("检查状态") { model.refreshPermissions() }
                Button("完成") { onFinish() }.keyboardShortcut(.defaultAction)
            }.buttonStyle(.bordered)
        }.padding(20).frame(width: 560, height: 430)
            .environment(\.colorScheme, .light)
    }

    private func permissionRow(_ section: PermissionSection, granted: Bool,
                               description: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).frame(width: 30)
                .foregroundColor(Color(red: 0, green: 0.49, blue: 0.45))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(section.title).fontWeight(.semibold)
                    Text(granted ? "已授权" : "未授权").font(.caption)
                        .foregroundColor(granted ? .green : .orange)
                }
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("打开\(section.title)设置") { model.openPermissionSettings(section) }
        }.padding(12).background(Color.gray.opacity(0.06)).cornerRadius(10)
    }
}
