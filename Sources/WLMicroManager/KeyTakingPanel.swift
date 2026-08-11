import AppKit
import WLKit

/// A panel that **takes the keyboard**, for the two places on the pad that have
/// to read arrow keys: the open-with strip on key 6 and the model picker on the
/// dial.
///
/// Deliberately not built on `FloatingPanel`. That class promises never to become
/// key — "you are looking at it *from* the terminal you were already typing in" —
/// and the stack, tune and land panels all depend on the promise. A mode switch
/// inside it would put the exception in the one place they share.
///
/// Taking focus means a panel can leave you somewhere you did not ask to be, so
/// this remembers what was frontmost and puts it back on any dismissal that does
/// not deliberately activate something else.
///
/// Keys arrive through a **local** monitor, never a `CGEventTap`. A local monitor
/// only sees events already delivered to this app, so it needs no Input
/// Monitoring grant and cannot swallow a keystroke meant for an agent — and a
/// consuming system-wide tap is the same category of thing Work Louder name as
/// breaking communication with this pad.
@MainActor
final class KeyTakingPanel {

    /// Every key while visible. Return nil to swallow it, or the event to let it
    /// through to the app.
    var onKey: ((PanelKey, NSEvent) -> NSEvent?)?
    /// Key status lost some other way: the panel should not be left behind the
    /// window you switched to, waiting for keys it will never receive.
    var onResignKey: (() -> Void)?
    var onVisibilityChange: ((Bool) -> Void)?

    private let content: () -> NSView
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// What to reactivate on a dismissal that launches nothing. A pad press is a
    /// detour, not a destination.
    private var previousApp: NSRunningApplication?

    init(content: @escaping () -> NSView) {
        self.content = content
    }

    var isVisible: Bool { panel?.isVisible == true }

    func present(size: CGSize) {
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = self.panel ?? makePanel()
        self.panel = panel
        centre(panel, size: size)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startWatching(panel)
        onVisibilityChange?(true)
    }

    /// Puts the keyboard back where it was. Esc, a second press of the key, a
    /// click outside.
    func dismiss() {
        hide()
        previousApp?.activate()
        previousApp = nil
    }

    /// For a dismissal whose own action brings something forward — an app being
    /// launched, a terminal being raised — so nothing is restored over it.
    func closeWithoutRestoring() {
        hide()
        previousApp = nil
    }

    private func hide() {
        stopWatching()
        panel?.orderOut(nil)
        onVisibilityChange?(false)
    }

    // MARK: - Keys

    private func startWatching(_ panel: NSPanel) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            let key = PanelKey(keyCode: event.keyCode, modifiers: event.modifierFlags)
            return self.onKey?(key, event) ?? event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isVisible else { return }
                self.onResignKey?()
            }
        }
    }

    private func stopWatching() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    // MARK: - Window

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .fullSizeContentView],
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

        let hosting = content()
        hosting.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    /// Centred on the screen holding the mouse, like every other panel here, and
    /// sized to its content so a two-icon strip is not mostly margin.
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
