import AppKit
import SwiftUI
import WLKit

/// The app-switcher strip on key 6: pick Finder, Zed or Tower, and the focused
/// agent's working directory opens there.
///
/// This is the one window in the app that **takes focus**, and it is not built on
/// `FloatingPanel` for that reason. That class promises never to become key —
/// "you are looking at it *from* the terminal you were already typing in" — and
/// the stack, tune and land panels all depend on the promise. A mode switch
/// inside it would put the exception in the one place they share.
///
/// Taking focus means it can leave you somewhere you did not ask to be, so the
/// controller remembers what was frontmost and puts it back on any dismissal
/// that does not launch something.
@MainActor
final class OpenWithPanelController {

    static let shared = OpenWithPanelController()

    /// Fires when the strip appears or disappears, so key 6's light can follow
    /// it. Same join the stack panel used.
    var onVisibilityChange: ((Bool) -> Void)?
    /// Where refusals go: the menu panel, via the bridge's own error line.
    var onError: ((String) -> Void)?

    private var panel: NSPanel?
    private var model = StripModel()
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    /// What to reactivate on a dismissal that launches nothing. An app press is
    /// a detour, not a destination.
    private var previousApp: NSRunningApplication?
    /// Bumped by every open and close, so a resolve belonging to an earlier
    /// press cannot put up a strip you have already dismissed.
    private var generation = 0

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - The key

    /// Key 6. Up goes down; down resolves the directory and comes up.
    func handleKey() {
        if isVisible {
            dismiss()
            return
        }
        generation += 1
        let generation = self.generation
        Task { [weak self] in
            let agent = try? await HerdrClient.focusedAgent()
            guard let self, self.generation == generation, !self.isVisible else { return }
            switch OpenWith.start(agent: agent, locate: OpenWith.locate) {
            case .refuse(let message):
                // Silent on screen: an empty Herdr does not deserve a window.
                // Still reported, so a key 6 that is dead for a real reason
                // does not look like this one.
                self.onError?(message)
            case .show(let strip):
                self.present(strip)
            }
        }
    }

    // MARK: - Presenting

    private func present(_ strip: OpenWith.Strip) {
        model.strip = strip
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel
        centre(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startWatching(panel)
        onVisibilityChange?(true)
    }

    /// Esc, key 6 again, a click outside, or losing key status. Puts the
    /// keyboard back where it was.
    private func dismiss() {
        close()
        previousApp?.activate()
        previousApp = nil
    }

    /// Enter. The app being opened activates itself, so nothing is restored.
    private func confirm() {
        guard let strip = model.strip else { return }
        close()
        previousApp = nil
        OpenWith.launch(strip.selected, directory: strip.directory) { [weak self] message in
            self?.onError?(message)
        }
    }

    private func close() {
        generation += 1
        stopWatching()
        panel?.orderOut(nil)
        onVisibilityChange?(false)
    }

    // MARK: - Keys

    /// A **local** monitor, deliberately, not a `CGEventTap`. A local monitor
    /// only sees events already delivered to this app, so it needs no Input
    /// Monitoring grant and cannot swallow a keystroke meant for an agent — and
    /// a consuming system-wide tap is the same category of thing Work Louder
    /// name as breaking communication with this pad. Returning nil consumes the
    /// key so it does not also beep.
    private func startWatching(_ panel: NSPanel) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch OpenWith.Key(keyCode: event.keyCode, modifiers: event.modifierFlags) {
            case .left: self.model.move(.left); return nil
            case .right: self.model.move(.right); return nil
            case .confirm: self.confirm(); return nil
            case .dismiss: self.dismiss(); return nil
            case .ignore: return nil
            case .passThrough: return event
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // Reached another window some other way: the strip should not be
            // left behind it, waiting for keys it will never receive.
            Task { @MainActor [weak self] in
                guard let self, self.isVisible else { return }
                self.close()
                self.previousApp = nil
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

        let view = StripView(
            model: model,
            onPick: { [weak self] index in
                self?.model.select(index)
                self?.confirm()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    /// Centred on the screen holding the mouse, like every other panel here, and
    /// sized to its content so a two-icon strip is not mostly margin.
    private func centre(_ panel: NSPanel) {
        let count = model.strip?.choices.count ?? OpenWith.App.all.count
        let size = StripView.size(choices: count)
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

// MARK: - Model

/// The strip's state, observable so the view follows the arrow keys.
@MainActor
final class StripModel: ObservableObject {
    @Published var strip: OpenWith.Strip?

    func move(_ direction: OpenWith.Direction) {
        strip?.move(direction)
    }

    func select(_ index: Int) {
        guard var strip, index >= 0, index < strip.choices.count else { return }
        while strip.selection != index { strip.move(.right) }
        self.strip = strip
    }
}

// MARK: - View

/// A horizontal strip of app icons with the selection on a rounded highlight,
/// in the manner of the macOS app switcher, and one line underneath naming what
/// Enter will do.
private struct StripView: View {

    @ObservedObject var model: StripModel
    let onPick: (Int) -> Void
    let onDismiss: () -> Void

    private static let icon: CGFloat = 64
    private static let cell: CGFloat = 88
    private static let padding: CGFloat = 16
    private static let captionHeight: CGFloat = 44

    static func size(choices: Int) -> CGSize {
        CGSize(
            width: CGFloat(max(choices, 1)) * cell + padding * 2,
            height: icon + padding * 2 + captionHeight
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20,
                                                                    style: .continuous))
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                        cell(choice, selected: index == model.strip?.selection)
                            .frame(width: Self.cell)
                            .onTapGesture { onPick(index) }
                    }
                }
                caption
            }
            .padding(Self.padding)
        }
        .ignoresSafeArea()
        // Clicking the strip's own background dismisses, matching the other
        // panels; the icons take their taps first.
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }

    private var choices: [OpenWith.Choice] { model.strip?.choices ?? [] }

    private func cell(_ choice: OpenWith.Choice, selected: Bool) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: choice.url.path))
            .resizable()
            .frame(width: Self.icon, height: Self.icon)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(selected ? 0.22 : 0))
            )
    }

    /// The app Enter would open, and the directory it would open. Seeing the
    /// path before committing is the difference between a picker and a guess.
    private var caption: some View {
        VStack(spacing: 1) {
            Text(model.strip?.selected.app.displayName ?? "")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.strip.map { PanelHTML.abbreviate($0.directory.path) } ?? "")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(height: Self.captionHeight - 6)
    }
}
