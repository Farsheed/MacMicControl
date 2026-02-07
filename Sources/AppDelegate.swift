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
        
        // Observe Mute State
        appState.audioController.$isMuted
            .sink { [weak self] isMuted in
                self?.updateIcon()
            }
            .store(in: &cancellables)
            
        // Observe PTT Active State
        appState.$isPTTActive
            .sink { [weak self] isActive in
                self?.updateIcon()
            }
            .store(in: &cancellables)
            
        // Observe Settings Changes
        let settings = SettingsManager.shared
        
        settings.$mutedColor.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        settings.$unmutedColor.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        settings.$iconScale.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        
        settings.$pttEnabled.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        settings.$pttBlinkColor.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        settings.$pttInactiveBackgroundColor.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        settings.$pttInactiveIconColor.sink { [weak self] _ in self?.updateIcon() }.store(in: &cancellables)
        
        // If PTT interval changes, we might need to restart timer if active
        settings.$pttBlinkInterval.sink { [weak self] _ in
            if self?.appState.isPTTActive == true {
                self?.startBlinking(interval: settings.pttBlinkInterval)
            }
        }.store(in: &cancellables)
        
        // Observe Countdown
        appState.$pttCountdownRemaining.sink { [weak self] _ in
             self?.updateIcon()
        }.store(in: &cancellables)
        
        settings.$generalBlinkInterval.sink { [weak self] _ in
            if self?.appState.isPTTActive == false && self?.appState.audioController.isMuted == false {
                self?.startBlinking(interval: settings.generalBlinkInterval)
            }
        }.store(in: &cancellables)
        
        settings.$generalBlinkEnabled.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateIcon()
            }
        }.store(in: &cancellables)
        
        settings.$pttBlinkEnabled.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateIcon()
            }
        }.store(in: &cancellables)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Ensure microphone is unmuted when quitting
        if appState.audioController.isMuted {
            appState.audioController.setMute(false)
        }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Mute", action: #selector(toggleMuteAction), keyEquivalent: "m"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
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
        menu.addItem(NSMenuItem(title: "Toggle Mute", action: #selector(toggleMuteAction), keyEquivalent: "m"))
        
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
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil) // Pop the menu
        statusItem.menu = nil // Clear it after so left click works again as toggle
    }
    
    @objc func selectMicrophone(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? InputDevice else { return }
        appState.audioController.setDefaultInputDevice(device)
        // Refresh menu or icon might happen via notifications if we listened, but menu is transient.
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
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 650), // Increased size for PTT and consistent UI
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Mac Mic Control Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
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
        
        // Logic for Timer
        if isPTTActive {
            // PTT Active
            if settings.pttBlinkEnabled {
                startBlinking(interval: settings.pttBlinkInterval)
            } else {
                stopBlinking()
            }
        } else if !isMuted {
            // Standard Unmute
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
             // Already running with correct interval
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
        isBlinkVisible = true // Reset to "Main" state
    }
    
    func drawIcon() {
        guard let button = statusItem.button else { return }
        
        let settings = SettingsManager.shared
        let isMuted = appState.audioController.isMuted
        let isPTTActive = appState.isPTTActive
        let pttEnabled = settings.pttEnabled
        let countdown = appState.pttCountdownRemaining
        
        // Base dimensions
        let baseWidth: CGFloat = 34
        let baseHeight: CGFloat = 22
        
        // Apply Scale
        let scale = CGFloat(settings.iconScale)
        let width = baseWidth * scale
        let height = baseHeight * scale
        let size = NSSize(width: width, height: height)
        
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw background oval
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let path = NSBezierPath(roundedRect: rect, xRadius: height/2, yRadius: height/2)
        
        // Determine Colors
        if isPTTActive {
            if countdown != nil {
                // If counting down, we use Unmuted color but static (no blink)
                // because we need to read the number.
                settings.getUnmutedNSColor().setFill()
            } else if settings.pttBlinkEnabled {
                if isBlinkVisible {
                    // Main: PTT Blink Color (Yellow)
                    settings.getPTTBlinkNSColor().setFill()
                } else {
                    // Secondary: Unmute Color (Red)
                    settings.getUnmutedNSColor().setFill()
                }
            } else {
                // No Blink: Just show PTT Active Color (or Unmuted color)
                settings.getUnmutedNSColor().setFill()
            }
        } else if !isMuted {
            // Standard Unmuted -> Blink between Unmute Color and Dimmed Unmute Color
            let onColor = settings.getUnmutedNSColor()
            if settings.generalBlinkEnabled {
                if isBlinkVisible {
                    onColor.setFill()
                } else {
                    onColor.withAlphaComponent(0.3).setFill()
                }
            } else {
                // No Blink: Solid "On" Color
                onColor.setFill()
            }
        } else {
            // Muted
            if pttEnabled {
                // PTT Inactive (Muted) -> PTT Inactive Background Color
                settings.getPTTInactiveBackgroundNSColor().setFill()
            } else {
                // Standard Muted -> Muted Color
                settings.getMutedNSColor().setFill()
            }
        }
        
        path.fill()
        
        // Icon OR Text
        if let count = countdown {
            // Draw Countdown Number
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
                y: (height - textSize.height) / 2 - (1 * scale), // Adjustment for vertical center
                width: textSize.width,
                height: textSize.height
            )
            string.draw(in: textRect)
            
        } else {
            // Draw Microphone Icon
            var iconName = "mic.fill"
            var iconColor = NSColor.white
            
            if isMuted {
                if pttEnabled {
                    // PTT Inactive -> Struck Icon, Custom Color
                    iconName = "mic.slash.fill"
                    iconColor = settings.getPTTInactiveIconNSColor()
                } else {
                    iconName = "mic.slash.fill"
                }
            }
            
            if let iconImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                let iconConfig = NSImage.SymbolConfiguration(pointSize: 13 * scale, weight: .bold)
                let configuredImage = iconImage.withSymbolConfiguration(iconConfig) ?? iconImage
                
                // Calculate Icon Position
                let iconSize = configuredImage.size
                let x = (width - iconSize.width) / 2
                let y = (height - iconSize.height) / 2
                let iconRect = NSRect(x: x, y: y, width: iconSize.width, height: iconSize.height)
                
                // Create a colored version of the icon
                let coloredIcon = NSImage(size: iconSize)
                coloredIcon.lockFocus()
                configuredImage.draw(in: NSRect(origin: .zero, size: iconSize))
                
                // Fill with color
                NSGraphicsContext.current?.compositingOperation = .sourceIn
                iconColor.set()
                NSBezierPath(rect: NSRect(origin: .zero, size: iconSize)).fill()
                
                coloredIcon.unlockFocus()
                
                coloredIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }
        
        image.unlockFocus()
        image.isTemplate = false
        
        button.image = image
    }
}
