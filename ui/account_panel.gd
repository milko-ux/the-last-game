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
#
# THE MENU'S LOOK (2026-10-23, roadmap step 4). The Stitch look (sharp
# glass, corner brackets, neon outlines) is replaced by the menu's parts
# (prototype/hud.gd's kit): a rounded glass card, capsule buttons in
# their styles -- amber for joining (CREATE ACCOUNT, LOG IN), glass for
# SIGN OUT, the lethal magenta for deleting -- capsule tabs and switches
# with the chosen side cyan, rounded glass fields, the menu's lettering,
# a round close button. Buttons act when the finger lifts (press.gd).
# ============================================================

signal closed

enum Mode { CONSENT, FORM, SIGNED_IN, DELETE }

const PANEL_W := 560.0
const Hud := preload("res://prototype/hud.gd")
const Press := preload("res://prototype/press.gd")

var mode: int = Mode.CONSENT
var form_login := false   # false = create account, true = log in
var busy := false
var error_text := ""
var _pass_visible := false

# Tap targets, recorded while drawing (same pattern as ui.gd).
var _rects := {}          # name -> Rect2
var _press := Press.new()
var _open_t := 0.0        # seconds since the panel opened (the pop-in)

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

	# The menu's look (2026-10-23): a rounded well of dark glass, its rim
	# cyan while it has the keyboard.
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.05, 0.12, 0.85)
	normal.border_color = Color(1, 1, 1, 0.18)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(14)
	normal.anti_aliasing = true
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0

	var focus: StyleBoxFlat = normal.duplicate()
	focus.border_color = Color(WorldPalette.SAFE.lightened(0.3), 0.95)
	focus.set_border_width_all(2)

	e.add_theme_stylebox_override("normal", normal)
	e.add_theme_stylebox_override("focus", focus)
	e.add_theme_color_override("font_color", Color.WHITE)
	e.add_theme_color_override("caret_color", WorldPalette.SAFE.lightened(0.3))
	e.add_theme_font_size_override("font_size", 16)
	add_child(e)
	return e


func open() -> void:
	error_text = ""
	busy = false
	_editing_country = false
	_pass_visible = false
	_consent_detail = false
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
	_open_t = 0.0
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


func _process(delta: float) -> void:
	if visible:
		_open_t += delta
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

	if busy:
		return
	# A tap outside any field commits the in-progress country edit.
	if Press.is_down(event) and _editing_country and not _rects.get("country", Rect2()).has_point(event.position):
		_finish_country_edit()
	# A button acts when the finger lifts on it (press.gd: real touches and
	# a real mouse only, the click on the way down).
	var tapped := _press.feed(event, _rects)
	if tapped != "":
		_tap(tapped)


func _tap(what: String) -> void:
	match what:
		"close", "close2":
			close()
		"detail":
			_consent_detail = true
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


# A capsule button in a Hud style, showing the state the finger gives it.
func _button(rect: Rect2, key: String, label: String, style := "glass", size := 15) -> void:
	_rects[key] = rect
	Hud.button(self, rect, label, style, _press.state(key), size, 1.0, _press.scale(key))


# A two-way switch: the chosen side light glass, the other dark glass
# (cyan is kept for a screen's one main action).
func _choice(rect: Rect2, key: String, label: String, on: bool, size := 13) -> void:
	_rects[key] = rect
	Hud.button(self, rect, label, "chosen" if on else "glass", _press.state(key), size, 1.0, _press.scale(key))


# A text link (NOT NOW, KEEP MY ACCOUNT, What exactly is stored?).
func _link(rect: Rect2, key: String, label: String, font) -> void:
	_rects[key] = rect
	var a := 0.55 if _press.state(key) == Hud.Btn.PRESSED else 0.85
	_centre(font, label, rect.get_center(), 13, Color(1, 1, 1, a))


# ============================================================
# DRAWING
# ============================================================
func _draw() -> void:
	var screen := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	_rects = {}

	# Dim everything underneath so the panel owns the screen.
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.72), true)

	var w := minf(PANEL_W, screen.x - 60.0)
	var h := 470.0 if mode == Mode.CONSENT else 420.0
	var panel := Rect2(Vector2((screen.x - w) * 0.5, (screen.y - h) * 0.5), Vector2(w, h))

	# The sheet pops in. The LineEdits are real controls and cannot scale
	# with it, so they appear once it has settled.
	var k := Hud.intro_k(_open_t)
	Hud.zoom(self, panel.get_center(), k)
	Hud.card(self, panel)

	# Close, a round glass button top-right -- except mid-delete, where
	# KEEP MY ACCOUNT is the explicit way back.
	if mode != Mode.DELETE and not busy:
		var xr := Rect2(panel.position + Vector2(w - 62, 12), Vector2(50, 50))
		_rects["close"] = xr
		var xs := _press.state("close")
		Hud.capsule_button(self, xr, Hud.GLASS_TOP, Hud.GLASS_BOTTOM, 1.0, 0.0, xs)
		var xc := xr.get_center() + Hud.sink(xs)
		draw_line(xc + Vector2(-7, -7), xc + Vector2(7, 7), Color.WHITE, 2.6, true)
		draw_line(xc + Vector2(-7, 7), xc + Vector2(7, -7), Color.WHITE, 2.6, true)

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
		_centre(Hud.bold(), "...", Vector2(panel.get_center().x, panel.end.y - 22), 20, WorldPalette.SAFE.lightened(0.3))
	Hud.unzoom(self)
	if _open_t < Hud.POP_S:
		for e in [_name_edit, _pass_edit, _email_edit, _country_edit]:
			e.visible = false


# The consent screen (2026-09-22, Milko's copy): short enough to read
# in one breath. The full detail is one tap away — "What exactly is
# stored?" swaps in the long text, unchanged, on the same screen.
const CONSENT_SHORT := [
	"To put your distance on the board we store your name,",
	"a scrambled password and your scores.",
	"",
	"Email only if you want password recovery.",
	"Country only if you choose to show it.",
	"",
	"No tracking. No ads. Nothing sold.",
	"",
	"Delete your account in the game any time —",
	"your scores go with it.",
	"",
	"Rather not? Play as a guest. Nothing leaves your phone.",
]
const CONSENT_LONG := [
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
var _consent_detail := false


func _draw_consent(panel: Rect2, font) -> void:
	var cx := panel.get_center().x
	var y := panel.position.y + 40.0
	Hud.title(self, Hud.bold(), "JOIN THE LEADERBOARD", cx, y + 6.0, 22, 3.0, Color.WHITE)
	y += 36.0

	var lines: Array = CONSENT_LONG if _consent_detail else CONSENT_SHORT
	for line in lines:
		_centre(font, line, Vector2(cx, y), 13, Color(1, 1, 1, 0.82))
		y += 18.0

	if not _consent_detail:
		y += 4.0
		_link(Rect2(Vector2(cx - 110.0, y - 6.0), Vector2(220.0, 26.0)), "detail", "What exactly is stored?", font)
		draw_line(Vector2(cx - 74.0, y + 16.0), Vector2(cx + 74.0, y + 16.0), Color(1, 1, 1, 0.35), 1.0)
		y += 26.0

	var bw := minf(320.0, panel.size.x - 60.0)
	var agree := Rect2(Vector2(cx - bw * 0.5, y + 8.0), Vector2(bw, 48.0))
	_button(agree, "agree", "CREATE ACCOUNT", "goal", 16)
	_link(Rect2(Vector2(cx - 70.0, agree.end.y + 10.0), Vector2(140.0, 28.0)), "close2", "NOT NOW", font)


func _draw_form(panel: Rect2, font) -> void:
	var cx := panel.get_center().x
	var x := panel.position.x + 40.0
	var fw := panel.size.x - 80.0
	var y := panel.position.y + 24.0

	# The two forms as a capsule switch, the chosen one cyan.
	var tw := 170.0
	_choice(Rect2(Vector2(cx - tw - 6.0, y), Vector2(tw, 38.0)), "tab_register", "CREATE ACCOUNT", not form_login)
	_choice(Rect2(Vector2(cx + 6.0, y), Vector2(tw, 38.0)), "tab_login", "LOG IN", form_login)
	y += 52.0

	y = _field(font, "NAME", _name_edit, x, y, fw)
	y = _field(font, "PASSWORD", _pass_edit, x, y, fw)
	if form_login:
		_email_edit.visible = false
	else:
		y = _field(font, "EMAIL - OPTIONAL, ONLY FOR PASSWORD RECOVERY", _email_edit, x, y, fw)
		y = _draw_country_row(font, x, y, fw)

	if not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, y + 4.0), 13, WorldPalette.LETHAL_SEAM)
	y += 18.0

	var bw := minf(320.0, fw)
	_button(Rect2(Vector2(cx - bw * 0.5, y), Vector2(bw, 46.0)), "submit", "LOG IN" if form_login else "CREATE ACCOUNT", "goal", 16)


# One labelled input row. Positions the LineEdit over the panel and
# returns the y below it. The password field grows a SHOW/HIDE toggle
# in its label row automatically.
func _field(font, label: String, edit: LineEdit, x: float, y: float, fw: float) -> float:
	draw_string(Hud.bold(), Vector2(x, y + 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))

	if edit == _pass_edit:
		edit.secret = not _pass_visible
		var tr := Rect2(Vector2(x + fw - 54.0, y - 4.0), Vector2(54.0, 18.0))
		_rects["pass_toggle"] = tr
		_centre(Hud.bold(), "SHOW" if not _pass_visible else "HIDE", tr.get_center(), 10,
			WorldPalette.SAFE.lightened(0.35))

	edit.visible = true
	edit.position = Vector2(x, y + 16.0)
	edit.size = Vector2(fw, 34.0)
	return y + 58.0


func _draw_country_row(font, x: float, y: float, fw: float) -> float:
	draw_string(Hud.bold(), Vector2(x, y + 10.0), "COUNTRY ON THE LEADERBOARD",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.7))

	var code_r := Rect2(Vector2(x, y + 16.0), Vector2(64.0, 30.0))
	_rects["country"] = code_r
	if _editing_country:
		_country_edit.visible = true
		_country_edit.position = code_r.position
		_country_edit.size = code_r.size
	else:
		_country_edit.visible = false
		var code := Consent.country if not Consent.country.is_empty() else "--"
		Hud.button(self, code_r, code, "glass", _press.state("country"), 15)

	var show_r := Rect2(Vector2(x + 76.0, y + 16.0), Vector2(86.0, 30.0))
	var hide_r := Rect2(Vector2(x + 168.0, y + 16.0), Vector2(86.0, 30.0))
	_choice(show_r, "country_show", "SHOWN", Consent.show_country, 12)
	_choice(hide_r, "country_hide", "HIDDEN", not Consent.show_country, 12)

	draw_string(font, Vector2(x + 266.0, y + 36.0), "tap the code to change it",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
	return y + 60.0


func _draw_signed_in(panel: Rect2, font) -> void:
	_name_edit.visible = false
	_pass_edit.visible = false
	_email_edit.visible = false
	var cx := panel.get_center().x
	var x := panel.position.x + 40.0
	var fw := panel.size.x - 80.0
	var y := panel.position.y + 56.0

	_centre(Hud.bold(), "SIGNED IN AS", Vector2(cx, y), 12, Color(1, 1, 1, 0.65))
	Hud.title(self, Hud.bold(), Talo.identifier, cx, y + 38.0, 26, 2.0, WorldPalette.SAFE.lightened(0.45))
	y += 70.0

	y = _draw_country_row(font, x, y, fw)
	y += 14.0

	if not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, y), 13, WorldPalette.LETHAL_SEAM)
	y += 16.0

	var bw := minf(320.0, fw)
	_button(Rect2(Vector2(cx - bw * 0.5, y), Vector2(bw, 44.0)), "signout", "SIGN OUT", "glass")
	_button(Rect2(Vector2(cx - bw * 0.5, y + 56.0), Vector2(bw, 44.0)), "delete", "DELETE ACCOUNT + MY DATA", "danger", 14)


func _draw_delete(panel: Rect2, font) -> void:
	var cx := panel.get_center().x
	var x := panel.position.x + 40.0
	var fw := panel.size.x - 80.0
	var y := panel.position.y + 50.0

	Hud.title(self, Hud.bold(), "DELETE THIS ACCOUNT?", cx, y + 6.0, 22, 2.0, WorldPalette.LETHAL_SEAM)
	y += 34.0
	for line in [
		"This permanently removes your account and your",
		"leaderboard entries. There is no undo.",
	]:
		_centre(font, line, Vector2(cx, y), 13, Color(1, 1, 1, 0.82))
		y += 18.0
	y += 16.0

	_email_edit.visible = false
	_name_edit.visible = false
	_country_edit.visible = false
	y = _field(font, "PASSWORD - CONFIRMS IT'S REALLY YOU", _pass_edit, x, y, fw)

	if not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, y + 4.0), 13, WorldPalette.LETHAL_SEAM)
	y += 22.0

	var bw := minf(320.0, fw)
	var del_r := Rect2(Vector2(cx - bw * 0.5, y), Vector2(bw, 46.0))
	_button(del_r, "delete_confirm", "YES, DELETE EVERYTHING", "danger")
	_link(Rect2(Vector2(cx - 80.0, del_r.end.y + 12.0), Vector2(160.0, 28.0)), "delete_back", "KEEP MY ACCOUNT", font)


func _centre(font, text: String, c: Vector2, size: int, col: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, c - Vector2(w * 0.5, -size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
