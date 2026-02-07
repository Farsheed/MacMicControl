import SwiftUI
import Carbon

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            PTTSettingsView()
                .tabItem {
                    Label("Push to Talk", systemImage: "mic.and.signal.meter")
                }
            
            DevicesSettingsView()
                .tabItem {
                    Label("Devices", systemImage: "mic")
                }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 600)
        .alert(isPresented: $settings.showHotkeyAlert) {
            Alert(
                title: Text("Shortcut Conflict"),
                message: Text(settings.hotkeyError ?? "Unknown error"),
                primaryButton: .default(Text("Keep Anyway")),
                secondaryButton: .cancel(Text("Cancel")) // Note: Cancel just dismisses too, effectively keeping it. 
                // To truly cancel, we'd need to revert. But "Keep Anyway" is what the user asked for.
            )
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecording = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if #available(macOS 13.0, *) {
                    Toggle("Launch Mac Mic Control at login", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.launchAtLogin = $0 }
                    ))
                    
                    Divider()
                }
                
                Text("Global Shortcut")
                    .font(.headline)
                
                HStack {
                    Text("Toggle Mute Feature:")
                    Spacer()
                    ShortcutRecorderButton(shortcut: $settings.shortcut, isRecording: $isRecording)
                }
                
                Text("Note: Some system shortcuts cannot be overridden.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Icon Colors")
                        .font(.headline)
                    
                    ColorPicker("Muted (Off) Background", selection: Binding(
                        get: { Color(nsColor: settings.getMutedNSColor()) },
                        set: { settings.setMutedColor(NSColor($0)) }
                    ))
                    
                    ColorPicker("Live (On) Background", selection: Binding(
                        get: { Color(nsColor: settings.getUnmutedNSColor()) },
                        set: { settings.setUnmutedColor(NSColor($0)) }
                    ))
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Icon Size")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                        Slider(value: $settings.iconScale, in: 0.5...1.5, step: 0.1)
                        Image(systemName: "circle.fill")
                            .font(.system(size: 18))
                    }
                    
                    Text("Scale: \(Int(settings.iconScale * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Blink Rate (Live)")
                        .font(.headline)
                    
                    Toggle("Blink when Unmuted", isOn: $settings.generalBlinkEnabled)
                    
                    if settings.generalBlinkEnabled {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Rate: \(String(format: "%.0f", settings.generalBlinkInterval * 1000))ms")
                                Spacer()
                            }
                            Slider(value: $settings.generalBlinkInterval, in: 0.2...2.0, step: 0.1) {
                                Text("Blink Rate")
                            } minimumValueLabel: {
                                Text("Fast")
                            } maximumValueLabel: {
                                Text("Slow")
                            }
                        }
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Feedback")
                        .font(.headline)
                    
                    Toggle("Visual notifications", isOn: $settings.generalVisualFeedback)
                    Toggle("Audio Feedback (Beep/Click)", isOn: $settings.generalAudioFeedback)
                    
                    if settings.generalAudioFeedback {
                        VStack(alignment: .leading) {
                            SoundPicker(label: "Mute Sound", selection: $settings.soundStandardMute)
                            SoundPicker(label: "Unmute Sound", selection: $settings.soundStandardUnmute)
                        }
                        .padding(.leading)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PTTSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecordingToggle = false
    @State private var isRecordingAction = false
    @State private var showTestSheet = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Master Toggle
                Toggle("Enable Push to Talk", isOn: $settings.pttEnabled)
                    .font(.headline)
                
                Divider()
                
                // Shortcuts
                Group {
                    Text("Shortcuts").font(.headline)
                    
                    HStack {
                        Text("Toggle PTT Feature:")
                        Spacer()
                        ShortcutRecorderButton(shortcut: $settings.pttToggleShortcut, isRecording: $isRecordingToggle)
                    }
                    
                    HStack {
                        Text("PTT Action (Hold):")
                        Spacer()
                        ShortcutRecorderButton(shortcut: $settings.pttActionShortcut, isRecording: $isRecordingAction)
                    }
                    
                    if settings.pttToggleShortcut == settings.pttActionShortcut {
                        Text("Warning: Same shortcut assigned to both actions.")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .disabled(!settings.pttEnabled)
                
                Group {
                    Divider()
                    
                    // Timing / Delay
                    Group {
                        Text("Timing").font(.headline)
                        
                        HStack {
                             Text("Delay Mute: \(String(format: "%.0f", settings.pttReleaseDelay))s")
                             Spacer()
                        }
                        Slider(value: $settings.pttReleaseDelay, in: 0...30.0, step: 1.0) {
                            Text("Delay Mute")
                        } minimumValueLabel: {
                            Text("0s")
                        } maximumValueLabel: {
                            Text("30s")
                        }
                        
                        Text("Time to wait before muting after releasing the key.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .disabled(!settings.pttEnabled)
                    
                    Divider()
                    
                    // Appearance
                    Group {
                        Text("Appearance").font(.headline)
                        
                        Toggle("Blink when Active", isOn: $settings.pttBlinkEnabled)
                        
                        if settings.pttBlinkEnabled {
                            ColorPicker("Blink Color (Active)", selection: Binding(
                                get: { Color(nsColor: settings.getPTTBlinkNSColor()) },
                                set: { settings.setPTTBlinkColor(NSColor($0)) }
                            ))
                        }
                        
                        ColorPicker("Inactive Background", selection: Binding(
                            get: { Color(nsColor: settings.getPTTInactiveBackgroundNSColor()) },
                            set: { settings.setPTTInactiveBackgroundColor(NSColor($0)) }
                        ))
                        
                        ColorPicker("Inactive Icon", selection: Binding(
                            get: { Color(nsColor: settings.getPTTInactiveIconNSColor()) },
                            set: { settings.setPTTInactiveIconColor(NSColor($0)) }
                        ))
                        
                        if settings.pttBlinkEnabled {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Blink Rate: \(String(format: "%.0f", settings.pttBlinkInterval * 1000))ms")
                                    Spacer()
                                }
                                Slider(value: $settings.pttBlinkInterval, in: 0.2...1.0, step: 0.1) {
                                    Text("Blink Rate")
                                } minimumValueLabel: {
                                    Text("Fast")
                                } maximumValueLabel: {
                                    Text("Slow")
                                }
                            }
                        }
                    }
                    .disabled(!settings.pttEnabled)
                    
                    Divider()
                    
                    // Feedback
                    Group {
                        Text("Feedback").font(.headline)
                        Toggle("Visual notifications", isOn: $settings.pttVisualFeedback)
                        Toggle("Audio Feedback", isOn: $settings.pttAudioFeedback)
                        
                        if settings.pttAudioFeedback {
                            VStack(alignment: .leading) {
                                SoundPicker(label: "Press (Activate)", selection: $settings.soundPTTActivate)
                                SoundPicker(label: "Release (Deactivate)", selection: $settings.soundPTTDeactivate)
                            }
                            .padding(.leading)
                        }
                    }
                    .disabled(!settings.pttEnabled)
                }
                
                Divider()
                
                // Test & Reset
                HStack {
                    Button("Reset to Defaults") {
        settings.pttEnabled = false
        settings.pttToggleShortcut = AppKeyboardShortcut(keyCode: kVK_ANSI_P, modifiers: cmdKey | shiftKey)
        settings.pttActionShortcut = AppKeyboardShortcut(keyCode: kVK_Space, modifiers: optionKey)
        settings.setPTTBlinkColor(.yellow)
                        settings.setPTTInactiveBackgroundColor(.black)
                        settings.setPTTInactiveIconColor(.white)
                        settings.pttBlinkInterval = 0.5
                        settings.pttAudioFeedback = false
                    }
                    
                    Spacer()
                    
                    Button("Test PTT") {
                        showTestSheet = true
                    }
                    .disabled(!settings.pttEnabled)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showTestSheet) {
            TestPTTView(isPresented: $showTestSheet)
        }
    }
}

struct ShortcutRecorderButton: View {
    @Binding var shortcut: AppKeyboardShortcut
    @Binding var isRecording: Bool
    
    var body: some View {
        HStack {
            ZStack {
                Text(shortcut.description)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .frame(width: 140, alignment: .center) // Fixed width for consistency
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isRecording ? Color.blue : Color.clear, lineWidth: 2)
                    )
                
                // Invisible recorder view that sits on top of the text area when recording
                if isRecording {
                    ShortcutRecorder(isRecording: $isRecording) { keyCode, modifiers in
                        let newShortcut = AppKeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
                        shortcut = newShortcut
                        // Only stop recording if it's NOT a modifier-only key
                        // (e.g. Cmd+P stops, but just Ctrl keeps recording until user clicks done)
                        if !newShortcut.isModifier {
                            isRecording = false
                        }
                    }
                    .frame(width: 140, height: 30) // Match the text area roughly
                    .opacity(0.01) // Nearly invisible but hit-testable
                }
            }
            
            Button(isRecording ? "Press Keys..." : "Change") {
                isRecording.toggle()
            }
            .buttonStyle(.bordered)
        }
    }
}

struct TestPTTView: View {
    @Binding var isPresented: Bool
    @ObservedObject var appState: AppState
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var isBlinking = false
    @State private var timer: Timer?
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        // Hack to get AppState
        if let appDelegate = NSApp.delegate as? AppDelegate {
            self.appState = appDelegate.appState
        } else {
            self.appState = AppState() // Fallback
        }
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Push to Talk Test")
                .font(.title)
                .bold()
            
            Text("Press and hold your PTT Action shortcut to test.")
                .foregroundColor(.secondary)
            
            // Visualization
            ZStack {
                Circle()
                    .fill(currentBackgroundColor)
                    .frame(width: 100, height: 100)
                
                Image(systemName: currentIconName)
                    .font(.system(size: 50))
                    .foregroundColor(currentIconColor)
            }
            .shadow(radius: 5)
            
            if appState.isPTTActive {
                Text("MIC LIVE")
                    .font(.headline)
                    .foregroundColor(.red)
            } else {
                Text("MIC MUTED")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 400, height: 350)
        .onAppear {
            startBlinkTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    func startBlinkTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: settings.pttBlinkInterval, repeats: true) { _ in
            isBlinking.toggle()
        }
    }
    
    var currentBackgroundColor: Color {
        if appState.isPTTActive {
            if settings.pttBlinkEnabled {
                return isBlinking ? Color(nsColor: settings.getPTTBlinkNSColor()) : Color(nsColor: settings.getUnmutedNSColor())
            } else {
                return Color(nsColor: settings.getUnmutedNSColor())
            }
        } else {
            return Color(nsColor: settings.getPTTInactiveBackgroundNSColor())
        }
    }
    
    var currentIconColor: Color {
        if appState.isPTTActive {
            return .white // Usually white on colored bg
        } else {
            return Color(nsColor: settings.getPTTInactiveIconNSColor())
        }
    }
    
    var currentIconName: String {
        if appState.isPTTActive {
            return "mic.fill"
        } else {
            return "mic.slash.fill"
        }
    }
}

struct DevicesSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var audioController: AudioController
    
    init() {
        // Access AudioController via AppDelegate to ensure we have the live instance
        if let appDelegate = NSApp.delegate as? AppDelegate {
            self.audioController = appDelegate.appState.audioController
        } else {
            self.audioController = AudioController() // Fallback
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // System Input Selection
                HStack {
                    Text("System input")
                        .font(.headline)
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { audioController.getDefaultInputDeviceID() ?? 0 },
                        set: { newID in
                            if let device = audioController.availableInputDevices.first(where: { $0.id == newID }) {
                                audioController.setDefaultInputDevice(device)
                            }
                        }
                    )) {
                        ForEach(audioController.availableInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Compatible devices")
                        .font(.headline)
                    Text("Disable a device to prevent Mac Mic Control muting it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 0) {
                    ForEach(audioController.availableInputDevices) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !settings.excludedDeviceIDs.contains(device.id) },
                                set: { isEnabled in
                                    if isEnabled {
                                        settings.excludedDeviceIDs.removeAll { $0 == device.id }
                                    } else {
                                        if !settings.excludedDeviceIDs.contains(device.id) {
                                            settings.excludedDeviceIDs.append(device.id)
                                        }
                                    }
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle(tint: .red))
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        
                        if device != audioController.availableInputDevices.last {
                            Divider()
                                .padding(.leading)
                        }
                    }
                }
                .cornerRadius(10)
                
                Spacer()
            }
            .padding()
        }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onRecord: (Int, Int) -> Void
    
    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onRecord = onRecord
        view.isRecording = isRecording
        return view
    }
    
    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onRecord = onRecord
        nsView.isRecording = isRecording
        
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

struct SoundPicker: View {
    let label: String
    @Binding var selection: String
    
    var body: some View {
        HStack {
            Text(label)
            
            Spacer()
            
            Picker("", selection: $selection) {
                ForEach(SettingsManager.shared.availableSounds, id: \.self) { sound in
                    Text(sound).tag(sound)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: selection) { newValue in
                if newValue == "None" { return }
                if let sound = NSSound(named: newValue) {
                    sound.play()
                }
            }
        }
    }
}
    
class KeyCaptureView: NSView {
    var onRecord: ((Int, Int) -> Void)?
    var isRecording: Bool = false
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        return isRecording
    }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording {
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.option) {
                 // Capture system shortcuts like Cmd+Q, Cmd+W, etc during recording
                 keyDown(with: event)
                 return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func flagsChanged(with event: NSEvent) {
        if !isRecording {
            super.flagsChanged(with: event)
            return
        }
        
        // Capture modifier-only keys
        var modifiers: Int = 0
        if event.modifierFlags.contains(.command) { modifiers |= cmdKey }
        if event.modifierFlags.contains(.option) { modifiers |= optionKey }
        if event.modifierFlags.contains(.control) { modifiers |= controlKey }
        if event.modifierFlags.contains(.shift) { modifiers |= shiftKey }
        
        // Use the modifier key itself as the keyCode
        // flagsChanged doesn't give a consistent keyCode for "all pressed modifiers", only the one that changed.
        // But for visual feedback and potential hotkey registration, we can use the event.keyCode.
        // HOWEVER, standard Hotkeys usually require a non-modifier key. 
        // If the user wants "Ctrl + Cmd", they are asking for a modifier-only hotkey.
        // Carbon Hotkeys technically support this if we pass the keycode of one of the modifiers.
        
        onRecord?(Int(event.keyCode), modifiers)
    }
    
    override func keyDown(with event: NSEvent) {
        if !isRecording {
            super.keyDown(with: event)
            return
        }
        
        if event.keyCode == 53 { // Esc
            // Cancel logic if needed
            return
        }
        
        var modifiers: Int = 0
        if event.modifierFlags.contains(.command) { modifiers |= cmdKey }
        if event.modifierFlags.contains(.option) { modifiers |= optionKey }
        if event.modifierFlags.contains(.control) { modifiers |= controlKey }
        if event.modifierFlags.contains(.shift) { modifiers |= shiftKey }
        
        onRecord?(Int(event.keyCode), modifiers)
    }
}
