extends Node2D
# ============================================================
# BOARD — draws the static world: floor tiles, pits, wall cubes
# and the goal marker.
#
# It's a separate node from the entities so the draw order is
# guaranteed: board first, then hazards and the player on top,
# then the UI layer above everything.
# ============================================================

const TEX_FLOOR := preload("res://assets/rock_floor.png")
const TEX_WALL := preload("res://assets/rock_wall.png")
const TEX_UNDERSIDE := preload("res://assets/island_underside.png")

# How many world pixels one repeat of each texture covers. Bigger = the
# rock pattern looks larger and repeats less often.
const FLOOR_TEX_WORLD := 384.0
# The wall faces are squashed by the isometric angle, so their texture
# needs a much larger world scale than the floor or the rock detail
# compresses into vertical stripes.
const WALL_TEX_WORLD := 900.0
# How much of the texture's height one wall face shows. Tuned so the
# rock reads at roughly 1:1 instead of being stretched.
const WALL_TEX_V := 0.09

# The source art is mid-grey — brighter than this game wants. These tints
# multiply it down so the rock stays dark and the neon is still the
# brightest thing on screen. Raise them to lighten the rock.
# The light/mid/dark relationship matches the old flat colours: tops
# catch the most light, the right-hand faces are deepest in shadow.
const TINT_FLOOR := Color(0.40, 0.45, 0.55)
const TINT_WALL_TOP := Color(0.46, 0.50, 0.60)
const TINT_WALL_LEFT := Color(0.30, 0.33, 0.41)
const TINT_WALL_RIGHT := Color(0.22, 0.25, 0.32)
const TINT_UNDERSIDE := Color(0.42, 0.47, 0.57)

var grid: Array = []
var goal_pos := Vector2.ZERO

# Drives the goal marker's gentle bobbing.
var pulse := 0.0


func _ready() -> void:
	# Lets UVs run past 1.0 so one texture tiles across the whole board
	# instead of being squashed into every single tile.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func setup(new_grid: Array, new_goal: Vector2) -> void:
	grid = new_grid
	goal_pos = new_goal
	queue_redraw()


func cell_char(col: int, row: int) -> String:
	if row < 0 or row >= grid.size():
		return "#"
	var line: String = grid[row]
	if col < 0 or col >= line.length():
		return "#"
	return line[col]


func is_wall(col: int, row: int) -> bool:
	return cell_char(col, row) == "#"


func _draw() -> void:
	if grid.is_empty():
		return
	# Underside first so the platform's own rock sides cover its flat
	# top edge — only the hanging part is ever visible.
	_draw_underside()
	_draw_floor()
	_draw_walls()
	_draw_goal()


# The island underside art is drawn front-on with a straight top edge,
# while the board is isometric. Rather than fight that, we line its
# widest point up with the board's widest point and let the board's
# own walls hide the join.
func _draw_underside() -> void:
	var span_x := float(Iso.cols + Iso.rows) * Iso.TILE * Iso.ISO_X
	var mid_y := float(Iso.cols + Iso.rows) * Iso.TILE * Iso.ISO_Y * 0.5
	var origin := Iso.origin()

	# The board's centre of mass and its lowest corner are NOT in the same
	# place once it's skewed into isometric. The art is symmetrical, so we
	# hang it between the two: under the mass, but pulled toward the point
	# the platform actually dips to.
	var centroid_x := origin.x + float(Iso.cols - Iso.rows) * Iso.TILE * Iso.ISO_X * 0.5
	var low_x := origin.x + float(Iso.cols - Iso.rows) * Iso.TILE * Iso.ISO_X
	var centre_x: float = lerp(centroid_x, low_x, 0.25)

	# Why 0.66 and not full width: the art has a STRAIGHT top edge, but the
	# board is a rhombus whose thickness tapers to nothing at its left and
	# right corners. A straight edge can only hide where there is thickness
	# to hide behind, so the island has to be narrower than the board or the
	# top edge shows as a hard horizontal line across the screen.
	var w := span_x * 0.66
	var left_x := centre_x - w * 0.5
	var top_y := origin.y + mid_y * 1.08
	var h := w * float(TEX_UNDERSIDE.get_height()) / float(TEX_UNDERSIDE.get_width())

	draw_texture_rect(TEX_UNDERSIDE, Rect2(Vector2(left_x, top_y), Vector2(w, h)),
		false, TINT_UNDERSIDE)


# UVs are derived from WORLD position, not from the tile, so the rock
# pattern flows continuously across neighbouring tiles instead of
# restarting (and showing a seam) on every one.
func _world_uvs(x0: float, y0: float, x1: float, y1: float, scale: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x0 / scale, y0 / scale),
		Vector2(x1 / scale, y0 / scale),
		Vector2(x1 / scale, y1 / scale),
		Vector2(x0 / scale, y1 / scale),
	])


func _draw_floor() -> void:
	for row in range(Iso.rows):
		for col in range(Iso.cols):
			var c := cell_char(col, row)
			if c == "#":
				continue
			var quad := Iso.tile_quad(col, row, 0.0)
			var outline := PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]])
			if c == "O":
				# Pits stay flat black so they read as holes, not rock.
				draw_colored_polygon(quad, Palette.PIT)
				draw_polyline(outline, Color(Palette.HAZ.r, Palette.HAZ.g, Palette.HAZ.b, 0.35), 1.5)
			else:
				var x0 := col * Iso.TILE
				var y0 := row * Iso.TILE
				draw_colored_polygon(quad, TINT_FLOOR,
					_world_uvs(x0, y0, x0 + Iso.TILE, y0 + Iso.TILE, FLOOR_TEX_WORLD),
					TEX_FLOOR)
				draw_polyline(outline, Palette.FLOOR_LINE, 1.0)


func _draw_walls() -> void:
	# Back to front: a smaller (col + row) is further away.
	var cells := []
	for row in range(Iso.rows):
		for col in range(Iso.cols):
			if is_wall(col, row):
				cells.append({"c": col, "r": row})
	cells.sort_custom(func(a, b): return (a["c"] + a["r"]) < (b["c"] + b["r"]))
	for cell in cells:
		_draw_cube(cell["c"], cell["r"])


func _draw_cube(col: int, row: int) -> void:
	var x0 := col * Iso.TILE
	var y0 := row * Iso.TILE
	var x1 := x0 + Iso.TILE
	var y1 := y0 + Iso.TILE
	var h := Iso.WALL_H

	# Vertical faces: u runs along the wall, v runs down its height.
	var v_top := 0.0
	var v_bottom := WALL_TEX_V

	# Front-right face (the +x side)
	if not is_wall(col + 1, row):
		draw_colored_polygon(PackedVector2Array([
			Iso.to_screen(Vector2(x1, y0), h),
			Iso.to_screen(Vector2(x1, y1), h),
			Iso.to_screen(Vector2(x1, y1), 0.0),
			Iso.to_screen(Vector2(x1, y0), 0.0),
		]), TINT_WALL_RIGHT, PackedVector2Array([
			Vector2(y0 / WALL_TEX_WORLD, v_top),
			Vector2(y1 / WALL_TEX_WORLD, v_top),
			Vector2(y1 / WALL_TEX_WORLD, v_bottom),
			Vector2(y0 / WALL_TEX_WORLD, v_bottom),
		]), TEX_WALL)

	# Front-left face (the +y side)
	if not is_wall(col, row + 1):
		draw_colored_polygon(PackedVector2Array([
			Iso.to_screen(Vector2(x0, y1), h),
			Iso.to_screen(Vector2(x1, y1), h),
			Iso.to_screen(Vector2(x1, y1), 0.0),
			Iso.to_screen(Vector2(x0, y1), 0.0),
		]), TINT_WALL_LEFT, PackedVector2Array([
			Vector2(x0 / WALL_TEX_WORLD, v_top),
			Vector2(x1 / WALL_TEX_WORLD, v_top),
			Vector2(x1 / WALL_TEX_WORLD, v_bottom),
			Vector2(x0 / WALL_TEX_WORLD, v_bottom),
		]), TEX_WALL)

	var top := Iso.tile_quad(col, row, h)
	draw_colored_polygon(top, TINT_WALL_TOP,
		_world_uvs(x0, y0, x1, y1, FLOOR_TEX_WORLD), TEX_FLOOR)

	# Neon edges only where the wall is actually exposed.
	if not is_wall(col, row - 1):
		draw_line(top[0], top[1], Palette.glow(Palette.EDGE, 2.5), 2.0)
	if not is_wall(col + 1, row):
		draw_line(top[1], top[2], Palette.glow(Palette.EDGE, 2.5), 2.0)
	if not is_wall(col, row + 1):
		draw_line(top[2], top[3], Palette.glow(Palette.EDGE, 2.5), 2.0)
	if not is_wall(col - 1, row):
		draw_line(top[3], top[0], Palette.glow(Palette.EDGE, 2.5), 2.0)

	# Vertical glow down the exposed front corner.
	if not is_wall(col + 1, row) and not is_wall(col, row + 1):
		draw_line(
			Iso.to_screen(Vector2(x1, y1), h),
			Iso.to_screen(Vector2(x1, y1), 0.0),
			Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.5) * Color(1.6, 1.6, 1.6, 1.0), 1.5)


func _draw_goal() -> void:
	var base := Iso.to_screen(goal_pos, 0.0)
	var lift := 12.0 + sin(pulse * 2.5) * 4.0
	var top := Iso.to_screen(goal_pos, lift)

	draw_circle(base, 16.0, Color(0, 0, 0, 0.45))

	var s := 15.0
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, -s), top + Vector2(s * 0.8, 0),
		top + Vector2(0, s), top + Vector2(-s * 0.8, 0)
	]), Palette.glow(Palette.GOAL, 1.2))
	draw_circle(top, 24.0, Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.15))
