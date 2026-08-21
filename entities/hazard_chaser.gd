extends Hazard
# ============================================================
# CHASER HAZARD — slowly homes in on the player. Never stops.
#
# Low, so it can be jumped over, but it keeps coming.
# ============================================================

const BASE_SPEED := 115.0


func _configure(data: Dictionary) -> void:
	world_pos = Iso.cell_center(int(data["start"].x), int(data["start"].y))


func tick(delta: float, _elapsed: float, player_pos: Vector2) -> void:
	# delta is 0 on the frame the level loads, which keeps the chaser
	# parked at its spawn point until play actually starts.
	if delta > 0.0:
		var to_player := player_pos - world_pos
		if to_player.length() > 1.0:
			world_pos += to_player.normalized() * BASE_SPEED * speed * delta
	queue_redraw()


func _draw() -> void:
	_draw_shadow()
	_draw_orb(Palette.CHASER, 10.0)
