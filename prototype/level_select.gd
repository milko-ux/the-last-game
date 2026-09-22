extends Node2D
# ============================================================
# LEVEL SELECT — a DEV TOOL now, not a screen the player sees. The main
# menu (prototype/menu.tscn, Phase E section 7) is what the game opens
# into; this is reached from its DEV button while Progress.UNLOCK_ALL.
#
# What a tile does changed with Phase E: there are no levels any more,
# there are LAPS of one endless run, and a lap uses the curriculum band
# of the same number. So tapping "N" here starts an endless run AT LAP
# N-1 — the way to look at band N without playing up to it. ENDLESS RUN
# (top right) is the ordinary run from lap 0.
#
# Same frosted-glass language as the touch controls (ui/ui.gd), drawn
# here so ui.gd stays untouched.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const RUN_SCENE := "res://prototype/track_test.tscn"
const COLS := 6
const ROWS := 5

var _rects: Array = []      # [Rect2] per lap tile, filled in _draw
# The run scene builds its level in one blocking step (validation + the
# field). Say so BEFORE it starts, or the phone just looks dead: the
# tap shows LOADING, and the scene changes two frames later.
var _loading_level := 0        # > 0 a level, -1 the endless run
var _endless_rect := Rect2()
var _painted := 0
var _painted_at_tap := 0
var _loading_from := 0


func _ready() -> void:
	queue_redraw()
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)


# Counts PAINTED frames, and NOTHING else: this runs inside the render
# step (see frame_meter.first_frame_painted() for what that cost once).
func _on_frame_drawn() -> void:
	_painted += 1


# While the LOADING label is up, the scene changes (a blocking step: the
# scene file, then the level) only after the label has really been drawn
# and one more frame has gone by, so the browser has shown it — or after
# FrameMeter.LABEL_TIMEOUT_MS, if those frames never come.
func _tick_loading() -> void:
	var waited := Time.get_ticks_msec() - _loading_from
	if _painted - _painted_at_tap < 2 and waited < FrameMeter.LABEL_TIMEOUT_MS:
		return
	if _painted - _painted_at_tap < 2:
		push_warning("LOADING LEVEL: no painted frame after %d ms; carrying on" % waited)
		FrameMeter.first_frame_painted()
	FrameMeter.load_label_painted(_painted - _painted_at_tap < 2)
	set_process(false)
	get_tree().change_scene_to_file.call_deferred(RUN_SCENE)


# The tap is taken: the label goes up now, and the wait for it to be
# painted starts from this moment (with its ceiling).
func _begin_loading(which: int) -> void:
	_loading_level = which
	_painted_at_tap = _painted
	_loading_from = Time.get_ticks_msec()
	FrameMeter.load_begin()
	queue_redraw()


func _process(_delta: float) -> void:
	if _painted >= 1:
		FrameMeter.first_frame_painted()
	if _loading_level != 0:
		_tick_loading()
	queue_redraw()


func _input(event: InputEvent) -> void:
	var pos: Variant = null
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	if pos == null:
		return
	if _endless_rect.has_point(pos) and _loading_level == 0:
		Rules.ENDLESS = true
		Rules.START_LAP = 0
		_begin_loading(-1)
		return
	for i in _rects.size():
		if _rects[i].has_point(pos):
			_tap(i + 1)
			return


# Tapping N starts the endless run at lap N-1, which is the lap that
# uses band N. Nothing here plays an old stand-alone level any more:
# ?level=N (track_test.gd's dev URL switches) is the one path left to
# those, and it is the fixed spot for frame-time readings.
func _tap(level: int) -> void:
	if _loading_level != 0:
		return
	Rules.ENDLESS = true
	Rules.START_LAP = level - 1
	_begin_loading(level)


func _draw() -> void:
	var screen := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	_rects = []

	_centre(font, "THE LAST GAME", Vector2(screen.x * 0.5, 44), 26, Palette.GOAL)
	_centre(font, "DEV  ·  start the run at any lap", Vector2(screen.x * 0.5, 72), 13,
		Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.8))

	var margin := 26.0
	var top := 96.0
	var gap := 10.0
	var w: float = (screen.x - margin * 2.0 - gap * (COLS - 1)) / COLS
	var h: float = minf(64.0, (screen.y - top - 24.0 - gap * (ROWS - 1)) / ROWS)
	for i in Rules.level_count():
		var level := i + 1
		var c := i % COLS
		var r := i / COLS
		var rect := Rect2(Vector2(margin + c * (w + gap), top + r * (h + gap)), Vector2(w, h))
		_rects.append(rect)
		_glass_pill(rect, Palette.EDGE, 1.0)
		var col := Color(1, 1, 1, 0.92)
		_centre(font, "%d" % level, rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5 - 6), 22, col)
		var sub := "lap %d" % (level - 1)
		_centre(font, sub, rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.5 + 16), 11,
			Color(col.r, col.g, col.b, col.a * 0.75))

	# The game itself: the endless run (this screen is the dev tool now).
	_endless_rect = Rect2(Vector2(screen.x - 190.0, 22.0), Vector2(164.0, 44.0))
	_glass_pill(_endless_rect, Palette.GOAL, 1.0)
	_centre(font, "ENDLESS RUN", _endless_rect.position + _endless_rect.size * 0.5, 15, Color(1, 1, 1, 0.92))

	if _loading_level != 0:
		draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.82), true)
		_centre(font, ("LOADING LAP %d" % (_loading_level - 1)) if _loading_level > 0 else "LOADING THE RUN", screen * 0.5, 24, Palette.GOAL)
		_centre(font, "building the course  ·  this can take a while the first time", screen * 0.5 + Vector2(0, 30), 12,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.8))


func _glass_pill(rect: Rect2, tint: Color, strength: float) -> void:
	draw_rect(Rect2(rect.position - Vector2(3, 3), rect.size + Vector2(6, 6)), Color(tint.r, tint.g, tint.b, 0.05 * strength), true)
	draw_rect(rect, Color(1, 1, 1, 0.05 * strength), true)
	draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.05 * strength), true)
	draw_rect(rect, Color(1, 1, 1, 0.22 * strength), false, 1.5)
	draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.30 * strength), false, 1.0)
	draw_line(rect.position + Vector2(6, 1), rect.position + Vector2(rect.size.x - 6, 1), Color(1, 1, 1, 0.42 * strength), 1.5)


func _centre(font, text: String, c: Vector2, size: int, col: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, c - Vector2(w * 0.5, -size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
