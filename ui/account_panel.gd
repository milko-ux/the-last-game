extends Node2D
# ============================================================
# ACCOUNT PANEL — the overlay for everything account-shaped:
#
#   1. CONSENT   the GDPR screen. Always first, and nothing talks to
#                the network until it's been agreed to. Declining just
#                closes the panel — guests keep playing untouched.
#   2. FORM      create account / log in. Username is prefilled from
#                the guest name (guest-first: never an empty field).
#                Email is optional and says so. Country is shown and
#                can be edited or hidden before anything is sent.
#   3. SIGNED_IN manage the account: country, sign out, delete.
#   4. DELETE    the GDPR "remove my data" path — asks for the
#                password, then deletes the account and its entries.
#
# Sits on the UI CanvasLayer above the menu/results screens. ui.gd
# ignores input while any overlay is visible, so taps never leak
# through to the screen underneath.
#
# VISUAL PASS (2026-09-02): restyled after a Google Stitch mockup —
# sharp-cornered glass panel with a glowing top edge and corner
# brackets, darker recessed fields that light up on focus, underline
# tabs instead of boxed ones. The UI CanvasLayer never blooms (see
# ui.gd / main.tscn), so "glow" here is faked by layering translucent
# outlines (_glow_rect / _glow_line) the same way ui.gd's
# draw_glass_disc() fakes it for the touch controls — never
# Palette.glow(), which only matters on the world layer.
# All tap-target rects and layout offsets are unchanged from before
# this pass; only how they're painted (plus the new password
# show/hide toggle) changed.
# ============================================================

signal closed

enum Mode { CONSENT, FORM, SIGNED_IN, DELETE }

const PANEL_W := 560.0

var mode: int = Mode.CONSENT
var form_login := false   # false = create account, true = log in
var busy := false
var error_text := ""
var _pass_visible := false

# Tap targets, recorded while drawing (same pattern as ui.gd).
var _rects := {}          # name -> Rect2

var _name_edit: LineEdit
var _pass_edit: LineEdit
var _email_edit: LineEdit
var _country_edit: LineEdit
var _editing_country := false


func _ready() -> void:
	_name_edit = _make_edit(16)
	_pass_edit = _make_edit(64)
	_pass_edit.secret = true
	_email_edit = _make_edit(128)
	_country_edit = _make_edit(2)
	_country_edit.text_submitted.connect(func(_t): _finish_country_edit())
	_country_edit.focus_exited.connect(_finish_country_edit)


# Dark, sharp-cornered "recessed glass" field: dim border at rest,
# a bright border plus a real StyleBoxFlat drop-shadow on focus — a
# native Godot glow, no manual redraw needed while the control is
# focused.
func _make_edit(max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.max_length = max_len
	e.visible = false
	e.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0.4)
	normal.border_color = Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.3)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0

	var focus: StyleBoxFlat = normal.duplicate()
	focus.border_color = Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.9)
	focus.bg_color = Color(0, 0, 0, 0.5)
	focus.shadow_color = Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.28)
	focus.shadow_size = 6

	e.add_theme_stylebox_override("normal", normal)
	e.add_theme_stylebox_override("focus", focus)
	e.add_theme_color_override("font_color", Palette.TEXT)
	e.add_theme_color_override("caret_color", Palette.EDGE)
	e.add_theme_font_size_override("font_size", 16)
	add_child(e)
	return e


func open() -> void:
	error_text = ""
	busy = false
	_editing_country = false
	_pass_visible = false
	if Talo.logged_in():
		mode = Mode.SIGNED_IN
	elif Consent.needs_consent():
		mode = Mode.CONSENT
	else:
		mode = Mode.FORM
		form_login = false
	_name_edit.text = Profile.username
	_pass_edit.text = ""
	_email_edit.text = ""
	visible = true


func close() -> void:
	if busy:
		return
	visible = false
	_hide_edits()
	closed.emit()


func _hide_edits() -> void:
	for e in [_name_edit, _pass_edit, _email_edit, _country_edit]:
		e.visible = false
		e.release_focus()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# ============================================================
# INPUT
# ============================================================
func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		return

	# Touch is handled directly; mouse only when it's a REAL mouse.
	# On phones Godot synthesises mouse events from touches (device -1)
	# and reacting to both would double-fire every toggle.
	var pos := Vector2.ZERO
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
		tapped = true
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		pos = event.position
		tapped = true
	if not tapped or busy:
		return

	# A tap outside any field commits the in-progress country edit.
	if _editing_country and not _rects.get("country", Rect2()).has_point(pos):
		_finish_country_edit()

	for key in _rects:
		if _rects[key].has_point(pos):
			_tap(str(key))
			return


func _tap(what: String) -> void:
	match what:
		"close", "close2":
			close()
		"agree":
			Consent.grant()
			mode = Mode.FORM
			form_login = false
			error_text = ""
		"tab_register":
			form_login = false
			error_text = ""
		"tab_login":
			form_login = true
			error_text = ""
		"submit":
			_submit_form()
		"pass_toggle":
			_pass_visible = not _pass_visible
		"country":
			_begin_country_edit()
		"country_show":
			Consent.set_show_country(true)
		"country_hide":
			Consent.set_show_country(false)
		"signout":
			_do_logout()
		"delete":
			mode = Mode.DELETE
			_pass_edit.text = ""
			error_text = ""
		"delete_confirm":
			_do_delete()
		"delete_back":
			mode = Mode.SIGNED_IN
			error_text = ""


# ============================================================
# ACTIONS
# ============================================================
func _submit_form() -> void:
	var account_name := _name_edit.text.strip_edges()
	var password := _pass_edit.text
	if account_name.length() < 2:
		error_text = "Name needs at least 2 characters."
		return
	if password.length() < 6:
		error_text = "Password needs at least 6 characters."
		return

	error_text = ""
	busy = true
	var res: Dictionary
	if form_login:
		res = await Talo.login(account_name, password)
	else:
		res = await Talo.register_account(account_name, password, _email_edit.text.strip_edges())
	busy = false
	if res.ok:
		close()
	else:
		error_text = str(res.error)


func _do_logout() -> void:
	busy = true
	await Talo.logout()
	busy = false
	close()


func _do_delete() -> void:
	if _pass_edit.text.is_empty():
		error_text = "Enter your password to confirm."
		return
	error_text = ""
	busy = true
	var res: Dictionary = await Talo.delete_account(_pass_edit.text)
	busy = false
	if res.ok:
		close()
	else:
		error_text = str(res.error)


func _begin_country_edit() -> void:
	_editing_country = true
	_country_edit.text = Consent.country
	_country_edit.visible = true
	_country_edit.grab_focus()
	_country_edit.select_all()


func _finish_country_edit() -> void:
	if not _editing_country:
		return
	_editing_country = false
	if not Consent.set_country(_country_edit.text):
		error_text = "Country must be a 2-letter code, like SE."
	_country_edit.visible = false
	_country_edit.release_focus()


# ============================================================
# GLOW HELPERS
# Immediate-mode fakes for the "glowing border" look — layered
# translucent outlines growing outward with falling alpha, same
# technique as ui.gd's draw_glass_disc(). Shared by every panel mode.
# ============================================================
func _glow_rect(rect: Rect2, color: Color, strength: float = 1.0, width: float = 1.5) -> void:
	for i in range(3, 0, -1):
		var grown := rect.grow(float(i) * 2.0)
		draw_rect(grown, Color(color.r, color.g, color.b, 0.035 * strength / i), false, width)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.7 * strength), false, width)


func _glow_line(a: Vector2, b: Vector2, color: Color, strength: float = 1.0) -> void:
	draw_line(a, b, Color(color.r, color.g, color.b, 0.12 * strength), 7.0)
	draw_line(a, b, Color(color.r, color.g, color.b, 0.28 * strength), 3.0)
	draw_line(a, b, Color(1, 1, 1, 0.85 * strength), 1.5)


# A filled, glow-bordered button with centred text — the one button
# style every mode of this panel uses.
func _glow_button(rect: Rect2, accent: Color, label: String, font, strength: float = 1.0) -> void:
	draw_rect(rect, Color(0, 0, 0, 0.32), true)
	_glow_rect(rect, accent, strength, 1.5)
	_centre(font, label, rect.get_center(), 15, accent)


# ============================================================
# DRAWING
# ============================================================
func _draw() -> void:
	var screen := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	_rects = {}

	# Dim everything underneath so the panel owns the screen.
	draw_rect(Rect2(Vector2.ZERO, screen), Color(Palette.BG.r, Palette.BG.g, Palette.BG.b, 0.92), true)

	var w := minf(PANEL_W, screen.x - 60.0)
	var h := 470.0 if mode == Mode.CONSENT else 420.0
	var panel := Rect2(Vector2((screen.x - w) * 0.5, (screen.y - h) * 0.5), Vector2(w, h))

	# Card fill is the world's own rock-floor colour, near-opaque — the
	# panel reads as part of the same material as the game, not a
	# generic app sheet dropped on top of it.
	draw_rect(panel, Color(Palette.FLOOR.r, Palette.FLOOR.g, Palette.FLOOR.b, 0.94), true)
	_glow_rect(panel, Palette.EDGE, 0.9, 1.5)
	_glow_line(panel.position + Vector2(3, 1), panel.position + Vector2(w - 3, 1), Palette.EDGE, 1.0)
	_draw_corner_brackets(panel, Palette.EDGE)

	# Close "X", top-right — except mid-delete, where BACK is explicit.
	if mode != Mode.DELETE and not busy:
		var xr := Rect2(panel.position + Vector2(w - 40, 8), Vector2(32, 32))
		_rects["close"] = xr
		_centre(font, "X", xr.get_center(), 16, Color(1, 1, 1, 0.5))

	match mode:
		Mode.CONSENT:
			_draw_consent(panel, font)
		Mode.FORM:
			_draw_form(panel, font)
		Mode.SIGNED_IN:
			_draw_signed_in(panel, font)
		Mode.DELETE:
			_draw_delete(panel, font)

	if busy:
		_centre(font, "...", Vector2(panel.get_center().x, panel.end.y - 22), 18, Palette.EDGE)


# Small L-shaped accents at the bottom corners — a light structural
# detail borrowed from the Stitch reference, cheap and unobtrusive.
func _draw_corner_brackets(panel: Rect2, color: Color) -> void:
	var arm := 12.0
	var col := Color(color.r, color.g, color.b, 0.55)
	var bl := panel.position + Vector2(0, panel.size.y)
	draw_line(bl, bl + Vector2(arm, 0), col, 2.0)
	draw_line(bl, bl + Vector2(0, -arm), col, 2.0)
	var br := panel.end
	draw_line(br, br + Vector2(-arm, 0), col, 2.0)
	draw_line(br, br + Vector2(0, -arm), col, 2.0)


func _draw_consent(panel: Rect2, font) -> void:
	var cx := panel.get_center().x
	var y := panel.position.y + 40.0
	_centre(font, "BEFORE YOU JOIN THE LEADERBOARD", Vector2(cx, y), 20, Palette.EDGE)
	y += 34.0

	var lines := [
		"Creating an account stores this on our leaderboard",
		"service (Talo):",
		"",
		"- your player name and a scrambled (hashed) password",
		"- your scores, deaths and furthest level",
		"- your country code, only if you choose to show it",
		"- your email, only if you give one (used for password",
		"  recovery, nothing else)",
		"",
		"No tracking, no ads profiles, no selling data.",
		"",
		"You can delete your account in-game at any time -",
		"that erases everything above, scores included.",
		"",
		"Not into it? Keep playing as a guest -",
		"nothing ever leaves your phone.",
	]
	for line in lines:
		_centre(font, line, Vector2(cx, y), 13, Palette.TEXT)
		y += 18.0

	var bw := minf(320.0, panel.size.x - 60.0)
	var agree := Rect2(Vector2(cx - bw * 0.5, y + 8.0), Vector2(bw, 44.0))
	_rects["agree"] = agree
	_glow_button(agree, Palette.EDGE, "I AGREE - LET'S GO", font)

	var later := Rect2(Vector2(cx - 70.0, agree.end.y + 10.0), Vector2(140.0, 28.0))
	_rects["close2"] = later
	_centre(font, "NOT NOW", later.get_center(), 13, Color(1, 1, 1, 0.5))


func _draw_form(panel: Rect2, font) -> void:
	var cx := panel.get_center().x
	var x := panel.position.x + 40.0
	var fw := panel.size.x - 80.0
	var y := panel.position.y + 24.0

	# Underline tabs: label plus a glowing rule under the active one.
	# Same tap zones as before, just repainted without the boxed look.
	var tw := 150.0
	var tab_r := Rect2(Vector2(cx - tw - 8.0, y), Vector2(tw, 32.0))
	var tab_l := Rect2(Vector2(cx + 8.0, y), Vector2(tw, 32.0))
	_rects["tab_register"] = tab_r
	_rects["tab_login"] = tab_l
	for pair in [[tab_r, "CREATE ACCOUNT", not form_login], [tab_l, "LOG IN", form_login]]:
		var r: Rect2 = pair[0]
		var on: bool = pair[2]
		_centre(font, String(pair[1]), r.get_center() - Vector2(0, 4), 13,
			Palette.EDGE if on else Color(1, 1, 1, 0.4))
		if on:
			var uy := r.position.y + 24.0
			_glow_line(Vector2(r.position.x, uy), Vector2(r.end.x, uy), Palette.EDGE, 0.75)
	y += 52.0

	y = _field(font, "NAME", _name_edit, x, y, fw)
	y = _field(font, "PASSWORD", _pass_edit, x, y, fw)
	if form_login:
		_email_edit.visible = false
	else:
		y = _field(font, "EMAIL - OPTIONAL, ONLY FOR PASSWORD RECOVERY", _email_edit, x, y, fw)
		y = _draw_country_row(font, x, y, fw)

	if not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, y + 4.0), 13, Palette.HAZ)
	y += 18.0

	var bw := minf(320.0, fw)
	var submit := Rect2(Vector2(cx - bw * 0.5, y), Vector2(bw, 44.0))
	_rects["submit"] = submit
	_glow_button(submit, Palette.GOAL, "LOG IN" if form_login else "CREATE ACCOUNT", font)


# One labelled input row. Positions the LineEdit over the panel and
# returns the y below it. The password field grows a SHOW/HIDE toggle
# in its label row automatically.
func _field(font, label: String, edit: LineEdit, x: float, y: float, fw: float) -> float:
	draw_string(font, Vector2(x, y + 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.6))

	if edit == _pass_edit:
		edit.secret = not _pass_visible
		var tr := Rect2(Vector2(x + fw - 42.0, y - 1.0), Vector2(42.0, 14.0))
		_rects["pass_toggle"] = tr
		_centre(font, "SHOW" if not _pass_visible else "HIDE", tr.get_center(), 10,
			Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.65))

	edit.visible = true
	edit.position = Vector2(x, y + 16.0)
	edit.size = Vector2(fw, 34.0)
	return y + 58.0


func _draw_country_row(font, x: float, y: float, fw: float) -> float:
	draw_string(font, Vector2(x, y + 10.0), "COUNTRY ON THE LEADERBOARD",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.6))

	var code_r := Rect2(Vector2(x, y + 16.0), Vector2(64.0, 30.0))
	_rects["country"] = code_r
	if _editing_country:
		_country_edit.visible = true
		_country_edit.position = code_r.position
		_country_edit.size = code_r.size
	else:
		_country_edit.visible = false
		draw_rect(code_r, Color(0, 0, 0, 0.4), true)
		draw_rect(code_r, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.4), false, 1.0)
		var code := Consent.country if not Consent.country.is_empty() else "--"
		_centre(font, code, code_r.get_center(), 15, Palette.EDGE)

	var show_r := Rect2(Vector2(x + 76.0, y + 16.0), Vector2(86.0, 30.0))
	var hide_r := Rect2(Vector2(x + 168.0, y + 16.0), Vector2(86.0, 30.0))
	_rects["country_show"] = show_r
	_rects["country_hide"] = hide_r
	for pair in [[show_r, "SHOWN", Consent.show_country], [hide_r, "HIDDEN", not Consent.show_country]]:
		var r: Rect2 = pair[0]
		var on: bool = pair[2]
		draw_rect(r, Color(0, 0, 0, 0.35 if on else 0.2), true)
		draw_rect(r, Color(1, 1, 1, 0.4 if on else 0.14), false, 1.0)
		_centre(font, String(pair[1]), r.get_center(), 12,
			Color(1, 1, 1, 0.9 if on else 0.35))

	draw_string(font, Vector2(x + 266.0, y + 36.0), "tap the code to change it",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.3))
	return y + 60.0


func _draw_signed_in(panel: Rect2, font) -> void:
	_name_edit.visible = false
	_pass_edit.visible = false
	_email_edit.visible = false
	var cx := panel.get_center().x
	var x := panel.position.x + 40.0
	var fw := panel.size.x - 80.0
	var y := panel.position.y + 56.0

	_centre(font, "SIGNED IN AS", Vector2(cx, y), 12,
		Color(Palette.TEXT.r, Palette.TEXT.g, Palette.TEXT.b, 0.55))
	_centre(font, Talo.identifier, Vector2(cx, y + 30.0), 24, Palette.EDGE)
	y += 70.0

	y = _draw_country_row(font, x, y, fw)
	y += 14.0

	if not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, y), 13, Palette.HAZ)
	y += 16.0

	var bw := minf(320.0, fw)
	var out_r := Rect2(Vector2(cx - bw * 0.5, y), Vector2(bw, 40.0))
	_rects["signout"] = out_r
	_glow_button(out_r, Color(1, 1, 1, 0.85), "SIGN OUT", font, 0.6)

	var del_r := Rect2(Vector2(cx - bw * 0.5, y + 52.0), Vector2(bw, 40.0))
	_rects["delete"] = del_r
	_glow_button(del_r, Palette.HAZ, "DELETE ACCOUNT + MY DATA", font, 0.8)


func _draw_delete(panel: Rect2, font) -> void:
	var cx := panel.get_center().x
	var x := panel.position.x + 40.0
	var fw := panel.size.x - 80.0
	var y := panel.position.y + 50.0

	_centre(font, "DELETE THIS ACCOUNT?", Vector2(cx, y), 20, Palette.HAZ)
	y += 34.0
	for line in [
		"This permanently removes your account and your",
		"leaderboard entries. There is no undo.",
	]:
		_centre(font, line, Vector2(cx, y), 13, Palette.TEXT)
		y += 18.0
	y += 16.0

	_email_edit.visible = false
	_name_edit.visible = false
	_country_edit.visible = false
	y = _field(font, "PASSWORD - CONFIRMS IT'S REALLY YOU", _pass_edit, x, y, fw)

	if not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, y + 4.0), 13, Palette.HAZ)
	y += 22.0

	var bw := minf(320.0, fw)
	var del_r := Rect2(Vector2(cx - bw * 0.5, y), Vector2(bw, 44.0))
	_rects["delete_confirm"] = del_r
	_glow_button(del_r, Palette.HAZ, "YES, DELETE EVERYTHING", font, 1.0)

	var back := Rect2(Vector2(cx - 70.0, del_r.end.y + 12.0), Vector2(140.0, 28.0))
	_rects["delete_back"] = back
	_centre(font, "KEEP MY ACCOUNT", back.get_center(), 13, Color(1, 1, 1, 0.6))


func _centre(font, text: String, c: Vector2, size: int, col: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, c - Vector2(w * 0.5, -size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
