import Foundation
import CoreAudio
import AudioToolbox
import os.log

extension Notification.Name {
    static let inputDeviceDisconnected = Notification.Name("inputDeviceDisconnected")
    static let inputDevicesChanged = Notification.Name("inputDevicesChanged")
}

enum AudioError: Error {
    case deviceNotFound
    case propertyError(OSStatus)
    case unknown
}

struct InputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let uid: String
}

class AudioController: ObservableObject {
    @Published var isMuted: Bool = false
    @Published var availableInputDevices: [InputDevice] = []
    @Published var currentInputDeviceID: AudioObjectID = kAudioObjectUnknown

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macmiccontrol", category: "AudioController")

    private var currentDeviceID: AudioObjectID? {
        didSet {
            let newID = currentDeviceID ?? kAudioObjectUnknown
            DispatchQueue.main.async { [weak self] in
                self?.currentInputDeviceID = newID
            }
        }
    }
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?

    /// Serial queue for synchronizing CoreAudio callback access
    private let audioQueue = DispatchQueue(label: "com.macmiccontrol.audiocontroller")

    init() {
        checkMuteStatus()
        startMonitoring()
        refreshInputDevices()
    }

    deinit {
        stopMonitoring()
    }

    func setDefaultInputDevice(_ device: InputDevice) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = device.id
        let size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &deviceID)
        if status != noErr {
            logger.error("Error setting default input device: \(status, privacy: .public)")
        }
    }

    func refreshInputDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)

        guard status == noErr else {
            logger.error("Error getting device list size: \(status, privacy: .public)")
            return
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)

        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)

        guard status == noErr else {
            logger.error("Error getting device list: \(status, privacy: .public)")
            return
        }

        var inputDevices: [InputDevice] = []

        for id in deviceIDs {
            // Check if device supports input
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &inputSize)

            if status == noErr && inputSize > 0 {
                // Get Name
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioObjectPropertyName,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )

                var name: CFString = "" as CFString
                var nameSize = UInt32(MemoryLayout<CFString>.size)

                status = withUnsafeMutablePointer(to: &name) { namePtr in
                    AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, namePtr)
                }

                // Get persistent UID
                let uid = Self.getDeviceUID(for: id) ?? "unknown-\(id)"

                if status == noErr {
                    inputDevices.append(InputDevice(id: id, name: name as String, uid: uid))
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.availableInputDevices = inputDevices
        }
    }

    /// Get the persistent UID string for an audio device
    static func getDeviceUID(for deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafeMutablePointer(to: &uid) { uidPtr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, uidPtr)
        }
        
        if status == noErr {
            return uid as String
        }
        return nil
    }

    func toggleMute() {
        let newMuteStatus = !isMuted
        setMute(newMuteStatus)
    }

    func setMute(_ mute: Bool) {
        guard let deviceID = getDefaultInputDeviceID() else {
            logger.warning("No default input device found when trying to mute")
            return
        }

        // Check exclusion using persistent UID
        if let uid = Self.getDeviceUID(for: deviceID),
           SettingsManager.shared.excludedDeviceUIDs.contains(uid) {
            logger.info("Device \(uid, privacy: .public) is excluded from muting.")
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var muteValue: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &muteValue)
        if status == noErr {
            DispatchQueue.main.async { [weak self] in
                self?.isMuted = mute
            }
        } else {
            logger.error("Error setting mute status: \(status, privacy: .public)")
        }
    }

    func checkMuteStatus() {
        guard let deviceID = getDefaultInputDeviceID() else {
            DispatchQueue.main.async { [weak self] in
                self?.isMuted = true
            }
            return
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var muteValue: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteValue)
        if status == noErr {
            DispatchQueue.main.async { [weak self] in
                self?.isMuted = (muteValue == 1)
            }
        } else {
            logger.error("Error getting mute status: \(status, privacy: .public)")
        }
    }

    func isInputDeviceAvailable() -> Bool {
        return getDefaultInputDeviceID() != nil
    }

    func getDefaultInputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        if status == noErr && deviceID != kAudioObjectUnknown {
            return deviceID
        }
        return nil
    }

    private func startMonitoring() {
        // Monitor Default Device changes
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.audioQueue.async {
                self?.handleDeviceChange()
            }
        }
        self.defaultDeviceListenerBlock = defaultDeviceListener

        var status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, nil, defaultDeviceListener)
        if status != noErr {
            logger.error("Error adding default device listener: \(status, privacy: .public)")
        }

        // Monitor Device List changes (added/removed)
        var deviceListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.audioQueue.async {
                self?.refreshInputDevices()
            }
        }
        self.deviceListListenerBlock = deviceListListener

        status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, nil, deviceListListener)
        if status != noErr {
            logger.error("Error adding device list listener: \(status, privacy: .public)")
        }

        // Initial setup
        audioQueue.async { [weak self] in
            self?.handleDeviceChange()
        }
    }

    private func stopMonitoring() {
        // Remove default device listener
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        if let listener = defaultDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, nil, listener)
            defaultDeviceListenerBlock = nil
        }

        // Remove device list listener
        var deviceListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        if let listener = deviceListListenerBlock {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, nil, listener)
            deviceListListenerBlock = nil
        }

        // Remove mute listener for current device
        if let deviceID = currentDeviceID {
            removeMuteListener(for: deviceID)
        }
    }

    /// Called on audioQueue for thread safety
    private func handleDeviceChange() {
        let newDeviceID = getDefaultInputDeviceID()

        if currentDeviceID != newDeviceID {
            if let oldID = currentDeviceID {
                removeMuteListener(for: oldID)
            }

            currentDeviceID = newDeviceID

            if let newID = newDeviceID {
                addMuteListener(for: newID)
            }

            checkMuteStatus()

            DispatchQueue.main.async {
                if newDeviceID == nil {
                    NotificationCenter.default.post(name: .inputDeviceDisconnected, object: nil)
                }
            }
        }
    }

    private func addMuteListener(for deviceID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        let listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.audioQueue.async {
                self?.checkMuteStatus()
            }
        }
        self.muteListenerBlock = listenerBlock

        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, listenerBlock)
        if status != noErr {
            logger.error("Error adding mute listener: \(status, privacy: .public)")
        }
    }

    private func removeMuteListener(for deviceID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        if let listener = muteListenerBlock {
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, listener)
            muteListenerBlock = nil
        }
    }
}
