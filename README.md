<div align="center">

# SnapClick

### macOS 效率增强工具 — 右键增强 · 截图标注 · 屏幕贴图 · 智能取色

[![Version](https://img.shields.io/github/v/release/Tyeerth/SnapClick?color=blue&label=version)](https://github.com/Tyeerth/SnapClick/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](https://github.com/Tyeerth/SnapClick/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-green)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/Tyeerth/SnapClick/total)](https://github.com/Tyeerth/SnapClick/releases/latest)

一款专为 macOS 打造的高级效率增强工具，将 Finder 菜单增强、高级截图标注、屏幕贴图、智能取色等常用效率功能一体化汇总，以纯原生 Swift 架构呈现，为您提供丝滑般尊贵的使用体验。

[功能特性](#-功能特性) · [下载安装](#-下载安装) · [编译构建](#-编译构建) · [参与贡献](#-参与贡献)

</div>

---

## ✨ 功能特性

### 🔧 Finder 右键菜单增强

- **新建常用文件** — 右键一键新建 `.txt`、`.md`、`.docx`、`.xlsx`、`.pptx`、`.html`、`.css`、`.js`、`.py`、`.sh` 等多种格式文件，支持自定义模板，新建后自动进入重命名状态
- **文件剪切与粘贴** — 比原生更简单的高效剪切粘贴流，支持跨目录快速移动
- **快速移动/复制到** — 支持添加常用目录，一键归档
- **路径高级拷贝** — 支持拷贝完整路径、仅文件名或 POSIX 规范路径
- **常用终端/编辑器快捷打开** — 右键在当前目录拉起 Terminal、iTerm2、VS Code、Sublime Text 或 Xcode
- **文件哈希校验** — 快速计算 MD5、SHA1、SHA256
- **快捷隔空投送** — 一键对选中文件发起 AirDrop

### 📸 高级截图与标注

- **区域截图 & 智能窗口识别** — 拖拽自由选区、自动贴合悬停窗口
- **延迟全屏截图** — 自定义倒计时，捕捉下拉菜单等过渡态
- **高级标注编辑器** — 矩形、椭圆、直线、画笔、高亮蒙层、像素级马赛克、智能步骤序号
- **截图美化包装** — 毛玻璃大阴影、自定义圆角

### 📌 屏幕贴图与智能取色

- **多视窗屏幕贴图** — 透明无边框悬浮固定，全局置顶、跨 Space 跟随、透明度调节
- **16x 精准放大镜取色** — 一键拷贝 Hex、RGB、HSL、Swift (NSColor) 或 CSS 格式颜色代码

---

## � 下载安装

### 方式一：直接下载安装包（推荐）

前往 [Releases 页面](https://github.com/Tyeerth/SnapClick/releases/latest) 下载最新的 `.dmg` 安装包，双击打开后拖拽到应用程序文件夹即可。

<a href="https://github.com/Tyeerth/SnapClick/releases/latest">
  <img src="https://img.shields.io/badge/Download-Latest%20Release-blue?style=for-the-badge&logo=github" alt="Download Latest Release">
</a>

### 方式二：从源码编译

请参阅下方 [编译构建](#-编译构建) 章节。

### ⚠️ 首次运行授权

首次启动时，App 会引导您授予以下权限：

1. **屏幕录制权限** — 用于截图和放大镜取色
2. **辅助功能权限** — 用于捕获全局快捷键
3. **Finder 扩展启用** — 在「系统设置 → 通用 → 登录项与扩展 → Finder 扩展」中勾选 `FinderExtension`

---

## �🛠️ 技术栈

| 技术 | 说明 |
|------|------|
| Swift 5.9+ | 开发语言 |
| SwiftUI + AppKit | 混合架构，遵循 macOS Modern Design 规范 |
| ScreenCaptureKit | 高性能屏幕捕获 |
| FinderSync | 原生 Finder 进程插件 |
| CGEventTap | 全局快捷键高精度拦截 |
| AVFoundation & CryptoKit | 多媒体处理与加密哈希 |

---

## � 编译构建

### 前置要求

- macOS 13.0 (Ventura) 及以上
- Xcode 15.0 及以上
- Apple Developer Account（用于签名）

### 构建步骤

1. **克隆仓库**
   ```bash
   git clone https://github.com/Tyeerth/SnapClick.git
   cd SnapClick
   ```

2. **打开项目**
   ```bash
   open SnapClick.xcodeproj
   ```

3. **配置签名** — 在 Xcode 的 `Signing & Capabilities` 中为以下两个 Target 配置开发团队：
   - `SnapClick`（主 App，Bundle ID: `com.snapclick.app`，非沙盒模式）
   - `FinderExtension`（右键菜单插件，Bundle ID: `com.snapclick.app.FinderExtension`，沙盒模式，绑定 App Group: `group.com.snapclick.shared`）

4. **构建运行** — 选择 Scheme `SnapClick` → 构建目标 `My Mac` → 运行 (⌘R)

---

## 📂 项目结构

```
SnapClick/
├── Shared/                          # 主 App 与 FinderExtension 共享模块
│   ├── AppGroup.swift               # App Group 共享 UserDefaults 桥接
│   └── FileOperations.swift         # 文件操作核心（剪切/粘贴/新建/哈希/显示）
│
├── FinderExtension/                 # Finder 右键插件
│   ├── FinderSync.swift             # FIFinderSync 生命周期控制器
│   ├── MenuBuilder.swift            # 动态右键菜单构造引擎
│   ├── FinderExtension.entitlements
│   └── Info.plist
│
└── SnapClick/                       # 主 App
    ├── App/
    │   ├── SnapClickApp.swift       # SwiftUI 生命周期入口
    │   └── AppDelegate.swift        # AppKit 周期管理、命令分发
    ├── Core/
    │   ├── AppSettings.swift         # 全局 @AppStorage 配置项
    │   ├── PermissionManager.swift   # 系统权限检测与引导
    │   └── HotkeyManager.swift       # CGEventTap 全局快捷键
    ├── UI/
    │   ├── MainWindow.swift          # SwiftUI 多栏设置中心
    │   ├── WelcomeView.swift         # 首次启动授权引导页
    │   └── StatusBarController.swift # 菜单栏图标与下拉菜单
    └── Modules/
        ├── Screenshot/               # 截图与标注模块
        ├── PinColor/                 # 贴图与取色模块
        └── RightClick/               # 右键菜单设置模块
```

---

## ⚠️ 开发注意事项

1. **非沙盒特权** — 主 App 禁用 Sandbox，这是实现全局键盘监听 (CGEventTap) 及原生拉起外部软件的必要前提
2. **Finder 扩展沙盒** — `FinderExtension` 必须处于沙盒环境，与主 App 通过 App Group 共享数据
3. **IPC 通信** — FinderExtension 通过命名剪贴板 (NSPasteboard) 与主 App 通信，避免触发 TCC 权限弹窗
4. **文件显示** — 使用 `/usr/bin/open -R` 替代 `NSWorkspace.activateFileViewerSelecting` 避免 Apple Event 权限弹窗

---

## 🤝 参与贡献

欢迎贡献代码！请遵循以下流程：

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

---

## 📄 开源协议

本项目基于 [Apache License 2.0](LICENSE) 开源。
