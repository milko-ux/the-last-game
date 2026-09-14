extends SceneTree
# ============================================================
# HEADLESS AUTOPLAYER for the Phase R prototype.
#
#   godot --headless --path . -s tools/autoplay.gd -- bars=20 mode=validator
#
# mode=validator  follows the safe path the fairness validator found,
#                 one tile per beat, moving during the non-lethal part
#                 of each beat. It must never die: every death is a
#                 place where the runtime disagrees with rules.gd.
# mode=naive      replays the phone report: runs through the first
#                 gate's opening as soon as it can, then stands still.
#
# Runs in real time (the song clock is the system clock). Prints the
# scene's DEATH log lines and a summary.
# ============================================================

# Loaded at runtime: anything this -s script preloads is compiled before
# the autoloads exist, and these scripts reference BeatClock.
var Rules: GDScript = null
var HazardMath: GDScript = null

# The -s script is compiled before autoloads exist, so the clock is
# fetched from the tree at runtime (and created if script mode skipped it).
var clock: Node = null
var mode := "validator"
var max_bar := 20
var test: Node = null
var path: Array = []
var first_beat := 0
var naive_target: Variant = null
var naive_done := false
var last_deaths := 0
var death_bars := []
var t_wall0 := 0


func _process(_delta: float) -> bool:
	if test == null:
		_setup()
		return false
	if test.state == test.State.WAIT:
		test.start_now()
		return false
	if test.deaths != last_deaths:
		last_deaths = test.deaths
		death_bars.append(clock.current_bar())
	var done: bool = clock.current_bar() > max_bar or test.state == test.State.WON \
		or (Time.get_ticks_msec() - t_wall0) > 260000
	if done:
		print("AUTOPLAY mode=%s bars<=%d deaths=%d at_bars=%s notes=%d state=%d" % [
			mode, max_bar, test.deaths, str(death_bars), test.notes, test.state])
		return true
	return false


func _setup() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2 and kv[0] == "mode":
			mode = kv[1]
		if kv.size() == 2 and kv[0] == "bars":
			max_bar = int(kv[1])
	Rules = load("res://prototype/rules.gd")
	HazardMath = load("res://prototype/hazard_math.gd")
	clock = root.get_node_or_null("BeatClock")
	if clock == null:
		clock = load("res://prototype/beat_clock.gd").new()
		clock.name = "BeatClock"
		root.add_child(clock)
	var scene: PackedScene = load("res://prototype/track_test.tscn")
	test = scene.instantiate()
	root.add_child(test)
	test.bot = self
	var fair: Dictionary = test.field.fairness
	if fair.get("cached", false) or fair["path"].is_empty():
		# The game reused a cached verdict; compute the path here.
		fair = load("res://prototype/fairness.gd").validate(test.field.plan, clock)
	path = fair["path"]
	first_beat = int(fair["first_beat"])
	t_wall0 = Time.get_ticks_msec()
	print("AUTOPLAY start mode=%s validator_ok=%s path_len=%d" % [mode, fair["ok"], path.size()])


# Called by the scene every frame instead of reading the joystick.
# Returns (screen-right, forward); world +x is screen-left.
func move_dir(scene: Node) -> Vector2:
	var target: Variant = _naive_target(scene) if mode == "naive" else _validator_target(scene)
	if target == null:
		return Vector2.ZERO
	var p: Vector3 = scene.player.position
	var d := Vector2(float(target.x) - p.x, float(target.y) - p.z)
	var dist := d.length()
	# Full speed until practically there: a slow final approach leaves a
	# sideways move unfinished when the next forward move starts, and the
	# bot then cuts the corner into a wall.
	if dist < 0.06:
		return Vector2.ZERO
	var v := d / dist
	return Vector2(-v.x, v.y)


func _validator_target(scene: Node) -> Variant:
	var t: float = clock.hazard_time()
	var z_back: float = clock.z_at(clock.song_time())
	var i: int = clock.beat_at(t)
	if i < first_beat:
		# Run-up: ride the front of the window in the first tile's column,
		# so the first tile is reached well before the first downbeat.
		var front: float = z_back + Rules.WINDOW_DEPTH - 1.5
		if path.size() > 0 and path[0] != null:
			var p0: Vector2 = path[0]["pos"]
			return Vector2(p0.x, minf(p0.y, front))
		return Vector2(0.0, front)
	var idx := i - first_beat
	if idx >= path.size() or path[idx] == null:
		return Vector2(0.0, z_back + Rules.WINDOW_DEPTH * 0.6)
	var here: Dictionary = path[idx]
	if idx + 1 >= path.size() or path[idx + 1] == null:
		# Plan over (the outro): keep ahead of the back edge to the goal.
		return Vector2(here["pos"].x, z_back + Rules.WINDOW_DEPTH * 0.6)
	# Set off for the next tile at this beat's planned "leave" moment.
	if clock.beat_phase_at(t) >= float(here["leave"]):
		return path[idx + 1]["pos"]
	return here["pos"]


func _naive_target(scene: Node) -> Variant:
	if naive_done:
		return null
	if naive_target == null:
		for spec in scene.field.plan["hazards"]:
			if String(spec["kind"]) == "gate":
				naive_target = spec
				break
		if naive_target == null:
			naive_done = true
			return null
	var spec: Dictionary = naive_target
	var t: float = clock.hazard_time()
	var z_back: float = clock.z_at(clock.song_time())
	var goal := Vector2(HazardMath.gate_opening_x(spec, t), float(spec["z"]) + 1.5)
	if goal.y > z_back + Rules.WINDOW_DEPTH - 1.0:
		return Vector2(goal.x, z_back + Rules.WINDOW_DEPTH - 1.5)
	var p: Vector3 = scene.player.position
	if p.z > float(spec["z"]) + 1.0:
		naive_done = true
		print("AUTOPLAY naive: through the gate at t=%.2f, standing still at (%.2f, %.2f)" % [clock.song_time(), p.x, p.z])
		return null
	return goal
