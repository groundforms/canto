# canto

A Norns + grid performance instrument for Simeon ten Holt's *Canto Ostinato*.
Four independent, free-floating "players" launch and loop cells extracted from
the score; they share the clock's pulse but not a downbeat, so they phase. Each
player's voice is provided by **nb**, so you assign any installed voice per
player (a Plaits clone, mx.synths, PolyPerc, MIDI/crow out to the modular, …).

Requires a 128 grid. The 116 cells are pre-baked into `lib/canto_cells.lua`.

## Install (maiden)

    ;install https://github.com/USERNAME/canto

This clones the repo to `dust/code/canto` and Norns loads `canto.lua`.

### Updating (no delete needed)
- maiden: open the project and use its update/pull action, **or**
- ssh: `ssh we@norns.local` then `cd ~/dust/code/canto && git pull`

Then reload the script. Your params/psets in `dust/data/canto/` survive updates.
Keep edits one-way (commit from your machine, Norns only pulls) to avoid merge
conflicts on `git pull`.

## nb (required)

The script finds nb automatically if either is true:
- nb is installed as its own project at `dust/code/nb`  → uses `nb/lib/nb`, or
- nb is vendored into this repo at `lib/nb`            → uses `lib/nb/lib/nb`

To vendor nb as a **git submodule** (so it updates independently and `;install`
pulls it too), from the repo root:

    git submodule add <NB_REPO_URL> lib/nb
    git commit -m "add nb as submodule"

Use the same nb repo you installed via maiden as `<NB_REPO_URL>`. When others
(or you) clone, fetch submodules with `git clone --recurse-submodules …` or
`git submodule update --init`. maiden's `;install` handles submodules.

If nb isn't found, canto still loads (grid + screen work) but stays silent and
says so in maiden.

## Playing

Assign voices in **PARAMS > EDIT** (`P1 Pulse voice` … `P4 Lead voice`).

GRID — 4 players, 2 rows each. Cols 1-13 = cell pads (26/player). Col 14 REC /
15 MUTE / 16 STOP (mirrored on both of a player's rows). Tap a pad to launch
(immediate if idle) or queue (launches at the current cell's boundary); long-
hold a pad (3s) stops that player. Cell LEDs: dim available / bright playing /
pulse queued.

REC (per player): press to arm → recording starts on your next pad press →
press to stop + loop → hold to overdub → long-press (when stopped) to clear.
Loop end snaps to the current cell boundary.

NORNS — KEY1 toggles Overview / Player detail (detail follows the grid). ENC1
tempo. Overview: ENC2 focus, ENC3 seed, KEY2 stop-all, KEY3 re-roll the cell
map. Detail: ENC2 level, ENC3 voice, KEY2 mute, KEY3 stop.

## Notes
- Per-player polyphony caps (Pulse 2, Body 4/4, Lead 3) sit on top of the
  assigned voice — oldest note stolen past the cap.
- Per-player level = velocity scale. Pan + shared FX is a later mixer step.
- The 116 cell MIDIs (for Ableton) and a JSON copy of the data are not in this
  repo — they're source material kept alongside the project.


## Voice constraint to know about
Some nb voice packs back onto a single shared engine instance — notably
**mxsynths** and other sample-based packs load *one instrument at a time*. If
two players both select an mxsynths voice, they share that one loaded sound;
you can't have two different mxsynths patches at once. For genuinely different
timbres per player, use voices that instantiate independently (a Plaits clone,
doubledecker, per-voice engines). Same pack on two players = same sound.

## Roadmap
7. Global mixer (true per-player level/pan, shared reverb/echo)
8. 16n faderbank → 4 params/player, captured by the recorders
