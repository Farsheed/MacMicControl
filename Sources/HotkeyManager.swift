import Cocoa
import Carbon
import Combine

protocol HotkeyDelegate: AnyObject {
    func toggleMuteHotkeyPressed()
    func pttToggleHotkeyPressed()
    func pttActionHotkeyPressed()
    func pttActionHotkeyReleased()
}

class HotkeyManager {
    weak var delegate: HotkeyDelegate?
    var eventHandler: EventHandlerRef?
    
    // Hotkey References
    var toggleMuteHotKeyRef: EventHotKeyRef?
    var pttToggleHotKeyRef: EventHotKeyRef?
    var pttActionHotKeyRef: EventHotKeyRef?
    
    // Modifier Monitors (for Modifier-only PTT)
    private var modifierMonitorGlobal: Any?
    private var modifierMonitorLocal: Any?
    private var isModifierPTTActive: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    // IDs
    private let kToggleMuteID: UInt32 = 1
    private let kPTTToggleID: UInt32 = 2
    private let kPTTActionID: UInt32 = 3
    private let kSignature: OSType = 0x1234
    
    init(delegate: HotkeyDelegate) {
        self.delegate = delegate
        
        print("HotkeyManager: Initializing...")
        
        // Initial registration
        updateToggleMuteHotkey(SettingsManager.shared.shortcut)
        updatePTTToggleHotkey(SettingsManager.shared.pttToggleShortcut)
        updatePTTActionHotkey(SettingsManager.shared.pttActionShortcut)
        
        // Listen for changes
        SettingsManager.shared.$shortcut
            .sink { [weak self] newShortcut in
                self?.updateToggleMuteHotkey(newShortcut)
            }
            .store(in: &cancellables)
            
        SettingsManager.shared.$pttToggleShortcut
            .sink { [weak self] newShortcut in
                self?.updatePTTToggleHotkey(newShortcut)
            }
            .store(in: &cancellables)
            
        SettingsManager.shared.$pttActionShortcut
            .sink { [weak self] newShortcut in
                self?.updatePTTActionHotkey(newShortcut)
            }
            .store(in: &cancellables)
            
        installEventHandler()
    }
    
    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(GetApplicationEventTarget(), { (handler, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if status != noErr {
                return status
            }
            
            let kind = GetEventKind(event)
            
            if kind == kEventHotKeyPressed {
                switch hotKeyID.id {
                case manager.kToggleMuteID:
                    print("HotkeyManager: Toggle Mute Pressed")
                    manager.delegate?.toggleMuteHotkeyPressed()
                case manager.kPTTToggleID:
                    print("HotkeyManager: PTT Toggle Pressed")
                    manager.delegate?.pttToggleHotkeyPressed()
                case manager.kPTTActionID:
                    print("HotkeyManager: PTT Action Pressed")
                    manager.delegate?.pttActionHotkeyPressed()
                default:
                    break
                }
            } else if kind == kEventHotKeyReleased {
                if hotKeyID.id == manager.kPTTActionID {
                    print("HotkeyManager: PTT Action Released")
                    manager.delegate?.pttActionHotkeyReleased()
                }
            }
            
            return noErr
        }, 2, &eventTypes, observer, &eventHandler)
        
        if status != noErr {
            print("HotkeyManager: Failed to install event handler: \(status)")
        }
    }
    
    func updateToggleMuteHotkey(_ shortcut: AppKeyboardShortcut) {
        if let ref = toggleMuteHotKeyRef {
            UnregisterEventHotKey(ref)
            toggleMuteHotKeyRef = nil
        }
        
        let hotKeyID = EventHotKeyID(signature: kSignature, id: kToggleMuteID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        
        if status == noErr {
            toggleMuteHotKeyRef = ref
            print("HotkeyManager: Registered Toggle Mute: \(shortcut.description)")
        } else if status == eventHotKeyExistsErr {
            print("HotkeyManager: Failed to register Toggle Mute (Exists): \(status)")
            DispatchQueue.main.async {
                SettingsManager.shared.reportHotkeyError(shortcut: shortcut, type: "Toggle Mute")
            }
        } else {
            print("HotkeyManager: Failed to register Toggle Mute: \(status)")
        }
    }
    
    func updatePTTToggleHotkey(_ shortcut: AppKeyboardShortcut) {
        if let ref = pttToggleHotKeyRef {
            UnregisterEventHotKey(ref)
            pttToggleHotKeyRef = nil
        }
        
        let hotKeyID = EventHotKeyID(signature: kSignature, id: kPTTToggleID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        
        if status == noErr {
            pttToggleHotKeyRef = ref
            print("HotkeyManager: Registered PTT Toggle: \(shortcut.description)")
        } else if status == eventHotKeyExistsErr {
            print("HotkeyManager: Failed to register PTT Toggle (Exists): \(status)")
            DispatchQueue.main.async {
                SettingsManager.shared.reportHotkeyError(shortcut: shortcut, type: "PTT Toggle")
            }
        } else {
            print("HotkeyManager: Failed to register PTT Toggle: \(status)")
        }
    }
    
    func updatePTTActionHotkey(_ shortcut: AppKeyboardShortcut) {
        // Cleanup old hotkey
        if let ref = pttActionHotKeyRef {
            UnregisterEventHotKey(ref)
            pttActionHotKeyRef = nil
        }
        
        // Cleanup old monitors
        if let monitor = modifierMonitorGlobal { NSEvent.removeMonitor(monitor); modifierMonitorGlobal = nil }
        if let monitor = modifierMonitorLocal { NSEvent.removeMonitor(monitor); modifierMonitorLocal = nil }
        isModifierPTTActive = false
        
        if shortcut.isModifier {
            setupModifierMonitor(shortcut)
            print("HotkeyManager: Registered Modifier PTT: \(shortcut.description)")
        } else {
            let hotKeyID = EventHotKeyID(signature: kSignature, id: kPTTActionID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
            
            if status == noErr {
                pttActionHotKeyRef = ref
                print("HotkeyManager: Registered PTT Action: \(shortcut.description)")
            } else if status == eventHotKeyExistsErr {
                print("HotkeyManager: Failed to register PTT Action (Exists): \(status)")
                DispatchQueue.main.async {
                    SettingsManager.shared.reportHotkeyError(shortcut: shortcut, type: "PTT Action")
                }
            } else {
                print("HotkeyManager: Failed to register PTT Action: \(status)")
            }
        }
    }
    
    private func setupModifierMonitor(_ shortcut: AppKeyboardShortcut) {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }
            
            if self.matchesModifiers(event.modifierFlags, shortcut: shortcut) {
                // If modifiers match, activate PTT if not already active
                if !self.isModifierPTTActive {
                    self.isModifierPTTActive = true
                    self.delegate?.pttActionHotkeyPressed()
                }
            } else {
                // If modifiers don't match, release if we were active
                if self.isModifierPTTActive {
                    self.isModifierPTTActive = false
                    self.delegate?.pttActionHotkeyReleased()
                }
            }
        }
        
        modifierMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        modifierMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(event)
            return event
        }
    }
    
    private func matchesModifiers(_ flags: NSEvent.ModifierFlags, shortcut: AppKeyboardShortcut) -> Bool {
        var carbonFlags: Int = 0
        if flags.contains(.command) { carbonFlags |= cmdKey }
        if flags.contains(.shift) { carbonFlags |= shiftKey }
        if flags.contains(.option) { carbonFlags |= optionKey }
        if flags.contains(.control) { carbonFlags |= controlKey }
        
        // Check if the flags match the shortcut's modifiers
        // Note: shortcut.modifiers might include bits that are not in the standard set (e.g. alphaLock?)
        // Let's filter shortcut.modifiers to only the 4 main ones.
        let mask = cmdKey | shiftKey | optionKey | controlKey
        return (carbonFlags & mask) == (shortcut.modifiers & mask)
    }
    
    deinit {
        if let ref = toggleMuteHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = pttToggleHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = pttActionHotKeyRef { UnregisterEventHotKey(ref) }
        
        if let monitor = modifierMonitorGlobal { NSEvent.removeMonitor(monitor) }
        if let monitor = modifierMonitorLocal { NSEvent.removeMonitor(monitor) }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
