# RemoteOrbit

把小米蓝牙语音遥控器 2 Pro 变成 macOS 上的 Voice Coding 麦克风：

- 短按语音键：忽略，不调用本机或外接麦克风。
- 长按语音键：调用遥控器的 ATVV 蓝牙麦克风。
- 向豆包输入法暴露可识别的 `RemoteOrbit Mic 2ch` 输入设备。

## 当前版本：0.2.11（RemoteOrbit 正式基线，Build 40）

这是独立维护的开发基线，后续功能和发布节奏均由本项目单独维护。

当前 `main` 包含按 App 的按键模板、可重复触发策略、
FloatTabs/Codex/Ghostty/Obsidian 等应用适配，以及按键注入、语音焦点和音频切换逻辑。
当前基线以代码和 `SETUP_NOTES.md` 为准。

本机实际安装过的配置、豆包设置、Redmi Air/其他型号兼容性边界和常见排障步骤，见
[SETUP_NOTES.md](SETUP_NOTES.md)。

项目已在 Xiaomi Bluetooth Voice Remote 2 Pro、Apple Silicon Mac 和豆包输入法上完成
连续长按、短按忽略和遥控器音频链路验证。发布 DMG 会把 App 和独立音频驱动一起带上，普通用户
不需要准备开发环境；维护者也可以用仓库中的脚本重新生成 DMG。

### 当前功能

- 修复 ATVV `AUDIO_SYNC` 在 `AUDIO_START` 前后到达时的解码状态问题。
- 增加协议自测，覆盖连续音频流和同步状态隔离。
- 增加菜单栏状态、登录时自动启动、日志与调试录音控制。
- 日志和调试录音默认关闭，可查看占用、打开目录或清空。
- 改进长按语音键的 Option 按键行为和遥控器音频诊断。
- 自定义组合快捷键改为完整发送修饰键按下、目标键按下/松开和修饰键释放，兼容更多全局快捷键监听器。
- 改进兼容模式下遥控器原生 Home/方向键的事件压制，并修复首次打开快捷键录制窗口无内容的问题。
- 对带 Command 的自定义快捷键增加 System Events 路径，兼容 `KeyboardShortcuts`/Carbon 全局热键。
- 增加语音焦点事务保护，避免 FloatTabs/Codex 在第一次输入时因焦点回调过期而丢字。
- 增加“刷新当前页面”语义预设：FloatTabs 走直连命令，其他浏览器走 `Command-R`。
- 兼容 HID 监控模式下的遥控器电源原生事件，避免页面刷新映射同时触发 macOS 关机提示。
- 增加菜单栏“音频设备”子菜单：可分别切换系统默认输入和输出设备；输入设备选择会保留，输出设备立即生效。
- 新安装自动提供 Codex 与 FloatTabs 的系统默认模板，并锁定当前确认过的物理按键布局；已有自定义模板只在保持旧内置快照时迁移。
- 增加蓝牙 ATVV 语音链路的断连重连、退避和重新握手，HID 重连不会再让遥控器麦克风永久离线。
- 丰富 Obsidian 标准模板：增加编辑器/分栏焦点、向右分屏、堆叠标签、大纲和书签等语义动作。
- Obsidian 动作选择器按“焦点与布局、标签与窗口、笔记与编辑、搜索与命令、视图与属性、设置”分类展示；命令通过 Obsidian 命令面板执行，不依赖用户重新录制快捷键。
- 更新 Obsidian 默认模板：上下键按阅读方向滚屏，左右键切换左右分栏焦点，返回键删除，主页键快速切换文件，菜单键打开命令面板，TV 键新建笔记，音量键切换标签。

## RemoteOrbit Control Center

菜单栏中的“打开控制中心…”现在是本项目自己的统一设置入口，包含：

- **概览**：查看按钮数量、应用 Profile 数量和当前滚动速度。
- **按键映射**：先选“默认 · 所有 App”或某个 App，再编辑具体按钮；“系统控制”中可把“检查当前快捷映射”绑定到单击、双击或长按。
- **应用配置**：为不同 App 建立独立 Profile，并明确选择 Active Profile。
- **诊断与日志**：集中打开或清理日志、调试录音，并查看本机配置摘要。
- **关于**：展示独立产品名、Bundle ID、版本和音频设备信息。

映射规则固定为“默认映射 → App Profile → 单按钮始终使用默认”。这套名称和界面只属于
RemoteOrbit，不复用原项目的设置入口或配置界面。

### 音频设备切换

点击菜单栏图标后，一级菜单直接提供“输入设备”和“输出设备”，可以分别选择系统默认输入和输出：

- 输入设备会列出 `RemoteOrbit Mic 2ch（遥控器/自动）`、内置麦克风和当前可用的外接麦克风。
- 输出设备会列出扬声器、显示器音频和耳机等真实输出设备，并自动隐藏 BlackHole、RemoteOrbit
  等虚拟回环设备，避免误选。
- 默认输入仍是 RemoteOrbit；当前语音键采用仅长按遥控器麦克风的工作方式，短按不会调用本机麦克风。
- 如果改选物理麦克风，macOS 会直接把它作为系统默认输入；需要恢复遥控器语音链路时，重新选择
  `RemoteOrbit Mic 2ch（遥控器/自动）`。
- 输出设备切换只修改 macOS 系统默认输出，不会重启 App；菜单每次打开时会刷新设备列表。

## DMG 安装（推荐）

发布 DMG 顶层只包含可直接拖拽的 `RemoteOrbit.app` 和 `Applications` 快捷入口；App 内含预先构建好的
`RemoteOrbitAudio.driver`。最终用户不需要安装 Xcode、Homebrew、
Xcode Command Line Tools，也不需要再次联网下载 BlackHole 或其他构建依赖。

推荐安装流程：

1. 将 DMG 顶层的 `RemoteOrbit.app` 拖到旁边的 `Applications` 快捷入口。
2. 从 `/Applications/RemoteOrbit.app` 启动，按 macOS 提示授予蓝牙、麦克风、辅助功能和输入监控权限。
3. 打开“设置与诊断”。如果虚拟音频组件未检测到，点击“重新安装音频组件”并在管理员对话框中授权。
4. 应用会自动重新加载 CoreAudio，通常不需要重启 Mac；在“声音”或“音频 MIDI 设置”中确认
   `RemoteOrbit Mic 2ch` 已出现并作为输入设备。

音频驱动补装会把被替换的旧 `MiRemoteVoice.driver` 和旧 `BlackHole2ch.driver`
备份到 `~/Library/Application Support/RemoteOrbit/Backups/`，以免旧输入设备继续抢占系统默认输入。
系统自带的 `ParrotAudioPlugin.driver` 和其他未列出的音频驱动不会被处理。

## 从源码构建

只有维护者从源码生成 DMG 时需要准备：

1. macOS 13 或更高版本；当前主要在 Apple Silicon Mac 上验证。
2. 已安装 Xcode Command Line Tools，并能运行 `xcodebuild`。驱动脚本会固定下载
   BlackHole 0.7.1 源码，构建独立的 `RemoteOrbitAudio.driver`，不会依赖或修改原 BlackHole。
3. 生成 DMG 时会下载 BlackHole 0.7.1 源码并构建独立驱动；这些步骤发生在发布机上，
   不会出现在最终用户的首次安装过程中。

> AI Agent 可以执行检查、构建和安装命令，但不能代替用户输入管理员密码，也不能绕过
> macOS 的隐私授权界面。

## 从源码安装（开发者备用流程）

### 有动手能力的用户

```bash
git clone https://github.com/Lost0rz/RemoteOrbit.git
cd RemoteOrbit

# 协议回归自测：应输出三行 PASS
./remote-orbit/run-self-tests.sh

# 从 BlackHole 0.7.1 源码生成 RemoteOrbitAudio HAL 驱动
./remote-orbit-audio-driver/build-driver.sh
sudo ./remote-orbit-audio-driver/install-driver.sh

# 构建并安装菜单栏 App
./remote-orbit/package-app.sh
./remote-orbit/install-app.sh

# 启动
./LaunchRemoteOrbit.command
```

驱动安装会备份已有的 `RemoteOrbitAudio.driver`，然后重启 `coreaudiod`，让 CoreAudio
重新加载实际标记为 USB 的音频设备。只有设备在重载后仍未出现时，才需要把重启 macOS
作为最后的恢复步骤。

### 让 AI Agent 协助安装

可以把下面这段任务直接交给能够操作终端的 Agent：

```text
请在我的 Mac 上从个人仓库安装 RemoteOrbit：
1. 检查 macOS、Xcode Command Line Tools，以及
   /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver。
2. 克隆 https://github.com/Lost0rz/RemoteOrbit.git。
3. 运行 remote-orbit/run-self-tests.sh，必须全部 PASS。
4. 运行 remote-orbit-audio-driver/build-driver.sh。
5. 在我确认后，用管理员权限运行 install-driver.sh。
6. 运行 remote-orbit/package-app.sh 和 install-app.sh。
7. 启动 RemoteOrbit.app，逐项告诉我需要手动授予的 macOS 权限。
不要绕过 Gatekeeper，不要替我修改系统安全策略。
```

安装成功的基本判据：

- 自测输出三行 `PASS`。
- 驱动构建输出 `Built: .../RemoteOrbitAudio.driver`。
- App 构建输出 `Built: .../RemoteOrbit.app`。
- “音频 MIDI 设置”或音频输入设备中出现 `RemoteOrbit Mic 2ch`。
- 菜单栏出现 RemoteOrbit 状态图标。

## 启动与退出

DMG 安装的应用位于：

```text
/Applications/RemoteOrbit.app
```

双击应用或运行 `LaunchRemoteOrbit.command` 即可启动。源码安装脚本也默认使用
`/Applications/RemoteOrbit.app`。它是菜单栏应用，不显示 Dock 图标；
点击菜单栏的麦克风图标可查看状态或退出。菜单中的“登录时自动启动”可以控制登录后
自动启动，不需要管理员权限。

## 日志与调试录音

默认不写日志，也不保存录音。菜单中可以分别开启，并提供占用大小、刷新、打开文件夹
和清空功能。

- 日志：`~/Library/Logs/RemoteOrbit/RemoteOrbit.log`
- 录音：`~/Library/Application Support/RemoteOrbit/Recordings/`

日志最大为 5 MB，到达上限后自动截断。调试录音会同时保存 16 kHz WAV 和原始 ATVV
数据，仅在用户手动开启后生效。

## 当前限制

- App 和驱动目前使用本地 ad-hoc 签名，DMG 尚未提供 Developer ID 签名和 Apple 公证。
- 驱动构建脚本会固定获取 BlackHole 0.7.1 源码并生成独立的 `RemoteOrbitAudio.driver`；遥控器型号兼容性仍以已验证设备为准。
- 当前明确验证的硬件是 Xiaomi Bluetooth Voice Remote 2 Pro；其他型号和固件不保证兼容。
- macOS 隐私权限必须由用户本人手动授予。

## 生成发布 DMG

在发布机上执行：

```bash
./package-dmg.sh
```

该命令会下载固定版本的 BlackHole 源码、构建独立驱动、打包 App，并生成
`dist/RemoteOrbit-0.2.11.dmg`。如果已经有本地构建好的驱动，可以使用：

```bash
./package-dmg.sh --reuse-driver
```

后续计划包括：

- 完善 GPL v3 对应源码和许可证分发。
- 提供 App、驱动和登录启动项的统一卸载方法。
- 提供 Developer ID 签名、Hardened Runtime 和 Apple 公证的正式安装包。
- 增加 GitHub Actions、更多自动测试和干净 Mac 安装验证。

当前 `0.2.11` 是 RemoteOrbit 的正式独立产品基线；安装包使用本地 ad-hoc 签名，仍需用户按
macOS 提示授予蓝牙、麦克风、辅助功能和输入监控权限。Developer ID 签名和 Apple 公证仍是后续
发布工作，不影响本机测试和安装。

## 目录

- `remote-orbit/`：Swift 菜单栏应用、BLE/ATVV 解码和音频路由。
- `remote-orbit-audio-driver/`：生成 `RemoteOrbit Mic 2ch` HAL 驱动的构建及安装脚本。
- `installer/`：DMG 安装器和首次安装配置逻辑。
- `package-dmg.sh`：在发布机上生成包含 App 与驱动的 DMG。

## 许可证

应用源码遵循 [MIT License](LICENSE)。当前驱动基于 BlackHole 0.7.1，遵循 GNU GPL v3。
第三方项目、许可证和归属信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
