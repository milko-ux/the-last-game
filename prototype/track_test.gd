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

const LIVES := 3
const DEATH_FREEZE_S := 0.35
# The first tap unlocks browser audio; give the AudioContext a beat to
# resume before the clock and the music start together.
const START_DELAY_S := 0.20
# Same haptics the 2D game uses (main.gd).
const HAPTIC_DEATH_MS := 35
const HAPTIC_WIN_MS := 80
const HAPTIC_COIN_MS := 25
const HIT_RANGE_Z := 12.0
const NOTE_RADIUS := 1.0
const COMBO_CAP := 4
const START_Z := 8.0

enum State { WAIT, STARTING, RUN, DEAD, WON }

@onready var music: AudioStreamPlayer = $Music
@onready var field: Node3D = $Field
@onready var player: CharacterBody3D = $Player
@onready var rig: Node3D = $CameraRig
@onready var ui: Node2D = $UI/Screen
@onready var status: Label = $UI/Status
@onready var score_label: Label = $UI/Score
@onready var debug: Label = $UI/Debug

var state := State.WAIT
var lives := LIVES
var deaths := 0
var checkpoint := -1        # index into field.checkpoints; -1 = song start
var notes := 0
var streak := 0             # notes since the last death
var score := 0
var _freeze := 0.0
var _start_delay := 0.0
var _run_started_ms := 0
var _fair_warning := ""


func _ready() -> void:
	field.build()
	if not field.fairness["ok"]:
		_fair_warning = "FAIRNESS CHECK FAILED (%d) — see log" % field.fairness["problems"].size()
	player.reset_to(0.0, START_Z)
	ui.level_count = 1
	ui.leave_menu()
	ui.jump_pressed.connect(_on_jump)
	status.text = "TAP TO START"
	debug.text = _fair_warning
	score_label.text = ""
	_update_world(BeatClock.hazard_time(), 0.0)
	rig.set_window(0.0)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if state == State.RUN:
			_on_jump()
	if state != State.WAIT:
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if pressed:
		state = State.STARTING
		_start_delay = START_DELAY_S
		status.text = ""


func _process(delta: float) -> void:
	match state:
		State.STARTING:
			_start_delay -= delta
			if _start_delay <= 0.0:
				BeatClock.start(music)
				_run_started_ms = Time.get_ticks_msec()
				state = State.RUN
		State.RUN:
			_tick_run(delta)
		State.DEAD:
			_freeze -= delta
			if _freeze <= 0.0:
				_rewind()
	ui.set_status(0, 1, lives, deaths, state == State.DEAD)
	_update_hud()


func _tick_run(delta: float) -> void:
	var t := BeatClock.song_time()
	var ht := BeatClock.hazard_time()
	var z_back := BeatClock.z_at(t)
	var z_front := z_back + Rules.WINDOW_DEPTH

	player.move_dir = _move_input()
	player.tick(delta, z_front, field)
	rig.set_window(z_back)
	_update_world(ht, z_back)

	for i in field.checkpoints.size():
		if i > checkpoint and t >= float(field.checkpoints[i]["t"]):
			checkpoint = i
			field.mark_checkpoint(i)
			Input.vibrate_handheld(HAPTIC_COIN_MS)

	for n in field.notes:
		if n["taken"] or player.y > 1.8:
			continue
		if Vector2(n["x"] - player.position.x, n["z"] - player.position.z).length() < NOTE_RADIUS:
			n["taken"] = true
			n["node"].visible = false
			streak += 1
			notes += 1
			score += mini(streak, COMBO_CAP)
			Input.vibrate_handheld(HAPTIC_COIN_MS)

	# --- death checks: the beat caught you / fell / the floor / a hazard
	if player.position.z < z_back:
		_die()
		return
	if player.fell():
		_die()
		return
	if player.on_ground and field.tile_state_at(player.position.x, player.position.z, ht) == field.TileState.LETHAL:
		_die()
		return
	var pb: AABB = player.bounds()
	for h in field.hazards:
		if not h.is_lethal():
			continue
		if absf(h.position.z - player.position.z) > HIT_RANGE_Z:
			continue
		for b in h.boxes():
			if b.intersects(pb):
				_die()
				return

	player.look_at_danger(_nearest_danger(ht))

	if player.position.z >= field.goal_z:
		_win()


func _update_world(ht: float, z_back: float) -> void:
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
func _move_input() -> Vector2:
	var v := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if ui.stick_touch_id != -1:
		var drag: Vector2 = ui.stick_current - ui.stick_origin
		v = drag.normalized() if drag.length() > ui.STICK_DEADZONE else Vector2.ZERO
	return Vector2(v.x, -v.y)


func _on_jump() -> void:
	if state != State.RUN:
		return
	if player.jump():
		ui.confirm_jump()


func _die() -> void:
	state = State.DEAD
	lives -= 1
	deaths += 1
	streak = 0
	player.dead = true
	player.move_dir = Vector2.ZERO
	Input.vibrate_handheld(HAPTIC_DEATH_MS)
	BeatClock.pause()
	rig.shake()
	_freeze = DEATH_FREEZE_S


func _rewind() -> void:
	var t := 0.0
	var x := 0.0
	var z := START_Z
	if lives <= 0:
		# Out of lives: the loop resets to the very start, notes and all.
		lives = LIVES
		checkpoint = -1
		notes = 0
		score = 0
		field.reset_run()
	elif checkpoint >= 0:
		var cp: Dictionary = field.checkpoints[checkpoint]
		t = float(cp["resume_t"])
		x = float(cp["x"])
		z = float(cp["z"])
	player.reset_to(x, z)
	player.dead = false
	BeatClock.seek(t)
	var z_back := BeatClock.z_at(t)
	rig.set_window(z_back)
	_update_world(BeatClock.hazard_time(), z_back)
	state = State.RUN


func _win() -> void:
	state = State.WON
	player.move_dir = Vector2.ZERO
	Input.vibrate_handheld(HAPTIC_WIN_MS)
	var secs := (Time.get_ticks_msec() - _run_started_ms) / 1000.0
	var time_bonus := maxi(0, 300 - int(maxf(0.0, secs - BeatClock.duration)))
	status.text = "GOAL\nnotes %d   ·   combo x%d   ·   deaths %d\nscore %d  (+%d time bonus)   ·   %.1f s" % [
		notes, mini(maxi(streak, 1), COMBO_CAP), deaths, score + time_bonus, time_bonus, secs]


func _update_hud() -> void:
	if state == State.WAIT:
		return
	score_label.text = "♪ %d   x%d" % [notes, mini(maxi(streak, 1), COMBO_CAP)]
	var line := "bar %d / %d   ·   %.1f s   ·   sync %+d ms" % [
		BeatClock.current_bar(), BeatClock.bar_count(), BeatClock.song_time(),
		int(round(BeatClock.SYNC_OFFSET_S * 1000.0))]
	debug.text = line if _fair_warning.is_empty() else _fair_warning + "\n" + line
