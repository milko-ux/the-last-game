extends Node2D

# ============================================================
# THE LAST GAME - Phase 2
#   Isometric projection (Marble Madness look)
#   Real Z axis - the player can JUMP
#   Spinning chains, sweepers, chasers, pits
#
# The world is still a flat grid underneath. Isometric is only
# how we DRAW it. That keeps level design readable as text.
# ============================================================

# --- Movement tuning ---
const TILE := 64.0
const PLAYER_HALF := 12.0
const PLAYER_SPEED := 300.0
const JUMP_VELOCITY := 320.0
const GRAVITY := 950.0
const AIRBORNE_HEIGHT := 16.0   # above this Z you clear low hazards
const DEATH_PAUSE := 0.40

# --- Isometric projection ---
const ISO_X := 0.5
const ISO_Y := 0.25
const ISO_ORIGIN := Vector2(368.0, 96.0)
const WALL_H := 42.0

# --- Hazards ---
const HAZ_R := 15.0
const CHASER_SPEED := 115.0

const COLS := 15
const ROWS := 8

# --- Colours ---
const COL_BG := Color("0a0612")
const COL_FLOOR := Color("160c28")
const COL_FLOOR_LINE := Color("2b1b4d")
const COL_WALL_TOP := Color("311a5c")
const COL_WALL_LEFT := Color("1a0e33")
const COL_WALL_RIGHT := Color("120a24")
const COL_EDGE := Color("00fff2")
const COL_PLAYER := Color("7dfaff")
const COL_HAZ := Color("ff2bd6")
const COL_CHAIN := Color("ff7a1f")
const COL_CHASER := Color("ff2b6b")
const COL_GOAL := Color("ffd23d")
const COL_PIT := Color("05030a")
const COL_TEXT := Color("a89fc2")

# ============================================================
# LEVEL DATA
# '#' wall   '.' floor   'P' start   'G' goal   'O' pit
#
# Hazard types:
#   patrol  - moves a to b, LOW  (you can jump it)
#   sweep   - moves a to b fast, LOW (you must jump it)
#   chain   - spins around pivot, TALL (you cannot jump it)
#   chaser  - follows you, LOW
# ============================================================
var levels := [
	# 1 - learn to move
	{
		"grid": [
			"###############",
			"#.............#",
			"#.............#",
			"#.P.........G.#",
			"#.............#",
			"#.............#",
			"#.............#",
			"###############",
		],
		"hazards": []
	},

	# 2 - learn to jump. One sweeper, nothing else.
	{
		"grid": [
			"###############",
			"#.............#",
			"#.............#",
			"#.P.........G.#",
			"#.............#",
			"#.............#",
			"#.............#",
			"###############",
		],
		"hazards": [
			{"type": "sweep", "a": Vector2(7, 1), "b": Vector2(7, 6), "speed": 3.4}
		]
	},

	# 3 - the chain. Tall, spinning, cannot be jumped. Go around.
	{
		"grid": [
			"###############",
			"#.............#",
			"#.P...........#",
			"#.............#",
			"#.............#",
			"#...........G.#",
			"#.............#",
			"###############",
		],
		"hazards": [
			{"type": "chain", "pivot": Vector2(7, 3), "radius": 2.2, "speed": 1.6},
			{"type": "patrol", "a": Vector2(11, 1), "b": Vector2(11, 6), "speed": 2.2}
		]
	},

	# 4 - pits. Jump them or fall.
	{
		"grid": [
			"###############",
			"#.............#",
			"#.P..OO...OO..#",
			"#....OO...OO..#",
			"#.............#",
			"#..OO.....OO.G#",
			"#..OO.....OO..#",
			"###############",
		],
		"hazards": [
			{"type": "sweep", "a": Vector2(8, 1), "b": Vector2(8, 6), "speed": 3.8},
			{"type": "patrol", "a": Vector2(13, 1), "b": Vector2(13, 6), "speed": 2.6}
		]
	},

	# 5 - everything at once, and something is following you.
	{
		"grid": [
			"###############",
			"#.............#",
			"#.P...OO......#",
			"#.....OO..#...#",
			"#.........#...#",
			"#..OO.....#...#",
			"#..OO........G#",
			"###############",
		],
		"hazards": [
			{"type": "chain", "pivot": Vector2(7, 4), "radius": 2.0, "speed": 2.0},
			{"type": "sweep", "a": Vector2(11, 1), "b": Vector2(11, 6), "speed": 4.0},
			{"type": "chaser", "start": Vector2(1, 6), "speed": 1.0},
		]
	},
]

# --- Runtime state ---
var current_level := 0
var lives := 3
var total_deaths := 0
var player_pos := Vector2.ZERO
var player_z := 0.0
var player_vz := 0.0
var on_ground := true
var goal_pos := Vector2.ZERO
var haz_pos: Array[Vector2] = []
var haz_kind: Array[String] = []
var chaser_pos := Vector2.ZERO
var haz_time := 0.0
var death_timer := 0.0
var is_dead := false
var won := false
var pulse := 0.0

# --- Touch ---
var touch_start := Vector2.ZERO
var touch_current := Vector2.ZERO
var touch_began := 0.0
var is_touching := false


func _ready() -> void:
	load_level(0)


func _process(delta: float) -> void:
	pulse += delta

	if won:
		queue_redraw()
		return

	if is_dead:
		death_timer -= delta
		if death_timer <= 0.0:
			load_level(current_level)
		queue_redraw()
		return

	haz_time += delta
	update_hazards(delta)
	move_player(delta)
	apply_gravity(delta)
	check_collisions()
	queue_redraw()


# ============================================================
# LEVEL LOADING
# ============================================================
func load_level(index: int) -> void:
	current_level = index
	haz_time = 0.0
	is_dead = false
	player_z = 0.0
	player_vz = 0.0
	on_ground = true

	var grid: Array = levels[index]["grid"]
	for row in range(grid.size()):
		var line: String = grid[row]
		for col in range(line.length()):
			if line[col] == "P":
				player_pos = cell_center(col, row)
			elif line[col] == "G":
				goal_pos = cell_center(col, row)

	for h in levels[index]["hazards"]:
		if h["type"] == "chaser":
			chaser_pos = cell_center(int(h["start"].x), int(h["start"].y))

	update_hazards(0.0)


func cell_center(col: int, row: int) -> Vector2:
	return Vector2((col + 0.5) * TILE, (row + 0.5) * TILE)


func cell_char(col: int, row: int) -> String:
	var grid: Array = levels[current_level]["grid"]
	if row < 0 or row >= grid.size():
		return "#"
	var line: String = grid[row]
	if col < 0 or col >= line.length():
		return "#"
	return line[col]


func is_wall(col: int, row: int) -> bool:
	return cell_char(col, row) == "#"


# ============================================================
# MOVEMENT
# ============================================================
func move_player(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if is_touching:
		var drag := touch_current - touch_start
		if drag.length() > 14.0:
			# Convert screen drag into world direction (undo the iso skew)
			dir = screen_dir_to_world(drag.normalized())

	if dir == Vector2.ZERO:
		return

	var step := dir.normalized() * PLAYER_SPEED * delta

	var try_x := player_pos + Vector2(step.x, 0)
	if not blocked(try_x):
		player_pos = try_x

	var try_y := player_pos + Vector2(0, step.y)
	if not blocked(try_y):
		player_pos = try_y


func screen_dir_to_world(d: Vector2) -> Vector2:
	# Inverse of the iso projection, direction only.
	var wx := d.x / (2.0 * ISO_X) + d.y / (2.0 * ISO_Y)
	var wy := -d.x / (2.0 * ISO_X) + d.y / (2.0 * ISO_Y)
	return Vector2(wx, wy).normalized()


func blocked(pos: Vector2) -> bool:
	var corners := [
		pos + Vector2(-PLAYER_HALF, -PLAYER_HALF),
		pos + Vector2(PLAYER_HALF, -PLAYER_HALF),
		pos + Vector2(-PLAYER_HALF, PLAYER_HALF),
		pos + Vector2(PLAYER_HALF, PLAYER_HALF),
	]
	for c in corners:
		var col := int(floor(c.x / TILE))
		var row := int(floor(c.y / TILE))
		if is_wall(col, row):
			return true
	return false


func jump() -> void:
	if on_ground:
		player_vz = JUMP_VELOCITY
		on_ground = false


func apply_gravity(delta: float) -> void:
	if on_ground:
		return
	player_vz -= GRAVITY * delta
	player_z += player_vz * delta
	if player_z <= 0.0:
		player_z = 0.0
		player_vz = 0.0
		on_ground = true


func airborne() -> bool:
	return player_z > AIRBORNE_HEIGHT


# ============================================================
# HAZARDS
# ============================================================
func update_hazards(delta: float) -> void:
	haz_pos.clear()
	haz_kind.clear()

	for h in levels[current_level]["hazards"]:
		var kind: String = h["type"]

		if kind == "chain":
			var pivot: Vector2 = cell_center(int(h["pivot"].x), int(h["pivot"].y))
			var ang: float = haz_time * float(h["speed"])
			var r: float = float(h["radius"]) * TILE
			haz_pos.append(pivot + Vector2(cos(ang), sin(ang)) * r)
			haz_kind.append("chain")

		elif kind == "chaser":
			if delta > 0.0:
				var to_player := player_pos - chaser_pos
				if to_player.length() > 1.0:
					chaser_pos += to_player.normalized() * CHASER_SPEED * float(h["speed"]) * delta
			haz_pos.append(chaser_pos)
			haz_kind.append("chaser")

		else:
			var a: Vector2 = cell_center(int(h["a"].x), int(h["a"].y))
			var b: Vector2 = cell_center(int(h["b"].x), int(h["b"].y))
			var t: float = fmod(haz_time * float(h["speed"]) * 0.5, 2.0)
			if t > 1.0:
				t = 2.0 - t
			haz_pos.append(a.lerp(b, t))
			haz_kind.append(kind)


func chain_pivot(index: int) -> Vector2:
	var i := 0
	for h in levels[current_level]["hazards"]:
		if i == index:
			if h["type"] == "chain":
				return cell_center(int(h["pivot"].x), int(h["pivot"].y))
		i += 1
	return Vector2.ZERO


# ============================================================
# COLLISIONS
# ============================================================
func check_collisions() -> void:
	# Pit: only kills you if you are on the ground
	if player_z < 4.0:
		var col := int(floor(player_pos.x / TILE))
		var row := int(floor(player_pos.y / TILE))
		if cell_char(col, row) == "O":
			die()
			return

	for i in range(haz_pos.size()):
		var kind := haz_kind[i]
		# Low hazards can be jumped. Chains cannot.
		if kind != "chain" and airborne():
			continue
		var hp: Vector2 = haz_pos[i]
		var closest := Vector2(
			clamp(hp.x, player_pos.x - PLAYER_HALF, player_pos.x + PLAYER_HALF),
			clamp(hp.y, player_pos.y - PLAYER_HALF, player_pos.y + PLAYER_HALF)
		)
		if closest.distance_to(hp) < HAZ_R:
			die()
			return

	if player_pos.distance_to(goal_pos) < TILE * 0.45:
		if current_level + 1 >= levels.size():
			won = true
		else:
			load_level(current_level + 1)


func die() -> void:
	is_dead = true
	death_timer = DEATH_PAUSE
	total_deaths += 1
	lives -= 1
	if lives <= 0:
		lives = 3
		current_level = 0


# ============================================================
# INPUT
# ============================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			jump()
		elif event.keycode == KEY_R:
			lives = 3
			total_deaths = 0
			won = false
			load_level(0)

	if event is InputEventScreenTouch:
		if event.pressed:
			is_touching = true
			touch_start = event.position
			touch_current = event.position
			touch_began = pulse
		else:
			# A quick tap that didn't move much = jump
			var held := pulse - touch_began
			if held < 0.22 and (touch_current - touch_start).length() < 20.0:
				jump()
			is_touching = false
	elif event is InputEventScreenDrag:
		touch_current = event.position


# ============================================================
# ISOMETRIC PROJECTION
# world (x, y) + height z  ->  screen point
# ============================================================
func to_screen(w: Vector2, z: float = 0.0) -> Vector2:
	return Vector2(
		(w.x - w.y) * ISO_X,
		(w.x + w.y) * ISO_Y - z
	) + ISO_ORIGIN


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


# ============================================================
# DRAWING
# ============================================================
func _draw() -> void:
	var screen := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), COL_BG, true)
	var font := ThemeDB.fallback_font

	if won:
		draw_string(font, Vector2(screen.x * 0.5 - 200, screen.y * 0.5 - 10),
			"YOU CLEARED THE LOOP", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, COL_GOAL)
		draw_string(font, Vector2(screen.x * 0.5 - 110, screen.y * 0.5 + 34),
			"Deaths: %d" % total_deaths, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, COL_TEXT)
		draw_string(font, Vector2(screen.x * 0.5 - 110, screen.y * 0.5 + 64),
			"Press R to run it again", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_TEXT)
		return

	draw_floor()
	draw_walls()
	draw_goal()
	draw_hazards()
	draw_player()
	draw_hud(screen, font)


func draw_floor() -> void:
	for row in range(ROWS):
		for col in range(COLS):
			var c := cell_char(col, row)
			if c == "#":
				continue
			var quad := tile_quad(col, row, 0.0)
			if c == "O":
				draw_colored_polygon(quad, COL_PIT)
				draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]),
					Color(COL_HAZ.r, COL_HAZ.g, COL_HAZ.b, 0.35), 1.5)
			else:
				draw_colored_polygon(quad, COL_FLOOR)
				draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]),
					COL_FLOOR_LINE, 1.0)


func draw_walls() -> void:
	# Back to front: smaller (col + row) is further away
	var cells := []
	for row in range(ROWS):
		for col in range(COLS):
			if is_wall(col, row):
				cells.append({"c": col, "r": row})
	cells.sort_custom(func(a, b): return (a["c"] + a["r"]) < (b["c"] + b["r"]))

	for cell in cells:
		draw_cube(cell["c"], cell["r"])


func draw_cube(col: int, row: int) -> void:
	var x0 := col * TILE
	var y0 := row * TILE
	var x1 := x0 + TILE
	var y1 := y0 + TILE

	# Front-right face (the +x side)
	if not is_wall(col + 1, row):
		draw_colored_polygon(PackedVector2Array([
			to_screen(Vector2(x1, y0), WALL_H),
			to_screen(Vector2(x1, y1), WALL_H),
			to_screen(Vector2(x1, y1), 0.0),
			to_screen(Vector2(x1, y0), 0.0),
		]), COL_WALL_RIGHT)

	# Front-left face (the +y side)
	if not is_wall(col, row + 1):
		draw_colored_polygon(PackedVector2Array([
			to_screen(Vector2(x0, y1), WALL_H),
			to_screen(Vector2(x1, y1), WALL_H),
			to_screen(Vector2(x1, y1), 0.0),
			to_screen(Vector2(x0, y1), 0.0),
		]), COL_WALL_LEFT)

	# Top face
	var top := tile_quad(col, row, WALL_H)
	draw_colored_polygon(top, COL_WALL_TOP)

	# Neon edges only where the wall is exposed
	if not is_wall(col, row - 1):
		draw_line(top[0], top[1], COL_EDGE, 2.0)
	if not is_wall(col + 1, row):
		draw_line(top[1], top[2], COL_EDGE, 2.0)
	if not is_wall(col, row + 1):
		draw_line(top[2], top[3], COL_EDGE, 2.0)
	if not is_wall(col - 1, row):
		draw_line(top[3], top[0], COL_EDGE, 2.0)

	# Vertical corner glow on the front corner
	if not is_wall(col + 1, row) and not is_wall(col, row + 1):
		draw_line(to_screen(Vector2(x1, y1), WALL_H), to_screen(Vector2(x1, y1), 0.0),
			Color(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 0.5), 1.5)


func draw_goal() -> void:
	var base := to_screen(goal_pos, 0.0)
	var lift := 12.0 + sin(pulse * 2.5) * 4.0
	var top := to_screen(goal_pos, lift)
	draw_circle(base, 16.0, Color(0, 0, 0, 0.45))
	# diamond
	var s := 15.0
	draw_colored_polygon(PackedVector2Array([
		top + Vector2(0, -s), top + Vector2(s * 0.8, 0),
		top + Vector2(0, s), top + Vector2(-s * 0.8, 0)
	]), COL_GOAL)
	draw_circle(top, 24.0, Color(COL_GOAL.r, COL_GOAL.g, COL_GOAL.b, 0.15))


func draw_hazards() -> void:
	var idx := 0
	for h in levels[current_level]["hazards"]:
		if idx >= haz_pos.size():
			break
		var wp: Vector2 = haz_pos[idx]
		var kind: String = haz_kind[idx]

		# shadow on the floor
		draw_circle(to_screen(wp, 0.0), HAZ_R * 0.8, Color(0, 0, 0, 0.5))

		if kind == "chain":
			# tall hazard: draw the tether and a raised orb
			var pivot: Vector2 = cell_center(int(h["pivot"].x), int(h["pivot"].y))
			var p_base := to_screen(pivot, 0.0)
			var p_top := to_screen(pivot, 34.0)
			draw_line(p_base, p_top, Color(COL_CHAIN.r, COL_CHAIN.g, COL_CHAIN.b, 0.5), 2.0)
			var h_top := to_screen(wp, 34.0)
			draw_line(p_top, h_top, Color(COL_CHAIN.r, COL_CHAIN.g, COL_CHAIN.b, 0.7), 2.0)
			draw_circle(h_top, HAZ_R + 8.0, Color(COL_CHAIN.r, COL_CHAIN.g, COL_CHAIN.b, 0.2))
			draw_circle(h_top, HAZ_R, COL_CHAIN)
			draw_circle(h_top - Vector2(3, 3), HAZ_R * 0.35, Color(1, 1, 1, 0.6))
		else:
			var col := COL_HAZ
			if kind == "chaser":
				col = COL_CHASER
			var sp := to_screen(wp, 10.0)
			draw_circle(sp, HAZ_R + 7.0, Color(col.r, col.g, col.b, 0.2))
			draw_circle(sp, HAZ_R, col)
			draw_circle(sp - Vector2(3, 3), HAZ_R * 0.35, Color(1, 1, 1, 0.55))

		idx += 1


func draw_player() -> void:
	var ground := to_screen(player_pos, 0.0)
	var body := to_screen(player_pos, player_z + 10.0)

	# Shadow shrinks as you rise - this is what sells the height
	var shrink: float = clamp(1.0 - player_z / 90.0, 0.35, 1.0)
	draw_circle(ground, 13.0 * shrink, Color(0, 0, 0, 0.55 * shrink))

	var col := COL_PLAYER
	if is_dead:
		col = COL_HAZ

	if not on_ground:
		draw_circle(body, 20.0, Color(COL_PLAYER.r, COL_PLAYER.g, COL_PLAYER.b, 0.18))

	var s := PLAYER_HALF
	draw_colored_polygon(PackedVector2Array([
		body + Vector2(0, -s), body + Vector2(s, 0),
		body + Vector2(0, s), body + Vector2(-s, 0)
	]), col)
	draw_polyline(PackedVector2Array([
		body + Vector2(0, -s), body + Vector2(s, 0),
		body + Vector2(0, s), body + Vector2(-s, 0), body + Vector2(0, -s)
	]), Color(1, 1, 1, 0.85), 1.5)


func draw_hud(screen: Vector2, font) -> void:
	draw_string(font, Vector2(16, 26), "LEVEL %d / %d" % [current_level + 1, levels.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_EDGE)
	draw_string(font, Vector2(screen.x - 220, 26), "LIVES %d" % lives,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_HAZ)
	draw_string(font, Vector2(screen.x - 120, 26), "DEATHS %d" % total_deaths,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_TEXT)
	draw_string(font, Vector2(16, screen.y - 16), "ARROWS move    SPACE jump    R reset",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, 0.6))

	if is_dead:
		draw_string(font, Vector2(screen.x * 0.5 - 45, screen.y * 0.5),
			"DIED", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, COL_HAZ)
