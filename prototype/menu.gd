extends Node3D
# ============================================================
# MAIN MENU (Phase E brief 1, section 7) — the first thing the game
# shows. It is NOT a flat screen with a picture of the game on it: it
# is the game's own world, running. A short strip of the stone field
# floats in the grey fog, two carved buildings stand behind it, and the
# creature stands on the strip facing the camera, breathing, pulsing on
# the song's beat and glancing around. The one open eye is the logo.
#
# Everything on screen is built from what already exists:
#   the strip       field.gd's tiles, the same size and the same
#                   Mats.tile() material (flat_mats.gd)
#   the buildings   props.gd's two models, the same Props.building()
#   the fog         camera_rig.gd's backdrop gradient and its far
#                   silhouettes — the rig is instanced whole
#   the creature    creature.tscn, unchanged
#   the buttons     hud.gd's glass pill (Hud.glass_pill), the same
#                   button the end screen draws
#   the colours     WorldPalette for the world, Palette for text
# No new colour, no new font, no image texture.
#
# WHAT THE BUTTONS DO
#   PLAY         starts the endless run at lap 0 (Rules.ENDLESS)
#   LEADERBOARD  the EXISTING leaderboard screen (ui/leaderboard_screen.gd)
#                in its distance mode: GLOBAL / MY COUNTRY, metres. Dim
#                with a note when this build has no Talo key.
#   SETTINGS     sound on/off, the nickname, and the EXISTING account
#                panel (ui/account_panel.gd: consent -> register / log
#                in -> manage / delete). No second account flow was
#                written and none may be.
#   DEV          the level select, only while Progress.UNLOCK_ALL
#
# TWO RULES THIS FILE OBEYS, both learned the hard way (see
# prototype/README.md):
#  - LOADING is painted BEFORE the blocking work. Tapping PLAY changes
#    scene to the run, which validates and builds a lap in one blocking
#    step. The label goes up, the code waits for a really painted frame
#    (with FrameMeter.LABEL_TIMEOUT_MS as the ceiling), and only then
#    changes scene. Copied from level_select.gd on purpose.
#  - The world is built ONE KIND PER FRAME (tiles, then buildings, then
#    the creature). The web renderer compiles a shader the first time
#    something using it is drawn, and that compile blocks the frame:
#    one new shader per frame instead of four in one.
#
# NO MUSIC HERE. The browser will not play audio before a tap anyway,
# and PLAY starts the song — the song's intro IS the run-up. So the
# beat squash is driven by beating BeatClock's own downbeat signal at
# the song's tempo, silently: the creature's pulse listens to that
# signal and nothing else in this scene does.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const Mats := preload("res://prototype/flat_mats.gd")
const Props := preload("res://prototype/props/props.gd")
const LapGen := preload("res://prototype/lap_gen.gd")
const CameraRig := preload("res://prototype/camera_rig.gd")
const Hud := preload("res://prototype/hud.gd")
const Field := preload("res://prototype/field.gd")

const RUN_SCENE := "res://prototype/track_test.tscn"
const SELECT_SCENE := "res://prototype/level_select.tscn"

# ------------------------------------------------------------
# THE SHOT
# ------------------------------------------------------------
# The camera is the game's own (camera_rig.gd: yaw 24°, pitch 54°, FOV
# 55), only closer: the rig works out its distance from the window
# depth it is given, so the depth below is chosen to land on
# MENU_DISTANCE and nothing else.
const MENU_DISTANCE := 17.0
# The rig always looks straight down the field's centre line (its x is
# forced to 0), so the creature is moved off centre instead of the
# camera: the whole stage sits this far along +x, which puts it to the
# RIGHT of the screen (screen-right is world -x at this yaw). That
# leaves the left of the frame for the title and the buttons.
const STAGE_X := 3.6
# The strip, in units either side of the creature. The fog does the
# rest: flat_mats.gd fades anything more than 14 units ahead of the
# window's back edge and more than 2 behind it, so the strip has no
# visible end in either direction.
const STRIP_BACK := 12.0
const STRIP_AHEAD := 24.0
const ROW_DEPTH := Rules.BAR_LENGTH / Rules.ROWS   # 2 units, one tile row per beat
# The field is nine columns wide; the menu shows the middle five. Nine
# fills the frame edge to edge and reads as a road — five reads as the
# strip the brief asks for, floating with fog on both sides, and its two
# bright rims frame the creature instead of crossing the whole screen.
const STRIP_COLS := 5
const COL_FROM := (Rules.COLS - STRIP_COLS) / 2
const COL_TO := COL_FROM + STRIP_COLS - 1
const STRIP_HALF := STRIP_COLS * Rules.TILE * 0.5

# The two buildings: [model, side (-1 left / +1 right), gap from the
# field's edge, height, yaw]. Two, deliberately placed — not the run's
# random field, which would put a different pair behind the menu every
# time it opened.
# The two buildings: [model, side (-1 left / +1 right), gap from the
# strip's edge, height, yaw, z]. Two, deliberately placed — not the
# run's random field, which would stand a different pair behind the
# menu every time it opened. The heights matter: as in monoliths.gd the
# foot is buried at BUILDING_BASE_Y, so a building shorter than 22
# never reaches the slab and is seen lying below it.
# The `_hi` meshes are the carved ones (6k triangles each): in the run
# only the nearest monolith gets them, but the menu has exactly two
# buildings and all the room in the frame, so both are carved.
const BUILDINGS := [
	["building_tall_hi", 1.0, 3.0, 44.0, 0.30, 20.0],
	["building_stacked_hi", -1.0, 20.0, 40.0, -0.42, 30.0],
]
const BUILDING_BASE_Y := -22.0    # as monoliths.gd: the foot sits far below the slab

# The creature stands a little nearer the camera than the point the
# camera looks at, which drops it below the centre line and makes it
# bigger: a figure dead centre reads as a placeholder.
const CREATURE_Z := -3.0

# ------------------------------------------------------------
# THE GREETING (the idle)
# ------------------------------------------------------------
# It faces the lens, looks around, and hops now and then. All of it is
# creature.gd's own pose code driven from here — the body turn is the
# stand's yaw, the head and eye are set_look_target(), the hop is
# on_jump() over player3d.gd's own jump numbers. Nothing animates the
# creature but the creature.
#
# The script, in order, as [what, seconds]. Written out rather than
# rolled at random so it is the same every time Milko opens the menu and
# the same in a screenshot.
# 18 seconds round, three hops: one about every six. Two hops in twenty
# seconds read as asleep; a hop every two reads as a fidget.
const IDLE := [
	["greet", 2.4],
	["left", 2.0],
	["hop", 1.6],
	["greet", 1.6],
	["right", 2.0],
	["hop", 1.6],
	["greet", 1.4],
	["left", 1.8],
	["hop", 1.6],
	["greet", 2.0],
]
const BODY_TURN_DEG := 24.0     # how far the BODY turns on a look-around
const LOOK_SIDE_DEG := 58.0     # ... and how far off the lens the eye goes
const LOOK_DIST := 8.0          # how far away the thing it looks at is
const LOOK_EYE_Y := 1.1         # at about its own eye height
const TURN_LERP := 3.2          # the body turn eases at this rate per second

# The hop is the GAME's jump, scaled down: a greeting, not an escape.
# Airtime falls with it, so the one full turn still lands on the ground.
const Player3D := preload("res://prototype/player3d.gd")
const HOP_SCALE := 0.8
const HOP_V := Player3D.JUMP_VELOCITY_PX * Player3D.WORLD_PER_PX * HOP_SCALE
const HOP_G := Player3D.GRAVITY_PX * Player3D.WORLD_PER_PX

var _stage: Node3D
var _stand: Stand
var _creature: Node3D
var _overlay: Overlay
var _name_edit: LineEdit
var _build_step := 0
var _beat_t := 0.0
var _idle_step := 0
var _idle_t := 0.0
var _base_yaw := 0.0            # the yaw that faces the lens
var _turn := 0.0                # the body's current turn off it, degrees
var _turn_want := 0.0
var _alpha := 0.0             # the overlay fades up while the world is built

@onready var rig: Node3D = $CameraRig
@onready var account_panel: Node2D = $UI/AccountPanel
@onready var lb_screen: Node2D = $UI/LeaderboardScreen

# Which overlay is up. The 3D stays live behind all of them.
enum Sheet { NONE, SETTINGS }
var _panel: int = Sheet.NONE
var _editing_name := false

# Tap targets, recorded while drawing (the same pattern as ui.gd).
var _rects := {}

# LOADING: the tap is taken, the label goes up, and the scene changes
# only once the label has really been painted.
var _loading := false
var _painted := 0
var _painted_at_tap := 0
var _loading_from := 0


# What creature.gd reads off its parent: move_dir, y, on_ground. The
# menu's creature never moves, so all three are their resting values.
class Stand extends Node3D:
	var move_dir := Vector2.ZERO
	var y := 0.0
	var on_ground := true
	var vy := 0.0
	var creature: Node3D = null


# The 2D layer. Node2D is the only thing that can draw, and the menu is
# one thing, so it draws through this and keeps its code in one file.
class Overlay extends Node2D:
	var menu: Node = null
	func _draw() -> void:
		if menu != null:
			menu.draw_overlay(self)


func _ready() -> void:
	FrameMeter.load_scene_started()
	# A page opened with a dev URL switch (?level=N, ?autoplay=1, ?live=1,
	# ?grad=1, ?scale=X — frame_meter.gd) wants the RUN, not the menu:
	# ?level=1 is still the fixed spot for a frame-time reading, and the
	# bot has to reach the run without a tap. The run scene reads them
	# itself, exactly as it did when it was the first scene.
	if FrameMeter.any_url_switch():
		print("MENU skipped: a dev URL switch asked for the run")
		get_tree().change_scene_to_file.call_deferred(RUN_SCENE)
		return
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_apply_render_scale()
	# The menu's copy of the run's light: the same direction, published
	# the same way (brief 6 section 1), so the strip's tiles and the
	# buildings are shaded here exactly as in the run.
	rig.publish_light($CreatureLight)

	_stage = Node3D.new()
	_stage.position = Vector3(STAGE_X, 0.0, 0.0)
	add_child(_stage)

	# The window the camera frames. Its depth is what sets the camera's
	# distance, so it is solved from MENU_DISTANCE rather than picked.
	var depth: float = Rules.BAR_LENGTH * ((MENU_DISTANCE - CameraRig.CAMERA_DISTANCE_AT_2_2)
		/ CameraRig.CAMERA_DISTANCE_PER_BAR + 2.2)
	rig.set_window_depth(depth)
	rig.set_window(-depth * 0.5)        # so the rig looks at z = 0, where the creature stands

	_overlay = Overlay.new()
	_overlay.menu = self
	$UI.add_child(_overlay)
	_name_edit = _make_name_edit()
	$UI.add_child(_name_edit)
	account_panel.closed.connect(func() -> void: _overlay.queue_redraw())
	lb_screen.closed.connect(func() -> void: _overlay.queue_redraw())
	# JOIN on the board: the same account panel SETTINGS opens.
	lb_screen.join_requested.connect(func() -> void:
		lb_screen.close()
		account_panel.open())
	# A best run that has not reached the board yet goes up as soon as the
	# player is signed in — now, or the moment they register in SETTINGS.
	Talo.auth_changed.connect(_post_best)
	_post_best()

	if FrameMeter.enabled():
		$UI.add_child(FrameMeter.new())
	print("MENU season %d, best %d m, %s" % [LapGen.SEASON_SEED,
		Progress.best_distance_for(LapGen.SEASON_SEED),
		"signed in as " + Talo.identifier if Talo.logged_in() else "guest"])


# The run scales the 3D down on a phone (track_test.gd RENDER SCALE).
# The menu draws the same shaders over the same screen, so it does the
# same thing — and the 2D overlay stays at full resolution either way.
func _apply_render_scale() -> void:
	var sc := 0.75 if (OS.has_feature("web") or OS.has_feature("mobile")) else 1.0
	get_viewport().scaling_3d_scale = sc


func _on_frame_drawn() -> void:
	_painted += 1


# ------------------------------------------------------------
# BUILDING THE WORLD — one kind per frame
# ------------------------------------------------------------
func _build_next() -> void:
	match _build_step:
		0:
			_build_strip()
		1:
			_build_buildings()
		2:
			_build_creature()
		3:
			_warm_dust()
		4:
			FrameMeter.load_mark("menu", "", true)
			FrameMeter.load_done()
	_build_step += 1


# The field's own tiles: same size, same material, same outer-rim flag,
# so the strip is the field — not something that looks like it.
func _build_strip() -> void:
	var rows := int(round((STRIP_BACK + STRIP_AHEAD) / ROW_DEPTH))
	var half := Vector3(Rules.TILE, Field.THICK, ROW_DEPTH) * 0.5
	for col in range(COL_FROM, COL_TO + 1):
		# Which x side of this column is the strip's bright outer rim.
		var outer := Vector2(1.0 if col == COL_FROM else 0.0, 1.0 if col == COL_TO else 0.0)
		for row in rows:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(Rules.TILE, Field.THICK, ROW_DEPTH)
			mi.mesh = bm
			mi.material_override = Mats.tile(0, half, outer)
			mi.position = Vector3(Rules.col_x(col), -Field.THICK * 0.5,
				-STRIP_BACK + (row + 0.5) * ROW_DEPTH)
			_stage.add_child(mi)


# The run's fog swallows everything more than 14 units ahead of the
# window's back edge, because in a run that is two bars ahead and the
# player must not read the course from there. The menu has no course to
# hide and its buildings are 30-40 units tall, so with the run's fade
# they are either a blank white wall (their near face) or gone. The menu
# therefore gives them ITS OWN copy of the same material with the fade
# pushed out — one duplicate, same shader, nothing to prewarm — and the
# run's shared material is left exactly as it was.
const MENU_FOG := Vector2(18.0, 48.0)

func _building_material() -> Material:
	var m: ShaderMaterial = Props.building(false).duplicate()
	m.set_shader_parameter("fade", Quaternion(MENU_FOG.x, MENU_FOG.y,
		Mats.FADE_BEHIND_START, Mats.FADE_BEHIND_END))
	return m


func _build_buildings() -> void:
	var mat := _building_material()
	for i in BUILDINGS.size():
		var spec: Array = BUILDINGS[i]
		var model := String(spec[0])
		var side := float(spec[1])
		var height := float(spec[3])
		var msize: Vector3 = Props.size_of(model)
		var k := height / msize.y
		var reach: float = maxf(msize.x, msize.z) * k * 0.5
		var node := Props.make(model, msize * k, "base", mat, rad_to_deg(float(spec[4])))
		node.position = Vector3(side * (STRIP_HALF + float(spec[2]) + reach),
			BUILDING_BASE_Y, float(spec[5]))
		_stage.add_child(node)


func _build_creature() -> void:
	_stand = Stand.new()
	# Square to the lens. The model's eye looks down +z — the way the
	# player runs, which is AWAY from the camera — so the stand is turned
	# half a turn plus the camera's own bearing (its yaw off the field
	# axis), and the eye comes back down the lens.
	_base_yaw = PI + deg_to_rad(CameraRig.CAMERA_YAW_DEG)
	_stand.rotation.y = _base_yaw
	_stand.position.z = CREATURE_Z
	_stage.add_child(_stand)
	_creature = load("res://prototype/creature.tscn").instantiate()
	_stand.add_child(_creature)
	_stand.creature = _creature
	_begin_idle("greet")


# The landing's dust puff has a material of its own, and the web renderer
# compiles a material the first time something using it is DRAWN — in the
# run that is what prewarm.gd is for, and the same rule holds here or the
# first hop's landing is a hitch. One invisible copy, drawn once, from
# prewarm's own code rather than a second copy of it.
func _warm_dust() -> void:
	var warm: Node3D = load("res://prototype/prewarm.gd").new()
	_stage.add_child(warm)
	warm.global_position = _stand.global_position
	warm.warm_bursts([_creature.dust()])
	warm.step()


func _camera_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3(0.0, 8.0, -14.0)


# WHY THE LOOK TARGET IS MOVED BEFORE IT IS HANDED OVER.
# creature.gd measures the angle to its target in WORLD space and then
# applies it as a yaw in its OWN frame. In the run those are the same
# frame — player3d never rotates — so it is exactly right there. The
# menu's creature IS rotated (it is turned to face the camera), so a
# world point would come out as a yaw off by that whole rotation: the
# first build of this screen had it looking a quarter-turn wide, which
# is the "it stands in profile" Milko saw. The target is therefore
# rotated into the stand's frame first, and the creature then does the
# same sum it does in the run.
func _look_point(world: Vector3) -> Vector3:
	if _stand == null:
		return world
	var here: Vector3 = _stand.global_position
	return here + _stand.global_transform.basis.inverse() * (world - here)


# A point LOOK_DIST away, `off` degrees to one side of the lens, at eye
# height: something off in the fog for it to look at.
func _side_point(off_deg: float) -> Vector3:
	var here: Vector3 = _stand.global_position
	var to_cam := _camera_point() - here
	to_cam.y = 0.0
	if to_cam.length() < 0.001:
		to_cam = Vector3.BACK
	var dir := to_cam.normalized().rotated(Vector3.UP, deg_to_rad(off_deg))
	return here + dir * LOOK_DIST + Vector3(0.0, LOOK_EYE_Y, 0.0)


# ------------------------------------------------------------
# THE GREETING, one step at a time
# ------------------------------------------------------------
func _begin_idle(what: String) -> void:
	if _creature == null:
		return
	match what:
		"left":
			_turn_want = BODY_TURN_DEG
			_creature.set_look_target(_look_point(_side_point(LOOK_SIDE_DEG)))
		"right":
			_turn_want = -BODY_TURN_DEG
			_creature.set_look_target(_look_point(_side_point(-LOOK_SIDE_DEG)))
		"hop":
			_turn_want = 0.0
			_creature.set_look_target(_look_point(_camera_point()))
			_hop()
		_:
			_turn_want = 0.0
			_creature.set_look_target(_look_point(_camera_point()))


func _tick_idle(delta: float) -> void:
	if _creature == null:
		return
	_idle_t += delta
	if _idle_t >= float(IDLE[_idle_step][1]):
		_idle_t = 0.0
		_idle_step = (_idle_step + 1) % IDLE.size()
		_begin_idle(String(IDLE[_idle_step][0]))
	# The body eases after the head instead of snapping with it.
	_turn = lerpf(_turn, _turn_want, 1.0 - exp(-TURN_LERP * delta))
	_stand.rotation.y = _base_yaw + deg_to_rad(_turn)
	# The hop, run exactly as player3d runs it: the same launch speed and
	# gravity scaled by HOP_SCALE, the creature told once at take-off.
	# It lands itself — the landing squash, the footfall and the dust
	# puff are creature.gd noticing on_ground come back.
	if not _stand.on_ground:
		_stand.vy -= HOP_G * delta
		_stand.y += _stand.vy * delta
		if _stand.y <= 0.0:
			_stand.y = 0.0
			_stand.vy = 0.0
			_stand.on_ground = true
		_stand.position.y = _stand.y


func _hop() -> void:
	if not _stand.on_ground:
		return
	_stand.on_ground = false
	_stand.vy = HOP_V
	_creature.on_jump(2.0 * HOP_V / HOP_G)


# ------------------------------------------------------------
# PER FRAME
# ------------------------------------------------------------
func _process(delta: float) -> void:
	if _painted >= 1:
		FrameMeter.first_frame_painted()
	if _build_step <= 4:
		_build_next()
	_alpha = minf(1.0, _alpha + delta * 2.2)

	# The silent beat (see the header): the creature's squash is wired
	# to BeatClock.downbeat, so the menu beats it at the song's tempo.
	var bar_s: float = maxf(BeatClock.beat_interval, 0.2) * 4.0
	_beat_t += delta
	if _beat_t >= bar_s:
		_beat_t -= bar_s
		BeatClock.downbeat.emit(0)

	_tick_idle(delta)

	if _loading:
		_tick_loading()
	_overlay.queue_redraw()


# ------------------------------------------------------------
# LOADING (the rule: paint the label, THEN do the blocking work)
# ------------------------------------------------------------
func _begin_loading() -> void:
	_loading = true
	_painted_at_tap = _painted
	_loading_from = Time.get_ticks_msec()
	FrameMeter.load_begin()
	_overlay.queue_redraw()


func _tick_loading() -> void:
	var waited := Time.get_ticks_msec() - _loading_from
	if _painted - _painted_at_tap < 2 and waited < FrameMeter.LABEL_TIMEOUT_MS:
		return
	if _painted - _painted_at_tap < 2:
		push_warning("MENU LOADING: no painted frame after %d ms; carrying on" % waited)
		FrameMeter.first_frame_painted()
	FrameMeter.load_label_painted(_painted - _painted_at_tap < 2)
	set_process(false)
	get_tree().change_scene_to_file.call_deferred(RUN_SCENE)


func _play() -> void:
	if _loading:
		return
	Rules.ENDLESS = true
	Rules.START_LAP = 0
	_begin_loading()


# ------------------------------------------------------------
# INPUT
# ------------------------------------------------------------
func _overlay_open() -> bool:
	return account_panel.visible or lb_screen.visible


# Section 8: the stored best goes to the board once (Talo.post_best_distance
# does nothing when it is already there). Fire-and-forget; the menu has no
# rank line to show, the end screen does.
func _post_best() -> void:
	var line: String = await Talo.post_best_distance(LapGen.SEASON_SEED)
	if line != "":
		print("MENU posted best: %s" % line)


func _input(event: InputEvent) -> void:
	if _overlay_open() or _loading:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _panel != Sheet.NONE:
			_close_panel()
		return
	var pos: Variant = null
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		pos = event.position
	if pos == null:
		return
	if _editing_name:
		_finish_name_edit()
	for key in _rects:
		if _rects[key].has_point(pos):
			_tap(String(key))
			return
	if _panel == Sheet.SETTINGS:
		_close_panel()


func _tap(what: String) -> void:
	match what:
		"play":
			_play()
		"leaderboard":
			if Talo.configured():
				lb_screen.open_distance()
		"settings", "name_chip":
			_panel = Sheet.SETTINGS
		"close":
			_close_panel()
		"sound_on":
			Progress.set_sound(true)
		"sound_off":
			Progress.set_sound(false)
		"random":
			Profile.reroll()
		"edit":
			_begin_name_edit()
		"account":
			account_panel.open()
		"dev":
			get_tree().change_scene_to_file.call_deferred(SELECT_SCENE)


func _close_panel() -> void:
	if _editing_name:
		_finish_name_edit()
	_panel = Sheet.NONE


# ------------------------------------------------------------
# THE NICKNAME (Profile — the local guest name, no account needed)
# ------------------------------------------------------------
func _make_name_edit() -> LineEdit:
	var e := LineEdit.new()
	e.max_length = Profile.MAX_LENGTH
	e.visible = false
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.45)
	box.border_color = Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.8)
	box.set_border_width_all(1)
	e.add_theme_stylebox_override("normal", box)
	e.add_theme_stylebox_override("focus", box)
	e.add_theme_color_override("font_color", Palette.EDGE)
	e.add_theme_color_override("caret_color", Palette.EDGE)
	e.add_theme_font_size_override("font_size", 20)
	e.text_submitted.connect(func(_t: String) -> void: _finish_name_edit())
	return e


func _begin_name_edit() -> void:
	var rect: Rect2 = _rects.get("name_field", Rect2())
	if rect.size.x <= 0.0:
		return
	_editing_name = true
	_name_edit.text = Profile.username
	_name_edit.position = rect.position
	_name_edit.size = rect.size
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func _finish_name_edit() -> void:
	if not _editing_name:
		return
	_editing_name = false
	Profile.set_username(_name_edit.text)
	_name_edit.visible = false
	_name_edit.release_focus()


# ------------------------------------------------------------
# DRAWING — called by the Overlay child, which is the only Node2D here
# ------------------------------------------------------------
# THE PHONE'S REAL SIZES. The 2D canvas is 540 units tall whatever the
# screen is (project.godot: 960x540, stretch canvas_items), and the test
# iPhone hands the game 1179 device pixels at 3 per point — so one canvas
# unit is 0.73 pt and the brief's "tap targets >= 48 pt" means
# TAP_MIN units, not 48. Every button below is at least that tall.
# MARGIN also has to clear the notch, which in landscape eats about 44 pt
# off one side.
const TAP_MIN := 66.0
const MARGIN := 88.0
const BOTTOM := 30.0            # clear of the home indicator (~22 pt)

func draw_overlay(c: CanvasItem) -> void:
	_rects = {}
	var screen := get_viewport().get_visible_rect().size
	var font := ThemeDB.fallback_font

	# Landscape only, the same words the run uses (ui/ui.gd).
	if screen.y > screen.x:
		Hud.centre_text(c, font, "ROTATE YOUR PHONE", Vector2(screen.x * 0.5, screen.y * 0.5 - 24), 26, Palette.EDGE)
		Hud.centre_text(c, font, "This one is played sideways", Vector2(screen.x * 0.5, screen.y * 0.5 + 18), 16, Palette.TEXT)
		return

	if _loading:
		c.draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.86), true)
		Hud.centre_text(c, font, "LOADING", screen * 0.5, 26, Palette.GOAL)
		Hud.centre_text(c, font, "building the course", screen * 0.5 + Vector2(0, 30), 12,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.8))
		return

	# The leaderboard is a whole screen, not a sheet: while it is up the
	# menu draws nothing of its own but the dim, and the world stays live
	# behind it.
	if lb_screen.visible:
		c.draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.6), true)
		return

	var a := _alpha
	_draw_title(c, font, a)
	_draw_buttons(c, screen, font, a)
	_draw_name_chip(c, screen, font, a)
	if Progress.UNLOCK_ALL:
		var dev := Rect2(Vector2(screen.x - MARGIN - 78.0, screen.y - BOTTOM - 44.0), Vector2(78.0, 44.0))
		_rects["dev"] = dev
		Hud.glass_pill(c, dev, Palette.TEXT, 0.5 * a)
		Hud.centre_text(c, font, "DEV", dev.get_center() + Vector2(0, -1), 13, Color(1, 1, 1, 0.5 * a))
	# Anything open dims the menu behind it. The account panel is the
	# settings sheet's own next screen, so while it is up the sheet
	# stands down: it is a Node2D of its own and would otherwise be
	# drawn over (this node's Overlay is added last, so it draws last).
	if _panel == Sheet.SETTINGS or account_panel.visible:
		c.draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.72), true)
	if _panel == Sheet.SETTINGS and not account_panel.visible:
		# The sheet is modal: the menu's own buttons are behind it, so
		# their tap targets are dropped and only the sheet's are live.
		_rects = {}
		_draw_settings(c, screen, font)


# THE LAST GAME, then a cyan hairline, then the best distance. The
# title is drawn letter by letter so it can carry real tracking — a
# title without it reads as a default label, which is the look this
# game is not having.
const TITLE_SIZE := 38
const TITLE_TRACK := 6.0

func _draw_title(c: CanvasItem, font: Font, a: float) -> void:
	var x := MARGIN
	var y := 108.0
	var w := _tracked(c, font, "THE LAST GAME", Vector2(x, y), TITLE_SIZE, TITLE_TRACK,
		Color(1, 1, 1, 0.95 * a))
	c.draw_line(Vector2(x, y + 16.0), Vector2(x + w, y + 16.0),
		Color(WorldPalette.SAFE.r, WorldPalette.SAFE.g, WorldPalette.SAFE.b, 0.55 * a), 1.0)
	var best := Progress.best_distance_for(LapGen.SEASON_SEED)
	if best > 0:
		_tracked(c, font, "BEST " + Hud.metres(best), Vector2(x, y + 46.0), 17, 2.0,
			Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.95 * a))
	else:
		_tracked(c, font, "HOW FAR CAN YOU GET", Vector2(x, y + 46.0), 15, 2.0,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.75 * a))
	_tracked(c, font, "SEASON %d" % LapGen.SEASON_SEED, Vector2(x, y + 74.0), 11, 2.0,
		Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.45 * a))


# Draws `text` with `track` extra pixels between letters; returns its
# total width so a rule can be drawn under it.
func _tracked(c: CanvasItem, font: Font, text: String, at: Vector2, size: int, track: float, col: Color) -> float:
	var x := at.x
	for i in text.length():
		var ch := text[i]
		c.draw_string(font, Vector2(x, at.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + track
	return maxf(0.0, x - at.x - track)


func _draw_buttons(c: CanvasItem, screen: Vector2, font: Font, a: float) -> void:
	var x := MARGIN
	var row_y := screen.y - BOTTOM - TAP_MIN
	var play := Rect2(Vector2(x, row_y - 110.0), Vector2(304.0, 96.0))
	_rects["play"] = play
	Hud.glass_pill(c, play, WorldPalette.SAFE, a)
	Hud.centre_text(c, font, "PLAY", play.get_center() + Vector2(0, 2), 36, Color(1, 1, 1, 0.96 * a))

	var lb := Rect2(Vector2(x, row_y), Vector2(190.0, TAP_MIN))
	_rects["leaderboard"] = lb
	if Talo.configured():
		Hud.glass_pill(c, lb, Palette.GOAL, 0.9 * a)
		Hud.centre_text(c, font, "LEADERBOARD", lb.get_center() + Vector2(0, -1), 14, Color(1, 1, 1, 0.92 * a))
	else:
		# No Talo key in this build: honestly dim, and it says why.
		Hud.glass_pill(c, lb, Palette.TEXT, 0.45 * a)
		Hud.centre_text(c, font, "LEADERBOARD", lb.get_center() + Vector2(0, -4), 14, Color(1, 1, 1, 0.45 * a))
		Hud.centre_text(c, font, "not set up in this build", lb.get_center() + Vector2(0, 14), 10,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.5 * a))

	var st := Rect2(Vector2(x + 202.0, row_y), Vector2(114.0, TAP_MIN))
	_rects["settings"] = st
	Hud.glass_pill(c, st, Palette.TEXT, 0.8 * a)
	Hud.centre_text(c, font, "SETTINGS", st.get_center() + Vector2(0, -1), 13, Color(1, 1, 1, 0.85 * a))


# Top right: who is playing. A tap goes to the same place SETTINGS does,
# because that is where the nickname and the account live.
func _draw_name_chip(c: CanvasItem, screen: Vector2, font: Font, a: float) -> void:
	var label := Profile.username
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 76.0
	var chip := Rect2(Vector2(screen.x - MARGIN - w, 72.0), Vector2(w, TAP_MIN))
	_rects["name_chip"] = chip
	var tint: Color = WorldPalette.SAFE if Talo.logged_in() else Palette.TEXT
	Hud.glass_pill(c, chip, tint, 0.85 * a)
	c.draw_circle(chip.position + Vector2(24.0, chip.size.y * 0.5), 4.5,
		Color(tint.r, tint.g, tint.b, 0.95 * a))
	c.draw_string(font, chip.position + Vector2(40.0, chip.size.y * 0.5 + 6.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.9 * a))


# ------------------------------------------------------------
# SETTINGS — sound, the nickname, and the door to the account panel
# ------------------------------------------------------------
func _draw_settings(c: CanvasItem, screen: Vector2, font: Font) -> void:
	var pw := 520.0
	var ph := 406.0
	var panel := Rect2(screen * 0.5 - Vector2(pw, ph) * 0.5, Vector2(pw, ph))
	# A panel this big cannot be a tinted pane — the tint becomes a wash.
	# It is the background colour first, then the glass edge on top.
	c.draw_rect(panel, Color(0.04, 0.05, 0.08, 0.93), true)
	Hud.glass_pill(c, panel, WorldPalette.SAFE, 0.45)
	var px := panel.position.x
	var py := panel.position.y
	var cx := panel.get_center().x
	Hud.centre_text(c, font, "SETTINGS", Vector2(cx, py + 44.0), 21, Color(1, 1, 1, 0.92))

	# Sound
	c.draw_string(font, Vector2(px + 34.0, py + 140.0), "SOUND",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.9))
	var on_rect := Rect2(Vector2(cx + 16.0, py + 100.0), Vector2(92.0, TAP_MIN))
	var off_rect := Rect2(Vector2(cx + 118.0, py + 100.0), Vector2(92.0, TAP_MIN))
	_rects["sound_on"] = on_rect
	_rects["sound_off"] = off_rect
	_toggle(c, font, on_rect, "ON", Progress.sound_on)
	_toggle(c, font, off_rect, "OFF", not Progress.sound_on)

	# Nickname
	c.draw_string(font, Vector2(px + 34.0, py + 200.0), "NAME",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.9))
	var field := Rect2(Vector2(px + 34.0, py + 214.0), Vector2(230.0, TAP_MIN))
	_rects["name_field"] = field
	if not _editing_name:
		Hud.glass_pill(c, field, WorldPalette.SAFE, 0.6)
		Hud.centre_text(c, font, Profile.username, field.get_center() + Vector2(0, -1), 19, Color(1, 1, 1, 0.92))
	if Profile.claimed:
		c.draw_string(font, Vector2(px + 280.0, py + 254.0), "your account name",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.6))
	else:
		var rnd := Rect2(Vector2(px + 276.0, py + 214.0), Vector2(100.0, TAP_MIN))
		var ed := Rect2(Vector2(px + 388.0, py + 214.0), Vector2(98.0, TAP_MIN))
		_rects["random"] = rnd
		_rects["edit"] = ed
		Hud.glass_pill(c, rnd, Palette.TEXT, 0.7)
		Hud.centre_text(c, font, "RANDOM", rnd.get_center() + Vector2(0, -1), 13, Color(1, 1, 1, 0.85))
		Hud.glass_pill(c, ed, Palette.TEXT, 0.7)
		Hud.centre_text(c, font, "EDIT", ed.get_center() + Vector2(0, -1), 13, Color(1, 1, 1, 0.85))

	# The account: the existing panel, nothing new.
	if Talo.configured():
		var acc := Rect2(Vector2(px + 34.0, py + 302.0), Vector2(pw - 68.0, 72.0))
		_rects["account"] = acc
		Hud.glass_pill(c, acc, Palette.GOAL, 0.9)
		var label := "ACCOUNT" if Talo.logged_in() else "REGISTER  ·  LOG IN"
		Hud.centre_text(c, font, label, acc.get_center() + Vector2(0, -6), 17, Color(1, 1, 1, 0.92))
		Hud.centre_text(c, font, "post your distance to the leaderboard",
			acc.get_center() + Vector2(0, 16), 11,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.7))
	else:
		Hud.centre_text(c, font, "accounts are not set up in this build",
			Vector2(cx, py + 340.0), 13,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.55))

	var close := Rect2(Vector2(px + pw - 16.0 - TAP_MIN, py + 16.0), Vector2(TAP_MIN, TAP_MIN))
	_rects["close"] = close
	Hud.glass_pill(c, close, Palette.TEXT, 0.7)
	Hud.centre_text(c, font, "X", close.get_center() + Vector2(0, -1), 16, Color(1, 1, 1, 0.85))


func _toggle(c: CanvasItem, font: Font, rect: Rect2, label: String, on: bool) -> void:
	Hud.glass_pill(c, rect, WorldPalette.SAFE if on else Palette.TEXT, 1.0 if on else 0.5)
	Hud.centre_text(c, font, label, rect.get_center() + Vector2(0, -1), 14,
		Color(1, 1, 1, 0.95 if on else 0.5))
