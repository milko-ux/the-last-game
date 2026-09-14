extends Node3D
# ============================================================
# CAMERA RIG — behind and above the player, looking at a point
# ahead so the frame shows what is coming, not the player's back.
#
# z tracks the player exactly (z is time; any lag reads as sync
# error). x follows with a small lag. The only "juice" in Phase R
# is a 2% FOV punch on each downbeat, there so Milko can FEEL the
# beat clock through the camera.
# ============================================================

const OFFSET := Vector3(0.0, 5.5, -8.5)
const LOOK_AHEAD := 4.0
const LOOK_HEIGHT := 0.8
const FOV := 65.0
const X_LERP := 0.12          # per frame at 60 fps; made frame-rate independent below
const PUNCH := 0.02
const SHAKE_S := 0.35
const SHAKE_AMOUNT := 0.12

@export var target_path: NodePath
var _target: Node3D
var _x := 0.0
var _punch := 0.0
var _shake_t := 0.0

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	_target = get_node(target_path)
	cam.fov = FOV
	BeatClock.downbeat.connect(_on_downbeat)
	snap()


func _on_downbeat(_bar: int) -> void:
	_punch = 1.0


func shake() -> void:
	_shake_t = SHAKE_S


# Jump straight to the target (used on rewind so the lag never shows a swing).
func snap() -> void:
	if _target == null:
		return
	_x = _target.position.x
	position = Vector3(_x, 0.0, _target.position.z)
	_aim()


func _process(delta: float) -> void:
	if _target == null:
		return
	var k := 1.0 - pow(1.0 - X_LERP, delta * 60.0)
	_x = lerpf(_x, _target.position.x, k)
	position = Vector3(_x, 0.0, _target.position.z)

	if _punch > 0.0:
		_punch = maxf(0.0, _punch - delta / BeatClock.beat_interval)
	cam.fov = FOV * (1.0 + PUNCH * _punch)

	var off := Vector3.ZERO
	if _shake_t > 0.0:
		_shake_t -= delta
		var s := SHAKE_AMOUNT * (_shake_t / SHAKE_S)
		off = Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
	cam.position = OFFSET + off
	_aim()


func _aim() -> void:
	cam.look_at(global_position + Vector3(0.0, LOOK_HEIGHT, LOOK_AHEAD), Vector3.UP)
