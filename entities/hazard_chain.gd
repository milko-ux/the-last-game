extends Hazard
# ============================================================
# CHAIN HAZARD — orbs swinging in a circle around a pivot.
#
# TALL: jumping does not save you, so you have to go around.
# That's why `jumpable` is false.
#
# "arms" puts more than one orb on the same pivot, evenly spaced.
# Two arms turn a gap you can wait out into a rotating wall.
# ============================================================

const TETHER_HEIGHT := 34.0

var pivot := Vector2.ZERO
var radius_tiles := 2.0
var arms := 1

# Where each orb is right now. world_pos tracks the first one so the
# shared trail still has something to follow.
var _orbs: Array[Vector2] = []


func _configure(data: Dictionary) -> void:
	jumpable = false
	pivot = Iso.cell_center(int(data["pivot"].x), int(data["pivot"].y))
	radius_tiles = float(data.get("radius", 2.0))
	arms = maxi(1, int(data.get("arms", 1)))
	_recalc(0.0)


func _move(_delta: float, elapsed: float, _player_pos: Vector2) -> void:
	_recalc(elapsed)


func _recalc(elapsed: float) -> void:
	_orbs.clear()
	var r := radius_tiles * Iso.TILE
	for i in range(arms):
		var ang := elapsed * speed + TAU * float(i) / float(arms)
		_orbs.append(pivot + Vector2(cos(ang), sin(ang)) * r)
	world_pos = _orbs[0]


# Every arm can kill, not just the one the trail follows.
func hits(player_pos: Vector2, player_r: float, player_airborne: bool) -> bool:
	if jumpable and player_airborne:
		return false
	for orb in _orbs:
		if Iso.project_offset(orb - player_pos).length() < RADIUS + player_r:
			return true
	return false


func _draw() -> void:
	_draw_trail(Palette.CHAIN, TETHER_HEIGHT)

	var p_base := Iso.to_screen(pivot, 0.0)
	var p_top := Iso.to_screen(pivot, TETHER_HEIGHT)
	draw_line(p_base, p_top, Color(Palette.CHAIN.r, Palette.CHAIN.g, Palette.CHAIN.b, 0.5), 2.0)

	for orb in _orbs:
		draw_circle(Iso.to_screen(orb, 0.0), RADIUS * 0.8, Color(0, 0, 0, 0.5))
		var h_top := Iso.to_screen(orb, TETHER_HEIGHT)
		draw_line(p_top, h_top, Color(Palette.CHAIN.r, Palette.CHAIN.g, Palette.CHAIN.b, 0.7), 2.0)
		draw_circle(h_top, RADIUS + 8.0, Color(Palette.CHAIN.r, Palette.CHAIN.g, Palette.CHAIN.b, 0.2))
		draw_circle(h_top, RADIUS, Palette.glow(Palette.CHAIN, 1.3))
		draw_circle(h_top - Vector2(3, 3), RADIUS * 0.35, Color(1, 1, 1, 0.6))
