// AudioRecordingHUDWindow.swift
// SnapClick - 音频录音中悬浮条控制面板
// 仿 RecordingHUDWindow 的视觉语言（NSPanel + ultraThinMaterial），
// 中部参数条替换为左右声道电平柱，260×56

import AppKit
import SwiftUI
import Combine

// MARK: - 录音中悬浮面板
final class AudioRecordingHUDWindow: NSPanel {

    private static let positionXKey = "SnapClick.AudioRecordingHUD.PositionX"
    private static let positionYKey = "SnapClick.AudioRecordingHUD.PositionY"

    private static let defaultSize = CGSize(width: 410, height: 60)

    init(onPauseResume: @escaping () -> Void, onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let hudView = AudioRecordingHUDView(
            onPauseResume: onPauseResume,
            onStop: onStop,
            onCancel: onCancel
        )

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = CGRect(origin: .zero, size: Self.defaultSize)

        let panelFrame = Self.resolveInitialFrame()

        super.init(
            contentRect: panelFrame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.contentView = hostingView
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.isMovable = true
        self.acceptsMouseMovedEvents = true

        // tracking area：mouseEntered/Exited 切换 openHand
        let trackArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.contentView?.addTrackingArea(trackArea)

        // 拖动后保存位置
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    deinit {
        savePositionTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private var savePositionTimer: Timer?

    @objc private func handleWindowDidMove() {
        savePositionTimer?.invalidate()
        savePositionTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let origin = self.frame.origin
            UserDefaults.standard.set(Double(origin.x), forKey: Self.positionXKey)
            UserDefaults.standard.set(Double(origin.y), forKey: Self.positionYKey)
        }
    }

    // MARK: - 拖动光标
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.openHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        NSCursor.closedHand.push()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        NSCursor.pop()
        NSCursor.openHand.push()
    }

    // MARK: - 屏幕边界约束
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        guard let targetScreen = screen ?? NSScreen.main else { return frameRect }
        let visible = targetScreen.visibleFrame
        let minVisible: CGFloat = 60
        let minVisibleHeight: CGFloat = 20

        var x = frameRect.origin.x
        var y = frameRect.origin.y

        x = max(visible.minX - frameRect.width + minVisible, x)
        x = min(visible.maxX - minVisible, x)
        y = max(visible.minY, y)
        y = min(visible.maxY - minVisibleHeight, y)

        return NSRect(x: x, y: y, width: frameRect.width, height: frameRect.height)
    }

    // MARK: - 初始位置
    private static func resolveInitialFrame() -> NSRect {
        if let saved = loadSavedFrame(), isFrameUsable(saved) {
            return saved
        }
        return defaultFrame()
    }

    private static func loadSavedFrame() -> CGRect? {
        guard let x = UserDefaults.standard.object(forKey: positionXKey) as? Double,
              let y = UserDefaults.standard.object(forKey: positionYKey) as? Double else {
            return nil
        }
        return CGRect(x: x, y: y, width: defaultSize.width, height: defaultSize.height)
    }

    private static func isFrameUsable(_ rect: CGRect) -> Bool {
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(rect)
            if !intersection.isNull {
                let widthRatio = intersection.width / rect.width
                let heightRatio = intersection.height / rect.height
                if widthRatio >= 0.5 && heightRatio >= 0.5 {
                    return true
                }
            }
        }
        return false
    }

    private static func defaultFrame() -> CGRect {
        let screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(
            x: screenFrame.midX - defaultSize.width / 2,
            y: screenFrame.minY + 40,
            width: defaultSize.width,
            height: defaultSize.height
        )
    }
}

// MARK: - SwiftUI HUD 视图
struct AudioRecordingHUDView: View {
    @ObservedObject private var engine   = AudioRecordingEngine.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var isRedDotVisible = true
    private let flashTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    // 保存路径显示名
    private var savePathDisplayName: String {
        let path = settings.audioRecordSavePath
        if path.hasSuffix("Desktop")   { return "桌面".localized }
        if path.hasSuffix("Downloads") { return "下载".localized }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    let onPauseResume: () -> Void
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 闪烁红色圆点 + 计时器
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .opacity(engine.isPaused ? 0.4 : (isRedDotVisible ? 1.0 : 0.2))
                    .onReceive(flashTimer) { _ in
                        if !engine.isPaused {
                            isRedDotVisible.toggle()
                        } else {
                            isRedDotVisible = true
                        }
                    }
                Text(formatDuration(engine.recordingDuration))
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: 64)

            // 分隔线
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 28)

            // 保存位置（只读显示）
            VStack(alignment: .leading, spacing: 3) {
                Text("保存到")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(Color(white: 1.0, opacity: 0.45))

                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                    Text(savePathDisplayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .frame(height: 24)
            }
            .frame(width: 72)
            .help("当前保存路径：\(settings.audioRecordSavePath)")

            // 分隔线
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 28)

            // 输入等级：MIC + SYS 两行独立格子
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("麦克")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 1.0, opacity: 0.45))
                        .frame(width: 22, alignment: .leading)
                    AudioLevelSegments(
                        level: engine.micLevel,
                        segments: 12,
                        trackColor: Color(white: 1.0, opacity: 0.10),
                        spacing: 1.5,
                        cornerRadius: 1.5
                    )
                    .frame(height: 9)
                }
                HStack(spacing: 5) {
                    Text("系统")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 1.0, opacity: 0.45))
                        .frame(width: 22, alignment: .leading)
                    AudioLevelSegments(
                        level: engine.systemLevel,
                        segments: 12,
                        trackColor: Color(white: 1.0, opacity: 0.10),
                        spacing: 1.5,
                        cornerRadius: 1.5
                    )
                    .frame(height: 9)
                }
            }
            .frame(width: 120)

            // 分隔线
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 28)

            // 暂停 / 继续
            Button(action: onPauseResume) {
                Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Color(white: 1.0, opacity: 0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(engine.isPaused ? "继续录音".localized : "暂停录音".localized)
            .accessibilityLabel(engine.isPaused ? "继续录音" : "暂停录音")

            // 停止（保存）
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 22, height: 22)
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                }
            }
            .buttonStyle(.plain)
            .help("停止并保存".localized)
            .accessibilityLabel("停止并保存")

            // 取消（丢弃）
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 22, height: 22)
                    .background(Color(white: 1.0, opacity: 0.08))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("取消并删除".localized)
            .accessibilityLabel("取消并删除")
        }
        .padding(.horizontal, 12)
        .frame(width: 410, height: 60)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(white: 1.0, opacity: 0.12), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .colorScheme(.dark)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
