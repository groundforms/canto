# canto — v0.4 (nb voice layer)

Four free-floating players for Canto Ostinato. Each player's VOICE is now any
nb (note-blok) voice you assign — your Plaits clone, mx.synths, PolyPerc, or
MIDI/crow out to the modular. No shared-engine bleed; each player is its own
voice with its own params.

## Install
1. Copy the `canto` folder into `dust/code/` (data at
   `dust/code/canto/lib/canto_cells.lua`).
2. **nb is required.** The script finds it automatically if either is true:
   - nb is installed as a project at `dust/code/nb`  (it'll use `nb/lib/nb`), OR
   - you vendor it: copy your `nb` folder to `dust/code/canto/lib/nb`
     (so `dust/code/canto/lib/nb/lib/nb.lua` exists).
   If nb isn't found, canto still loads (grid + screen work) but stays silent
   and prints a note to maiden.
3. Reload. In **PARAMS > EDIT** you'll see four voice selectors:
   `P1 Pulse voice` … `P4 Lead voice`. Assign a voice to each (e.g. your
   Plaits clone on P1/P4, soft pads on P2/P3). Each voice's own parameters
   appear in the menu under nb.

## Playing
GRID — 4 players, 2 rows each. Cols 1-13 cell pads; col 14 REC / 15 MUTE /
16 STOP. Tap a pad to launch/queue; long-hold (3s) a pad stops that player.
REC: arm -> records on first pad press -> press to stop+loop -> hold to
overdub -> long-press (stopped) to clear.

NORNS — KEY1 Overview/Detail. ENC1 tempo. Overview: ENC2 focus, ENC3 seed,
KEY2 stop-all, KEY3 re-roll. Detail: ENC2 level, ENC3 **voice select for the
focused player**, KEY2 mute, KEY3 stop.

## Notes
- MollyThePoly is no longer used; you can ignore it for canto now.
- Per-player polyphony caps (Pulse 2, Body 4/4, Lead 3) still apply on top of
  whatever the assigned nb voice does — oldest note is stolen past the cap.
- Per-player level works (velocity scale). Pan + shared FX is still the mixer
  step; with nb you can also just pan/treat each voice in its own nb params or
  outboard.
