# RemoteOrbit 安装与排障记录

## 当前基线

- RemoteOrbit 当前版本为 `0.2.5 (Build 10)`；当前 `main` 已将本次音频设备切换、断连重连和默认模板整理为正式基线。
- 当前主线覆盖独立产品改名、DMG/组件安装、Control Center、通用映射与 App 模板、Codex/FloatTabs/Ghostty/Obsidian 预设、音频链路和语音焦点修复。
- 当前整理后的音频设备基线还包含菜单栏输入/输出切换、物理麦克风保留选择和虚拟回环设备过滤。
- FloatTabs 是独立仓库和独立应用；RemoteOrbit 只通过本机语义命令协议与它对接，两个仓库需要分别记录基线。

### 历史提交进度

本次发布前已核对测试基线与 `main` 的差异；以下功能全部纳入 RemoteOrbit `main`，不存在只留在测试分支的必需修复：

1. `f96291a`：建立独立项目基线，包含 BLE/ATVV 音频、HID、按键映射、日志和安装脚本。
2. `26eeec5`：从旧项目重命名为 VoiceRemoteBridge，并切换源码与启动入口。
3. `8ca98ab`：清理最后残留的旧命名。
4. `6b1f395`：增加自包含 macOS 安装器、驱动备份和 CoreAudio 重载流程。
5. `5120cf0`：重做 Control Center、映射设置界面和产品品牌。
6. `83710a9`：切换到 RemoteOrbit 0.2.0 目录、Bundle、驱动和打包基线。
7. `2368b64`：校准 Codex 默认按键映射。
8. `4552b4c`：升级时补齐 Codex 默认模板且不覆盖用户配置。
9. `1072ca0`：迁移旧版音量键的上下一个对话绑定。
10. `bfbac6f`：扩展 Obsidian 标准动作和默认模板。
11. `ed02b7b`：建立 RemoteOrbit 0.2.3 的清晰基线，纳入语音焦点、按键注入、滚动释放和刷新协议修复。
12. `78bcb7e` / `cce936a`：增加菜单栏输入/输出设备切换、输入选择持久化、虚拟回环过滤和音频设备测试。
13. `1302849`：修复音量事件路由与原生媒体事件压制。
14. `9ce624e` / `d519a21`：完善 HID 兼容模式、原生事件压制和监控回退。
15. `279ea76` / `30ea77d`：补齐 FloatTabs、Obsidian 语义动作和应用模板。
16. `2b7db15`：增加 ATVV 断连重连、退避和重新握手，蓝牙恢复后自动恢复语音链路。
17. `2f2a6f8` 及本次发布修复：校准内置模板上下滚屏方向、默认模板初始化和语音焦点首击保护。

当前基线把语音焦点事务、App 实际焦点路由、快捷键异步发送、滚动释放保护、电源原生事件拦截、
FloatTabs 语义刷新协议、音频设备切换和回归测试一并纳入。这样后续从个人仓库安装时，
可以直接以本次基线提交为起点，不需要从旧的 VoiceRemoteBridge 文件名或旧安装路径恢复。

这份文档记录本次在 Apple Silicon Mac + 豆包输入法上的最终可用配置，方便以后从个人仓库重新安装时直接复现。

## 当前验证过的设备和软件

- Mac mini（Apple Silicon，macOS 26.6.2）。
- 小米蓝牙语音遥控器 2 Pro。
- 豆包 macOS 输入法。
- BlackHole 2ch 作为原始参考驱动；项目另外构建独立的 `RemoteOrbit Mic 2ch`。
- 当前实际使用的音频设备必须显示：`RemoteOrbit Mic 2ch · Transport: USB`。

当前只验证过小米蓝牙语音遥控器 2 Pro。Redmi Air、其他 Redmi 蓝牙设备或其他型号遥控器目前没有验证，不能默认认为兼容。它们需要同时具备兼容的 ATVV 音频服务、HID 语音键报告和对应的 VID/PID；否则需要单独增加协议或按键映射。

## 首次安装（DMG）

普通用户优先将 DMG 顶层的 `RemoteOrbit.app` 拖到旁边的 `Applications` 快捷入口，
再从 `/Applications/RemoteOrbit.app` 启动。不需要自行安装 Xcode、Homebrew、Xcode Command
Line Tools，也不需要单独下载 BlackHole。DMG 已经包含预先构建好的 `RemoteOrbitAudio.driver`。

首次启动后，在“设置与诊断”中检查虚拟音频组件；如果未检测到，点击“重新安装音频组件”，
在管理员对话框中授权。应用会自动重启 `coreaudiod`，通常不需要重启 Mac。

音频驱动补装会将替换前的驱动备份到 `~/Library/Application Support/RemoteOrbit/Backups/`。

首次打开 App 时，仍需要用户按照 macOS 的隐私提示授予蓝牙、麦克风、辅助功能和
输入监控权限。安装器不能绕过这些系统授权。

## 最终工作方式

### 菜单栏音频切换

菜单栏一级菜单直接提供两个独立子菜单：

- **输入设备**：`RemoteOrbit Mic 2ch（遥控器/自动）`、内置麦克风和已连接的外接麦克风。
- **输出设备**：扬声器、显示器音频、耳机等真实输出设备。

输入设备按当前系统默认设备显示勾选；选择物理麦克风后会写入 macOS 默认输入，并在 RemoteOrbit
重启或驱动重载后恢复该选择。重新选择 `RemoteOrbit Mic 2ch（遥控器/自动）`，即可恢复豆包使用
遥控器长按语音链路。输出设备选择立即切换系统默认输出；BlackHole、RemoteOrbit
等虚拟回环设备不会显示在输出列表中。菜单每次打开都会重新扫描设备，插拔外接设备后可点击
“刷新设备列表”。

### 短按

短按遥控器语音键会被忽略：不调用本机或外接麦克风、不发送语音输入，也不切换系统音频设备。这样可以避免短按/长按识别竞态和第一次输入丢失。

### 长按

长按超过约 120 ms 时：

1. 真实左 Option 立即保持按下状态，所以豆包能显示按住说话浮窗；FloatTabs 的焦点预热不插入语音键延迟。
2. RemoteOrbit 只把遥控器 ATVV 解码后的音频送入 `RemoteOrbit Mic 2ch`，不回退到本机麦克风。
3. 豆包从同一个默认输入读取遥控器音频。
4. 松开遥控器后立即释放 Option、停止遥控器音频，并清空本次语音的预缓冲。

遥控器音频当前使用约 20 倍增益，并使用软限幅，解决遥控器距离较远时声音过小的问题；如果近距离说话出现失真，可以调低 `AudioPipe.swift` 中的 `remoteGain`。

## 从个人仓库重新安装

```bash
git clone https://github.com/Lost0rz/RemoteOrbit.git
cd RemoteOrbit

./remote-orbit/run-self-tests.sh
./remote-orbit-audio-driver/build-driver.sh
sudo ./remote-orbit-audio-driver/install-driver.sh
```

驱动安装脚本会：

- 从 BlackHole 0.7.1 官方源码重新构建驱动；
- 保持外层 Audio Box 为 Virtual，但把实际 Audio Device 标记为 USB；
- 安装独立的 `RemoteOrbitAudio.driver`，不覆盖原 BlackHole；
- 将已有的 `RemoteOrbitAudio.driver` 移到 `remote-orbit-audio-driver/build/RemoteOrbitAudio.driver.previous` 备份；
- 重启 CoreAudio。

安装驱动后应用会重启 `coreaudiod`，通常不需要重启整台 Mac。只有 `RemoteOrbit Mic 2ch`
仍未出现时，才把重启 macOS 作为最后的恢复步骤；只重启豆包不能代替音频驱动重载。

然后构建并安装菜单栏 App：

```bash
./remote-orbit/package-app.sh
./remote-orbit/install-app.sh
open /Applications/RemoteOrbit.app
```

首次启动时，按 macOS 提示授予蓝牙、麦克风、辅助功能和输入监控权限。豆包也建议在驱动安装、默认输入设备变化或 App 更新后重新启动一次。

## 必须确认的设置

在“声音”或“音频 MIDI 设置”中确认：

- `RemoteOrbit Mic 2ch` 存在；
- `RemoteOrbit Mic 2ch` 是默认输入设备；
- `RemoteOrbit Mic 2ch` 显示 `Transport: USB`；
- 豆包没有手动固定到 `External Microphone` 或其他设备；
- 项目按键映射中的语音键仍然是“默认”，不要改成右 Option，也不要单独绑定右 Option。

程序连接遥控器后会应用只针对该遥控器的 HID 映射：VID `0x2717`、PID `0x32B8` 的语音键 F5 usage 映射到左 Option。FloatTabs 场景由显示/激活流程预热输入焦点，语音键本身不等待焦点通知；不会修改 Mac 键盘或其他蓝牙键盘。退出程序时会清除这条设备级映射。

## 常见问题处理

### 0. 自定义 `Command+Home` 等组合快捷键不唤起目标 App

旧版本只把 Command 标志附加在 Home 的合成事件上。普通前台应用通常能识别，
但 Float Tabs 使用 `KeyboardShortcuts`/Carbon 注册全局热键，普通 `CGEvent`
即使发送成功也不会触发它。当前版本对带 Command 的自定义快捷键优先通过
macOS System Events 发送，发送顺序相当于：

```text
Command down → Home down → Home up → Command up
```

更新 App 后重新运行 `package-app.sh` 和 `install-app.sh`，退出旧的 RemoteOrbit 进程
并重新打开。首次触发时如果 macOS 要求自动化权限，请在“系统设置 → 隐私与
安全性 → 自动化”中允许 RemoteOrbit 控制“系统事件”。同时确认 Float Tabs 自己设置
的快捷键与物理键盘按下 `⌘Home` 时确实能够正常唤起；如果物理快捷键也无效，
应先在 Float Tabs 中处理快捷键冲突。

### 1. 没有 `RemoteOrbit Mic 2ch`

确认驱动安装命令是否成功，并先重新检测音频设备；只有 CoreAudio 重载后仍没有设备时，
再重启整台 Mac。可用下面的命令检查：

```bash
system_profiler SPAudioDataType
```

如果仍没有设备，重新执行：

```bash
./remote-orbit-audio-driver/build-driver.sh
sudo ./remote-orbit-audio-driver/install-driver.sh
```

### 2. `RemoteOrbit Mic 2ch` 显示为 `Transport: Virtual`

这是旧的二进制补丁没有正确修改 BlackHole 0.7.1 的实际设备属性。豆包可能因此忽略它并继续使用外接麦克风。不要继续修改 Option，重新用个人仓库里的源码构建脚本安装，然后重新检测；若设备仍未出现，再重启 Mac。

### 3. 长按有浮窗，但仍然读取外接麦克风

按顺序检查：

1. `RemoteOrbit Mic 2ch` 是否为默认输入；
2. Transport 是否为 USB；
3. 驱动安装后豆包是否重新启动；
4. RemoteOrbit 日志中长按时是否出现“输入切换 → 遥控器麦克风”；
5. 日志中是否有 `remoteBuffers` 和 `renderedFrames`。

### 4. 长按音频太小

先把遥控器靠近说话测试。如果仍然太小，调整：

```text
remote-orbit/Sources/RemoteOrbit/AudioPipe.swift
remoteGain
```

当前值是 `20.0`。调大可以提高远距离音量，但过大可能使近距离声音失真。

### 5. 第一次点击“录制快捷键”没有弹窗

旧版本的设置窗口同时切换 `showRecorder` 和 `recorderButton`，SwiftUI 第一次
展示 sheet 时可能还没有拿到目标按钮，所以看起来像点击无效。当前版本改用
按钮本身作为 sheet 的展示状态，第一次点击也应直接出现录制窗口。

### 6. 短按浮窗一闪就消失

旧版本可能同时产生设备级真实 Option 和合成 Option，导致浮窗一闪就消失或第一次语音无文字。当前版本只保留设备级真实 Option，不再额外合成第二个 Option，也不在语音键按下时等待焦点；FloatTabs 只在显示/激活阶段预热输入焦点。不要手动运行 `hidutil` 添加重复映射，也不要把语音键同时绑定到左 Option 和右 Option。

### 7. 按键时后台嘟一声，或自定义映射没有生效

日志里的“遥控器已连接（兼容模式）”表示 macOS 没有允许 App 独占这个 HID
设备。旧版本的原生事件压制发生得偏晚，遥控器的 Home/方向键可能先漏给系统，
再叠加项目的合成快捷键，结果就是系统提示音或重复动作。当前版本已把压制器
移到 HID 层，并同步处理 HID 报告，优先吞掉原生事件；日志还会记录：

```text
[KEY] 主页键 down → ⌘Home; sent=true
[KEY] 主页键 up → ⌘Home; sent=true
```

如果日志显示 `sent=true` 但 Float Tabs 仍没有动作，先检查自动化权限，再用
物理键盘按 `⌘Home` 确认 Float Tabs 自己的全局快捷键仍然有效。

自定义快捷键录制窗口现在可以单独选择“单次点击”或“按住重复”。旧版本保存
的快捷键会自动按“单次点击”读取，所以 `⌘C`、`⌘Q`、`⌘Home` 等不会因为升级
而突然重复。需要连续操作时（例如把某个按钮映射为 Delete、音量或方向快捷键），
选择“按住重复”；按住约 350 ms 后会按遥控器的重复节奏继续发送。

没有设置自定义快捷键的预设动作继续沿用原规则：方向、音量、返回键支持长按
重复，电源、主页、菜单、TV、确定等默认是单次动作。每次按键松开都会取消该键
的重复计时器，避免修饰键或目标程序退出后残留按键。

### 7.1 电源键映射成刷新却弹出关机提示

这是遥控器原生电源 `systemDefined` 事件漏给 macOS，同时 RemoteOrbit 又发送了
`Command-R` 的双重事件。当前版本在遥控器处于兼容 HID 模式并已连接时，专门拦截原生
电源事件；RemoteOrbit 自己发送的合成刷新动作仍会放行。

按键映射中优先选择“刷新当前页面”预设：FloatTabs 会走内部 `reload` 命令，其他浏览器
发送标准 `Command-R`。原先手动录制的 `Command-R` 不会被升级过程自动覆盖。

### 8. 通用映射与 App 模板

按键映射现在分为两层：

- 通用映射：适用于所有 App，也是没有匹配模板时的回退配置；
- App 模板：按 Bundle ID 绑定到具体 App。同一个 App 可以有多个模板，但同时
  只有一个模板处于“生效”状态。

通用映射中的每个按键还可以勾选“应用全局”。启用后，该按键始终使用通用映射，
即使当前前台 App 有 Active 模板，也不会被模板替代；切换到 App 模板查看时，这个
按键会显示锁定/图钉标记并变灰，必须回到“通用映射”修改。适合主页键打开/隐藏 FloatTabs、
显示桌面、应用切换、打开固定程序等跨程序固定动作。若要实现主页键的呼出逻辑，
可将通用主页键设为“打开 / 显示 / 隐藏 FloatTabs”，再在 FloatTabs 模板里将主页键设为
“FloatTabs：显示 / 隐藏”；全局动作在目标程序前台时隐藏，不在前台时打开并激活。
是否应用全局由用户逐个按键选择，不会自动改变已有映射。

在 RemoteOrbit Control Center 的“按键映射”页面，先选择“默认 · 所有 App”
或某个 App，再选择该 App 的 Active Profile。默认映射、App Profile 和单按钮的“始终
使用默认”关系不会混在一起；第一次创建应用配置时，在“应用配置”页面新建 Profile，
或在按键映射页面导入预设。新 Profile 会从当前默认映射复制一份完整的 13 个按键配置，
之后可以独立修改每一个按键。

运行时按遥控器按钮的瞬间读取前台 App，并锁定这次按下对应的模板；即使该快捷键
随后切换窗口或退出程序，松开和长按重复仍使用同一套映射。没有对应 App 激活
模板时，始终使用通用映射。

当前按 Bundle ID 区分的是整个 App，不区分浏览器网页或标签页。网页级别的功能
需要浏览器扩展或进一步的 App 适配器，不能仅靠这个按键模板完成。

预设动作已经按功能分组显示：

- 系统控制：禁用、显示桌面、上下文菜单、应用切换、鼠标右键；
- 方向与滚动：方向键、滚屏、Return、Escape；
- 复制与编辑：复制、粘贴、剪切、全选、删除、撤销、重做；
- 媒体控制：音量、静音、播放/暂停；
- 软件专属：FloatTabs、ChatGPT/Codex、Ghostty、Obsidian、网易云音乐。

设置某个程序时，先在“程序”下拉框选择目标 App，再在旁边的“模板”下拉框中
选择已有模板，或点击“导入预设”。导入后会立即设为该 App 的 Active 模板；同一
程序可以保留多个模板，切换模板下拉框就会切换生效内容。已经存在同名模板时，
导入只会激活它，不会覆盖用户已经改过的按键。没有模板的程序不会直接修改通用
映射，必须先导入或新增模板。

当前内置的软件模板包括：

- ChatGPT 默认、Codex 默认：均包含官方 ChatGPT / Codex 全量快捷动作目录，并按以下四类显示在预设动作选择器中：
  - 通用：命令菜单、设置、快捷键帮助、打开文件夹、前进/后退、字体大小、侧边栏、底部面板、Terminal、清空 Terminal、清除提醒、撤销/重做、关闭窗口、全屏和退出；
  - 对话：新建/归档/未读/置顶/重命名对话、侧边对话、搜索/查找、上/下一个对话、下一个需要注意的对话、最近对话 1–6、跳转对话 1–9；
  - 输入与模式：模型/项目选择、语音、听写、恢复上次输入、批准/拒绝请求、Chat/Work/Codex 切换和 Activity；
  - 工作区与浏览器：环境主操作、搜索文件、文件树、审查页/面板、浏览器标签/面板、地址栏、后退/前进、刷新、浏览器模式、复制路径/链接/会话 ID/工作目录和 Appshot。
  Codex 默认的菜单键为显示/隐藏侧边栏，左/右键发送输入栏左右方向键；ChatGPT 默认的菜单键仍留空。
  两者的音量 `+/-` 都是侧边栏中的上一个/下一个对话。
- FloatTabs 默认：上下滚屏、对话框/网页焦点、显示/隐藏、设置和标签切换；音量
  `+/-` 默认切换下一个/上一个标签；
- Ghostty 默认：新标签、新窗口、上下一个标签、关闭 surface、右/下分屏、搜索、
  命令面板；
- 网易云音乐默认：上一首、下一首、播放/暂停和音量；
- Obsidian 默认：上下滚屏、标签切换、快速切换文件、命令面板、新建笔记、关闭标签和全库搜索；
  预设动作中还提供新建/恢复标签、编辑/阅读模式切换和添加属性。

全局“程序启动”分类提供“打开 / 显示 / 隐藏 FloatTabs”和“打开 / 显示 / 隐藏 Codex”两个
动作；它们不要求当前前台程序是 FloatTabs 或 Codex。前者用于从其他程序重新唤起
或隐藏 FloatTabs，后者用于启动、激活或隐藏 Codex。

ChatGPT 与 Codex 在当前这台 Mac 的安装中都对应 `com.openai.codex`，因此系统
只能把它们识别为同一个程序范围；代码中把“ChatGPT 默认”和“Codex 默认”做成
同一程序下的两个可切换模板，而不是伪造两个不同的 Bundle ID。Ghostty 的新标签、
标签切换、分屏、搜索和命令面板动作会先尝试通过辅助功能菜单适配器执行，不依赖
当前快捷键；如果 Ghostty 版本、菜单语言或自定义配置导致菜单项找不到，则回退到
该动作的默认快捷键，此时仍可在 RemoteOrbit 中改成自定义录制。首次使用适配器时，需要
在“系统设置 → 隐私与安全性 → 辅助功能”中允许 RemoteOrbit 控制 Ghostty。

FloatTabs 已内置 `⌃Tab` / `⌃⇧Tab` 的下一个/上一个标签快捷键。RemoteOrbit 的预设动作
也提供了“FloatTabs：下一个标签”和“FloatTabs：上一个标签”，不需要手动录制
组合键。要用音量键切换 FloatTabs 标签：先在按键映射中选择 FloatTabs 的 App
模板，再把“音量 +”设为下一个标签，把“音量 -”设为上一个标签。现在这些
FloatTabs 专属动作会在 FloatTabs 运行时通过本机语义命令直连，不依赖 FloatTabs
当前设置的快捷键；因此以后改 FloatTabs 快捷键不需要重新录制 RemoteOrbit 映射。

FloatTabs 的 App 模板和全局动作都支持同一个按键完成开关：目标程序前台时隐藏，
目标程序不在前台时显示、激活并聚焦；目标未运行时则先启动。全局动作还可以选择
“打开 / 显示 / 隐藏 Codex”，用于从任意程序切换到 Codex，再按同一个按键隐藏它。
这样 FloatTabs、Codex 的 App 模板和所有程序通用的唤起动作不会互相割裂。

当前仓库内置了 ChatGPT 默认和 Codex 默认两个模板，绑定到 ChatGPT/Codex 桌面端的同一个
Bundle ID `com.openai.codex`。首次启动新版 RemoteOrbit 时，如果尚未存在 ChatGPT 模板，会自动
创建并激活“ChatGPT 默认”；如果尚未存在 Codex 模板，也会自动补出“Codex 默认”，但不会
擅自切换已经激活的模板或覆盖用户修改。需要使用 Codex 布局时，在程序范围选择
“ChatGPT / Codex”，再在模板下拉框选择“Codex 默认”并点“设为 Active”。
ChatGPT 默认：左键打开侧边栏，右键用 ⌘J 开关终端底部面板，中键确认/批准，返回键 Delete，
上下键发送滚轮滚动，主页键跳到下一个需要注意的对话，菜单键留空，TV 键保持 Command-Tab
应用切换；音量 `+/-` 为侧边栏中的上一个/下一个对话。Codex 默认：左/右键为输入栏左右移动，
音量 `+/-` 为侧边栏中的上一个/下一个对话，菜单键为显示/隐藏侧边栏；Terminal 仍可从 Codex
预设动作中单独选择。
“搜索对话”在官方命令表中默认没有快捷键，RemoteOrbit 会优先尝试通过 Codex 的辅助功能菜单执行；如果系统未授予辅助功能权限，该动作会失败并在日志中显示原因。
已有 ChatGPT 自定义模板不会被覆盖。

### 9. 豆包完全没有浮窗

先用 Mac 键盘实际按左 Option，确认豆包本身正常。然后检查 RemoteOrbit 菜单状态和权限：

- 辅助功能：开启 RemoteOrbit；
- 输入监控：开启 RemoteOrbit；
- 蓝牙：允许 RemoteOrbit 连接遥控器；
- 麦克风：如果 macOS 显示该权限请求，允许 RemoteOrbit；当前语音键只使用遥控器麦克风，不会回退到本机麦克风。

如果刚更新过 App，退出旧的 RemoteOrbit 进程后重新打开；如果刚更新过驱动，先在设置中
重新检测并等待 CoreAudio 重载，设备仍未出现时再重启整台 Mac。

## 日志与诊断

打开日志：

```bash
defaults write com.lost0rz.RemoteOrbit RemoteOrbit.loggingEnabled -bool true
```

日志位置：

```text
~/Library/Logs/RemoteOrbit/RemoteOrbit.log
```

重点关注：

```text
[HID-MAP] 遥控器语音键 → 左 Option 已启用
[AUDIO] 输入切换 → 遥控器麦克风
[PRESS] LONG start → Option DOWN
[AUDIO-METER] remoteBuffers=... renderedFrames=...
[PRESS] LONG end → Option UP
[AUDIO] 输入切换 → 无输入（等待下一次遥控器长按）
```

需要确认遥控器原始音频时，可以在菜单中打开调试录音。录音目录为：

```text
~/Library/Application Support/RemoteOrbit/Recordings/
```

测试结束后可以关闭日志：

```bash
defaults write com.lost0rz.RemoteOrbit RemoteOrbit.loggingEnabled -bool false
```

## 本次代码修改位置

- `remote-orbit/Sources/RemoteOrbit/main.swift`：短按忽略/长按状态机、立即物理 Option、设备级映射。
- `remote-orbit/Sources/RemoteOrbit/AudioPipe.swift`：遥控器增益、预缓冲和虚拟设备输出诊断；启动时恢复菜单选择的输入设备。
- `remote-orbit/Sources/RemoteOrbit/AudioDeviceManager.swift`：CoreAudio 输入/输出设备枚举、系统默认设备切换和虚拟回环过滤。
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/MappingStore.swift`：全局映射、App 模板、持久化迁移和按下时目标快照。
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/SettingsView.swift`：RemoteOrbit Control Center、按键 Profile、预设导入和全局按键锁定。
- `remote-orbit/Sources/RemoteOrbit/ProductBranding.swift`：独立产品标题栏、版本信息和统一品牌文案。
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/AppTemplatePresets.swift`：内置 App 模板与语义动作目录。
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/KeyInjector.swift`：预设动作、目标 App 激活、滚屏和外部适配回退。
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/FloatTabsCommandClient.swift`：FloatTabs 本地命令与输入焦点握手。
- `remote-orbit/Sources/RemoteOrbit/KeyMapping/CodexCommandAdapter.swift`、`GhosttyCommandAdapter.swift`：辅助功能菜单适配。
- `remote-orbit-audio-driver/build-driver.sh`：固定从 BlackHole 0.7.1 源码构建 USB 传输驱动。
- `remote-orbit-audio-driver/install-driver.sh`：可恢复地备份并安装驱动。
- `remote-orbit/Packaging/Info.plist`：更新麦克风权限说明。
