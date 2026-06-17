-- canto
-- v0.3.1 — four players + grid + record keys (grid diagnostics)
--
-- Performance instrument for Canto Ostinato.
-- Four independent, free-floating PLAYERS, each:
--   * a bank of 26 cells on two grid rows (randomly mapped, re-rollable)
--   * its own voice profile, its own loop, its own cell-boundary launch quant
--   * one pattern recorder (records cell launches; 16n moves come with step 8)
-- Players share the clock's PULSE but not a downbeat, so they phase.
--
-- GRID (128, 16x8)
--   rows are paired per player (P1=rows1-2 ... P4=rows7-8)
--   cols 1-13  : 26 cell pads per player (row1 = slots 1-13, row2 = 14-26)
--   col 14     : REC      col 15 : MUTE      col 16 : STOP
--   (function keys act per-player; both of a player's rows mirror them)
--   cell LEDs  : off=empty  dim=available  bright=playing  pulse=queued
--   REC LED    : off=empty  blink=armed/recording  full=playing  dim=stored
--
-- NORNS
--   KEY1 toggle Overview <-> Player detail (detail follows grid focus)
--   ENC1 tempo
--   Overview : ENC2 focus player  ENC3 cell-map seed   KEY2 stop all  KEY3 re-roll map
--   Detail   : ENC2 player level  ENC3 player profile   KEY2 mute     KEY3 stop player
--
-- install: copy this folder to dust/code/canto/  (data at lib/canto_cells.lua)

engine.name = "MollyThePoly"

local music = require "musicutil"
local cells = include("canto/lib/canto_cells")  -- table indexed [1..N]

local NUM_PLAYERS      = 4
local PADS_PER_ROW     = 13
local CELLS_PER_PLAYER = PADS_PER_ROW * 2  -- 26
local HOLD_STOP_S      = 3.0    -- long-hold on a cell stops that player
local REC_CLEAR_S      = 3.0    -- long-press REC (when stopped) clears
local OVERDUB_S        = 0.3    -- hold REC (when playing) past this = overdub

local g = grid.connect()
local GRID_DEBUG = true  -- prints grid key events + draw errors to maiden

-- ----------------------------------------------------------------------------
-- state
-- ----------------------------------------------------------------------------
local n_cells = 0
for _ in pairs(cells) do n_cells = n_cells + 1 end

local players = {}
local focused_player = 1
local page = "overview"          -- "overview" | "detail"
local global_uid = 0             -- engine voice id counter
local last_profile_applied = nil -- which profile's params are live on the engine
local redraw_clock = nil

local hold = {}     -- grid cell hold timers, keyed "x_y"
local recpress = {} -- REC key press info, keyed by player index

-- ----------------------------------------------------------------------------
-- voice profiles (one MollyThePoly, four parameter sets)
-- Molly's params are global; envelope/wave/level latch per voice at note-on,
-- so applying a player's profile just before its note-ons keeps the four
-- timbres distinct. Continuous per-player control (16n sweeps) is the thing
-- that wants the bespoke engine — that's the v0.x voice step.
-- ----------------------------------------------------------------------------
local profiles = {
  { name = "Pulse", cap = 2, params = {
      oscWaveShape=2, mainOscLevel=0.9, subOscLevel=0.7, subOscDetune=0.1, noiseLevel=0.0,
      hpFilterCutoff=20, lpFilterCutoff=500, lpFilterResonance=0.25,
      lpFilterCutoffEnvSelect=0, lpFilterCutoffModEnv=0.7,
      ampAttack=0.004, ampDecay=0.18, ampSustain=0.0, ampRelease=0.14,
      envAttack=0.004, envDecay=0.16, envSustain=0.0, envRelease=0.12, chorusMix=0.0 } },
  { name = "Body L", cap = 4, params = {
      oscWaveShape=1, mainOscLevel=0.8, subOscLevel=0.5, subOscDetune=0.18, noiseLevel=0.02,
      hpFilterCutoff=20, lpFilterCutoff=1400, lpFilterResonance=0.12,
      lpFilterCutoffEnvSelect=0, lpFilterCutoffModEnv=0.15,
      ampAttack=0.7, ampDecay=1.2, ampSustain=0.85, ampRelease=2.6,
      envAttack=0.6, envDecay=1.0, envSustain=0.7, envRelease=2.0, chorusMix=0.45 } },
  { name = "Body R", cap = 4, params = {
      oscWaveShape=1, mainOscLevel=0.8, subOscLevel=0.5, subOscDetune=0.12, noiseLevel=0.02,
      hpFilterCutoff=20, lpFilterCutoff=1700, lpFilterResonance=0.12,
      lpFilterCutoffEnvSelect=0, lpFilterCutoffModEnv=0.15,
      ampAttack=0.8, ampDecay=1.3, ampSustain=0.85, ampRelease=2.8,
      envAttack=0.7, envDecay=1.1, envSustain=0.7, envRelease=2.2, chorusMix=0.5 } },
  { name = "Lead", cap = 3, params = {
      oscWaveShape=1, mainOscLevel=0.9, subOscLevel=0.2, subOscDetune=0.08, noiseLevel=0.0,
      hpFilterCutoff=40, lpFilterCutoff=3500, lpFilterResonance=0.30,
      lpFilterCutoffEnvSelect=0, lpFilterCutoffModEnv=0.30,
      ampAttack=0.02, ampDecay=0.5, ampSustain=0.7, ampRelease=2.2,
      envAttack=0.02, envDecay=0.5, envSustain=0.6, envRelease=1.8, chorusMix=0.2 } },
}

-- ----------------------------------------------------------------------------
-- engine helpers (guarded — unknown commands skip + log once)
-- ----------------------------------------------------------------------------
local reported = {}
local function eng(cmd, ...)
  local f = engine[cmd]
  if type(f) == "function" then f(...) return true end
  if not reported[cmd] then
    reported[cmd] = true
    print("canto: MollyThePoly has no command '" .. cmd .. "' — skipped")
  end
  return false
end

local function apply_profile(p)
  for k, v in pairs(profiles[p].params) do eng(k, v) end
end

-- ensure the engine's global params match player pi's profile before a note-on
local function ensure_profile(pi)
  local prof = players[pi].profile
  if last_profile_applied ~= prof then
    apply_profile(prof)
    last_profile_applied = prof
  end
end

-- ----------------------------------------------------------------------------
-- per-player voice allocation (hard cap + oldest-first stealing)
-- ----------------------------------------------------------------------------
local function voice_on(pi, freq, vel)
  local pl = players[pi]
  local cap = profiles[pl.profile].cap
  while #pl.voices >= cap do
    local old = table.remove(pl.voices, 1)
    if old then eng("noteOff", old) else break end
  end
  ensure_profile(pi)
  global_uid = global_uid + 1
  eng("noteOn", global_uid, freq, vel)
  pl.voices[#pl.voices + 1] = global_uid
  return global_uid
end

local function voice_off(pi, id)
  if not id then return end
  eng("noteOff", id)
  local pl = players[pi]
  for i = #pl.voices, 1, -1 do
    if pl.voices[i] == id then table.remove(pl.voices, i) break end
  end
end

local function all_voices_off(pi)
  local pl = players[pi]
  for i = #pl.voices, 1, -1 do eng("noteOff", pl.voices[i]); pl.voices[i] = nil end
end

-- ----------------------------------------------------------------------------
-- cell event building
-- ----------------------------------------------------------------------------
local function build_events(cell)
  local ev = {}
  for i, n in ipairs(cell.notes) do
    ev[#ev + 1] = { time = n.t, kind = "on", idx = i, note = n.note, vel = n.vel }
    local offt = n.t + n.dur
    if offt > cell.length_beats then offt = cell.length_beats end
    ev[#ev + 1] = { time = offt, kind = "off", idx = i }
  end
  table.sort(ev, function(a, b)
    if a.time == b.time then return a.kind < b.kind end
    return a.time < b.time
  end)
  return ev
end

local function sleep_beats(b)
  if b > 0 then clock.sleep(b * clock.get_beat_sec()) end
end

-- ----------------------------------------------------------------------------
-- player loop
-- ----------------------------------------------------------------------------
local function player_loop(pi)
  local pl = players[pi]
  while true do
    if pl.queued then
      pl.current      = pl.queued
      pl.current_slot = pl.queued_slot
      pl.queued       = nil
      pl.queued_slot  = nil
    end
    if not pl.current then pl.playing = false return end

    local cell = cells[pl.current]
    local ev = build_events(cell)
    pl.loop_start_beat = clock.get_beats()
    local last = 0
    local note_uid = {}
    for _, e in ipairs(ev) do
      sleep_beats(e.time - last)
      last = e.time
      if e.kind == "on" then
        if not pl.muted then
          note_uid[e.idx] = voice_on(pi, music.note_num_to_freq(e.note),
            (e.vel / 127) * pl.level)
        end
      else
        voice_off(pi, note_uid[e.idx]); note_uid[e.idx] = nil
      end
    end
    sleep_beats(cell.length_beats - last)
  end
end

-- launch a pad's cell on a player. from_rec = called by the recorder
local function player_launch(pi, slot, from_rec)
  local pl = players[pi]
  local cell_id = pl.cellmap[slot]
  if not cell_id then return end
  if not pl.playing then
    pl.current = cell_id
    pl.current_slot = slot
    pl.queued = nil
    pl.queued_slot = nil
    pl.playing = true
    pl.clock_id = clock.run(player_loop, pi)
  else
    if cell_id == pl.current and not pl.queued then return end
    pl.queued = cell_id
    pl.queued_slot = slot
  end
end

local function player_stop(pi)
  local pl = players[pi]
  if pl.clock_id then clock.cancel(pl.clock_id); pl.clock_id = nil end
  pl.playing = false
  pl.current = nil; pl.current_slot = nil
  pl.queued = nil;  pl.queued_slot = nil
  all_voices_off(pi)
end

local function toggle_mute(pi)
  local pl = players[pi]
  pl.muted = not pl.muted
  if pl.muted then all_voices_off(pi) end
end

-- ----------------------------------------------------------------------------
-- recorder (one per player) — records cell launches in the player's own time,
-- loop end snapped to the current cell's boundary.
-- ----------------------------------------------------------------------------
local function rec_record_launch(pi, slot)
  local r = players[pi].rec
  if r.state == "armed" then
    r.state = "recording"
    r.rec_start_beat = clock.get_beats()
    r.events = {}
  end
  if r.state == "recording" then
    r.events[#r.events + 1] = { beat = clock.get_beats() - r.rec_start_beat, slot = slot }
  elseif r.state == "playing" and r.overdubbing then
    local pos = (clock.get_beats() - (r.play_start_beat or clock.get_beats()))
                  % (r.length_beats or 1)
    r.events[#r.events + 1] = { beat = pos, slot = slot }
    r.need_sort = true
  end
end

local function rec_start_playback(pi)
  local r = players[pi].rec
  r.state = "playing"
  r.play_clock = clock.run(function()
    while true do
      r.play_start_beat = clock.get_beats()
      local last = 0
      for _, e in ipairs(r.events) do
        sleep_beats(e.beat - last); last = e.beat
        player_launch(pi, e.slot, true)
      end
      sleep_beats((r.length_beats or 0) - last)
    end
  end)
end

local function rec_stop_playback(pi)
  local r = players[pi].rec
  if r.play_clock then clock.cancel(r.play_clock); r.play_clock = nil end
  r.state = "stopped"
end

-- finish recording at the next current-cell boundary, then play
local function rec_stop_and_play(pi)
  local pl = players[pi]
  local r = pl.rec
  r.closing = clock.run(function()
    if pl.playing and pl.current then
      local cell = cells[pl.current]
      local pos = clock.get_beats() - pl.loop_start_beat
      local rem = cell.length_beats - (pos % cell.length_beats)
      sleep_beats(rem)
    end
    r.length_beats = clock.get_beats() - (r.rec_start_beat or clock.get_beats())
    if r.length_beats <= 0 then
      r.length_beats = (pl.current and cells[pl.current].length_beats) or 2.5
    end
    table.sort(r.events, function(a, b) return a.beat < b.beat end)
    rec_start_playback(pi)
  end)
end

local function rec_overdub_start(pi) players[pi].rec.overdubbing = true end
local function rec_overdub_stop(pi)
  local r = players[pi].rec
  r.overdubbing = false
  if r.need_sort then
    table.sort(r.events, function(a, b) return a.beat < b.beat end)
    r.need_sort = false
  end
end

local function rec_clear(pi)
  local r = players[pi].rec
  if r.play_clock then clock.cancel(r.play_clock); r.play_clock = nil end
  r.state = "empty"; r.events = {}; r.length_beats = nil; r.overdubbing = false
end

-- ----------------------------------------------------------------------------
-- cell-map (seeded, re-rollable)
-- ----------------------------------------------------------------------------
local function build_cellmap(seed)
  math.randomseed(seed)
  local order = {}
  for i = 1, n_cells do order[i] = i end
  for i = n_cells, 2, -1 do
    local j = math.random(i)
    order[i], order[j] = order[j], order[i]
  end
  local idx = 1
  for pi = 1, NUM_PLAYERS do
    players[pi].cellmap = {}
    for s = 1, CELLS_PER_PLAYER do
      players[pi].cellmap[s] = order[idx]
      idx = idx + 1
      if idx > n_cells then idx = 1 end  -- wrap if fewer cells than slots
    end
  end
end

-- ----------------------------------------------------------------------------
-- grid
-- ----------------------------------------------------------------------------
local function slot_to_xy(pi, slot)
  local row = (slot > PADS_PER_ROW) and 2 or 1
  local x = ((slot - 1) % PADS_PER_ROW) + 1
  local y = (pi - 1) * 2 + row
  return x, y
end

local function handle_cell_key(pi, slot, x, y, z)
  focused_player = pi
  local k = x .. "_" .. y
  if z == 1 then
    local h = { longfired = false }
    hold[k] = h
    h.timer = clock.run(function()
      clock.sleep(HOLD_STOP_S)
      if hold[k] == h then
        h.longfired = true
        player_stop(pi)
      end
    end)
  else
    local h = hold[k]; hold[k] = nil
    if h then
      if h.timer then clock.cancel(h.timer) end
      if not h.longfired then
        rec_record_launch(pi, slot)
        player_launch(pi, slot, false)
      end
    end
  end
end

local function handle_rec_key(pi, z)
  focused_player = pi
  local r = players[pi].rec
  if z == 1 then
    local h = { longfired = false, downbeat = clock.get_beats(), overdubbing = false }
    recpress[pi] = h
    h.clear_timer = clock.run(function()
      clock.sleep(REC_CLEAR_S)
      if recpress[pi] == h and r.state == "stopped" then
        h.longfired = true
        rec_clear(pi)
      end
    end)
    h.od_timer = clock.run(function()
      clock.sleep(OVERDUB_S)
      if recpress[pi] == h and r.state == "playing" then
        h.overdubbing = true
        rec_overdub_start(pi)
      end
    end)
  else
    local h = recpress[pi]; recpress[pi] = nil
    if not h then return end
    if h.clear_timer then clock.cancel(h.clear_timer) end
    if h.od_timer then clock.cancel(h.od_timer) end
    if h.longfired then return end
    if r.state == "empty" then
      r.state = "armed"
    elseif r.state == "armed" then
      r.state = "empty"
    elseif r.state == "recording" then
      rec_stop_and_play(pi)
    elseif r.state == "playing" then
      if h.overdubbing then rec_overdub_stop(pi) else rec_stop_playback(pi) end
    elseif r.state == "stopped" then
      rec_start_playback(pi)
    end
  end
end

g.key = function(x, y, z)
  local pi = math.ceil(y / 2)
  local row = ((y - 1) % 2) + 1
  if x <= PADS_PER_ROW then
    local slot = (row - 1) * PADS_PER_ROW + x
    handle_cell_key(pi, slot, x, y, z)
  elseif x == 14 then
    handle_rec_key(pi, z)
  elseif x == 15 then
    if z == 1 then focused_player = pi; toggle_mute(pi) end
  elseif x == 16 then
    if z == 1 then focused_player = pi; player_stop(pi) end
  end
end

local function grid_redraw()
  g:all(0)
  local pulse = math.floor(6 + 9 * (0.5 + 0.5 * math.sin(util.time() * 6)))
  local fast  = (math.floor(util.time() * 6) % 2) == 0
  local slow  = (math.floor(util.time() * 2) % 2) == 0
  for pi = 1, NUM_PLAYERS do
    local pl = players[pi]
    -- cell pads
    for slot = 1, CELLS_PER_PLAYER do
      local x, y = slot_to_xy(pi, slot)
      local lvl = 0
      if pl.cellmap[slot] then
        lvl = 3
        if pl.playing and slot == pl.current_slot then lvl = 15 end
        if slot == pl.queued_slot then lvl = pulse end
      end
      g:led(x, y, lvl)
    end
    -- function keys on both of the player's rows
    local r = pl.rec
    local rec_lvl = 0
    if r.state == "armed" then rec_lvl = slow and 12 or 2
    elseif r.state == "recording" then rec_lvl = fast and 15 or 3
    elseif r.state == "playing" then rec_lvl = 15
    elseif r.state == "stopped" then rec_lvl = 5 end
    local mute_lvl = pl.muted and 15 or 3
    local stop_lvl = pl.playing and 8 or 3
    for row = 1, 2 do
      local y = (pi - 1) * 2 + row
      g:led(14, y, rec_lvl)
      g:led(15, y, mute_lvl)
      g:led(16, y, stop_lvl)
    end
  end
  g:refresh()
end

-- ----------------------------------------------------------------------------
-- screen
-- ----------------------------------------------------------------------------
local function draw_phasebar(x, y, w, frac)
  screen.level(3); screen.rect(x, y, w, 4); screen.stroke()
  screen.level(15); screen.rect(x, y, math.max(1, frac * w), 4); screen.fill()
end

local function redraw_overview()
  screen.move(0, 8); screen.level(15); screen.text("canto")
  screen.move(128, 8); screen.text_right(math.floor(params:get("clock_tempo") + 0.5) .. " bpm")
  for pi = 1, NUM_PLAYERS do
    local pl = players[pi]
    local y = 20 + (pi - 1) * 11
    screen.level(pi == focused_player and 15 or 5)
    screen.move(0, y)
    screen.text("P" .. pi .. " " .. profiles[pl.profile].name)
    screen.move(58, y)
    if pl.playing and pl.current then screen.text("c" .. pl.current) else screen.text("-") end
    if pl.queued then screen.move(80, y); screen.text(">" .. pl.queued) end
    if pl.muted then screen.move(100, y); screen.text("M") end
    if pl.playing and pl.current then
      local cell = cells[pl.current]
      local frac = ((clock.get_beats() - pl.loop_start_beat) / cell.length_beats) % 1
      draw_phasebar(108, y - 5, 20, frac)
    end
  end
end

local function redraw_detail()
  local pl = players[focused_player]
  screen.move(0, 8); screen.level(15)
  screen.text("P" .. focused_player .. " " .. profiles[pl.profile].name)
  screen.move(128, 8); screen.text_right(math.floor(params:get("clock_tempo") + 0.5) .. " bpm")

  screen.level(pl.playing and 15 or 3); screen.move(0, 24)
  if pl.playing and pl.current then
    local cell = cells[pl.current]
    screen.text("cell " .. pl.current .. "  " .. cell.measures)
    screen.move(0, 34); screen.level(10)
    screen.text(cell.meter[1] .. "/" .. cell.meter[2] .. "  " ..
      string.format("%.2f", cell.length_beats) .. " beats  " .. #cell.notes .. " notes")
    local frac = ((clock.get_beats() - pl.loop_start_beat) / cell.length_beats) % 1
    draw_phasebar(0, 40, 128, frac)
  else
    screen.text("stopped")
  end
  if pl.queued then screen.level(6); screen.move(0, 52); screen.text("queued: cell " .. pl.queued) end

  screen.level(6); screen.move(0, 62)
  screen.text("lvl " .. math.floor(pl.level * 100) .. "%   " ..
    (pl.muted and "MUTE  " or "") .. "rec:" .. pl.rec.state)
end

function redraw()
  screen.clear()
  if n_cells == 0 then
    screen.level(3); screen.move(0, 32); screen.text("no cells loaded"); screen.update(); return
  end
  if page == "overview" then redraw_overview() else redraw_detail() end
  screen.update()
end

-- ----------------------------------------------------------------------------
-- norns controls
-- ----------------------------------------------------------------------------
function enc(n, d)
  if n == 1 then params:delta("clock_tempo", d); return end
  if page == "overview" then
    if n == 2 then focused_player = util.clamp(focused_player + d, 1, NUM_PLAYERS)
    elseif n == 3 then params:delta("canto_seed", d) end
  else
    local pl = players[focused_player]
    if n == 2 then pl.level = util.clamp(pl.level + d * 0.02, 0, 1)
    elseif n == 3 then pl.profile = util.clamp(pl.profile + d, 1, #profiles) end
  end
end

function key(n, z)
  if z ~= 1 then return end
  if n == 1 then page = (page == "overview") and "detail" or "overview"; return end
  if page == "overview" then
    if n == 2 then for i = 1, NUM_PLAYERS do player_stop(i) end
    elseif n == 3 then params:set("canto_seed", (math.floor(util.time() * 1000) % 9999) + 1) end
  else
    if n == 2 then toggle_mute(focused_player)
    elseif n == 3 then player_stop(focused_player) end
  end
end

-- ----------------------------------------------------------------------------
-- lifecycle
-- ----------------------------------------------------------------------------
function init()
  for pi = 1, NUM_PLAYERS do
    players[pi] = {
      profile = pi, cellmap = {}, current = nil, queued = nil,
      current_slot = nil, queued_slot = nil, playing = false, muted = false,
      level = 1.0, pan = 0, clock_id = nil, loop_start_beat = 0, voices = {},
      rec = { state = "empty", events = {}, length_beats = nil,
              play_clock = nil, closing = nil, overdubbing = false },
    }
  end

  params:add_separator("canto")
  params:add_number("canto_seed", "cell-map seed", 1, 9999, 1)
  params:set_action("canto_seed", function(v) build_cellmap(v) end)

  params:set("clock_tempo", 75)
  build_cellmap(params:get("canto_seed"))

  if n_cells == 0 then
    print("canto: WARNING — no cells loaded (check lib/canto_cells.lua)")
  else
    print("canto: loaded " .. n_cells .. " cells across " .. NUM_PLAYERS .. " players")
  end

  -- grid diagnostic: if cols/rows are 0/nil, no grid is mapped to this script
  print("canto: grid = '" .. tostring(g.name) .. "'  " ..
    tostring(g.cols) .. "x" .. tostring(g.rows) ..
    "  (if 0x0 / nil, map the grid in SYSTEM > DEVICES > GRID)")

  redraw_clock = clock.run(function()
    while true do
      clock.sleep(1 / 15)
      local ok, err = pcall(function() redraw(); grid_redraw() end)
      if not ok then print("canto: redraw error -> " .. tostring(err)) end
    end
  end)
  grid_redraw()
  redraw()
end

function cleanup()
  if redraw_clock then clock.cancel(redraw_clock) end
  for pi = 1, NUM_PLAYERS do
    local pl = players[pi]
    if pl.clock_id then clock.cancel(pl.clock_id) end
    if pl.rec.play_clock then clock.cancel(pl.rec.play_clock) end
    all_voices_off(pi)
  end
end
