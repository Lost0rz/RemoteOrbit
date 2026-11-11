# RemoteOrbit

RemoteOrbit 把 Xiaomi Bluetooth Voice Remote 2 Pro 的蓝牙 ATVV 语音链路接入 macOS，并通过 `RemoteOrbit Mic 2ch` 向豆包等输入法提供远程麦克风音频，同时提供遥控器按键映射、App Profile、诊断与安装能力。

## 当前源码基线

- `main` 源码版本元数据：`0.2.15` / Build `44`。
- 版本元数据来自 `remote-orbit/Packaging/Info.plist`；已发布版本以 GitHub Releases 为准，不在本文件复制“最新 Release”状态。
- `AGENTS.md` 记录 RemoteOrbit 专属的产品行为、硬件边界与运行安全约束。
- 项目结构与源码/测试入口见 [`docs/DOMAIN_MAP.md`](docs/DOMAIN_MAP.md)。

## 语音键合同

RC003 麦克风键只有一种用户可见语音模式：

- **SHORT**：在约 300 ms 的 hold boundary 前释放，为纯 no-op；不触发输入法、不打开本地麦克风、不切换 Persistent session，也不显示语音/readiness HUD。
- **LONG**：按住达到约 300 ms 后进入直接远程语音生命周期；RemoteOrbit 使用遥控器 ATVV 音频并向 `RemoteOrbit Mic 2ch` 供给 PCM，松开后等待输出收尾，再释放语音快捷键。
- Persistent、双 Receiver、Receiver B、本地麦克风短按等旧业务语义均不是当前产品合同。

在 Control Center 的麦克风设置中可以管理具名语音快捷键，并为其中一个配置选择 Active；菜单栏“语音输入”也可以切换 Active。首次配置保留原有六种左右 Option、Control、Command 纯修饰键。自定义组合会保留左右修饰键侧别。活动语音会话或输出收尾期间，切换 Active 或更改/删除当前 Active 会被拒绝，完成后可重试。

语音快捷键不会自动切换 macOS 输入法。组合键通过系统键盘事件发送，具体输入法是否接受该事件取决于输入法自身；软件测试不能证明输入法接收或语音文本完成。

源码中若仍存在历史命名，只能按其当前调用关系和测试判断用途；不能因为符号名包含 Persistent/Dual 等字样就推断旧业务仍有效。

## 主要能力

- Xiaomi RC003 BLE / ATVV 连接、握手、音频帧解析与重连。
- RemoteOrbit 虚拟音频输出链路、实时 playout、drain 与默认输入设备协调。
- 遥控器 HID 按键、单击/双击/长按识别、事件压制与快捷键注入。
- Codex、FloatTabs、Ghostty、Obsidian 等 App Profile / 语义命令适配。
- Control Center、映射设置、登录启动、安装/组件状态。
- 单一 machine-readable diagnostic authority、只读 CLI、长期语音可观测与显式导出。

## 安装

普通使用优先安装项目发布的 DMG：

1. 将 `RemoteOrbit.app` 拖到 `/Applications`。
2. 启动 App，并按 macOS 提示授予蓝牙、辅助功能和输入监控权限。
3. 在设置中检查 `RemoteOrbitAudio.driver`；缺失时使用应用提供的音频组件安装入口。
4. 在系统声音或“音频 MIDI 设置”中确认 `RemoteOrbit Mic 2ch` 可见。

遥控器语音来自 BLE ATVV；当前产品路径不使用本机/外接麦克风作为麦克风键语音输入，因此 RemoteOrbit 不以本地麦克风采集作为当前语音合同的一部分。

完整安装、权限、设备验证和排障步骤见 [`SETUP_NOTES.md`](SETUP_NOTES.md)。

## 从源码构建

维护者需要 macOS 13+、Xcode Command Line Tools，以及构建音频驱动所需的标准工具。

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

驱动安装、CoreAudio 重载和系统权限更改都会影响实际运行环境，需在 macOS 管理员权限与隐私控制允许的条件下操作。

## 测试与 CI

- Swift Package 与回归测试位于 `remote-orbit/Tests/RemoteOrbitTests/`。
- 例行 CI 入口为 `.github/workflows/remoteorbit-ci.yml`。
- 软件 CI 不替代真实 RC003 / 豆包的人机验收，也不应安装 App、替换 HAL driver、重启 CoreAudio 或修改 TCC/默认音频设备。

## 日志与诊断

普通日志和录音均由用户显式控制。诊断架构的持久决策见：

- [`docs/diagnostics/ADR-0001-single-diagnostic-authority.md`](docs/diagnostics/ADR-0001-single-diagnostic-authority.md)
- [`docs/diagnostics/ADR-0002-read-only-diagnostic-cli.md`](docs/diagnostics/ADR-0002-read-only-diagnostic-cli.md)
- [`docs/diagnostics/ADR-0003-long-term-observability.md`](docs/diagnostics/ADR-0003-long-term-observability.md)

只读 CLI 示例：

```bash
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics status
/Applications/RemoteOrbit.app/Contents/MacOS/RemoteOrbit diagnostics verify
```

诊断关闭不能关闭语音正确性所需要的 ownership、release/drain、suppression、watchdog 或 transport 机制。

## 项目资料

[`docs/README.md`](docs/README.md) 列出当前项目资料：

- `README.md`：当前产品/仓库入口。
- `AGENTS.md`：RemoteOrbit 产品和运行时技术约束。
- `SETUP_NOTES.md`：当前安装与排障入口。
- `docs/DOMAIN_MAP.md`：从源码和测试派生的导航地图，不拥有业务合同。
- `docs/diagnostics/ADR-*.md`：仍有效的长期诊断设计决策。
- `docs/incidents/`：历史事故证据，不是当前产品或设计权威。
- 根目录 `RELEASE_NOTES_v*.md`：对应版本的历史发布记录；旧版本中的业务语义不得被当成当前合同。
