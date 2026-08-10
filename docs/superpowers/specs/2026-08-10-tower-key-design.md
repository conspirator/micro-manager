# Key 7 opens the focused agent's directory in Tower

Date: 2026-08-10

## What changes

Key 7, the second key of row 3, stops triggering the GitButler land flow and
instead opens the focused agent's working directory in
[Tower](https://www.git-tower.com) (bundle id `com.fournova.Tower3`), bringing
Tower forward.

The land feature's own code stays in the repo, dormant. Only the wiring that
pointed key 7 at it is removed, so nothing in the new path reads or extends
`LandPanel.swift` or `GitButler`'s land functions.

No new UI. No new window, no panel, no confirmation step.

## Behaviour

A press of key 7:

1. asks Herdr for the focused agent (`HerdrClient.focusedAgent()`);
2. takes that agent's `workingDirectory`;
3. opens it in Tower with `NSWorkspace.shared.open(_:withApplicationAt:configuration:completionHandler:)`,
   `configuration.activates = true`.

Failures surface through `BridgeController.noteError`, where the bridge's own
errors already appear in the menu panel, and reuse wording that already exists
in the app so the messages stay consistent:

| condition | message |
|---|---|
| nothing focused in Herdr | `Nothing has focus in Herdr right now.` (as `injectPrompt`) |
| agent has no directory | `Herdr did not report a working directory for this agent.` (as `StackPanel`) |
| Tower not installed | `Tower is not installed.` |
| `NSWorkspace` returns an error | `Could not open Tower: <description>` |

The key is stateless: pressing it twice opens Tower twice, which is a no-op the
second time because Tower already has the repository open.

Clicking key 7 in the menu panel's pad mirror does exactly the same thing. The
panel and the pad must never disagree about what a key does, and a dead button
in the mirror would be one more way to be unsure whether the key works.

## Why `NSWorkspace` and not `gittower .`

`gittower` lives at `/usr/local/bin/gittower` on this machine, and a
GUI-launched app inherits `/usr/bin:/bin:/usr/sbin:/sbin`, so the binary this
app can see is not the one a terminal finds. `GitButler.swift` carries a whole
search (Homebrew, Cargo, then the login shell) to work around exactly that for
`but`. `NSWorkspace` needs no PATH, no shell, no CLI installed, and raises Tower
as part of opening it.

## New code

`Sources/WLKit/Tower.swift`, an `enum Tower` in the shape of
`InspectorLauncher.swift`:

- `static let bundleID = "com.fournova.Tower3"`
- `static var url: URL?` — `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`,
  so a missing Tower reports rather than crashes
- `static func launch(onError: @escaping (String) -> Void)` — resolves the
  agent, then opens
- `static func target(agent: HerdrAgent?, towerURL: URL?) -> Result<URL, String>`
  — the pure decision: which directory to open, or which message to report.
  Split out so both failure messages are testable without touching
  `NSWorkspace` or Herdr.

It goes in WLKit, not `Sources/WLMicroManager/` beside `InspectorLauncher`,
for one reason: `WLKitTests` is the only test target in `Package.swift`, so a
pure function in the executable target could not be tested. WLKit already
reaches for `NSWorkspace` in `BridgeController.raiseTerminal()`, so nothing new
is being dragged into it.

## Edits to existing code

`Sources/WLKit/OAIProtocol.swift`
- `landKeyID` becomes `towerKeyID = 7`, with a doc comment saying it opens the
  focused agent's directory in Tower. `boundKeyIDs` follows the rename.
- There is deliberately no second constant for position 7. Two names for one
  key is how the panel and the pad start to disagree.

`Sources/WLKit/BridgeController.swift`
- `onLandKey` becomes `onTowerKey`; `handleKeyPress`'s `Pad.landKeyID` branch
  becomes `Pad.towerKeyID` calling `onTowerKey`.
- Remove `landPanelOpen`, `setLandPanelOpen`, and the `landThread` entry in the
  thread list, replaced by `StatusMapper.towerThread(config)`.
- `onKeyIntercept` stays as a property. It has no caller once land is unwired,
  and it is the only hook for "a key means cancel right now", so it stays for
  the next feature that needs it.

`Sources/WLKit/StatusMapper.swift`
- `landThread(open:_:)` becomes `towerThread(_:)`: dim solid, no state, like
  `tabCycleThread` and `newTabThread`. A bound-but-dark key reads as broken, so
  it is lit at `brightness * 0.3` like its neighbours.
- `landColor` becomes `towerColor`, keeping `0xE91E63`. Row 3 is purple, this,
  teal, cyan; a Tower blue would blend into the two keys beside it.

`Sources/WLMicroManager/MicroManagerApp.swift`
- Remove the `LandPanelController` wiring block (`onVisibilityChange`,
  `onLandKey`) and the `onKeyIntercept` closure that made every non-land key
  mean cancel.
- Add `bridge.onTowerKey = { [weak bridge] in Tower.launch { bridge?.noteError($0) } }`,
  weakly captured like the other handlers.

`Sources/WLMicroManager/MenuPanelView.swift`
- `isLandKey` becomes `isTowerKey`; the click calls the same `Tower.launch`,
  reporting through `bridge.noteError`.
- Help text: `Open the focused agent's directory in Tower`.

## Code left dormant

Untouched, unreferenced, still compiling and still tested:
`Sources/WLMicroManager/LandPanel.swift`, `GitButler.land`,
`GitButler.landPlan`, `Tests/WLKitTests/GitButlerLandPlanTests.swift`.

`LandPanelController.onVisibilityChange` keeps its setter with no caller. That
is the cost of keeping the feature intact rather than half-deleting it.

## Tests

Written before the code, in the existing files:

`Tests/WLKitTests/PadGeometryTests.swift`
- `Pad.towerKeyID == 7`, is in `boundKeyIDs`, and is not an agent slot.

`Tests/WLKitTests/KeyPressRoutingTests.swift`
- Pressing key 7 fires `onTowerKey` exactly once and posts no keystroke. This is
  the row-3 off-by-one guard the existing test makes: key 7 sits beside the
  stack and tab-cycle keys, and a press landing in the wrong branch would fire
  the wrong action with nothing reporting a fault.

`Tests/WLKitTests/StatusMapperTests.swift`
- `towerThread` is `towerColor`, solid, dimmed, on key 7.
- The `Pad.agentSlot(for:)` assertion at line 121 follows the rename.

`Tests/WLKitTests/KeyBindingsTests.swift`
- Key 7 is still not in `rebindableKeyIDs`, so a stray `"7"` in `config.json`
  cannot take the key. This is the guarantee the existing test at line 25 makes
  under the old name.

`Tests/WLKitTests/TowerTargetTests.swift` (new file)
- `target(agent:towerURL:)` returns the agent's directory when both are present.
- Nothing focused, no working directory, and no Tower each return their message.

## Docs

- `README.md:57` — row 3 table: the land row becomes
  `| tower | opens the focused agent's directory in Tower |`.
- `README.md` — the paragraph listing what row 3 does, if it names land.
- `docs/index.html:359,373` — the keycap label and the bullet describing land.
- `AGENTS.md` — nothing to add. The trap it records (a panel click is not a test
  of the pad) already covers this key, and this change keeps the two in step.

## Out of scope

- Any Tower feature beyond opening a repository: no branch, no commit, no diff.
- Restoring land on another key. The code stays; if it is wanted back, that is
  its own change.
- Rebinding key 7 from `config.json`. Only keys 9 to 12 take macros, and that
  stays true.
