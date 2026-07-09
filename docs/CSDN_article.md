---
title: SnapClick —— 一款纯原生 Swift 打造的 macOS 效率工具集（截图 / 录屏 / 取色 / 右键增强）
categories:
  - macOS
  - 开源项目
  - 效率工具
tags:
  - macOS
  - Swift
  - SwiftUI
  - AppKit
  - ScreenCaptureKit
  - FinderSync
  - 截图
  - 录屏
  - 取色器
  - 右键菜单
---

# SnapClick —— 一款纯原生 Swift 打造的 macOS 效率工具集

> 一把瑞士军刀，搞定 macOS 日常高频效率场景：Finder 右键增强、截图标注、长截图、屏幕录制、屏幕贴图、像素取色。

![SnapClick 整体介绍](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/introduce.png)

## 一、为什么做这个项目？

市面上的 macOS 效率工具不少，但真正做到"纯原生、零卡顿、零 Electron 包袱"的屈指可数。SnapClick 的定位很明确：

- **纯 Swift + SwiftUI + AppKit**：不套任何 Web 壳，启动即原生体验
- **Apple 官方框架为底座**：截图/录屏全部走 `ScreenCaptureKit`，硬件加速
- **零系统资源浪费**：后台常驻 < 80 MB
- **中文用户体验优先**：i18n、快捷键、未签名应用的"保姆级"打开指引

## 二、六大核心功能

### 1️⃣ Finder 右键菜单增强（RClick）

- 一键新建 `.txt` / `.md` / `.docx` / `.xlsx` / `.html` / `.css` / `.js` / `.py` 等文件，支持自定义模板
- 跨目录剪切粘贴
- 常用目录快速归档
- 一键拉起 Terminal / iTerm2 / VS Code / Warp / Xcode

实现要点：通过 `FinderSync Extension` 拦截右键事件，主 App 负责执行，App Group + Darwin Notification 跨进程通信。

### 2️⃣ 高级截图与标注

- ⌥⇧A 自由选区 / 窗口吸附
- **长截图**：滚动网页/长文档无缝拼接
- 标注工具栏：矩形、椭圆、直线、箭头、文字、画笔、高亮蒙层、步骤序号、马赛克
- 美化包装：毛玻璃阴影、0-32px 自定义圆角

### 3️⃣ 高性能屏幕录制

- 基于 `ScreenCaptureKit`（macOS 12.3+ 官方框架），硬件加速
- 三种录屏模式：自定义区域 / 全屏 / 指定应用窗口
- 支持 30/60/120 FPS，H.264 / HEVC 编码
- **双音轨独立录制**：系统内录 + 麦克风分轨保存
- HUD 悬浮控制条：暂停 / 继续 / 停止 / 取消

### 4️⃣ 屏幕贴图（Pin Window）

- ⌥⇧P 一键置顶任意图片
- 跨 Space 跟随
- 滚轮无级调节透明度，双击缩放

### 5️⃣ 像素取色放大镜

- 16× 像素级放大镜
- HEX / RGB / HSL / NSColor / CSS 多格式一键复制
- 20 条取色历史记录

### 6️⃣ 玻璃面板主设置窗口

- 毛玻璃材质 + 可调透明度
- 多 Tab 分类管理
- 全键盘可达

## 三、技术架构亮点

| 模块 | 技术选型 | 说明 |
|------|----------|------|
| UI 主框架 | SwiftUI + AppKit 混编 | SwiftUI 写界面，AppKit 处理窗口/事件 |
| 截图/录屏 | ScreenCaptureKit | 苹果官方硬件加速框架 |
| Finder 扩展 | FinderSync Extension | 沙盒运行，IPC 委托主 App |
| 进程通信 | App Group UserDefaults + Darwin Notification | 轻量、稳定 |
| 快捷键 | Carbon HotKey API | 替代易被拦截的 NSEvent.addGlobalMonitor |
| 颜色拾取 | CoreGraphics + CGDisplay | 像素级精度 |
| 多语言 | 本地化 .strings | 中 / 英 / 日 |

**架构原则：**

1. 主 App 与 FinderExtension **完全隔离**，扩展只负责"传话"，所有文件操作回到主 App 执行
2. 涉及 TCC（隐私权限）的 API（`NSWorkspace.urlForApplication` 等）全部下沉到主 App，扩展绝不调用
3. 用 `/usr/bin/open -R` 替代 `activateFileViewerSelecting`，避免 Apple Event 弹窗

## 四、效果展示

### 主设置界面

![主设置界面](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/hero_screenshot.png)

### 右键菜单增强

![右键菜单](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/right_click_screenshot.png)

### 截图标注 + 长截图

![截图标注](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/screenshot_editor_screenshot.png)
![长截图](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/long_screenshot_preview.png)

### 录屏 HUD

![录屏](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/recording_overlay.png)

### 屏幕贴图 + 取色

![贴图](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/pin_window_overlay.png)
![取色](https://raw.githubusercontent.com/Tyeerth/SnapClick/main/docs/assets/color_picker_overlay.png)

## 五、5 分钟跑起来

```bash
# 1. 克隆
git clone https://github.com/Tyeerth/SnapClick.git
cd SnapClick

# 2. 用 Xcode 打开
open SnapClick.xcodeproj

# 3. 在 Signing & Capabilities 里为两个 Target 配置你的开发者账号：
#    - SnapClick           (com.snapclick.app)               非沙盒
#    - FinderExtension     (com.snapclick.app.FinderExtension) 沙盒 + App Group
```

启动后，按 ⌥⇧A 调起截图、⌥⇧P 贴图、⌥⇧C 取色，右键任意 Finder 文件即可看到增强菜单。

> ⚠️ 未签名应用首次打开会被 Gatekeeper 拦截，参考 README 里的 `xattr -dr com.apple.quarantine` 解决方案。

## 六、未来规划

- [ ] 录屏支持鼠标点击高亮 + 键盘按键回显
- [ ] 标注工具支持图层管理 + 撤销历史面板
- [ ] 取色器支持取色板调色（HSL 滑杆微调）
- [ ] 截图 OCR 文字识别（Vision 框架）
- [ ] 全局快捷动作工作流（类似 Alfred）

## 七、写在最后

做这个项目的初衷很简单：**macOS 用户值得一个不臃肿、不打扰、真正好用的效率工具集**。

如果你也喜欢它，欢迎：

- ⭐ Star：<https://github.com/Tyeerth/SnapClick>
- 🐛 提 Issue：反馈 bug 或新功能想法
- 🍴 Fork & PR：一起把它做得更好

> 项目持续更新中，欢迎评论区交流你心目中的"完美 macOS 效率工具"长什么样 🚀
