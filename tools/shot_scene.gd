extends SceneTree
# ============================================================
# SCENE SHOT — opens ONE scene file, lets it live for a moment, and
# saves a PNG of it. For the screens: the main menu, the leaderboard,
# the end screen (Phase E sections 7-8 ask for all four).
#
# tools/shot.gd shoots a RUN and tools/shot_walk.gd shoots the walk
# rig; neither can be pointed at a scene file, which is what a screen
# is. This is that tool, and nothing else — no driving, no measuring.
#
#   godot --path . --resolution 2400x1080 --rendering-method gl_compatibility \
#         --fixed-fps 60 -s tools/shot_scene.gd -- \
#         scene=res://prototype/menu.tscn out=docs/screenshots/e-menu.png at=2.5
#
# ALWAYS PASS --fixed-fps 60 (the standing rule, see tools/shot_walk.gd).
# Without it every frame's delta is however long that frame really took —
# a cold shader compile is half a second, saving a 2400x1080 PNG is
# another tenth — so `at=` lands somewhere different every run and a
# moving thing (a hop) cannot be aimed at. With it, `at` IS the scene's
# own clock and the same number gives the same frame every time.
#
#   scene=res://...   the scene to open (required)
#   out=path.png      where the image goes
#   at=SEC            how long the scene runs before the shot (default 2.5:
#                     long enough for a fade-in and a breath)
#   fps=60            the fixed step, so the shot is the same every time
#   frames=N step=S   a BURST: N shots from `at`, S seconds apart, named
#                     out-01.png, out-02.png ... One run instead of N,
#                     which is how a moving thing (a hop) gets found.
#   tap=X,Y[;X,Y...]  tap the screen there first (screen pixels, not the
#                     2D canvas: multiply by the stretch scale), so a
#                     panel that only exists after a tap can be shot.
#                     Several taps are walked through TAP_GAP apart.
#   tap_at=SEC        when the first tap happens (default 1.0)
#
# Nothing here writes the save file (Milko's rule 6).
# ============================================================

var scene_path := "res://prototype/menu.tscn"
var out := "/tmp/scene.png"
var at := 2.5
var fps := 60
var frames := 1
var step := 0.1
var _shots := 0
var taps: Array[Vector2] = []
var tap_at := 1.0
const TAP_GAP := 0.5
var _taps_done := 0

var _t := 0.0
var _frames := 0
const MAX_FRAMES := 6000     # the kill switch: never spin for ever (100 s at 60 fps: a burst over a strip of monoliths)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"scene": scene_path = kv[1]
			"out": out = kv[1]
			"at": at = float(kv[1])
			"fps": fps = int(kv[1])
			"frames": frames = maxi(1, int(kv[1]))
			"step": step = float(kv[1])
			"tap_at": tap_at = float(kv[1])
			"tap":
				for one in kv[1].split(";"):
					var xy: PackedStringArray = one.split(",")
					if xy.size() == 2:
						taps.append(Vector2(float(xy[0]), float(xy[1])))
	Engine.max_fps = fps
	# The autoload is reached through the tree here: a `-s` tool's own
	# script is compiled before the autoloads exist, so naming Progress
	# directly fails to compile (the same shape as tools/shot.gd).
	var progress = get_root().get_node_or_null("Progress")
	if progress != null:
		progress.save_enabled = false
	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("SHOT SCENE: could not load %s" % scene_path)
		quit(1)
		return
	var node := packed.instantiate()
	get_root().add_child(node)
	# It has to BE the current scene, not just a child of the root: a
	# screen that calls change_scene_to_file (the menu's PLAY) frees the
	# current one, and with none set the old screen stays on top of the
	# new one for ever.
	current_scene = node
	print("SHOT SCENE %s -> %s at %.2f s" % [scene_path, out, at])


func _process(delta: float) -> bool:
	_t += delta
	_frames += 1
	if _taps_done < taps.size() and _t >= tap_at + _taps_done * TAP_GAP:
		var where: Vector2 = taps[_taps_done]
		_taps_done += 1
		var ev := InputEventScreenTouch.new()
		ev.pressed = true
		ev.position = where
		Input.parse_input_event(ev)
		print("SHOT SCENE tapped %.0f,%.0f at %.2f s" % [where.x, where.y, _t])
	if _frames >= MAX_FRAMES:
		return true
	if _shots < frames and _t >= at + _shots * step and not _pending:
		# Read the picture AFTER this frame has been drawn, not before:
		# read from _process the texture is the previous frame's, and with
		# a 2D overlay that changed this frame (a screen that just opened)
		# that is a picture of the wrong screen. Learned the hard way,
		# 2026-09-22. (A `-s` script's _process cannot await: its return
		# value is the quit signal, so the read is a one-shot callback.)
		_pending = true
		RenderingServer.frame_post_draw.connect(_capture, CONNECT_ONE_SHOT)
	return _shots >= frames and not _pending


var _pending := false


func _capture() -> void:
	var img := get_root().get_viewport().get_texture().get_image()
	var dir := out.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var path := out
	if frames > 1:
		path = "%s-%02d.%s" % [out.get_basename(), _shots + 1, out.get_extension()]
	var err := img.save_png(path)
	print("SHOT SCENE saved %s  t=%.2f  (%d x %d, %d frames, %s)" % [path, _t,
		img.get_width(), img.get_height(), _frames, "ok" if err == OK else "ERROR %d" % err])
	_shots += 1
	_pending = false
