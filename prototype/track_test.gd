extends Node3D
# ============================================================
# TRACK TEST — the Phase R run scene. The referee: owns lives,
# deaths, notes/combo, the current checkpoint, and decides death
# and goal.
#
# Run it with:
#   godot --path . prototype/track_test.tscn
#
# The song drives the WORLD: the window (the strip of field on
# screen) scrolls at song speed and the player moves freely inside
# it. Death rewinds the SONG (BeatClock.seek); the window, every
# hazard and every plate re-derive their state from the new time.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const Mats := preload("res://prototype/flat_mats.gd")
const HazardMath := preload("res://prototype/hazard_math.gd")
const LapGen := preload("res://prototype/lap_gen.gd")

# Lives come from the level's knobs (Rules.lives(): 0 on level 1, 3 from
# level 2). Out of lives = the death screen, then back to level 1.
# Level 1 (addendum 2): no lives, a short freeze, rewind, continue.
const DEATH_FREEZE_S := 0.25
const DEATH_FREEZE_LIVES_S := 0.35
# The first tap unlocks browser audio; give the AudioContext a beat to
# resume before the clock and the music start together.
const START_DELAY_S := 0.20
# Same haptics the 2D game uses (main.gd).
const HAPTIC_DEATH_MS := 35
const HAPTIC_WIN_MS := 80
const HAPTIC_COIN_MS := 25
const NOTE_RADIUS := 1.0
const COMBO_CAP := 4
const START_Z := 10.0
const SELECT_SCENE := "res://prototype/level_select.tscn"
# Score (addendum 4 section 5): distance and deaths; notes are a bonus.
const DISTANCE_POINTS := 1000
const DEATH_PENALTY := 40
const NOTE_BONUS := 15

# LOADING is last so the numbers the tools print for the other states stay the same.
enum State { WAIT, STARTING, RUN, DEAD, WON, GAMEOVER, LOADING }

@onready var music: AudioStreamPlayer = $Music
@onready var field: Node3D = $Field
@onready var player: CharacterBody3D = $Player
@onready var rig: Node3D = $CameraRig
@onready var ui: Node2D = $UI/Screen
@onready var status: Label = $UI/Status
@onready var score_label: Label = $UI/Score
@onready var debug: Label = $UI/Debug
@onready var hud: Node2D = $UI/Hud
# Brief 3: everything on the beat and the weight of the moments; presentation only.
var motion: Node = null
# The knobs of what is being played: one curriculum row. Everything that
# depends on a knob gets this dictionary handed to it; nothing reads a
# global "current level" (Phase E section 1). Rules.LEVEL is only the pick
# the level select / a tool made, read once here.
var knobs := {}
var meter: FrameMeter = null   # dev only, null in a release

var state := State.WAIT
var lives := 0
var deaths := 0
var checkpoint := {}        # the last checkpoint passed ({} = the start): t, resume_t, x, z, bar
var notes := 0
var streak := 0             # notes since the last death
var combo_max := 1          # the longest streak this run
var furthest_t := 0.0       # furthest song time reached this run (distance)
var score := 0
var _freeze := 0.0
var _start_delay := 0.0
var _run_started_ms := 0
var _fair_warning := ""
var _prev_ht := 0.0
var _death_z := 0.0
# Optional autoplayer (tools/autoplay.gd). When set, its move_dir(scene)
# replaces the joystick. Never set in normal play.
var bot: Object = null
var _edge_line: MeshInstance3D
var _demo_bar_shown := 0
var _best_saved := 0.0
var _end_shown := 0.0       # seconds the goal / death screen has been up
# LOADING: the prewarm rack fills one item per frame behind a progress
# bar with the world hidden, then the world is revealed piece by piece.
const LOAD_SETTLE_FRAMES := 3
var _warm: Node3D = null
var _reveal: Array = []
var _load_frames := 0
var _settle := 0
var _tap_queued := false    # a tap during LOADING is kept: the run starts the moment loading ends
var _label_wait_from := 0   # msec: when the wait for a painted LOADING label began
var _bar_back: ColorRect
var _bar_fill: ColorRect

# ------------------------------------------------------------
# THE ENDLESS RUN (Phase E brief 1). The course is generated lap by lap
# (lap_gen.gd): the lap being played and the next one exist, nothing
# else. The next lap is generated, validated and built inside a budget
# of GEN_BUDGET_USEC per frame while this one is played; it should be
# ready by bar GEN_READY_BAR and, if it still is not at bar
# GEN_FORCE_BAR, it is finished on the spot with every unvalidated bar
# cleared to open floor (never a stall, never an unfair bar).
# ------------------------------------------------------------
const GEN_BUDGET_USEC := 2000
const GEN_READY_BAR := 60
const GEN_FORCE_BAR := 68
const LOAD_BUDGET_USEC := 10000      # per frame behind the progress bar, before the run
const FREE_AFTER_BARS := 3           # lap k - 1 goes once the death line is this far into lap k
const EASE_BARS := 2.0               # window / camera ease between two bands over this many bars
var endless := false
var graduated := false
var _job = null                      # LapGen.Job for the lap being generated
var _job_started_ms := 0
var _lap_knobs := {}                 # lap -> knobs (kept after the lap's nodes are gone)
var _lap_now := -1
var _start_z := 0.0                  # where the player stands at the start of this run
var _load_phase := 0                 # 0 generate lap 0, 1 build its nodes, 2 prewarm + reveal

# Lives in the endless run (section 4). A graduated player has RUN_LIVES
# for the whole run; a death costs one, freezes, rewinds the song to the
# last checkpoint (exactly what levels 2+ do); none left = the run is
# over. A NEW player's lap 0 costs no lives (exactly level 1): theirs
# start at RUN_LIVES when they cross into lap 1. rules.gd still decides
# what is lethal; this scene is the referee.
const RUN_LIVES := 3
# RETRY starts the song later into the intro: a run-up of RETRY_RUNUP_S
# instead of the full 8.6 s. The first run of a session keeps the full one.
const RETRY_RUNUP_S := 4.0
static var runs_this_session := 0
var _lives_on := false

# Distance and the shield (section 5). Distance = how far past bar 1's
# start line the player has been, in metres (1 unit = 1 m); it never goes
# down, a rewind takes nothing away; the best is kept per SEASON_SEED.
# Notes no longer score: each one adds the current combo (1-4) to a meter;
# at SHIELD_COST the shield arms and holds (one at most). An armed shield
# absorbs ONE hazard or plate death: no life lost, no rewind, the shield
# pops, SHIELD_GRACE_S of invulnerability to hazards and plates. Falling
# and the death line always kill. Decided here, after Rules.death_cause():
# rules.gd is untouched.
const SHIELD_COST := 30
const SHIELD_GRACE_S := 1.0
var distance_m := 0
var shield_meter := 0
var shield_armed := false
var shields_used := 0
var _grace := 0.0
var _furthest_z := 0.0
var _bar1_z := 0.0
var _best_m := 0                     # the best distance when this run began
var _best_crossed := false
var _best_line: MeshInstance3D
var _best_label: Label
var _bubble: MeshInstance3D
var _shield_burst: CPUParticles3D


func _ready() -> void:
	FrameMeter.load_scene_started()
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_dev_url_switches()
	_apply_render_scale()
	endless = Rules.ENDLESS
	if endless:
		_ready_endless()
	else:
		knobs = Rules.level(Rules.LEVEL)
		# The level's knobs (addendum 3 / 4): hazards act once per period, the
		# song starts at the level's offset. Both before the field is built,
		# since the layout is a function of them.
		BeatClock.set_endless(false)
		BeatClock.set_tempo(Rules.song_tempo(knobs))
		music.stream = load(BeatClock.music_path())
		BeatClock.set_start_offset(Rules.song_offset(knobs))
		lives = Rules.lives(knobs)
		print(Rules.knobs_line(knobs))
	_start_z = BeatClock.z_at(BeatClock.start_offset) + START_Z
	furthest_t = BeatClock.start_offset
	FrameMeter.load_mark("music")
	motion = load("res://prototype/motion.gd").new()
	motion.name = "Motion"
	add_child(motion)
	motion.knobs = knobs
	rig.motion = motion
	rig.configure(knobs)
	# (The level path's blocking build — validation + the whole field — waits
	# until the LOADING label has been painted: _build_level in _tick_loading.)
	player.reset_to(0.0, _start_z)
	ui.level_count = 1
	ui.show_hud = false
	ui.leave_menu()
	_edge_line = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(Rules.FIELD_WIDTH + 0.6, 0.06, 0.5)
	_edge_line.mesh = bm
	_edge_line.material_override = Mats.player(WorldPalette.SAFE)
	add_child(_edge_line)
	hud.ticks = []
	ui.jump_pressed.connect(_on_jump)
	status.text = "TAP TO START"
	debug.text = _fair_warning
	score_label.text = ""
	var z_back0 := BeatClock.z_at(BeatClock.start_offset)
	_update_world(BeatClock.hazard_time(), z_back0)
	rig.set_window(z_back0)
	motion.set_window(z_back0)
	if endless:
		_setup_run_hud()
	# Dev only: the frame-time readout and the load line (off in a release, see frame_meter.gd).
	if FrameMeter.enabled():
		meter = FrameMeter.new()
		$UI.add_child(meter)
	_begin_loading()


# The endless run: the looped track, the lap the run starts on. The lap is
# generated in the LOADING phase (a shipped or cached verdict makes that a
# few milliseconds; without one it is validated there, behind the bar).
func _ready_endless() -> void:
	BeatClock.set_endless(true)
	var stream: AudioStream = load(BeatClock.ENDLESS_MUSIC)
	stream.loop = true
	stream.loop_offset = BeatClock.loop_start_t
	music.stream = stream
	BeatClock.start_offset = BeatClock.ENDLESS_Z_ORIGIN_S
	if runs_this_session > 0:
		BeatClock.start_offset = BeatClock.loop_start_t - RETRY_RUNUP_S
	runs_this_session += 1
	if Rules.START_LAP > 0:
		# Dev: enter the course at a later lap, a short run-up before its bar 1.
		BeatClock.start_offset = BeatClock.bar_start(Rules.START_LAP * BeatClock.loop_bars + 1) - 4.0
	field.runup_z0 = BeatClock.z_at(BeatClock.start_offset) - field.PLAIN_LEN
	graduated = Progress.graduated or Rules.START_LAP > 0
	knobs = LapGen.knobs_for(Rules.START_LAP, graduated)
	_lap_knobs[Rules.START_LAP] = knobs
	_job = LapGen.begin(BeatClock, Rules.START_LAP, graduated)
	_job_started_ms = Time.get_ticks_msec()
	_lives_on = graduated
	lives = RUN_LIVES if graduated else 0
	if Rules.LIVES_OVERRIDE >= 0:
		# The bots measure the course, not the lives (unless asked to: lives=1).
		_lives_on = Rules.LIVES_OVERRIDE > 0
		lives = Rules.LIVES_OVERRIDE
	print("ENDLESS season %d, start lap %d (%s), run %d of the session, run-up %.1f s, lives %s, %s" % [LapGen.SEASON_SEED, Rules.START_LAP,
		String(knobs.get("variant", "")), runs_this_session, BeatClock.loop_start_t - BeatClock.start_offset,
		str(lives) if _lives_on else "off", Rules.knobs_line(knobs)])


# RENDER SCALE (2026-09-20, from the iPhone numbers: frame 28.7 ms with cpu
# 2.5 ms at level 1 bar 11 — the GPU is the limit, not the scripts). A phone
# browser hands the game a canvas at 3 device pixels per point (2556 x 1179
# on the test iPhone); every one of those pixels runs the stone / clay /
# monolith shaders. The 3D world is rendered at RENDER_SCALE_MOBILE of that
# and scaled up (0.75 = 56 % of the pixels); the HUD and the glass touch
# controls are 2D and stay at full resolution. The web (Compatibility)
# renderer supports this (checked); it has no pixel-ratio cap to offer
# instead, and one would blur the controls. Desktop stays at 1.0.
const RENDER_SCALE_MOBILE := 0.75
var _render_scale_override := -1.0

func _apply_render_scale() -> void:
	var sc := RENDER_SCALE_MOBILE if (OS.has_feature("web") or OS.has_feature("mobile")) else 1.0
	if _render_scale_override > 0.0:
		sc = _render_scale_override
	get_viewport().scaling_3d_scale = clampf(sc, 0.25, 1.0)
	FrameMeter.load_info = "3D %.2f of %d x %d" % [get_viewport().scaling_3d_scale, DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]


# DEV ONLY (same switch as the frame meter), web build only: URL switches
# for measuring the web build on a phone, where there is no console.
#   ?level=N      play level N of the old curriculum instead of the run
#                 (the fixed spot for frame-time readings: level 1, bar 11)
#   ?scale=0.6    3D render scale (see RENDER SCALE)
#   ?live=1       ignore shipped / cached verdicts: every lap is generated
#                 and validated live, inside the frame budget
#   ?autoplay=1   the validator bot (tools/autoplay.gd) drives the endless
#                 run, and starts it without a tap (no sound: the browser
#                 wants a tap)
#   ?grad=1       play as a graduated player (nothing is saved)
var _dev_autoplay := false

static func _url_param(query: String, key: String) -> String:
	for part in query.trim_prefix("?").split("&"):
		var kv := part.split("=")
		if kv.size() == 2 and kv[0] == key:
			return kv[1]
	return ""


func _dev_url_switches() -> void:
	if not OS.has_feature("web") or not FrameMeter.enabled():
		return
	var q := str(JavaScriptBridge.eval("window.location.search"))
	if _url_param(q, "scale") != "":
		_render_scale_override = float(_url_param(q, "scale"))
	if _url_param(q, "level") != "":
		Rules.ENDLESS = false
		Rules.LEVEL = clampi(int(_url_param(q, "level")), 1, 6)
		return
	if not Rules.ENDLESS:
		return
	if _url_param(q, "live") == "1":
		LapGen.ignore_verdicts = true
	if _url_param(q, "grad") == "1":
		Progress.save_enabled = false
		Progress.graduated = true
	if _url_param(q, "autoplay") == "1":
		Progress.save_enabled = false
		_dev_autoplay = true
		var ap: Object = load("res://tools/autoplay.gd").new()
		ap.mode = "validator"
		ap.Rules = Rules
		ap.HazardMath = HazardMath
		ap.attach_endless(self, BeatClock)
		bot = ap
		Rules.LIVES_OVERRIDE = 0
		print("DEV autoplay=1 live=%s" % LapGen.ignore_verdicts)


# Every material is drawn once before the run so no shader compiles in
# the middle of it (prewarm.gd) — one item per frame, behind a progress
# bar, with the world hidden, so the screen never freezes on it.
func _begin_loading() -> void:
	_warm = load("res://prototype/prewarm.gd").new()
	add_child(_warm)
	_warm.global_position = rig.global_position
	var bursts := [motion.burst(), player.creature.burst()]
	if _shield_burst != null:
		bursts.append(_shield_burst)
	_warm.prepare(bursts)
	_load_phase = -1
	if DisplayServer.get_name() == "headless":
		# Nothing is drawn, so there is nothing to warm: just make the level / the first lap.
		if not endless:
			_build_level()
		if endless:
			LapGen.step(_job, -1)
			_take_lap()
			field.build_step(-1)
		_end_loading()
		return
	state = State.LOADING
	_label_wait_from = Time.get_ticks_msec()
	_reveal = [rig, player, _edge_line, field]
	for n in _reveal:
		n.visible = false
	status.text = "LOADING"
	_bar_back = ColorRect.new()
	_bar_back.color = Color(1, 1, 1, 0.12)
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.set_anchors_preset(Control.PRESET_CENTER)
	_bar_back.position = Vector2(-160.0, -3.0)
	_bar_back.size = Vector2(320.0, 6.0)
	_bar_fill = ColorRect.new()
	_bar_fill.color = WorldPalette.SAFE
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_fill.size = Vector2(0.0, 6.0)
	_bar_back.add_child(_bar_fill)
	$UI.add_child(_bar_back)


# Painted frames. This runs inside the render step, so it does ONE thing:
# add 1 to an int. Nothing that can raise, and nothing that talks to the
# browser, belongs in here — see frame_meter.first_frame_painted().
var _painted := 0

func _on_frame_drawn() -> void:
	_painted += 1


# The level path's blocking step: generate + validate + build the level.
func _build_level() -> void:
	field.build(knobs)
	if not field.fairness["ok"]:
		_fair_warning = "FAIRNESS CHECK FAILED (%d) — see log" % field.fairness["problems"].size()
		debug.text = _fair_warning
	for cp in field.checkpoints:
		hud.ticks.append(BeatClock.progress_of(float(cp["t"])))
	hud.best = BeatClock.progress_of(Progress.best_for(Rules.LEVEL))
	_update_world(BeatClock.hazard_time(), BeatClock.z_at(BeatClock.start_offset))


func _tick_loading() -> void:
	_load_frames += 1
	# Nothing heavy before the LOADING label has really been painted — but
	# never wait for that for ever (FrameMeter.LABEL_TIMEOUT_MS).
	if _load_phase == -1:
		if _painted >= 1:
			FrameMeter.first_frame_painted()
		var waited := Time.get_ticks_msec() - _label_wait_from
		if _painted < 2 and waited < FrameMeter.LABEL_TIMEOUT_MS:
			return
		if _painted < 2:
			push_warning("LOADING: no painted frame after %d ms; carrying on" % waited)
			FrameMeter.first_frame_painted()
		FrameMeter.load_label_painted(_painted < 2)
		if not endless:
			_build_level()
		_load_phase = 0 if endless else 2
		return
	# The endless run first makes its first lap: generate (+ validate when no
	# verdict is stored), then build the nodes, LOAD_BUDGET_USEC per frame.
	if _load_phase == 0:
		if LapGen.step(_job, LOAD_BUDGET_USEC):
			_take_lap()
			_load_phase = 1
		_bar_fill.size.x = 320.0 * 0.05
		return
	if _load_phase == 1:
		var before: int = field.pending_items()
		if field.build_step(LOAD_BUDGET_USEC):
			FrameMeter.load_mark("nodes", "%d hazards" % field.hazards.size())
			_load_phase = 2
		_bar_fill.size.x = 320.0 * (0.05 + 0.45 * (1.0 - float(field.pending_items()) / maxf(float(before), 1.0)))
		return
	var total := float(_warm.item_count() + 4 + LOAD_SETTLE_FRAMES)
	var done := 0.0
	var p: float = _warm.step()
	done = p * _warm.item_count()
	if p >= 1.0:
		if not _reveal.is_empty():
			_reveal.pop_front().visible = true
		else:
			_settle += 1
		done += (4 - _reveal.size()) + _settle
	var frac := clampf(done / total, 0.0, 1.0)
	_bar_fill.size.x = 320.0 * ((0.5 + 0.5 * frac) if endless else frac)
	if _settle >= LOAD_SETTLE_FRAMES:
		_end_loading()


func _end_loading() -> void:
	FrameMeter.load_mark("prewarm", "%d items, %d frames" % [_warm.item_count(), _load_frames], true)
	FrameMeter.load_done()
	_warm.queue_free()
	_warm = null
	if _bar_back != null:
		_bar_back.queue_free()
	state = State.WAIT
	status.text = "TAP TO START"
	if _tap_queued or _dev_autoplay:
		state = State.STARTING
		_start_delay = START_DELAY_S
		status.text = ""


# The generation job is done: the lap goes into the field (its nodes are
# queued there) and its verdict is on the load line.
func _take_lap() -> void:
	var job = _job
	_job = null
	_lap_knobs[job.lap] = job.knobs
	field.add_lap(job.lap, job.knobs, job.clock, job.plan, job.fairness, job.lap == Rules.START_LAP)
	var note := "lap %d %s" % [job.lap, job.from]
	if job.from == "live" or job.from == "forced":
		note += ", %d passes, %d cleared, %.1f s cpu over %.1f s" % [job.passes, job.cleared.size(),
			job.work_usec / 1_000_000.0, (Time.get_ticks_msec() - _job_started_ms) / 1000.0]
	print("LAP READY " + note)
	if state == State.LOADING:
		FrameMeter.load_mark("validate", note, true)
	elif FrameMeter.active:
		FrameMeter.note("lap %d taken" % job.lap)


# Per frame, in an endless run: which lap is being played, the next lap's
# generation and building inside the frame budget, freeing the lap behind.
func _tick_course(t: float, z_back: float) -> void:
	var lap := BeatClock.lap_at(t)
	if lap != _lap_now:
		_lap_now = lap
		field.set_current(lap)
		knobs = _lap_knobs.get(lap, knobs)
		motion.knobs = knobs
		if lap >= 1 and not graduated:
			# The one flag: from now on lap 0 no longer teaches...
			graduated = true
			Progress.set_graduated()
			# ...and the new player's lives start here.
			if Rules.LIVES_OVERRIDE < 0:
				_lives_on = true
				lives = RUN_LIVES
	var next := maxi(lap, Rules.START_LAP) + 1
	if _job == null and not field.has_lap(next):
		_job = LapGen.begin(BeatClock, next, true)
		_job_started_ms = Time.get_ticks_msec()
	if _job != null:
		var local_bar := BeatClock.bar_at(t) - lap * BeatClock.loop_bars
		if local_bar >= GEN_FORCE_BAR:
			LapGen.force_finish(_job)
		if LapGen.step(_job, GEN_BUDGET_USEC):
			_take_lap()
	elif field.pending_items() > 0:
		var hurry := BeatClock.bar_at(t) - lap * BeatClock.loop_bars >= GEN_FORCE_BAR
		field.build_step(GEN_BUDGET_USEC * (4 if hurry else 1))
	# The lap behind goes once the death line is well into this one.
	if field.has_lap(lap - 1) and field.has_lap(lap) \
			and Rules.back_edge(z_back) > field.laps[lap].z0 + FREE_AFTER_BARS * Rules.BAR_LENGTH:
		field.free_lap(lap - 1)


# The window's depth now. Between two laps whose bands differ it eases
# over the new lap's first EASE_BARS bars (the camera distance follows).
func _window_depth_at(t: float) -> float:
	var depth := Rules.window_depth(knobs)
	if not endless or _lap_now <= 0 or not _lap_knobs.has(_lap_now - 1):
		return depth
	var prev := Rules.window_depth(_lap_knobs[_lap_now - 1])
	if is_equal_approx(prev, depth):
		return depth
	var first := _lap_now * BeatClock.loop_bars + 1
	var u := clampf((t - BeatClock.bar_start(first)) / maxf(BeatClock.bar_start(first + int(EASE_BARS)) - BeatClock.bar_start(first), 0.001), 0.0, 1.0)
	return lerpf(prev, depth, u * u * (3.0 - 2.0 * u))


# The endless HUD: the distance big at the top centre, BEST under it, the
# lives and the shield ring beside it (hud.gd); the best line on the
# field; the shield's bubble and its pop.
func _setup_run_hud() -> void:
	hud.endless = true
	_bar1_z = BeatClock.z_at(BeatClock.loop_start_t)
	_furthest_z = _start_z
	_best_m = Progress.best_distance_for(LapGen.SEASON_SEED)
	score_label.add_theme_font_size_override("font_size", 34)
	score_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	score_label.offset_top = 16.0
	score_label.offset_bottom = 60.0
	score_label.pivot_offset = Vector2(200.0, 22.0)
	_best_label = Label.new()
	_best_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_best_label.offset_left = -200.0
	_best_label.offset_right = 200.0
	_best_label.offset_top = 58.0
	_best_label.offset_bottom = 76.0
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_best_label.add_theme_font_size_override("font_size", 12)
	_best_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.24, 0.85))
	$UI.add_child(_best_label)
	# The best line: thin, amber (amber = goal), built like the death line.
	_best_line = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(Rules.FIELD_WIDTH + 0.6, 0.06, 0.22)
	_best_line.mesh = bm
	_best_line.material_override = Mats.player(WorldPalette.GOAL)
	_best_line.position = Vector3(0.0, 0.04, _bar1_z + float(_best_m))
	_best_line.visible = _best_m > 0
	add_child(_best_line)
	# The shield: a thin glass bubble in SAFE cyan, and the creature's clay
	# pop recoloured cyan for when it breaks.
	_bubble = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.75
	sm.height = 3.5
	sm.radial_segments = 24
	sm.rings = 12
	_bubble.mesh = sm
	_bubble.material_override = Mats.shield()
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.visible = false
	player.add_child(_bubble)
	_shield_burst = player.creature.burst().duplicate()
	var ball: Mesh = _shield_burst.mesh.duplicate()
	var mat: StandardMaterial3D = ball.material.duplicate()
	mat.albedo_color = WorldPalette.SAFE
	ball.material = mat
	_shield_burst.mesh = ball
	_shield_burst.emitting = false
	add_child(_shield_burst)


static func metres(m: int) -> String:
	var txt := str(m)
	var out := ""
	while txt.length() > 3:
		out = " " + txt.substr(txt.length() - 3) + out
		txt = txt.substr(0, txt.length() - 3)
	return txt + out + " m"


# Per frame in a run: the distance, the best line, the shield's look.
func _tick_distance_and_shield(delta: float) -> void:
	_grace = maxf(0.0, _grace - delta)
	_furthest_z = maxf(_furthest_z, player.position.z)
	distance_m = maxi(0, int(floor(_furthest_z - _bar1_z)))
	if _best_m > 0 and not _best_crossed and distance_m > _best_m:
		_best_crossed = true
		motion.on_best_crossed()
		FrameMeter.note("best line crossed")
	_bubble.position.y = player.y + 1.35
	# Armed: the bubble. In the grace second after it broke: it flickers out.
	_bubble.visible = shield_armed or (_grace > 0.0 and fmod(_grace, 0.16) > 0.08)


# A note charges the shield with the current combo (1-4).
func _charge_shield() -> void:
	if shield_armed:
		return
	shield_meter = mini(SHIELD_COST, shield_meter + mini(maxi(streak, 1), COMBO_CAP))
	if shield_meter >= SHIELD_COST:
		shield_armed = true
		FrameMeter.note("shield armed")


# True when the death was taken by the shield (or falls in its grace).
func _shield_takes(cause: Dictionary) -> bool:
	var kind := String(cause["kind"])
	if kind == "fall" or kind == "back_edge":
		return false          # these always kill
	if _grace > 0.0:
		return true
	if not shield_armed:
		return false
	shield_armed = false
	shield_meter = 0
	shields_used += 1
	_grace = SHIELD_GRACE_S
	hud.shield_pop = 1.0
	_shield_burst.global_position = player.position + Vector3(0.0, player.y + 1.2, 0.0)
	_shield_burst.restart()
	Input.vibrate_handheld(HAPTIC_COIN_MS)
	FrameMeter.note("shield pop")
	print("SHIELD absorbed %s at bar %d, %d m" % [kind, BeatClock.current_bar(), distance_m])
	return true


# Do deaths cost lives right now?
func lives_enabled() -> bool:
	return _lives_on if endless else Rules.lives_enabled(knobs)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if state == State.RUN:
			_on_jump()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_to_level_select()
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if not pressed:
		return
	match state:
		State.LOADING:
			_tap_queued = true
			status.text = "LOADING  ·  starts when ready"
		State.WAIT:
			state = State.STARTING
			_start_delay = START_DELAY_S
			status.text = ""
		State.WON:
			if _end_shown > 0.6:
				_to_level_select()
		State.GAMEOVER:
			# Out of lives. A level: the loop starts over from level 1 (the
			# original rule). The endless run: a new run, short run-up.
			if _end_shown > 0.6:
				if endless:
					# RETRY (big) starts a new run with the short run-up; MENU goes to
					# the dev level select until Stage 2's menu exists. A key = retry.
					var pos: Variant = event.position if (event is InputEventScreenTouch or event is InputEventMouseButton) else null
					if pos != null and hud.menu_rect.has_point(pos):
						_to_level_select()
					elif pos == null or hud.retry_rect.has_point(pos):
						BeatClock.stop()
						get_tree().reload_current_scene()
					return
				Rules.LEVEL = 1
				get_tree().reload_current_scene()


func _to_level_select() -> void:
	if endless:
		Progress.record_distance(LapGen.SEASON_SEED, distance_m)
	BeatClock.stop()
	get_tree().change_scene_to_file(SELECT_SCENE)


func _process(delta: float) -> void:
	match state:
		State.LOADING:
			_tick_loading()
		State.STARTING:
			_start_delay -= delta
			if _start_delay <= 0.0:
				if meter != null:
					meter.run_started()
				BeatClock.start(music)
				_run_started_ms = Time.get_ticks_msec()
				motion.on_level_start()
				state = State.RUN
		State.RUN:
			_tick_run(delta)
		State.DEAD:
			_freeze -= delta
			if _freeze <= 0.0:
				_rewind()
		State.WON, State.GAMEOVER:
			_end_shown += delta
	ui.set_status(0, 1, lives, deaths, state == State.DEAD and lives_enabled())
	if state != State.DEAD:
		motion.animate_notes(field.notes, player.position)
	_update_hud()


func _tick_run(delta: float) -> void:
	var t := BeatClock.song_time()
	var ht := BeatClock.hazard_time()
	var z_back := BeatClock.z_at(t)
	if endless:
		_tick_course(t, z_back)
	var depth := _window_depth_at(t)
	rig.set_window_depth(depth)
	var z_front := z_back + depth

	player.move_dir = bot.move_dir(self) if bot != null else _move_input()
	player.tick(delta, z_back, z_front, field)
	rig.set_window(z_back)
	motion.set_window(z_back)
	_update_world(ht, z_back)
	_update_progress(t)
	_update_demo(ht)
	field.widen_goal(clampf((player.position.z - (field.goal_z - BeatClock.BAR_UNITS)) / BeatClock.BAR_UNITS, 0.0, 1.0))

	for cp in field.checkpoints:
		if float(cp["t"]) > float(checkpoint.get("t", -1.0)) and t >= float(cp["t"]):
			checkpoint = {"t": cp["t"], "resume_t": cp["resume_t"], "x": cp["x"], "z": cp["z"], "bar": cp["bar"]}
			FrameMeter.note("checkpoint")
			field.mark_checkpoint(cp)
			motion.on_checkpoint(float(cp["z"]))
			hud.lit += 1
			player.creature.play_glance()
			Input.vibrate_handheld(HAPTIC_COIN_MS)

	for n in field.notes:
		if n["taken"] or player.y > 1.8:
			continue
		if Vector2(n["x"] - player.position.x, n["z"] - player.position.z).length() < NOTE_RADIUS:
			n["taken"] = true
			streak += 1
			notes += 1
			combo_max = maxi(combo_max, mini(streak, COMBO_CAP))
			if endless:
				_charge_shield()
			motion.on_pickup(n["node"], player, streak)
			Input.vibrate_handheld(HAPTIC_COIN_MS)

	# --- death: ONE rules query (rules.gd decides; meshes are visual only)
	var cause := Rules.death_cause(field, player.prev_position, player.position,
		player.on_ground, z_back, _prev_ht, ht)
	_prev_ht = ht
	if endless:
		_tick_distance_and_shield(delta)
		if not cause.is_empty() and _shield_takes(cause):
			cause = {}
	if not cause.is_empty():
		FrameMeter.note("death")
		_log_death(cause, t, ht, z_back)
		_die()
		motion.on_death(_killer_node(cause), cause["pos"], player.position)
		return

	player.look_at_danger(_demo_target(ht) if _in_demo_bar(ht) else _nearest_danger(ht))

	if player.position.z >= field.goal_z:
		_win()


func _update_progress(t: float) -> void:
	furthest_t = maxf(furthest_t, t)
	if endless:
		return            # a level's progress bar and best time mean nothing here
	hud.fill = motion.progress_fill(BeatClock.progress_of(t))
	if t > Progress.best_for(Rules.LEVEL):
		hud.best = BeatClock.progress_of(t)
		if t - _best_saved > 2.0:
			Progress.record_best(Rules.LEVEL, t)
			FrameMeter.note("progress save")
			_best_saved = t


# Addendum 4 section 5: distance and deaths; notes are a bonus.
func distance_points() -> int:
	return int(floor(BeatClock.progress_of(furthest_t) * DISTANCE_POINTS))


func current_score() -> int:
	return maxi(0, distance_points() - deaths * DEATH_PENALTY + notes * NOTE_BONUS * combo_max)


func _in_demo_bar(ht: float) -> bool:
	return field.plan["demo_bars"].has(BeatClock.bar_at(ht))


# The one word above the field while a demo bar plays (or, in a breather,
# the word for what the next wave introduces); fades on the next downbeat.
func _update_demo(ht: float) -> void:
	var bar := BeatClock.bar_at(ht)
	var word := String(field.plan["bars"][bar]["word"]) if field.plan["bars"].has(bar) else ""
	if word != "":
		if _demo_bar_shown != bar:
			_demo_bar_shown = bar
			hud.show_word(word)
	elif _demo_bar_shown != 0:
		_demo_bar_shown = 0
		hud.hide_word()


# During a demo bar the eye locks onto the thing being demonstrated.
func _demo_target(ht: float) -> Variant:
	var bar := BeatClock.bar_at(ht)
	var kind := String(field.plan["demo_bars"].get(bar, ""))
	if kind == "plates":
		return field.nearest_danger_tile(player.position.x, player.position.z, ht)
	var best: Variant = null
	var best_d := 1e9
	for h in field.hazards:
		if int(h.spec["bar"]) != bar:
			continue
		for b in HazardMath.shape_boxes_at(h.spec, ht, h.knobs):
			var bb: AABB = b
			var c := bb.get_center()
			var d := Vector2(c.x - player.position.x, c.z - player.position.z).length()
			if d < best_d:
				best_d = d
				best = c
	return best


func _update_world(ht: float, z_back: float) -> void:
	# Drawn at the geometric back edge; during the intro it carries, after
	# the first downbeat it kills (Rules.death_line).
	_edge_line.position = Vector3(0.0, 0.03, Rules.back_edge(z_back))
	field.update_tiles(ht, z_back)
	field.update_hazards(ht, z_back)


# Nearest hazard box or plate that is lethal now or within the next beat.
func _nearest_danger(ht: float) -> Variant:
	var best: Variant = field.nearest_danger_tile(player.position.x, player.position.z, ht)
	var best_d: float = 1e9 if best == null else Vector2(best.x - player.position.x, best.z - player.position.z).length()
	var soon := ht + BeatClock.beat_interval
	for h in field.hazards:
		if absf(h.position.z - player.position.z) > 10.0:
			continue
		for b in h.boxes() + h.boxes_at(soon):
			var bb: AABB = b
			var c := bb.get_center()
			var d := Vector2(c.x - player.position.x, c.z - player.position.z).length()
			if d < best_d:
				best_d = d
				best = c
	return best


# Joystick / keys -> (screen-right, forward). Past the deadzone the
# normalised direction is used at full speed, the 2D game's rule.
# Input is WORLD-relative by default (joystick up = down the field
# whatever the camera's yaw); CameraRig.INPUT_CAMERA_RELATIVE flips it.
# The joystick, raw: the thumb's offset from where it landed, read every
# frame, no smoothing and no lerp anywhere between the touch and the
# player's position. Dead zone 6 % of the stick radius (was 13 %); full
# speed at STICK_FULL of the radius, so a small flick is already a run.
const STICK_DEADZONE_FRAC := 0.06
const STICK_FULL_FRAC := 0.30


func _move_input() -> Vector2:
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if ui.stick_touch_id != -1:
		var drag: Vector2 = ui.stick_current - ui.stick_origin
		var r: float = ui.STICK_RADIUS
		if drag.length() <= r * STICK_DEADZONE_FRAC:
			v = Vector2.ZERO
		else:
			v = (drag / (r * STICK_FULL_FRAC)).limit_length(1.0)
	var dir := Vector2(v.x, -v.y)
	if rig.INPUT_CAMERA_RELATIVE:
		dir = rig.screen_to_world_dir(dir)
	return dir


func _on_jump() -> void:
	if state != State.RUN:
		return
	if player.jump():
		ui.confirm_jump()


# Permanent death log: one line per death, kept in every build.
func _log_death(cause: Dictionary, t: float, ht: float, z_back: float) -> void:
	var p := player.position
	var kp: Vector3 = cause["pos"]
	var rules_here := Rules.point_lethal(field, p, player.on_ground, ht)
	var between := []
	var cam_pos: Vector3 = rig.cam.global_position
	var eye := p + Vector3(0.0, 0.8, 0.0)
	for h in field.hazards:
		for b in h.boxes():
			var bb: AABB = b
			if bb.intersects_segment(cam_pos, eye) != null:
				between.append("%s@z%.1f" % [h.kind, h.position.z])
	print("DEATH t=%.3f bar=%d beat=%d phase=%.2f player=(%.2f, %.2f, %.2f) on_ground=%s killer=%s at=(%.2f, %.2f, %.2f) rules_lethal_here=%s z_back=%.2f between_camera_and_player=%s" % [
		t, BeatClock.bar_at(t), BeatClock.beat_in_bar_at(ht) + 1, BeatClock.beat_phase_at(ht),
		p.x, p.y, p.z, player.on_ground, cause["kind"], kp.x, kp.y, kp.z, rules_here, z_back,
		"none" if between.is_empty() else ",".join(between)])


# tools/shot.gd only: walk into the nearest lethal hazard so the next tick
# is a death (for the death-flash screenshot). Not reachable from play.
func debug_walk_into_danger() -> bool:
	var best: Variant = null
	var best_d := 1e9
	for h in field.hazards:
		if h.kind == "gate":
			continue   # a gate only kills on a crossing, standing in it does nothing
		for b in h.boxes():
			var bb: AABB = b
			var c := bb.get_center()
			if c.z < player.position.z - 0.5 or c.z > player.position.z + 8.0:
				continue   # behind us (a back-edge death) or too far ahead (a gate crossing)
			var d := Vector2(c.x - player.position.x, c.z - player.position.z).length()
			if d < best_d:
				best_d = d
				best = Vector3(c.x, 0.0, c.z)
	if best == null:
		return false
	player.position = best
	player.prev_position = best
	return true


# The node that killed us, for the death flash (visual only): the hazard
# whose lethal box is nearest the cause's position, or the plate tile.
func _killer_node(cause: Dictionary) -> Node:
	var kp: Vector3 = cause["pos"]
	match String(cause["kind"]):
		"plate":
			return field.tile_node_at(kp.x, kp.z)
		"back_edge", "fall":
			return null
	var best: Node = null
	var best_d := 1e9
	for h in field.hazards:
		if h.kind != String(cause["kind"]):
			continue
		var d: float = (h.position - Vector3(h.position.x, 0.0, kp.z)).length()
		for b in h.boxes():
			var bb: AABB = b
			d = minf(d, (bb.get_center() - kp).length())
		if d < best_d:
			best_d = d
			best = h
	return best


func start_now() -> void:
	if state == State.WAIT:
		state = State.STARTING
		_start_delay = 0.0
		status.text = ""


func _die() -> void:
	state = State.DEAD
	if lives_enabled():
		lives -= 1
	deaths += 1
	streak = 0
	player.dead = true
	player.move_dir = Vector2.ZERO
	Input.vibrate_handheld(HAPTIC_DEATH_MS)
	# Brief 3 hit-stop: the clock and the music keep running; the world's
	# visuals hold because nothing samples time in State.DEAD and
	# motion.frozen stops the beat visuals. (Was BeatClock.pause().)
	_death_z = player.position.z
	_freeze = DEATH_FREEZE_LIVES_S if lives_enabled() else DEATH_FREEZE_S
	player.creature.play_death(_freeze)
	if endless:
		Progress.record_distance(LapGen.SEASON_SEED, distance_m)
	else:
		Progress.record_best(Rules.LEVEL, BeatClock.song_time())
	if lives_enabled() and lives <= 0:
		_game_over()


# Out of lives (level 2+): the minimal death screen — score, how far,
# retry. No roast text, no share screen yet (addendum 4 section 6).
func _game_over() -> void:
	state = State.GAMEOVER
	_end_shown = 0.0
	hud.hide_word()
	if endless:
		# The end screen (section 6): distance big, BEST / NEW BEST, RETRY, MENU.
		var new_best: bool = Progress.record_distance(LapGen.SEASON_SEED, distance_m) or (distance_m > _best_m and distance_m > 0)
		status.text = ""
		score_label.visible = false
		_best_label.visible = false
		_bubble.visible = false
		# The two lines that always draw on top would cut across the buttons.
		_edge_line.visible = false
		_best_line.visible = false
		hud.show_end(metres(distance_m), "BEST " + metres(maxi(_best_m, distance_m)), new_best)
		print("RUN OVER distance=%d m best=%d m new_best=%s laps=%d run_s=%.1f deaths=%d notes=%d shields_used=%d" % [
			distance_m, maxi(_best_m, distance_m), new_best, BeatClock.current_lap(),
			BeatClock.song_time() - BeatClock.start_offset, deaths, notes, shields_used])
		return
	score = current_score()
	Progress.record_score(Rules.LEVEL, score)
	status.text = "OUT OF LIVES\ndied at %d%%   ·   deaths %d   ·   score %d\nTAP TO RETRY FROM LEVEL 1" % [
		int(round(BeatClock.progress_of(furthest_t) * 100.0)), deaths, score]


func _rewind() -> void:
	var t := BeatClock.start_offset
	var x := 0.0
	var z := _start_z
	if not checkpoint.is_empty():
		t = float(checkpoint["resume_t"])
		x = float(checkpoint["x"])
		z = float(checkpoint["z"])
	player.reset_to(x, z)
	player.dead = false
	player.creature.play_respawn()
	motion.on_rewind(_death_z, z)
	FrameMeter.note("rewind (song seek)")
	BeatClock.seek(t)
	var z_back := BeatClock.z_at(t)
	# Permanent log, like DEATH: where the song and the world went back to.
	print("REWIND t=%.3f lap=%d bar=%d audio=%.3f z_back=%.2f player=(%.2f, %.2f) checkpoint_bar=%d lives=%s" % [
		t, BeatClock.lap_at(t), BeatClock.bar_at(t), BeatClock.local_t(t), z_back, x, z,
		int(checkpoint.get("bar", 0)), str(lives) if lives_enabled() else "off"])
	rig.set_window(z_back)
	_update_world(BeatClock.hazard_time(), z_back)
	state = State.RUN


func _win() -> void:
	state = State.WON
	_end_shown = 0.0
	player.move_dir = Vector2.ZERO
	player.creature.play_goal()
	motion.on_goal()
	Input.vibrate_handheld(HAPTIC_WIN_MS)
	hud.fill = 1.0
	furthest_t = BeatClock.duration
	Progress.record_best(Rules.LEVEL, BeatClock.duration)
	hud.best = 1.0
	hud.hide_word()
	score = current_score()
	Progress.record_score(Rules.LEVEL, score)
	Progress.mark_level_cleared(Rules.LEVEL)
	status.text = "GOAL\ndistance 100%%   ·   deaths %d   ·   notes %d (x%d)\nscore %d   ·   TAP FOR LEVELS" % [
		deaths, notes, combo_max, score]


# The run's HUD: the distance, BEST, lives, the shield meter. No score, no
# combo readout, no song progress bar.
func _update_run_hud() -> void:
	score_label.text = metres(distance_m) if state != State.LOADING and state != State.WAIT else ""
	score_label.scale = Vector2.ONE
	score_label.modulate.a = 1.0
	var best := maxi(_best_m, distance_m)
	_best_label.text = ("BEST " + metres(best)) if best > 0 else ""
	hud.lives = lives
	hud.lives_max = RUN_LIVES if lives_enabled() else 0
	hud.shield = float(shield_meter) / float(SHIELD_COST)
	hud.shield_armed = shield_armed
	var lap := BeatClock.current_lap()
	var line := "lap %d   ·   bar %d / %d   ·   %.1f s   ·   notes %d   ·   sync %+d ms" % [
		lap, BeatClock.current_bar() - lap * BeatClock.loop_bars, BeatClock.loop_bars, BeatClock.song_time(), notes,
		int(round(BeatClock.SYNC_OFFSET_S * 1000.0))]
	debug.text = line if _fair_warning.is_empty() else _fair_warning + "\n" + line


func _update_hud() -> void:
	if endless:
		_update_run_hud()
		return
	if state == State.WAIT:
		return
	if lives_enabled():
		score_label.text = "♪ %d   x%d   ·   lives %d   ·   %d" % [notes, mini(maxi(streak, 1), COMBO_CAP), lives, current_score()]
	else:
		score_label.text = "♪ %d   x%d   ·   %d" % [notes, mini(maxi(streak, 1), COMBO_CAP), current_score()]
	var pop: float = maxf(motion.counter_scale, motion.combo_scale)
	score_label.scale = Vector2.ONE * pop
	score_label.modulate.a = lerpf(0.45, 1.0, motion.combo_alpha)
	var line := "bar %d / %d   ·   %.1f s   ·   sync %+d ms" % [
		BeatClock.current_bar(), BeatClock.bar_count(), BeatClock.song_time(),
		int(round(BeatClock.SYNC_OFFSET_S * 1000.0))]
	debug.text = line if _fair_warning.is_empty() else _fair_warning + "\n" + line
