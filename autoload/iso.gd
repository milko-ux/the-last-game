extends Node
# ============================================================
# ISO — the isometric projection, shared by everything that draws.
#
# The world underneath is a plain flat grid (columns and rows).
# "Isometric" is only how we DRAW it — that's what keeps the level
# files readable as text. This singleton is the one place that
# converts a world position into a point on screen, so the player,
# the hazards and the board all agree on where things are.
#
# It's an autoload (a "singleton"): Godot loads it once at startup
# and any script can call Iso.to_screen(...) without wiring it up.
# ============================================================

const TILE := 64.0
const ISO_X := 0.5
const ISO_Y := 0.25
const WALL_H := 42.0

# Small manual nudge so the board sits optically centred rather than
# mathematically centred. Preserves the framing Milko already signed off on.
const VERTICAL_NUDGE := 6.0

# Size of the board currently being played. Set by the level loader so
# the view stays centred for any level size, not just the original 15x8.
var cols := 15
var rows := 8


func set_board_size(c: int, r: int) -> void:
	cols = c
	rows = r


# Where world (0,0) lands on screen, chosen so the whole board is centred.
func origin() -> Vector2:
	var screen: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(
		screen.x * 0.5 - float(cols - rows) * TILE * ISO_X * 0.5,
		screen.y * 0.5 - float(cols + rows) * TILE * ISO_Y * 0.5 + VERTICAL_NUDGE
	)


# world position (+ height z) -> screen point
func to_screen(w: Vector2, z: float = 0.0) -> Vector2:
	return Vector2(
		(w.x - w.y) * ISO_X,
		(w.x + w.y) * ISO_Y - z
	) + origin()


func cell_center(col: int, row: int) -> Vector2:
	return Vector2((col + 0.5) * TILE, (row + 0.5) * TILE)


# The on-screen offset between two world points. Same projection as
# to_screen() but without the origin, since that cancels out for a
# difference. Used for hit tests that need to match what's DRAWN.
func project_offset(w: Vector2) -> Vector2:
	return Vector2((w.x - w.y) * ISO_X, (w.x + w.y) * ISO_Y)


# The four screen corners of one tile, at height z.
func tile_quad(col: int, row: int, z: float) -> PackedVector2Array:
	var x0 := col * TILE
	var y0 := row * TILE
	var x1 := x0 + TILE
	var y1 := y0 + TILE
	return PackedVector2Array([
		to_screen(Vector2(x0, y0), z),
		to_screen(Vector2(x1, y0), z),
		to_screen(Vector2(x1, y1), z),
		to_screen(Vector2(x0, y1), z),
	])


# Converts a drag on screen into a direction in the world (undoes the skew).
func screen_dir_to_world(d: Vector2) -> Vector2:
	var wx := d.x / (2.0 * ISO_X) + d.y / (2.0 * ISO_Y)
	var wy := -d.x / (2.0 * ISO_X) + d.y / (2.0 * ISO_Y)
	return Vector2(wx, wy).normalized()
