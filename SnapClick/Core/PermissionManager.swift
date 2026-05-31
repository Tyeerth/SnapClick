import AppKit
import AVFoundation
import ApplicationServices

final class PermissionManager: ObservableObject {

    static let shared = PermissionManager()
    private init() {
        hasAccessibilityPermission = checkAccessibilityPermission()
        hasScreenRecordingPermission = checkScreenRecordingPermission()
    }

    @Published var hasScreenRecordingPermission: Bool = false
    @Published var hasAccessibilityPermission: Bool = false

    private var pollingTimer: Timer?

    func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAllPermissions()
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    func refreshAllPermissions() {
        let screen = checkScreenRecordingPermission()
        let accessibility = checkAccessibilityPermission()

        hasScreenRecordingPermission = screen
        hasAccessibilityPermission = accessibility

        if hasScreenRecordingPermission && hasAccessibilityPermission {
            stopPolling()
        }
    }

    func checkScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() {
        guard !checkScreenRecordingPermission() else {
            refreshAllPermissions()
            return
        }

        _ = CGRequestScreenCaptureAccess()
        openPrivacyPreferences(section: "ScreenCapture")
        startPolling()
    }

    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else {
            refreshAllPermissions()
            return
        }

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        DispatchQueue.main.async {
            self.hasAccessibilityPermission = trusted
        }

        if !trusted {
            startPolling()
        }
    }

    private func openPrivacyPreferences(section: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
