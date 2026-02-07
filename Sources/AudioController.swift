import Foundation
import CoreAudio
import AudioToolbox

extension Notification.Name {
    static let inputDeviceDisconnected = Notification.Name("inputDeviceDisconnected")
    static let inputDevicesChanged = Notification.Name("inputDevicesChanged")
}

struct InputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
}

class AudioController: ObservableObject {
    @Published var isMuted: Bool = false
    @Published var availableInputDevices: [InputDevice] = []
    
    private var audioObjectPropertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
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
            print("Error setting default input device: \(status)")
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
            print("Error getting device list size: \(status)")
            return
        }
        
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: count)
        
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceIDs)
        
        guard status == noErr else {
            print("Error getting device list: \(status)")
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
                
                status = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
                
                if status == noErr {
                    inputDevices.append(InputDevice(id: id, name: name as String))
                }
            }
        }
        
        DispatchQueue.main.async {
            self.availableInputDevices = inputDevices
        }
    }
    
    func toggleMute() {
        let newMuteStatus = !isMuted
        setMute(newMuteStatus)
    }
    
    func setMute(_ mute: Bool) {
        guard let deviceID = getDefaultInputDeviceID() else { return }
        
        // Check exclusion
        if SettingsManager.shared.excludedDeviceIDs.contains(deviceID) {
            print("Device \(deviceID) is excluded from muting.")
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
            DispatchQueue.main.async {
                self.isMuted = mute
            }
        } else {
            print("Error setting mute status: \(status)")
        }
    }
    
    func checkMuteStatus() {
        guard let deviceID = getDefaultInputDeviceID() else {
            DispatchQueue.main.async {
                self.isMuted = true // Safe default?
            }
            return
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain // Often 0
        )
        
        // Some devices might use a different element or scope, but Input/Master is standard.
        // Try getting the value.
        
        var muteValue: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muteValue)
        if status == noErr {
            DispatchQueue.main.async {
                self.isMuted = (muteValue == 1)
            }
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
    
    private var currentDeviceID: AudioObjectID?
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?

    private func startMonitoring() {
        // Monitor Default Device changes
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleDeviceChange()
        }
        self.defaultDeviceListenerBlock = listenerBlock
        
        var status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, nil, listenerBlock)
        if status != noErr {
            print("Error adding default device listener: \(status)")
        }
        
        // Monitor Device List changes (added/removed)
        var deviceListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let deviceListListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshInputDevices()
        }
        
        status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &deviceListAddress, nil, deviceListListener)
        if status != noErr {
            print("Error adding device list listener: \(status)")
        }
        
        // Initial setup
        handleDeviceChange()
    }
    
    private func stopMonitoring() {
        // Remove system listener
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if let listener = defaultDeviceListenerBlock {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
            defaultDeviceListenerBlock = nil
        }
        
        // Remove device listener
        if let deviceID = currentDeviceID {
            removeMuteListener(for: deviceID)
        }
    }
    
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
            self?.checkMuteStatus()
        }
        self.muteListenerBlock = listenerBlock
        
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, listenerBlock)
        if status != noErr {
            print("Error adding mute listener: \(status)")
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
