extends Node2D
# ============================================================
# THE LAST GAME — Phase 1.5
#
# main.gd is now just the REFEREE. It owns the run (lives, deaths,
# which level you're on), loads levels from levels.json, spawns the
# right entities, and decides when you died or won.
#
# Everything else lives in its own file:
#   autoload/iso.gd      the isometric projection, shared by all
#   autoload/palette.gd  the fixed colour language
#   entities/board.gd    draws floor, pits, walls, goal
#   entities/player.gd   movement, jump, gravity, wall collision
#   entities/hazard*.gd  one scene per hazard type
#   ui/ui.gd             HUD, glass touch controls, results screen
#
# NATIVE BUILD NOTE:
#   To force landscape on real phones, set
#   Project Settings > Display > Window > Handheld > Orientation
#   to "landscape". The web build can't lock orientation, which
#   is why the rotate prompt still exists.
# ============================================================

const SHARE_URL := "https://mivasthecreator.itch.io/the-last-game"
const LEVELS_PATH := "res://levels.json"

const DEATH_PAUSE := 0.40
const STARTING_LIVES := 3

# --- Haptics (ms). No-op on platforms/browsers without vibration support. ---
const HAPTIC_DEATH_MS := 35
const HAPTIC_WIN_MS := 80

const PLAYER_SCENE := preload("res://entities/player.tscn")
const HAZARD_SCENES := {
	"patrol": preload("res://entities/hazard_line.tscn"),
	"sweep": preload("res://entities/hazard_line.tscn"),
	"chain": preload("res://entities/hazard_chain.tscn"),
	"chaser": preload("res://entities/hazard_chaser.tscn"),
}

@onready var board: Node2D = $Board
@onready var entities: Node2D = $Entities
@onready var ui: Node2D = $UI/Screen

var levels: Array = []

# --- Run state ---
var current_level := 0
var lives := STARTING_LIVES
var total_deaths := 0
var run_highest_level := 0

var player: Node2D = null
var hazards: Array = []

var elapsed := 0.0
var death_timer := 0.0
var is_dead := false
var showing_results := false
var result_won := false


func _ready() -> void:
	load_levels()
	ui.jump_pressed.connect(_on_jump_pressed)
	ui.restart_requested.connect(start_new_run)
	ui.copy_requested.connect(copy_brag)
	load_level(0)


# ============================================================
# LEVEL DATA
# Levels live in res://levels.json so they can be edited without
# touching code. See the "_readme" block in that file for the grid
# symbols and hazard types.
# ============================================================
func load_levels() -> void:
	var json_res: JSON = load(LEVELS_PATH)
	if json_res == null:
		push_error("Could not load %s" % LEVELS_PATH)
		return

	var parsed: Dictionary = json_res.data
	levels = []

	for entry in parsed["levels"]:
		var level_hazards: Array = []
		for h in entry.get("hazards", []):
			var haz: Dictionary = {"type": h["type"], "speed": float(h["speed"])}
			for key in ["a", "b", "pivot", "start"]:
				if h.has(key):
					haz[key] = Vector2(float(h[key][0]), float(h[key][1]))
			if h.has("radius"):
				haz["radius"] = float(h["radius"])
			level_hazards.append(haz)

		levels.append({
			"name": entry.get("name", ""),
			"grid": entry["grid"],
			"hazards": level_hazards,
		})


func load_level(index: int) -> void:
	current_level = index
	run_highest_level = max(run_highest_level, index)
	elapsed = 0.0
	is_dead = false

	var grid: Array = levels[index]["grid"]

	# Board size comes from the level itself, so a bigger maze in
	# levels.json just works instead of being clipped.
	Iso.set_board_size(_grid_width(grid), grid.size())

	var start := Vector2.ZERO
	var goal := Vector2.ZERO
	for row in range(grid.size()):
		var line: String = grid[row]
		for col in range(line.length()):
			if line[col] == "P":
				start = Iso.cell_center(col, row)
			elif line[col] == "G":
				goal = Iso.cell_center(col, row)

	board.setup(grid, goal)
	_spawn_entities(grid, start, levels[index]["hazards"])
	_tick_hazards(0.0)


func _grid_width(grid: Array) -> int:
	var w := 0
	for line in grid:
		w = max(w, (line as String).length())
	return w


func _spawn_entities(grid: Array, start: Vector2, haz_data: Array) -> void:
	for child in entities.get_children():
		child.queue_free()
	hazards = []

	# Hazards first, then the player, so the player draws on top.
	for data in haz_data:
		var scene: PackedScene = HAZARD_SCENES.get(data["type"], null)
		if scene == null:
			push_warning("Unknown hazard type '%s' in levels.json" % data["type"])
			continue
		var haz: Hazard = scene.instantiate()
		entities.add_child(haz)
		haz.setup(data)
		hazards.append(haz)

	player = PLAYER_SCENE.instantiate()
	entities.add_child(player)
	player.setup(grid, start)


func start_new_run() -> void:
	lives = STARTING_LIVES
	total_deaths = 0
	run_highest_level = 0
	showing_results = false
	result_won = false
	ui.leave_results()
	load_level(0)


# ============================================================
# GAME LOOP
# ============================================================
func _process(delta: float) -> void:
	board.pulse += delta

	var hide_world: bool = showing_results or ui.portrait()
	board.visible = not hide_world
	entities.visible = not hide_world

	if showing_results:
		return

	ui.set_status(current_level, levels.size(), lives, total_deaths, is_dead)

	if is_dead:
		death_timer -= delta
		if death_timer <= 0.0:
			if lives <= 0:
				enter_results(false)
			else:
				load_level(current_level)
		return

	elapsed += delta
	_tick_hazards(delta)

	player.move_dir = ui.move_dir()
	player.tick(delta)

	_check_collisions()


func _tick_hazards(delta: float) -> void:
	var p: Vector2 = player.world_pos if player != null else Vector2.ZERO
	for haz in hazards:
		haz.tick(delta, elapsed, p)


func _on_jump_pressed() -> void:
	if showing_results or player == null:
		return
	if player.jump():
		ui.confirm_jump()


# ============================================================
# COLLISIONS
# ============================================================
func _check_collisions() -> void:
	# on_ground (not raw z height) so a jump pressed the instant you
	# step onto a pit still saves you, even before z has risen.
	if player.on_ground and player.current_cell() == "O":
		die()
		return

	for haz in hazards:
		if haz.hits(player.world_pos, player.HALF, player.airborne()):
			die()
			return

	if player.world_pos.distance_to(board.goal_pos) < Iso.TILE * 0.45:
		if current_level + 1 >= levels.size():
			enter_results(true)
		else:
			load_level(current_level + 1)


func die() -> void:
	is_dead = true
	player.dead = true
	player.queue_redraw()
	death_timer = DEATH_PAUSE
	total_deaths += 1
	lives -= 1
	Input.vibrate_handheld(HAPTIC_DEATH_MS)


func enter_results(won_flag: bool) -> void:
	showing_results = true
	result_won = won_flag
	is_dead = false
	ui.enter_results(won_flag, run_highest_level, levels.size(), total_deaths)
	if won_flag:
		Input.vibrate_handheld(HAPTIC_WIN_MS)


# ============================================================
# SHARE
# ============================================================
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


func copy_brag() -> void:
	DisplayServer.clipboard_set(brag_text())
	ui.flash_copied()


# ============================================================
# INPUT (keyboard shortcuts; touch lives in ui.gd)
# ============================================================
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_SPACE and not showing_results:
		_on_jump_pressed()
	elif event.keycode == KEY_R:
		start_new_run()
	elif event.keycode == KEY_C and showing_results:
		copy_brag()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Palette.BG, true)
