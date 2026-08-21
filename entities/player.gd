extends Node2D
# ============================================================
# PLAYER — owns its own position, jump, gravity, wall collision
# and drawing.
#
# The maths here is deliberately IDENTICAL to the version that
# lived in main.gd, so the game feels exactly the same. Only the
# place it lives has changed.
# ============================================================

const SPEED := 300.0
const JUMP_VELOCITY := 320.0
const GRAVITY := 950.0
const HALF := 12.0
# Above this height you clear low hazards.
const AIRBORNE_HEIGHT := 16.0
# Effective on-screen radius of the drawn diamond, used for hazard hit tests.
# (HALF is the wall-collision box on the grid — a different thing.)
const HIT_R := 9.0

# Where we are on the flat grid underneath, plus how high we've jumped.
var world_pos := Vector2.ZERO
var z := 0.0
var vz := 0.0
var on_ground := true

# Direction the player wants to move, set each frame by main.gd.
var move_dir := Vector2.ZERO

# Drawn magenta during the death pause.
var dead := false

# The level's ASCII grid, so we can test for walls ourselves.
var _grid: Array = []

# Motion ribbon. When you stand still every sample lands on the same
# spot, so the trail collapses on its own — no special case needed.
var trail := Trail.new(8)


func setup(grid: Array, start: Vector2) -> void:
	_grid = grid
	world_pos = start
	z = 0.0
	vz = 0.0
	on_ground = true
	move_dir = Vector2.ZERO
	dead = false
	trail.clear()


func tick(delta: float) -> void:
	_move(delta)
	_apply_gravity(delta)
	trail.update(delta, world_pos)
	queue_redraw()


func jump() -> bool:
	if not on_ground:
		return false
	vz = JUMP_VELOCITY
	on_ground = false
	return true


# True while high enough to clear a low hazard.
func airborne() -> bool:
	return z > AIRBORNE_HEIGHT


func _move(delta: float) -> void:
	if move_dir == Vector2.ZERO:
		return

	var step := move_dir.normalized() * SPEED * delta

	# Each axis is tested separately so you slide along a wall
	# instead of sticking to it.
	var try_x := world_pos + Vector2(step.x, 0)
	if not _blocked(try_x):
		world_pos = try_x

	var try_y := world_pos + Vector2(0, step.y)
	if not _blocked(try_y):
		world_pos = try_y


func _apply_gravity(delta: float) -> void:
	if on_ground:
		return
	vz -= GRAVITY * delta
	z += vz * delta
	if z <= 0.0:
		z = 0.0
		vz = 0.0
		on_ground = true


func _blocked(pos: Vector2) -> bool:
	var corners := [
		pos + Vector2(-HALF, -HALF),
		pos + Vector2(HALF, -HALF),
		pos + Vector2(-HALF, HALF),
		pos + Vector2(HALF, HALF),
	]
	for c in corners:
		if _is_wall(int(floor(c.x / Iso.TILE)), int(floor(c.y / Iso.TILE))):
			return true
	return false


func _is_wall(col: int, row: int) -> bool:
	return cell_char(col, row) == "#"


func cell_char(col: int, row: int) -> String:
	if row < 0 or row >= _grid.size():
		return "#"
	var line: String = _grid[row]
	if col < 0 or col >= line.length():
		return "#"
	return line[col]


# The tile we're standing on right now.
func current_cell() -> String:
	return cell_char(int(floor(world_pos.x / Iso.TILE)), int(floor(world_pos.y / Iso.TILE)))


func _draw() -> void:
	# Trail first so the player body always sits on top of its own wake.
	trail.draw_into(self, Palette.HAZ if dead else Palette.PLAYER,
		HALF * 0.8, z + 10.0, 1.2, 0.38)

	var ground := Iso.to_screen(world_pos, 0.0)
	var body := Iso.to_screen(world_pos, z + 10.0)

	# The shadow shrinking as you rise is what sells the height.
	var shrink: float = clamp(1.0 - z / 90.0, 0.35, 1.0)
	draw_circle(ground, 13.0 * shrink, Color(0, 0, 0, 0.55 * shrink))

	var col := Palette.HAZ if dead else Palette.PLAYER

	if not on_ground:
		draw_circle(body, 20.0, Color(Palette.PLAYER.r, Palette.PLAYER.g, Palette.PLAYER.b, 0.18))

	var s := HALF
	draw_colored_polygon(PackedVector2Array([
		body + Vector2(0, -s), body + Vector2(s, 0),
		body + Vector2(0, s), body + Vector2(-s, 0)
	]), Palette.glow(col, 1.2))
	draw_polyline(PackedVector2Array([
		body + Vector2(0, -s), body + Vector2(s, 0),
		body + Vector2(0, s), body + Vector2(-s, 0), body + Vector2(0, -s)
	]), Color(1, 1, 1, 0.85), 1.5)
