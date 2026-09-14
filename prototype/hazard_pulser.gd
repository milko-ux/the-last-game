extends "res://prototype/hazard3d.gd"
# ============================================================
# PULSER — a pillar in one lane that is UP (lethal) for half a
# beat starting on the beat, then down. A dark magenta plate on
# the floor marks it at all times so the pattern is readable
# ahead. Too tall to jump: landing on a raised pulser is death.
# ============================================================

const W := 1.8
const H := 3.0
const D := 1.0
const RISE_S := 0.04
const FALL_S := 0.08
const UP_BEATS := 0.5

var _plate: MeshInstance3D
var _pillar: MeshInstance3D
var _s := 0.0


func _build() -> void:
	position.x = lane_x
	_plate = _box_mesh(Vector3(1.9, 0.08, 1.2), Mats.magenta_dim())
	_plate.position.y = 0.04
	_pillar = _box_mesh(Vector3(W, H, D), Mats.magenta())
	_pillar.visible = false


func update_state(t: float) -> void:
	var dt := t - t_beat
	var up := beat_len * UP_BEATS
	if dt < 0.0:
		_s = 0.0
	elif dt < RISE_S:
		_s = dt / RISE_S
	elif dt < up:
		_s = 1.0
	elif dt < up + FALL_S:
		_s = 1.0 - (dt - up) / FALL_S
	else:
		_s = 0.0
	_pillar.visible = _s > 0.001
	_pillar.scale.y = maxf(_s, 0.001)
	_pillar.position.y = H * 0.5 * _s
	_lethal = _s > 0.35


func boxes() -> Array:
	var gp := global_position
	return [AABB(Vector3(gp.x - W * 0.5, gp.y, gp.z - D * 0.5), Vector3(W, H * _s, D))]
