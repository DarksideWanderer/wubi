# macOS 版

原生 SwiftUI + AppKit 悬浮窗，最低 macOS 13。共用仓库根目录 `data/`，无需重新下载词库；无第三方 Swift 依赖。

## 功能

- 置顶、跨桌面显示，候选点击保持原应用的输入焦点。
- 默认显示上下文、候选和取码说明。按住 **F8** 时在同一区域只显示字根键盘，隐藏候选；松开恢复候选。窗口尺寸始终不变，候选和编码状态保留。若 F8 是媒体键，使用 **Fn + F8** 或在系统设置中启用标准功能键。
- Accessibility 读取当前输入框光标前最多 80 个 UTF-16 单元，不使用剪贴板。
- 监听 QWERTY 字母维护最多 4 位待输入编码，结合中文上下文推荐最多 5 个下一字。例如「直 + R」优先显示「接 · RUVG」。
- 退格删除一位；回车、空格、数字选词、Esc、导航键及快捷键清空。四码后继续输入按新字处理。
- `Control + Option + W` 暂停 / 继续，`Control + Option + T` 切换置顶。
- 手动上下文、编码前缀及单字查询。主窗口按「继续」恢复实时读取。
- 菜单栏「五笔」可重新显示窗口、暂停、切换置顶及退出；关闭主窗口即退出。

## 构建

在 Mac 上安装 Xcode Command Line Tools，然后从仓库根目录执行：

```bash
xcode-select --install
swift test --package-path macos
bash macos/build.sh
open dist/macOS/WubiCoach.app
```

生成 `dist/macOS/WubiCoach.app` 和对应架构的 ZIP。同时构建 Apple Silicon 与 Intel：

```bash
bash macos/build.sh --universal
```

Universal 构建会分别编译 arm64 和 x86_64，再用 `lipo` 合并。构建使用本地 ad-hoc 签名，不包含 Developer ID 签名或 Apple 公证；面向其他用户正式分发时需要自行配置这些步骤。Bundle ID 固定为 `org.wubicoach.desktop`。

开发时可在仓库根目录执行 `swift run --package-path macos WubiCoach`，但系统权限更适合授予构建后的固定路径 `.app`。重建或移动应用后，系统可能要求重新授权。

## 首次运行

点击主窗口「权限」，在「系统设置 → 隐私与安全性」中为五笔伴学开启：

1. **辅助功能**：读取其他应用的文本和光标位置。
2. **输入监控**：识别待输入的字母和全局按住快捷键。

授权后重启五笔伴学。在 TextEdit 等标准文本框输入「直」，再按 `r`，应显示「正在输入：R」，首选「接」，完整码 `RUVG`。按住 F8 切换键盘，可看高亮的 R/U/V/G 键位；松开回到候选，窗口尺寸不变。

## 边界与隐私

macOS 版使用按键推测待输入编码，不读取输入法完整候选列表，也不能跨应用调用目标编辑器的 `NSTextInputClient`。自定义上屏规则、鼠标选词或输入模式切换可能使推测短暂不一致，可按回车或 Esc 清空。使用拼音/英文时可关闭「编码提示」。

密码框、安全键盘输入、未开放光标范围或 Accessibility 文本接口的应用不会参与自动预测；界面会说明原因。遇到不支持的应用可用手动上下文。后台读取有超时，失败或失去焦点时清除待输入编码。

普通输入事件原样传递，只有 F8 用于本应用的展开手势，不向目标编辑器传递。暂停后不再处理字母编码，F8 仍可查看字根。上下文、有限的待处理按键和当前编码只在内存中，不写入历史，不上传，不访问剪贴板。

## 测试与验收

```bash
swift test --package-path macos
```

自动测试校验词库数量、编码与字根、共同的 Windows 预测结果、前缀筛选、退格/提交状态，以及按住手势的重复事件和释放。GitHub Actions 还会执行完整原生应用的 Universal 编译。

当前开发主机是 Windows，尚未实际执行 Mac 的编译与授权交互。发布前需在 Mac 验证：

1. 无权限时能显示明确的授权提示。
2. TextEdit 中「直 + R → 接」及退格/选词能正常更新。
3. F8 按下只显示键盘、重复按下不反复切换、释放恢复候选；两种视图互斥，窗口尺寸始终不变，候选和编码保留。
4. 点击候选与切换视图不抢原输入框焦点；手动输入窗口能正常编辑。
5. 密码和安全输入不显示上下文；暂停后清空，恢复后从新输入开始。
6. 关闭主窗口后移除事件监听并退出。

接口参考：[NSPanel](https://developer.apple.com/documentation/appkit/nspanel)、[CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)、[Accessibility 范围读取](https://developer.apple.com/documentation/applicationservices/1461203-axuielementcopyparameterizedattr)。
