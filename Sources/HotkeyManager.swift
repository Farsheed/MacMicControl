import Cocoa
import Carbon
import Combine
import os.log

protocol HotkeyDelegate: AnyObject {
    func toggleMuteHotkeyPressed()
    func pttToggleHotkeyPressed()
    func pttActionHotkeyPressed()
    func pttActionHotkeyReleased()
}

class HotkeyManager {
    weak var delegate: HotkeyDelegate?
    var eventHandler: EventHandlerRef?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macmiccontrol", category: "HotkeyManager")

    // Hotkey References
    var toggleMuteHotKeyRef: EventHotKeyRef?
    var pttToggleHotKeyRef: EventHotKeyRef?
    var pttActionHotKeyRef: EventHotKeyRef?

    // Modifier Monitors (for Modifier-only PTT)
    private var modifierMonitorGlobal: Any?
    private var modifierMonitorLocal: Any?
    private var isModifierPTTActive: Bool = false

    private var cancellables = Set<AnyCancellable>()

    // Previous shortcut values for revert support
    private var previousToggleMuteShortcut: AppKeyboardShortcut?
    private var previousPTTToggleShortcut: AppKeyboardShortcut?
    private var previousPTTActionShortcut: AppKeyboardShortcut?

    // IDs
    private let kToggleMuteID: UInt32 = 1
    private let kPTTToggleID: UInt32 = 2
    private let kPTTActionID: UInt32 = 3
    private let kSignature: OSType = 0x1234

    init(delegate: HotkeyDelegate) {
        self.delegate = delegate

        // Initial registration
        updateToggleMuteHotkey(SettingsManager.shared.shortcut)
        updatePTTToggleHotkey(SettingsManager.shared.pttToggleShortcut)
        updatePTTActionHotkey(SettingsManager.shared.pttActionShortcut)

        // Listen for changes
        SettingsManager.shared.$shortcut
            .dropFirst()
            .sink { [weak self] newShortcut in
                self?.updateToggleMuteHotkey(newShortcut)
            }
            .store(in: &cancellables)

        SettingsManager.shared.$pttToggleShortcut
            .dropFirst()
            .sink { [weak self] newShortcut in
                self?.updatePTTToggleHotkey(newShortcut)
            }
            .store(in: &cancellables)

        SettingsManager.shared.$pttActionShortcut
            .dropFirst()
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
                    manager.delegate?.toggleMuteHotkeyPressed()
                case manager.kPTTToggleID:
                    manager.delegate?.pttToggleHotkeyPressed()
                case manager.kPTTActionID:
                    manager.delegate?.pttActionHotkeyPressed()
                default:
                    break
                }
            } else if kind == kEventHotKeyReleased {
                if hotKeyID.id == manager.kPTTActionID {
                    manager.delegate?.pttActionHotkeyReleased()
                }
            }

            return noErr
        }, 2, &eventTypes, observer, &eventHandler)

        if status != noErr {
            logger.error("Failed to install event handler: \(status, privacy: .public)")
        }
    }

    func updateToggleMuteHotkey(_ shortcut: AppKeyboardShortcut) {
        let oldShortcut = previousToggleMuteShortcut

        if let ref = toggleMuteHotKeyRef {
            UnregisterEventHotKey(ref)
            toggleMuteHotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: kSignature, id: kToggleMuteID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)

        if status == noErr {
            toggleMuteHotKeyRef = ref
            previousToggleMuteShortcut = shortcut
        } else if status == eventHotKeyExistsErr {
            DispatchQueue.main.async {
                SettingsManager.shared.reportHotkeyError(shortcut: shortcut, type: "Toggle Mute") {
                    if let old = oldShortcut {
                        SettingsManager.shared.shortcut = old
                    }
                }
            }
            previousToggleMuteShortcut = shortcut
        } else {
            logger.error("Failed to register Toggle Mute hotkey: \(status, privacy: .public)")
            previousToggleMuteShortcut = shortcut
        }
    }

    func updatePTTToggleHotkey(_ shortcut: AppKeyboardShortcut) {
        let oldShortcut = previousPTTToggleShortcut

        if let ref = pttToggleHotKeyRef {
            UnregisterEventHotKey(ref)
            pttToggleHotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: kSignature, id: kPTTToggleID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)

        if status == noErr {
            pttToggleHotKeyRef = ref
            previousPTTToggleShortcut = shortcut
        } else if status == eventHotKeyExistsErr {
            DispatchQueue.main.async {
                SettingsManager.shared.reportHotkeyError(shortcut: shortcut, type: "PTT Toggle") {
                    if let old = oldShortcut {
                        SettingsManager.shared.pttToggleShortcut = old
                    }
                }
            }
            previousPTTToggleShortcut = shortcut
        } else {
            logger.error("Failed to register PTT Toggle hotkey: \(status, privacy: .public)")
            previousPTTToggleShortcut = shortcut
        }
    }

    func updatePTTActionHotkey(_ shortcut: AppKeyboardShortcut) {
        let oldShortcut = previousPTTActionShortcut

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
            previousPTTActionShortcut = shortcut
        } else {
            let hotKeyID = EventHotKeyID(signature: kSignature, id: kPTTActionID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)

            if status == noErr {
                pttActionHotKeyRef = ref
                previousPTTActionShortcut = shortcut
            } else if status == eventHotKeyExistsErr {
                DispatchQueue.main.async {
                    SettingsManager.shared.reportHotkeyError(shortcut: shortcut, type: "PTT Action") {
                        if let old = oldShortcut {
                            SettingsManager.shared.pttActionShortcut = old
                        }
                    }
                }
                previousPTTActionShortcut = shortcut
            } else {
                logger.error("Failed to register PTT Action hotkey: \(status, privacy: .public)")
                previousPTTActionShortcut = shortcut
            }
        }
    }

    private func setupModifierMonitor(_ shortcut: AppKeyboardShortcut) {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self = self else { return }

            if self.matchesModifiers(event.modifierFlags, shortcut: shortcut) {
                if !self.isModifierPTTActive {
                    self.isModifierPTTActive = true
                    self.delegate?.pttActionHotkeyPressed()
                }
            } else {
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
