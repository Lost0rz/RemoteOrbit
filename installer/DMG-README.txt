RemoteOrbit 安装说明

推荐方式：将 DMG 顶层的 `RemoteOrbit.app` 拖到旁边的“Applications”快捷入口。

1. 拖拽完成后，从 `/Applications/RemoteOrbit.app` 启动 RemoteOrbit。
2. 首次启动时，按 macOS 提示授予蓝牙、麦克风、辅助功能和输入监控权限。
3. 打开“设置与诊断”。如果“虚拟音频组件”显示未检测到，点击“重新安装音频组件”，在 macOS 管理员对话框中授权。
4. 应用会自动重新加载 CoreAudio，通常不需要重启 Mac；然后在“声音”或“音频 MIDI 设置”中确认 `RemoteOrbit Mic 2ch` 已出现。

如果 CoreAudio 重载后设备仍未出现，再重启 Mac 作为最后的恢复步骤。音频驱动补装会把被替换的旧驱动备份到：
~/Library/Application Support/RemoteOrbit/Backups/

这个 DMG 只提供 RemoteOrbit.app 的拖拽安装，不再同时提供第二套安装器。
音频驱动随 App 一起封装；首次检测不到时，从“设置与诊断”中按需授权补装。
它不连接原始项目，并会把旧版 MiRemoteVoice/BlackHole2ch 输入驱动移入备份目录，
避免它们继续抢占默认输入。
