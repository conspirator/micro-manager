#!/usr/bin/env bash
# Re-verify the five Raycast window-management chords the radial menu presses.
#
# Run this when a slice stops moving windows, or after a Raycast update. It posts
# each chord exactly as `WindowLayout` does and reads the frontmost window's frame
# back, so a chord Raycast ignores shows up as a frame that did not change.
#
# It moves the frontmost window five times. Put a scratch window in front and
# leave the keyboard alone while it runs; it takes about 15 seconds.
#
# Expected on the 2560-wide display this was measured on:
#
#   left half        0, 31, 1280, 1409
#   right half    1280, 31, 1280, 1409
#   first two thirds 0, 31, 1706, 1409
#   last two thirds 854, 31, 1706, 1409
#   almost maximize 128, 101, 2304, 1268
#
# What matters is not the numbers but that the frame changed at all: `reset` below
# is 420, 260, 900, 700, and a frame still reading that means the chord was
# discarded. The usual cause is a missing `.maskSecondaryFn` — Raycast matches the
# flags a real press carries, and every key here is a function key. See AGENTS.md.
#
# Measure with System Events, not `kAXFocusedWindowAttribute`: AX handed back
# another window's frame and reported no movement while the window on screen had
# moved, which made the first attempt at this lie twice.

set -uo pipefail

read_frame() {
  osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to get {position of front window, size of front window}' 2>/dev/null
}

reset_frame() {
  osascript -e 'tell application "System Events" to tell (first process whose frontmost is true)
    set position of front window to {420, 260}
    set size of front window to {900, 700}
  end tell' 2>/dev/null
  sleep 0.6
}

post() { # $1 = key code
  swift -e "
import CoreGraphics
let s = CGEventSource(stateID: .hidSystemState)
let d = CGEvent(keyboardEventSource: s, virtualKey: $1, keyDown: true)!
let u = CGEvent(keyboardEventSource: s, virtualKey: $1, keyDown: false)!
d.flags = [.maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
u.flags = []
d.post(tap: .cghidEventTap); usleep(40_000); u.post(tap: .cghidEventTap)
"
}

run() { # $1 = label, $2 = key code
  reset_frame
  post "$2"
  sleep 1
  local frame
  frame="$(read_frame)"
  if [ "$frame" = "420, 260, 900, 700" ]; then
    echo "IGNORED  $1 -> $frame"
  else
    echo "moved    $1 -> $frame"
  fi
}

echo "reset position is 420, 260, 900, 700 - a frame still reading that was discarded"
run "W  left half        (left  0x7B)" 0x7B
run "E  right half       (right 0x7C)" 0x7C
run "NW first two thirds (up    0x7E)" 0x7E
run "NE last two thirds  (down  0x7D)" 0x7D
run "N  almost maximize  (pgdn  0x79)" 0x79
