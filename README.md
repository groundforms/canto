# canto — v0.1 script (build steps 2-3)

Engine + four voice profiles + single-cell looper. This is the foundation
the four-player grid instrument is built on; here you drive one "player"
from the keys to confirm the engine, the profiles, and cell timing/looping.

## Install
1. Copy this whole `canto` folder into `dust/code/` on the Norns
   (so the data file lands at `dust/code/canto/lib/canto_cells.lua`).
2. Requires the **MollyThePoly** engine (install via maiden if not present:
   it ships with the `molly_the_poly` script — having that script installed
   makes the engine available).
3. SYSTEM > RESET, then load `canto`.

## Controls
- ENC1 — tempo (clock bpm), defaults to 75
- ENC2 — select cell (1..116)
- ENC3 — select profile (Pulse / Body L / Body R / Lead)
- KEY3 — start / restart the selected cell looping
- KEY2 — stop

## What success looks like
- Picking a cell and hitting KEY3 loops it cleanly at the set tempo; the phase
  bar fills once per loop and resets exactly at the cell boundary.
- Changing tempo (ENC1) speeds/slows the loop proportionally.
- Switching profile (ENC3) + KEY3 changes the timbre audibly:
  Pulse = short plucky; Body = slow soft pad; Lead = brighter, long release.
- maiden prints the cell's length in beats and seconds on each start, so you
  can check the loop period against the clock.

## Notes / caveats
- Profile param NAMES target MollyThePoly's standard engine commands. If a
  param seems to do nothing, check it against your installed MollyThePoly
  version's command list — the engine silently ignores unknown commands.
- MollyThePoly params are GLOBAL. For one player at a time this is fine. When
  we add four simultaneous players, continuous params (e.g. live filter sweeps)
  will bleed across players on a single engine instance — that shared-param
  limit is the main reason the bespoke per-voice engine is the v0.x voice step.
  Envelope/wave/level/detune latch per voice at note-on, so the four profiles
  will still read as distinct even when overlapping.
- Polyphony caps (per the spec) are not enforced yet — dense cells lean on
  MollyThePoly's own voice limit. Caps arrive with the multi-player build.

## Next build steps (from the spec)
4. Player state machine (queue-to-cell-boundary launch, loop, long-hold stop)
5. Grid handler (4 players x 2 rows, cell pads + REC/MUTE/STOP)
6. Record key state machine
7. Global mixer screen  8. 16n routing  9. Random seeded cell map
