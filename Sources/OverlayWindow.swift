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
        // Remove window shadow as the view will handle its own shadow/blur
        self.hasShadow = false
    }
}

class OverlayController: ObservableObject {
    private var window: OverlayWindow?
    private var timer: Timer?

    func showOverlay(isMuted: Bool, duration: TimeInterval) {
        timer?.invalidate()

        if window == nil {
            let width: CGFloat = 200
            let height: CGFloat = 200

            let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let x = (screenRect.width - width) / 2
            let y = (screenRect.height - height) / 2 - 100 // Center on screen, slightly higher

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
        window?.alphaValue = 0.0
        
        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window?.animator().alphaValue = 1.0
        }

        if duration > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        } else {
             // If duration is 0, fade out immediately after fade in?
             // Or maybe 0 implies "do not auto hide"?
             // Given the range 0-10, likely 0 means "very short".
             // If the user sets 0, they probably don't want to see it, but they have a toggle for that.
             // Let's assume 0 means "don't auto hide" is NOT the standard interpretation for a "duration" slider unless specified.
             // If I put 0 into timer, it fires immediately.
             timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { [weak self] context in
            context.duration = 0.5
            self?.window?.animator().alphaValue = 0.0
        } completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
        }
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct OverlayView: View {
    let isMuted: Bool

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 60))
                .foregroundColor(isMuted ? .secondary : .red)
            
            Text(isMuted ? "Muted" : "Live")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
        // Add a subtle border for better contrast on dark backgrounds
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
