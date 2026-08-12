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
/// Nothing is bound to the other seven yet. This is the panel and the gesture;
/// what a slice does comes next.
@MainActor
final class RadialMenuController {

    static let shared = RadialMenuController()

    /// How long the committed slice stays up after release. A flick can engage
    /// and commit 60ms apart, so for a fast gesture this linger is the only
    /// feedback there is — it is load-bearing, not decoration.
    private static let linger: TimeInterval = 0.8

    private static let size = CGSize(width: 320, height: 320)

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
            case .sleep:
                close()
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

    private static let accent = Color(red: 0.24, green: 0.47, blue: 0.98)
    private static let ink = Color(red: 0.10, green: 0.12, blue: 0.16)
    private static let muted = Color(red: 0.54, green: 0.57, blue: 0.62)
    private static let quiet = Color(white: 0.945)
    private static let hairline = Color(red: 0.894, green: 0.906, blue: 0.925)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white)
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
        if model.committed == direction {
            return direction == .south ? Self.muted : Self.accent
        }
        if model.aimed == direction {
            return direction == .south
                ? Self.muted.opacity(0.22)
                : Self.accent.opacity(0.20)
        }
        return Self.quiet
    }

    private func label(_ direction: RadialAim.Direction) -> some View {
        let radius = (Self.inner + Self.outer) / 2
        let radians = direction.centreTurns * 2 * .pi
        let selected = model.committed == direction
        return Text(Self.title(direction))
            .font(.system(size: direction == .south ? 12 : 15, weight: selected ? .bold : .medium,
                          design: .rounded))
            .foregroundStyle(colour(direction, selected: selected))
            .position(
                x: 160 + radius * cos(radians),
                y: 160 - radius * sin(radians)
            )
    }

    private func colour(_ direction: RadialAim.Direction, selected: Bool) -> Color {
        if selected { return .white }
        if direction == .south { return Self.muted }
        return model.aimed == direction ? Self.accent : Self.ink.opacity(0.75)
    }

    /// South is cancel; the rest are still just their directions, because
    /// nothing is bound to them yet and a made-up name would be a lie.
    private static func title(_ direction: RadialAim.Direction) -> String {
        direction == .south ? "Cancel" : direction.label
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
            .fill(Self.accent.opacity(0.35))
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
            .foregroundStyle(Self.muted.opacity(0.7))
            .frame(width: 320, height: 320, alignment: .bottom)
            .padding(.bottom, 9)
    }

    private var centre: some View {
        VStack(spacing: 1) {
            Text(centreTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(model.committed != nil ? Self.accent : Self.ink)
            Text(centreCaption)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(Self.muted)
        }
        .frame(width: Self.inner * 1.8)
    }

    private var centreTitle: String {
        if let committed = model.committed {
            return committed == .south ? "Cancelled" : committed.label
        }
        return model.aimed.map(Self.title) ?? "—"
    }

    private var centreCaption: String {
        if model.committed != nil { return "selected" }
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
