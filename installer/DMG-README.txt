Voice Remote Bridge 安装说明

1. 双击 `VoiceRemoteBridge.pkg`，使用 macOS Installer 完成安装。
2. 按 Installer 提示输入管理员密码。App 和独立音频驱动已经包含在这个 DMG 内，不需要安装 Xcode、Homebrew、命令行工具，也不需要再次下载 BlackHole。
3. 安装器会自动配置 VoiceRemoteAudio.driver；安装完成后请重启 Mac。
4. 重启后打开 `/Applications/VoiceRemoteBridge.app`。
5. 首次启动时，按 macOS 提示授予蓝牙、麦克风、辅助功能和输入监控权限；然后在“声音”或“音频 MIDI 设置”中确认 VoiceRemote Mic 2ch 已出现。

如果安装完成后暂时没有重启，请在测试遥控器前手动重启 Mac。安装器会把被替换的旧 App/驱动备份到：
~/Library/Application Support/VoiceRemoteBridge/Backups/

这个安装包不连接原始项目，也不会修改原 BlackHole 驱动；它只安装本项目自己的 VoiceRemoteBridge.app 和 VoiceRemoteAudio.driver。
