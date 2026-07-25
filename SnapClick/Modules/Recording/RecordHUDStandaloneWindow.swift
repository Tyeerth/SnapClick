// RecordHUDStandaloneWindow.swift
// SnapClick - 全屏录制的"独立参数面板"窗口
// 直接复用 RecordSelectionOverlayWindow.swift 中已有的 RecordingSelectionHUDView
// （横向 HUD：清晰度 / 格式 / 帧率 / 麦克风 / 系统声音 / 鼠标 / 保存到 / 倒计时），
// 不带选区拖拽，仅承载"开始录制 / 取消"两个动作。
//
// 三种录制模式（选区 / 窗口 / 全屏）都用同一份 HUD，UI 样式 100% 保持一致：
//   - 选区 / 窗口录制 → RecordSelectionOverlayWindow（已自带底部 HUD）
//   - 全屏录制        → RecordHUDStandaloneWindow（仅 HUD）
// 用户从同一份 HUD 选完参数后点"开始录制"，参数写入 AppSettings.recordQuality 等字段，
// ScreenRecordingEngine 启动时按 recordQuality 读取 VideoQuality 应用到 AVAssetWriter。

import AppKit
import SwiftUI

final class RecordHUDStandaloneWindow: NSWindow {

    /// 用户点"开始录制"（HUD 右侧红色按钮）
    var onRecord: (() -> Void)?

    /// 用户取消（ESC / 左侧 X 按钮）
    var onCancel: (() -> Void)?

    /// 拖动开始时窗口的原点，每次手势 .began 重置
    private var dragStartOrigin: CGPoint = .zero

    /// 拖动开始时鼠标的全局 screen 坐标（不受窗口移动影响，是真正的绝对参考点）
    private var dragStartMouseLocation: CGPoint = .zero

    init(hostScreen: NSScreen) {
        // 独立 HUD 宽度要装下"屏幕"下拉，比选区底部 HUD 多 ~150px
        let hudWidth: CGFloat = 1030
        let hudHeight: CGFloat = 64

        // 初始位置：挂在 hostScreen 正中（用户后续可拖动）
        let frame = NSRect(
            x: hostScreen.frame.midX - hudWidth / 2,
            y: hostScreen.frame.midY - hudHeight / 2,
            width: hudWidth,
            height: hudHeight
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.acceptsMouseMovedEvents = true
        // 不要打开 isMovableByWindowBackground：
        //   - 之前和 NSPanGestureRecognizer 同时启用时，AppKit 和 SwiftUI 各自计算
        //     一次窗口位置，叠加成"闪缩回到原位"的效果
        //   - 现在只由 NSPanGestureRecognizer 统一管拖动
        self.isMovableByWindowBackground = false
        self.isMovable = false

        let hudView = RecordingSelectionHUDView(
            onRecord: { [weak self] in
                self?.orderOut(nil)
                self?.onRecord?()
            },
            onCancel: { [weak self] in
                self?.orderOut(nil)
                self?.onCancel?()
            },
            onResolutionChange: { _ in
                // 全屏录制没有选区，分辨率变化时不需要调整选区大小
            },
            showsScreenSelection: true
        )

        let hosting = NSHostingView(rootView: hudView)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        // 让 hostingView 跟着 contentView 一起缩放，避免 SwiftUI 重渲后 frame 被重置
        hosting.autoresizingMask = [.width, .height]
        self.contentView = hosting

        // 用 NSPanGestureRecognizer 统一管拖动：
        //   1) SwiftUI hostingView 在 macOS 上会吃掉 mouseDown，isMovableByWindowBackground 不可靠
        //   2) 自定义累计位移 + 锚定起点，避免 AppKit/SwiftUI 双重计算窗口位置导致闪缩
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        // 关键：不要让 gesture 吞掉 mouseDown / mouseUp，否则下拉框点不开
        pan.delaysPrimaryMouseButtonEvents = false
        pan.delaysSecondaryMouseButtonEvents = false
        // NSPanGestureRecognizer 默认只识别左键拖动，无需额外配置右键
        hosting.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        // 只在拖动中处理；其他状态（possible/ended/cancelled/failed）直接返回
        // 防止 mouseUp 时 gesture.translation 跳变触发"跳回原位"
        guard gesture.state == .began || gesture.state == .changed else {
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                dragStartOrigin = .zero
                dragStartMouseLocation = .zero
            }
            return
        }

        if gesture.state == .began {
            dragStartOrigin = self.frame.origin
            dragStartMouseLocation = NSEvent.mouseLocation
            return
        }

        // .changed：用 NSEvent.mouseLocation（全局 screen 坐标）算位移。
        // 千万不要用 gesture.translation(in: nil)——
        //   nil 走的是 window 坐标系，窗口每次 setFrameOrigin 都会让坐标系漂移，
        //   下一帧 translation 就被自己上次的位移污染一次，形成自激振荡 → 持续闪烁
        // NSEvent.mouseLocation 始终是 global screen，绝对稳定：
        //   deltaX = 当前鼠标X - 拖动起始时鼠标X（永远只反映真实鼠标移动，不受窗口影响）
        let current = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: dragStartOrigin.x + (current.x - dragStartMouseLocation.x),
            y: dragStartOrigin.y + (current.y - dragStartMouseLocation.y)
        )
        self.setFrameOrigin(newOrigin)
        // 不需要 setTranslation 重置：位移完全靠两次 mouseLocation 之差算，不依赖 gesture 内部状态
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            cancel()
        }
    }

    func cancel() {
        orderOut(nil)
        onCancel?()
    }
}
