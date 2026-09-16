extends SceneTree
# ============================================================
# FRAMING SCREENSHOT for the Phase R prototype (addendum 4: one
# screenshot per section into docs/screenshots/).
#
#   godot --path . --resolution 2400x1080 -s tools/shot.gd -- out=docs/screenshots/x.png bar=1 level=1
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
var test: Node = null
var clock: Node = null
var bot: Object = null
var _frames_after := -1


func _process(_delta: float) -> bool:
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
			var err := img.save_png(out)
			print("SHOT saved=%s err=%d size=%dx%d t=%.2f bar=%d" % [out, err, img.get_width(), img.get_height(), clock.song_time(), clock.current_bar()])
			return true
		return false
	var t: float = clock.song_time()
	if clock.current_bar() >= bar and t >= clock.bar_start(bar) + after:
		_frames_after = 0
	return false


func _setup() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"out": out = kv[1]
			"bar": bar = int(kv[1])
			"after": after = float(kv[1])
			"level": level = int(kv[1])
	AudioServer.set_bus_volume_db(0, -80.0)
	var Rules: GDScript = load("res://prototype/rules.gd")
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
	if bar > 1:
		# Let the validator bot carry the player to the requested bar alive.
		var ap: Node = load("res://tools/autoplay.gd").new()
		bot = ap
		test.bot = ap
		ap.mode = "validator"
		ap.clock = clock
		ap.Rules = Rules
		ap.HazardMath = load("res://prototype/hazard_math.gd")
		var fair: Dictionary = test.field.fairness
		if fair.get("cached", false) or fair["path"].is_empty():
			fair = load("res://prototype/fairness.gd").validate(test.field.plan, clock)
		ap.path = fair["path"]
		ap.first_beat = int(fair["first_beat"])
