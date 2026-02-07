import Foundation
import Carbon
import AppKit
import SwiftUI
import Combine
import ServiceManagement

struct AppKeyboardShortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int // Carbon modifier flags
    
    var carbonKeyCode: UInt32 { UInt32(keyCode) }
    var carbonModifiers: UInt32 { UInt32(modifiers) }
    
    var isModifier: Bool {
        return [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }
    
    static let defaultShortcut = AppKeyboardShortcut(keyCode: kVK_ANSI_M, modifiers: cmdKey | shiftKey)
    
    var description: String {
        var str = ""
        if (modifiers & cmdKey) != 0 { str += "⌘" }
        if (modifiers & shiftKey) != 0 { str += "⇧" }
        if (modifiers & optionKey) != 0 { str += "⌥" }
        if (modifiers & controlKey) != 0 { str += "⌃" }
        
        str += keyString(for: keyCode)
        return str
    }
    
    private func keyString(for code: Int) -> String {
        // Simple mapping for common keys, incomplete but sufficient for now
        switch code {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_Quote: return "\""
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Grave: return "`"
        case kVK_Space: return "Space"
        case kVK_Command: return "" // Handled by modifiers
        case kVK_Shift: return ""
        case kVK_Option: return ""
        case kVK_Control: return ""
        case kVK_RightShift: return ""
        case kVK_RightOption: return ""
        case kVK_RightControl: return ""
        default: return "?"
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status == .enabled { return }
                        try SMAppService.mainApp.register()
                        print("App registered for launch at login")
                    } else {
                        if SMAppService.mainApp.status == .notRegistered { return }
                        try SMAppService.mainApp.unregister()
                        print("App unregistered from launch at login")
                    }
                    objectWillChange.send()
                } catch {
                    print("Failed to toggle launch at login: \(error)")
                }
            }
        }
    }
    
    @Published var shortcut: AppKeyboardShortcut {
        didSet {
            saveShortcut()
        }
    }
    
    @Published var mutedColor: Data {
        didSet {
            UserDefaults.standard.set(mutedColor, forKey: SettingsManager.kMutedColorKey)
        }
    }
    
    @Published var unmutedColor: Data {
        didSet {
            UserDefaults.standard.set(unmutedColor, forKey: SettingsManager.kUnmutedColorKey)
        }
    }
    
    @Published var iconScale: Double {
        didSet {
            UserDefaults.standard.set(iconScale, forKey: SettingsManager.kIconScaleKey)
        }
    }
    
    @Published var pttEnabled: Bool {
        didSet { UserDefaults.standard.set(pttEnabled, forKey: SettingsManager.kPTTEnabledKey) }
    }
    
    @Published var pttToggleShortcut: AppKeyboardShortcut {
        didSet {
            if let encoded = try? JSONEncoder().encode(pttToggleShortcut) {
                UserDefaults.standard.set(encoded, forKey: SettingsManager.kPTTToggleShortcutKey)
            }
        }
    }
    
    @Published var pttActionShortcut: AppKeyboardShortcut {
        didSet {
             if let encoded = try? JSONEncoder().encode(pttActionShortcut) {
                UserDefaults.standard.set(encoded, forKey: SettingsManager.kPTTActionShortcutKey)
            }
        }
    }
    
    @Published var pttBlinkEnabled: Bool {
        didSet { UserDefaults.standard.set(pttBlinkEnabled, forKey: SettingsManager.kPTTBlinkEnabledKey) }
    }
    
    @Published var pttBlinkColor: Data {
        didSet { UserDefaults.standard.set(pttBlinkColor, forKey: SettingsManager.kPTTBlinkColorKey) }
    }
    
    @Published var pttInactiveBackgroundColor: Data {
        didSet { UserDefaults.standard.set(pttInactiveBackgroundColor, forKey: SettingsManager.kPTTInactiveBackgroundColorKey) }
    }
    
    @Published var pttInactiveIconColor: Data {
        didSet { UserDefaults.standard.set(pttInactiveIconColor, forKey: SettingsManager.kPTTInactiveIconColorKey) }
    }
    
    @Published var pttBlinkInterval: Double {
        didSet { UserDefaults.standard.set(pttBlinkInterval, forKey: SettingsManager.kPTTBlinkIntervalKey) }
    }
    
    @Published var pttReleaseDelay: Double {
        didSet { UserDefaults.standard.set(pttReleaseDelay, forKey: SettingsManager.kPTTReleaseDelayKey) }
    }
    
    @Published var pttAudioFeedback: Bool {
        didSet { UserDefaults.standard.set(pttAudioFeedback, forKey: SettingsManager.kPTTAudioFeedbackKey) }
    }
    
    @Published var generalAudioFeedback: Bool {
        didSet { UserDefaults.standard.set(generalAudioFeedback, forKey: SettingsManager.kGeneralAudioFeedbackKey) }
    }
    
    @Published var generalVisualFeedback: Bool {
        didSet { UserDefaults.standard.set(generalVisualFeedback, forKey: SettingsManager.kGeneralVisualFeedbackKey) }
    }
    
    @Published var pttVisualFeedback: Bool {
        didSet { UserDefaults.standard.set(pttVisualFeedback, forKey: SettingsManager.kPTTVisualFeedbackKey) }
    }
    
    @Published var excludedDeviceIDs: [UInt32] {
        didSet {
             UserDefaults.standard.set(excludedDeviceIDs, forKey: SettingsManager.kExcludedDeviceIDsKey)
        }
    }
    
    @Published var generalBlinkEnabled: Bool {
        didSet { UserDefaults.standard.set(generalBlinkEnabled, forKey: SettingsManager.kGeneralBlinkEnabledKey) }
    }
    
    @Published var generalBlinkInterval: Double {
        didSet { UserDefaults.standard.set(generalBlinkInterval, forKey: SettingsManager.kGeneralBlinkIntervalKey) }
    }
    
    // Sound Settings
    @Published var soundStandardMute: String {
        didSet { UserDefaults.standard.set(soundStandardMute, forKey: SettingsManager.kSoundStandardMuteKey) }
    }
    @Published var soundStandardUnmute: String {
        didSet { UserDefaults.standard.set(soundStandardUnmute, forKey: SettingsManager.kSoundStandardUnmuteKey) }
    }
    @Published var soundPTTActivate: String {
        didSet { UserDefaults.standard.set(soundPTTActivate, forKey: SettingsManager.kSoundPTTActivateKey) }
    }
    @Published var soundPTTDeactivate: String {
        didSet { UserDefaults.standard.set(soundPTTDeactivate, forKey: SettingsManager.kSoundPTTDeactivateKey) }
    }
    
    @Published var hotkeyError: String?
    @Published var showHotkeyAlert: Bool = false
    
    func reportHotkeyError(shortcut: AppKeyboardShortcut, type: String) {
        self.hotkeyError = "The shortcut '\(shortcut.description)' for \(type) is already in use by another application or the system.\n\nDo you want to keep this assignment? It may not work until the conflict is resolved."
        self.showHotkeyAlert = true
    }
    
    private static let kShortcutKey = "globalShortcut"
    private static let kMutedColorKey = "mutedColor"
    private static let kUnmutedColorKey = "unmutedColor"
    private static let kIconScaleKey = "iconScale"
    
    private static let kPTTEnabledKey = "pttEnabled"
    private static let kPTTToggleShortcutKey = "pttToggleShortcut"
    private static let kPTTActionShortcutKey = "pttActionShortcut"
    private static let kPTTBlinkEnabledKey = "pttBlinkEnabled"
    private static let kPTTBlinkColorKey = "pttBlinkColor"
    private static let kPTTInactiveBackgroundColorKey = "pttInactiveBackgroundColor"
    private static let kPTTInactiveIconColorKey = "pttInactiveIconColor"
    private static let kPTTBlinkIntervalKey = "pttBlinkInterval"
    private static let kPTTReleaseDelayKey = "pttReleaseDelay"
    private static let kPTTAudioFeedbackKey = "pttAudioFeedback"
    private static let kPTTVisualFeedbackKey = "pttVisualFeedback"
    private static let kGeneralAudioFeedbackKey = "generalAudioFeedback"
    private static let kGeneralVisualFeedbackKey = "generalVisualFeedback"
    private static let kGeneralBlinkEnabledKey = "generalBlinkEnabled"
    private static let kGeneralBlinkIntervalKey = "generalBlinkInterval"
    
    private static let kSoundStandardMuteKey = "soundStandardMute"
    private static let kSoundStandardUnmuteKey = "soundStandardUnmute"
    private static let kSoundPTTActivateKey = "soundPTTActivate"
    private static let kSoundPTTDeactivateKey = "soundPTTDeactivate"
    
    private static let kExcludedDeviceIDsKey = "excludedDeviceIDs"
    
    let availableSounds = [
        "None", "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", 
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
    
    init() {
        if let data = UserDefaults.standard.data(forKey: SettingsManager.kShortcutKey),
           let decoded = try? JSONDecoder().decode(AppKeyboardShortcut.self, from: data) {
            self.shortcut = decoded
        } else {
            self.shortcut = .defaultShortcut
        }
        
        if let data = UserDefaults.standard.data(forKey: SettingsManager.kMutedColorKey) {
            self.mutedColor = data
        } else {
            // Default Blue
            self.mutedColor = try! NSKeyedArchiver.archivedData(withRootObject: NSColor.systemBlue, requiringSecureCoding: false)
        }
        
        if let data = UserDefaults.standard.data(forKey: SettingsManager.kUnmutedColorKey) {
            self.unmutedColor = data
        } else {
            // Default Red
            self.unmutedColor = try! NSKeyedArchiver.archivedData(withRootObject: NSColor.systemRed, requiringSecureCoding: false)
        }
        
        // Default Scale 1.0
        let savedScale = UserDefaults.standard.double(forKey: SettingsManager.kIconScaleKey)
        self.iconScale = savedScale > 0 ? savedScale : 1.0
        
        self.pttEnabled = UserDefaults.standard.bool(forKey: SettingsManager.kPTTEnabledKey)
        
        if let data = UserDefaults.standard.data(forKey: SettingsManager.kPTTToggleShortcutKey),
           let decoded = try? JSONDecoder().decode(AppKeyboardShortcut.self, from: data) {
            self.pttToggleShortcut = decoded
        } else {
            self.pttToggleShortcut = AppKeyboardShortcut(keyCode: kVK_ANSI_P, modifiers: cmdKey | shiftKey)
        }
        
        if let data = UserDefaults.standard.data(forKey: SettingsManager.kPTTActionShortcutKey),
           let decoded = try? JSONDecoder().decode(AppKeyboardShortcut.self, from: data) {
            self.pttActionShortcut = decoded
        } else {
            self.pttActionShortcut = AppKeyboardShortcut(keyCode: kVK_Space, modifiers: optionKey)
        }
        
        self.pttBlinkEnabled = UserDefaults.standard.object(forKey: SettingsManager.kPTTBlinkEnabledKey) as? Bool ?? true
        self.pttBlinkColor = UserDefaults.standard.data(forKey: SettingsManager.kPTTBlinkColorKey) ?? (try! NSKeyedArchiver.archivedData(withRootObject: NSColor.yellow, requiringSecureCoding: false))
        self.pttInactiveBackgroundColor = UserDefaults.standard.data(forKey: SettingsManager.kPTTInactiveBackgroundColorKey) ?? (try! NSKeyedArchiver.archivedData(withRootObject: NSColor.black, requiringSecureCoding: false))
        self.pttInactiveIconColor = UserDefaults.standard.data(forKey: SettingsManager.kPTTInactiveIconColorKey) ?? (try! NSKeyedArchiver.archivedData(withRootObject: NSColor.white, requiringSecureCoding: false))
        
        let savedInterval = UserDefaults.standard.double(forKey: SettingsManager.kPTTBlinkIntervalKey)
        self.pttBlinkInterval = savedInterval == 0 ? 0.5 : savedInterval
        
        self.pttReleaseDelay = UserDefaults.standard.double(forKey: SettingsManager.kPTTReleaseDelayKey)
        
        self.pttAudioFeedback = UserDefaults.standard.bool(forKey: SettingsManager.kPTTAudioFeedbackKey)
        self.pttVisualFeedback = UserDefaults.standard.object(forKey: SettingsManager.kPTTVisualFeedbackKey) as? Bool ?? true
        self.generalAudioFeedback = UserDefaults.standard.bool(forKey: SettingsManager.kGeneralAudioFeedbackKey)
        self.generalVisualFeedback = UserDefaults.standard.object(forKey: SettingsManager.kGeneralVisualFeedbackKey) as? Bool ?? true
        
        self.generalBlinkEnabled = UserDefaults.standard.object(forKey: SettingsManager.kGeneralBlinkEnabledKey) as? Bool ?? true
        let savedGeneralInterval = UserDefaults.standard.double(forKey: SettingsManager.kGeneralBlinkIntervalKey)
        self.generalBlinkInterval = savedGeneralInterval == 0 ? 0.8 : savedGeneralInterval
        
        // Initialize Sounds
        let savedStandardMute = UserDefaults.standard.string(forKey: SettingsManager.kSoundStandardMuteKey)
        self.soundStandardMute = savedStandardMute ?? "Tink"
        
        let savedStandardUnmute = UserDefaults.standard.string(forKey: SettingsManager.kSoundStandardUnmuteKey)
        self.soundStandardUnmute = savedStandardUnmute ?? "Pop"
        
        let savedPTTActivate = UserDefaults.standard.string(forKey: SettingsManager.kSoundPTTActivateKey)
        self.soundPTTActivate = savedPTTActivate ?? "Pop"
        
        let savedPTTDeactivate = UserDefaults.standard.string(forKey: SettingsManager.kSoundPTTDeactivateKey)
        self.soundPTTDeactivate = savedPTTDeactivate ?? "Tink"
        
        self.excludedDeviceIDs = UserDefaults.standard.array(forKey: SettingsManager.kExcludedDeviceIDsKey) as? [UInt32] ?? []
    }
    
    func getMutedNSColor() -> NSColor {
        if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: mutedColor) {
            return color
        }
        return .systemBlue
    }
    
    func getUnmutedNSColor() -> NSColor {
        if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: unmutedColor) {
            return color
        }
        return .systemRed
    }
    
    func setMutedColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            self.mutedColor = data
        }
    }
    
    func setUnmutedColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            self.unmutedColor = data
        }
    }
    
    func getPTTBlinkNSColor() -> NSColor {
        if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: pttBlinkColor) {
            return color
        }
        return .yellow
    }
    
    func setPTTBlinkColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            self.pttBlinkColor = data
        }
    }
    
    func getPTTInactiveBackgroundNSColor() -> NSColor {
        if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: pttInactiveBackgroundColor) {
            return color
        }
        return .black
    }
    
    func setPTTInactiveBackgroundColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            self.pttInactiveBackgroundColor = data
        }
    }
    
    func getPTTInactiveIconNSColor() -> NSColor {
        if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: pttInactiveIconColor) {
            return color
        }
        return .white
    }
    
    func setPTTInactiveIconColor(_ color: NSColor) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
            self.pttInactiveIconColor = data
        }
    }
    
    private func saveShortcut() {
        if let encoded = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(encoded, forKey: SettingsManager.kShortcutKey)
        }
    }
}
