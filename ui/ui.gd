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

# --- Touch control sizing (tune these for thumb comfort) ---
const STICK_RADIUS := 76.0
const STICK_KNOB := 32.0
const STICK_DEADZONE := 10.0
const JUMP_BTN_RADIUS := 62.0
const CTRL_MARGIN := Vector2(125.0, 118.0)

# --- Status shown in the HUD, pushed in by main.gd ---
var level_index := 0
var level_count := 1
var lives := 3
var deaths := 0
var player_dead := false

# --- Results screen ---
var showing_results := false
var result_won := false
var level_reached := 0
var copy_flash_timer := 0.0
var copy_button_rect := Rect2()

# --- Multi-touch state (move and jump at the same time) ---
var stick_touch_id := -1
var stick_origin := Vector2.ZERO
var stick_current := Vector2.ZERO
var jump_touch_id := -1
var jump_flash := 0.0
var stick_fade := 0.0


func _process(delta: float) -> void:
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


func enter_results(won: bool, reached: int, count: int, d: int) -> void:
	showing_results = true
	result_won = won
	level_reached = reached
	level_count = count
	deaths = d
	# Drop any held touches so the next tap is read cleanly.
	stick_touch_id = -1
	jump_touch_id = -1


func leave_results() -> void:
	showing_results = false


func flash_copied() -> void:
	copy_flash_timer = 1.4


func portrait() -> bool:
	var screen := get_viewport_rect().size
	return screen.y > screen.x


# ============================================================
# INPUT
# ============================================================
func _input(event: InputEvent) -> void:
	var screen := get_viewport_rect().size

	if event is InputEventScreenTouch:
		if event.pressed:
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
	else:
		restart_requested.emit()


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
		return

	if showing_results:
		_draw_results(screen, font)
		return

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


func _draw_results(screen: Vector2, font) -> void:
	var accent := Palette.GOAL if result_won else Palette.HAZ
	var title := "YOU CLEARED THE LOOP" if result_won else "THE LOOP RESET"
	var cx := screen.x * 0.5

	centre_text(font, title, Vector2(cx, screen.y * 0.5 - 130), 34, accent)
	centre_text(font, "Level reached: %d / %d" % [level_reached + 1, level_count],
		Vector2(cx, screen.y * 0.5 - 80), 20, Palette.TEXT)
	centre_text(font, "Deaths: %d" % deaths,
		Vector2(cx, screen.y * 0.5 - 48), 20, Palette.TEXT)

	var bw := 320.0
	var bh := 60.0
	var bx := cx - bw * 0.5
	var by := screen.y * 0.5
	copy_button_rect = Rect2(Vector2(bx, by), Vector2(bw, bh))

	draw_rect(copy_button_rect, Color(1, 1, 1, 0.05), true)
	draw_rect(copy_button_rect, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.55), false, 2.0)
	draw_line(Vector2(bx + 4, by + 2), Vector2(bx + bw - 4, by + 2), Color(1, 1, 1, 0.25), 1.5)

	var label := "COPIED!" if copy_flash_timer > 0.0 else "TAP TO COPY BRAG"
	centre_text(font, label, Vector2(cx, by + bh * 0.5), 18, Palette.EDGE)

	centre_text(font, "Tap anywhere else to try again",
		Vector2(cx, by + 105), 14, Color(1, 1, 1, 0.4))


func _draw_hud(screen: Vector2, font) -> void:
	draw_string(font, Vector2(18, 32), "LEVEL %d / %d" % [level_index + 1, level_count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.EDGE)
	draw_string(font, Vector2(screen.x - 230, 32), "LIVES %d" % lives,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.HAZ)
	draw_string(font, Vector2(screen.x - 125, 32), "DEATHS %d" % deaths,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.TEXT)

	if player_dead:
		centre_text(font, "DIED", Vector2(screen.x * 0.5, screen.y * 0.5), 30, Palette.HAZ)
