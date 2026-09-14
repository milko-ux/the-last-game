extends Node3D
# ============================================================
# TRACK TEST — the Phase R run scene. The referee: owns lives,
# deaths, the current checkpoint, and decides death and goal.
#
# Run it with:
#   godot --path . prototype/track_test.tscn
#
# Death rewinds the SONG (BeatClock.seek); the player and every
# hazard re-derive their state from the new time. There is no
# separate respawn logic.
# ============================================================

const LIVES := 3
const DEATH_FREEZE_S := 0.35
# The first tap unlocks browser audio; give the AudioContext a beat to
# resume before the clock and the music start together.
const START_DELAY_S := 0.20
# Same haptics the 2D game uses (main.gd).
const HAPTIC_DEATH_MS := 35
const HAPTIC_WIN_MS := 80
const HAPTIC_COIN_MS := 25
# Hazards further than this from the player along z are skipped in
# the hit test (the sweeper is 8 deep, so keep a margin).
const HIT_RANGE_Z := 12.0

enum State { WAIT, STARTING, RUN, DEAD, WON }

@onready var music: AudioStreamPlayer = $Music
@onready var track: Node3D = $Track
@onready var player: CharacterBody3D = $Player
@onready var rig: Node3D = $CameraRig
@onready var kill_plane: Area3D = $KillPlane
@onready var ui: Node2D = $UI/Screen
@onready var status: Label = $UI/Status
@onready var debug: Label = $UI/Debug

var state := State.WAIT
var lives := LIVES
var deaths := 0
var checkpoint := -1        # index into track.checkpoints; -1 = song start
var _freeze := 0.0
var _start_delay := 0.0
var _run_started_ms := 0


func _ready() -> void:
	track.build()
	player.reset_to(0.0, 0.0)
	ui.level_count = 1
	ui.leave_menu()
	ui.jump_pressed.connect(_on_jump)
	kill_plane.body_entered.connect(_on_kill_plane)
	status.text = "TAP TO START"
	debug.text = ""
	_update_hazards(BeatClock.hazard_time())
	rig.snap()


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
	_update_debug()


func _tick_run(delta: float) -> void:
	var t := BeatClock.song_time()
	player.move_axis = _axis()
	player.tick(delta, BeatClock.z_at(t))
	_update_hazards(BeatClock.hazard_time())

	for i in track.checkpoints.size():
		if i > checkpoint and t >= float(track.checkpoints[i]["t"]):
			checkpoint = i
			track.mark_checkpoint(i)
			Input.vibrate_handheld(HAPTIC_COIN_MS)

	var pb: AABB = player.bounds()
	for h in track.hazards:
		if not h.is_lethal():
			continue
		if absf(h.global_position.z - player.position.z) > HIT_RANGE_Z:
			continue
		for b in h.boxes():
			if b.intersects(pb):
				_die()
				return

	if player.position.z >= track.goal_z:
		_win()


func _update_hazards(t: float) -> void:
	for h in track.hazards:
		h.update_state(t)


# Left/right only. Keyboard for the desktop browser, the glass stick on
# phones. Reads the stick's raw drag so ui.gd stays untouched; past the
# deadzone the normalised direction's x is the axis, same rule as the
# 2D game (full speed, no analogue creep).
func _axis() -> float:
	var a := Input.get_axis("ui_left", "ui_right")
	if ui.stick_touch_id != -1:
		var drag: Vector2 = ui.stick_current - ui.stick_origin
		if drag.length() > ui.STICK_DEADZONE:
			a = drag.normalized().x
	return clampf(a, -1.0, 1.0)


func _on_jump() -> void:
	if state != State.RUN:
		return
	if player.jump():
		ui.confirm_jump()


func _on_kill_plane(_body: Node3D) -> void:
	if state == State.RUN:
		_die()


func _die() -> void:
	state = State.DEAD
	lives -= 1
	deaths += 1
	player.dead = true
	player.move_axis = 0.0
	Input.vibrate_handheld(HAPTIC_DEATH_MS)
	BeatClock.pause()
	rig.shake()
	_freeze = DEATH_FREEZE_S


func _rewind() -> void:
	var t := 0.0
	var x := 0.0
	if lives <= 0:
		# Out of lives: the loop resets to the very start.
		lives = LIVES
		checkpoint = -1
		track.clear_checkpoints()
	elif checkpoint >= 0:
		var cp: Dictionary = track.checkpoints[checkpoint]
		t = float(cp["resume_t"])
		x = (int(cp["lane"]) - 1) * 2.0
	player.reset_to(x, BeatClock.z_at(t))
	player.dead = false
	BeatClock.seek(t)
	_update_hazards(BeatClock.hazard_time())
	rig.snap()
	state = State.RUN


func _win() -> void:
	state = State.WON
	player.move_axis = 0.0
	Input.vibrate_handheld(HAPTIC_WIN_MS)
	var secs := (Time.get_ticks_msec() - _run_started_ms) / 1000.0
	status.text = "GOAL\ntime to goal %.1f s   ·   deaths %d" % [secs, deaths]


func _update_debug() -> void:
	if state == State.WAIT:
		debug.text = ""
		return
	debug.text = "bar %d / %d   ·   %.1f s   ·   sync %+d ms" % [
		BeatClock.current_bar(), BeatClock.bar_count(), BeatClock.song_time(),
		int(round(BeatClock.SYNC_OFFSET_S * 1000.0))]
