# Micro Manager

A macOS menu-bar app that lights each running [Herdr](https://herdr.dev) agent
on its own key of a Work Louder
**[Creator Micro 2](https://worklouder.cc/creator-micro-2)**, and jumps to that agent
when you press the key.

It is the bridge itself — no Node, no daemon, nothing to install on the Herdr
side. It reads Herdr's socket directly and drives the pad over raw HID.

**[Download the latest release](https://github.com/schacon/micro-manager/releases/latest/download/MicroManager.zip)**
· [website](https://schacon.github.io/micro-manager/)
· [hacking guide](docs/hacking.md)

---

## Install

Download, unzip, drag `MicroManager.app` to Applications, and launch it. macOS
will ask for **Input Monitoring** — grant it, then toggle the manager off and on
from the menu-bar panel so it reconnects with the permission.

Or build it yourself:

```bash
./scripts/bundle.sh --install     # build, sign, install to /Applications, launch
```

You will also need a Creator Micro 2 and a running Herdr server with agents in
it. Quit Work Louder's Input app and the Codex desktop app while you use this —
all three drive the same lighting and will overwrite each other.

## What the pad does

**The icon** shows state at a glance: dimmed when off, a coloured dot when
running — blue all idle, amber something working, red something needs you —
and a badge when the pad is missing or permission is denied.

**The top six keys** are one agent each, in the order Herdr's own panel lists
them. Colours are red (blocked, breathing), amber (working), green (done —
finished but not yet looked at) and blue (idle — finished and seen). Herdr
distinguishes done from idle by whether you have focused the pane yet, so green
means something is waiting to be read and blue means quiet. The **underglow**
carries the worst state across all agents, so "does anything need me?" is
readable from across the room.

Pressing an agent key focuses that agent in Herdr **and brings the terminal
forward** — Herdr selects the pane but leaves the window where it was, so an
agent key pressed from a browser used to move a cursor you could not see. Set
`WL_TERMINAL_BUNDLE_ID` if your panes do not live in iTerm2.

**Row 3** is actions:

| key | what it does |
|---|---|
| open | opens the focused agent's directory in Finder, Zed or Tower |
| close tab | closes the focused Herdr tab, on two presses |
| tabs | cycles the tabs of the focused Herdr window |
| new tab | opens a Herdr tab beside the focused agent |

**Row 4** is Esc — it taps Esc wherever the focus is — the voice key, which taps
right control to start and stop [Monologue](https://www.monologue.to), and Enter.

The new-tab key opens a tab beside the focused agent, in the directory that
agent is working in, focuses it, and brings the terminal forward. Esc and Enter
go to whatever holds focus and raise nothing: a keystroke that moved a window
first would land somewhere you did not mean.

The close-tab key is the only thing on the pad that destroys work, so it takes
two presses. The first arms it: the key and the **whole underglow** go solid red,
and nothing is sent to Herdr. A second press within five seconds closes the
focused tab and everything running in it. Esc cancels without posting an Esc
anywhere, any other key cancels and still does its own job, and an arm nobody
confirms lets go after five seconds — the ring is how you read whether an agent
needs you, so it is only borrowed. Armed red is solid where blocked-red breathes.

The voice key sends **two** right-control taps to start a take and **one** to
stop it, because that is how Monologue's hotkey works — two taps inside a second
lock recording hands-free, one more tap ends it, and a lone tap from idle is
discarded silently. The key breathes red while a take is open. Stopping a take
from the keyboard instead makes that drift, and the next press puts it right.
Both Esc/Enter and the voice key need **Accessibility** on top of Input
Monitoring, since they synthesise key events.

**The dial** picks the model on a pi pane and tunes reasoning effort on Claude
and Codex. **The joystick** switches model on Claude and Codex: it puts the model
list on screen, north and south move, east confirms, west cancels.

### The dial, on a pi pane

Turning it puts pi's own model list on screen and moves a highlight. Nothing is
sent while you turn: the panel is a proposal. **Pressing the dial in** commits,
by sending the pane as many `ctrl+p` chords as it takes to walk from the model pi
reports to the one you chose. Esc dismisses, so does a click outside, losing
focus, or twenty seconds of nothing. Pressing the dial with no panel up opens it.

The list is `enabledModels` from `~/.pi/agent/settings.json`, which is the same
list, in the same order, that ctrl+p walks inside pi. There is deliberately no
second copy in this app's config: a copy is a copy that goes stale.

What it does **not** do is type into pi's prompt. `/model <provider/id>` would
switch a session in one shot, but only when the editor is empty — with a
half-written prompt sitting there, the command is appended to your draft and
submitted as a question. A chord is not text, so `ctrl+p` is safe with a draft.
Writing `settings.json` is no use either: pi reads `defaultModel` once, at
startup, and nothing watches the file, so a write would change the next session
and leave the pane in front of you alone.

Each chord is confirmed before the next is sent, by reading the pane back and
waiting for the footer to name a different model. Pi's own `cycleModel` awaits an
auth check per model and nothing serialises it, so a burst of chords can collapse
into one change and land a model short. If a press moves nothing, or the walk
ends somewhere else, the reason goes to the menu panel rather than passing as
success.

A pane that pi did not start, fewer than two enabled models, a glob in the list
(which pi expands and the pad cannot count through), or two enabled models
sharing an id: each is refused before the panel opens, silently on screen and
with the reason in the menu panel.

### The open key

It puts up a horizontal strip of app icons — Finder, Zed,
[Tower](https://www.git-tower.com) — in the manner of the macOS app switcher.
Left and Right move the selection and wrap at the ends, Enter opens the focused
agent's working directory in the selected app, Esc dismisses, and pressing the
key again puts the strip away. Clicking an icon opens it. The line under the
icons names the app and the directory, so you can see what Enter will do before
you commit to it.

An app that is not installed is left out of the strip rather than shown and
refusing. The selection always starts on Finder, so "open, right, Enter" is a
gesture rather than a decision.

This is the one window in the app that **takes the keyboard**, because it has to
read the arrow keys. It hands focus back to the app you came from when you
dismiss it without opening anything. If Herdr has nothing focused, the key does
nothing visible; the reason waits in the menu panel.

Tower is here rather than on a key of its own: key 7 closes a tab now, and this
strip is the deliberate choice among three apps.

The GitButler stack this key used to float is still in the app, still building
and still tested. So is the Tower launcher that used to own key 7. Both are only
unwired from the pad.

Apps are opened through `NSWorkspace`, not by running `open`, `zed` or
`gittower`. An app launched by launchd inherits `/usr/bin:/bin:/usr/sbin:/sbin`,
so the binaries your terminal finds instantly are invisible here. The dormant
stack code carries a whole search to work around that for `but` — Homebrew and
Cargo locations first, then your login shell, with `WL_BUT_PATH` to skip it all
— and `NSWorkspace` needs none of it.

## The panel

Click the menu-bar icon. It draws the pad in its real shape with every key
showing its live colour, then one row per agent. Click a key or a row to jump to
that agent. It also carries the on/off switch, an "Open at login" toggle, a
warning when another app is fighting for the device, and the **Inspector**
button.

**Off** clears the lights and stops driving, but deliberately leaves the device
keymap alone: rebinding is a flash write, and the keys light instantly on the
way back in if the bindings are still there.

## The Inspector

The debug UI ships inside the app — the **Inspector** button in the panel opens
it. It logs every message in both directions (`TX`, `RX`, `NOTIFY`, `DEVICE`),
decodes the device's abbreviated notifications, and drives the lighting by hand:
per-key colours and effects, the two zones, a key walk, and a raw JSON-RPC
console with presets.

It lives at `MicroManager.app/Contents/Library/Inspector.app`, signed by the
same identity as its host, so it is one download and one trust decision. During
development there is no surrounding bundle, so run it directly:

```bash
swift run WLInspector
```

Run that **from your terminal**, not from Finder: macOS attributes Input
Monitoring to the responsible process, so a terminal that already has the grant
passes it on.

## No pad to hand

Tick **Emulate the pad** in the panel and a window opens with a virtual Creator
Micro 2 in it. The bridge drives its lights exactly as it drives the hardware,
and clicking a key — or the dial, or the joystick — sends the same
`v.oai.hid` report back, so the whole loop works with nothing plugged in.

```bash
WL_EMULATE=1 swift run WLMicroManager    # start emulated, no clicking required
```

It is a stand-in for the firmware rather than a picture of one, and it
reproduces the firmware's more awkward habits deliberately, because those are
the ones that cost time on real hardware:

- it answers `{"ok":1}` to any lighting payload, right or wrong;
- it boots on the **stock F-key keymap**, so the app has to bind the keys
  before anything can light — and a key that is not bound to `KV_OAI_AG*`
  accepts its colour in silence and stays dark;
- an unbound key reports nothing when pressed, because on the pad it would be
  sending a keystroke instead.

The window also shows the RPC traffic, and **Reset** puts a factory pad back.

The emulator lives inside the app, so it stands in for the device for Micro
Manager only — the Inspector is a separate process and still needs hardware.

## Configuration

Everything works without a config file. To replace what the four keys below the
agent block do, or to change what the dial and joystick offer, drop a
`config.json` into `~/.config/micromanager/`:

```json
{
  "keys": {
    "9":  "Open PRs for all active GitButler branches",
    "12": "Run but pull"
  },
  "claude": { "models": ["fable", "opus"], "efforts": ["low", "high"] },
  "codex":  { "models": ["gpt-5.6-sol", "gpt-5.6-codex"] }
}
```

A bound string is injected into the focused agent's prompt, unsubmitted — you
still read it and press enter — **instead of** what that key normally does. Keys
9 to 12 are the only ones that listen, since losing the key that focuses an
agent to a stray config line would be a poor trade. There are no defaults: every
key has a role, and an empty string returns a key to it.

`codex.models` is your copy of what Codex's own `/model` menu offers, in its
order — the joystick steers that menu rather than owning it, so there is nothing
to read it from. Pi needs no entry here: its list is read from pi's own
`settings.json`.

| variable | what it overrides |
|---|---|
| `WL_TERMINAL_BUNDLE_ID` | the terminal to raise (default iTerm2) |
| `WL_BUT_PATH` | the GitButler binary, skipping the search |
| `HERDR_SOCKET_PATH` | the Herdr socket |
| `WL_SIGN_IDENTITY` | the signing identity `bundle.sh` uses |

## Why it must be bundled and signed

`swift run` works for development because it inherits your terminal's Input
Monitoring grant. A background app needs its own, and macOS keys that grant to
the **code signature** — so an ad-hoc signature, whose hash changes on every
build, forces you to re-grant after every rebuild. `bundle.sh` prefers a real
Apple Development or Developer ID identity from your keychain, which gives a
stable designated requirement and makes the grant stick. It also sets
`LSUIElement` so there is no Dock icon, and gives `SMAppService` a bundle it
will actually register as a login item.

Every push to main republishes the **`latest`** release, so the download link
above always points at the current build; tagging `v*` cuts a permanent
versioned release alongside it. Both go through
[the release workflow](.github/workflows/release.yml).

That workflow signs with a Developer ID and notarizes when the repository has
the secrets for it — the file lists them — and falls back to an ad-hoc
signature when it does not, rather than failing. An ad-hoc build works, but
macOS stops it until you right-click → Open, and because the grant is keyed to
the signature and an ad-hoc one changes every build, Input Monitoring has to be
granted again after each update. The release notes say which kind you are
downloading.

## Only one bridge at a time

Work Louder's Input app and the Codex desktop app drive this same pad. Running
two at once means they overwrite each other. The panel detects this — the device
is opened shared, so we receive other clients' replies, and a response id we
never issued is a reliable tell.

## Development

```bash
swift build            # both apps and the shared library
swift test             # live tests skip themselves without hardware
swift run WLInspector  # the debug UI
./scripts/bundle.sh    # assemble build/MicroManager.app, unsigned install
```

| | |
|---|---|
| `Sources/WLKit` | device transport, vendor protocol, Herdr client, bridge engine |
| `Sources/WLMicroManager` | the menu-bar app and its panels |
| `Sources/WLInspector` | the debug UI |
| `docs/hacking.md` | how the pad protocol works, and how to drive it yourself |
| `docs/index.html` | the website, served by GitHub Pages from `docs/` |

The device protocol — raw-HID JSON-RPC, per-key colour, key and joystick events,
and the keymap binding that makes per-key lighting possible at all — is written
up in full in **[docs/hacking.md](docs/hacking.md)**.

---

An independent interoperability tool for hardware I own. Not affiliated with
Work Louder.
