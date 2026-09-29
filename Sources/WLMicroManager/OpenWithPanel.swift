import AppKit
import SwiftUI
import WLKit

/// The app-switcher strip on key 6: pick Tower, VS Code or Finder, and the focused
/// agent's working directory opens there.
///
/// The window itself is a `KeyTakingPanel`, which this key shares with the dial's
/// model picker: both have to read arrow keys, and the reasons that window is not
/// a `FloatingPanel` are written down there.
@MainActor
final class OpenWithPanelController {

    static let shared = OpenWithPanelController()

    /// Fires when the strip appears or disappears, so key 6's light can follow
    /// it. Same join the stack panel used.
    var onVisibilityChange: ((Bool) -> Void)? {
        get { panel.onVisibilityChange }
        set { panel.onVisibilityChange = newValue }
    }
    /// Where refusals go: the menu panel, via the bridge's own error line.
    var onError: ((String) -> Void)?

    private let model = StripModel()
    private lazy var panel: KeyTakingPanel = makePanel()
    /// Bumped by every open and close, so a resolve belonging to an earlier
    /// press cannot put up a strip you have already dismissed.
    private var generation = 0

    var isVisible: Bool { panel.isVisible }

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
        panel.present(size: StripView.size(choices: strip.choices.count))
    }

    /// Esc, key 6 again, a click outside, or losing key status. Puts the
    /// keyboard back where it was.
    private func dismiss() {
        generation += 1
        panel.dismiss()
    }

    /// Enter. The app being opened activates itself, so nothing is restored.
    private func confirm() {
        guard let strip = model.strip else { return }
        generation += 1
        panel.closeWithoutRestoring()
        OpenWith.launch(strip.selected, directory: strip.directory) { [weak self] message in
            self?.onError?(message)
        }
    }

    // MARK: - Window

    /// Returning nil from the key handler consumes the key so it does not also
    /// beep. The strip works the horizontal axis and swallows the vertical one.
    private func makePanel() -> KeyTakingPanel {
        let view = StripView(
            model: model,
            onPick: { [weak self] index in
                self?.model.select(index)
                self?.confirm()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let panel = KeyTakingPanel { NSHostingView(rootView: view) }
        panel.onKey = { [weak self] key, event in
            guard let self else { return event }
            switch key {
            case .left: self.model.move(.left); return nil
            case .right: self.model.move(.right); return nil
            case .confirm: self.confirm(); return nil
            case .dismiss: self.dismiss(); return nil
            case .up, .down, .ignore: return nil
            case .passThrough: return event
            }
        }
        panel.onResignKey = { [weak self] in
            self?.generation += 1
            self?.panel.closeWithoutRestoring()
        }
        return panel
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
