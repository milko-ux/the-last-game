extends Node3D
# ============================================================
# CAMERA RIG — follows the WINDOW, not the player. Sits high and
# back from the window centre looking at it, so the whole field
# width and about two bars ahead are in frame, and the player is
# seen committing to a route inside it.
#
# z is time, so the rig never lags. The only "juice" is a 2 % FOV
# punch on each downbeat, there so Milko can feel the beat clock.
# ============================================================

const Rules := preload("res://prototype/rules.gd")

const OFFSET := Vector3(0.0, 12.0, -11.0)
const FOV := 60.0
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


func _process(delta: float) -> void:
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - delta / BeatClock.beat_interval)
	cam.fov = FOV * (1.0 + PUNCH * _punch)

	var off := Vector3.ZERO
	if _shake_t > 0.0:
		_shake_t -= delta
		var s := SHAKE_AMOUNT * (_shake_t / SHAKE_S)
		off = Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
	cam.position = OFFSET + off
	cam.look_at(global_position, Vector3.UP)
