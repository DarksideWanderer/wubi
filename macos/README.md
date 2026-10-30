# macOS 版

原生 SwiftUI + AppKit 悬浮窗，最低 macOS 13。共用仓库根目录 `data/`，无需重新下载词库；无第三方 Swift 依赖。

## 功能

- 置顶、跨桌面显示，候选点击保持原应用的输入焦点。
- 默认显示上下文、候选和取码说明。按住 **Control + Option + K（⌃⌥K）** 时在同一区域只显示字根键盘，隐藏候选；松开恢复候选。窗口尺寸始终不变，候选和编码状态保留。松开 K、Control 或 Option 中任一键即恢复候选，无需使用功能键。主窗口默认及最小内容尺寸为 800 × 420，不滚动；左侧九个个人偏好、右侧九个去重后的常规候选和完整字根键盘均可显示。
- Accessibility 读取当前输入框光标前最多 80 个 UTF-16 单元，不使用剪贴板。
- 监听 QWERTY 字母维护最多 4 位待输入编码，结合中文上下文推荐最多 18 个下一字。例如「直 + R」优先显示「接 · RUVG」。
- 未上屏编码支持 `←` / `→` 移动光标并在中间插入，例如 `yt → ← → r` 得到 `yrt`。Delete 退格删除光标前一位，Fn+Delete 前向删除光标后一位；不会因为输入框的辅助功能文本短暂滞后而丢失剩余编码。回车、空格、数字选词、Esc、其他导航键及快捷键清空。四码后继续输入按新字处理。
- `Control + Option + W` 暂停 / 继续，`Control + Option + T` 切换置顶。
- 三个组合键均通过 macOS 系统独占全局热键注册，在 VS Code 等应用前台也优先于其本地快捷键，且不依赖辅助功能或输入监控权限。「帮助」按钮悬停提示显示注册状态；若组合键已被其他程序注册为全局热键，会明确显示冲突。关闭占用程序后可重启本应用重试。
- 手动窗口内置单字拼音查字：直接输入 `shi` / `zhong` / `lv`，无需切换系统输入法；显示全部同音单字，点选预览五笔码和字根，回车或「查看五笔」显示到主窗口。保留「上下文 / 汉字查码」标签；查字后返回其他应用自动继续读取，不会进入持续的手动模式；原本已暂停时保持暂停。
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

应用图标源文件为 `Resources/AppIcon.png`。构建时自动生成包含标准与 Retina 尺寸的 `AppIcon.icns` 并嵌入应用；生成图标时使用的提示词保存在 `Resources/AppIcon.prompt.txt`。

Universal 构建会分别编译 arm64 和 x86_64，再用 `lipo` 合并。本机构建默认使用固定的本地代码签名证书，身份资料存放在被 Git 忽略的 `.signing/` 专用钥匙串中。首次构建自动创建，之后始终复用；缺少部分资料时会停止，不会悄悄生成新证书。请保留并安全备份该目录，勿提交或分发其中的钥匙串和密码。

签名身份绑定本机证书和 Bundle ID，避免构建内容变化导致授权反复失效。从旧 ad-hoc 身份迁移过来需要重新授权一次；之后使用同一身份及应用路径构建。证书不会被设为系统信任根。

可用 `WUBI_SIGN_IDENTITY` 指定已有的 Apple 签名身份，`WUBI_SIGN_KEYCHAIN` 可选。GitHub Actions 默认使用 ad-hoc；本地可用 `WUBI_ADHOC_SIGN=1` 显式选择临时签名，但该模式无法跨版本保留授权。这里的本地签名不包含 Developer ID 或 Apple 公证；面向其他用户正式分发时需要自行配置。Bundle ID 固定为 `org.wubicoach.desktop`。

开发时可在仓库根目录执行 `swift run --package-path macos WubiCoach`，但系统权限更适合授予构建后的固定路径 `.app`。更换签名证书、改用临时签名或移动应用后，系统可能要求重新授权。

## 首次运行

点击主窗口「权限」会打开独立的权限窗口，分别显示辅助功能和输入监控的授权状态。点击「打开辅助功能设置」或「打开输入监控设置」会直接进入对应的系统设置页面，系统不再重复弹出授权提示时也能使用。

在「系统设置 → 隐私与安全性」中为五笔伴学开启：

1. **辅助功能**：读取其他应用的文本和光标位置。
2. **输入监控**：识别待输入的五笔字母；系统全局快捷键不依赖此权限。

若列表中没有本应用，可点击系统设置的「+」添加，通过权限窗口的「在访达中显示本应用」定位当前构建。返回应用会自动检查状态；输入监控若提示重启，请退出后重新打开。

授权后重启五笔伴学。在 TextEdit 等标准文本框输入「直」，再按 `r`，应显示「正在输入：R」，首选「接」，完整码 `RUVG`。按住 Control + Option + K 切换键盘，可看高亮的 R/U/V/G 键位；松开回到候选，窗口尺寸不变。

## 边界与隐私

macOS 版使用按键推测待输入编码，不读取输入法完整候选列表，也不能跨应用调用目标编辑器的 `NSTextInputClient`。自定义上屏规则、鼠标选词或输入模式切换可能使推测短暂不一致，可按回车或 Esc 清空。使用拼音/英文时可关闭「编码提示」。

VS Code 等 Electron 编辑器会收到一次文本接口启用请求；如果仍提示无法访问编辑器，悬浮窗会明确提示并显示「编辑器设置」，可跳转到 `Editor: Accessibility Support` 并设为 `On`。未开放的文本不会当作已经成功读取的空上下文。

密码框、安全键盘输入、未开放光标范围或 Accessibility 文本接口的应用不会参与自动预测；界面会说明原因。遇到不支持的应用可用手动上下文。后台读取有超时，失败或失去焦点时清除待输入编码。

普通输入事件原样传递。Control + Option + K / W / T 由系统全局热键处理，不传给目标应用的本地快捷键。普通字母的监听使用只读事件监听，与系统热键注册独立；未授权辅助功能或输入监控时，字根键盘快捷键仍可使用，但跨应用文字读取和编码推测受限。暂停后不再处理字母编码，Control + Option + K 仍可查看字根。上下文、有限的待处理按键和当前编码只在内存中，不写入历史，不上传，不访问剪贴板。

## 测试与验收

```bash
swift test --package-path macos
```

自动测试校验词库数量、编码与字根、共同的 Windows 预测结果、前缀筛选、编码内光标移动、插入、前后删除、滞后的辅助功能快照与提交状态，按住手势的重复事件和释放，以及全部 426 个拼音音节的完整结果数量、无重复码点与排序哈希。GitHub Actions 还会执行完整原生应用的 Universal 编译。

已在 Apple Silicon Mac 完成原生构建、候选/字根键盘布局渲染及全局热键实测。后续验收项目：

1. 无权限时能显示明确的授权提示。
2. TextEdit 中「直 + R → 接」及退格/选词能正常更新。
3. VS Code 前台按住 Control + Option + K 只显示键盘，不执行 VS Code 的同名本地快捷键；长按不反复切换，先释放 K、Control 或 Option 均恢复候选。未授予读取权限时也能使用；两种视图互斥，窗口尺寸始终不变，候选和编码保留。
4. 点击候选与切换视图不抢原输入框焦点；主窗口不滚动，最小尺寸下两种视图均完整显示；手动输入窗口能正常编辑。
5. 密码和安全输入不显示上下文；暂停后清空，恢复后从新输入开始。
6. 关闭主窗口后移除事件监听并退出。

接口参考：[NSPanel](https://developer.apple.com/documentation/appkit/nspanel)、[CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)、[Accessibility 范围读取](https://developer.apple.com/documentation/applicationservices/1461203-axuielementcopyparameterizedattr)。

签名机制参考：[Apple：Designated Requirements 与跨版本授权](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

## 本机偏好

左侧优先使用 SQLite 中学习的个人偏好，不足九个时按常规联想补齐；右侧显示常规联想排除左侧后的前九个，两侧都遵循五笔前缀筛选。点击候选查看计 4 次，确认上屏计 1 次。自动学习只接受同一输入框中、已观察到编码后的短追加，不记录首次读取、退格、切换输入框或长段粘贴；未观察到预编辑时可能无法学习。单字查询不会计入。

数据库位于 `~/Library/Application Support/org.wubicoach.desktop/preferences.sqlite3`，只记录最多三个前置汉字、下一个字及累计次数，无完整输入历史，不上传。重启或重建应用会保留数据；退出应用后删除该文件可重置。数据库异常时左栏提示并回退到常规联想。Windows 使用相同规则，数据库位于 `%LOCALAPPDATA%\WubiCoach\preferences.sqlite3`。
