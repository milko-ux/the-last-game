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
#   the fog         camera_rig.gd's backdrop gradient and its far
#                   silhouettes — the rig is instanced whole
#   the creature    creature.tscn, unchanged
#   the buttons     hud.gd's capsule button (Hud.capsule_button), the
#                   layered button of docs/concept/UI/ref-button-layers.png
#   THE LAYOUT      docs/concept/UI/ref-menu.png (2026-10-22, roadmap
#                   step 4): the title centred on top, the creature in
#                   the middle, PLAY big at the bottom between two round
#                   buttons (trophy = leaderboard, gear = settings), the
#                   name top right, BEST bottom left. The mockup's neon
#                   on black is the dropped synthwave look: its layout and
#                   its buttons are kept, its colours are the canyon's.
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
const LapGen := preload("res://prototype/lap_gen.gd")
const CameraRig := preload("res://prototype/camera_rig.gd")
const Hud := preload("res://prototype/hud.gd")
const Field := preload("res://prototype/field.gd")
const Looks := preload("res://prototype/looks.gd")
const Scarf := preload("res://prototype/scarf.gd")
const Press := preload("res://prototype/press.gd")
const TimeOfDay := preload("res://prototype/time_of_day.gd")

const RUN_SCENE := "res://prototype/track_test.tscn"
const SELECT_SCENE := "res://prototype/level_select.tscn"

# ------------------------------------------------------------
# THE SHOT
# ------------------------------------------------------------
# The camera is the game's own rig (camera_rig.gd, FOV 44). Its window
# depth -- what the distance fade in flat_mats.gd measures from -- is
# solved from MENU_DISTANCE as before; the SHOT is the mockup's
# (docs/concept/UI/ref-menu.png, 2026-10-22): straight down the strip,
# low, and close enough that the creature is the hero of the screen
# (MENU_YAW_DEG / MENU_PITCH_DEG / MENU_CAM_DISTANCE, the rig's
# yaw_deg / pitch_deg / distance). The run's 24 / 42 / 32.5 is untouched.
# MENU_DISTANCE was 17 under the old 55-degree lens; x 1.29 for the
# 44-degree one.
const MENU_DISTANCE := 22.0
const MENU_YAW_DEG := 0.0
const MENU_PITCH_DEG := 22.0
const MENU_CAM_DISTANCE := 12.0
# The rig always looks straight down the field's centre line (its x is
# forced to 0), so the creature is moved off centre instead of the
# camera: the whole stage sits this far along +x (screen-right is world
# -x at this yaw). 3.6 put it right of the left-hand buttons; the
# mockup's layout (2026-10-22) puts it in the middle, under the title.
const STAGE_X := 0.0
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

# NO BUILDINGS (2026-10-22). Two grey carved buildings from the stone-
# and-fog look stood either side of the strip; the canyon replaced that
# look, and the mockup (docs/concept/UI/ref-menu.png) has open air there.
# Gone from the menu with their 12k triangles.

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
var _press := Press.new()

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
	# FIRST LAUNCH (2026-10-23, "zero menus before the first run"; Apple's
	# onboarding guidance: teach by playing). Until a run has been played
	# the game opens straight into one -- its TAP TO START and lap 0 are
	# the tutorial -- and this menu is what the first game over leads to.
	if not Progress.played:
		print("MENU skipped: first launch, straight into a run")
		get_tree().change_scene_to_file.call_deferred(RUN_SCENE)
		return
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	_apply_render_scale()
	# The menu's copy of the run's light: the same direction, published
	# the same way (brief 6 section 1), so the strip's tiles and the
	# buildings are shaded here exactly as in the run.
	rig.publish_light($CreatureLight)
	TimeOfDay.light = $CreatureLight
	Looks.apply_world()   # the current look variant's fog and pillars (looks.gd)

	_stage = Node3D.new()
	_stage.position = Vector3(STAGE_X, 0.0, 0.0)
	add_child(_stage)

	# The window the camera frames. Its depth is what sets the camera's
	# distance, so it is solved from MENU_DISTANCE rather than picked.
	var depth: float = Rules.BAR_LENGTH * ((MENU_DISTANCE - CameraRig.CAMERA_DISTANCE_AT_2_2)
		/ CameraRig.CAMERA_DISTANCE_PER_BAR + 2.2)
	rig.set_window_depth(depth)
	rig.set_window(-depth * 0.5)        # so the rig looks at z = 0, where the creature stands
	rig.yaw_deg = MENU_YAW_DEG
	rig.pitch_deg = MENU_PITCH_DEG
	rig.distance = MENU_CAM_DISTANCE

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
			_build_creature()
		2:
			_warm_dust()
		3:
			_build_shadows()
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


func _build_creature() -> void:
	_stand = Stand.new()
	# Square to the lens. The model's eye looks down +z — the way the
	# player runs, which is AWAY from the camera — so the stand is turned
	# half a turn plus the camera's own bearing (its yaw off the field
	# axis), and the eye comes back down the lens.
	_base_yaw = PI + deg_to_rad(MENU_YAW_DEG)
	_stand.rotation.y = _base_yaw
	_stand.position.z = CREATURE_Z
	_stage.add_child(_stand)
	_creature = load("res://prototype/creature.tscn").instantiate()
	_stand.add_child(_creature)
	# The scarf, always: before it is earned it is the teaser (the label
	# over the creature, _draw_scarf_teaser), after it it is simply worn.
	_creature.wear_scarf(true)
	_stand.creature = _creature
	_begin_idle("greet")


# The creature's drop shadow (brief 6 section 2): the run's own shadow
# system with one caster. Its own build frame: a MultiMesh is its own
# pipeline variant, so its first draw is a shader compile like the rest.
func _build_shadows() -> void:
	var sh: MultiMeshInstance3D = load("res://prototype/shadows.gd").new()
	sh.name = "Shadows"
	sh.creature = _creature
	add_child(sh)


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
	# A button acts when the finger lifts on it (press.gd); a tap that
	# lands on no button closes the settings sheet, as before.
	var down := Press.is_down(event)
	if down and _editing_name:
		_finish_name_edit()
	var tapped := _press.feed(event, _rects)
	if tapped != "":
		_tap(tapped)
	elif down and _press.key == "" and _panel == Sheet.SETTINGS:
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
		"effects_on":
			Progress.set_effects(true)
		"effects_off":
			Progress.set_effects(false)
		"music_on":
			Progress.set_music(true)
		"music_off":
			Progress.set_music(false)
		"random":
			Profile.reroll()
		"edit", "name_field":
			if not Profile.claimed:
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
	# menu draws nothing of its own, and the world stays live behind it.
	# Not even the dim: this Overlay is added after the leaderboard, so it
	# draws OVER it, and a dim here was a 60 % dark sheet over every row
	# (2026-09-29, "barely visible" on the phone). The screen dims itself.
	# The account panel the same (2026-10-23): with the menu centred, its
	# title and PLAY were drawn straight over the panel's card.
	if lb_screen.visible or account_panel.visible:
		return

	var a := _alpha
	_draw_title(c, screen, font, a)
	_draw_buttons(c, screen, font, a)
	_draw_name_chip(c, screen, font, a)
	_draw_scarf_teaser(c, font, a)
	if Progress.UNLOCK_ALL:
		var dev := Rect2(Vector2(screen.x - MARGIN - 86.0, screen.y - BOTTOM - TAP_MIN), Vector2(86.0, TAP_MIN))
		_rects["dev"] = dev
		Hud.button(c, dev, "DEV", "glass", _press.state("dev"), 13, 0.6 * a)
	# The settings sheet dims the menu behind it.
	if _panel == Sheet.SETTINGS:
		c.draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.72), true)
		# The sheet is modal: the menu's own buttons are behind it, so
		# their tap targets are dropped and only the sheet's are live.
		_rects = {}
		_draw_settings(c, screen, font)


# THE LAST over GAME, centred, as the mockup stacks it; bottom left the
# best distance in the goal's amber (or the game's question before there
# is one) and the season under it. The lettering is Hud's (tracked,
# outlined, GAME emboldened): the screens share it.
const TITLE_TOP := 64.0
const TITLE_GAME := 128.0

func _draw_title(c: CanvasItem, screen: Vector2, font: Font, a: float) -> void:
	var cx := screen.x * 0.5
	Hud.title(c, font, "THE LAST", cx, TITLE_TOP, 24, 10.0, Color(1, 1, 1, 0.95 * a))
	Hud.title(c, Hud.bold(), "GAME", cx, TITLE_GAME, 66, 6.0, Color(1, 1, 1, 0.97 * a))
	var y := screen.y - BOTTOM - 30.0
	var best := Progress.best_distance_for(LapGen.SEASON_SEED)
	if best > 0:
		Hud.tracked(c, Hud.bold(), "BEST " + Hud.metres(best), Vector2(MARGIN, y), 19, 2.0,
			Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.97 * a))
	else:
		Hud.tracked(c, font, "HOW FAR CAN YOU GET", Vector2(MARGIN, y), 15, 2.0, Color(1, 1, 1, 0.85 * a))
	Hud.tracked(c, font, "SEASON %d" % LapGen.SEASON_SEED, Vector2(MARGIN, y + 22.0), 11, 2.0, Color(1, 1, 1, 0.6 * a))


# PLAY, big and cyan (cyan = safe: go), centred at the bottom; the two
# round dark-glass buttons either side of it, a trophy for the
# leaderboard and a gear for settings. The glass is dark so the white
# icons read on the light sky (the canyon's lesson, 2026-10-21). Every
# button shows the state the finger gives it (press.gd); the trophy is
# DISABLED when this build has no Talo key.
const PLAY_SIZE := Vector2(300.0, 84.0)
const ROUND := 78.0
const ROUND_GAP := 28.0

func _draw_buttons(c: CanvasItem, screen: Vector2, font: Font, a: float) -> void:
	var play := Rect2(Vector2(screen.x * 0.5 - PLAY_SIZE.x * 0.5, screen.y - BOTTOM - PLAY_SIZE.y - 8.0), PLAY_SIZE)
	_rects["play"] = play
	var ps := _press.state("play")
	var go := Hud.style("go")
	Hud.capsule_button(c, play, go[0], go[1], a, go[3], ps)
	var label_w: float = Hud.bold().get_string_size("PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var group := 22.0 + 14.0 + label_w
	var left := play.get_center().x - group * 0.5
	var mid_y := play.get_center().y + Hud.sink(ps).y
	c.draw_colored_polygon(PackedVector2Array([Vector2(left, mid_y - 12.0), Vector2(left + 22.0, mid_y),
		Vector2(left, mid_y + 12.0)]), Color(Hud.INK, a))
	c.draw_string(Hud.bold(), Vector2(left + 36.0, mid_y + 12.0), "PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(Hud.INK, a))

	var row_mid := play.get_center().y
	var lb := Rect2(Vector2(play.position.x - ROUND_GAP - ROUND, row_mid - ROUND * 0.5), Vector2(ROUND, ROUND))
	var lb_state := _press.state("leaderboard", Talo.configured())
	if Talo.configured():
		_rects["leaderboard"] = lb
	Hud.capsule_button(c, lb, Hud.GLASS_TOP, Hud.GLASS_BOTTOM, 0.95 * a, 0.0, lb_state)
	_draw_trophy(c, lb.get_center() + Hud.sink(lb_state), Color(1, 1, 1, (0.5 if lb_state == Hud.Btn.DISABLED else 0.95) * a))

	var st := Rect2(Vector2(play.end.x + ROUND_GAP, row_mid - ROUND * 0.5), Vector2(ROUND, ROUND))
	_rects["settings"] = st
	var st_state := _press.state("settings")
	Hud.capsule_button(c, st, Hud.GLASS_TOP, Hud.GLASS_BOTTOM, 0.95 * a, 0.0, st_state)
	_draw_gear(c, st.get_center() + Hud.sink(st_state), Color(1, 1, 1, 0.95 * a),
		Color(Hud.GLASS_TOP.lerp(Hud.GLASS_BOTTOM, 0.5), a))


# The trophy: a cup with two handles on a stem and a base, ~30 across.
func _draw_trophy(c: CanvasItem, at: Vector2, col: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-11, -14), at + Vector2(11, -14), at + Vector2(10, -5),
		at + Vector2(6, 1), at + Vector2(2, 3), at + Vector2(-2, 3), at + Vector2(-6, 1), at + Vector2(-10, -5)]), col)
	c.draw_arc(at + Vector2(-11, -8), 5.0, PI * 0.5, PI * 1.5, 12, col, 2.6, true)
	c.draw_arc(at + Vector2(11, -8), 5.0, -PI * 0.5, PI * 0.5, 12, col, 2.6, true)
	c.draw_rect(Rect2(at + Vector2(-2.5, 3), Vector2(5, 7)), col, true)
	c.draw_rect(Rect2(at + Vector2(-9, 10), Vector2(18, 4.5)), col, true)


# The gear: a disc, eight teeth, a hole in the middle in the glass colour.
func _draw_gear(c: CanvasItem, at: Vector2, col: Color, hole: Color) -> void:
	for i in 8:
		var t := TAU * i / 8.0
		var d := Vector2(cos(t), sin(t))
		var s := Vector2(-d.y, d.x)
		c.draw_colored_polygon(PackedVector2Array([at + d * 9.0 - s * 3.6, at + d * 15.0 - s * 2.6,
			at + d * 15.0 + s * 2.6, at + d * 9.0 + s * 3.6]), col)
	c.draw_circle(at, 11.0, col)
	c.draw_circle(at, 4.6, hole)


# Over the creature's head until the scarf is earned: what it takes.
func _draw_scarf_teaser(c: CanvasItem, font: Font, a: float) -> void:
	if Progress.scarf_unlocked or _creature == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.unproject_position(_creature.global_position + Vector3(0.0, 2.75, 0.0))   # just over its head
	var label := "REACH %s TO UNLOCK THE SCARF" % Hud.metres(Scarf.UNLOCK_M).replace(" 000 m", " KM")
	var w: float = Hud.bold().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 40.0
	var pill := Rect2(at - Vector2(w * 0.5, 18.0), Vector2(w, 36.0))
	Hud.button(c, pill, label, "scarf", Hud.Btn.NORMAL, 13, 0.92 * a)


# Top right: who is playing. A tap goes to the same place SETTINGS does,
# because that is where the nickname and the account live. The dot is
# cyan when signed in.
func _draw_name_chip(c: CanvasItem, screen: Vector2, font: Font, a: float) -> void:
	var label := Profile.username
	var w: float = Hud.bold().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 76.0
	var chip := Rect2(Vector2(screen.x - MARGIN - w, 72.0), Vector2(w, TAP_MIN))
	_rects["name_chip"] = chip
	var cs := _press.state("name_chip")
	var tint: Color = WorldPalette.SAFE if Talo.logged_in() else Palette.TEXT
	Hud.capsule_button(c, chip, Hud.GLASS_TOP, Hud.GLASS_BOTTOM, 0.9 * a, 0.0, cs)
	var o := chip.position + Hud.sink(cs)
	c.draw_circle(o + Vector2(26.0, chip.size.y * 0.5), 4.5, Color(tint.r, tint.g, tint.b, 0.95 * a))
	c.draw_string(Hud.bold(), o + Vector2(42.0, chip.size.y * 0.5 + 6.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 1, 0.92 * a))


# ------------------------------------------------------------
# SETTINGS — sound, the nickname, and the door to the account panel.
# A Hud card with Hud buttons (2026-10-23: it matches the menu now): the
# chosen side of a switch is cyan, the other dark glass; ACCOUNT is the
# leaderboard's amber, DISABLED when this build has no Talo key.
# ------------------------------------------------------------
const SHEET := Vector2(540.0, 480.0)

func _draw_settings(c: CanvasItem, screen: Vector2, font: Font) -> void:
	var panel := Rect2(screen * 0.5 - SHEET * 0.5, SHEET)
	Hud.card(c, panel)
	var px := panel.position.x
	var py := panel.position.y
	var pw := panel.size.x
	Hud.title(c, Hud.bold(), "SETTINGS", panel.get_center().x, py + 52.0, 24, 4.0, Color.WHITE)

	var close := Rect2(Vector2(px + pw - 22.0 - TAP_MIN, py + 18.0), Vector2(TAP_MIN, TAP_MIN))
	_rects["close"] = close
	var cs := _press.state("close")
	Hud.capsule_button(c, close, Hud.GLASS_TOP, Hud.GLASS_BOTTOM, 1.0, 0.0, cs)
	var xc := close.get_center() + Hud.sink(cs)
	c.draw_line(xc + Vector2(-8, -8), xc + Vector2(8, 8), Color.WHITE, 3.0, true)
	c.draw_line(xc + Vector2(-8, 8), xc + Vector2(8, -8), Color.WHITE, 3.0, true)

	# Sound: the effects and the music, each on its own (Progress).
	for row in [["EFFECTS", "effects", Progress.effects_on, 92.0], ["MUSIC", "music", Progress.music_on, 170.0]]:
		var top: float = py + float(row[3])
		var on: bool = row[2]
		Hud.tracked(c, Hud.bold(), String(row[0]), Vector2(px + 40.0, top + 40.0), 16, 2.0, Color(1, 1, 1, 0.9))
		var on_rect := Rect2(Vector2(px + pw - 40.0 - 214.0, top), Vector2(104.0, TAP_MIN))
		var off_rect := Rect2(Vector2(px + pw - 40.0 - 104.0, top), Vector2(104.0, TAP_MIN))
		var key := String(row[1])
		_rects[key + "_on"] = on_rect
		_rects[key + "_off"] = off_rect
		Hud.button(c, on_rect, "ON", "go" if on else "glass", _press.state(key + "_on"), 16)
		Hud.button(c, off_rect, "OFF", "go" if not on else "glass", _press.state(key + "_off"), 16)

	# Nickname: the name in a glass field (tap it, or EDIT, to type one).
	Hud.tracked(c, Hud.bold(), "NAME", Vector2(px + 40.0, py + 272.0), 16, 2.0, Color(1, 1, 1, 0.9))
	var field := Rect2(Vector2(px + 40.0, py + 286.0), Vector2(236.0, TAP_MIN))
	_rects["name_field"] = field
	if not _editing_name:
		Hud.button(c, field, Profile.username, "glass", _press.state("name_field", not Profile.claimed), 18)
	if Profile.claimed:
		c.draw_string(font, Vector2(px + 292.0, py + 326.0), "your account name",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	else:
		var rnd := Rect2(Vector2(px + 288.0, py + 286.0), Vector2(116.0, TAP_MIN))
		var ed := Rect2(Vector2(px + 412.0, py + 286.0), Vector2(88.0, TAP_MIN))
		_rects["random"] = rnd
		_rects["edit"] = ed
		Hud.button(c, rnd, "RANDOM", "glass", _press.state("random"), 14)
		Hud.button(c, ed, "EDIT", "glass", _press.state("edit"), 14)

	# The account: the existing panel, nothing new.
	var acc := Rect2(Vector2(px + 40.0, py + 380.0), Vector2(pw - 80.0, 72.0))
	if Talo.configured():
		_rects["account"] = acc
		var as_ := _press.state("account")
		var label := "ACCOUNT" if Talo.logged_in() else "REGISTER  ·  LOG IN"
		var st := Hud.style("glass" if Talo.logged_in() else "goal")
		Hud.capsule_button(c, acc, st[0], st[1], 1.0, st[3], as_)
		var ink: Color = st[2]
		var mid := acc.get_center() + Hud.sink(as_)
		Hud.centre_text(c, Hud.bold(), label, mid + Vector2(0, -8), 18, ink)
		Hud.centre_text(c, font, "post your distance to the leaderboard", mid + Vector2(0, 15), 12, Color(ink, 0.75))
	else:
		Hud.button(c, acc, "ACCOUNTS ARE NOT SET UP IN THIS BUILD", "glass", Hud.Btn.DISABLED, 13)
