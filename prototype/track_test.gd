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
var checkpoint := -1        # index into field.checkpoints; -1 = song start
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
var _bar_back: ColorRect
var _bar_fill: ColorRect


func _ready() -> void:
	FrameMeter.load_mark("scene")
	knobs = Rules.level(Rules.LEVEL)
	# The level's knobs (addendum 3 / 4): hazards act once per period, the
	# song starts at the level's offset. Both before the field is built,
	# since the layout is a function of them.
	BeatClock.set_tempo(Rules.song_tempo(knobs))
	music.stream = load(BeatClock.music_path())
	BeatClock.start_offset = Rules.song_offset(knobs)
	lives = Rules.lives(knobs)
	furthest_t = BeatClock.start_offset
	print(Rules.knobs_line(knobs))
	FrameMeter.load_mark("music")
	motion = load("res://prototype/motion.gd").new()
	motion.name = "Motion"
	add_child(motion)
	motion.knobs = knobs
	rig.motion = motion
	rig.configure(knobs)
	field.build(knobs)
	if not field.fairness["ok"]:
		_fair_warning = "FAIRNESS CHECK FAILED (%d) — see log" % field.fairness["problems"].size()
	player.reset_to(0.0, START_Z)
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
	for cp in field.checkpoints:
		hud.ticks.append(BeatClock.progress_of(float(cp["t"])))
	hud.best = BeatClock.progress_of(Progress.best_for(Rules.LEVEL))
	ui.jump_pressed.connect(_on_jump)
	status.text = "TAP TO START"
	debug.text = _fair_warning
	score_label.text = ""
	_update_world(BeatClock.hazard_time(), 0.0)
	rig.set_window(0.0)
	motion.set_window(0.0)
	# Dev only: the frame-time readout and the load line (off in a release, see frame_meter.gd).
	if FrameMeter.enabled():
		meter = FrameMeter.new()
		$UI.add_child(meter)
	_begin_loading()


# Every material is drawn once before the run so no shader compiles in
# the middle of it (prewarm.gd) — one item per frame, behind a progress
# bar, with the world hidden, so the screen never freezes on it.
func _begin_loading() -> void:
	_warm = load("res://prototype/prewarm.gd").new()
	add_child(_warm)
	_warm.global_position = rig.global_position
	_warm.prepare([motion.burst(), player.creature.burst()])
	if DisplayServer.get_name() == "headless":
		_end_loading()       # nothing is drawn, so there is nothing to warm
		return
	state = State.LOADING
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


func _tick_loading() -> void:
	_load_frames += 1
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
	_bar_fill.size.x = 320.0 * clampf(done / total, 0.0, 1.0)
	if _settle >= LOAD_SETTLE_FRAMES:
		_end_loading()


func _end_loading() -> void:
	FrameMeter.load_mark("prewarm", "%d items, %d frames" % [_warm.item_count(), _load_frames], true)
	_warm.queue_free()
	_warm = null
	if _bar_back != null:
		_bar_back.queue_free()
	state = State.WAIT
	status.text = "TAP TO START"
	if _tap_queued:
		state = State.STARTING
		_start_delay = START_DELAY_S
		status.text = ""


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
			# Out of lives: the loop starts over from level 1 (the original rule).
			if _end_shown > 0.6:
				Rules.LEVEL = 1
				get_tree().reload_current_scene()


func _to_level_select() -> void:
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
	ui.set_status(0, 1, lives, deaths, state == State.DEAD and Rules.lives_enabled(knobs))
	if state != State.DEAD:
		motion.animate_notes(field.notes, player.position)
	_update_hud()


func _tick_run(delta: float) -> void:
	var t := BeatClock.song_time()
	var ht := BeatClock.hazard_time()
	var z_back := BeatClock.z_at(t)
	var z_front := z_back + Rules.window_depth(knobs)

	player.move_dir = bot.move_dir(self) if bot != null else _move_input()
	player.tick(delta, z_back, z_front, field)
	rig.set_window(z_back)
	motion.set_window(z_back)
	_update_world(ht, z_back)
	_update_progress(t)
	_update_demo(ht)
	field.widen_goal(clampf((player.position.z - (field.goal_z - BeatClock.BAR_UNITS)) / BeatClock.BAR_UNITS, 0.0, 1.0))

	for i in field.checkpoints.size():
		if i > checkpoint and t >= float(field.checkpoints[i]["t"]):
			checkpoint = i
			FrameMeter.note("checkpoint")
			field.mark_checkpoint(i)
			motion.on_checkpoint(float(field.checkpoints[i]["z"]))
			hud.lit = i + 1
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
			motion.on_pickup(n["node"], player, streak)
			Input.vibrate_handheld(HAPTIC_COIN_MS)

	# --- death: ONE rules query (rules.gd decides; meshes are visual only)
	var cause := Rules.death_cause(field, player.prev_position, player.position,
		player.on_ground, z_back, _prev_ht, ht)
	_prev_ht = ht
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
	for h in field.hazards:
		h.update_state(ht)


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
	if Rules.lives_enabled(knobs):
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
	_freeze = DEATH_FREEZE_LIVES_S if Rules.lives_enabled(knobs) else DEATH_FREEZE_S
	player.creature.play_death(_freeze)
	Progress.record_best(Rules.LEVEL, BeatClock.song_time())
	if Rules.lives_enabled(knobs) and lives <= 0:
		_game_over()


# Out of lives (level 2+): the minimal death screen — score, how far,
# retry. No roast text, no share screen yet (addendum 4 section 6).
func _game_over() -> void:
	state = State.GAMEOVER
	_end_shown = 0.0
	score = current_score()
	Progress.record_score(Rules.LEVEL, score)
	hud.hide_word()
	status.text = "OUT OF LIVES\ndied at %d%%   ·   deaths %d   ·   score %d\nTAP TO RETRY FROM LEVEL 1" % [
		int(round(BeatClock.progress_of(furthest_t) * 100.0)), deaths, score]


func _rewind() -> void:
	var t := BeatClock.start_offset
	var x := 0.0
	var z := START_Z
	if checkpoint >= 0:
		var cp: Dictionary = field.checkpoints[checkpoint]
		t = float(cp["resume_t"])
		x = float(cp["x"])
		z = float(cp["z"])
	player.reset_to(x, z)
	player.dead = false
	player.creature.play_respawn()
	motion.on_rewind(_death_z, z)
	FrameMeter.note("rewind (song seek)")
	BeatClock.seek(t)
	var z_back := BeatClock.z_at(t)
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


func _update_hud() -> void:
	if state == State.WAIT:
		return
	if Rules.lives_enabled(knobs):
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
