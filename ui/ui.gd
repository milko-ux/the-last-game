extends Node2D
# ============================================================
# UI — the HUD, the frosted-glass touch controls, the results
# screen and the portrait "rotate your phone" prompt.
#
# This sits on a CanvasLayer so it always draws ON TOP of the
# board and the entities, no matter what order they move in.
#
# IMPORTANT: the glass control drawing below is carried over
# unchanged from the version Milko confirmed feels good on a real
# phone. Treat any change to it as a change to a non-negotiable.
# ============================================================

signal jump_pressed
signal restart_requested
signal copy_requested
signal difficulty_chosen(d: int)
signal menu_requested
signal account_requested
signal leaderboard_requested

# --- Touch control sizing (tune these for thumb comfort) ---
const STICK_RADIUS := 76.0
const STICK_KNOB := 32.0
const STICK_DEADZONE := 10.0
const JUMP_BTN_RADIUS := 62.0
const CTRL_MARGIN := Vector2(125.0, 118.0)

# The Phase R prototype reuses this layer for its touch controls only
# and draws its own HUD; it turns the text HUD off here. Default on.
var show_hud := true

# One extra line under the rotate prompt, set by whoever is loading.
# The Phase R run's own LOADING label sits 70 px from the TOP edge, and
# in portrait the eye is on the centred rotate prompt instead -- Milko
# held the phone through a 6.5 s load on 2026-09-21 and never saw it.
# Empty = nothing extra is drawn. This is only ever read inside the
# portrait branch of _draw(), which returns BEFORE the HUD and the glass
# controls, so it cannot reach either of them.
var portrait_note := ""

# --- Status shown in the HUD, pushed in by main.gd ---
var level_index := 0
var level_count := 1
var lives := 3
var deaths := 0
var player_dead := false

# --- Difficulty select (the first thing you see; guest-first, no login) ---
var showing_menu := true
var _tier_rects: Array = []
var _lb_rect := Rect2()
var _account_rect := Rect2()

# Overlay panels (account, leaderboard), assigned by main. While any
# of them is visible this screen ignores input entirely, so a tap on
# a panel never falls through to the menu or results underneath.
var overlays: Array = []

# Name row on the menu. The player already HAS a name by the time they
# get here (Profile hands one out on first launch), so this is about
# changing it, never about filling in a blank.
var _name_rect := Rect2()
var _reroll_rect := Rect2()
var _edit_rect := Rect2()
var _editing_name := false
@onready var _name_edit: LineEdit = get_parent().get_node("NameEdit")

# --- Results screen ---
var showing_results := false
var menu_button_rect := Rect2()
var result_won := false
var level_reached := 0
# >= 0 means a checkpoint is armed and continuing resumes there.
var resume_level := -1
var copy_flash_timer := 0.0
var copy_button_rect := Rect2()
var lb_action_rect := Rect2()
# Status line for the leaderboard submission ("SENDING..." / "GLOBAL #4"),
# pushed in by main once the network answers.
var submit_text := ""

# --- Multi-touch state (move and jump at the same time) ---
var stick_touch_id := -1
var stick_origin := Vector2.ZERO
var stick_current := Vector2.ZERO
var jump_touch_id := -1
var jump_flash := 0.0
var stick_fade := 0.0


func _ready() -> void:
	_style_name_edit()
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(_finish_name_edit)


# Matches the frosted-glass language without touching the touch controls
# themselves, which are a non-negotiable.
func _style_name_edit() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.06)
	box.border_color = Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.7)
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	_name_edit.add_theme_stylebox_override("normal", box)
	_name_edit.add_theme_stylebox_override("focus", box)
	_name_edit.add_theme_color_override("font_color", Palette.EDGE)
	_name_edit.add_theme_color_override("caret_color", Palette.EDGE)
	_name_edit.add_theme_font_size_override("font_size", 20)


func _begin_name_edit() -> void:
	_editing_name = true
	_name_edit.text = Profile.username
	_name_edit.visible = true
	_name_edit.position = _name_rect.position
	_name_edit.size = _name_rect.size
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_name_submitted(text: String) -> void:
	# A rejected name (blank, too short, symbols only) just leaves the
	# old one in place rather than wiping it.
	Profile.set_username(text)
	_finish_name_edit()


func _finish_name_edit() -> void:
	if not _editing_name:
		return
	_editing_name = false
	_name_edit.visible = false
	_name_edit.release_focus()


func _process(delta: float) -> void:
	# The name field only ever exists on the menu.
	if _editing_name and not showing_menu:
		_finish_name_edit()

	if copy_flash_timer > 0.0:
		copy_flash_timer -= delta
	if jump_flash > 0.0:
		jump_flash -= delta * 4.0

	# Smooth fade when the stick is grabbed / released.
	var target: float = 1.0 if stick_touch_id != -1 else 0.0
	stick_fade = lerp(stick_fade, target, clamp(delta * 12.0, 0.0, 1.0))

	queue_redraw()


# The direction the player wants to move, in WORLD space.
func move_dir() -> Vector2:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if stick_touch_id != -1:
		var drag := stick_current - stick_origin
		if drag.length() > STICK_DEADZONE:
			dir = Iso.screen_dir_to_world(drag.normalized())
	return dir


func set_status(idx: int, count: int, l: int, d: int, is_dead: bool) -> void:
	level_index = idx
	level_count = count
	lives = l
	deaths = d
	player_dead = is_dead


func enter_results(won: bool, reached: int, count: int, d: int, resume: int = -1) -> void:
	showing_results = true
	result_won = won
	level_reached = reached
	level_count = count
	deaths = d
	resume_level = resume
	submit_text = ""
	# Drop any held touches so the next tap is read cleanly.
	stick_touch_id = -1
	jump_touch_id = -1


func leave_results() -> void:
	showing_results = false


func enter_menu() -> void:
	showing_menu = true
	showing_results = false
	stick_touch_id = -1
	jump_touch_id = -1


func leave_menu() -> void:
	showing_menu = false


func flash_copied() -> void:
	copy_flash_timer = 1.4


func set_submit_text(t: String) -> void:
	submit_text = t


func portrait() -> bool:
	var screen := get_viewport_rect().size
	return screen.y > screen.x


# ============================================================
# INPUT
# ============================================================
func _input(event: InputEvent) -> void:
	for o in overlays:
		if o != null and o.visible:
			return

	var screen := get_viewport_rect().size

	if event is InputEventScreenTouch:
		if event.pressed:
			if showing_menu:
				_tap_menu(event.position)
				return
			if showing_results:
				_tap_results(event.position)
				return
			if event.position.x < screen.x * 0.5:
				if stick_touch_id == -1:
					stick_touch_id = event.index
					stick_origin = event.position
					stick_current = event.position
			else:
				if jump_touch_id == -1:
					jump_touch_id = event.index
					_fire_jump()
		else:
			if event.index == stick_touch_id:
				stick_touch_id = -1
			if event.index == jump_touch_id:
				jump_touch_id = -1

	elif event is InputEventScreenDrag:
		if event.index == stick_touch_id:
			stick_current = event.position

	# Mouse fallback so the game is testable in a desktop browser.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if showing_menu:
				_tap_menu(event.position)
				return
			if showing_results:
				_tap_results(event.position)
				return
			if event.position.x < screen.x * 0.5:
				stick_touch_id = -100
				stick_origin = event.position
				stick_current = event.position
			else:
				_fire_jump()
		else:
			if stick_touch_id == -100:
				stick_touch_id = -1
	elif event is InputEventMouseMotion and stick_touch_id == -100:
		stick_current = event.position


func _tap_results(pos: Vector2) -> void:
	if copy_button_rect.has_point(pos):
		copy_requested.emit()
	elif lb_action_rect.size != Vector2.ZERO and lb_action_rect.has_point(pos):
		if Talo.logged_in():
			leaderboard_requested.emit()
		else:
			account_requested.emit()
	elif menu_button_rect.has_point(pos):
		menu_requested.emit()
	else:
		restart_requested.emit()


func _tap_menu(pos: Vector2) -> void:
	if _lb_rect.size != Vector2.ZERO and _lb_rect.has_point(pos):
		leaderboard_requested.emit()
		return
	if Profile.claimed:
		# The name is a real account now — the name and the ACCOUNT
		# button both open account management.
		if _account_rect.has_point(pos) or _name_rect.has_point(pos):
			account_requested.emit()
			return
	else:
		if _reroll_rect.has_point(pos):
			Profile.reroll()
			return
		if _edit_rect.has_point(pos) or _name_rect.has_point(pos):
			_begin_name_edit()
			return
	if _editing_name:
		_finish_name_edit()
		return

	var tiers := [Progress.Diff.STANDARD, Progress.Diff.HARD, Progress.Diff.EXTREME]
	for i in range(_tier_rects.size()):
		if _tier_rects[i].has_point(pos) and Progress.is_unlocked(tiers[i]):
			difficulty_chosen.emit(tiers[i])
			return


func _fire_jump() -> void:
	jump_pressed.emit()


# Flashes the JUMP button. Called by main only when the jump really happened,
# so the button doesn't light up on a jump that was ignored mid-air.
func confirm_jump() -> void:
	jump_flash = 1.0


# ============================================================
# GLASS UI HELPER
# Fakes frosted glass with layered translucent fills, a bright
# top rim highlight, and a soft outer bloom.
# ============================================================
func draw_glass_disc(c: Vector2, r: float, tint: Color, strength: float) -> void:
	# soft outer bloom
	draw_circle(c, r * 1.18, Color(tint.r, tint.g, tint.b, 0.05 * strength))
	draw_circle(c, r * 1.08, Color(tint.r, tint.g, tint.b, 0.05 * strength))

	# frosted body: layered so the centre reads slightly denser
	draw_circle(c, r, Color(1, 1, 1, 0.045 * strength))
	draw_circle(c, r * 0.94, Color(tint.r, tint.g, tint.b, 0.05 * strength))
	draw_circle(c, r * 0.55, Color(1, 1, 1, 0.03 * strength))

	# outer rim
	draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.22 * strength), 1.5)
	draw_arc(c, r, 0.0, TAU, 64, Color(tint.r, tint.g, tint.b, 0.35 * strength), 2.5)

	# top-edge specular highlight (the thing that sells "glass")
	draw_arc(c, r * 0.99, -PI * 0.92, -PI * 0.08, 32, Color(1, 1, 1, 0.42 * strength), 2.0)
	draw_arc(c, r * 0.80, -PI * 0.80, -PI * 0.32, 24, Color(1, 1, 1, 0.14 * strength), 5.0)


func centre_text(font, text: String, c: Vector2, size: int, col: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, c - Vector2(w * 0.5, -size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# ============================================================
# DRAWING
# ============================================================
func _draw() -> void:
	var screen := get_viewport_rect().size
	var font := ThemeDB.fallback_font

	if portrait():
		centre_text(font, "ROTATE YOUR PHONE",
			Vector2(screen.x * 0.5, screen.y * 0.5 - 24), 26, Palette.EDGE)
		centre_text(font, "This one is played sideways",
			Vector2(screen.x * 0.5, screen.y * 0.5 + 18), 16, Palette.TEXT)
		if portrait_note != "":
			centre_text(font, portrait_note,
				Vector2(screen.x * 0.5, screen.y * 0.5 + 62), 16, Palette.GOAL)
		return

	if showing_menu:
		_draw_menu(screen, font)
		return

	if showing_results:
		_draw_results(screen, font)
		return

	if show_hud:
		_draw_hud(screen, font)
	_draw_touch_controls(screen, font)


func _draw_touch_controls(screen: Vector2, font) -> void:
	# ---------- JUMP BUTTON ----------
	var jb := Vector2(screen.x - CTRL_MARGIN.x, screen.y - CTRL_MARGIN.y)
	var pressed: float = clamp(jump_flash, 0.0, 1.0)
	var r := JUMP_BTN_RADIUS * (1.0 + pressed * 0.06)

	draw_glass_disc(jb, r, Palette.EDGE, 1.0 + pressed * 0.9)

	if pressed > 0.0:
		draw_arc(jb, r * (1.0 + (1.0 - pressed) * 0.35), 0.0, TAU, 48,
			Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.35 * pressed), 2.0)

	centre_text(font, "JUMP", jb, 18, Color(1, 1, 1, 0.75 + pressed * 0.25))

	# ---------- MOVEMENT STICK ----------
	var resting := Vector2(CTRL_MARGIN.x, screen.y - CTRL_MARGIN.y)
	var base := resting
	var knob := resting
	var active := stick_touch_id != -1

	if active:
		base = stick_origin
		var d := stick_current - stick_origin
		if d.length() > STICK_RADIUS - STICK_KNOB:
			d = d.normalized() * (STICK_RADIUS - STICK_KNOB)
		knob = base + d

	var strength := 0.85 + stick_fade * 0.75

	draw_glass_disc(base, STICK_RADIUS, Palette.PLAYER, strength)

	# faint direction crosshair inside the ring
	if not active:
		var cross := Color(1, 1, 1, 0.10)
		draw_line(base + Vector2(-16, 0), base + Vector2(16, 0), cross, 1.0)
		draw_line(base + Vector2(0, -16), base + Vector2(0, 16), cross, 1.0)

	# knob
	draw_circle(knob, STICK_KNOB * 1.15, Color(Palette.PLAYER.r, Palette.PLAYER.g, Palette.PLAYER.b, 0.08 * strength))
	draw_circle(knob, STICK_KNOB, Color(1, 1, 1, 0.10 * strength))
	draw_circle(knob, STICK_KNOB * 0.92, Color(Palette.PLAYER.r, Palette.PLAYER.g, Palette.PLAYER.b, 0.14 * strength))
	draw_arc(knob, STICK_KNOB, 0.0, TAU, 40, Color(1, 1, 1, 0.45 * strength), 1.8)
	draw_arc(knob, STICK_KNOB * 0.96, -PI * 0.88, -PI * 0.12, 24, Color(1, 1, 1, 0.5 * strength), 2.0)
	# tiny specular dot
	draw_circle(knob + Vector2(-STICK_KNOB * 0.34, -STICK_KNOB * 0.36),
		STICK_KNOB * 0.16, Color(1, 1, 1, 0.35 * strength))

	if not active:
		centre_text(font, "MOVE", resting + Vector2(0, STICK_RADIUS + 26), 13,
			Color(1, 1, 1, 0.35))


# Locked tiers are shown, not hidden — seeing what you haven't earned yet
# is the point. They're dimmed and crossed through.
func _draw_menu(screen: Vector2, font) -> void:
	var cx := screen.x * 0.5
	centre_text(font, "THE LAST GAME", Vector2(cx, screen.y * 0.20), 38, Palette.glow(Palette.EDGE, 2.0))
	centre_text(font, "Choose your difficulty", Vector2(cx, screen.y * 0.20 + 38), 14,
		Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.8))

	var tiers := [Progress.Diff.STANDARD, Progress.Diff.HARD, Progress.Diff.EXTREME]
	var accents := [Palette.EDGE, Palette.GOAL, Palette.HAZ]
	var cw := minf(240.0, (screen.x - 100.0) / 3.0 - 20.0)
	var ch := 118.0
	var gap := 20.0
	var x := cx - (cw * 3.0 + gap * 2.0) * 0.5
	var y := screen.y * 0.40
	_tier_rects = []

	for i in range(tiers.size()):
		var d: int = tiers[i]
		var rect := Rect2(Vector2(x, y), Vector2(cw, ch))
		_tier_rects.append(rect)

		var open: bool = Progress.is_unlocked(d)
		var accent: Color = accents[i]
		var a: float = 1.0 if open else 0.3

		draw_rect(rect, Color(1, 1, 1, 0.05 if open else 0.02), true)
		draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.6 * a), false, 2.0)
		if open:
			draw_line(rect.position + Vector2(4, 2), rect.position + Vector2(cw - 4, 2),
				Color(1, 1, 1, 0.25), 1.5)

		centre_text(font, Progress.tier_name(d), rect.position + Vector2(cw * 0.5, 44), 22,
			Color(accent.r, accent.g, accent.b, a))
		centre_text(font, String(Progress.rules(d)["blurb"]),
			rect.position + Vector2(cw * 0.5, 76), 11,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, a))

		if not open:
			draw_line(rect.position, rect.position + rect.size, Color(1, 1, 1, 0.16), 2.0)
			draw_line(rect.position + Vector2(0, ch), rect.position + Vector2(cw, 0),
				Color(1, 1, 1, 0.16), 2.0)
		x += cw + gap

	if not Progress.standard_cleared:
		centre_text(font, "Finish all %d levels on STANDARD to unlock the difficulties" % level_count,
			Vector2(cx, y + ch + 42), 14, Color(1, 1, 1, 0.45))

	_draw_name_row(cx, y + ch + 84, font)

	# Anyone may LOOK at the leaderboard — reading is anonymous, only
	# submitting needs an account. Hidden entirely until Talo is set up.
	_lb_rect = Rect2()
	if Talo.configured():
		_lb_rect = Rect2(Vector2(cx - 110.0, y + ch + 162.0), Vector2(220.0, 30.0))
		draw_rect(_lb_rect, Color(1, 1, 1, 0.03), true)
		draw_rect(_lb_rect, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.4), false, 1.0)
		centre_text(font, "LEADERBOARD", _lb_rect.get_center() + Vector2(0, -5), 13, Palette.EDGE)


# "Playing as <name>" with reroll and edit. No account, no login — the
# name already exists, so this is a nicety, not a gate.
func _draw_name_row(cx: float, row_y: float, font) -> void:
	centre_text(font, "PLAYING AS", Vector2(cx, row_y - 22), 11,
		Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.55))

	var nw: float = maxf(190.0,
		font.get_string_size(Profile.username, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 40.0)
	_name_rect = Rect2(Vector2(cx - nw * 0.5, row_y - 2), Vector2(nw, 34))

	# While the LineEdit is up it draws itself, so skip the painted version.
	if not _editing_name:
		draw_rect(_name_rect, Color(1, 1, 1, 0.04), true)
		draw_rect(_name_rect, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.35), false, 1.0)
		centre_text(font, Profile.username,
			_name_rect.position + Vector2(nw * 0.5, 17), 20, Palette.EDGE)

	var bw := 92.0
	var by := row_y + 40.0
	_reroll_rect = Rect2()
	_edit_rect = Rect2()
	_account_rect = Rect2()

	if Profile.claimed:
		# Signed in: the name IS the account, so no reroll/edit.
		_account_rect = Rect2(Vector2(cx - bw * 0.5 - 8.0, by), Vector2(bw + 16.0, 28))
		draw_rect(_account_rect, Color(1, 1, 1, 0.03), true)
		draw_rect(_account_rect, Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.30), false, 1.0)
		centre_text(font, "ACCOUNT", _account_rect.position + Vector2(bw * 0.5 + 8.0, 14), 12,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.85))
		return

	_reroll_rect = Rect2(Vector2(cx - bw - 6.0, by), Vector2(bw, 28))
	_edit_rect   = Rect2(Vector2(cx + 6.0, by), Vector2(bw, 28))

	for pair in [[_reroll_rect, "RANDOM"], [_edit_rect, "EDIT"]]:
		var r: Rect2 = pair[0]
		draw_rect(r, Color(1, 1, 1, 0.03), true)
		draw_rect(r, Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.30), false, 1.0)
		centre_text(font, String(pair[1]), r.position + Vector2(bw * 0.5, 14), 12,
			Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.85))


func _draw_results(screen: Vector2, font) -> void:
	var accent := Palette.GOAL if result_won else Palette.HAZ
	var title := "YOU CLEARED THE LOOP" if result_won else "THE LOOP RESET"
	var cx := screen.x * 0.5

	centre_text(font, title, Vector2(cx, screen.y * 0.5 - 130), 34, accent)
	centre_text(font, Profile.username, Vector2(cx, screen.y * 0.5 - 100), 15,
		Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.75))
	centre_text(font, "Level reached: %d / %d" % [level_reached + 1, level_count],
		Vector2(cx, screen.y * 0.5 - 74), 20, Palette.TEXT)
	centre_text(font, "Deaths: %d" % deaths,
		Vector2(cx, screen.y * 0.5 - 44), 20, Palette.TEXT)

	if not submit_text.is_empty():
		centre_text(font, submit_text, Vector2(cx, screen.y * 0.5 - 16), 13,
			Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.9))

	var bw := 320.0
	var bh := 52.0
	var bx := cx - bw * 0.5
	var by := screen.y * 0.5 + 2.0
	copy_button_rect = Rect2(Vector2(bx, by), Vector2(bw, bh))

	draw_rect(copy_button_rect, Color(1, 1, 1, 0.05), true)
	draw_rect(copy_button_rect, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.55), false, 2.0)
	draw_line(Vector2(bx + 4, by + 2), Vector2(bx + bw - 4, by + 2), Color(1, 1, 1, 0.25), 1.5)

	var label := "COPIED!" if copy_flash_timer > 0.0 else "TAP TO COPY BRAG"
	centre_text(font, label, Vector2(cx, by + bh * 0.5), 18, Palette.EDGE)

	# One leaderboard action: guests get the sign-up pitch, account
	# holders go straight to the rankings.
	lb_action_rect = Rect2()
	if Talo.configured():
		lb_action_rect = Rect2(Vector2(cx - bw * 0.5, by + 64.0), Vector2(bw, 34.0))
		var lb_label := "VIEW LEADERBOARD" if Talo.logged_in() else "JOIN THE LEADERBOARD"
		draw_rect(lb_action_rect, Color(1, 1, 1, 0.04), true)
		draw_rect(lb_action_rect, Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.55), false, 1.5)
		centre_text(font, lb_label, lb_action_rect.get_center() + Vector2(0, -5), 14, Palette.GOAL)

	var again := "Tap anywhere else to try again"
	if not result_won and resume_level >= 0:
		again = "Tap anywhere else to continue from level %d" % (resume_level + 1)
	centre_text(font, again, Vector2(cx, by + 122), 14, Color(1, 1, 1, 0.4))

	menu_button_rect = Rect2(Vector2(cx - 110.0, by + 138.0), Vector2(220.0, 34.0))
	draw_rect(menu_button_rect, Color(1, 1, 1, 0.03), true)
	draw_rect(menu_button_rect, Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.35), false, 1.0)
	centre_text(font, "CHANGE DIFFICULTY",
		menu_button_rect.position + Vector2(110.0, 17.0), 13,
		Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.85))


func _draw_hud(screen: Vector2, font) -> void:
	draw_string(font, Vector2(18, 32), "LEVEL %d / %d" % [level_index + 1, level_count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.EDGE)
	draw_string(font, Vector2(18, 54), Progress.tier_name(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.7))
	draw_string(font, Vector2(screen.x - 230, 32), "LIVES %d" % lives,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.HAZ)
	draw_string(font, Vector2(screen.x - 125, 32), "DEATHS %d" % deaths,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.TEXT)

	if player_dead:
		centre_text(font, "DIED", Vector2(screen.x * 0.5, screen.y * 0.5), 30, Palette.HAZ)
