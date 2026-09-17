extends Node3D
# ============================================================
# CAMERA RIG — follows the WINDOW, not the player. The camera ORBITS
# the window centre: it sits on a sphere around that point (yaw, pitch,
# distance) and looks straight at it, so the window centre is always
# the centre of the screen and the field's centre line runs through
# the middle of the frame. High, back and to one side, so the whole
# field width and about two bars ahead are in frame and the field
# is seen OBLIQUELY, as in docs/concept/field_monolith.png (addendum
# 4 section 1): the near edge runs diagonally across the lower part
# of the screen, not horizontally.
#
# z is time, so the rig never lags. The only "juice" is a 2 % FOV
# punch on each downbeat, there so Milko can feel the beat clock.
# ============================================================

const Rules := preload("res://prototype/rules.gd")

# The reference angle (addendum 4 section 1). Yaw is measured from the
# field axis, positive = the camera sits to the viewer's RIGHT of the
# axis (world -x). Both constants are meant to be flipped for the
# morning playtest: CAMERA_YAW_DEG = 0.0 gives the old straight view.
const CAMERA_YAW_DEG := 24.0
const CAMERA_PITCH_DEG := 54.0
# Camera v2: wider and further back. By projection at 2400x1080 the
# window's four corners land at x 757-1562, y 268-979, so the 18-unit
# width has ~100 px of margin at the near edge and clears both controls.
# (v1 was distance 26 / FOV 48: the near-right corner was off screen.)
# What lies beyond the window dissolves into the background: see the
# distance fade in flat_mats.gd (depth fog does not work on web).
const CAMERA_DISTANCE := 32.0
const FOV := 55.0
# false: joystick up = down the field regardless of the yaw (world-
# relative). true: joystick up = away from the camera.
const INPUT_CAMERA_RELATIVE := false

const PUNCH := 0.02
const SHAKE_S := 0.35
const SHAKE_AMOUNT := 0.15

var _punch := 0.0
var _shake_t := 0.0
var window_back := 0.0

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	cam.fov = FOV
	BeatClock.downbeat.connect(_on_downbeat)
	set_window(0.0)


func _on_downbeat(_bar: int) -> void:
	_punch = 1.0


func shake() -> void:
	_shake_t = SHAKE_S


func set_window(z_back: float) -> void:
	window_back = z_back
	position = Vector3(0.0, 0.0, z_back + Rules.WINDOW_DEPTH * 0.5)
	# The distance fade in flat_mats.gd is measured from the window.
	RenderingServer.global_shader_parameter_set("pr_window_back", z_back)


# The camera's offset from the look-at point for the reference angle.
static func camera_offset() -> Vector3:
	var yaw := deg_to_rad(CAMERA_YAW_DEG)
	var pitch := deg_to_rad(CAMERA_PITCH_DEG)
	var flat := CAMERA_DISTANCE * cos(pitch)
	return Vector3(-flat * sin(yaw), CAMERA_DISTANCE * sin(pitch), -flat * cos(yaw))


# (screen-right, forward) as the joystick gives it -> the same pair in
# the world frame the player uses (screen-right = world -x when the
# camera looks straight down +z). Only used when INPUT_CAMERA_RELATIVE.
static func screen_to_world_dir(v: Vector2) -> Vector2:
	var yaw := deg_to_rad(CAMERA_YAW_DEG)
	# Camera forward on the ground plane, and its right-hand vector.
	var f := Vector2(sin(yaw), cos(yaw))          # (x, z)
	var r := Vector2(-f.y, f.x)                   # screen-right in world (x, z)
	var w := r * v.x + f * v.y                    # world (x, z)
	return Vector2(-w.x, w.y)                     # player: x = screen-right * -1, y = +z


func _process(delta: float) -> void:
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - delta / BeatClock.beat_interval)
	cam.fov = FOV * (1.0 + PUNCH * _punch)

	var off := Vector3.ZERO
	if _shake_t > 0.0:
		_shake_t -= delta
		var s := SHAKE_AMOUNT * (_shake_t / SHAKE_S)
		off = Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
	cam.position = camera_offset() + off
	cam.look_at(global_position, Vector3.UP)
