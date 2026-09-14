extends "res://prototype/hazard3d.gd"
# ============================================================
# SLAMMER — a magenta bar hovering over one lane that drops onto
# it ON the beat and lifts by the next beat.
#
# Readable from the front: it is always visible hovering, turns
# bright ("armed") one beat early, then slams. While it sits on
# the floor it is low, so a jump clears it; being under it when
# it lands, or walking into it while it is down, kills.
# ============================================================

const W := 1.9
const H := 0.6
const D := 1.0
const HOVER := 3.0          # bottom of the bar while hovering
const DROP_S := 0.10        # the slam itself: fast, lands exactly on the beat
const LETHAL_BELOW := 1.2   # bar bottom under this = it can touch you

var _mesh: MeshInstance3D
var _bottom := HOVER
var _hot := false


func _build() -> void:
	position.x = lane_x
	_mesh = _box_mesh(Vector3(W, H, D), Mats.magenta_dim())
	_mesh.position.y = HOVER + H * 0.5


func update_state(t: float) -> void:
	var dt := t - t_beat
	var hot := dt >= -beat_len and dt < beat_len
	if dt < -DROP_S:
		_bottom = HOVER
	elif dt < 0.0:
		var k := (dt + DROP_S) / DROP_S
		_bottom = HOVER * (1.0 - k * k)
	elif dt < beat_len * 0.5:
		_bottom = 0.0
	elif dt < beat_len:
		var k := (dt - beat_len * 0.5) / (beat_len * 0.5)
		_bottom = HOVER * k * k
	else:
		_bottom = HOVER
	_mesh.position.y = _bottom + H * 0.5
	if hot != _hot:
		_hot = hot
		_mesh.material_override = Mats.magenta() if hot else Mats.magenta_dim()
	_lethal = _bottom < LETHAL_BELOW


func boxes() -> Array:
	var gp := global_position
	return [AABB(Vector3(gp.x - W * 0.5, gp.y + _bottom, gp.z - D * 0.5), Vector3(W, H, D))]
