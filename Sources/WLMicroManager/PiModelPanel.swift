import AppKit
import SwiftUI
import WLKit

/// The dial on a pi pane: turn to choose a model, click to go there.
///
/// Turning is local and costs nothing — it moves a highlight in a panel and
/// sends the pane nothing at all. The click is the only thing that touches pi,
/// and what it sends is the chord you would type yourself: `ctrl+p`, as many
/// times as it takes to walk from the model pi reports to the one you chose.
///
/// Nothing here decides anything. The list, the refusals, the distance and the
/// step-by-step walk all live in `PiModels`, where they are tested; this owns the
/// window, the timer and the two Herdr calls.
@MainActor
final class PiModelPanelController {

    static let shared = PiModelPanelController()

    /// Where refusals and failed walks go: the menu panel, via the bridge's own
    /// error line.
    var onError: ((String) -> Void)?

    /// Long enough to read four lines and decide, short enough that a panel you
    /// walked away from does not hold the keyboard. The tune panel's 6 seconds
    /// are for a window that never takes focus; this one does.
    private static let idleTimeout: TimeInterval = 20

    private let model = ListModel()
    private lazy var panel: KeyTakingPanel = makePanel()
    /// Bumped by every open, close and commit, so a read belonging to an earlier
    /// turn cannot put up a panel you have already dismissed, and an idle timer
    /// from a previous panel cannot close this one.
    private var generation = 0
    /// The pane the panel was opened against. A commit goes here, not to whatever
    /// has focus by the time you click.
    private var paneID: String?

    var isVisible: Bool { panel.isVisible }

    // MARK: - The dial

    /// A detent while the panel is up. Local: it moves the highlight and sends
    /// the pane nothing.
    func turn(_ step: Int) {
        guard isVisible else { return }
        model.move(step)
        armIdleTimer()
    }

    /// The dial's own click while the panel is up.
    func press() {
        guard isVisible else { return }
        commit()
    }

    // MARK: - Opening

    /// Reads pi's list off disk and its current model off the pane, then shows
    /// them together, with `step` already applied so the first detent moves the
    /// highlight rather than only opening the window.
    ///
    /// Both reads are fresh every time: a cached list would drift from
    /// `enabledModels`, and a cached position would defeat the point.
    func open(agent: HerdrAgent, pane: String, step: Int) {
        generation += 1
        let generation = self.generation
        Task { [weak self] in
            let settings = Self.readSettings()
            let text = try? await HerdrClient.readPane(pane)
            guard let self, self.generation == generation, !self.isVisible else { return }
            switch PiModels.start(entries: PiModels.enabledModels(in: settings), paneText: text) {
            case .refuse(let message):
                // Silent on screen, reported in the panel: a dial that is dead
                // for a real reason must not look like this one.
                self.onError?(message)
            case .show(var picker):
                picker.move(step)
                self.paneID = pane
                self.model.picker = picker
                self.model.agent = agent.shortName
                self.panel.present(size: ListView.size(rows: picker.entries.count))
                self.armIdleTimer()
            }
        }
    }

    /// `enabledModels` is pi's own list, read from pi's own file. Keeping a
    /// second copy in this app's config would be a copy that goes stale.
    private static func readSettings() -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: PiModels.settingsPath()),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    // MARK: - Committing

    private func commit() {
        guard let picker = model.picker, let pane = paneID else { return }
        dismiss()
        guard picker.steps != 0 else { return }
        Task { [weak self] in
            let outcome = await PiModels.advance(
                picker,
                send: { try await HerdrClient.sendKeys(paneID: pane, keys: ["ctrl+p"]) },
                read: { try await HerdrClient.readPane(pane) },
                pause: { try? await Task.sleep(nanoseconds: 80_000_000) }
            )
            if case .failed(let message) = outcome { self?.onError?(message) }
        }
    }

    // MARK: - Dismissing

    private func dismiss() {
        generation += 1
        paneID = nil
        panel.dismiss()
    }

    /// A panel nobody confirms lets go on its own, and gives the keyboard back
    /// when it does.
    private func armIdleTimer() {
        generation += 1
        let generation = self.generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleTimeout * 1_000_000_000))
            guard let self, self.generation == generation, self.isVisible else { return }
            self.dismiss()
        }
    }

    // MARK: - Window

    private func makePanel() -> KeyTakingPanel {
        let view = ListView(
            model: model,
            onPick: { [weak self] index in
                self?.model.select(index)
                self?.commit()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let panel = KeyTakingPanel { NSHostingView(rootView: view) }
        panel.onKey = { [weak self] key, event in
            guard let self else { return event }
            switch key {
            case .up: self.model.move(-1); self.armIdleTimer(); return nil
            case .down: self.model.move(1); self.armIdleTimer(); return nil
            case .confirm: self.commit(); return nil
            case .dismiss: self.dismiss(); return nil
            case .left, .right, .ignore: return nil
            case .passThrough: return event
            }
        }
        panel.onResignKey = { [weak self] in
            self?.generation += 1
            self?.paneID = nil
            self?.panel.closeWithoutRestoring()
        }
        return panel
    }
}

// MARK: - Model

/// The panel's state, observable so the view follows the dial.
@MainActor
final class ListModel: ObservableObject {
    @Published var picker: PiModels.Picker?
    @Published var agent: String = ""

    func move(_ step: Int) {
        picker?.move(step)
    }

    func select(_ index: Int) {
        guard var picker, index >= 0, index < picker.entries.count else { return }
        picker.move(index - picker.selection)
        self.picker = picker
    }
}

// MARK: - View

/// The list, one model per row, with the highlight on a rounded fill and one line
/// underneath saying what the click will do.
private struct ListView: View {

    @ObservedObject var model: ListModel
    let onPick: (Int) -> Void
    let onDismiss: () -> Void

    private static let row: CGFloat = 30
    private static let width: CGFloat = 460
    private static let padding: CGFloat = 16
    private static let captionHeight: CGFloat = 40

    static func size(rows: Int) -> CGSize {
        CGSize(
            width: width,
            height: CGFloat(max(rows, 1)) * row + padding * 2 + captionHeight
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20,
                                                                    style: .continuous))
            VStack(spacing: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        row(entry, index: index)
                            .onTapGesture { onPick(index) }
                    }
                }
                caption
            }
            .padding(Self.padding)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }

    private var entries: [PiModels.Entry] { model.picker?.entries ?? [] }

    /// The model pi is on is marked separately from the highlight, because they
    /// start together and then part company as you turn: one is where you are,
    /// the other is where the click would take you.
    private func row(_ entry: PiModels.Entry, index: Int) -> some View {
        let selected = index == model.picker?.selection
        let current = index == model.picker?.current
        return HStack(spacing: 8) {
            Text(current ? "●" : " ")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
            Text(entry.id)
                .font(.system(size: 14, weight: selected ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.7))
            Spacer(minLength: 0)
            Text(entry.provider)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .frame(height: Self.row)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(selected ? 0.22 : 0))
        )
    }

    /// What the click would do, and how far away it is. A count of presses is
    /// worth showing: it is the difference between a picker and a promise.
    private var caption: some View {
        VStack(spacing: 1) {
            Text(model.picker.map(headline) ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(model.agent)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .frame(height: Self.captionHeight - 6)
    }

    private func headline(_ picker: PiModels.Picker) -> String {
        guard let steps = picker.steps else {
            return "Pi is on a model that is not in this list"
        }
        switch steps {
        case 0: return "Already on \(picker.selected.id)"
        case 1: return "One ctrl+p to \(picker.selected.id)"
        default: return "\(steps) × ctrl+p to \(picker.selected.id)"
        }
    }
}
