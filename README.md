# MacMicControl

MacMicControl is a powerful macOS utility that gives you complete control over your microphone's mute state globally. Whether you need a simple global mute toggle or a robust Push-to-Talk (PTT) system for any application, MacMicControl has you covered.

## Features

### 🎙️ Global Control
- **System-Wide Mute**: Toggle your microphone on/off from anywhere using a customizable global shortcut.
- **Menubar Status**: Always know your mic status with a customizable menubar icon (Red for Live, Blue for Muted by default).

### 🗣️ Push-to-Talk (PTT)
- **PTT Mode**: Enable Push-to-Talk to keep your mic muted until you hold down your chosen key.
- **Delay Mute**: preventing abrupt cut-offs by keeping the mic live for a configurable duration after releasing the key.
- **Visual & Audio Feedback**: distinct sounds and visuals for PTT activation.

### ⚙️ Customization
- **Shortcuts**: Record your own key combinations for all actions (including modifier-only keys like "Ctrl" or "Cmd").
- **Appearance**: Customize the menubar icon colors for Muted, Unmuted, and PTT Active states.
- **Feedback**: 
  - **Visual Notifications**: Large HUD overlay when toggling mute or using PTT.
  - **Audio Cues**: Assign different system sounds for Mute, Unmute, PTT Press, and PTT Release.
  - **Blinking**: Option to blink the menubar icon when the mic is live.

### 🎧 Device Management
- **Input Selection**: Switch your system default input device directly from the app.
- **Exclusion List**: Choose which microphones the app controls. Keep specific devices (like a dedicated loopback or conference room mic) always active by excluding them from global mute.

## Installation & Requirements

### Requirements
- macOS 12.0 or later.
- **Accessibility Permissions**: Required to listen for global keyboard shortcuts.
- **Microphone Permissions**: Required to control the audio input mute state.

### Building from Source
1. Clone the repository.
2. Open the project in Xcode.
3. Build and Run.

## Usage

1. **Launch the App**: The app lives in your menubar.
2. **Open Settings**: Click the menubar icon and select "Settings" (or press `Cmd+,`).
3. **Set Permissions**: Grant Accessibility and Microphone access when prompted.
4. **Configure Shortcuts**:
   - Go to the **General** tab to set your main Toggle Mute shortcut.
   - Go to the **Push to Talk** tab to enable PTT and set your Action Key.

## Troubleshooting

- **Shortcut not working?** Ensure the app has Accessibility permissions in `System Settings > Privacy & Security > Accessibility`.
- **Mic not muting?** Check the **Devices** tab in Settings to ensure your microphone isn't in the exclusion list.

## License

[MIT License](LICENSE)
