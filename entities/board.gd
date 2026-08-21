extends Node2D
# ============================================================
# BOARD — draws the static world: floor tiles, pits, wall cubes
# and the goal marker.
#
# It's a separate node from the entities so the draw order is
# guaranteed: board first, then hazards and the player on top,
# then the UI layer above everything.
# ============================================================

var grid: Array = []
var goal_pos := Vector2.ZERO

# Drives the goal marker's gentle bobbing.
var pulse := 0.0


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
	_draw_floor()
	_draw_walls()
	_draw_goal()


func _draw_floor() -> void:
	for row in range(Iso.rows):
		for col in range(Iso.cols):
			var c := cell_char(col, row)
			if c == "#":
				continue
			var quad := Iso.tile_quad(col, row, 0.0)
			var outline := PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]])
			if c == "O":
				draw_colored_polygon(quad, Palette.PIT)
				draw_polyline(outline, Color(Palette.HAZ.r, Palette.HAZ.g, Palette.HAZ.b, 0.35), 1.5)
			else:
				draw_colored_polygon(quad, Palette.FLOOR)
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

	# Front-right face (the +x side)
	if not is_wall(col + 1, row):
		draw_colored_polygon(PackedVector2Array([
			Iso.to_screen(Vector2(x1, y0), h),
			Iso.to_screen(Vector2(x1, y1), h),
			Iso.to_screen(Vector2(x1, y1), 0.0),
			Iso.to_screen(Vector2(x1, y0), 0.0),
		]), Palette.WALL_RIGHT)

	# Front-left face (the +y side)
	if not is_wall(col, row + 1):
		draw_colored_polygon(PackedVector2Array([
			Iso.to_screen(Vector2(x0, y1), h),
			Iso.to_screen(Vector2(x1, y1), h),
			Iso.to_screen(Vector2(x1, y1), 0.0),
			Iso.to_screen(Vector2(x0, y1), 0.0),
		]), Palette.WALL_LEFT)

	var top := Iso.tile_quad(col, row, h)
	draw_colored_polygon(top, Palette.WALL_TOP)

	# Neon edges only where the wall is actually exposed.
	if not is_wall(col, row - 1):
		draw_line(top[0], top[1], Palette.EDGE, 2.0)
	if not is_wall(col + 1, row):
		draw_line(top[1], top[2], Palette.EDGE, 2.0)
	if not is_wall(col, row + 1):
		draw_line(top[2], top[3], Palette.EDGE, 2.0)
	if not is_wall(col - 1, row):
		draw_line(top[3], top[0], Palette.EDGE, 2.0)

	# Vertical glow down the exposed front corner.
	if not is_wall(col + 1, row) and not is_wall(col, row + 1):
		draw_line(
			Iso.to_screen(Vector2(x1, y1), h),
			Iso.to_screen(Vector2(x1, y1), 0.0),
			Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.5), 1.5)


func _draw_goal() -> void:
	var base := Iso.to_screen(goal_pos, 0.0)
	var lift := 12.0 + sin(pulse * 2.5) * 4.0
	var top := Iso.to_screen(goal_pos, lift)

	draw_circle(base, 16.0, Color(0, 0, 0, 0.45))

	var s := 15.0
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, -s), top + Vector2(s * 0.8, 0),
		top + Vector2(0, s), top + Vector2(-s * 0.8, 0)
	]), Palette.GOAL)
	draw_circle(top, 24.0, Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.15))
