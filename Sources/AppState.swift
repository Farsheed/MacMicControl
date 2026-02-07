import SwiftUI
import Combine
import AVFoundation
import UserNotifications

class AppState: ObservableObject, HotkeyDelegate {
    @Published var audioController = AudioController()
    @Published var overlayController = OverlayController()
    @Published var isPTTActive: Bool = false
    @Published var pttCountdownRemaining: Int? = nil
    
    var hotkeyManager: HotkeyManager?
    
    private var cancellables = Set<AnyCancellable>()
    private var lastToggleTime: TimeInterval = 0
    private var pttReleaseTimer: Timer?
    private var pttCountdownTimer: Timer?
    
    init() {
        self.hotkeyManager = HotkeyManager(delegate: self)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleDeviceDisconnected), name: .inputDeviceDisconnected, object: nil)
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error)")
            }
        }
        
        // Subscribe to isMuted changes
        audioController.$isMuted
            .dropFirst() // Don't show overlay on initial load
            .sink { [weak self] isMuted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    
                    if self.isPTTActive {
                        // PTT Mode
                        if SettingsManager.shared.pttVisualFeedback {
                            self.overlayController.showOverlay(isMuted: isMuted)
                        }
                    } else {
                        // Standard Mode
                        if SettingsManager.shared.generalVisualFeedback {
                            self.overlayController.showOverlay(isMuted: isMuted)
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    @objc private func handleDeviceDisconnected() {
        DispatchQueue.main.async {
            // Even if PTT is not active, if it's enabled we might want to warn?
            // But spec says "If the microphone is disconnected during PTT... blinking stops"
            if self.isPTTActive {
                 self.isPTTActive = false
                 self.audioController.setMute(true)
                 self.showNotification(title: "Microphone disconnected", message: "Push to Talk disabled.")
            }
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
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
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
            // If we just disabled it and it was active, stop it
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
                self.isPTTActive = true // Ensure it's true
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
                let soundName = SettingsManager.shared.soundPTTActivate
                if soundName != "None", let sound = NSSound(named: soundName) {
                    sound.play()
                }
            }
        }
    }
    
    func pttActionHotkeyReleased() {
        DispatchQueue.main.async {
            guard SettingsManager.shared.pttEnabled else { return }
            guard self.isPTTActive else { return }
            
            // Check for delay
            let delay = SettingsManager.shared.pttReleaseDelay
            if delay > 0 {
                // Start Timer
                self.pttReleaseTimer?.invalidate()
                self.pttReleaseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    self?.finalizePTTRelease()
                }
                
                // Start Countdown
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
            // Play subtle click
            let soundName = SettingsManager.shared.soundPTTDeactivate
            if soundName != "None", let sound = NSSound(named: soundName) {
                sound.play()
            }
        }
    }
    
    func toggleMute() {
        let now = Date().timeIntervalSince1970
        if now - lastToggleTime < 0.3 { return }
        lastToggleTime = now
        
        // Interrupt PTT/Timer if active
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
            if newMuteState {
                // Muted -> Click (Inactive)
                let soundName = SettingsManager.shared.soundStandardMute
                if soundName != "None", let sound = NSSound(named: soundName) {
                    sound.play()
                }
            } else {
                // Unmuted -> Beep (Active)
                let soundName = SettingsManager.shared.soundStandardUnmute
                if soundName != "None", let sound = NSSound(named: soundName) {
                    sound.play()
                }
            }
        }
    }
}
