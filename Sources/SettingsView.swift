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
        .frame(width: 550, height: 600)
        .alert(isPresented: $settings.showHotkeyAlert) {
            Alert(
                title: Text("Shortcut Conflict"),
                message: Text(settings.hotkeyError ?? "Unknown error"),
                primaryButton: .default(Text("Keep Anyway")),
                secondaryButton: .cancel(Text("Revert")) {
                    settings.hotkeyRevertAction?()
                    settings.hotkeyRevertAction = nil
                }
            )
        }
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecording = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if #available(macOS 13.0, *) {
                    GroupBox {
                        Toggle("Launch Mac Mic Control at login", isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { settings.launchAtLogin = $0 }
                        ))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox(label: Text("Global Shortcut")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Toggle Mute")
                            Spacer()
                            ShortcutRecorderButton(shortcut: $settings.shortcut, isRecording: $isRecording)
                        }
                        
                        Text("Note: Some system shortcuts cannot be overridden.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(4)
                }

                GroupBox(label: Text("Appearance")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ColorPicker("Muted (Off) Background", selection: Binding(
                            get: { Color(nsColor: settings.getMutedNSColor()) },
                            set: { settings.setMutedColor(NSColor($0)) }
                        ))
                        
                        ColorPicker("Live (On) Background", selection: Binding(
                            get: { Color(nsColor: settings.getUnmutedNSColor()) },
                            set: { settings.setUnmutedColor(NSColor($0)) }
                        ))

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Icon Scale")
                                Spacer()
                                Text("\(Int(settings.iconScale * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.iconScale, in: 0.5...1.5, step: 0.1)
                        }
                        
                        Divider()
                        
                        Toggle("Blink when Unmuted", isOn: $settings.generalBlinkEnabled)
                        
                        if settings.generalBlinkEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Blink Rate")
                                    Spacer()
                                    Text("\(String(format: "%.0f", settings.generalBlinkInterval * 1000))ms")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $settings.generalBlinkInterval, in: 0.2...2.0, step: 0.1) {
                                    EmptyView()
                                } minimumValueLabel: {
                                    Text("Fast").font(.caption)
                                } maximumValueLabel: {
                                    Text("Slow").font(.caption)
                                }
                            }
                        }
                    }
                    .padding(4)
                }

                GroupBox(label: Text("Feedback")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Visual notifications", isOn: $settings.generalVisualFeedback)
                        
                        if settings.generalVisualFeedback {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Duration")
                                    Spacer()
                                    Text("\(String(format: "%.1f", settings.notificationDuration))s")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $settings.notificationDuration, in: 0...10.0, step: 0.5) {
                                    EmptyView()
                                } minimumValueLabel: {
                                    Text("0s").font(.caption)
                                } maximumValueLabel: {
                                    Text("10s").font(.caption)
                                }
                            }
                            .padding(.leading, 20)
                        }

                        Toggle("Audio Feedback", isOn: $settings.generalAudioFeedback)

                        if settings.generalAudioFeedback {
                            Divider()
                            SoundPicker(label: "Mute Sound", selection: $settings.soundStandardMute)
                            SoundPicker(label: "Unmute Sound", selection: $settings.soundStandardUnmute)
                        }
                    }
                    .padding(4)
                }
            }
            .padding()
        }
    }
}

struct PTTSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @EnvironmentObject var appState: AppState
    @State private var isRecordingToggle = false
    @State private var isRecordingAction = false
    @State private var showTestSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                GroupBox {
                    Toggle("Enable Push to Talk", isOn: $settings.pttEnabled)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if settings.pttEnabled {
                    GroupBox(label: Text("Shortcuts")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Toggle PTT Mode")
                                Spacer()
                                ShortcutRecorderButton(shortcut: $settings.pttToggleShortcut, isRecording: $isRecordingToggle)
                            }

                            HStack {
                                Text("PTT Action (Hold)")
                                Spacer()
                                ShortcutRecorderButton(shortcut: $settings.pttActionShortcut, isRecording: $isRecordingAction)
                            }

                            if settings.pttToggleShortcut == settings.pttActionShortcut {
                                Text("Warning: Same shortcut assigned to both actions.")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding(4)
                    }

                    GroupBox(label: Text("Timing")) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Delay Mute")
                                Spacer()
                                Text("\(String(format: "%.0f", settings.pttReleaseDelay))s")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.pttReleaseDelay, in: 0...30.0, step: 1.0) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("0s").font(.caption)
                            } maximumValueLabel: {
                                Text("30s").font(.caption)
                            }
                            
                            Text("Time to wait before muting after releasing the key.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(4)
                    }

                    GroupBox(label: Text("Appearance")) {
                        VStack(alignment: .leading, spacing: 12) {
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
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Blink Rate")
                                        Spacer()
                                        Text("\(String(format: "%.0f", settings.pttBlinkInterval * 1000))ms")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $settings.pttBlinkInterval, in: 0.2...1.0, step: 0.1) {
                                        EmptyView()
                                    } minimumValueLabel: {
                                        Text("Fast").font(.caption)
                                    } maximumValueLabel: {
                                        Text("Slow").font(.caption)
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }

                    GroupBox(label: Text("Feedback")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Visual notifications", isOn: $settings.pttVisualFeedback)
                            
                            if settings.pttVisualFeedback {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Duration")
                                        Spacer()
                                        Text("\(String(format: "%.1f", settings.pttNotificationDuration))s")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $settings.pttNotificationDuration, in: 0...10.0, step: 0.5) {
                                        EmptyView()
                                    } minimumValueLabel: {
                                        Text("0s").font(.caption)
                                    } maximumValueLabel: {
                                        Text("10s").font(.caption)
                                    }
                                }
                                .padding(.leading, 20)
                            }

                            Toggle("Audio Feedback", isOn: $settings.pttAudioFeedback)

                            if settings.pttAudioFeedback {
                                Divider()
                                SoundPicker(label: "Press (Activate)", selection: $settings.soundPTTActivate)
                                SoundPicker(label: "Release (Deactivate)", selection: $settings.soundPTTDeactivate)
                            }
                        }
                        .padding(4)
                    }

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
                    }
                    .padding(.top, 10)
                }
            }
            .padding()
        }
        .sheet(isPresented: $showTestSheet) {
            TestPTTView(isPresented: $showTestSheet)
                .environmentObject(appState)
        }
    }
}

struct DevicesSettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @EnvironmentObject var appState: AppState

    var body: some View {
        let audioController = appState.audioController
        
        VStack(spacing: 0) {
            // System Input Header
            VStack(alignment: .leading, spacing: 8) {
                Text("System Input")
                    .font(.headline)
                
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: Binding(
                        get: { audioController.currentInputDeviceID },
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
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Device List
            List {
                Section(header: Text("Compatible Devices").font(.subheadline)) {
                    ForEach(audioController.availableInputDevices) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.body)
                                Text("UID: \(device.uid)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                            
                            Toggle(device.name, isOn: Binding(
                                get: { !settings.excludedDeviceUIDs.contains(device.uid) },
                                set: { isEnabled in
                                    if isEnabled {
                                        settings.excludedDeviceUIDs.removeAll { $0 == device.uid }
                                    } else {
                                        if !settings.excludedDeviceUIDs.contains(device.uid) {
                                            settings.excludedDeviceUIDs.append(device.uid)
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section {
                        Text("Disable a device to prevent Mac Mic Control from muting it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }
}

struct ShortcutRecorderButton: View {
    @Binding var shortcut: AppKeyboardShortcut
    @Binding var isRecording: Bool

    var body: some View {
        HStack {
            Button(action: {
                isRecording.toggle()
            }) {
                HStack {
                    if isRecording {
                        Image(systemName: "record.circle")
                            .foregroundColor(.red)
                            .animateForever()
                        Text("Press keys...")
                    } else {
                        Image(systemName: "keyboard")
                        Text(shortcut.description.isEmpty ? "Click to set" : shortcut.description)
                    }
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .overlay(
                // Invisible recorder view when recording
                Group {
                    if isRecording {
                        ShortcutRecorder(isRecording: $isRecording) { keyCode, modifiers in
                            let newShortcut = AppKeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
                            shortcut = newShortcut
                            if !newShortcut.isModifier {
                                isRecording = false
                            }
                        }
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                    }
                }
            )
        }
    }
}

extension View {
    func animateForever() -> some View {
        self.modifier(InfiniteAnimationModifier())
    }
}

struct InfiniteAnimationModifier: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(Animation.easeInOut(duration: 0.8).repeatForever(), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

struct TestPTTView: View {
    @Binding var isPresented: Bool
    @ObservedObject var settings = SettingsManager.shared
    @EnvironmentObject var appState: AppState

    @State private var isBlinking = false

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 10) {
                Text("Push to Talk Test")
                    .font(.title2)
                    .bold()

                Text("Press and hold your PTT Action shortcut to test.")
                    .foregroundColor(.secondary)
            }

            ZStack {
                Circle()
                    .fill(currentBackgroundColor)
                    .frame(width: 120, height: 120)
                    .shadow(radius: 5)

                Image(systemName: currentIconName)
                    .font(.system(size: 60))
                    .foregroundColor(currentIconColor)
            }
            .frame(height: 150)

            VStack(spacing: 5) {
                if appState.isPTTActive {
                    Text("MIC LIVE")
                        .font(.headline)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.red.opacity(0.1)))
                } else {
                    Text("MIC MUTED")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.gray.opacity(0.1)))
                }
            }

            Button("Close") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 400)
        .onReceive(Timer.publish(every: settings.pttBlinkInterval, on: .main, in: .common).autoconnect()) { _ in
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
            return .white
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
                SettingsManager.shared.cachedSound(named: newValue)?.play()
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

        var modifiers: Int = 0
        if event.modifierFlags.contains(.command) { modifiers |= cmdKey }
        if event.modifierFlags.contains(.option) { modifiers |= optionKey }
        if event.modifierFlags.contains(.control) { modifiers |= controlKey }
        if event.modifierFlags.contains(.shift) { modifiers |= shiftKey }

        onRecord?(Int(event.keyCode), modifiers)
    }

    override func keyDown(with event: NSEvent) {
        if !isRecording {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // Esc
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
