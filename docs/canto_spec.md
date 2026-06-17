# `canto` — v0.1 build spec

A Norns + grid performance instrument for Simeon ten Holt's *Canto Ostinato*, built around independent "players" that launch, loop, and phase against each other. Centrepiece for live performance.

Target hardware: **Norns Fates** (run `canto` here), 128 grid, 16n faderbank. A second Norns (Shield) runs washes / field recordings / loops alongside and is out of scope for this script.

---

## 1. Core concept

Canto is written for multiple performers, each holding a part and entering/exiting independently. `canto` mirrors that: **four players**, each with its own bank of cells, its own voice profile, and its own self-contained launch/loop/record rules. Players are **free-floating** — there is no shared global downbeat. Each player quantises its own actions to its own current cell boundary, which is what produces the phasing between parts.

The 116 cells extracted from the score are the raw material. v0.1 maps them to the grid **randomly** (seeded, re-rollable); bespoke per-player curation is a later version.

---

## 2. Cell data

Source: the 116 single-pass cell MIDI files already extracted (`canto_cell_001.mid` … `canto_cell_116.mid`), validated tick-exact against the MusicXML repeat structure.

For the script we do **not** ship 116 MIDI files. We pre-bake them into one data file the script loads at startup.

**Pre-processing step (offline, done once):** parse all 116 cells into a single Lua table (or JSON loaded into Lua) with this shape per cell:

```
cell[i] = {
  id        = i,              -- 1..116
  measures  = "m8-9",         -- for reference / display
  meter     = {10, 16},       -- numerator, denominator
  length_ticks = 2400,        -- cell loop length at 480 PPQN
  length_beats = 5.0,         -- length_ticks / PPQN, for clock scheduling
  notes = {                   -- flattened across all voices, sorted by onset
    { t = 0,    dur = 240, note = 60, vel = 80 },
    { t = 120,  dur = 120, note = 67, vel = 72 },
    ...
  }
}
```

Notes are stored in **beats** (ticks / 480) so scheduling is tempo-independent — the script's clock tempo drives playback, not the original 75 BPM. (75 BPM is the score reference; the performer sets tempo live.)

Polyphony note: the per-voice track identity from the original 11-track MIDI is collapsed in v0.1 (all notes go to the player's single voice profile). We keep the data structure able to carry a `track`/`voice` tag per note so a later version *could* route Canto's internal voices separately — but v0.1 ignores it.

I (Claude) generate this data file from the cells as the first build deliverable.

---

## 3. Grid layout (128, 16×8)

Four players, two rows each:

```
Row 1  Player 1  [ 13 cell pads ............ ][ REC ][ MUTE ][ STOP ]
Row 2  Player 1  [ 13 cell pads ............ ][ REC ][ MUTE ][ STOP ]
Row 3  Player 2  [ 13 cell pads ............ ][ REC ][ MUTE ][ STOP ]
Row 4  Player 2  [ 13 cell pads ............ ][ REC ][ MUTE ][ STOP ]
Row 5  Player 3  [ 13 cell pads ............ ][ REC ][ MUTE ][ STOP ]
Row 6  Player 3  [ 13 cell pads ............ ][ REC ][ MUTE ][ STOP ]
Row 7  Player 4  [ 13 cell pads ............ ][ REC ][ MUTE ][ STOP ]
Row 8  Player 4  [ 13 cell pads ............ ][ REC ][ MUTE ][ STOP ]
```

- Columns 1–13 = cell pads → **26 cells per player** (two rows of 13).
- Columns 14, 15, 16 = the three function keys per row.

**Function-key resolution:** each player has 2 rows = 6 function slots, but only 3 functions (REC / MUTE / STOP). For v0.1, the three functions live on **row 1 of each player**; row 2's three function pads mirror them (same action) so the player's function keys are reachable from either row. (Alternative: leave row-2 function pads dark. Decide at build — mirroring is friendlier.)

Cell-pad LED states:
- **off** — no cell assigned / empty slot
- **dim** — cell assigned, available
- **bright** — cell currently playing
- **pulsing** — cell queued (waiting for current cell boundary to launch)

Two cells are sacrificed overall to fit the function keys (26×4 = 104 pads vs 116 cells). v0.1's random map simply draws 26 cells per player from the 116; not all cells need be reachable in a given mapping. Re-rolling redraws.

---

## 4. Player launch / loop logic (the heart of it)

Each player is an independent state machine. No cross-player synchronisation.

States: `idle` → `playing` (with an optional `queued` cell pending).

- **Press a cell pad while idle** → that cell launches immediately, starts looping.
- **Press a different cell pad while playing** → the new cell is **queued** (pad pulses). It launches at the **end of the current cell's loop** (cell-boundary quantisation, per-player). The current cell plays to its natural end, then the queued cell begins. Clean handover, no chopping.
- **No new cell pressed** → current cell **loops** indefinitely.
- **Press the currently-playing cell again** → no-op (or re-queue itself = no audible change). Keep simple: no-op.
- **Long-hold a cell pad (3s+)** → **stop** that player (voice releases, player returns to idle). This is the "long hold stops it" behaviour.
- **STOP function key** → immediate stop for that player (harder/faster than the long-hold; long-hold is the in-context gesture, STOP is the explicit one).

Polyphony: each player has a **hard voice cap** (see §6). Cells exceeding the cap use per-player voice-stealing (oldest note stolen first).

Quantisation is per-player and fixed to **cell boundary** in v0.1. (v0.x: menu param to switch quant behaviour — see §9.)

---

## 5. Record key logic (per player, one recorder each)

One pattern recorder per player. Captures **cell launches and 16n parameter moves**, in that player's own floating time. Loop boundary is **snapped to the current cell's end** (a recorded loop is always musically closed). Free/take-length recording is a v0.x menu option, not v0.1 — but the boundary rule is built as a single swappable function so the toggle is cheap to add later.

LED states for the REC key:
- **off** — empty (no pattern stored)
- **blinking** — recording (also covers armed-and-waiting; optionally a slower blink for armed vs faster for actively recording)
- **steady full** — pattern stored and playing
- **semi-lit** — pattern stored but stopped

Transitions:

| State | Gesture | Result |
|---|---|---|
| Empty | press | **prime** (arm). Recording begins on the next **cell-pad** press, capturing that launch and everything after. |
| Recording | press | **stop recording + immediately start playback.** Loop end snaps to current cell boundary. |
| Playing | quick press + release | **stop** playback (pattern retained, → semi-lit). |
| Playing | hold (> ~300 ms) | **overdub** while held; new launches/param moves layer onto the loop. |
| Stopped (stored) | long press (3 s+) | **clear** pattern (→ off). |

**Implementation note — the press/hold collision:** "playing + quick press = stop" and "playing + hold = overdub" both begin with press-down. Resolve by: *stop fires on release if released before the hold threshold; overdub engages once the hold threshold (~300 ms, tunable) is crossed.* Consequence: stop is release-triggered (registers a hair later than press). Acceptable for v0.1. **Escape hatch if it feels laggy live:** move overdub onto a held modifier (function key + REC) so stop can fire instantly on press-down. Not built in v0.1, just keep the recorder structured so this is a small change.

Because players float, recorded patterns play back in the player's own time and will phase differently against live players each pass depending on launch moment. This is intended (non-deterministic playback = more alive).

---

## 6. Engine & voice profiles

**Engine: MollyThePoly** for v0.1 (subtractive, capable across the range we need). One engine instance; the four players are four **parameter profiles**, not four engines (Norns runs one engine at a time — this is the key constraint that shaped the design).

Starting profiles (tune by ear):

- **Player 1 — The Pulse** (quintuplet bass, deep plucky): short amp env (fast attack, short decay/release), high filter-env amount, lower register, narrow pulse / detune minimal. Voice cap **2**.
- **Players 2 & 3 — The Body** (chord blocks, foundational harmony): slow attack, long release, detuned oscillators, lower cutoff, gentle filter env. Soft evolving pads. Voice cap **4** each.
- **Player 4 — The Lead** (higher melodies that detach later): brighter, more resonance, long release, more velocity sensitivity / dynamics. Voice cap **3**.

Total simultaneous voice ceiling ≈ **13**, comfortable on Fates with built-in FX. (MollyThePoly is subtractive — true FM pluck for Player 1 is approximate. Bespoke FM-capable engine is the v0.x voice-refinement path once the structure is proven.)

---

## 7. Global / mixer screen (Norns main screen)

The Norns screen is the **mixer/global page**:

- **4 player levels** (per-player output gain)
- **4 player pan positions** — Player 1 hard L (or as desired), Players 2/3 mid L / mid R, Player 4 hard R; global content sits centre. (Exact placement performer-set; defaults: P1 L, P2 midL, P3 midR, P4 R.)
- **Built-in reverb toggle + level** (Norns system reverb — lean on it, lush hall feel via its controls)
- **Built-in compressor toggle** (Norns system compressor)
- Heavy spatial FX (long hall, dotted-⅛ echo) are handled by the **outboard chain**, not the script — deliberate CPU decision for the Fates.

No custom FX bus in v0.1. Panning is a per-voice stereo pan; levels are per-player gain.

Screen also shows minimal status: which cell each player is playing, queued indicators, record states — but the grid is the primary UI; screen is secondary.

---

## 8. 16n faderbank

16 faders → **4 per player**. Suggested mapping per player (tune):

1. Filter cutoff
2. Level (or amp env release)
3. Reverb send
4. One more sound-design param (FM index / detune / filter-env amount — pick per profile)

Fader moves are **captured by the per-player pattern recorder** alongside cell launches, so a recorded take includes its parameter automation. (Standard Norns pattern_time / lattice approach, extended to log CC moves with timestamps.)

---

## 9. Explicitly v0.x / later (NOT in v0.1)

Parked to prevent scope creep — noted so the architecture leaves room:

- Quantisation menu params: per-player or global, switch cell-boundary ↔ bar ↔ free.
- Recorder loop-boundary toggle: cell-snapped ↔ free take-length.
- Bespoke SC engine (real FM for the Pulse; per-voice modes).
- Bespoke per-player cell **curation** (assign cells by character, not random).
- Routing Canto's internal 11 voices to separate outputs/voices.
- Overdub-on-modifier alternative to overdub-on-hold.
- Custom shared FX bus (if moving spatial FX in-box).

---

## 10. Build order

1. **Cell data file** — generate the baked Lua/JSON table from the 116 cells (Claude delivers this first; it's standalone and verifiable).
2. **Engine + four profiles** — load MollyThePoly, define the four parameter profiles, confirm they sound distinct.
3. **Cell playback** — schedule one cell's notes on the clock as a loop at script tempo; verify timing against the data.
4. **Player state machine** — launch / queue-to-cell-boundary / loop / long-hold-stop, per player, independent clocks.
5. **Grid handler** — layout, cell-pad LED states, function keys.
6. **Record key state machine** — the §5 table, with the press/hold resolution and cell-snapped loop boundary.
7. **Global mixer screen** — levels, pans, reverb/comp toggles.
8. **16n routing** — 4 params/player, into the recorders.
9. **Random seeded re-rollable cell map** — key combo to reshuffle; seed displayed/recallable.

Each step is independently testable. Steps 1–4 prove the principle; 5–9 make it playable.

---

## Locked decisions (recap)

- Four free-floating players, no global downbeat — phasing is the point.
- One engine (MollyThePoly v0.1), four parameter profiles.
- Per-player cell-boundary launch quantisation.
- Hard per-player polyphony caps with voice-stealing (~13 total).
- One pattern recorder per player; records launches + 16n moves; **loop end snapped to cell boundary**.
- Record key: prime → record-on-first-cell → press-to-stop-and-play → hold-to-overdub → long-press-to-clear.
- Random seeded re-rollable cell→pad mapping.
- Built-in reverb + comp; panning + player levels on the global screen; spatial FX outboard.
- 16n: 4 params/player, captured by recorders.
- Runs on the Fates.
- Script name: `canto`.
