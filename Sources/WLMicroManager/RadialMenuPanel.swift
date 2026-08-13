import AppKit
import SwiftUI
import WLKit

/// The compass: eight slices, driven by the joystick's radial channel.
///
/// Aim by pushing the stick, select by letting go. The menu appears on the first
/// touch rather than on the first aim — the pad reports `d: 0.0096` the moment
/// your finger lands, which is early enough for this to be a menu you read while
/// deciding rather than a receipt after the fact.
///
/// South is cancel. It has to be a slice: the centre cannot mean cancel, because
/// a stick held at centre and a stick the spring returned read identically and
/// the hold is silent. See `RadialAim` for the measurements behind that.
///
/// Five slices press a Raycast window-management hotkey, from the one table in
/// `WindowLayout`; the two lower diagonals are unbound. Nothing here can tell
/// whether Raycast acted on the chord, so a slice that appears to do nothing is
/// most likely Raycast quit or a hotkey reassigned.
@MainActor
final class RadialMenuController {

    static let shared = RadialMenuController()

    /// How long the committed slice stays up after release. A flick can engage
    /// and commit 60ms apart, so for a fast gesture this linger is the only
    /// feedback there is — it is load-bearing, not decoration.
    private static let linger: TimeInterval = 0.8

    private static let size = CGSize(width: 320, height: 320)

    /// Accessibility denial is the realistic failure and it has a message worth
    /// reading, so it goes the same way every other controller's does.
    var onError: ((String) -> Void)?

    private let model = RadialMenuModel()
    private var aim = RadialAim()
    private lazy var panel = HostingPanel { [model] in
        NSHostingView(rootView: RadialMenuView(model: model))
    }
    /// Bumped by every show and hide, so a pending close belonging to an earlier
    /// gesture knows it has been superseded.
    private var generation = 0

    private init() {}

    /// One `v.oai.rad` report.
    func handle(angle: Double, distance: Double) {
        // Corrected once, here, before anything reads it: this pad's zero points
        // west. See `RadialAim.compassTurns`.
        let turns = RadialAim.compassTurns(angle)
        let events = aim.update(angle: turns, distance: distance)
        model.track(turns: turns, distance: distance, reported: angle)

        for event in events {
            switch event {
            case .wake:
                generation += 1
                model.aimed = nil
                model.committed = nil
                panel.present(size: Self.size)
            case .aim(let direction):
                model.aimed = direction
            case .commit(let direction):
                model.aimed = nil
                model.committed = direction
                scheduleClose()
                perform(direction)
            case .sleep:
                close()
            }
        }
    }

    /// Presses the slice's chord. The panel never takes focus, so the window you
    /// were looking at is still frontmost and Raycast acts on it.
    private func perform(_ direction: RadialAim.Direction) {
        guard let layout = WindowLayout.forDirection(direction) else { return }
        Task { [weak self] in
            do {
                try await layout.tap.post()
            } catch {
                self?.onError?(error.localizedDescription)
            }
        }
    }

    private func close() {
        generation += 1
        panel.close()
    }

    private func scheduleClose() {
        generation += 1
        let generation = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.linger * 1_000_000_000))
            guard let self, self.generation == generation else { return }
            self.panel.close()
        }
    }
}

/// What the view draws. Separate from the controller so the view observes
/// position and selection without reaching for a device.
@MainActor
final class RadialMenuModel: ObservableObject {

    @Published var aimed: RadialAim.Direction?
    @Published var committed: RadialAim.Direction?

    /// The angle, unwrapped: it keeps accumulating past a full turn instead of
    /// snapping back to zero. Crossing east from 0.98 to 0.01 is a small move of
    /// the wrist, and a wrapped angle would animate it as a 350-degree spin.
    @Published var turns: Double = 0
    @Published var distance: Double = 0
    /// Exactly what the pad said, for the readout. Kept so the convention can be
    /// checked by pushing the stick and reading a number, rather than inferred.
    @Published var reported: Double = 0

    func track(turns angle: Double, distance: Double, reported: Double) {
        // A release reports `a: 0` along with `d: 0`, which is not an angle —
        // keep the last one so the needle retracts along the way it went out
        // rather than swinging to east on the way home.
        if distance > RadialAim.rest {
            let current = self.turns - floor(self.turns)
            var delta = (angle - floor(angle)) - current
            if delta > 0.5 { delta -= 1 }
            if delta < -0.5 { delta += 1 }
            self.turns += delta
            self.reported = reported
        }
        self.distance = distance
    }
}

struct RadialMenuView: View {

    @ObservedObject var model: RadialMenuModel

    private static let outer: CGFloat = 132
    private static let inner: CGFloat = 44
    /// Half a slice, less a hair for the gap between them.
    private static let halfSlice: Double = 1.0 / 16 - 0.004
    /// Just outside the wedges, where the position dot rides.
    private static let rim: CGFloat = 146

    /// Dark, like every other panel in this app: `.black.opacity(0.55)` over
    /// `.ultraThinMaterial`, as `PiModelPanel` and `OpenWithPanel` do it. The
    /// blue is lighter than the light-mode one was — 0.24/0.47/0.98 on a dark
    /// wedge is a fill you can barely tell from the unaimed grey.
    private static let accent = Color(red: 0.40, green: 0.64, blue: 1.0)
    private static let ink = Color.white
    private static let muted = Color.white.opacity(0.45)
    private static let quiet = Color.white.opacity(0.09)
    /// Committed-but-unbound. Opaque rather than a white alpha, because the
    /// label on top of it is white and a translucent grey leaves it unreadable.
    private static let inert = Color(white: 0.40)
    private static let hairline = Color.white.opacity(0.10)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18,
                                                                     style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Self.hairline, lineWidth: 1)
                )

            ForEach(RadialAim.Direction.allCases, id: \.rawValue) { direction in
                slice(direction)
            }
            ForEach(RadialAim.Direction.allCases, id: \.rawValue) { direction in
                label(direction)
            }

            needle
            dot
            centre
            readout
        }
        .frame(width: 320, height: 320)
        .animation(.easeOut(duration: 0.12), value: model.aimed)
        .animation(.easeOut(duration: 0.12), value: model.committed)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: model.turns)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: model.distance)
    }

    // MARK: - Slices

    private func slice(_ direction: RadialAim.Direction) -> some View {
        Wedge(
            centreTurns: direction.centreTurns,
            halfWidthTurns: Self.halfSlice,
            inner: Self.inner,
            outer: Self.outer
        )
        .fill(fill(direction))
    }

    private func fill(_ direction: RadialAim.Direction) -> Color {
        // Grey for anything that does nothing — cancel and the two unbound
        // diagonals alike, read from the same table the labels come from.
        let unbound = WindowLayout.forDirection(direction) == nil
        if model.committed == direction {
            return unbound ? Self.inert : Self.accent
        }
        if model.aimed == direction {
            return unbound
                ? Color.white.opacity(0.18)
                : Self.accent.opacity(0.28)
        }
        return Self.quiet
    }

    private func label(_ direction: RadialAim.Direction) -> some View {
        let radius = (Self.inner + Self.outer) / 2
        let radians = direction.centreTurns * 2 * .pi
        let selected = model.committed == direction
        // A layout name is several words where a compass letter was one glyph,
        // and a wedge is only about 69pt of arc at this radius, so names wrap
        // inside a fixed width instead of running over their neighbours.
        let named = WindowLayout.forDirection(direction) != nil
        return Text(Self.title(direction))
            .font(.system(size: named ? 11 : (direction == .south ? 12 : 15),
                          weight: selected ? .bold : .medium,
                          design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(-1)
            .foregroundStyle(colour(direction, selected: selected))
            .frame(width: 68)
            .position(
                x: 160 + radius * cos(radians),
                y: 160 - radius * sin(radians)
            )
    }

    private func colour(_ direction: RadialAim.Direction, selected: Bool) -> Color {
        // Committed sits on the accent fill, which is light — black reads on it
        // where white did on the old dark-blue one.
        if selected {
            return WindowLayout.forDirection(direction) == nil
                ? .white
                : Color(white: 0.06)
        }
        if WindowLayout.forDirection(direction) == nil { return Self.muted }
        // White, not accent: an aimed wedge is already tinted blue, and blue text
        // on it was the one label in here you had to squint at.
        return model.aimed == direction ? .white : Self.ink.opacity(0.85)
    }

    /// Raycast's own name for the layout a slice asks for. South is the menu's
    /// cancel, and the two unbound diagonals keep their compass letters, because
    /// a made-up name would be a lie.
    private static func title(_ direction: RadialAim.Direction) -> String {
        if let layout = WindowLayout.forDirection(direction) { return layout.name }
        return direction == .south ? "Cancel" : direction.label
    }

    // MARK: - Position

    /// From the centre out to wherever the stick is, so how far you have pushed
    /// is visible and not just which slice it lands in.
    ///
    /// Built as an offset-then-rotated capsule rather than a positioned one.
    /// `.position` expands to fill its container, which makes a following
    /// `.rotationEffect(anchor: .center)` turn about the panel's centre instead
    /// of the capsule's — that doubled the angle, and it is how the needle came
    /// to disagree with the dot.
    private var needle: some View {
        let length = max(2, Self.outer * CGFloat(min(model.distance, 1)))
        return Capsule()
            .fill(Self.accent.opacity(0.45))
            .frame(width: length, height: 3)
            .offset(x: length / 2)
            .rotationEffect(.radians(-model.turns * 2 * .pi), anchor: .center)
    }

    /// The exact angle, to a precision eight wedges cannot show. It rides the
    /// rim so it stays readable at full deflection, and fades towards the centre
    /// where the angle means nothing.
    private var dot: some View {
        Circle()
            .fill(Self.accent)
            .frame(width: 11, height: 11)
            .opacity(0.25 + 0.75 * min(model.distance, 1))
            .offset(x: Self.rim)
            .rotationEffect(.radians(-model.turns * 2 * .pi), anchor: .center)
    }

    /// What the pad actually said. Here so the angle convention can be settled by
    /// pushing the stick and reading a number.
    private var readout: some View {
        Text(String(format: "a %.3f  d %.3f", model.reported, model.distance))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(width: 320, height: 320, alignment: .bottom)
            .padding(.bottom, 9)
    }

    private var centre: some View {
        VStack(spacing: 1) {
            Text(centreTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .lineLimit(2)
                .foregroundStyle(model.committed != nil ? Self.accent : Self.ink)
            Text(centreCaption)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Self.muted)
        }
        // Just inside the hole in the middle of the wedges, so a wrapped layout
        // name does not run underneath them.
        .frame(width: Self.inner * 2)
    }

    private var centreTitle: String {
        if let committed = model.committed {
            return committed == .south ? "Cancelled" : Self.title(committed)
        }
        return model.aimed.map(Self.title) ?? "—"
    }

    /// Honest about the three slices that press nothing: "selected" under an
    /// unbound diagonal would read as a layout that failed.
    private var centreCaption: String {
        if let committed = model.committed {
            if committed == .south { return "nothing sent" }
            return WindowLayout.forDirection(committed) == nil ? "nothing bound" : "sent"
        }
        return model.aimed == nil ? "push to aim" : "let go to select"
    }
}

/// One slice of the donut. Angles come in as fractions of a turn with 0 east and
/// climbing counter-clockwise — the pad's convention — and are negated on the
/// way to screen space, where y grows downwards.
struct Wedge: Shape {

    let centreTurns: Double
    let halfWidthTurns: Double
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let origin = CGPoint(x: rect.midX, y: rect.midY)
        let from = Angle.radians(-(centreTurns + halfWidthTurns) * 2 * .pi)
        let to = Angle.radians(-(centreTurns - halfWidthTurns) * 2 * .pi)
        var path = Path()
        path.addArc(center: origin, radius: outer, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: origin, radius: inner, startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}
