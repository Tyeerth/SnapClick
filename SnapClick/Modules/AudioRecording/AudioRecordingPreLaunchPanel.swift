// AudioRecordingPreLaunchPanel.swift
// SnapClick - 录音前参数选择 HUD 面板
// 点击「开始录音」时先弹出此面板，用户调完参数再开始录音。
// 风格与 RecordHUDStandaloneWindow 完全一致（无边框毛玻璃深色横向 HUD）。

import AppKit
import SwiftUI
import AVFoundation

// MARK: - 面板窗口

final class AudioRecordingPreLaunchPanel: NSPanel {

    /// 用户点「开始录音」时触发
    var onRecord: (() -> Void)?

    /// 用户取消（ESC / ✕ 按钮）时触发
    var onCancel: (() -> Void)?

    private var dragStartOrigin: CGPoint = .zero
    private var dragStartMouseLocation: CGPoint = .zero

    private static let hudWidth:  CGFloat = 980
    private static let hudHeight: CGFloat = 64

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = NSRect(
            x: screen.frame.midX - Self.hudWidth  / 2,
            y: screen.frame.midY + 60,
            width:  Self.hudWidth,
            height: Self.hudHeight
        )

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.acceptsMouseMovedEvents = true
        self.isMovableByWindowBackground = false
        self.isMovable = false

        let hudView = AudioRecordingPreLaunchView(
            onRecord: { [weak self] in
                self?.orderOut(nil)
                self?.onRecord?()
            },
            onCancel: { [weak self] in
                self?.orderOut(nil)
                self?.onCancel?()
            }
        )

        let hosting = NSHostingView(rootView: hudView)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        self.contentView = hosting

        // 拖动手势（与录屏 HUD 同一方案，避免 AppKit/SwiftUI 双重计算）
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delaysPrimaryMouseButtonEvents  = false
        pan.delaysSecondaryMouseButtonEvents = false
        hosting.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
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
        let current = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: dragStartOrigin.x + (current.x - dragStartMouseLocation.x),
            y: dragStartOrigin.y + (current.y - dragStartMouseLocation.y)
        )
        self.setFrameOrigin(newOrigin)
    }

    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            orderOut(nil)
            onCancel?()
        }
    }
}

// MARK: - SwiftUI HUD 视图

struct AudioRecordingPreLaunchView: View {

    let onRecord: () -> Void
    let onCancel: () -> Void

    @ObservedObject private var settings  = AppSettings.shared
    @ObservedObject private var testEngine = AudioMicrophoneTestEngine.shared
    @State private var microphones: [String] = ["无"]

    // MARK: 辅助计算

    private var savePathDisplayName: String {
        let path = settings.audioRecordSavePath
        if path.hasSuffix("Desktop")   { return "桌面".localized }
        if path.hasSuffix("Downloads") { return "下载".localized }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var systemAudioAvailable: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 10) {

            // ── 1. 麦克风 ─────────────────────────────────────────
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 1.0, opacity: 0.8))
                    .padding(.top, 10)

                HUDDropdown(
                    label: "麦克风",
                    selection: $settings.audioRecordMicrophone,
                    options: microphones,
                    width: 120
                )
            }

            // ── 2. 系统音频 ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text("系统音频")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 1.0, opacity: 0.4))

                HStack(spacing: 4) {
                    Image(systemName: settings.audioRecordSystemAudio
                          ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 11))
                        .foregroundColor(
                            (!systemAudioAvailable)
                                ? Color(white: 1.0, opacity: 0.3)
                                : (settings.audioRecordSystemAudio ? .green : Color(white: 1.0, opacity: 0.8))
                        )
                        .frame(width: 14)

                    Button(action: {
                        guard systemAudioAvailable else { return }
                        settings.audioRecordSystemAudio.toggle()
                    }) {
                        ZStack(alignment: settings.audioRecordSystemAudio ? .trailing : .leading) {
                            Capsule()
                                .fill(
                                    (!systemAudioAvailable)
                                        ? Color(white: 1.0, opacity: 0.1)
                                        : (settings.audioRecordSystemAudio ? Color.green : Color(white: 1.0, opacity: 0.2))
                                )
                                .frame(width: 32, height: 18)
                            Circle()
                                .fill(.white.opacity(systemAudioAvailable ? 1.0 : 0.4))
                                .frame(width: 14, height: 14)
                                .padding(.horizontal, 2)
                        }
                        .animation(.easeInOut(duration: 0.15), value: settings.audioRecordSystemAudio)
                    }
                    .buttonStyle(.plain)
                    .disabled(!systemAudioAvailable)
                }
                .frame(height: 24)
            }
            .help(systemAudioAvailable ? "录制系统内部声音" : "需要 macOS 13 或更高版本")

            HUDSeparator()

            // ── 3. 质量 ────────────────────────────────────────────
            HUDDropdown(
                label: "质量",
                selection: $settings.audioRecordQuality,
                options: ["经济", "标准", "高质量"],
                width: 82
            )

            // ── 4. 采样率 ──────────────────────────────────────────
            HUDDropdown(
                label: "采样率",
                selection: Binding(
                    get: { settings.audioRecordSampleRate == 44_100 ? "44.1 kHz" : "48 kHz" },
                    set: { settings.audioRecordSampleRate = ($0 == "44.1 kHz") ? 44_100 : 48_000 }
                ),
                options: ["44.1 kHz", "48 kHz"],
                width: 82
            )

            // ── 5. 声道 ────────────────────────────────────────────
            HUDDropdown(
                label: "声道",
                selection: Binding(
                    get: { settings.audioRecordChannels == 1 ? "单声道" : "立体声" },
                    set: { settings.audioRecordChannels = ($0 == "单声道") ? 1 : 2 }
                ),
                options: ["单声道", "立体声"],
                width: 72
            )

            HUDSeparator()

            // ── 6. 保存路径 ────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                Text("保存到")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 1.0, opacity: 0.4))

                HUDFolderButton(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories   = true
                    panel.canChooseFiles         = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        settings.audioRecordSavePath = url.path
                    }
                }, savePathDisplayName: savePathDisplayName)
            }
            .help("修改保存路径: \(settings.audioRecordSavePath)")

            // ── 7. 倒计时 ──────────────────────────────────────────
            HUDDropdown(
                label: "倒计时",
                selection: Binding(
                    get: { settings.audioRecordCountdown == 0 ? "关" : "\(settings.audioRecordCountdown)秒" },
                    set: {
                        if $0 == "关" {
                            settings.audioRecordCountdown = 0
                        } else {
                            let s = $0.replacingOccurrences(of: "秒", with: "")
                            settings.audioRecordCountdown = Int(s) ?? 0
                        }
                    }
                ),
                options: ["关", "3秒", "5秒", "10秒"],
                width: 60
            )

            Spacer(minLength: 0).frame(maxWidth: 8)

            // ── 8. 实时输入电平预览 ────────────────────────────────
            HUDSeparator()

            VStack(alignment: .leading, spacing: 3) {
                Text("输入")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(white: 1.0, opacity: 0.4))

                HStack(spacing: 3) {
                    // 信号灯：监测中 = 闪烁红点，未监测 = 灯灰
                    Circle()
                        .fill(testEngine.isTesting
                              ? Color.red.opacity(testEngine.currentLevel > 0.01 ? 1.0 : 0.3)
                              : Color(white: 1.0, opacity: 0.18))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.15), value: testEngine.currentLevel)

                    AudioLevelSegments(
                        level: testEngine.isTesting ? testEngine.currentLevel : 0,
                        segments: 14,
                        trackColor: Color(white: 1.0, opacity: 0.10),
                        spacing: 1.5,
                        cornerRadius: 1.5
                    )
                    .frame(height: 9)
                }
                .frame(width: 120)
            }

            Spacer(minLength: 0).frame(maxWidth: 8)

            // ── 8. 动作按钮 ───────────────────────────────────────
            HUDCancelButton(action: onCancel)
                .help("取消 (ESC)")

            AudioHUDRecordButton(action: onRecord)
                .help("开始录音")
        }
        .padding(.horizontal, 14)
        .frame(width: 980, height: 64)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(white: 1.0, opacity: 0.15), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .colorScheme(.dark)
        .onAppear {
            loadMicrophones()
            startPreviewIfPossible()
        }
        .onChange(of: settings.audioRecordMicrophone) { _ in
            // 用户切换麦克风时重启预测
            startPreviewIfPossible()
        }
        .onDisappear {
            testEngine.stopTesting()
        }
    }

    private func loadMicrophones() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = ["无"] + session.devices.map { $0.localizedName }
        self.microphones = devices

        // 如果当前选中的设备已不存在，回退到第一个可用设备
        if !devices.contains(settings.audioRecordMicrophone) {
            settings.audioRecordMicrophone = devices.first ?? "无"
        }
    }

    /// 启动麦克风实时监测（面板展示期间预览输入电平）
    private func startPreviewIfPossible() {
        let name = settings.audioRecordMicrophone
        guard name != "无", !name.isEmpty else {
            testEngine.stopTesting()
            return
        }
        // 如果已在监测相同设备则不重复启动
        Task { @MainActor in
            if testEngine.isTesting { testEngine.stopTesting() }
            try? await testEngine.startTesting(deviceName: name)
        }
    }
}

// MARK: - 录音专用开始按钮（麦克风图标 + 红色圆，区别于录屏的纯红圆点）

private struct AudioHUDRecordButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(isHovered ? Color.blue : Color.white, lineWidth: 2.2)
                    .frame(width: 36, height: 36)
                    .shadow(color: isHovered ? Color.blue.opacity(0.5) : .clear, radius: 4)

                Circle()
                    .fill(Color.red)
                    .frame(width: 26, height: 26)
                    .scaleEffect(isHovered ? 1.15 : 1.0)

                Image(systemName: "mic.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
    }
}
