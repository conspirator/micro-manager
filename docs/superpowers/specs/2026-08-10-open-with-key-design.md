# Key 6 opens the focused agent's directory in a chosen app

Date: 2026-08-10

## What changes

Key 6, the first key of row 3, stops toggling the GitButler stack panel and
instead puts up a horizontal strip of app icons — Finder, Zed, Tower — and opens
the focused agent's working directory in whichever one you pick.

The stack feature's own code stays in the repo, dormant, exactly as the land
flow was left when key 7 changed. Only the wiring that pointed key 6 at it is
removed, so nothing in the new path reads or extends `StackPanel.swift`.

This is the second key to open the focused agent's directory in Tower, and that
duplication is deliberate: key 7 is the one-press shortcut for the app you reach
for most, key 6 is the deliberate choice among three.

## Behaviour

A press of key 6 asks Herdr for the focused agent and takes its
`workingDirectory`, the same source key 7 uses. If that cannot be resolved, the
press reports through `BridgeController.noteError` and **puts up no window**.
Nothing appears on screen; the reason is in the menu panel when you next open
it. A dialog for "Herdr is empty" would be louder than the mistake.

With a directory in hand, the app activates itself and shows the strip, centred
on the screen holding the mouse, in the manner of the macOS app switcher: a dark
rounded panel, one 64pt icon per destination, the selected icon on a rounded
highlight, and one line underneath naming the selected app and the directory
(abbreviated to `~/src/micro-manager`). The directory is resolved once, when the
strip opens, and held for the life of the strip.

Destinations, always in this order:

| app | bundle id |
|---|---|
| Finder | `com.apple.finder` |
| Zed | `dev.zed.Zed` |
| Tower | `com.fournova.Tower3` |

An app that is not installed is **left out of the strip** rather than shown and
refusing. An icon you can select but not launch is a key press that fails for no
visible reason; a strip with two icons in it is still honest. The selection
starts on Finder every time and is never remembered: a picker whose selection
moves on its own has to be read before Enter can be trusted, and a fixed start
makes "6, right, Enter" a gesture rather than a decision.

| input | effect |
|---|---|
| Left / Right | moves the selection, wrapping at both ends |
| Enter (or keypad Enter) | opens the directory in the selected app, dismisses the strip |
| Esc | dismisses without opening |
| key 6 again | dismisses, as the stack key toggled |
| click an icon | opens it |
| click the strip's own background | dismisses |
| Cmd, Control or Option held | passed through untouched — Cmd-Q is not the strip's to eat |
| any other key | swallowed, so it neither acts nor beeps |

Moving the mouse across the strip does not move the selection. Only a click
does, and a click also launches.

A click that lands in **another app** is not in this table: the strip loses key
status and dismisses, and focus stays where you just clicked. Yanking it back to
the terminal would fight the click you had just made.

Failures of the open itself do go to `noteError` — `Could not open Zed: …` —
because you asked for something specific and it did not happen. Only the
unresolvable-directory case is silent.

## Focus

This is the first window in the app that takes focus, and the first that can
leave you somewhere you did not ask to be.

The app is `.accessory`, so showing the strip means `NSApp.activate` plus
`makeKeyAndOrderFront`, which takes the keyboard from the terminal you were
typing in. So the controller records `NSWorkspace.shared.frontmostApplication`
before it activates, and on a dismissal that does not launch anything (Esc, key 6
again, a click on the strip's background) it reactivates that app. On Enter it
does not bother: the app being opened activates itself.

The strip also dismisses on `NSWindow.didResignKeyNotification`, so it cannot be
left behind a window reached some other way. That path restores nothing, because
whatever took key status is where you asked to be.

Keys are read with `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`,
installed when the strip opens and removed when it closes. A *local* monitor,
not a `CGEventTap`: a local monitor only sees events already delivered to this
app, so it needs no Input Monitoring grant and cannot swallow a keystroke meant
for an agent. `AGENTS.md` records that apps holding system-wide input monitoring
break communication with this pad — Work Louder name Karabiner and Logitech
Options+ — and a consuming system tap is that same category of thing. Returning
`nil` from the monitor consumes the key so it does not also beep.

## The light

Key 6 keeps the state it has today. It breathes at full brightness while the
strip is up and sits dim solid otherwise, in the same `0x7C4DFF`. Key 7 dropped
its state when it became stateless; key 6 stays stateful because the strip is a
window that is either on screen or not, so the existing `stackPanelOpen`
machinery is renamed rather than deleted.

## New code

`Sources/WLKit/OpenWith.swift`, splitting decision from I/O the way
`Tower.swift` does, and in WLKit for the same reason: `WLKitTests` is the only
test target in `Package.swift`, so a pure function in the executable target
could not be tested.

- `OpenWith.App` — `case finder, zed, tower`, each with `bundleID` and
  `displayName`. `App.all` is the strip order, and the only place that order is
  written down.
- `OpenWith.Choice` — an app and the resolved URL of its bundle. Only installed
  apps become choices.
- `OpenWith.Strip` — the directory, the choices, and the selection index.
  `move(_:)` wraps both ways and is a no-op with one choice. `selected` is
  non-optional: a strip cannot exist with an empty list.
- `OpenWith.Start` — `.show(Strip)` or `.refuse(String)`.
  `start(agent:locate:)` is the whole decision, pure. `locate` is injected so
  tests do not depend on what is installed on the machine running them.
- `OpenWith.Key` — `.left, .right, .confirm, .dismiss, .ignore, .passThrough`
  from an event key code (123, 124, 36, 76, 53) and its modifiers. Pure, so the
  mapping is tested without a window. A Command, Control or Option chord is
  `.passThrough`: the strip swallows plain keys so they do not beep, which means
  it must not swallow the ones that were never meant for it.
- `OpenWith.launch(_:directory:onError:)` — the `NSWorkspace` call, the only
  part with I/O, with `activates = true`.

The refusal messages reuse the exact strings key 7 already produces, so the two
keys cannot drift into describing one fault two ways:

| condition | message |
|---|---|
| nothing focused in Herdr | `Nothing has focus in Herdr right now.` |
| agent has no directory | `Herdr did not report a working directory for this agent.` |
| none of the three installed | `Finder, Zed and Tower are all missing.` |
| `NSWorkspace` returns an error | `Could not open <app>: <description>` |

`Sources/WLMicroManager/OpenWithPanel.swift`, an `OpenWithPanelController.shared`
holding an `NSPanel` with `[.titled, .fullSizeContentView]` — no
`.nonactivatingPanel` — title bar hidden, floating level, `canJoinAllSpaces`,
hosting a SwiftUI strip through `NSHostingView`.

It is **not** built on `FloatingPanel`. That class promises never to become key,
and three other panels depend on the promise; a mode switch inside it would put
the exception in the one place they all share.

## Edits to existing code

Renames only, with no new constant for position 6. Two names for one key is how
the panel and the pad start to disagree.

`Sources/WLKit/OAIProtocol.swift`
- `Pad.stackKeyID` becomes `Pad.openWithKeyID = 6`, doc comment rewritten.
  `boundKeyIDs` follows.

`Sources/WLKit/BridgeController.swift`
- `onStackKey` → `onOpenWithKey`; `stackPanelOpen` → `openWithPanelOpen`;
  `setStackPanelOpen` → `setOpenWithPanelOpen`; the `handleKeyPress` branch
  follows.
- The AG-binding warning naming "the stack key" is reworded.

`Sources/WLKit/StatusMapper.swift`
- `stackThread(open:_:)` → `openWithThread(open:_:)`, `stackColor` →
  `openWithColor`, same `0x7C4DFF`, same breath-when-open behaviour.

`Sources/WLMicroManager/MicroManagerApp.swift`
- The `StackPanelController` wiring block becomes `OpenWithPanelController`,
  keeping the visibility-change-to-light join.

`Sources/WLMicroManager/MenuPanelView.swift`
- `isStackKey` → `isOpenWithKey`; the click calls the same controller; help text
  becomes `Open the focused agent's directory in Finder, Zed or Tower`.

## Code left dormant

Untouched, unreferenced, still compiling: `Sources/WLMicroManager/StackPanel.swift`
and the `GitButler` status path behind it, alongside what `LandPanel` already
keeps alive from the last change. `StackPanelController.onVisibilityChange`
keeps a setter with no caller. That is the cost of keeping a feature intact
rather than half-deleting it.

## Tests

Written before the code.

`Tests/WLKitTests/OpenWithTests.swift` (new)
- `start` with an agent, a directory and all three apps located returns `.show`
  with three choices in Finder, Zed, Tower order, selected on Finder.
- Nothing focused, no working directory, and nothing installed each return their
  message, asserted as strings.
- Zed absent gives a two-choice strip, Finder then Tower, still selected on
  Finder. This is the guard on hiding rather than dimming: indexing `App.all`
  instead of the choices is the easy way to break it.
- Right from the last choice wraps to the first, Left from the first wraps to
  the last, and with one choice both are no-ops.
- `Key(keyCode:)` maps 123, 124, 36, 76 and 53, anything else is `.ignore`, a
  Command, Control or Option chord is `.passThrough`, and Shift or Caps Lock
  still drives the strip.

Renames in existing tests, which is where the row-3 off-by-one guards live:
- `PadGeometryTests` — key 6 is `openWithKeyID`, is bound, is not an agent slot;
  the row-3 comment follows.
- `KeyPressRoutingTests` — a press of key 6 fires `onOpenWithKey` once and posts
  no keystroke, so a press landing in a neighbour's branch fails here.
- `StatusMapperTests` — `openWithThread` is dim solid closed, full breath open,
  on key 6; the Tower colour comparison follows the rename.
- `KeyBindingsTests` — key 6 still takes no macro, so a stray `"6"` in
  `config.json` cannot steal the key.
- `SystemKeyTapTests`, `LiveDeviceTests` — rename only.

The panel itself is not tested, like every other panel in the app. Two of its
behaviours cannot be covered here and are verified by hand: Esc putting the
keyboard back in the terminal it came from, and the strip dismissing when it
loses key status.

## Docs

- `README.md:56` — row-3 table: the stack row becomes
  `| open with | opens the focused agent's directory in Finder, Zed or Tower |`.
- `README.md:80` — `### The stack key` rewritten for the new key, noting the
  stack code is dormant rather than gone.
- `docs/index.html:357` — keycap label; `:371` — the bullet describing the stack.
- `AGENTS.md` — a trap entry: this is the only window that takes focus, it reads
  keys with a local `NSEvent` monitor and not a `CGEventTap` on purpose, and the
  two hand-checked behaviours above.

## Out of scope

- Remembering the last choice.
- A config-driven destination list, or more destinations.
- Restoring the stack panel onto another key. The code stays; putting it back is
  its own change.
- Rebinding key 6 from `config.json`. Only keys 9 to 12 take macros.
- Opening anything narrower than the directory: no file, no branch, no diff.
- Hover moving the selection.
