# RemoteOrbit v0.2.11

## 语音输入恢复与连续触发稳定性

- 从已验证的 `0.2.10` 基线重新建立语音恢复线，没有合并失败的 voice-session lifecycle 实验。
- 强化 Option 触发所有权和 stale callback 防护，保持物理 Option 为主路径。
- 将快速重按防抖与音频尾部排空解耦，移除旧的约 900ms 固定锁定。
- 当上一轮语音尾部仍在处理时，新一轮真实按键不再被直接丢弃，而是延迟接管；上一轮 teardown 完成后再安全启动下一轮。
- 保持关键启动顺序：先请求 BLE 语音链路，再准备远程音频路由，避免增加首字延迟。
- 在 `AUDIO_STOP` 排空窗口内忽略迟到的 `AUDIO_START`，防止旧流取消尾部 drain，并保留 `DRAIN_FINISH / AUDIO_SUMMARY / AUDIO_STOP drained` 完整闭环。
- 真实硬件日志中，deferred rapid handoff 路径已观察到 9/9 完整进入 `BLE_START_REQUEST → MIC_OPEN_TX → AUDIO_FIRST → OPTION_GATE_RELEASE`，未观察到旧连接 disconnect 清除新一轮语音的 race。

## 已知边界

- 极端快速连续触发时，豆包输入法自身可能在上一轮识别尚未完成时吞掉下一次触发；该现象可脱离 RemoteOrbit 独立复现，因此不再通过增加 RemoteOrbit 延迟来规避。
- rapid session 中曾观察到极少量满幅 PCM 样本（约 0.007%–0.014%），目前没有可听失真证据，不调整增益或解码器。

## 验证

- Swift 单元测试：87 项通过，0 失败。
- 协议自测：3 项通过，0 失败。
- Release build：通过。
- `git diff --check`：通过。
- App：Universal 2，RemoteOrbit 0.2.11（Build 40）。
- 安装包继续使用本地 ad-hoc 签名；首次运行需按 macOS 提示授予蓝牙、麦克风、辅助功能和输入监控权限。
