---
title: SnapClick 2.x 更新速递：右键秒开 / 多编辑器打开 / 录屏 HUD / 毛玻璃透明度
categories:
  - macOS
  - 开源项目
  - 版本更新
tags:
  - macOS
  - Swift
  - SwiftUI
  - 效率工具
  - 版本更新
  - NSCache
  - ScreenCaptureKit
  - NSVisualEffectView
---

# SnapClick 2.x 更新速递：右键秒开 / 多编辑器打开 / 录屏 HUD / 毛玻璃透明度

> 本次更新围绕"日常使用体验"做了四项重点打磨，让 Finder 右键更顺滑、录屏控制更专业、设置窗口更精致。

![SnapClick 整体介绍](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/introduce.png)

---

## 🚀 一、右键启动速度优化

之前打开 Finder 右键菜单有偶发卡顿，根因在于每次弹菜单都要同步调用 `NSWorkspace.icon(for:)` 拉图标。2.x 重构后改为 **NSCache 内存缓存** + **资源变更时主动失效**。

### 关键改动

[`FinderExtension/MenuBuilder.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/FinderExtension/MenuBuilder.swift#L341-L406)：

```swift
// 缓存开发工具图标、目录图标和 SF Symbol
// 避免每次右键时同步调用 NSWorkspace.icon(for:)
// 资源变更时主动清空内存缓存
```

### 实际效果

- 首次打开右键菜单：~50ms（构建缓存）
- 后续每次右键：**< 5ms**（命中缓存）
- 安装/卸载新应用后，缓存自动失效重建

---

## 💻 二、默认在终端打开 + 多编辑器选择

右键菜单顶部固定"在终端中打开"作为默认行为，下面挂一个"用其他软件打开"子菜单，**自动识别系统中已安装的编辑器/IDE**。

### 关键改动

[`FinderExtension/MenuBuilder.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/FinderExtension/MenuBuilder.swift#L21-L34)：

```swift
// 1. 固定插入"在终端中打开"项（默认行为）
// 2. 追加"用其他软件打开"子菜单
// 3. 从缓存的开发工具列表动态生成菜单项
```

### 支持的编辑器（自动检测）

| 编辑器 | Bundle ID |
|--------|-----------|
| Terminal | `com.apple.Terminal` |
| iTerm2 | `com.googlecode.iterm2` |
| Warp | `dev.warp.Warp-Stable` |
| VS Code | `com.microsoft.VSCode` |
| Cursor | `com.todesktop.230313mzl4w4u92` |
| Xcode | `com.apple.dt.Xcode` |
| WebStorm / GoLand / PyCharm 等 JetBrains 全家桶 | 自动识别 |

> 安装/卸载编辑器后，刷新右键菜单即可看到最新列表。

---

## 🎥 三、录屏 HUD 控制条 + 停止快捷键

录屏过程中浮出一个独立的 HUD 控制条，无需切回主窗口就能完成所有操作。

### HUD 布局（从左到右）

- 🔴 录制指示灯（呼吸动画）
- ⏱ 录制时长（`mm:ss` 格式）
- ⏸ 暂停 / ▶ 继续
- ⏹ 停止并保存
- ❌ 取消（不保存，触发二次确认）

### 停止录制全局快捷键

[`SnapClick/Core/AppSettings.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick/Core/AppSettings.swift#L202-L204)：

```swift
hotkeyStopRecording = "ctrl+shift+s"  // 默认值，可在设置中修改
```

按 `⌃⇧S` 即可在任何场景下停止当前录制，录屏文件会自动弹出 Finder 选中位置。

### 关键实现

- [`SnapClick/Modules/Recording/RecordingHUDWindow.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick/Modules/Recording/RecordingHUDWindow.swift#L9-L17) — `onPauseResume / onStop / onCancel` 三个回调
- [`SnapClick/Core/HotkeyManager.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick/Core/HotkeyManager.swift#L109-L119) — 全局快捷键注册，触发后调 `ScreenRecordingEngine.shared.stopRecording()`

---

## ✨ 四、主窗口毛玻璃面板 + 透明度可调

主设置窗口全面支持 macOS 原生毛玻璃材质，并且**用户可以自由调节透明度**（30% ~ 100%）。

### 关键实现

- [`SnapClick/UI/MainWindow.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick/UI/MainWindow.swift#L4-L20) — `VisualEffectView` 是 `NSVisualEffectView` 的 SwiftUI 包装
- [`SnapClick/UI/MainWindow.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick/UI/MainWindow.swift#L408-L424) — 侧边栏根据 `enableGlassEffect` 切换 `VisualEffectView(contentBackground, withinWindow)` 与纯色背景
- [`SnapClick/UI/MainWindow.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick/UI/MainWindow.swift#L306-L331) — `settings.enableGlassEffect` + `settings.glassOpacity` 控制外层窗口背景

### 设置项

[`SnapClick/Core/AppSettings.swift`](file:///Users/tyeerth/Documents/MAC_software/SnapClick/SnapClick/Core/AppSettings.swift#L115-L129)：

```swift
enableGlassEffect: Bool = true
glassOpacity: Double = 0.85  // 范围 0.3 ~ 1.0
```

### 使用方法

设置 → 外观 → 开启"毛玻璃效果" → 出现"面板透明度"滑块 → 拖动即可实时预览。

![主设置界面](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/hero_screenshot.png)

---

## 📊 本次更新总览

| 模块 | 优化点 | 关键文件 |
|------|--------|----------|
| 右键菜单 | NSCache 缓存图标，秒级响应 | `FinderExtension/MenuBuilder.swift` |
| 右键菜单 | 终端默认 + 编辑器多选 | `FinderExtension/MenuBuilder.swift` |
| 录屏 | HUD 控制条（暂停/停止/取消） | `Modules/Recording/RecordingHUDWindow.swift` |
| 录屏 | ⌃⇧S 停止快捷键 | `Core/HotkeyManager.swift` |
| 主窗口 | 毛玻璃材质 + 透明度滑块 | `UI/MainWindow.swift` + `Core/AppSettings.swift` |

---

## 🛠 升级方式

```bash
git pull
open SnapClick.xcodeproj
# ⌘R 运行即可
```

或下载最新 [Release](https://github.com/Tyeerth/SnapClick/releases/latest) 安装包。

---

## 💡 后续规划

- [ ] 录屏支持鼠标点击高亮 + 键盘按键回显
- [ ] 标注工具图层管理
- [ ] 截图 OCR 文字识别
- [ ] 全局快捷动作工作流（Alfred 风格）

---

> ⭐ 如果觉得有用，欢迎到 [GitHub](https://github.com/Tyeerth/SnapClick) 给个 Star！
>
> 📮 有任何建议或 Bug 反馈，欢迎评论区交流或加入微信交流群（二维码见 README）
