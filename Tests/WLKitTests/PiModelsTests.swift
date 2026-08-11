import XCTest
@testable import WLKit

/// The dial's model picker, with no Herdr socket and no filesystem in sight.
///
/// Every failure here is one that looks like working software: a step count off
/// by one lands you on a model you did not ask for and says nothing, and a glob
/// in `enabledModels` makes pi's cycle list longer than the list on screen while
/// both still look reasonable.
final class PiModelsTests: XCTestCase {

    private let settings: [String: Any] = [
        "enabledModels": [
            "apple-anthropic/anthropic.claude-opus-5",
            "apple-anthropic/anthropic.claude-sonnet-5",
            "apple-genai-bridge/afm-v11-4-zap-latest",
        ]
    ]

    private func entries() -> [PiModels.Entry] {
        PiModels.enabledModels(in: settings)
    }

    // MARK: - Reading the list

    func testKeepsTheOrderPiCyclesIn() {
        let list = entries()
        XCTAssertEqual(list.map(\.id), [
            "anthropic.claude-opus-5",
            "anthropic.claude-sonnet-5",
            "afm-v11-4-zap-latest",
        ])
        XCTAssertEqual(list.first?.provider, "apple-anthropic")
        XCTAssertEqual(list.first?.reference, "apple-anthropic/anthropic.claude-opus-5")
    }

    /// A thinking suffix is pi's business, not the pad's: it changes what the
    /// model starts at, never how many presses reach it.
    func testStripsAThinkingSuffix() {
        let list = PiModels.enabledModels(in: ["enabledModels": ["p/m:high", "p/n"]])
        XCTAssertEqual(list.map(\.id), ["m", "n"])
    }

    func testAnEntryWithNoProviderStillCounts() {
        let list = PiModels.enabledModels(in: ["enabledModels": ["opus", "sonnet"]])
        XCTAssertEqual(list.map(\.id), ["opus", "sonnet"])
        XCTAssertEqual(list.first?.provider, "")
        XCTAssertEqual(list.first?.reference, "opus")
    }

    func testMissingOrEmptyListReadsAsNothing() {
        XCTAssertTrue(PiModels.enabledModels(in: [:]).isEmpty)
        XCTAssertTrue(PiModels.enabledModels(in: ["enabledModels": []]).isEmpty)
    }

    // MARK: - Refusals

    func testRefusesWhenThereIsNothingToPickBetween() {
        let start = PiModels.start(
            entries: PiModels.enabledModels(in: ["enabledModels": ["p/only"]]),
            paneText: "(p) only • high"
        )
        guard case .refuse(let message) = start else { return XCTFail("expected a refusal") }
        XCTAssertTrue(message.contains("enabledModels"), message)
    }

    /// A glob expands inside pi to however many models match, so the list on
    /// screen would be shorter than the list ctrl+p walks and every step count
    /// would be wrong. Refusing is the honest answer.
    func testRefusesAGlob() {
        for pattern in ["apple-anthropic/*", "p/claude-?", "p/m[12]"] {
            let start = PiModels.start(
                entries: PiModels.enabledModels(in: ["enabledModels": [pattern, "p/other"]]),
                paneText: "(p) other"
            )
            guard case .refuse(let message) = start else {
                return XCTFail("expected a refusal for \(pattern)")
            }
            XCTAssertTrue(message.contains(pattern), message)
        }
    }

    func testRefusesWhenTwoEnabledModelsShareAnID() {
        let start = PiModels.start(
            entries: PiModels.enabledModels(in: ["enabledModels": ["one/m", "two/m"]]),
            paneText: "(one) m"
        )
        guard case .refuse(let message) = start else { return XCTFail("expected a refusal") }
        XCTAssertTrue(message.contains("m"), message)
    }

    // MARK: - Finding pi in its own footer

    func testReadsTheModelFromTheFooter() {
        let footer = """
             ~/src/micro-manager (main)
             0.0%/1.0M (auto)      (apple-anthropic) anthropic.claude-sonnet-5 • high
             MCP: 0/3 servers
            """
        XCTAssertEqual(PiModels.currentIndex(paneText: footer, entries: entries()), 1)
    }

    /// Pi drops the provider when only one is available, and truncates the
    /// right-hand side in a narrow pane. The id is the part that survives.
    func testReadsTheModelWithoutAProviderPrefix() {
        XCTAssertEqual(
            PiModels.currentIndex(paneText: "0.0%/1.0M  afm-v11-4-zap-latest\n", entries: entries()),
            2
        )
    }

    /// Scrollback talks about other models: an assistant message naming opus
    /// must not outvote the footer at the bottom.
    func testTheLastMentionWins() {
        let text = """
            I would use anthropic.claude-opus-5 for this.
            0.0%/1.0M (auto)   (apple-anthropic) anthropic.claude-sonnet-5 • high
            """
        XCTAssertEqual(PiModels.currentIndex(paneText: text, entries: entries()), 1)
    }

    /// A pane started with --model carries something that is not in the list.
    /// Guessing zero here would send presses that land somewhere arbitrary.
    func testAModelOutsideTheListIsNotAGuess() {
        XCTAssertNil(
            PiModels.currentIndex(paneText: "0.0%/1.0M  some-other-model • high", entries: entries())
        )
        XCTAssertNil(PiModels.currentIndex(paneText: "", entries: entries()))
    }

    /// One id must not match another by being a prefix of it.
    func testMatchesWholeIDsOnly() {
        let list = PiModels.enabledModels(in: ["enabledModels": ["p/claude", "p/claude-5"]])
        XCTAssertEqual(PiModels.currentIndex(paneText: "(p) claude-5 • high", entries: list), 1)
        XCTAssertEqual(PiModels.currentIndex(paneText: "(p) claude • high", entries: list), 0)
    }

    // MARK: - The picker

    func testTurningWrapsBothWays() {
        var picker = PiModels.Picker(entries: entries(), current: 0)
        XCTAssertEqual(picker.selection, 0, "the highlight starts where pi is")
        picker.move(-1)
        XCTAssertEqual(picker.selection, 2, "counter-clockwise from the top reaches the bottom")
        picker.move(1)
        XCTAssertEqual(picker.selection, 0)
        picker.move(3)
        XCTAssertEqual(picker.selection, 0, "a full turn comes home")
    }

    func testAnUnknownCurrentStillMoves() {
        var picker = PiModels.Picker(entries: entries(), current: nil)
        XCTAssertEqual(picker.selection, 0)
        picker.move(1)
        XCTAssertEqual(picker.selection, 1)
        XCTAssertNil(picker.steps, "there is no distance from a position we cannot see")
    }

    /// Forward only, wrapping, because ctrl+p is the one chord we trust to
    /// arrive: shift+ctrl+p depends on the terminal reporting modifiers.
    func testStepsCountForwardWithWraparound() {
        var picker = PiModels.Picker(entries: entries(), current: 2)
        XCTAssertEqual(picker.steps, 0, "committing where you already are sends nothing")
        picker.move(1)
        XCTAssertEqual(picker.selection, 0)
        XCTAssertEqual(picker.steps, 1, "two to zero wraps in one press, not two back")
        picker.move(1)
        XCTAssertEqual(picker.steps, 2)
    }

    // MARK: - Committing

    /// A pane that advances one model per chord: the ordinary case.
    private func pane(_ list: [PiModels.Entry], at index: Int) -> FakePane {
        FakePane(list: list, index: index)
    }

    private final class FakePane {
        let list: [PiModels.Entry]
        var index: Int
        var chords = 0
        var reads = 0
        /// How many models each chord moves. Zero is a pi that never answered.
        var stride = 1

        init(list: [PiModels.Entry], index: Int) {
            self.list = list
            self.index = index
        }

        func send() { chords += 1; index = (index + stride) % list.count }
        func read() -> String { reads += 1; return "0.0%/1.0M  \(list[index].id) • high" }
    }

    func testCommitStepsUntilTheFooterNamesTheChosenModel() async {
        let list = entries()
        let fake = pane(list, at: 0)
        var picker = PiModels.Picker(entries: list, current: 0)
        picker.move(2)

        let outcome = await PiModels.advance(
            picker,
            send: { fake.send() },
            read: { fake.read() },
            pause: {}
        )

        XCTAssertEqual(outcome, .landed)
        XCTAssertEqual(fake.chords, 2)
        XCTAssertEqual(fake.index, 2)
    }

    func testCommitSendsNothingForTheModelPiIsAlreadyOn() async {
        let list = entries()
        let fake = pane(list, at: 1)
        let picker = PiModels.Picker(entries: list, current: 1)

        let outcome = await PiModels.advance(
            picker, send: { fake.send() }, read: { fake.read() }, pause: {}
        )

        XCTAssertEqual(outcome, .landed)
        XCTAssertEqual(fake.chords, 0)
    }

    /// The failure this loop exists for. Pi's `cycleModel` awaits an auth check
    /// per model and nothing serialises it, so a burst of chords can leave the
    /// model where it was. One press that changes nothing must stop the loop and
    /// say so, not hammer the pane.
    func testCommitGivesUpWhenPiDoesNotMove() async {
        let list = entries()
        let fake = pane(list, at: 0)
        fake.stride = 0
        var picker = PiModels.Picker(entries: list, current: 0)
        picker.move(1)

        let outcome = await PiModels.advance(
            picker, send: { fake.send() }, read: { fake.read() }, pause: {}, pollsPerStep: 3
        )

        XCTAssertEqual(fake.chords, 1, "one press, then stop")
        guard case .failed(let message) = outcome else { return XCTFail("expected a failure") }
        XCTAssertTrue(message.contains("anthropic.claude-opus-5"), message)
    }

    /// A pi whose cycle list is not ours — a `--models` flag, or a provider that
    /// failed its auth check — moves by something other than one, and can step
    /// past the target forever. Landing is decided by the footer, never by
    /// counting, so the walk has to stop inside the length of the list and say
    /// where pi actually ended up.
    func testCommitStopsWhenTheModelKeepsMissingTheTarget() async {
        let list = PiModels.enabledModels(in: [
            "enabledModels": ["p/a", "p/b", "p/c", "p/d"]
        ])
        let fake = pane(list, at: 0)
        fake.stride = 2
        var picker = PiModels.Picker(entries: list, current: 0)
        picker.move(1)

        let outcome = await PiModels.advance(
            picker, send: { fake.send() }, read: { fake.read() }, pause: {}
        )

        guard case .failed(let message) = outcome else { return XCTFail("expected a failure") }
        XCTAssertTrue(message.contains("c"), message)
        XCTAssertLessThanOrEqual(fake.chords, list.count - 1, "bounded by the list, whatever happens")
    }

    func testCommitRefusesWhenPiIsOnAModelOutsideTheList() async {
        let list = entries()
        var picker = PiModels.Picker(entries: list, current: nil)
        picker.move(1)
        var sent = 0

        let outcome = await PiModels.advance(
            picker, send: { sent += 1 }, read: { "" }, pause: {}
        )

        XCTAssertEqual(sent, 0)
        guard case .failed(let message) = outcome else { return XCTFail("expected a failure") }
        XCTAssertTrue(message.contains("which model"), message)
    }
}
