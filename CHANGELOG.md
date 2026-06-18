# canto — changelog

## v0.4.1
- Robust nb discovery (searches dust/code/nb and vendored lib/nb, several
  layouts); nb setup wrapped so a bad/missing nb can't brick init.
- Prints where nb loaded from (or why not) to maiden, and shows
  "nb not loaded" on screen so a silent run is never a mystery.

## v0.4
- Voice layer moved to **nb (note-blok)**. Each of the four players is an nb
  slot; assign any installed nb voice (Plaits clone, mx.synths, PolyPerc,
  MIDI/crow to the modular) per player in PARAMS > EDIT. No shared-engine bleed.
- MollyThePoly removed. Detail page ENC3 now selects the focused player's voice.
- Per-player polyphony caps + oldest-note stealing retained on top of nb.
- Repo restructured flat for GitHub + maiden `;install`.

## v0.3.1
- Grid diagnostics (prints grid name/size on load) + pcall-guarded draw loop.

## v0.3
- Four free-floating players, grid handler, per-player record keys, paged
  screen (Overview + grid-focused Detail), seeded re-rollable cell map.

## v0.2
- Guarded engine calls (unknown commands skip + log).

## v0.1
- Cell extraction (116 cells), baked data, single-cell looper.
