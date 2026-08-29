# VoiceRemoteBridge / Voice Remote Bridge

把小米蓝牙语音遥控器 2 Pro 变成 macOS 上的 Voice Coding 麦克风：

- 短按语音键：自动选择可用的本机物理麦克风（内置或外接）。
- 长按语音键：调用遥控器的 ATVV 蓝牙麦克风。
- 向豆包输入法暴露可识别的 `VoiceRemote Mic 2ch` 输入设备。

## 当前版本：0.1.0（独立开发基线）

这是独立维护的开发基线，后续功能和发布节奏均由本项目单独维护。

当前 `main` 包含按 App 的按键模板、可重复触发策略、
FloatTabs/Codex/Ghostty 等应用适配，以及更完整的按键注入和语音音频切换逻辑。
这些内容尚未单独发布新版本，发布说明以代码和 `SETUP_NOTES.md` 为准。

本机实际安装过的配置、豆包设置、Redmi Air/其他型号兼容性边界和常见排障步骤，见
[SETUP_NOTES.md](SETUP_NOTES.md)。

本次 Release 暂时只发布源码，没有预编译 App、PKG、DMG 或一键安装包。项目已在
Xiaomi Bluetooth Voice Remote 2 Pro、Apple Silicon Mac 和豆包输入法上完成连续长按、
短按和音源往返切换验证。有动手能力的用户可以按下文从源码安装，也可以让能够执行
终端命令的 AI Agent 协助安装。

### 当前功能

- 修复 ATVV `AUDIO_SYNC` 在 `AUDIO_START` 前后到达时的解码状态问题。
- 增加协议自测，覆盖连续音频流和同步状态隔离。
- 增加菜单栏状态、登录时自动启动、日志与调试录音控制。
- 日志和调试录音默认关闭，可查看占用、打开目录或清空。
- 改进长按语音键的 Option 按键行为和遥控器音频诊断。
- 自定义组合快捷键改为完整发送修饰键按下、目标键按下/松开和修饰键释放，兼容更多全局快捷键监听器。
- 改进兼容模式下遥控器原生 Home/方向键的事件压制，并修复首次打开快捷键录制窗口无内容的问题。
- 对带 Command 的自定义快捷键增加 System Events 路径，兼容 `KeyboardShortcuts`/Carbon 全局热键。

## 使用前准备

目前的源码安装方式需要：

1. macOS 13 或更高版本；当前主要在 Apple Silicon Mac 上验证。
2. Xcode Command Line Tools：`xcode-select --install`。
3. 已安装 Xcode Command Line Tools，并能运行 `xcodebuild`。驱动脚本会固定下载
   BlackHole 0.7.1 源码，构建独立的 `VoiceRemoteAudio.driver`，不会依赖或修改原 BlackHole。
4. 安装 HAL 驱动时需要管理员密码。
5. 首次启动后，由用户手动授予蓝牙、麦克风、辅助功能和输入监控权限。

> AI Agent 可以执行检查、构建和安装命令，但不能代替用户输入管理员密码，也不能绕过
> macOS 的隐私授权界面。

## 从源码安装

### 有动手能力的用户

```bash
git clone https://github.com/Lost0rz/VoiceRemoteBridge.git
cd VoiceRemoteBridge

# 协议回归自测：应输出三行 PASS
./voice-remote-bridge/run-self-tests.sh

# 从 BlackHole 0.7.1 源码生成 VoiceRemoteAudio HAL 驱动
./voice-remote-audio-driver/build-driver.sh
sudo ./voice-remote-audio-driver/install-driver.sh

# 构建并安装菜单栏 App
./voice-remote-bridge/package-app.sh
./voice-remote-bridge/install-app.sh

# 启动
./LaunchVoiceRemoteBridge.command
```

驱动安装会备份已有的 `VoiceRemoteAudio.driver`，然后提示重启 macOS，让 CoreAudio
重新加载实际标记为 USB 的音频设备。

### 让 AI Agent 协助安装

可以把下面这段任务直接交给能够操作终端的 Agent：

```text
请在我的 Mac 上从个人仓库安装 VoiceRemoteBridge：
1. 检查 macOS、Xcode Command Line Tools，以及
   /Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver。
2. 克隆 https://github.com/Lost0rz/VoiceRemoteBridge.git。
3. 运行 voice-remote-bridge/run-self-tests.sh，必须全部 PASS。
4. 运行 voice-remote-audio-driver/build-driver.sh。
5. 在我确认后，用管理员权限运行 install-driver.sh。
6. 运行 voice-remote-bridge/package-app.sh 和 install-app.sh。
7. 启动 VoiceRemoteBridge.app，逐项告诉我需要手动授予的 macOS 权限。
不要绕过 Gatekeeper，不要替我修改系统安全策略。
```

安装成功的基本判据：

- 自测输出三行 `PASS`。
- 驱动构建输出 `Built: .../VoiceRemoteAudio.driver`。
- App 构建输出 `Built: .../VoiceRemoteBridge.app`。
- “音频 MIDI 设置”或音频输入设备中出现 `VoiceRemote Mic 2ch`。
- 菜单栏出现 Voice Remote Bridge 状态图标。

## 启动与退出

已安装的应用位于：

```text
~/Applications/VoiceRemoteBridge.app
```

双击应用或运行 `LaunchVoiceRemoteBridge.command` 即可启动。它是菜单栏应用，不显示 Dock 图标；
点击菜单栏的麦克风图标可查看状态或退出。菜单中的“登录时自动启动”可以控制登录后
自动启动，不需要管理员权限。

## 日志与调试录音

默认不写日志，也不保存录音。菜单中可以分别开启，并提供占用大小、刷新、打开文件夹
和清空功能。

- 日志：`~/Library/Logs/VoiceRemoteBridge/VoiceRemoteBridge.log`
- 录音：`~/Library/Application Support/VoiceRemoteBridge/Recordings/`

日志最大为 5 MB，到达上限后自动截断。调试录音会同时保存 16 kHz WAV 和原始 ATVV
数据，仅在用户手动开启后生效。

## 当前限制

- 这是源码预览版，App 和驱动目前使用本地 ad-hoc 签名，尚未提供签名和 Apple 公证的安装包。
- 驱动构建脚本会固定获取 BlackHole 0.7.1 源码并生成独立的 `VoiceRemoteAudio.driver`；遥控器型号兼容性仍以已验证设备为准。
- 当前明确验证的硬件是 Xiaomi Bluetooth Voice Remote 2 Pro；其他型号和固件不保证兼容。
- macOS 隐私权限必须由用户本人手动授予。

## 下一步计划

等维护者有时间后，会逐步推进：

- 完善 GPL v3 对应源码和许可证分发。
- 提供 App、驱动和登录启动项的统一卸载方法。
- 增加 Developer ID 签名、Hardened Runtime 和 Apple 公证。
- 评估统一 PKG、DMG 和 `.command` 安装体验。
- 增加 GitHub Actions、更多自动测试和干净 Mac 安装验证。

当前 `0.1.0` 是供开发者、动手能力较强的用户和 AI Agent 使用的独立源码基线；正式一键安装包
会在后续版本中提供，感谢耐心等待。

## 目录

- `voice-remote-bridge/`：Swift 菜单栏应用、BLE/ATVV 解码和音频路由。
- `voice-remote-audio-driver/`：生成 `VoiceRemote Mic 2ch` HAL 驱动的验证构建及安装脚本。

## 许可证

应用源码遵循 [MIT License](LICENSE)。当前驱动基于 BlackHole 0.7.1，遵循 GNU GPL v3。
第三方项目、许可证和归属信息见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
