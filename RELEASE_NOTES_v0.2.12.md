# RemoteOrbit v0.2.12

## 语音按键与输入链路稳定性

* 将小米遥控器 HID ownership 固定为 monitored / non-seize 模式，使 macOS 可以继续接收设备级 `hidutil` 映射产生的真实 Option 事件，同时由 RemoteOrbit 负责必要的事件抑制和语音手势协调。
* 保持物理 / 系统映射的左 Option 为正常语音触发路径；synthetic Option 不作为正常 owner，仅保留必要的异常平衡兜底。
* 修复“单击已禁用”时绕过 300ms short-vs-long classifier 的问题。禁用单击后，短按仍被正确判为 SHORT 并丢弃；长按仍在确认后进入遥控器语音路径。
* 将 ATVV transport preparation 与真正的 voice activation 分离。pending 阶段只允许预连接，不允许 `micOpen`、`AUDIO_START`、streaming 或 Option-down；只有确认 LONG 后才允许启动真正的语音会话。
* 保留第一帧远程 PCM 到达后才释放 Option-down 的顺序，避免外部语音窗口先于遥控器音频就绪。
* 增加输出排空屏障：遥控器停止发送后，已经进入 RemoteOrbit 输出队列的 PCM 必须播放完成后才释放最终 Option-up，降低句尾被截断的风险。
* 保留原有快速重按、BLE `AUDIO_STOP` drain、20x 远程音频增益和 FloatTabs semantic voice-focus 集成。

## 验证

### 自动化

* Swift 单元测试：108 项通过，0 失败。
* 协议自测：3/3 通过。
* Release build：通过。
* `git diff --check`：通过。

### 真实硬件

针对 transport-only prewarm 边界：

* disabled-short：12/12 正确判定为 SHORT。
* transport preparation：12/12。
* `micOpen`：0/12。
* `AUDIO_START`：0/12。
* streaming：0/12。
* Option-down：0/12。
* short release 后 transport 关闭并恢复 HID-only：12/12。

针对 long promotion：

* 长按语音：6/6 通过。
* `MIC_OPEN_TX`：6/6，每 session 恰好一次。
* `AUDIO_START`：6/6。
* `AUDIO_FIRST`：6/6。
* synthetic normal owner：0。
* stuck Option：0。

prewarm 的精确延迟收益由于没有同条件 historical baseline，目前保持 `INCONCLUSIVE`，不作为发布阻塞项。

## 版本

* RemoteOrbit 0.2.12
* Build 41
* Universal 2：Apple Silicon + Intel
* 安装包继续使用本地 ad-hoc 签名。
* 首次运行仍需按 macOS 提示授予蓝牙、麦克风、辅助功能和输入监控权限。
