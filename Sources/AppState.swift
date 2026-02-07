import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import os.log

class AppState: ObservableObject, HotkeyDelegate {
    @Published var audioController = AudioController()
    @Published var overlayController = OverlayController()
    @Published var isPTTActive: Bool = false
    @Published var pttCountdownRemaining: Int? = nil

    var hotkeyManager: HotkeyManager?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macmiccontrol", category: "AppState")
    private var cancellables = Set<AnyCancellable>()
    private var lastToggleTime: TimeInterval = 0
    private var pttReleaseTimer: Timer?
    private var pttCountdownTimer: Timer?
    private var notificationObserver: NSObjectProtocol?

    init() {
        self.hotkeyManager = HotkeyManager(delegate: self)

        notificationObserver = NotificationCenter.default.addObserver(
            forName: .inputDeviceDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDeviceDisconnected()
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            if let error = error {
                self?.logger.error("Notification auth error: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Subscribe to isMuted changes
        audioController.$isMuted
            .dropFirst()
            .sink { [weak self] isMuted in
                DispatchQueue.main.async {
                    guard let self = self else { return }

                    if self.isPTTActive {
                        if SettingsManager.shared.pttVisualFeedback {
                            self.overlayController.showOverlay(
                                isMuted: isMuted,
                                duration: SettingsManager.shared.pttNotificationDuration
                            )
                        }
                    } else {
                        if SettingsManager.shared.generalVisualFeedback {
                            self.overlayController.showOverlay(
                                isMuted: isMuted,
                                duration: SettingsManager.shared.notificationDuration
                            )
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pttReleaseTimer?.invalidate()
        pttCountdownTimer?.invalidate()
    }

    private func handleDeviceDisconnected() {
        if self.isPTTActive {
             self.isPTTActive = false
             self.audioController.setMute(true)
             self.showNotification(title: "Microphone disconnected", message: "Push to Talk disabled.")
        }
    }

    func checkPermissions() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return false
        case .denied, .restricted:
            showNotification(title: "Microphone access required", message: "Click to open System Preferences")
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return false
        @unknown default:
            return false
        }
    }

    func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Error showing notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - HotkeyDelegate

    func toggleMuteHotkeyPressed() {
        DispatchQueue.main.async {
            self.toggleMute()
        }
    }

    func pttToggleHotkeyPressed() {
        DispatchQueue.main.async {
            SettingsManager.shared.pttEnabled.toggle()
            if !SettingsManager.shared.pttEnabled && self.isPTTActive {
                self.pttActionHotkeyReleased()
            }
        }
    }

    func pttActionHotkeyPressed() {
        DispatchQueue.main.async {
            guard SettingsManager.shared.pttEnabled else { return }

            // If timer is running, cancel it and stay active
            if self.pttReleaseTimer != nil {
                self.pttReleaseTimer?.invalidate()
                self.pttReleaseTimer = nil
                self.pttCountdownTimer?.invalidate()
                self.pttCountdownTimer = nil
                self.pttCountdownRemaining = nil
                self.isPTTActive = true
                return
            }

            guard !self.isPTTActive else { return }
            guard self.checkPermissions() else { return }

            if self.audioController.isInputDeviceAvailable() == false {
                 self.showNotification(title: "No microphone detected", message: "Please connect a microphone to use Push to Talk")
                 return
            }

            self.isPTTActive = true
            self.audioController.setMute(false)

            if SettingsManager.shared.pttAudioFeedback {
                SettingsManager.shared.cachedSound(named: SettingsManager.shared.soundPTTActivate)?.play()
            }
        }
    }

    func pttActionHotkeyReleased() {
        DispatchQueue.main.async {
            guard SettingsManager.shared.pttEnabled else { return }
            guard self.isPTTActive else { return }

            let delay = SettingsManager.shared.pttReleaseDelay
            if delay > 0 {
                self.pttReleaseTimer?.invalidate()
                self.pttReleaseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    self?.finalizePTTRelease()
                }

                self.pttCountdownRemaining = Int(ceil(delay))
                self.pttCountdownTimer?.invalidate()
                self.pttCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self, let remaining = self.pttCountdownRemaining else { return }
                    if remaining > 1 {
                         self.pttCountdownRemaining = remaining - 1
                    } else {
                         self.pttCountdownTimer?.invalidate()
                         self.pttCountdownTimer = nil
                    }
                }

                return
            }

            self.finalizePTTRelease()
        }
    }

    private func finalizePTTRelease() {
        self.pttReleaseTimer = nil
        self.pttCountdownTimer?.invalidate()
        self.pttCountdownTimer = nil
        self.pttCountdownRemaining = nil

        self.isPTTActive = false
        self.audioController.setMute(true)

        if SettingsManager.shared.pttAudioFeedback {
            SettingsManager.shared.cachedSound(named: SettingsManager.shared.soundPTTDeactivate)?.play()
        }
    }

    func toggleMute() {
        let now = Date().timeIntervalSince1970
        if now - lastToggleTime < 0.3 { return }
        lastToggleTime = now

        if isPTTActive {
            pttReleaseTimer?.invalidate()
            pttReleaseTimer = nil
            pttCountdownTimer?.invalidate()
            pttCountdownTimer = nil
            pttCountdownRemaining = nil
            isPTTActive = false
        }

        let newMuteState = !audioController.isMuted
        audioController.setMute(newMuteState)

        if SettingsManager.shared.generalAudioFeedback {
            let soundName = newMuteState ? SettingsManager.shared.soundStandardMute : SettingsManager.shared.soundStandardUnmute
            SettingsManager.shared.cachedSound(named: soundName)?.play()
        }
    }
}
