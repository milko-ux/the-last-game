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
		test.start_now()
		return false
	if _frames_after >= 0:
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
			return true
		return false
	var t: float = clock.song_time()
	if _seq_taken > 0:
		if t >= _seq_next_t:
			_frames_after = 0
		return false
	if kill and test.state == test.State.DEAD:
		# The last rendered frame is the death frame, with the killer white.
		var img := root.get_viewport().get_texture().get_image()
		print("SHOT saved=%s err=%d size=%dx%d t=%.2f bar=%d (death frame)" % [out, img.save_png(out), img.get_width(), img.get_height(), clock.song_time(), clock.current_bar()])
		return true
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
	if bar > 1 or seq > 1 or kill:
		# Let the validator bot carry the player to the requested bar alive.
		var ap: Object = load("res://tools/autoplay.gd").new()   # a SceneTree script, not a Node
		bot = ap
		test.bot = ap
		ap.mode = "validator"
		ap.clock = clock
		ap.Rules = Rules
		ap.HazardMath = load("res://prototype/hazard_math.gd")
		if endless:
			ap.attach_endless(test, clock)
		else:
			var fair: Dictionary = test.field.fairness
			if fair.get("cached", false) or fair["path"].is_empty():
				fair = load("res://prototype/fairness.gd").validate(test.field.plan, clock, test.knobs)
			ap.path = fair["path"]
			ap.first_beat = int(fair["first_beat"])
