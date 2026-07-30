# 程序员狂喜！这款开源 macOS 神器 v1.2 大升级：侧边栏直接用上 Apple WWDC2025 同款 Liquid Glass 视觉，右键新建 Office 文件再也不"损坏"了

> 关键词：macOS 效率工具、Liquid Glass、Finder 右键增强、SwiftUI 开源、ScreenCaptureKit 录屏、屏幕取色、贴图、Swift 5.9、macOS 13、SnapClick、开源、免费、屏幕截图标注、长截图

## 一、前言：又肝了两个月，SnapClick v1.2 终于来了

距离上次发版隔了两个月，SnapClick v1.2 终于在 GitHub 正式发布。这一版本最大的变化是两件事：

1. **侧边栏全面拥抱 Apple WWDC 2025 的 Liquid Glass 设计语言**——半透明毛玻璃、悬浮胶囊导航、发光选中态，跟 macOS Tahoe / Apple Music 一个味儿。
2. **彻底修掉了一个让无数用户抓狂的 Bug**：右键新建 Word / Excel / PPT 文件后双击打开会弹"文件格式或文件扩展名无效"。

如果你已经装了老版本，**强烈建议立刻升级**。本文带你逐一拆解 v1.2 的所有更新点，文末给出 GitHub 项目地址与最新版 `.dmg` 下载链接。

![SnapClick v1.2 主界面-浅色模式](./docs/assets/hero_screenshot.png)

![SnapClick v1.2 主界面-暗黑模式](./docs/assets/hero_dark_screenshot.png)

---

## 二、最抢眼的更新：Apple Liquid Glass 侧边栏

v1.2 这次直接对标 Apple 自己在 WWDC 2025 推的 Liquid Glass 设计语言，整个侧边栏从底层重写：

![应用整体介绍动图](./docs/assets/app_introduction.gif)

### 2.1 侧边栏：半透明毛玻璃 + 1px 白色高光描边

- **材质**：自定义 `NSVisualEffectView` sidebar 材质，背景透明度 20–30%，背景模糊 40–60px，**能透出底下桌面的颜色**（毛玻璃的精髓）。
- **描边**：抛弃老版本那种"灰色大块背景 + 粗黑描边"，换成 1px 白色高光描边，干净利落。
- **圆角**：侧边栏四角 28–32px 大圆角，跟 macOS 系统窗口保持一致。

### 2.2 macOS 交通灯按钮嵌进侧边栏

以前窗口控制按钮挤在标题栏，视觉上是两个区域。现在 **macOS 红黄绿三颗按钮直接嵌进侧边栏顶部**，跟 Logo / 导航项保持统一的 ~20px 呼吸间距，整体感拉满。

### 2.3 导航项：悬浮胶囊 + 发光选中态

- **默认状态**：完全透明，跟背景融为一体
- **Hover 状态**：浮现淡淡的玻璃高光
- **选中状态**：用**发光 Liquid Glass 胶囊**取代旧版的蓝灰矩形背景，跟 macOS Tahoe 系统设置选中态一个味儿

### 2.4 SF Symbols 单色图标

所有导航图标统一替换为 SF Symbols 单色风格，**告别粗黑线条的拟物图标**。间距也增大了，整体留白更克制，是 Apple 一直强调的"内容为王"思路。

> 💡 技术细节：v1.2 把主窗口从自定义 `NSWindow + HStack` 迁移到 **SwiftUI `Window` scene + `NavigationSplitView`**，由系统管理原生交通灯按钮并自动给侧边栏让出安全区。同时新增 `AppNavigation` 单例，桥接状态栏菜单、Dock 点击、IPC 回调等非 SwiftUI 入口到 SwiftUI Window 场景，**状态栏、Dock 点击、欢迎页跳转**全部走新的 `AppNavigation` 链路。

---

## 三、最大的 Bug 修复：右键新建 Office 文件不再"损坏"

这个 Bug 在 v1.2 之前一直存在：**在 Finder 右键新建 Excel 表格 / Word 文档 / PPT 演示后，双击文件 Excel/Word/PowerPoint 会弹"文件格式或文件扩展名无效"**。

### 3.1 根因分析

排查下来定位到 `Shared/FileOperations.swift` 里的 `ZipWriter.centralDirectoryHeader` 写错了：

- ZIP 规范要求中央目录头的字段顺序是 `signature → mod time → **mod date** → crc-32 → ...`
- 老代码中央目录头**漏了 2 字节的 `mod date` 字段**（本地文件头是有的，中央目录头漏了）
- 整个中央目录错位 2 字节，Office 解析失败

不仅如此，模板 XML 里 `[Content_Types].xml` 和 `_rels/.rels` 对三种格式都硬编码成 `word/document.xml`，xlsx 还缺必需的 `xl/worksheets/sheet1.xml` 等子部件。**手写 Office 文件这条路，从根上就走不通**。

### 3.2 修复方案：参考 RClick，用真实 Office 模板

最终决定**完全放弃手写 Office 文件**这条路，参考 [wflixu/RClick](https://github.com/wflixu/RClick) 的做法：

- 在 `SnapClick/Resources/` 下放置 3 个**真实的 Office 模板文件**（`template.docx` / `template.xlsx` / `template.pptx`）
- 用 `textutil`（docx）、`openpyxl`（xlsx）、`python-pptx`（pptx）一次性生成，含完整主题、样式、app metadata
- `FileOperations.officeTemplateURL(for:)` 读取 Bundle 资源，`FileManager.copyItem(at:to:)` 直接克隆
- 删除 220 行手写 `ZipWriter` 编码器和 `minimalOfficeData` XML 拼装代码

**`FileOperations.swift` 从 537 行直接瘦身到 310 行**。后续想扩展支持 `.pages` / `.key` / `.numbers`，只需把模板文件放进 `Resources/` 并加到 Xcode project，**代码逻辑零改动**。

---

## 四、v1.2.1 微更新：模板名称可编辑 + 图标预热异步化

v1.2.1 是 v1.2.0 的小补丁更新，主要解决两个体验问题：

### 4.1 模板名称支持直接编辑

v1.2 之前，自定义文件模板的名字是写死的，新用户想改个名字就抓瞎。v1.2.1 把 `inMainMenu` 冗余字段移除，新增**模板名称行内编辑**：

- 编辑图标：12pt medium 字体、22×22pt 圆形点击区域，hover 时显示主题色 + 12% 背景填充
- 一键进入重命名状态，**所见即所得**

### 4.2 图标预热挪到后台队列

之前勾选/取消模板时，App 会同步触发 `IconCache.preheat()`，主线程卡顿明显。v1.2.1 把它挪到后台队列 `com.snapclick.app.preheat`（utility QoS）+ 300ms 防抖，**主线程零阻塞**，勾选反馈即时。

### 4.3 侧边栏蓝色 Glass Tint

侧边栏在选中态之外，整体加了一层淡淡的**蓝色 Glass Tint**，让 Liquid Glass 质感和 macOS Tahoe 系统设置更接近。

---

## 五、五大核心功能一览（v1.2 全都保留并增强）

### 5.1 Finder 右键菜单增强

![Finder 右键增强菜单](./docs/assets/right_click_screenshot.png)

- **一键新建** `.txt` / `.md` / `.docx` / `.xlsx` / `.pptx` / `.html` / `.css` / `.js` / `.py` / `.sh`（Office 文件 v1.2 之后不再损坏！）
- **真正的剪切粘贴**——比原生 `⌘C → ⌘⌥V` 的暗黑操作直观一万倍，支持跨目录快速移动
- **快速移动 / 复制到**——把常用目录加进收藏，归档文件不再翻目录
- **路径高级拷贝**——完整路径、仅文件名、POSIX 规范路径，按需取用
- **在当前目录打开 Terminal / iTerm2 / VS Code / Warp / Xcode**——开发者狂喜

### 5.2 高级截图与标注

![截图标注编辑器](./docs/assets/screenshot_editor_screenshot.png)

- **区域截图 & 智能窗口识别**——拖选区时鼠标悬停到任意窗口，会自动贴合窗口边缘。快捷键 `⌥⇧A`
- **智能长截图**——网页 / 聊天记录 / 超长文档，滚动捕获 + 智能拼接，无缝
- **高级标注工具栏**——矩形 / 椭圆 / 直线 / 箭头 / 文字 / 画笔 / 高亮蒙层 / 步骤序号 / 像素级马赛克
- **截图美化包装**——一键毛玻璃大阴影 + 0~32px 自定义圆角，做 CSDN 封面图神器

![长截图捕获](./docs/assets/long_screenshot_preview.png)

### 5.3 高性能屏幕录制

![录屏 HUD](./docs/assets/recording_overlay.png)

- **底层 SCK 架构**：基于 macOS 13+ 官方的 `ScreenCaptureKit` 框架，**硬件加速、CPU 占用极低**。同样录 4K 60FPS，Kap 风扇狂转，SnapClick 几乎听不到风扇声
- **三种录制模式**：自定义区域、全屏、指定应用窗口
- **极速高帧率**：30 / 60 / **120 FPS**，H.264 / HEVC 编码，支持"原画"无损分辨率
- **双音轨独立录制**：系统内部声音 + 麦克风**分轨保存**，做教程视频后期混音直接拖进剪映 / FCPX
- **HUD 浮动控制条**：实时显示录制时长，暂停 / 继续 / 停止一键搞定

### 5.4 屏幕贴图（Pin Window）

![屏幕贴图](./docs/assets/pin_window_overlay.png)

- **快捷键 `⌥⇧P`**——截图后秒贴到屏幕最上层
- **多视窗管理**——同时贴 N 张图，**跨 Space 跟随**，写代码对照 UI 稿、对账单时简直离不开
- **滚轮无级调节透明度**——盖在代码窗口上当"半透明小抄"很爽
- **双击缩放、随手摆放**

### 5.5 精准取色放大镜

![取色放大镜](./docs/assets/color_picker_overlay.png)

- **16x 像素级放大镜**，`⌥⇧C` 调起
- **多格式一键复制**：HEX、RGB、HSL、Swift (NSColor)、CSS——前端和 iOS 开发都不用再手动转格式
- **取色历史**——智能记录最近 20 条，临时丢的颜色不会再丢

---

## 六、技术栈（开发者关注）

SnapClick 完全使用 **Swift 5.9 + SwiftUI + AppKit** 编写，无任何 Electron / RN / Flutter 套壳：

| 模块 | 技术选型 |
|------|---------|
| 主 App | SwiftUI `Window` + `NavigationSplitView`（v1.2 重构） |
| FinderExtension | `FinderSync` Extension（沙盒模式） |
| IPC 通信 | App Group `UserDefaults` + `Darwin Notification` + `NSPasteboard` |
| 录屏 | `ScreenCaptureKit`（macOS 13+） |
| 截图取色 | `CoreGraphics` + Metal 加速 |
| 快捷键 | `CGEventTap` + 辅助功能权限拦截 |
| Office 文件 | 真实模板（`template.{docx,xlsx,pptx}`）+ `FileManager.copyItem` |
| 视觉 | 自定义 `NSVisualEffectView` + Liquid Glass 1px 高光描边 |

最低系统要求：**macOS 13 Ventura**。开源协议：**Apache License 2.0**，可自由 fork、二开、商用。

> 🏗 **架构小亮点**：FinderExtension 运行在沙盒里，不能直接执行文件操作。SnapClick 通过 App Group + Darwin Notification 把命令派给主 App 执行，**既安全又不会弹一堆 TCC 权限框**。文件调起使用 `/usr/bin/open -R` 替代 `NSWorkspace` 的 `activateFileViewerSelecting`，**避免 Apple Event 权限弹窗**。

---

## 七、下载安装

### 7.1 安装包

直接去 GitHub Releases 下载最新 `.dmg`：

```
https://github.com/Tyeerth/SnapClick/releases/latest
```

下载完成后双击 `.dmg`，把 SnapClick 拖入「应用程序」文件夹即可。

### 7.2 ⚠️ 处理"已损坏，无法打开"（重要）

由于作者还没加入 Apple 付费开发者计划，未做公证签名，首次打开会被 Gatekeeper 拦截。**这不是 App 有问题**，按以下任一方法即可：

**方法一：移除隔离属性（推荐，最稳定）**

```bash
sudo xattr -dr com.apple.quarantine /Applications/SnapClick.app
```

输入开机密码回车，之后正常双击打开。

**方法二：系统设置放行**

1. 双击 App，弹拦截提示点「**取消**」
2. 前往「**系统设置 → 隐私与安全性**」，向下滚动到「安全性」区域
3. 找到「已阻止使用 "SnapClick"」的提示，点击「**仍要打开**」
4. 在再次弹出的对话框中点「**打开**」

**方法三：右键打开**

在「应用程序」中**右键** SnapClick → 选择「**打开**」→ 提示框再次点「**打开**」

> 💡 以上操作只需首次执行一次，之后即可像普通 App 一样正常使用。

### 7.3 首次启动授权

App 会引导你授予以下权限：

1. **屏幕录制权限**——截图 / 录屏 / 取色全靠它
2. **辅助功能权限**——监听全局快捷键
3. **Finder 扩展启用**——系统设置 → 通用 → 登录项与扩展 → Finder 扩展，勾上 `FinderExtension`

---

## 八、写在最后

两个月前发 v1.1 的时候，我以为功能层面已经差不多了，剩下的就是慢慢修 Bug。

但 v1.2 让我意识到：**真正让一个工具变得"丝滑"的，不是堆功能，而是把每一个细节都重做一遍**。

- 把老旧的 `NSWindow + HStack` 推倒，用 SwiftUI `Window` + `NavigationSplitView` 重写主窗口架构；
- 把手写 Office 文件那 220 行 `ZipWriter` 删掉，用真实的 Office 模板文件替代；
- 把侧边栏从蓝灰矩形改成 Apple 自己的 Liquid Glass 设计语言；
- 把 `IconCache.preheat()` 挪到后台队列，勾选模板不再卡顿；
- 把模板名称从"不可改"变成"行内编辑"。

每一项单独看都不大，但**累计起来，整个 App 的质感就上了一个台阶**。

如果你也是 macOS 重度用户，欢迎去 GitHub 给 SnapClick 点个 ⭐，有任何 Bug / 建议都欢迎提 Issue：

- **GitHub 项目地址**：<https://github.com/Tyeerth/SnapClick>
- **官网**：<http://snapclick.cn/>
- **联系作者**：<tyeerth@163.com>

如果觉得这篇文章对你有帮助，欢迎 **点赞 + 收藏 + 关注**，三连是对原创作者最大的支持 ✌️

> 我是一个被 Mac 效率工具坑过无数次的老开发，下次再分享好东西。
