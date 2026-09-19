extends Node
# ============================================================
# MOTION (Phase A brief 3) — everything that makes the world move ON
# THE BEAT, and the weight of the big moments. Presentation only: it
# listens to the same BeatClock signals the game already fires, sets
# a few GLOBAL SHADER UNIFORMS once per frame (no per-tile scripts) and
# drives a handful of nodes (notes, camera, HUD). Nothing here can
# change when anything becomes lethal; rules.gd is untouched.
#
# The uniforms (declared in project.godot [shader_globals]):
#   pr_rim_pulse    rim brightness boost, 0..1 (x0.4 on a downbeat)
#   pr_seam_pulse   seam brightness boost, 0..1 (downbeat only)
#   pr_armed_pulse  armed hazards' mix toward LETHAL_LIVE, 0..0.25
#   pr_rim_amber    rim colour mix toward GOAL, 0..1 (combo / goal)
#   pr_ripple       (z centre, half width, strength, 0): a band of rim
#                   light travelling along the slab (rewind, checkpoint)
#   pr_build_front  z ahead of which tiles are still sunk (level start)
#
# HIT-STOP: during the death freeze the visuals hold. BeatClock keeps
# running so the audio never stutters; this node hands out `vis_time`,
# which stops advancing while `frozen` is true, and everything visual
# reads it instead of the clock.
#
# Every number is a constant at the top; Milko tunes by feel.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")

# --- 1. The world on the beat ---------------------------------------------
const RIM_DOWNBEAT := 0.40          # rim brightens this much on a downbeat...
const RIM_BEAT := 0.15              # ...and this much on the other beats
const RIM_DECAY_BEATS := 1.0        # decays over one beat
const SEAM_DOWNBEAT := 0.20         # seams: downbeat only
const SEAM_DECAY_BEATS := 0.5
const ARMED_PULSE := 0.25           # armed hazards lean toward live by this on each beat of their rate
const ARMED_DECAY_BEATS := 0.6
const NOTE_BOB := 0.15              # units, at the beat rate
const NOTE_NEAR := 4.0              # units (2 tiles): the nearest note within this pulses
const NOTE_NEAR_PULSE := 0.18
# --- 2. Death -----------------------------------------------------------------
const KICK_S := 0.25
const KICK_AMOUNT := 0.35
const KICK_FOV := 0.04
const FLASH_FRAMES := 2
const REWIND_RIPPLE_S := 0.2
const RIPPLE_HALF_WIDTH := 6.0
# --- 3. Pickup and combo --------------------------------------------------------
const PICKUP_COLLAPSE_S := 0.08
const PICKUP_PARTICLES := 8
const COUNTER_POP := 0.30
const COUNTER_POP_S := 0.15
const COMBO_POP := 0.50
const COMBO_BREAK_S := 0.30
# --- 4. Checkpoint and goal --------------------------------------------------
const CHECKPOINT_RIPPLE_S := 0.2
const GOAL_AMBER_BARS := 2
const GOAL_WIDEN_UNITS := 1.5       # each gate post moves outward this much over the last bar
# --- 5. Level start ---------------------------------------------------------------
const BUILD_AHEAD := Mats.FADE_AHEAD_START   # tiles rise as they enter fade range
const PROGRESS_FILL_S := 1.0
# --- 6. Camera --------------------------------------------------------------------
const NOD_DEG := 1.5

var frozen := false
var vis_time := 0.0                 # song time as the visuals see it (holds during hit-stop)
var combo_scale := 1.0              # read by the scene's HUD labels
var counter_scale := 1.0
var combo_alpha := 1.0

var _rim := 0.0
var _seam := 0.0
var _armed := 0.0
var _amber := 0.0
var _amber_hold_until := -1.0
var _amber_pulse_beat := -1
var _ripple_t := -1.0
var _ripple_from := 0.0
var _ripple_to := 0.0
var _ripple_dur := 0.2
var _counter_t := 99.0
var _combo_t := 99.0
var _combo_break_t := 99.0
var _combo_broken := false
var _progress_t := 99.0
var _build_front := -1e9
var _nod := 0.0
var _last_delta := 0.0

var _burst: CPUParticles3D
var _collapsing: Array = []
var _flashed: Array = []            # [node, material] pairs to restore
var _flash_frames := 0


func _ready() -> void:
	BeatClock.beat.connect(_on_beat)
	BeatClock.downbeat.connect(_on_downbeat)
	_build_burst()
	_push_uniforms()


# ------------------------------------------------------------
# Beat listeners
# ------------------------------------------------------------
func _on_beat(index: int) -> void:
	if frozen:
		return
	# The downbeat handler runs for the same beat and overrides these.
	_rim = maxf(_rim, RIM_BEAT / RIM_DOWNBEAT)
	# Armed hazards count down on every beat of their rate: the pulse grows
	# toward the period's last beat, so the wait visibly ends on a beat.
	var period: int = maxi(BeatClock.period_beats, 1)
	var into := posmod(index - BeatClock.first_bar_beat, period)
	_armed = (0.5 + 0.5 * float(into + 1) / float(period))


func _on_downbeat(bar: int) -> void:
	if frozen:
		return
	_rim = 1.0
	_seam = 1.0
	_nod = 1.0
	if _amber_hold_until > BeatClock.song_time():
		_amber = 1.0


# ------------------------------------------------------------
# Events from the scene
# ------------------------------------------------------------
func on_death(killer: Node, kill_pos: Vector3, player_pos: Vector3) -> void:
	frozen = true
	var rig = get_parent().get_node_or_null("CameraRig")
	if rig != null:
		var away := player_pos - kill_pos
		away.y = 0.0
		rig.kick(KICK_S, KICK_AMOUNT, KICK_FOV, away.normalized() if away.length() > 0.01 else Vector3.ZERO)
	_flash(killer)
	_combo_break_t = 0.0
	_combo_broken = true


func on_rewind(from_z: float, to_z: float) -> void:
	frozen = false
	_ripple_from = from_z
	_ripple_to = to_z
	_ripple_dur = REWIND_RIPPLE_S
	_ripple_t = 0.0
	_build_front = -1e9


# The note collapses onto the player over PICKUP_COLLAPSE_S, then bursts.
func on_pickup(note_node: Node3D, player: Node3D, streak: int) -> void:
	_counter_t = 0.0
	_combo_broken = false
	if streak >= 2:
		_combo_t = 0.0
		_amber_hold_until = BeatClock.song_time() + BeatClock.beat_interval
		_amber = 1.0
	_collapsing.append({"node": note_node, "player": player, "t": 0.0, "from": note_node.global_position})


func _tick_collapses(delta: float) -> void:
	var keep := []
	for c in _collapsing:
		c["t"] += delta
		var node: Node3D = c["node"]
		var u: float = clampf(c["t"] / PICKUP_COLLAPSE_S, 0.0, 1.0)
		var target: Vector3 = c["player"].global_position + Vector3(0.0, 1.0, 0.0)
		node.global_position = c["from"].lerp(target, u)
		node.scale = Vector3.ONE * (1.0 - 0.9 * u)
		if u >= 1.0:
			node.visible = false
			_burst.global_position = target
			_burst.restart()
		else:
			keep.append(c)
	_collapsing = keep


func on_checkpoint(z: float) -> void:
	_ripple_from = z
	_ripple_to = z + BeatClock.BAR_UNITS * 2.0
	_ripple_dur = CHECKPOINT_RIPPLE_S
	_ripple_t = 0.0


func on_goal() -> void:
	_amber_hold_until = BeatClock.song_time() + BeatClock.beat_interval * 4.0 * GOAL_AMBER_BARS
	_amber = 1.0


func on_level_start() -> void:
	_progress_t = 0.0


# ------------------------------------------------------------
# Per frame
# ------------------------------------------------------------
func _process(delta: float) -> void:
	_last_delta = delta
	var beat := BeatClock.beat_interval
	if not frozen:
		vis_time = BeatClock.song_time()
		_rim = maxf(0.0, _rim - delta / (beat * RIM_DECAY_BEATS))
		_seam = maxf(0.0, _seam - delta / (beat * SEAM_DECAY_BEATS))
		_armed = maxf(0.0, _armed - delta / (beat * ARMED_DECAY_BEATS))
		_nod = maxf(0.0, _nod - delta / (beat * 4.0))
		if _amber_hold_until > BeatClock.song_time():
			_amber = maxf(_amber, 0.6)
		_amber = maxf(0.0, _amber - delta / beat)
		if _ripple_t >= 0.0:
			_ripple_t += delta
			if _ripple_t > _ripple_dur + 0.05:
				_ripple_t = -1.0
	_tick_collapses(delta)
	_counter_t += delta
	_combo_t += delta
	_combo_break_t += delta
	_progress_t += delta
	counter_scale = 1.0 + COUNTER_POP * _settle(_counter_t, COUNTER_POP_S)
	combo_scale = 1.0 + COMBO_POP * _settle(_combo_t, COUNTER_POP_S)
	combo_alpha = 1.0 - clampf(_combo_break_t / COMBO_BREAK_S, 0.0, 1.0) if _combo_broken else 1.0
	if _flash_frames > 0:
		_flash_frames -= 1
		if _flash_frames == 0:
			_unflash()
	_push_uniforms()


func _push_uniforms() -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_set("pr_rim_pulse", _rim * RIM_DOWNBEAT)
	rs.global_shader_parameter_set("pr_seam_pulse", _seam * SEAM_DOWNBEAT)
	rs.global_shader_parameter_set("pr_armed_pulse", _armed * ARMED_PULSE)
	rs.global_shader_parameter_set("pr_rim_amber", _amber)
	var ripple := Vector4(0.0, 0.0, 0.0, 0.0)
	if _ripple_t >= 0.0:
		var u := clampf(_ripple_t / _ripple_dur, 0.0, 1.0)
		ripple = Vector4(lerpf(_ripple_from, _ripple_to, u), RIPPLE_HALF_WIDTH, 1.0 - u * 0.5, 0.0)
	rs.global_shader_parameter_set("pr_ripple", ripple)
	rs.global_shader_parameter_set("pr_build_front", _build_front)


# The build front for the level start (section 5): tiles ahead of it are
# still sunk. Called by the scene with the window's back edge.
func set_window(z_back: float) -> void:
	_build_front = maxf(_build_front, z_back + BUILD_AHEAD)


# Progress-bar fill for the first second of a run (section 5).
func progress_fill(actual: float) -> float:
	if _progress_t >= PROGRESS_FILL_S:
		return actual
	return actual * _ease(_progress_t / PROGRESS_FILL_S)


# Notes bob at the beat rate and turn once per bar; the nearest one
# within two tiles of the player pulses on the beat (section 1).
func animate_notes(notes: Array, player_pos: Vector3) -> void:
	var beat := BeatClock.beat_interval
	var phase := vis_time / beat
	var spin := TAU * fmod(vis_time / (beat * 4.0), 1.0)
	var nearest: Variant = null
	var nearest_d := NOTE_NEAR
	for n in notes:
		if n["taken"]:
			continue
		var node: Node3D = n["node"]
		if absf(float(n["z"]) - player_pos.z) > 24.0:
			continue
		node.position.y = 1.0 + NOTE_BOB * sin(TAU * phase + float(n["x"]))
		node.rotation.y = spin
		node.scale = Vector3.ONE
		var d := Vector2(float(n["x"]) - player_pos.x, float(n["z"]) - player_pos.z).length()
		if d < nearest_d:
			nearest_d = d
			nearest = node
	if nearest != null:
		var p := 1.0 - fmod(phase, 1.0)
		nearest.scale = Vector3.ONE * (1.0 + NOTE_NEAR_PULSE * p * p)


# The camera's nod: 1.5 degrees forward on the downbeat, decaying over
# the bar (section 6). Radians, for the rig.
func nod() -> float:
	return deg_to_rad(NOD_DEG) * _nod


# ------------------------------------------------------------
# Death flash: the killer goes white for two frames (section 2).
# ------------------------------------------------------------
func _flash(killer: Node) -> void:
	_unflash()
	if killer == null:
		return
	var white := Mats.white_flat()
	for mi in _meshes_of(killer):
		_flashed.append([mi, mi.material_override])
		mi.material_override = white
	_flash_frames = FLASH_FRAMES


func _unflash() -> void:
	for pair in _flashed:
		if is_instance_valid(pair[0]):
			pair[0].material_override = pair[1]
	_flashed.clear()


func _meshes_of(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out += _meshes_of(c)
	return out


# ------------------------------------------------------------
# Pickup burst: 8 amber particles, one shared emitter (section 3).
# ------------------------------------------------------------
func _build_burst() -> void:
	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = PICKUP_PARTICLES
	_burst.lifetime = 0.35
	_burst.explosiveness = 1.0
	_burst.direction = Vector3.UP
	_burst.spread = 180.0
	_burst.initial_velocity_min = 4.0
	_burst.initial_velocity_max = 6.0
	_burst.gravity = Vector3(0.0, -6.0, 0.0)
	_burst.scale_amount_min = 0.5
	_burst.scale_amount_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_burst.scale_amount_curve = curve
	var ball := SphereMesh.new()
	ball.radius = 0.16
	ball.height = 0.32
	ball.radial_segments = 6
	ball.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = WorldPalette.GOAL
	ball.material = mat
	_burst.mesh = ball
	_burst.top_level = true
	add_child(_burst)


# 1 at t = 0, settling to 0 over `dur` with one bounce.
static func _settle(t: float, dur: float) -> float:
	if t < 0.0 or t >= dur:
		return 0.0
	var u := t / dur
	return cos(u * PI * 1.5) * (1.0 - u)


static func _ease(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)
