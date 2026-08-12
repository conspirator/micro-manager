import AppKit

/// A floating, non-activating panel hosting a native view.
///
/// The app already has two panel classes and neither fits a compass.
/// `FloatingPanel` is a webview whose whole job is text with a header, a footer
/// and content-height measuring; `KeyTakingPanel` hosts a native view but
/// deliberately takes the keyboard. A radial menu wants native drawing and no
/// focus at all: the joystick is the input, so activating the app would move you
/// somewhere you did not ask to be for no benefit.
///
/// The window setup below is deliberately *not* shared with `KeyTakingPanel`.
/// That class's two load-bearing behaviours — Esc returning you to the app you
/// came from, and dismissing when it loses key status — are the two things
/// AGENTS.md records as covered by no test in this repo. Thirty duplicated lines
/// are cheaper than refactoring the one panel whose correctness is hand-checked.
@MainActor
final class HostingPanel {

    private let content: () -> NSView
    private var panel: NSPanel?

    init(content: @escaping () -> NSView) {
        self.content = content
    }

    var isVisible: Bool { panel?.isVisible == true }

    func present(size: CGSize) {
        let panel = self.panel ?? makePanel(size: size)
        self.panel = panel
        centre(panel, size: size)
        // Front without focus: `orderFrontRegardless` shows it over whatever is
        // there without making this app active, which `makeKeyAndOrderFront`
        // would.
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let frame = NSRect(origin: .zero, size: size)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Clicks fall through to whatever is behind: there is nothing to press
        // here, and a panel that swallows a click while showing you a joystick
        // position would eat the click you meant for your editor.
        panel.ignoresMouseEvents = true

        let hosting = content()
        hosting.frame = frame
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    /// Centred on the screen holding the mouse, like every other panel here.
    private func centre(_ panel: NSPanel, size: CGSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }
}
