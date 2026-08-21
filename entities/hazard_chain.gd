extends Hazard
# ============================================================
# CHAIN HAZARD — an orb swinging in a circle around a pivot.
#
# This one is TALL: jumping does not save you, so you have to go
# around it. That's why `jumpable` is false.
# ============================================================

const TETHER_HEIGHT := 34.0

var pivot := Vector2.ZERO
var radius_tiles := 2.0


func _configure(data: Dictionary) -> void:
	jumpable = false
	pivot = Iso.cell_center(int(data["pivot"].x), int(data["pivot"].y))
	radius_tiles = float(data.get("radius", 2.0))
	world_pos = pivot + Vector2(radius_tiles * Iso.TILE, 0.0)


func tick(_delta: float, elapsed: float, _player_pos: Vector2) -> void:
	var ang := elapsed * speed
	world_pos = pivot + Vector2(cos(ang), sin(ang)) * (radius_tiles * Iso.TILE)
	queue_redraw()


func _draw() -> void:
	_draw_shadow()

	# The tether, drawn from the top of the pivot post to the orb.
	var p_base := Iso.to_screen(pivot, 0.0)
	var p_top := Iso.to_screen(pivot, TETHER_HEIGHT)
	var h_top := Iso.to_screen(world_pos, TETHER_HEIGHT)

	draw_line(p_base, p_top, Color(Palette.CHAIN.r, Palette.CHAIN.g, Palette.CHAIN.b, 0.5), 2.0)
	draw_line(p_top, h_top, Color(Palette.CHAIN.r, Palette.CHAIN.g, Palette.CHAIN.b, 0.7), 2.0)

	draw_circle(h_top, RADIUS + 8.0, Color(Palette.CHAIN.r, Palette.CHAIN.g, Palette.CHAIN.b, 0.2))
	draw_circle(h_top, RADIUS, Palette.CHAIN)
	draw_circle(h_top - Vector2(3, 3), RADIUS * 0.35, Color(1, 1, 1, 0.6))
