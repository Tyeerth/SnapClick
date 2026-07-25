# SnapClick 音频录音功能 — 完整设计文档

> 版本：v1.0
> 目标：为 SnapClick 增加独立的"音频录音"功能，与现有"屏幕录制"并列，但仅输出音频文件（M4A/AAC），不录制画面。

---

## 1. 概述

### 1.1 背景

SnapClick 已有"屏幕录制"功能（`ScreenRecordingEngine`），可以同步录视频 + 系统音频 + 麦克风。但在以下场景中存在明显痛点：

- **只想录会议/口播/讲座音频**：视频文件动辄 GB，占用大量磁盘，但用户只关心声音。
- **系统音频无法独立录制**：当前必须先开录屏才能拿到系统声音（macOS 13+ ScreenCaptureKit 的限制）。
- **快捷键冲突**：录屏启动快捷键为 `Ctrl+Shift+R/F`，与单纯录音心智模型不一致。

### 1.2 目标

新增一个**独立、轻量、可后台运行**的"音频录音"功能，输出单文件 `.m4a`（AAC 编码），可同时收录麦克风与系统声音（可选），并提供：

- 实时电平反馈
- 暂停/继续/停止/取消
- 状态栏菜单与全局快捷键
- 独立侧边栏设置项

### 1.3 非目标

- ❌ 不录视频画面
- ❌ 不做语音转写 / 字幕 / AI 摘要
- ❌ 不做音频编辑（剪切、降噪、变声）
- ❌ 不做多音轨混音（每条录音文件最多 2 个音轨：mic + system audio）
- ❌ 不做实时流媒体推送
- ❌ 不做文件加密 / 云同步

---

## 2. 用户场景

| # | 场景 | 关键诉求 |
|---|------|---------|
| 1 | **远程会议归档**：Zoom/腾讯会议开着会，想纯录声音 | 仅音频、快启动、自动停止后能立即在 Finder 找到 |
| 2 | **系统声音采集**：截一段 Apple Music / 视频网站的声音 | 单独系统音频（不需要麦克风） |
| 3 | **播客 / 课程录音**：麦克风收音，环境安静 | 实时电平看到自己声音大小、不爆音 |
| 4 | **临时口播**：在桌面上临时录一段语音备忘 | 状态栏一键启动，结束后自动在 Finder 高亮 |
| 5 | **录屏同时录声音**：保留现有录屏功能不受影响 | 两者独立、互不冲突 |

---

## 3. 功能范围

### 3.1 包含

- **音频源**：麦克风（默认开启）+ 系统音频（可独立开关）
- **文件格式**：M4A（容器：MP4，编码：AAC-LC，44.1 kHz / 48 kHz 可选）
- **质量档位**：`经济`（64 kbps）/ `标准`（128 kbps）/ `高质量`（256 kbps）
- **声道**：单声道 / 立体声
- **实时反馈**：HUD 上左右声道电平柱状图（VU meter 风格）
- **录音控制**：开始 / 暂停 / 继续 / 停止保存 / 取消丢弃
- **倒计时启动**：复用现有 `RecordingCountdownWindow`（3/5/10 秒可配）
- **状态栏菜单**：录音时切换为"录音中"动态菜单
- **全局快捷键**：开始录音 + 停止录音
- **侧边栏设置**：独立的"音频录制"设置页
- **多麦克风设备**：下拉选择当前连接的输入设备
- **自动命名**：`SnapClick_录音_yyyy-MM-dd_HH.mm.ss.m4a`
- **保存路径**：默认桌面，可自定义
- **多语言**：简体中文 / English / 日本語

### 3.2 不包含（v1.0 后续可扩展）

- MP3 / WAV 导出
- 实时波形 / 频谱图
- 噪声抑制 / 自动增益
- 文件内嵌章节标记
- iCloud 同步
- 多音轨工程文件（DAW 风格）
- 与系统"语音备忘录"互通

---

## 4. 架构设计

### 4.1 总体架构

```
┌─────────────────────────────────────────────────────────┐
│                    AppSettings (现有)                    │
│  + audioRecordFormat / audioRecordQuality /            │
│  + audioRecordSampleRate / audioRecordMicrophone /     │
│  + audioRecordSystemAudio / audioRecordShowMeter /     │
│  + audioRecordSavePath / audioRecordCountdown /        │
│  + hotkeyAudioRecord / hotkeyStopAudioRecord            │
└──────────────────────────┬──────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌─────────────────┐  ┌────────────────┐
│ HotkeyManager │  │ StatusBar       │  │ MainWindow     │
│  (扩展注册)    │  │  Controller     │  │  Sidebar       │
│               │  │  (扩展菜单)      │  │  +.audioRec    │
└──────┬────────┘  └────────┬────────┘  └───────┬────────┘
       │                    │                    │
       └────────────────────┼────────────────────┘
                            ▼
              ┌────────────────────────────┐
              │  AudioRecordingEngine      │
              │  (新增 @MainActor 单例)      │
              │                            │
              │  - micSession              │
              │  - systemAudioTap          │
              │  - assetWriter             │
              │  - meterQueue              │
              │  - meterPublisher (@Pub)   │
              └──────────┬─────────────────┘
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
    ┌───────────────────┐  ┌──────────────────────────┐
    │ AudioRecordingHUD │  │ AudioRecordingPreview    │
    │  Window           │  │  Card (设置页预览)         │
    │ (实时电平 + 控制)   │  │                          │
    └───────────────────┘  └──────────────────────────┘
```

### 4.2 新增文件清单

| 路径 | 作用 |
|------|------|
| `SnapClick/Modules/AudioRecording/AudioRecordingEngine.swift` | 核心引擎：采集 + 编码 + 状态机 |
| `SnapClick/Modules/AudioRecording/AudioRecordingHUDWindow.swift` | 录音中浮动控制条（含电平柱） |
| `SnapClick/Modules/AudioRecording/AudioRecordingPreviewCard.swift` | 设置页中的"实时预览"卡片（复用现有 RecordingPreviewCard 风格） |
| `SnapClick/Modules/AudioRecording/AudioQualitySettings.swift` | 音频质量档位定义（比特率、采样率、声道映射） |
| `SnapClick/Modules/AudioRecording/AudioLevelMeter.swift` | 通用 SwiftUI 视图：左右声道电平柱（与 HUD 和预览卡共享） |

> 文件夹 `AudioRecording` 与现有 `Recording` 并列，与录屏共用倒计时窗口（`RecordingCountdownWindow`）和权限管理。

### 4.3 修改文件清单

| 路径 | 改动 |
|------|------|
| `SnapClick/Core/AppSettings.swift` | 新增 9 个 `@AppStorage` 属性 + 翻译键 |
| `SnapClick/UI/MainWindow.swift` | `SettingsDestination` 新增 `audioRecording` case + 新增 `AudioRecordingSettingsView` |
| `SnapClick/UI/StatusBarController.swift` | 新增"开始录音 / 停止录音"菜单项 + 录音中动态菜单切换 |
| `SnapClick/Core/HotkeyManager.swift` | 注册 `hotkeyAudioRecord` / `hotkeyStopAudioRecord` 两个快捷键 |
| `SnapClick/Core/PermissionManager.swift` | 新增 `hasMicrophonePermission` 检查 + `requestMicrophonePermission()`（TCC `AVCaptureDevice.requestAccess(for: .audio)`） |
| `SnapClick/Core/AppDelegate.swift` | 注册通知 + 启动时初始化 engine |
| `SnapClick/UI/WelcomeView.swift` | 欢迎页权限卡片增加"麦克风"项 |
| `SnapClick/App/Info.plist` | `NSMicrophoneUsageDescription`（必需，否则启动即崩） |
| `SnapClick/SnapClick.entitlements` | `com.apple.security.device.audio-input`（App Sandbox 已禁用，但保留以便未来沙盒化） |

---

## 5. UI 设计

### 5.1 侧边栏新增项

`SettingsDestination` 新增：

```swift
case audioRecording = "audioRecording"
```

- **显示名**："音频录制"（localized）
- **图标**：`waveform.circle.fill`（与现有 `record.circle` 录屏图标视觉区分）
- **位置**：紧邻 "屏幕录制" 之后（"屏幕录制" → "音频录制" → "贴图 & 取色"）

> 视觉一致性：沿用现有 Liquid Glass 胶囊风格，与录屏图标同色（红色系），但用 `waveform` 区分。

### 5.2 设置页结构（`AudioRecordingSettingsView`）

与 `RecordingSettingsView` 保持视觉对齐：

```
┌──────────────────────────────────────────────────────┐
│ AudioRecordingPreviewCard                            │
│  仿 Stitch 风格的暗色预览卡：                         │
│   - 顶部 "实时预览" 红色徽章 + REC 闪烁点              │
│   - 中央大号电平柱（左/右声道）                         │
│   - 底部状态文字："就绪" / "00:12" / "已暂停"            │
└──────────────────────────────────────────────────────┘

┌──────────────────────┐  ┌──────────────────────┐
│ 音频源               │  │ 输出格式             │
│  [DesignCard]        │  │ [DesignCard]         │
│  麦克风：[下拉]       │  │ 格式：M4A (只读)      │
│  系统音频：[Toggle]   │  │ 质量：[标准▾]        │
│  倒计时：[3秒▾]      │  │ 采样率：[44.1kHz▾]    │
└──────────────────────┘  │ 声道：[立体声▾]       │
                          │ 保存位置：[文件夹]     │
                          └──────────────────────┘
```

具体控件（与录屏设置完全对齐的视觉语言）：

| 控件 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| 麦克风 | Picker | "无" | 选项：无 / 内置麦克风 / 外置 USB / 系统检测到的所有输入设备 |
| 系统音频 | Toggle | true | macOS 13+ 用 SCK，< 13 灰显 |
| 倒计时 | Picker | 3 | 0/3/5/10 秒 |
| 格式 | 静态标签 | M4A | v1.0 锁死 M4A，避免与录屏混淆 |
| 质量 | Picker | "标准" | 经济(64k) / 标准(128k) / 高质量(256k) |
| 采样率 | Picker | 44.1 kHz | 44.1 / 48 kHz |
| 声道 | Picker | 立体声 | 单声道 / 立体声 |
| 保存位置 | 文件夹选择 | ~/Desktop | 沿用 `NSOpenPanel` |

### 5.3 录音中 HUD（`AudioRecordingHUDWindow`）

复用 `RecordingHUDWindow` 的浮动面板 + 可拖动 + openHand/closedHand 光标，但内容重做：

```
┌──────────────────────────────────────────────┐
│ ● 00:23   [▌▌▌▌▌▎  ]  [▌▌▌▌▎  ]   ⏸ ⏹ ✕  │
│  L: 麦克风  R: 系统                           │
└──────────────────────────────────────────────┘
```

具体规格：

- **尺寸**：`260 × 56 pt`（比录屏 HUD 略宽以容纳双电平柱）
- **位置**：屏幕顶部居中（与录屏 HUD 一致）
- **背景**：`.ultraThinMaterial` 黑色磨砂
- **边框**：0.5 px 白色 12% opacity
- **左部**：
  - 红色 6pt 圆点（与录屏相同的 0.8s 呼吸动画）
  - 计时器（`00:23` 格式，monospaced 13pt semibold）
- **中部**：左右声道电平柱（`AudioLevelMeter` 共享组件）
  - 每条柱 12pt × 24pt
  - 3 段彩色：绿(0-60%) / 黄(60-85%) / 红(85-100%)
  - 柱下方小字 `MIC` / `SYS` 标识
  - 单声道时只显示一条
- **右部**：3 个 22×22pt 圆形按钮
  - 暂停 / 继续（`pause.fill` / `play.fill`，系统黄）
  - 停止（`stop.fill`，绿色 — 暗示"保留"）
  - 取消（`xmark`，红色 — 暗示"丢弃"）
- **拖动**：`isMovableByWindowBackground = true` + openHand/closedHand 光标
- **位置记忆**：保存到 `SnapClick.AudioRecordingHUD.PositionX/Y` UserDefaults

> 风格与现有录屏 HUD 完全一致，仅把中间的"参数条"换成"双电平柱"。用户不会觉得突兀。

### 5.4 状态栏菜单

在 `StatusBarController` 现有"屏幕录制"组下方新增"音频录制"组：

```
───── 截图组 ─────
智能截图          ⌃⇧A
选区截图          ⌃⇧S
窗口截图          ⌃⇧W
长截图            ⌃⇧L
───── 屏幕录制组 ─────
选区录制          ⌃⇧R
全屏录制          ⌃⇧F
窗口录制
───── 音频录制组 ─────   ← 新增
开始录音          ⌃⇧M     ← 新增
停止录音          ⌃⇧N     ← 新增（仅录音中可见）
───── 取色 & 贴图 ─────
...
```

录音中状态栏菜单切换为动态菜单（与现有录屏动态菜单模式一致）：

```
录音中 00:23
─────
继续录音  ▶
停止录音  ⏹
取消录音  ✕
```

- 状态栏图标：录音中显示 `mic.fill`（系统红 palette），与录屏的 `dot.circle.fill` 区分
- 录音中不再有"开始录音"项，避免误触
- 录音结束后恢复常规菜单

### 5.5 首次启动权限

`WelcomeView` 权限卡片新增"麦克风"项：

- 图标：`mic.fill`
- 颜色：紫色
- 描述："语音录音、系统声音路由所需"
- 文案与 `NSScreen`/辅助功能/扩展项完全对齐的视觉风格

> 已有录屏逻辑会校验系统声音权限，但本功能**不依赖**屏幕录制权限 —— 录音功能即使在无屏幕录制授权时也可工作（仅系统音频不可用）。

---

## 6. 音频引擎设计

### 6.1 `AudioRecordingEngine`（新增）

```swift
@MainActor
final class AudioRecordingEngine: NSObject, ObservableObject {
    static let shared = AudioRecordingEngine()

    // MARK: 公开状态
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    // 实时电平（0.0 ~ 1.0）
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0

    // MARK: 公开接口
    func startRecording(countdown: Bool) async throws
    func pauseRecording()
    func resumeRecording()
    func stopRecording() async throws -> URL
    func cancelRecording() async throws
}
```

### 6.2 音频采集双轨方案

#### 麦克风轨（必选）

```swift
let session = AVCaptureSession()
let input = try AVCaptureDeviceInput(device: micDevice)
let output = AVCaptureAudioDataOutput()
output.setSampleBufferDelegate(self, queue: micQueue)
session.addInput(input)
session.addOutput(output)
session.startRunning()
```

- 使用 `AVCaptureAudioDataOutput`，与现有录屏麦克风采集一致
- `delegate` 回调里取 `CMSampleBuffer` → 转 `AVAudioPCMBuffer` 算电平 → 喂给 `AVAssetWriter`

#### 系统音频轨（可选，macOS 13+）

```swift
// 复用现有 ScreenCaptureKit 流，但只取 audio output
let content = SCShareableContent.current
let display = content.displays.first!
let filter = SCContentFilter(display: display, excludingApplications: [self])
let config = SCStreamConfiguration()
config.capturesAudio = true
config.sampleRate = 44100
config.channelCount = 2
config.width = 2   // 必须 ≥ 2，否则 SCK 报错
config.height = 2  // 同上
let stream = SCStream(filter: filter, configuration: config, delegate: self)
try stream.addStreamOutput(self, type: .audio, ...)
try await stream.startCapture()
```

- **关键点**：`width/height` 必须非 0（SCK 限制），给最小值 2 即可
- **不需要录视频**：`SCStreamConfiguration.capturesVideo` 默认为 true，但即使开启，只要不订阅 `.screen` 输出就不会有视频带宽开销
- **复用现有 `SCStreamDelegate`**：录屏引擎已有的 `stream(_:didStopWithError:)` 处理函数可平滑迁移到独立协议扩展

#### 为什么不用 `ScreenCaptureKit` 录系统音频 + 单独 `AVCaptureSession` 录麦克风？

- **统一错误处理**：两条流在同一进程管理，失败时可同时回滚
- **时间戳对齐**：两路音频在同一 `AVAssetWriter.startSession(atSourceTime:)` 后能自动 PTS 对齐
- **避免文件分叉**：单文件多音轨输出比让用户后期合并更友好

### 6.3 编码（AVAssetWriter）

```swift
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
let audioSettings: [String: Any] = [
    AVFormatIDKey:           kAudioFormatMPEG4AAC,
    AVSampleRateKey:         sampleRate,            // 44100 / 48000
    AVNumberOfChannelsKey:   channels,              // 1 / 2
    AVEncoderBitRateKey:     bitrate,               // 64k / 128k / 256k
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
]
let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
input.expectsMediaDataInRealTime = true
```

**音轨数：**

- 仅麦克风：单 `AVAssetWriterInput`
- 麦克风 + 系统音频：双 `AVAssetWriterInput`，用 `[AVAssetExportSession] ` 无法合并，但**写入同一个 .m4a 文件**会自动被 MP4 容器存为多条音轨（QuickTime / iTunes / GarageBand / 网易云播放均可正常切换音轨）
- 仅系统音频：单 `AVAssetWriterInput`（仅 SCK 一路）

> 注意：当多音轨时，需要在 writer 启动前给两路流对齐初始 PTS。复用录屏的 `withTimingOffset` + `lastAppendedPTS` 偏移逻辑。

### 6.4 实时电平计算

每帧 `CMSampleBuffer` → `AVAudioPCMBuffer` → 计算 RMS：

```swift
func computeLevel(buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData else { return 0 }
    let channelCount = Int(buffer.format.channelCount)
    let frameLength = Int(buffer.frameLength)
    var sum: Float = 0
    for ch in 0..<channelCount {
        let samples = channelData[ch]
        for i in 0..<frameLength {
            sum += samples[i] * samples[i]
        }
    }
    let rms = sqrt(sum / Float(frameLength * channelCount))
    // dB → 0..1 归一化
    let db = 20 * log10(max(rms, 0.000_01))
    let normalized = max(0, (db + 60) / 60)  // -60dB ~ 0dB → 0 ~ 1
    return Float(min(1.0, normalized))
}
```

电平更新走主线程 `await MainActor.run { self.micLevel = level }`，60 fps 足够。

### 6.5 状态机

```
                startRecording
        ┌────────────────────────────┐
        ▼                            │
     [Idle] ────────────► [Preparing]│
        ▲                            │
        │                            ▼
   cancelRecording                [Countdown] (optional)
        ▲                            │
        │                            ▼
   [Cancelled]                [Recording]
        ▲                   ┌──────┴───────┐
        │                   │              │
        │             pauseRecording  resumeRecording
        │                   │              │
        │                   ▼              │
        │             [Paused] ───────────┘
        │                   │
        │                   ▼
        │             stopRecording
        │                   │
        └────────────── [Saving]
                                │
                                ▼
                             [Idle] + 返回 URL
```

### 6.6 倒计时

直接复用 `ScreenRecordingEngine` 已有的 `RecordingCountdownWindow`：

```swift
let countdown = RecordingCountdownWindow(
    seconds: settings.audioRecordCountdown,
    onFinished: { continuation.resume() },
    onCancelled: { continuation.resume(throwing: AudioRecordingError.userCancelled) }
)
```

参数面板（开始前选源/参数）**不显示**：与录屏不同，录音没有"选区/窗口/全屏"概念，开始就开录。倒计时是唯一的前置交互。

### 6.7 文件命名

```swift
let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
let filename = "SnapClick_录音_\(formatter.string(from: Date()))"
let fileURL = saveDir.appendingPathComponent(filename).appendingPathExtension("m4a")
```

> 与录屏命名一致，便于用户在 Finder 中区分。

---

## 7. 设置项（AppSettings 扩展）

```swift
// MARK: - 音频录音设置
@AppStorage("audioRecordSavePath")     var audioRecordSavePath: String = "~/Desktop"
@AppStorage("audioRecordQuality")      var audioRecordQuality: String = "标准"      // 经济 / 标准 / 高质量
@AppStorage("audioRecordSampleRate")   var audioRecordSampleRate: Int = 44100     // 44100 / 48000
@AppStorage("audioRecordChannels")     var audioRecordChannels: Int = 2           // 1 / 2
@AppStorage("audioRecordMicrophone")   var audioRecordMicrophone: String = "内置麦克风"
@AppStorage("audioRecordSystemAudio")  var audioRecordSystemAudio: Bool = true
@AppStorage("audioRecordCountdown")    var audioRecordCountdown: Int = 3          // 0/3/5/10

// MARK: - 音频录音快捷键
@AppStorage("hotkeyAudioRecord")       var hotkeyAudioRecord: String = "ctrl+shift+m"
@AppStorage("hotkeyStopAudioRecord")   var hotkeyStopAudioRecord: String = "ctrl+shift+n"
```

> **不新增**格式选择（v1.0 锁死 M4A），与录屏"v1.0 锁死 HEVC"的设计哲学一致：先求稳，再扩展。

---

## 8. 快捷键

| 动作 | 默认快捷键 | 冲突检测 |
|------|-----------|---------|
| 开始录音 | `Ctrl+Shift+M` | M = Microphone |
| 停止录音 | `Ctrl+Shift+N` | N = sto**N** |

- 与现有快捷键无冲突（录屏用 R/F/S，截图用 A/S/W/C/L/P，取色用 C）
- 复用 `HotkeyManager` 的 `registerAll()` 流程，在录音启动/停止时调用 `AudioRecordingEngine.shared.startRecording(...)` / `.stopRecording()`

> **快捷键与录屏的复用**：`hotkeyStopRecording`（Ctrl+Shift+S）目前是"停止录屏"，**不能**改成"停止录音"。所以单独再开一组快捷键，避免动作语义冲突。

---

## 9. 权限

### 9.1 麦克风权限（TCC）

新增 `PermissionManager` 方法：

```swift
func checkMicrophonePermission() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
}

func requestMicrophonePermission() {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
            self.hasMicrophonePermission = granted
        }
    }
}
```

启动时：

- **仅麦克风模式** → 必须有麦克风权限
- **麦克风 + 系统音频** → 必须有麦克风权限（系统音频走 SCK，不需屏幕录制权限）
- **仅系统音频** → 不需任何权限

权限缺失时弹与录屏一致的 NSAlert：

```
需要麦克风权限
请在系统设置 → 隐私与安全性 → 麦克风中授权 SnapClick。
[去设置]  [取消]
```

### 9.2 Info.plist

```xml
<key>NSMicrophoneUsageDescription</key>
<string>SnapClick 需要使用麦克风来录制您的语音和会议音频。</string>
```

> ⚠️ **必填项**，未配置时 macOS 13+ 会闪退（TCC 强制）。

### 9.3 欢迎页

`WelcomeView` 权限卡片组（4 张 → 5 张）：

- 屏幕录制
- 辅助功能
- Finder 扩展
- 完全磁盘访问（可选）
- **麦克风**（新增，必需项）

---

## 10. 文件命名与保存

- **文件名**：`SnapClick_录音_yyyy-MM-dd_HH.mm.ss.m4a`
- **保存路径**：默认 `~/Desktop`，可在设置页改
- **路径不存在时**自动 `createDirectory(withIntermediateDirectories: true)`
- **同名冲突时**：在文件名后追加 `_2`/`_3`/...（避免覆盖）

保存成功后：

- 沿用录屏的 `NSWorkspace.shared.activateFileViewerSelecting([fileURL])`（**不要**用 `open -R` 替代，因为录音不触发 TCC 弹窗）
- 发送 `audioRecordingDidStop` 通知，状态栏恢复

---

## 11. 错误处理

新增 `AudioRecordingError`：

```swift
enum AudioRecordingError: LocalizedError {
    case permissionDenied(String)      // 缺哪个权限就传哪个名字
    case noMicrophoneAvailable
    case systemAudioNotSupported       // macOS < 13
    case alreadyRecording
    case notRecording
    case engineStartFailed(String)
    case writeFailed(String)
    case noAudioData
    case userCancelled

    var errorDescription: String? { ... }
}
```

- 错误**不弹窗**，仅在状态栏菜单中以 `NSAlert` 弹出（与录屏一致）
- 录音引擎失败时自动 cleanup 资源（writer 关闭、session stop、文件删除）

---

## 12. 国际化

在 `AppSettings.swift` 的 `LanguageManager.translations` 中新增以下键的 `en` / `ja` 翻译：

| 键（中文） | English | 日本語 |
|-----------|---------|--------|
| 音频录制 | Audio Recording | 音声録音 |
| 开始录音 | Start Recording | 録音開始 |
| 停止录音 | Stop Recording | 録音停止 |
| 取消录音 | Cancel Recording | 録音をキャンセル |
| 音频源 | Audio Source | 音声ソース |
| 系统音频 | System Audio | システム音声 |
| 输出格式 | Output Format | 出力形式 |
| 质量 | Quality | 音質 |
| 采样率 | Sample Rate | サンプリングレート |
| 声道 | Channels | チャンネル |
| 立体声 | Stereo | ステレオ |
| 单声道 | Mono | モノラル |
| 标准 | Standard | 標準 |
| 高质量 | High Quality | 高品質 |
| 经济 | Economy | エコノミー |
| 麦克风权限 | Microphone Permission | マイクの権限 |
| 请在系统设置 → 隐私与安全性 → 麦克风中授权 SnapClick | Please authorize SnapClick in System Settings → Privacy & Security → Microphone. | システム設定 → プライバシーとセキュリティ → マイク で SnapClick を承認してください。 |
| 录音中... | Recording... | 録音中... |
| 录音已暂停 | Recording Paused | 録音一時停止中 |

---

## 13. 实施步骤

> 总计约 5 个 commit，可分阶段 review。

### Phase 1：基础引擎（1 个 commit）

1. `AudioQualitySettings.swift`（纯枚举/常量）
2. `AudioRecordingEngine.swift`（核心引擎，单麦克风，不含系统音频）
3. `AppSettings.swift` 新增设置项
4. `AudioLevelMeter.swift`（可复用的电平柱组件）
5. `AudioRecordingPreviewCard.swift`（设置页预览）
6. `AudioRecordingSettingsView.swift`（设置页主体）
7. `MainWindow.swift` 增加 `audioRecording` 导航 + `SettingsDestination` case
8. **构建验证**：`xcodebuild -project SnapClick.xcodeproj -scheme SnapClick -configuration Debug build`

### Phase 2：UI 集成（1 个 commit）

1. `AudioRecordingHUDWindow.swift`（含电平柱）
2. `StatusBarController.swift` 菜单项 + 录音中动态菜单
3. `HotkeyManager.swift` 注册 `hotkeyAudioRecord` / `hotkeyStopAudioRecord`
4. `AppDelegate.swift` 注册 `audioRecordingDidStart/Stop` 通知
5. **构建验证**

### Phase 3：系统音频 + 权限（1 个 commit）

1. `AudioRecordingEngine` 增加 SCK 系统音频采集
2. `PermissionManager` 增加 `hasMicrophonePermission` + `requestMicrophonePermission()`
3. `Info.plist` 增加 `NSMicrophoneUsageDescription`
4. `WelcomeView` 增加麦克风权限卡
5. **构建验证**

### Phase 4：多语言 + 打磨（1 个 commit）

1. `AppSettings.swift` 增加 en/ja 翻译键
2. 倒计时 / 文件命名 / 错误提示文案 review
3. **构建验证**

### Phase 5：手动冒烟测试（不写代码）

参见 §15 测试计划。

---

## 14. 风险与权衡

| 风险 | 影响 | 缓解 |
|------|------|------|
| macOS < 13 不支持系统音频 | 部分老系统用户无法用 | Picker 中系统音频选项灰显 + Tooltip 提示 |
| SCK 系统音频 + 视频流带宽浪费 | 性能影响 | SCK `width=2 height=2` 已尽量小；不订阅 `.screen` output；测试对比内存占用 |
| 实时电平更新主线程负担 | UI 卡顿 | 60fps 节流到 30fps，smoothing 0.2 系数 |
| 多音轨 m4a 部分播放器不支持切换 | 用户困惑 | QuickTime / iTunes / GarageBand 全部支持；其他播放器回退到首音轨（无错误） |
| 麦克风热插拔导致录音中断 | 录音失败 | `AVCaptureSession` 监听 `wasDisconnected` 通知，自动 stopRecording + 提示 |
| 静音设备被选为默认 | 录音没声音 | 设置页加"测试麦克风"按钮，点击后录 2 秒并显示电平 |
| 状态栏菜单与录屏状态栏菜单冲突 | 录屏 + 录音不能并行 | v1.0 **显式禁止并行**：录音中点击"开始录屏"会弹 alert "音频录音进行中，请先停止"；反之亦然 |
| 快捷键 `Ctrl+Shift+M` 与输入法冲突 | 部分中文输入法抢键 | 用户可在设置页改键；M 在 macOS 习惯上是 Microphone 语义 |

---

## 15. 测试计划

### 15.1 单元测试（可选，v1.0 不强制）

- `AudioQualitySettings` 档位映射
- `AudioLevelMeter` RMS 计算（给定 sin 波 → 期望电平）
- 路径展开（`~/Desktop` → `/Users/.../Desktop`）
- 文件名冲突重命名

### 15.2 手动冒烟测试清单

#### A. 权限
- [ ] 全新安装 → 启动 → 欢迎页 5 张权限卡显示
- [ ] 拒绝麦克风权限 → 录音按钮变灰 + 提示
- [ ] 同意后刷新 → 权限状态变绿

#### B. 基本录音
- [ ] `Ctrl+Shift+M` 启动 → 倒计时 3 秒 → 开始录音
- [ ] HUD 显示红色闪烁 + 计时器递增
- [ ] HUD 电平柱随声音起伏
- [ ] `Ctrl+Shift+N` 停止 → Finder 高亮 .m4a 文件
- [ ] QuickTime 打开 .m4a → 正常播放

#### C. 音频源
- [ ] 仅麦克风：断开外置 USB → 自动 fallback 到内置麦克风
- [ ] 麦克风 + 系统音频：同时播放 Apple Music + 对着麦克风说话 → 录音文件两条音轨均正常
- [ ] 仅系统音频：静音下录音仍有 Apple Music 声音
- [ ] macOS 12 设备：系统音频 Picker 灰显

#### D. 控件
- [ ] 暂停 → 计时器停止 → 电平柱归零 → 状态栏图标变 `pause.circle`
- [ ] 继续 → 计时器接着走
- [ ] 停止 → 文件保存 → 状态栏恢复
- [ ] 取消 → 弹确认 → 文件被删除
- [ ] 拖动 HUD → 释放后位置被记住

#### E. 状态栏
- [ ] 录音中点开状态栏 → 看到动态菜单（暂停/停止/取消）
- [ ] 录音结束后 → 恢复常规菜单
- [ ] 状态栏图标在录屏/录音之间视觉区分清晰

#### F. 异常
- [ ] 录音中拔掉麦克风 → 自动停止 + 弹错误提示
- [ ] 保存路径被删 → 自动创建
- [ ] 磁盘空间不足 → 提示
- [ ] 同时启动录屏 → 弹 alert "音频录音进行中"
- [ ] 反之：录屏中启动录音 → 同样弹 alert

#### G. 国际化
- [ ] 切到 English → 所有新文案正确
- [ ] 切到 日本語 → 所有新文案正确

#### H. 性能
- [ ] 录音 1 小时内存稳定（不增长超过 50MB）
- [ ] CPU 占用 < 5%（空闲时）
- [ ] 录屏 + 录音不可同时（已禁止，但需验证不卡死）

---

## 16. 后续扩展方向（v1.x 路线图）

- v1.1：MP3 / WAV 格式可选
- v1.1：实时波形显示（替换电平柱）
- v1.2：录音内嵌章节标记（按 ⌘1/2/3 插入）
- v1.2：录音转写（调用 Whisper 本地模型）
- v1.3：与"语音备忘录"互通
- v1.3：M4A 元数据写入（标题/作者/封面）
- v1.4：实时噪声抑制
- v1.5：iCloud 同步录音文件

---

## 17. 附录

### 17.1 关键依赖

- `AVFoundation`（`AVAssetWriter` / `AVCaptureSession` / `AVAudioPCMBuffer`）
- `ScreenCaptureKit`（macOS 13+ 系统音频）
- `AppKit`（HUD 窗口 + NSAlert）
- `SwiftUI`（设置页 + 电平柱组件）

### 17.2 不依赖

- ❌ 第三方库（纯系统 API）
- ❌ 沙盒（沿用主 App 不开沙盒策略）

### 17.3 命名约定（与项目一致）

- 引擎后缀 `Engine`：`ScreenRecordingEngine` → `AudioRecordingEngine`
- HUD 后缀 `HUDWindow`：`RecordingHUDWindow` → `AudioRecordingHUDWindow`
- 设置后缀 `SettingsView`：直接命名 `AudioRecordingSettingsView`
- 通知前缀：`audioRecordingDidStart` / `audioRecordingDidStop`

### 17.4 与现有录制功能的关键差异表

| 维度 | 屏幕录制 | 音频录音（新增） |
|------|---------|----------------|
| 视频流 | ✅ | ❌ |
| 系统音频 | ✅（随视频） | ✅（独立，无视频） |
| 麦克风 | ✅ | ✅ |
| 输出文件 | .mov / .mp4 | .m4a |
| 选区概念 | ✅（区域/窗口/全屏） | ❌（无选区） |
| 选区覆盖层 | ✅ | ❌（仅倒计时） |
| HUD 大小 | 232×44 | 260×56（多一条电平柱） |
| 状态栏图标 | dot.circle.fill | mic.fill |
| 沙盒/屏幕录制权限 | 必需 | 不必需 |
| 麦克风权限 | 可选 | 必需 |
| 快捷键 | Ctrl+Shift+R/F/S | Ctrl+Shift+M/N |

---

**文档结束。** 实施前请 review：
1. 文件结构与命名是否接受
2. 设置页布局是否符合视觉一致
3. HUD 电平柱 vs 现有 HUD 风格是否冲突
4. 状态栏并行禁止策略是否可接受
5. 翻译键列表是否完整
