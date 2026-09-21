extends SceneTree
# ============================================================
# FRAMING SCREENSHOT for the Phase R prototype (addendum 4: one
# screenshot per section into docs/screenshots/).
#
#   godot --path . --resolution 2400x1080 -s tools/shot.gd -- out=docs/screenshots/x.png bar=1 level=1
#   ... jump=1      (jump at that moment, shoot when the creature's eye faces the camera)
#   ... kill=1      (walk into the nearest hazard there; shoot the frame the killer flashes)
#   ... seq=8 step=0.5   (eight frames half a second apart, out-01.png .. out-08.png)
#
# Opens the run scene, starts it, waits until the song reaches the
# given bar (plus `after` seconds), saves the frame and quits. Audio
# is muted. Nobody plays: the intro carry keeps an idle player alive
# to the first downbeat; for later bars the validator bot drives.
# ============================================================

var out := "docs/screenshots/shot.png"
var bar := 1
var after := 0.4
var level := 1
var endless := false         # endless=1: the endless run instead of one level (start_lap=N: enter at lap N)
var start_lap := 0
var grad := false            # grad=1: as a graduated player (lives on, no teaching lap)
var render_scale := 1.0      # scale=0.75: the 3D render scale the phone uses (see track_test RENDER SCALE)
var end_screen := false      # end=1 (with endless=1 grad=1): lose every life from `bar` on, shoot the end screen
var _end_wait := 0.0
var scene_kind := "run"      # scene=select captures the level-select screen instead
var _select_frames := -1
var test: Node = null
var clock: Node = null
var bot: Object = null
var _frames_after := -1
var jump := false            # jump=1: capture mid-jump with the eye toward the camera
var _jumped := false
var kill := false            # kill=1: walk into the nearest hazard at the bar, shoot the death frame
var _killed := false
var seq := 1                 # seq=N step=S: N frames S seconds apart from the bar (out-01.png ...)
var step := 0.5
var _seq_taken := 0
var _seq_next_t := 0.0


var _args_read := false


func _process(_delta: float) -> bool:
	if not _args_read:
		_args_read = true
		_setup_args()
	if scene_kind == "select":
		if _select_frames < 0:
			_setup_args()
			AudioServer.set_bus_volume_db(0, -80.0)
			root.add_child(load("res://prototype/level_select.tscn").instantiate())
			_select_frames = 0
			return false
		_select_frames += 1
		if _select_frames >= 20:
			var img := root.get_viewport().get_texture().get_image()
			print("SHOT saved=%s err=%d size=%dx%d (level select)" % [out, img.save_png(out), img.get_width(), img.get_height()])
			return true
		return false
	if test == null:
		_setup()
		return false
	if test.state == test.State.WAIT:
		if _pending_bot != null:
			_give_bot_its_path()
		test.start_now()
		# The leash number should describe PLAY. Before this point the
		# scene is still being set up and a foot can sit anywhere.
		test.player.creature.reset_reach_seen()
		return false
	if _frames_after >= 0:
		# The three frames between deciding to shoot and shooting are not
		# guaranteed: an unattended run can die in them, and the retry
		# hides the world again -- which is how this tool saved a black
		# LOADING screen. Cancel and wait for the world to be up again.
		if test.state != test.State.RUN and not (kill or end_screen):
			_frames_after = -1
			return false
		_frames_after += 1
		if _frames_after >= 3:
			var img := root.get_viewport().get_texture().get_image()
			if seq > 1:
				# A sequence: out-01.png, out-02.png, ... every `step` seconds.
				_seq_taken += 1
				var name := out.get_basename() + "-%02d." % _seq_taken + out.get_extension()
				print("SHOT saved=%s err=%d t=%.2f bar=%d" % [name, img.save_png(name), clock.song_time(), clock.current_bar()])
				if _seq_taken >= seq:
					return true
				_seq_next_t = clock.song_time() + step
				_frames_after = -1
				return false
			var err := img.save_png(out)
			print("SHOT saved=%s err=%d size=%dx%d t=%.2f bar=%d triangles=%d draw_calls=%d" % [out, err, img.get_width(), img.get_height(), clock.song_time(), clock.current_bar(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
			print("SHOT monoliths=%s" % [test.field.monolith_counts()])
			# Brief 5's leash, measured in the REAL game (the carry line can
			# pull the player in ways the walk rig cannot).
			print("LEASH max foot-to-hip as drawn %.4f (planted %.4f) of reach %.4f  ground %.2f u/s" % [
				test.player.creature.max_reach_seen(),
				test.player.creature.max_reach_planted(),
				test.player.creature.reach(),
				test.player.creature.ground_speed()])
			print("LEASH unclamped worst %.4f" % test.player.creature.max_raw())
			_print_triangle_budget()
			return true
		return false
	var t: float = clock.song_time()
	if end_screen:
		if test.state == test.State.GAMEOVER:
			_end_wait += _delta
			if _end_wait > 1.0:
				var img := root.get_viewport().get_texture().get_image()
				print("SHOT saved=%s err=%d (end screen)" % [out, img.save_png(out)])
				return true
		elif test.state == test.State.RUN and clock.current_bar() >= bar:
			test.debug_walk_into_danger()
		return false
	if _seq_taken > 0:
		if t >= _seq_next_t:
			_frames_after = 0
		return false
	if kill and test.state == test.State.DEAD:
		# The last rendered frame is the death frame, with the killer white.
		var img := root.get_viewport().get_texture().get_image()
		print("SHOT saved=%s err=%d size=%dx%d t=%.2f bar=%d (death frame)" % [out, img.save_png(out), img.get_width(), img.get_height(), clock.song_time(), clock.current_bar()])
		return true
	# Only once the world is actually on screen. The loading phase hides
	# rig / player / field, and since the shipped verdicts started being
	# used (2026-09-21) a cached level can reach the target bar while the
	# prewarm rack is still filling -- which shot a black frame.
	if test.state != test.State.RUN:
		return false
	if clock.current_bar() >= bar and t >= clock.bar_start(bar) + after:
		if kill:
			# Walk into the nearest lethal box once something is lethal.
			if not _killed:
				_killed = test.debug_walk_into_danger()
		elif not jump:
			_frames_after = 0
		elif not _jumped:
			# jump=1: jump, then shoot when the spin shows the eye to the camera.
			_jumped = true
			test._on_jump()
		elif test.player.creature.facing_camera() > 0.985 or test.player.on_ground:
			_frames_after = 2
	return false


func _setup_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"out": out = kv[1]
			"bar": bar = int(kv[1])
			"after": after = float(kv[1])
			"level": level = int(kv[1])
			"endless": endless = kv[1] == "1"
			"grad": grad = kv[1] == "1"
			"end": end_screen = kv[1] == "1"
			"scale": render_scale = float(kv[1])
			"start_lap": start_lap = int(kv[1])
			"scene": scene_kind = kv[1]
			"jump": jump = kv[1] == "1"
			"kill": kill = kv[1] == "1"
			"seq": seq = int(kv[1])
			"step": step = float(kv[1])


func _setup() -> void:
	_setup_args()
	AudioServer.set_bus_volume_db(0, -80.0)
	var Rules: GDScript = load("res://prototype/rules.gd")
	Rules.ENDLESS = endless
	var progress = root.get_node_or_null("Progress")
	if progress != null:
		progress.save_enabled = false
		progress.graduated = grad
	Rules.START_LAP = start_lap
	if level != 1:
		Rules.LEVEL = level
	clock = root.get_node_or_null("BeatClock")
	if clock == null:
		clock = load("res://prototype/beat_clock.gd").new()
		clock.name = "BeatClock"
		root.add_child(clock)
	var scene: PackedScene = load("res://prototype/track_test.tscn")
	test = scene.instantiate()
	root.add_child(test)
	root.scaling_3d_scale = render_scale
	if bar > 1 or seq > 1 or kill:
		# Let the validator bot carry the player to the requested bar alive.
		var ap: Object = load("res://tools/autoplay.gd").new()   # a SceneTree script, not a Node
		bot = ap
		test.bot = ap
		ap.mode = "validator"
		ap.clock = clock
		ap.Rules = Rules
		ap.HazardMath = load("res://prototype/hazard_math.gd")
		ap.test = test
		if endless:
			ap.attach_endless(test, clock)
		else:
			_pending_bot = ap      # the level is built in the scene's loading phase: its path is read at WAIT


# The windowed scene builds its level behind the loading bar, so the bot's
# path can only be read once the scene waits for the start.
var _pending_bot: Object = null

func _give_bot_its_path() -> void:
	var ap: Object = _pending_bot
	_pending_bot = null
	var fair: Dictionary = test.field.fairness
	if fair.get("cached", false) or fair["path"].is_empty():
		fair = load("res://prototype/fairness.gd").validate(test.field.plan, clock, test.knobs)
	ap.path = fair["path"]
	ap.first_beat = int(fair["first_beat"])


# Who puts the triangles in the frame: every visible MeshInstance3D whose
# bounds are inside the camera's view, grouped by what it is.
func _print_triangle_budget() -> void:
	var cam: Camera3D = test.rig.cam
	var frustum := cam.get_frustum()
	var groups := {}
	var stack: Array = [test]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D) or not n.is_visible_in_tree() or n.mesh == null:
			continue
		var mi: MeshInstance3D = n
		var box: AABB = mi.global_transform * mi.get_aabb()
		var inside := true
		for plane in frustum:
			# (Godot's frustum planes point outward.)
			var all_out := true
			for k in 8:
				if not plane.is_point_over(box.get_endpoint(k)):
					all_out = false
					break
			if all_out:
				inside = false
				break
		if not inside:
			continue
		var tris := 0
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null and idx.size() > 0 else arr[Mesh.ARRAY_VERTEX].size()) / 3
		var what := "other"
		var p: Node = mi
		while p != null and p != test:
			var nm := String(p.name)
			for key in ["gate_pillar", "sweeper_segment", "slammer", "orbiter_pillar", "volley_emitter"]:
				if nm.begins_with(key):
					what = key
			if p.get_script() != null and String(p.get_script().resource_path).ends_with("monoliths.gd"):
				what = "monolith"
			if p.get_script() != null and String(p.get_script().resource_path).ends_with("creature.gd"):
				what = "creature"
			p = p.get_parent()
		if what == "other" and mi.mesh is BoxMesh:
			what = "tiles / boxes"
		var g: Array = groups.get(what, [0, 0])
		g[0] += 1
		g[1] += tris
		groups[what] = g
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a][1] > groups[b][1])
	for k in keys:
		print("BUDGET %-16s %4d meshes  %7d triangles" % [k, groups[k][0], groups[k][1]])
