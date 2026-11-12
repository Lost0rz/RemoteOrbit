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

### 语音快捷键配置

Control Center 的“按键映射”中选中麦克风键，可新增、录制、重命名、修改或删除具名语音快捷键。菜单栏“语音输入”列出当前配置，每次只选择一个 Active。首次使用会保留左右 Option、Control、Command 六种原有纯修饰键配置；录制的组合键会保存左右修饰键侧别，配置模型支持两个或更多不同类型修饰键组成的组合（无需普通主键），但实际热切换是否被目标输入法接收仍需实机验证。Fn/Globe 尚未通过目标硬件验证，当前不可录制。

修改 Active 需要先完成运行时配置，再保存单一配置快照。如果当前语音键仍按住、语音输出仍在收尾、运行时被锁定或保存回读失败，操作会拒绝并保留原 Active；等待收尾结束后重试。无效或不支持的本地配置会保留原始数据并进入只读兼容模式，不会被自动重置。

RemoteOrbit 不会自动切换 macOS 输入法。组合快捷键作为系统键盘事件发送；输入法是否接受组合键、何时开始/停止接收语音，需要在实际目标输入法中由用户验证。源码测试或事件投递成功不能证明第三方输入法收到事件或语音文本完整。

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

驱动安装会触及 `/Library/Audio/Plug-Ins/HAL` 并可能重载 `coreaudiod`。这些操作需要 macOS 管理员权限，且可能中断当前音频设备与 RemoteOrbit 进程；只读诊断或软件构建不会自动执行安装、权限更改或设备切换。

## 5. 基本验收

安装后至少确认：

- `RemoteOrbit Mic 2ch` 存在；
- RemoteOrbit 能连接 RC003；
- 原有六种纯修饰快捷键在左/右侧按键下均能工作；
- 自定义左/右 Option、Control、Command 组合在目标输入法中的开始与停止行为；
- 重启后配置恢复，设置列表与菜单栏的 Active 一致；
- Active 会话/输出收尾期间的切换和编辑被拒绝，原 Active 保持不变；
- SHORT（释放早于约 300 ms）为 no-op；LONG（达到约 300 ms）开始直接远程语音并产生遥控器音频；
- 松开后语音键在输出收尾完成后释放；快速重复 LONG 时没有卡住或释放另一会话按键的情况；
- RC003 原生 F5 不泄漏给系统，结束/退出后没有合成修饰键残留。
- 退出 RemoteOrbit 后不会遗留应由进程持有的按键 ownership。

软件测试不能替代真实硬件/输入法验收。任何“稳定”“无丢字”“点击及时”等产品结论都必须基于对应的实际运行证据，而不能由源码存在或单元测试单独推出。

## 6. 输入/输出设备

RemoteOrbit 可以协调默认输入/输出设备。当前远程语音目标是 `RemoteOrbit Mic 2ch`；物理输入设备的用户选择属于系统设备配置，不会把本地麦克风重新变成 RC003 麦克风键的产品语义。

如果出现音频设备异常：

1. 先确认 `RemoteOrbit Mic 2ch` 是否存在；
2. 再确认 App/driver/运行进程身份是否与预期版本一致；
3. 确认驱动需要修复后，在具备管理员权限的本机操作环境中重装驱动并重载 CoreAudio；
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
- RemoteOrbit 专属工程与运行安全规则：`AGENTS.md`
- Domain 导航：`docs/DOMAIN_MAP.md`
- 文档分类：`docs/README.md`
- 诊断 ADR：`docs/diagnostics/`
- 历史事故证据：`docs/incidents/`

