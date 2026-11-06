# RemoteOrbit 安装与排障

本文件只维护**当前可复现的安装、验证和排障入口**。旧任务进度、旧分支/PR、历史提交清单和已经退役的业务设计不在这里维护；需要追溯时使用 Git 历史和 `docs/incidents/`。

## 1. 基线与设备边界

当前 `main` 的源码版本元数据为 `0.2.15 (Build 44)`，以 `remote-orbit/Packaging/Info.plist` 为准。该值描述当前源码，不等同于“本机已安装版本”或“最新已发布 Release”；安装/运行身份必须在对应机器上单独验证。

已接受的主要设备路径是：

- Apple Silicon Mac，macOS 13+；
- Xiaomi Bluetooth Voice Remote 2 Pro / RC003；
- 豆包 macOS 输入法；
- `RemoteOrbit Mic 2ch` 虚拟输入设备。

其他遥控器、Redmi 设备或不同 ATVV/HID 实现不能自动视为兼容。

## 2. 当前语音工作方式

RC003 麦克风键的当前合同固定为 LONG-only remote voice：

### SHORT

在约 300 ms hold boundary 前释放：

- 判定为 SHORT；
- 不触发输入法；
- 不打开本地/外接麦克风；
- 不建立 Persistent session；
- 不进入 Receiver A/B 路由；
- 不显示语音/readiness HUD。

### LONG

跨过约 300 ms boundary 后：

1. 手势进入直接远程语音生命周期；
2. RemoteOrbit 完成/复用 ATVV transport，并在允许的边界启动远程 capture；
3. 解码后的遥控器 PCM 进入 `RemoteOrbit Mic 2ch`；
4. 输入法触发、首帧准备、Option ownership、release 与 output drain 由当前运行时协调；
5. 松开后完成远程输入停止和现有 drain/close 流程。

Persistent、双 Receiver、Receiver B、本地麦克风短按以及旧 generic-short 业务语义均已退役。历史 release note 或 incident 中出现这些词，只代表当时版本/现场。

## 3. 首次安装

优先使用发布 DMG：

1. 将 `RemoteOrbit.app` 拖入 `/Applications`。
2. 启动 `/Applications/RemoteOrbit.app`。
3. 按 macOS 提示授予：
   - 蓝牙；
   - 辅助功能；
   - 输入监控；
   - 仅在某些语义快捷键需要时授予 Automation / System Events。
4. 打开设置，检查音频组件状态；缺失时使用“重新安装音频组件”。
5. 在“声音”或“音频 MIDI 设置”中确认 `RemoteOrbit Mic 2ch` 已出现。

遥控器语音走 BLE ATVV；当前麦克风键产品路径不依赖本机麦克风权限。

## 4. 从源码安装

```bash
git clone https://github.com/Lost0rz/RemoteOrbit.git
cd RemoteOrbit

./remote-orbit/run-self-tests.sh
./remote-orbit-audio-driver/build-driver.sh
sudo ./remote-orbit-audio-driver/install-driver.sh
./remote-orbit/package-app.sh
./remote-orbit/install-app.sh
open /Applications/RemoteOrbit.app
```

驱动安装会触及 `/Library/Audio/Plug-Ins/HAL` 并可能重载 `coreaudiod`。只有明确授权的安装/修复任务才能执行这些动作。普通源码审计、文档任务、诊断读取或 CI 都不授权修改 HAL、TCC、默认设备或运行中的 App。

## 5. 基本验收

安装后至少确认：

- `RemoteOrbit Mic 2ch` 存在；
- RemoteOrbit 能连接 RC003；
- SHORT 为 no-op；
- LONG 能触发直接远程语音并产生遥控器音频；
- 快速重复 LONG 不产生明显的 stuck trigger / 永久占用；
- 退出 RemoteOrbit 后不会遗留应由进程持有的按键 ownership。

软件测试不能替代真实硬件/输入法验收。任何“稳定”“无丢字”“点击及时”等产品结论都必须基于对应的实际运行证据，而不能由源码存在或单元测试单独推出。

## 6. 输入/输出设备

RemoteOrbit 可以协调默认输入/输出设备。当前远程语音目标是 `RemoteOrbit Mic 2ch`；物理输入设备的用户选择属于系统设备配置，不会把本地麦克风重新变成 RC003 麦克风键的产品语义。

如果出现音频设备异常：

1. 先确认 `RemoteOrbit Mic 2ch` 是否存在；
2. 再确认 App/driver/运行进程身份是否与预期版本一致；
3. 必要时在授权任务中重装驱动并重载 CoreAudio；
4. 只有驱动重载后设备仍不可见时，才把重启 macOS 作为最后恢复手段。

## 7. 权限排查

RemoteOrbit 的产品进程权限必须用产品进程自身身份判断。Terminal、脚本宿主或其他辅助进程拥有 Accessibility/Input Monitoring 权限，不代表 `/Applications/RemoteOrbit.app` 拥有同样权限。

遇到“按键无响应”“映射无效”“语音触发没有动作”时，按顺序确认：

- 当前运行的 Bundle/可执行文件是否真的是目标 RemoteOrbit；
- 蓝牙是否允许；
- Input Monitoring 是否允许；
- Accessibility 是否允许；
- 需要 System Events 的快捷键是否已授予 Automation；
- RC003 HID/ATVV 是否同时在线。

不要为了排障直接重置 TCC；TCC 变更属于单独的有副作用动作。

## 8. 日志、录音和长期诊断

普通日志与调试录音由用户显式控制。长期 machine-readable 诊断由 `DiagnosticAuthority` 统一拥有；当前有效架构见 `docs/diagnostics/ADR-0001..0003`。

常用只读命令：

```bash
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics status
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics verify
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics query --limit 100
```

需要导出诊断包时：

```text
RemoteOrbit diagnostics export --output <directory> --host-role TEST_HOST \
  --since-unix-ms <start> --until-unix-ms <end>
```

导出是只读证据工作流；它不能安装、修复、重置、修改设置或改变运行时行为。

## 9. 常见故障分类

### A. LONG 没有波纹 / 没有远程语音

先区分：

- HID gesture 是否进入 LONG；
- BLE/ATVV transport 是否准备成功；
- `micOpen` / AUDIO_START 是否实际发生；
- 第一帧远程 PCM 是否到达；
- `RemoteOrbit Mic 2ch` 是否有供给；
- 输入法触发/接收侧是否处于可消费状态。

不要把“输入法最终没文字”直接等同于 BLE、AudioPipe 或 Option 的根因。

### B. 快速重复 LONG 卡住或第二次不响应

重点看：

- physical down/up ownership；
- repress/grace 边界；
- output drain；
- transport reuse / close ordering；
- receiver readiness；
- 是否存在真实 drop、delivery deficit 或 lifecycle order anomaly。

优先导出 machine-readable diagnostic evidence，再做最小 corrective；不要先叠加 speculative fix。

### C. 有音频但文字丢失

分别检查：

- BLE notification / decode；
- AudioPipe supply / render；
- active 与 tail deficit；
- main-queue lag；
- 输入法接收侧证据。

RemoteOrbit 的本地探针只能证明本地边界，不能从本地日志单独证明输入法文字层的 root cause。

## 10. 文档入口

- 产品/仓库入口：`README.md`
- 工程规则及已接受控制模式：`AGENTS.md`
- 当前授权任务：从 GitHub 读取被批准的 Issue，并核对仓库、Issue、`TASK_ID`、`SPEC_REVISION` 与规范 SHA-256；审批和执行回执保存在同一 Issue 的评论中。
- PR、CI、提交与发布状态：以 GitHub 对应记录为准。
- Domain 导航：`docs/DOMAIN_MAP.md`
- 文档分类：`docs/README.md`
- 诊断 ADR：`docs/diagnostics/`
- 历史事故证据：`docs/incidents/`

旧任务计划、旧 corrective/audit 设计以及已退役 Persistent / dual-receiver 等业务方案不再作为当前文档保留；如需追溯，使用 Git 历史。
