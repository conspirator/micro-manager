# The bottom row: esc, new tab, Monologue, enter

## Why

Three of the four keys below the agent block did the wrong thing:

- The app treated matrix positions **10 and 11 as one wide keycap** and bound
  both to the same action. The pad's own keymap disagrees: row 3 is
  `KV_OAI_ACT10`, `KV_OAI_ACT11`, `KV_OAI_ACT12`, three distinct keycodes under
  three distinct caps. `docs/hacking.md` repeats the wide-cap claim and is
  wrong too.
- The voice key tapped **right command** for Superwhisper, which is no longer
  the dictation app in use. Monologue replaces it, and its trigger is right
  control.
- Keys 9 and 12 typed configured text into the focused agent's prompt. What is
  wanted there is a plain **Esc** and a plain **Enter**.

## What each key does

| key | role |
|---|---|
| 9 | taps Esc |
| 10 | creates a new Herdr tab and focuses it |
| 11 | starts or stops Monologue |
| 12 | taps Enter |

A string bound to any of these four in `config.json` still wins over the
built-in role, which is the existing escape hatch and the only thing left of
the old macro keys. `KeyBindings.defaults` therefore becomes empty, and the
`"10+11"` config alias goes away: it named a keycap that does not exist.

## Esc and Enter

`SystemKeyTap` in WLKit is a value describing a synthesised tap: key code,
modifier flags, how long to hold, how many taps, and the gap between them.
`.escape` is `0x35`, `.enter` is `0x24`, both unmodified. `post()` checks the
Accessibility grant, then posts a down/up pair per tap, setting the flag on the
way down and clearing it on the way up — a modifier posted without that leaves
listeners holding a key that never releases.

The taps go to whatever holds focus. Nothing is raised: an Esc that first
brought another window forward would be an Esc delivered to the wrong place.

## Monologue

Evidence for the two gestures is in Monologue's own bundle,
`Monologue.app/Contents/Resources/HOTKEY_RECORDING_BEHAVIOR.md`, and in the
state machine its binary logs (`idle -> pressAndHold -> doubleTapLock -> idle`):

- **Two taps within 1 s** cancel the buffered stop and hold the session open —
  hands-free. This is what `~/src/dotfiles/bin/right-control.swift` does, and it
  is how a recording starts.
- **One more tap while locked** stops the recording.
- **One tap from idle** with no second tap inside 1 s is *silently discarded*:
  no transcript, no error.

So the press is not one gesture repeated; it depends on whether a take is open,
which the app already tracks for the key's light:

- no take open → `.rightControlDouble` (two taps, 150 ms apart) → light goes
  breathing red;
- take open → `.rightControl` (one tap) → light back to dim white.

Stopping a take from the keyboard makes that state drift, and the drift heals
in one press: the app sends a single tap, Monologue discards it silently, and
the next press starts a recording properly.

## New Herdr tab

`tab.create` takes `workspace_id`, `cwd`, `label` and `focus`, and returns the
new tab; with `focus: true` there is no second call to make. The key passes the
**focused agent's** workspace and working directory, so the tab opens beside the
agent you were looking at rather than wherever the server would default to, and
falls back to a bare create when nothing has focus.

It also raises the terminal, for the reason `focusSlot` does: a tab you cannot
see is the same failure as a cursor you cannot see.

## Lighting

Each key keeps its own colour so the row does not read as one block: the two
system keys share a pale blue-grey, the new-tab key takes a cyan next to the
tab-cycle key's teal, and the voice key keeps white-at-rest and
recording-red-when-open. All are dim while idle, because a bound key that is
dark reads as broken — these keys no longer send a keystroke of their own.

## Tests

The parts worth testing are the ones that fail while looking like working
software: the tap table (a wrong key code posts a real event to the wrong key),
the pad geometry (an id in two roles, or a role on an unbound key), the
`tab.create` parameters, the light for each key, and the binding defaults.
`BridgeController` routing stays covered by hand on the hardware, as before —
the emulator always binds its keymap and so cannot fail the way the pad does.
