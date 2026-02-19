import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appState = AppState()
    private var cancellables = Set<AnyCancellable>()
    var settingsWindow: NSWindow?

    // Blinking State
    var blinkTimer: Timer?
    var isBlinkVisible = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup Status Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(toggleMute)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Combine all state changes into a single debounced icon update
        let settings = SettingsManager.shared

        let stateChanges: [AnyPublisher<Void, Never>] = [
            appState.audioController.$isMuted.map { _ in () }.eraseToAnyPublisher(),
            appState.$isPTTActive.map { _ in () }.eraseToAnyPublisher(),
            appState.$pttCountdownRemaining.map { _ in () }.eraseToAnyPublisher(),
            appState.$isPTMActive.map { _ in () }.eraseToAnyPublisher(),
            appState.$ptmCountdownRemaining.map { _ in () }.eraseToAnyPublisher(),
            settings.$mutedColor.map { _ in () }.eraseToAnyPublisher(),
            settings.$unmutedColor.map { _ in () }.eraseToAnyPublisher(),
            settings.$iconScale.map { _ in () }.eraseToAnyPublisher(),
            settings.$pttEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$pttBlinkColor.map { _ in () }.eraseToAnyPublisher(),
            settings.$pttInactiveBackgroundColor.map { _ in () }.eraseToAnyPublisher(),
            settings.$pttInactiveIconColor.map { _ in () }.eraseToAnyPublisher(),
            settings.$generalBlinkEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$pttBlinkEnabled.map { _ in () }.eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(stateChanges)
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.updateIcon()
            }
            .store(in: &cancellables)

        // Blink interval changes need to restart the timer if active
        settings.$pttBlinkInterval.sink { [weak self] _ in
            guard let self = self else { return }
            if self.appState.isPTTActive {
                self.startBlinking(interval: settings.pttBlinkInterval)
            }
        }.store(in: &cancellables)

        settings.$generalBlinkInterval.sink { [weak self] _ in
            guard let self = self else { return }
            if !self.appState.isPTTActive && !self.appState.audioController.isMuted {
                self.startBlinking(interval: settings.generalBlinkInterval)
            }
        }.store(in: &cancellables)

        // Initial draw
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if appState.audioController.isMuted {
            appState.audioController.setMute(false)
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let shortcut = SettingsManager.shared.shortcut
        let toggleItem = NSMenuItem(title: "Toggle Mute", action: #selector(toggleMuteAction), keyEquivalent: shortcut.menuItemKeyEquivalent)
        toggleItem.keyEquivalentModifierMask = shortcut.nsModifierFlags
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ""))
        return menu
    }

    @objc func toggleMute(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true) {
            showMenu()
        } else {
            appState.toggleMute()
        }
    }

    func showMenu() {
        let menu = NSMenu()
        
        let shortcut = SettingsManager.shared.shortcut
        let toggleItem = NSMenuItem(title: "Toggle Mute", action: #selector(toggleMuteAction), keyEquivalent: shortcut.menuItemKeyEquivalent)
        toggleItem.keyEquivalentModifierMask = shortcut.nsModifierFlags
        menu.addItem(toggleItem)

        // Microphone Selection
        let micMenu = NSMenu()
        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micItem.submenu = micMenu
        menu.addItem(micItem)

        let currentDeviceID = appState.audioController.getDefaultInputDeviceID()
        let availableDevices = appState.audioController.availableInputDevices

        if availableDevices.isEmpty {
            let item = NSMenuItem(title: "No Input Devices", action: nil, keyEquivalent: "")
            item.isEnabled = false
            micMenu.addItem(item)
        } else {
            for device in availableDevices {
                let item = NSMenuItem(title: device.name, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device
                item.state = (device.id == currentDeviceID) ? .on : .off
                micMenu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let blinkItem = NSMenuItem(title: "Blink when Unmuted", action: #selector(toggleBlinkAction), keyEquivalent: "")
        blinkItem.state = SettingsManager.shared.generalBlinkEnabled ? .on : .off
        menu.addItem(blinkItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func selectMicrophone(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? InputDevice else { return }
        appState.audioController.setDefaultInputDevice(device)
    }

    @objc func toggleMuteAction() {
        appState.toggleMute()
    }

    @objc func toggleBlinkAction() {
        SettingsManager.shared.generalBlinkEnabled.toggle()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Mac Mic Control Settings"
            window.contentView = NSHostingView(rootView: SettingsView()
                .environmentObject(appState)
                .environmentObject(SettingsManager.shared)
            )
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func updateIcon() {
        let isMuted = appState.audioController.isMuted
        let isPTTActive = appState.isPTTActive
        let settings = SettingsManager.shared

        if isPTTActive {
            if settings.pttBlinkEnabled {
                startBlinking(interval: settings.pttBlinkInterval)
            } else {
                stopBlinking()
            }
        } else if !isMuted {
            if settings.generalBlinkEnabled {
                startBlinking(interval: settings.generalBlinkInterval)
            } else {
                stopBlinking()
            }
        } else {
            stopBlinking()
        }

        drawIcon()
    }

    func startBlinking(interval: TimeInterval) {
        if blinkTimer?.isValid == true && blinkTimer?.timeInterval == interval {
             return
        }

        blinkTimer?.invalidate()
        isBlinkVisible = true

        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.isBlinkVisible.toggle()
            self.drawIcon()
        }
    }

    func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isBlinkVisible = true
    }

    func drawIcon() {
        guard let button = statusItem.button else { return }

        let settings = SettingsManager.shared
        let isMuted = appState.audioController.isMuted
        let isPTTActive = appState.isPTTActive
        let isPTMActive = appState.isPTMActive
        let pttEnabled = settings.pttEnabled
        let ptmEnabled = settings.ptmEnabled
        let countdown = appState.pttCountdownRemaining ?? appState.ptmCountdownRemaining

        let baseWidth: CGFloat = 34
        let baseHeight: CGFloat = 22
        let scale = CGFloat(settings.iconScale)
        let width = baseWidth * scale
        let height = baseHeight * scale
        let size = NSSize(width: width, height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            // Draw background oval
            let path = NSBezierPath(roundedRect: rect, xRadius: height/2, yRadius: height/2)

            // Determine background color
            if isPTTActive { // PTT is active (unmuted)
                if countdown != nil {
                    settings.getUnmutedNSColor().setFill()
                } else if settings.pttBlinkEnabled {
                    if self.isBlinkVisible {
                        settings.getPTTBlinkNSColor().setFill()
                    } else {
                        settings.getUnmutedNSColor().setFill()
                    }
                } else {
                    settings.getUnmutedNSColor().setFill()
                }
            } else if isPTMActive { // PTM is active (muted)
                 if countdown != nil {
                    // Countdown after PTM release, should show "unmuting soon" state
                    settings.getMutedNSColor().withAlphaComponent(0.5).setFill()
                 } else {
                    // Actively holding PTM key
                    settings.getMutedNSColor().setFill()
                 }
            } else if !isMuted {
                let onColor = settings.getUnmutedNSColor()
                if settings.generalBlinkEnabled {
                    if self.isBlinkVisible {
                        onColor.setFill()
                    } else {
                        onColor.withAlphaComponent(0.3).setFill()
                    }
                } else {
                    onColor.setFill()
                }
            } else { // Mic is muted (default state)
                if pttEnabled {
                    settings.getPTTInactiveBackgroundNSColor().setFill()
                } else if ptmEnabled {
                     // Could use a different color for PTM-ready state if desired
                    settings.getUnmutedNSColor().withAlphaComponent(0.3).setFill()
                } else {
                    settings.getMutedNSColor().setFill()
                }
            }

            path.fill()

            // Icon or countdown text
            if let count = countdown {
                let text = "\(count)"
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14 * scale, weight: .bold),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraphStyle
                ]

                let string = NSAttributedString(string: text, attributes: attrs)
                let textSize = string.size()
                let textRect = NSRect(
                    x: (width - textSize.width) / 2,
                    y: (height - textSize.height) / 2 - (1 * scale),
                    width: textSize.width,
                    height: textSize.height
                )
                string.draw(in: textRect)

            } else {
                var iconName = "mic.fill"
                var iconColor = NSColor.white

                if isMuted || isPTMActive {
                    if pttEnabled && !isPTMActive { // PTT-ready state
                        iconName = "mic.slash.fill"
                        iconColor = settings.getPTTInactiveIconNSColor()
                    } else {
                        iconName = "mic.slash.fill"
                    }
                } else if ptmEnabled && !isMuted { // PTM-ready, but mic is live
                    iconName = "mic.fill"
                    iconColor = settings.getMutedNSColor() // Use muted color to signify "press to mute"
                }


                if let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                    let iconConfig = NSImage.SymbolConfiguration(pointSize: 13 * scale, weight: .bold)
                    let configuredImage = iconImage.withSymbolConfiguration(iconConfig) ?? iconImage

                    let iconSize = configuredImage.size
                    let x = (width - iconSize.width) / 2
                    let y = (height - iconSize.height) / 2
                    let iconRect = NSRect(x: x, y: y, width: iconSize.width, height: iconSize.height)

                    // Create a colored version using drawing handler (no lockFocus)
                    let coloredIcon = NSImage(size: iconSize, flipped: false) { colorRect in
                        configuredImage.draw(in: colorRect)
                        NSGraphicsContext.current?.compositingOperation = .sourceIn
                        iconColor.set()
                        NSBezierPath(rect: colorRect).fill()
                        return true
                    }

                    coloredIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }

            return true
        }

        image.isTemplate = false
        button.image = image
    }
}
