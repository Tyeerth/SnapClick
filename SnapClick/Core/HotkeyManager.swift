// HotkeyManager.swift
// SnapClick - 全局快捷键管理器
// 使用 CGEventTap 监听系统全局键盘事件，免受 Sandbox 限制（主 App 已禁用沙盒）

import Cocoa
import Carbon

@MainActor
final class HotkeyManager: ObservableObject {
    
    // MARK: - 单例
    static let shared = HotkeyManager()
    
    // MARK: - 私有属性
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // 快捷键模型
    struct HotkeyDefinition {
        let name: String
        let modifiers: CGEventFlags
        let keyCode: CGKeyCode
        let action: () -> Void
    }
    
    private var registeredHotkeys: [HotkeyDefinition] = []
    
    private init() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.registerAll()
        }
    }
    
    // MARK: - 公开接口
    
    /// 初始化并注册所有快捷键
    func registerAll() {
        registeredHotkeys.removeAll()
        
        let settings = AppSettings.shared
        
        // 智能截图（区域 + 窗口合一）：
        // 拖拽选区 / 点击截取悬停窗口，单个快捷键统一入口
        register(settings.hotkeyAreaScreenshot, name: "智能截图") {
            Task {
                do {
                    try await ScreenCaptureEngine.shared.capture()
                } catch {
                    print("智能截图失败: \(error.localizedDescription)")
                }
            }
        }

        // 纯窗口截图（仅点击截取窗口，不进入区域选区）
        register(settings.hotkeyWindowScreenshot, name: "窗口截图") {
            Task {
                do {
                    try await ScreenCaptureEngine.shared.captureWindow()
                } catch {
                    print("窗口截图失败: \(error.localizedDescription)")
                }
            }
        }

        // 选区截图（仅区域框选，不支持点击截取窗口）
        register(settings.hotkeyRegionScreenshot, name: "选区截图") {
            Task {
                do {
                    try await ScreenCaptureEngine.shared.captureArea()
                } catch {
                    print("选区截图失败: \(error.localizedDescription)")
                }
            }
        }

        register(settings.hotkeyColorPicker, name: "屏幕取色") {
            ColorPickerEngine.shared.startPicking()
        }

        register(settings.hotkeyLongScreenshot, name: "长截图") {
            Task {
                do {
                    try await ScreenCaptureEngine.shared.captureLongScreenshot()
                } catch {
                    print("长截图失败: \(error.localizedDescription)")
                }
            }
        }
        register(settings.hotkeyPin, name: "剪贴板贴图") {
            if let image = NSImage(pasteboard: NSPasteboard.general) {
                PinWindowManager.shared.pin(image: image)
            } else {
                // 如果剪贴板没图片，弹个轻量提示
                let alert = NSAlert()
                alert.messageText = "贴图提示"
                alert.informativeText = "剪贴板中未找到图片，请先截图或复制图片。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "好的")
                alert.runModal()
            }
        }
        
        register(settings.hotkeyRecordArea, name: "区域录屏") {
            Task { @MainActor in
                do {
                    try await ScreenRecordingEngine.shared.startAreaRecording()
                } catch {
                    print("区域录屏失败: \(error.localizedDescription)")
                }
            }
        }
        
        register(settings.hotkeyRecordScreen, name: "全屏录屏") {
            Task { @MainActor in
                do {
                    try await ScreenRecordingEngine.shared.startFullScreenRecording()
                } catch {
                    print("全屏录屏失败: \(error.localizedDescription)")
                }
            }
        }
        
        register(settings.hotkeyStopRecording, name: "停止录制") {
            Task { @MainActor in
                guard ScreenRecordingEngine.shared.isRecording else { return }
                do {
                    let fileURL = try await ScreenRecordingEngine.shared.stopRecording()
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } catch {
                    print("停止录制失败: \(error.localizedDescription)")
                }
            }
        }

        // 开始音频录音 → 先弹参数面板，由 StatusBarController 统一处理
        register(settings.hotkeyAudioRecord, name: "开始录音") {
            Task { @MainActor in
                guard !AudioRecordingEngine.shared.isRecording else { return }
                // 发通知，StatusBarController 收到后弹预启动面板
                NotificationCenter.default.post(name: .showAudioPreLaunchPanel, object: nil)
            }
        }

        // 停止音频录音
        register(settings.hotkeyStopAudioRecord, name: "停止录音") {
            Task { @MainActor in
                guard AudioRecordingEngine.shared.isRecording else { return }
                do {
                    let fileURL = try await AudioRecordingEngine.shared.stopRecording()
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "停止录音失败"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "好的")
                    alert.runModal()
                }
            }
        }

        if eventTap == nil {
            startListening()
        }
    }

    
    // MARK: - 快捷键解析与添加
    
    private func register(_ hotkeyStr: String, name: String, action: @escaping () -> Void) {
        guard let (modifiers, keyCode) = parseHotkey(hotkeyStr) else {
            print("无法解析快捷键: \(hotkeyStr) (\(name))")
            return
        }
        
        let def = HotkeyDefinition(name: name, modifiers: modifiers, keyCode: keyCode, action: action)
        registeredHotkeys.append(def)
        print("成功注册快捷键: \(hotkeyStr) -> \(name) (Key: \(keyCode))")
    }
    
    // MARK: - 事件监听核心
    
    private func startListening() {
        // 检查辅助功能权限（CGEventTap 需要）
        guard AXIsProcessTrusted() else {
            print("辅助功能权限未授权，无法启动全局快捷键监听")
            return
        }

        // 同时监听 keyDown 与 EventTap 自身被系统禁用的事件，方便自愈
        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            // EventTap 被系统因超时/用户输入禁用时，自动重新启用
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async {
                    if let tap = HotkeyManager.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        print("CGEventTap 被系统禁用，已自动恢复 (type=\(type.rawValue))")
                    }
                }
                return Unmanaged.passUnretained(event)
            }

            guard type == .keyDown else { return Unmanaged.passUnretained(event) }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // 匹配快捷键，在主线程执行 action
            DispatchQueue.main.async {
                HotkeyManager.shared.handleKeyEvent(keyCode: CGKeyCode(keyCode), flags: flags)
            }

            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: nil
        )

        guard let eventTap = eventTap else {
            print("创建 CGEventTap 失败")
            return
        }

        // 确保添加到主线程的 RunLoop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            print("全局快捷键监听已启动")
        }
    }
    
    private func stopListening() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        print("全局快捷键监听已停止")
    }
    
    /// 处理按键事件并匹配已注册快捷键
    private func handleKeyEvent(keyCode: CGKeyCode, flags: CGEventFlags) {
        // 提取修饰键的有效部分进行匹配
        let cleanFlags = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        
        for hotkey in registeredHotkeys {
            if hotkey.keyCode == keyCode && compareFlags(hotkey.modifiers, cleanFlags) {
                print("匹配到快捷键: \(hotkey.name)")
                hotkey.action()
                break
            }
        }
    }
    
    // MARK: - 辅助解析逻辑
    
    private func compareFlags(_ lhs: CGEventFlags, _ rhs: CGEventFlags) -> Bool {
        let cmd = lhs.contains(.maskCommand) == rhs.contains(.maskCommand)
        let ctrl = lhs.contains(.maskControl) == rhs.contains(.maskControl)
        let opt = lhs.contains(.maskAlternate) == rhs.contains(.maskAlternate)
        let shift = lhs.contains(.maskShift) == rhs.contains(.maskShift)
        return cmd && ctrl && opt && shift
    }
    
    /// 解析快捷键文本，例如 "ctrl+shift+a"
    private func parseHotkey(_ str: String) -> (CGEventFlags, CGKeyCode)? {
        let sanitized = str.lowercased().replacingOccurrences(of: "+", with: " ")
        let parts = sanitized.split(separator: " ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        
        var flags = CGEventFlags()
        var charKey: String?
        
        for part in parts {
            switch part {
            case "ctrl", "control", "⌃":
                flags.insert(.maskControl)
            case "shift", "⇧":
                flags.insert(.maskShift)
            case "alt", "option", "opt", "⌥":
                flags.insert(.maskAlternate)
            case "cmd", "command", "⌘":
                flags.insert(.maskCommand)
            default:
                charKey = part
            }
        }
        
        guard let key = charKey, let keyCode = keyCodeMap[key] else {
            return nil
        }
        
        return (flags, keyCode)
    }
    
    // 基础 ANSI 键值映射
    private var keyCodeMap: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49, "esc": 53, "escape": 53,
        "enter": 36, "tab": 48,
        "↑": 126, "↓": 125, "←": 123, "→": 124,
        "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118,
        "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]
}
