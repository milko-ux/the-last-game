extends Hazard
# ============================================================
# LINE HAZARD — slides back and forth between two points.
#
# Covers both "patrol" (slower, you can jump it) and "sweep"
# (faster, you must jump it). They differ only in speed.
# Low, so jumping clears them.
# ============================================================

var point_a := Vector2.ZERO
var point_b := Vector2.ZERO


func _configure(data: Dictionary) -> void:
	point_a = Iso.cell_center(int(data["a"].x), int(data["a"].y))
	point_b = Iso.cell_center(int(data["b"].x), int(data["b"].y))
	world_pos = point_a


func tick(_delta: float, elapsed: float, _player_pos: Vector2) -> void:
	# Ping-pong 0 -> 1 -> 0 along the line.
	var t: float = fmod(elapsed * speed * 0.5, 2.0)
	if t > 1.0:
		t = 2.0 - t
	world_pos = point_a.lerp(point_b, t)
	queue_redraw()


func _draw() -> void:
	_draw_shadow()
	_draw_orb(Palette.HAZ, 10.0)
