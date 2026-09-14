extends Node3D
# ============================================================
# HAZARD (base) — shared by slammer / pulser / sweeper.
#
# A hazard is a pure function of song time. update_state(t) is
# called every frame with BeatClock.hazard_time(); the subclass
# poses its meshes and decides whether it is lethal RIGHT NOW.
# No timers, no tweens, no own timeline — so when death rewinds
# the song, the hazard simply re-derives itself. That is what
# makes the whole game deterministic.
#
# Kill test is a box overlap in world space (boxes()) against the
# player's box, so what you see is exactly what kills you.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")

var kind := ""
var bar := 0
var lane := 1
var t_beat := 0.0        # song time of the beat this hazard acts on
var beat_len := 0.5
var dir := 1
var lane_x := 0.0

var _lethal := false


func setup(spec: Dictionary, beat_interval: float) -> void:
	kind = String(spec["kind"])
	bar = int(spec["bar"])
	lane = int(spec["lane"])
	t_beat = float(spec["t"])
	dir = int(spec.get("dir", 1))
	beat_len = beat_interval
	lane_x = (lane - 1) * 2.0
	_build()


func _build() -> void:
	pass


func update_state(_t: float) -> void:
	pass


func is_lethal() -> bool:
	return _lethal


# World-space boxes that kill while is_lethal(). Usually one.
func boxes() -> Array:
	return []


func _box_mesh(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	return mi
