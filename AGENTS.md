# Notes for agents working on this repo

Start with `README.md` for what the app does and `docs/hacking.md` for the
protocol. This file is for the things that cost hours to learn and are invisible
in the code.

## The pad on this machine

`Codex Micro` — vendor `0x303A`, product `0x8360`, USB, serial `441BF6C83908`.
Renamed from stock, so do not match on the product string. `WLDevice` matches on
vendor only, and its primary usage page is `0x1` (keyboard); the vendor
collection is in `DeviceUsagePairs` as `0xff00:1`, which is what
`hasVendorCollection` finds.

Its `keymap.json` is **11,403 bytes, arriving as 187 reports in about 0.39s**.
Keep that number in mind: it is bigger than several buffers in this codebase
were sized for.

A copy of the keymap as it was before this app ever wrote to it is at
`/tmp/codex-micro-keymap-backup.json` — move it somewhere durable if the
original `ACT` bindings matter to you.

## Keycode families: AG vs ACT

This pad shipped with two families on the active layer:

```
row 0: KV_OAI_AG00,  KV_OAI_AG01
row 1: KV_OAI_AG02 … KV_OAI_AG05
row 2: KV_OAI_ACT06 … KV_OAI_ACT09     ← action row, ACT not AG
row 3: KV_OAI_ACT10 … KV_OAI_ACT12
```

`OAI.agIndex` only parses names prefixed `AG`, so **every press of keys 6–12 was
discarded before `handleKeyPress` ever ran** — agent keys worked, the whole
action row was dead, and nothing reported a fault. The firmware does accept a
rewrite to `AG06`–`AG12` (verified), which is what `KeymapManager.apply` does,
so the app heals this itself *provided the keymap read succeeds*.

If a pad ever looks dead from the action row down, read the keymap before
anything else.

Row 3 having **three** codes is also the answer to a question the code used to
get wrong: matrix positions 10 and 11 are two keys, not one wide keycap. The app
bound both to the voice action for a while, which cost a key.

## The bottom row posts real keystrokes

Keys 9, 11 and 12 synthesise key events, so they need **Accessibility** as well
as Input Monitoring, and both grants are keyed to the code signature.

Do not test them by posting into the terminal you are working in. An `Esc` from
a test script killed the agent session that launched it — which is also the
quickest proof the mechanism works. Use an inert key code (F16, `0x6A`) and a
listen-only `CGEvent.tapCreate` to count what actually landed.

Key 11 taps right control for Monologue, and start and stop are **different
gestures**: two taps inside 1s lock a recording hands-free, one further tap ends
it, and a lone tap from idle is discarded in silence. The rules are in
`Monologue.app/Contents/Resources/HOTKEY_RECORDING_BEHAVIOR.md`, and its binary
logs the state machine (`idle -> pressAndHold -> doubleTapLock -> idle`) if you
need to watch it. That silent discard is what makes the light's state safe: when
it drifts, the wasted press is the one Monologue throws away anyway.

## Open problems

1. **`cycleTabs()` and `injectPrompt()` never call `raiseTerminal()`.**
   `focusSlot()` does, deliberately — "an agent key pressed from a browser used
   to move a cursor you could not see". `newTab()` does too, for the same
   reason. The tab-cycle and macro keys never got the same treatment: the action
   fires, Herdr accepts it, and nothing visible happens because the terminal
   stays behind whatever window is in front.
2. **Reassembly is quadratic.** `drainRPC` rescans the buffer for a complete
   object on every chunk: 11 KB parses in 0.06s, 256 KB takes 29s. Fine for a
   keymap, not fine for anything larger.
3. **`debugAccumulator` still clears at 4096 characters.** Same shape as the RPC
   bug that was just fixed, on the device-log channel. Unproven, but a long line
   would vanish the same way.

## The pad can wedge, and USB cannot reset it

On 2026-08-10 the pad stopped answering entirely: `sys.version` timed out for a
single clean client, and 90 seconds of pressing every key produced **0 raw
reports and 0 bytes**. No keystrokes reached the Mac either. It still enumerated
as `registered, matched, active` with the `0xff00:1` vendor collection intact, so
the USB stack was alive and the application firmware was not.

**The rear button is power, not reset.** From Work Louder's own setup page for
this pad, <https://worklouder.cc/openai-micro-setup>:

- click once to turn **on**;
- **hold 2 seconds to turn off** — so "press and hold to reset it" turns the pad
  off, which then looks exactly like a wedge, because a powered-off pad still
  enumerates over USB;
- click once while on to **sleep**, then any key wakes it;
- holding it 3 seconds enters Bluetooth comms mode instead (underglow blue).

Hold it far too long and the backlight goes **red**: that is a factory reset, and
it wipes the keymap. Keep a copy of `keymap.json` somewhere durable first.

**The real reset is inside the case** (their step 08, for "if your Micro freezes,
or will not turn on/off"): four corner screws, lift the PCB gently — a flat cable
runs to a lower board — and press the button marked with **one dot** (Reset; two
dots is Boot). That is the only reliable reboot for a wedged firmware task,
because the battery means pulling USB is not a power cycle.

**Firmware v0.6.2-rc.9 describes this failure as a bug it fixes**, in
<https://github.com/worklouder/cm-v2-fw-releases/releases>: "the charging-only
state keeps lighting, controls, and communication disabled until the device is
restarted or the cable is removed", plus "accidental rear-button activity cannot
immediately interrupt the transition" and "interrupted power transitions can
recover safely". Earlier notes mention recovery from "blocked USB communication"
and from a device that "appears connected but stops responding". Check what
firmware a pad is on before blaming this app.

**Work Louder warn that other input-monitoring apps break communication with the
pad**, naming Karabiner and Logitech Options+. Anything holding Input Monitoring
for hotkeys is a suspect — on this machine that includes Raycast and Monologue —
and it is the same failure as running the Inspector alongside the bridge.

What that episode teaches, in general:

- **Three silent clients means the device.** This app, the Inspector and Work
  Louder's own Input app all hung on the same pad. One client failing is a bug
  in that client; all three failing is the hardware, and no amount of reading
  this code will fix it.
- **`0x303A` is Espressif**, so this is an ESP32-S3. The external button will not
  give you a bootloader; Reset and Boot are both internal.
- **Do not diagnose RPC while the app is running.** Quit it first. Every bridge
  start used to write flash (see the fix on 2026-08-10), and a second client
  turns "no reply" into a puzzle with two possible causes.

A standalone probe is the fastest way to separate app from device: open
`WLDevice`, count `onRawReport` bytes, call `sys.version`, and print every
`onNotification`. Build one against the SwiftPM products without adding a target:

```sh
swift build
swiftc -o probe main.swift -I .build/debug -L .build/debug -lWLKit \
  -framework IOKit -framework AppKit
```

Two outside references worth knowing, both clean-room and both agreeing with this
repo's reading of the protocol: <https://github.com/panghy/cm2-probe> (documents
`sys.bootloader` as a real method, and confirms lighting never touches flash
while `fs.write` does) and
<https://github.com/boopdotpng/work-louder-oai/blob/main/docs/PROTOCOL.md>.


## Traps that waste time

- **The open-with strip is the only window that takes the keyboard.** Every
  other panel here is a `.nonactivatingPanel` that never becomes key, on
  purpose; key 6's picker has to read the arrow keys, so it activates the app.
  Two things about it cannot be covered by a test in this repo and are worth
  checking by hand after any change: Esc puts you back in the app you came from,
  and the strip dismisses when it loses key status instead of sitting behind
  whatever you switched to. It reads keys with
  `NSEvent.addLocalMonitorForEvents` and **not** a `CGEventTap` — a local monitor
  only sees events already delivered to this app, so it cannot swallow a
  keystroke meant for an agent, and a consuming system-wide tap is the same
  category of thing Work Louder name as breaking communication with this pad.
- **A click in the menu panel is not a test of the pad.** `MenuPanelView` calls
  `bridge.cycleTabs()`, `bridge.focusSlot(_:)` and friends *directly*; only a
  physical press goes pad → `v.oai.hid` → `handleKeyPress`. If clicking works
  and pressing does not, the HID path is the suspect, not the action.
- **Input Monitoring is keyed to the code signature.** A local
  `scripts/bundle.sh` build signs with *Apple Development*; a CI release signs
  with *Developer ID*. Same path, same bundle id, different designated
  requirement — so the grant does not carry over, and the stale record stops
  `IOHIDRequestAccess` from prompting again. Clear it with
  `tccutil reset ListenEvent cc.worklouder.micromanager`, then enable the app in
  System Settings → Privacy & Security → Input Monitoring. Because the app is
  `LSUIElement`, **no consent dialog ever appears** — it must be flipped by hand.
- **A refused open is `0xE00002E2` (`kIOReturnNotPermitted`) on macOS 15**, not
  `0xE00002C1` and not `kIOReturnNotFound` (which is `0xE00002F0`). Print the
  constants rather than trusting memory:
  `swift -e 'import IOKit; print(kIOReturnNotPermitted)'`.
- **The Inspector contends for the pad.** `WLDevice` opens non-exclusively, so
  both processes receive each other's replies and `BridgeController` sets
  `contendingClient`. Do not run the Inspector and the bridge together while
  diagnosing RPC; it looks exactly like a flaky device.
- **`WL_TERMINAL_BUNDLE_ID` cannot help a login-item launch.** A GUI-launched app
  never sees your shell environment, so the compiled default is what runs. It is
  `com.googlecode.iterm2`; Herdr lives in iTerm2 on this machine.
- **The emulator and the hardware fail differently.** An emulated pad always
  binds its keymap, so `handleKeyPress` runs and every action works — a bug that
  only exists on the wire will pass every emulator test.

## Diagnostics that worked

- **Herdr logs every request it receives**, with the client's id, at
  `~/.config/herdr/herdr-server.log`. This app's ids are `wl_<n>`, so
  `grep 'request_id="wl_' …` proves whether a keypress reached Herdr — better
  evidence than any UI. `tab.focus` is logged with `changes_ui=true`.
- **Talk to Herdr directly** to separate its behaviour from the app's:
  `echo '{"id":"x","method":"tab.list","params":{}}' | nc -U ~/.config/herdr/herdr.sock`
  A bogus method name is the cheapest way to get the **full method list** — the
  `invalid_request` error names every variant it expected. That is how
  `tab.create` and its `workspace_id`/`cwd`/`label`/`focus` params were found;
  `herdr tab create --help` confirms them. It returns the tab **unfocused**
  unless you pass `focus`.
- **Count raw reports** to tell "nothing arrives" from "arrives but never
  parses": set `WLDevice.onRawReport`, sum `bytes[offset + 1]` accepting both
  alignments (the stack includes the report id, so a frame reads
  `[id][channel][len][payload…]`), and time the first and last chunk. That is
  what showed 11,403 bytes landing in 0.39s while the call timed out at 8s.
- **`sys.version` versus `fs.read`** is a useful pair: the first fits in one
  report, the second spans 187. If the small one answers and the big one times
  out, suspect reassembly, not the firmware.

## Conventions

Conventional commit subjects (`fix:`, `feat:`, `docs:`, `ci:`), lowercase, with
a body that explains *why* and names the failure it prevents. Tests come before
fixes; the ones worth writing are for the failures that look like working
software — a pad that accepts colour it cannot show, a reply wiped before its
closing brace.
