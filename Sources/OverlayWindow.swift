import Cocoa
import SwiftUI

class OverlayWindow: NSWindow {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

class OverlayController: ObservableObject {
    private var window: OverlayWindow?
    private var timer: Timer?
    
    func showOverlay(isMuted: Bool) {
        timer?.invalidate()
        
        if window == nil {
            let width: CGFloat = 300
            let height: CGFloat = 100
            
            // Center of screen
            let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let x = (screenRect.width - width) / 2
            let y = (screenRect.height - height) / 2 + 100 // Slightly above center
            
            let rect = NSRect(x: x, y: y, width: width, height: height)
            
            window = OverlayWindow(
                contentRect: rect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
        }
        
        let contentView = OverlayView(isMuted: isMuted)
        window?.contentView = NSHostingView(rootView: contentView)
        window?.makeKeyAndOrderFront(nil)
        window?.alphaValue = 1.0
        
        // Hide after 2 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.fadeOut()
        }
    }
    
    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            window?.animator().alphaValue = 0.0
        } completionHandler: {
            self.window?.orderOut(nil)
        }
    }
}

struct OverlayView: View {
    let isMuted: Bool
    
    var body: some View {
        VStack {
            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 40))
                .foregroundColor(.white)
            Text(isMuted ? "Microphone OFF" : "Microphone ON")
                .font(.title)
                .bold()
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(isMuted ? Color.gray.opacity(0.9) : Color.red.opacity(0.9))
        )
        .shadow(radius: 10)
    }
}
