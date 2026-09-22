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

# --- Haptics (ms). No-op on platforms/browsers without vibration support. ---
const HAPTIC_DEATH_MS := 35
const HAPTIC_WIN_MS := 80
const HAPTIC_COIN_MS := 25

const PLAYER_SCENE := preload("res://entities/player.tscn")
const HAZARD_SCENES := {
	"patrol": preload("res://entities/hazard_line.tscn"),
	"sweep": preload("res://entities/hazard_line.tscn"),
	"chain": preload("res://entities/hazard_chain.tscn"),
	"chaser": preload("res://entities/hazard_chaser.tscn"),
	"blinker": preload("res://entities/hazard_blinker.tscn"),
}

@onready var board: Node2D = $Board
@onready var entities: Node2D = $Entities
@onready var ui: Node2D = $UI/Screen
@onready var account_panel: Node2D = $UI/AccountPanel
@onready var lb_screen: Node2D = $UI/LeaderboardScreen

var levels: Array = []

# --- Run state ---
var current_level := 0
var lives := 3
var total_deaths := 0
var run_highest_level := 0

# Level to fall back to when all lives are gone. -1 = no checkpoint armed,
# so a wipe sends you back to the very start. Run-scoped on purpose: the
# loop resetting has to mean something.
var checkpoint_level := -1

# Levels whose coin has already been collected this run, so a coin you
# took doesn't reappear when you die and replay that level.
var coins_taken: Array[int] = []

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
	ui.restart_requested.connect(_on_restart_requested)
	ui.copy_requested.connect(copy_brag)
	ui.difficulty_chosen.connect(_on_difficulty_chosen)
	ui.menu_requested.connect(_on_menu_requested)
	ui.account_requested.connect(func(): account_panel.open())
	ui.leaderboard_requested.connect(_open_leaderboard)
	ui.overlays = [account_panel, lb_screen]
	lb_screen.join_requested.connect(_on_join_requested)
	Talo.auth_changed.connect(_on_auth_changed)
	# The difficulty screen is the entry point — guest-first, no login,
	# straight into choosing how badly you want to suffer.
	ui.level_count = levels.size()
	ui.enter_menu()
	load_level(0)


func _on_difficulty_chosen(d: int) -> void:
	Progress.selected = d
	ui.leave_menu()
	start_new_run()


func _on_menu_requested() -> void:
	ui.enter_menu()


func _open_leaderboard() -> void:
	lb_screen.open(Progress.selected, levels.size())


func _on_join_requested() -> void:
	lb_screen.close()
	account_panel.open()


func _overlay_open() -> bool:
	return account_panel.visible or lb_screen.visible


# Signing in mid-results submits the run that just ended — the "register
# on the results screen, score still counts" flow. (Keeping the guest
# name in step with the account is Talo's own job now: talo.gd
# _sync_profile, because the Phase R menu and run need it too.)
func _on_auth_changed() -> void:
	if Talo.logged_in() and showing_results:
		_submit_scores()


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
			for key in ["a", "b", "pivot", "start", "at"]:
				if h.has(key):
					haz[key] = Vector2(float(h[key][0]), float(h[key][1]))
			for num in ["radius", "period", "duty", "phase"]:
				if h.has(num):
					haz[num] = float(h[num])
			if h.has("arms"):
				haz["arms"] = int(h["arms"])
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
	var coin := Vector2.ZERO
	var coin_present := false
	for row in range(grid.size()):
		var line: String = grid[row]
		for col in range(line.length()):
			if line[col] == "P":
				start = Iso.cell_center(col, row)
			elif line[col] == "G":
				goal = Iso.cell_center(col, row)
			elif line[col] == "C":
				coin = Iso.cell_center(col, row)
				coin_present = true

	# The coin only exists in modes that actually have checkpoints, so it
	# never appears as a pickup that does nothing on Hard or Extreme.
	board.setup(grid, goal, coin, coin_present and Progress.checkpoints_allowed())
	board.coin_taken = index in coins_taken
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
	lives = Progress.lives_for()
	total_deaths = 0
	run_highest_level = 0
	checkpoint_level = -1
	coins_taken.clear()
	showing_results = false
	result_won = false
	ui.leave_results()
	load_level(0)


# Losing every life with a checkpoint armed drops you back to it with a
# full set of lives, rather than ending the run.
func resume_from_checkpoint() -> void:
	lives = Progress.lives_for()
	showing_results = false
	result_won = false
	ui.leave_results()
	load_level(max(checkpoint_level, 0))


func _on_restart_requested() -> void:
	if checkpoint_level >= 0 and Progress.checkpoints_allowed():
		resume_from_checkpoint()
	else:
		start_new_run()


# ============================================================
# GAME LOOP
# ============================================================
func _process(delta: float) -> void:
	board.pulse += delta

	var hide_world: bool = showing_results or ui.showing_menu or ui.portrait()
	board.visible = not hide_world
	entities.visible = not hide_world

	if showing_results or ui.showing_menu:
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
		if haz.hits(player.world_pos, player.HIT_R, player.airborne()):
			die()
			return

	if board.has_coin and not board.coin_taken \
			and player.world_pos.distance_to(board.coin_pos) < Iso.TILE * 0.5:
		board.coin_taken = true
		if current_level not in coins_taken:
			coins_taken.append(current_level)
		checkpoint_level = current_level
		board.queue_redraw()
		Input.vibrate_handheld(HAPTIC_COIN_MS)

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
	if won_flag:
		Progress.mark_cleared(Progress.selected)
	# The share screen shows on every wipe, checkpoint or not — it's the
	# viral mechanic, so it must not be skipped just because the player
	# has a checkpoint to fall back to. Only the continue action changes.
	var resume: int = checkpoint_level if Progress.checkpoints_allowed() else -1
	ui.enter_results(won_flag, run_highest_level, levels.size(), total_deaths, resume)
	_submit_scores()
	if won_flag:
		Input.vibrate_handheld(HAPTIC_WIN_MS)


# ============================================================
# LEADERBOARD SUBMISSION
# Fire-and-forget: the run is already over and the results screen is
# up, so a slow network just means the rank line appears late. Talo
# keeps ONE entry per player per board and only replaces it when the
# new score is better, so every finished run is submitted as-is.
# ============================================================
func _submit_scores() -> void:
	if not (Talo.configured() and Talo.logged_in() and Consent.granted):
		return
	var d: int = Progress.selected
	var won := result_won
	var deaths := total_deaths
	# Progress score = furthest level (1-based). A full clear counts one
	# past the last level, so finishing always outranks dying on it.
	var reached := (levels.size() + 1) if won else (run_highest_level + 1)
	var props := {"deaths": deaths}
	if Consent.show_country and not Consent.country.is_empty():
		props["country"] = Consent.country

	ui.set_submit_text("SENDING SCORE...")
	var lines: Array[String] = []

	var res: Dictionary = await Talo.submit_score(
		Talo.progress_board(d), Talo.encode_progress(reached, deaths), props)
	if res.ok:
		var pos := int(res.data.get("entry", {}).get("position", -1))
		if pos >= 0:
			lines.append("GLOBAL #%d" % (pos + 1))
	else:
		lines.append(str(res.error))

	if won:
		var res2: Dictionary = await Talo.submit_score(Talo.finishers_board(d), float(deaths), props)
		if res2.ok:
			var pos2 := int(res2.data.get("entry", {}).get("position", -1))
			if pos2 >= 0:
				lines.append("FINISHERS #%d" % (pos2 + 1))

	# Only touch the UI if the player is still looking at these results.
	if showing_results:
		ui.set_submit_text("   ".join(lines))


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
	if _overlay_open():
		return
	if event.keycode == KEY_SPACE and not showing_results:
		_on_jump_pressed()
	elif event.keycode == KEY_R:
		start_new_run()
	elif event.keycode == KEY_C and showing_results:
		copy_brag()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Palette.BG, true)
