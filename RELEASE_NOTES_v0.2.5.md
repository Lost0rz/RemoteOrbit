# RemoteOrbit v0.2.5

正式 RemoteOrbit 基线，Build 10。

## 本次包含

- Codex 与 FloatTabs 内置系统默认模板，使用当前确认的遥控器按键布局。
- Codex：上下键滚屏、左右键编辑移动、音量上下切换上/下一个对话、菜单键显示/隐藏侧边栏。
- FloatTabs：上下键滚屏、左键切换输入框/网页焦点、右键粘贴、音量上下切换标签、主页键显示/隐藏。
- 内置模板升级时只迁移未被用户修改的旧快照，不覆盖自定义按键。
- 蓝牙 ATVV 语音链路断连后自动退避重连并重新握手，恢复后自动恢复遥控器麦克风。
- 菜单栏一级提供输入设备和输出设备切换，输入选择持久化并过滤虚拟回环输出设备。
- 保留语音焦点首击保护、按键边沿防抖、滚动释放保护和原生电源/音量事件压制。

## 验证

- RemoteOrbit Swift 测试：27 项通过，0 失败。
- DMG：包含 RemoteOrbit.app 和 RemoteOrbitAudio.driver；安装后通常无需重启 macOS。

## 兼容范围

当前确认硬件为 Xiaomi Bluetooth Voice Remote 2 Pro；其他 Redmi 设备仍需单独验证 ATVV 服务、HID 报告和 VID/PID。
