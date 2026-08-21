extends Node2D

# ============================================================
# THE LAST GAME - Phase 2d
# Glass controls pass:
#   - Frosted-glass virtual joystick (left half)
#   - Frosted-glass JUMP button (right half)
#   - Multi-touch: move and jump simultaneously
#   - Auto-centres on any screen size
#   - "Rotate your phone" prompt in portrait
#
# NATIVE BUILD NOTE:
#   To force landscape on real phones, set
#   Project Settings > Display > Window > Handheld > Orientation
#   to "landscape". The web build can't lock orientation, which
#   is why the rotate prompt still exists.
# ============================================================

const SHARE_URL := "https://mivasthecreator.itch.io/the-last-game"

# --- Movement tuning ---
const TILE := 64.0
const PLAYER_HALF := 12.0
const PLAYER_SPEED := 300.0
const JUMP_VELOCITY := 320.0
const GRAVITY := 950.0
const AIRBORNE_HEIGHT := 16.0
const DEATH_PAUSE := 0.40

# --- Isometric projection ---
const ISO_X := 0.5
const ISO_Y := 0.25
const WALL_H := 42.0

# --- Touch control sizing (tune these for thumb comfort) ---
const STICK_RADIUS := 76.0
const STICK_KNOB := 32.0
const STICK_DEADZONE := 10.0
const JUMP_BTN_RADIUS := 62.0
const CTRL_MARGIN := Vector2(125.0, 118.0)

# --- Hazards ---
const HAZ_R := 15.0
const CHASER_SPEED := 115.0

# --- Haptics (ms). No-op on platforms/browsers without vibration support. ---
const HAPTIC_DEATH_MS := 35
const HAPTIC_WIN_MS := 80

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
# '#' wall  '.' floor  'P' start  'G' goal  'O' pit
# ============================================================
var levels := [
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
var run_highest_level := 0
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
var pulse := 0.0

# --- Results screen ---
var showing_results := false
var result_won := false
var copy_flash_timer := 0.0
var copy_button_rect := Rect2()

# --- Multi-touch ---
var stick_touch_id := -1
var stick_origin := Vector2.ZERO
var stick_current := Vector2.ZERO
var jump_touch_id := -1
var jump_flash := 0.0
var stick_fade := 0.0


func _ready() -> void:
	load_level(0)


func _process(delta: float) -> void:
	pulse += delta
	if copy_flash_timer > 0.0:
		copy_flash_timer -= delta
	if jump_flash > 0.0:
		jump_flash -= delta * 4.0

	# smooth fade when the stick is grabbed / released
	var target: float = 1.0 if stick_touch_id != -1 else 0.0
	stick_fade = lerp(stick_fade, target, clamp(delta * 12.0, 0.0, 1.0))

	if showing_results:
		queue_redraw()
		return

	if is_dead:
		death_timer -= delta
		if death_timer <= 0.0:
			if lives <= 0:
				enter_results(false)
			else:
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
	run_highest_level = max(run_highest_level, index)
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


func start_new_run() -> void:
	lives = 3
	total_deaths = 0
	run_highest_level = 0
	showing_results = false
	result_won = false
	load_level(0)


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

	if stick_touch_id != -1:
		var drag := stick_current - stick_origin
		if drag.length() > STICK_DEADZONE:
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
		jump_flash = 1.0


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


# ============================================================
# COLLISIONS
# ============================================================
func check_collisions() -> void:
	# on_ground (not raw z height) so a jump pressed the instant you
	# step onto a pit still saves you, even before z has risen.
	if on_ground:
		var col := int(floor(player_pos.x / TILE))
		var row := int(floor(player_pos.y / TILE))
		if cell_char(col, row) == "O":
			die()
			return

	for i in range(haz_pos.size()):
		var kind := haz_kind[i]
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
			enter_results(true)
		else:
			load_level(current_level + 1)


func die() -> void:
	is_dead = true
	death_timer = DEATH_PAUSE
	total_deaths += 1
	lives -= 1
	Input.vibrate_handheld(HAPTIC_DEATH_MS)


func enter_results(won_flag: bool) -> void:
	showing_results = true
	result_won = won_flag
	is_dead = false
	stick_touch_id = -1
	jump_touch_id = -1
	if won_flag:
		Input.vibrate_handheld(HAPTIC_WIN_MS)


func brag_text() -> String:
	var tier := ""
	if total_deaths < 5:
		tier = "Suspiciously good at this."
	elif total_deaths < 15:
		tier = "Respectable damage."
	elif total_deaths < 30:
		tier = "This is getting personal."
	elif total_deaths < 50:
		tier = "You have a problem."
	else:
		tier = "Certified Last Game victim."

	if result_won:
		return "I CLEARED the loop in THE LAST GAME after %d deaths. Beat that. %s" % [total_deaths, SHARE_URL]
	return "I reached Level %d of THE LAST GAME and died %d times. %s Think you can beat that? %s" % [run_highest_level + 1, total_deaths, tier, SHARE_URL]


# ============================================================
# INPUT
# ============================================================
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and not showing_results:
			jump()
		elif event.keycode == KEY_R:
			start_new_run()
		elif event.keycode == KEY_C and showing_results:
			copy_brag()

	var screen := get_viewport_rect().size

	if event is InputEventScreenTouch:
		if event.pressed:
			if showing_results:
				if copy_button_rect.has_point(event.position):
					copy_brag()
				else:
					start_new_run()
				return
			if event.position.x < screen.x * 0.5:
				if stick_touch_id == -1:
					stick_touch_id = event.index
					stick_origin = event.position
					stick_current = event.position
			else:
				if jump_touch_id == -1:
					jump_touch_id = event.index
					jump()
		else:
			if event.index == stick_touch_id:
				stick_touch_id = -1
			if event.index == jump_touch_id:
				jump_touch_id = -1

	elif event is InputEventScreenDrag:
		if event.index == stick_touch_id:
			stick_current = event.position

	# Mouse fallback for desktop browsers
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if showing_results:
				if copy_button_rect.has_point(event.position):
					copy_brag()
				else:
					start_new_run()
				return
			if event.position.x < screen.x * 0.5:
				stick_touch_id = -100
				stick_origin = event.position
				stick_current = event.position
			else:
				jump()
		else:
			if stick_touch_id == -100:
				stick_touch_id = -1
	elif event is InputEventMouseMotion and stick_touch_id == -100:
		stick_current = event.position


func copy_brag() -> void:
	DisplayServer.clipboard_set(brag_text())
	copy_flash_timer = 1.4


# ============================================================
# ISOMETRIC PROJECTION
# ============================================================
func iso_origin() -> Vector2:
	var screen := get_viewport_rect().size
	return Vector2(
		screen.x * 0.5 + 256.0 - 368.0,
		screen.y * 0.5 - 184.0 + 6.0
	)


func to_screen(w: Vector2, z: float = 0.0) -> Vector2:
	return Vector2(
		(w.x - w.y) * ISO_X,
		(w.x + w.y) * ISO_Y - z
	) + iso_origin()


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
# GLASS UI HELPER
# Fakes frosted glass with layered translucent fills, a bright
# top rim highlight, and a soft outer bloom.
# ============================================================
func draw_glass_disc(c: Vector2, r: float, tint: Color, strength: float) -> void:
	# soft outer bloom
	draw_circle(c, r * 1.18, Color(tint.r, tint.g, tint.b, 0.05 * strength))
	draw_circle(c, r * 1.08, Color(tint.r, tint.g, tint.b, 0.05 * strength))

	# frosted body: layered so the centre reads slightly denser
	draw_circle(c, r, Color(1, 1, 1, 0.045 * strength))
	draw_circle(c, r * 0.94, Color(tint.r, tint.g, tint.b, 0.05 * strength))
	draw_circle(c, r * 0.55, Color(1, 1, 1, 0.03 * strength))

	# outer rim
	draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.22 * strength), 1.5)
	draw_arc(c, r, 0.0, TAU, 64, Color(tint.r, tint.g, tint.b, 0.35 * strength), 2.5)

	# top-edge specular highlight (the thing that sells "glass")
	draw_arc(c, r * 0.99, -PI * 0.92, -PI * 0.08, 32, Color(1, 1, 1, 0.42 * strength), 2.0)
	draw_arc(c, r * 0.80, -PI * 0.80, -PI * 0.32, 24, Color(1, 1, 1, 0.14 * strength), 5.0)


func centre_text(font, text: String, c: Vector2, size: int, col: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, c - Vector2(w * 0.5, -size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ============================================================
# DRAWING
# ============================================================
func _draw() -> void:
	var screen := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, screen), COL_BG, true)
	var font := ThemeDB.fallback_font

	if screen.y > screen.x:
		centre_text(font, "ROTATE YOUR PHONE",
			Vector2(screen.x * 0.5, screen.y * 0.5 - 24), 26, COL_EDGE)
		centre_text(font, "This one is played sideways",
			Vector2(screen.x * 0.5, screen.y * 0.5 + 18), 16, COL_TEXT)
		return

	if showing_results:
		draw_results(screen, font)
		return

	draw_floor()
	draw_walls()
	draw_goal()
	draw_hazards()
	draw_player()
	draw_hud(screen, font)
	draw_touch_controls(screen, font)


func draw_touch_controls(screen: Vector2, font) -> void:
	# ---------- JUMP BUTTON ----------
	var jb := Vector2(screen.x - CTRL_MARGIN.x, screen.y - CTRL_MARGIN.y)
	var pressed: float = clamp(jump_flash, 0.0, 1.0)
	var r := JUMP_BTN_RADIUS * (1.0 + pressed * 0.06)

	draw_glass_disc(jb, r, COL_EDGE, 1.0 + pressed * 0.9)

	if pressed > 0.0:
		draw_arc(jb, r * (1.0 + (1.0 - pressed) * 0.35), 0.0, TAU, 48,
			Color(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 0.35 * pressed), 2.0)

	centre_text(font, "JUMP", jb, 18,
		Color(1, 1, 1, 0.75 + pressed * 0.25))

	# ---------- MOVEMENT STICK ----------
	var resting := Vector2(CTRL_MARGIN.x, screen.y - CTRL_MARGIN.y)
	var base := resting
	var knob := resting
	var active := stick_touch_id != -1

	if active:
		base = stick_origin
		var d := stick_current - stick_origin
		if d.length() > STICK_RADIUS - STICK_KNOB:
			d = d.normalized() * (STICK_RADIUS - STICK_KNOB)
		knob = base + d

	var strength := 0.85 + stick_fade * 0.75

	draw_glass_disc(base, STICK_RADIUS, COL_PLAYER, strength)

	# faint direction crosshair inside the ring
	if not active:
		var cross := Color(1, 1, 1, 0.10)
		draw_line(base + Vector2(-16, 0), base + Vector2(16, 0), cross, 1.0)
		draw_line(base + Vector2(0, -16), base + Vector2(0, 16), cross, 1.0)

	# knob
	draw_circle(knob, STICK_KNOB * 1.15, Color(COL_PLAYER.r, COL_PLAYER.g, COL_PLAYER.b, 0.08 * strength))
	draw_circle(knob, STICK_KNOB, Color(1, 1, 1, 0.10 * strength))
	draw_circle(knob, STICK_KNOB * 0.92, Color(COL_PLAYER.r, COL_PLAYER.g, COL_PLAYER.b, 0.14 * strength))
	draw_arc(knob, STICK_KNOB, 0.0, TAU, 40, Color(1, 1, 1, 0.45 * strength), 1.8)
	draw_arc(knob, STICK_KNOB * 0.96, -PI * 0.88, -PI * 0.12, 24, Color(1, 1, 1, 0.5 * strength), 2.0)
	# tiny specular dot
	draw_circle(knob + Vector2(-STICK_KNOB * 0.34, -STICK_KNOB * 0.36),
		STICK_KNOB * 0.16, Color(1, 1, 1, 0.35 * strength))

	if not active:
		centre_text(font, "MOVE", resting + Vector2(0, STICK_RADIUS + 26), 13,
			Color(1, 1, 1, 0.35))


func draw_results(screen: Vector2, font) -> void:
	var accent := COL_GOAL if result_won else COL_HAZ
	var title := "YOU CLEARED THE LOOP" if result_won else "THE LOOP RESET"
	var cx := screen.x * 0.5

	centre_text(font, title, Vector2(cx, screen.y * 0.5 - 130), 34, accent)
	centre_text(font, "Level reached: %d / %d" % [run_highest_level + 1, levels.size()],
		Vector2(cx, screen.y * 0.5 - 80), 20, COL_TEXT)
	centre_text(font, "Deaths: %d" % total_deaths,
		Vector2(cx, screen.y * 0.5 - 48), 20, COL_TEXT)

	var bw := 320.0
	var bh := 60.0
	var bx := cx - bw * 0.5
	var by := screen.y * 0.5
	copy_button_rect = Rect2(Vector2(bx, by), Vector2(bw, bh))

	draw_rect(copy_button_rect, Color(1, 1, 1, 0.05), true)
	draw_rect(copy_button_rect, Color(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 0.55), false, 2.0)
	draw_line(Vector2(bx + 4, by + 2), Vector2(bx + bw - 4, by + 2), Color(1, 1, 1, 0.25), 1.5)

	var label := "COPIED!" if copy_flash_timer > 0.0 else "TAP TO COPY BRAG"
	centre_text(font, label, Vector2(cx, by + bh * 0.5), 18, COL_EDGE)

	centre_text(font, "Tap anywhere else to try again",
		Vector2(cx, by + 105), 14, Color(1, 1, 1, 0.4))


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

	if not is_wall(col + 1, row):
		draw_colored_polygon(PackedVector2Array([
			to_screen(Vector2(x1, y0), WALL_H),
			to_screen(Vector2(x1, y1), WALL_H),
			to_screen(Vector2(x1, y1), 0.0),
			to_screen(Vector2(x1, y0), 0.0),
		]), COL_WALL_RIGHT)

	if not is_wall(col, row + 1):
		draw_colored_polygon(PackedVector2Array([
			to_screen(Vector2(x0, y1), WALL_H),
			to_screen(Vector2(x1, y1), WALL_H),
			to_screen(Vector2(x1, y1), 0.0),
			to_screen(Vector2(x0, y1), 0.0),
		]), COL_WALL_LEFT)

	var top := tile_quad(col, row, WALL_H)
	draw_colored_polygon(top, COL_WALL_TOP)

	if not is_wall(col, row - 1):
		draw_line(top[0], top[1], COL_EDGE, 2.0)
	if not is_wall(col + 1, row):
		draw_line(top[1], top[2], COL_EDGE, 2.0)
	if not is_wall(col, row + 1):
		draw_line(top[2], top[3], COL_EDGE, 2.0)
	if not is_wall(col - 1, row):
		draw_line(top[3], top[0], COL_EDGE, 2.0)

	if not is_wall(col + 1, row) and not is_wall(col, row + 1):
		draw_line(to_screen(Vector2(x1, y1), WALL_H), to_screen(Vector2(x1, y1), 0.0),
			Color(COL_EDGE.r, COL_EDGE.g, COL_EDGE.b, 0.5), 1.5)


func draw_goal() -> void:
	var base := to_screen(goal_pos, 0.0)
	var lift := 12.0 + sin(pulse * 2.5) * 4.0
	var top := to_screen(goal_pos, lift)
	draw_circle(base, 16.0, Color(0, 0, 0, 0.45))
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

		draw_circle(to_screen(wp, 0.0), HAZ_R * 0.8, Color(0, 0, 0, 0.5))

		if kind == "chain":
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
	draw_string(font, Vector2(18, 32), "LEVEL %d / %d" % [current_level + 1, levels.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_EDGE)
	draw_string(font, Vector2(screen.x - 230, 32), "LIVES %d" % lives,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_HAZ)
	draw_string(font, Vector2(screen.x - 125, 32), "DEATHS %d" % total_deaths,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_TEXT)

	if is_dead:
		centre_text(font, "DIED", Vector2(screen.x * 0.5, screen.y * 0.5), 30, COL_HAZ)
