extends Node2D
# ============================================================
# LEADERBOARD SCREEN — the rankings, viewable by anyone (guests
# included; reading is anonymous, only SUBMITTING needs an account).
#
# Two boards per difficulty:
#   PROGRESS   furthest level reached, deaths as the tiebreak.
#              Everyone who has ever run lands here.
#   FINISHERS  cleared all levels — ranked by fewest deaths.
#              The elite board. Empty until someone beats the loop.
#
# GLOBAL shows everyone; the country tab filters server-side on the
# country prop each entry carries (only players who chose to show
# theirs appear there).
#
# Talo serves 50 entries per request; this screen shows 8 rows at a
# time and quietly fetches the next 50 when you page past what's
# loaded. `_fetch_id` guards against a slow response landing after
# the player has already switched tabs.
#
# VISUAL PASS (2026-09-02): restyled after a Google Stitch mockup —
# the row list now sits inside a glass panel, the player's own row
# gets a glowing left accent bar, the top 3 ranks read bigger, and
# loading shows three pulsing dots instead of static text. The UI
# CanvasLayer never blooms (see ui.gd / main.tscn), so glow here is
# faked by layering translucent outlines, same technique as
# account_panel.gd's _glow_rect() and ui.gd's draw_glass_disc().
# All tap-target rects are unchanged from before this pass.
# ============================================================

signal closed
signal join_requested

const ROWS := 8

var diff: int = 0            # Progress.Diff
var board_finishers := false
var scope_country := false
var level_count := 30

var entries: Array = []
var view_page := 0
var _server_page := 0
var _last_server_page := false
var loading := false
var error_text := ""
var _fetch_id := 0
var _t := 0.0

var _rects := {}


func open(d: int, count: int) -> void:
	diff = d
	level_count = count
	board_finishers = false
	scope_country = false
	visible = true
	_refetch()


func close() -> void:
	visible = false
	_fetch_id += 1   # orphan any in-flight response
	closed.emit()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


# ============================================================
# FETCHING
# ============================================================
func _board_name() -> String:
	return Talo.finishers_board(diff) if board_finishers else Talo.progress_board(diff)


func _refetch() -> void:
	entries = []
	view_page = 0
	_server_page = 0
	_last_server_page = false
	error_text = ""
	_fetch_page(0)


func _fetch_page(page: int) -> void:
	loading = true
	_fetch_id += 1
	var id := _fetch_id
	var pk := "country" if scope_country else ""
	var pv := Consent.country if scope_country else ""
	var res: Dictionary = await Talo.get_entries(_board_name(), page, pk, pv)
	if id != _fetch_id:
		return   # player already moved on — drop it
	loading = false
	if not res.ok:
		error_text = str(res.error)
		return
	error_text = ""
	entries.append_array(res.data.get("entries", []))
	_server_page = page
	_last_server_page = bool(res.data.get("isLastPage", true))


func _next_page() -> void:
	if (view_page + 1) * ROWS < entries.size():
		view_page += 1
	elif not _last_server_page and not loading:
		view_page += 1
		_fetch_page(_server_page + 1)


# ============================================================
# INPUT
# ============================================================
func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		return

	# Real touches + real mouse only — emulated mouse events (device
	# -1, synthesised from touch) would double-fire every tap.
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
	if not tapped:
		return

	for key in _rects:
		if _rects[key].has_point(pos):
			_tap(str(key))
			return


func _tap(what: String) -> void:
	match what:
		"back":
			close()
		"join":
			join_requested.emit()
		"prev":
			view_page = maxi(view_page - 1, 0)
		"next":
			_next_page()
		"retry":
			_refetch()
		"scope_global":
			if scope_country:
				scope_country = false
				_refetch()
		"scope_country":
			if not scope_country:
				scope_country = true
				_refetch()
		"board_progress":
			if board_finishers:
				board_finishers = false
				_refetch()
		"board_finishers":
			if not board_finishers:
				board_finishers = true
				_refetch()
		_:
			if what.begins_with("diff_"):
				var d := int(what.trim_prefix("diff_"))
				if d != diff:
					diff = d
					_refetch()


# ============================================================
# GLOW HELPERS
# Same layered-outline fake used by account_panel.gd's _glow_rect —
# duplicated locally rather than shared, since these two overlay
# scripts don't otherwise depend on each other.
# ============================================================
func _glow_rect(rect: Rect2, color: Color, strength: float = 1.0, width: float = 1.5) -> void:
	for i in range(3, 0, -1):
		var grown := rect.grow(float(i) * 2.0)
		draw_rect(grown, Color(color.r, color.g, color.b, 0.035 * strength / i), false, width)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.7 * strength), false, width)


func _draw_loading_dots(center: Vector2) -> void:
	for i in range(3):
		var phase := _t * 3.0 - float(i) * 0.6
		var a := 0.35 + 0.65 * absf(sin(phase))
		draw_circle(center + Vector2(float(i - 1) * 14.0, 0.0),
			3.5, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, a))


# ============================================================
# DRAWING
# ============================================================
func _draw() -> void:
	var screen := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var cx := screen.x * 0.5
	_rects = {}

	draw_rect(Rect2(Vector2.ZERO, screen), Palette.BG, true)
	_centre(font, "LEADERBOARD", Vector2(cx, 40.0), 28, Palette.glow(Palette.EDGE, 2.0))

	var back := Rect2(Vector2(24.0, 20.0), Vector2(96.0, 36.0))
	_rects["back"] = back
	draw_rect(back, Color(0, 0, 0, 0.3), true)
	draw_rect(back, Color(1, 1, 1, 0.3), false, 1.0)
	_centre(font, "< BACK", back.get_center(), 13, Color(1, 1, 1, 0.8))

	# --- Difficulty tabs ---
	var tiers := [Progress.Diff.STANDARD, Progress.Diff.HARD, Progress.Diff.EXTREME]
	var accents := [Palette.EDGE, Palette.GOAL, Palette.HAZ]
	var tw := 130.0
	var x := cx - (tw * 3.0 + 24.0) * 0.5
	for i in range(tiers.size()):
		var r := Rect2(Vector2(x, 66.0), Vector2(tw, 30.0))
		_rects["diff_%d" % tiers[i]] = r
		var on: bool = tiers[i] == diff
		var accent: Color = accents[i]
		draw_rect(r, Color(0, 0, 0, 0.3 if on else 0.15), true)
		if on:
			_glow_rect(r, accent, 0.85, 1.5)
		else:
			draw_rect(r, Color(accent.r, accent.g, accent.b, 0.18), false, 1.5)
		_centre(font, Progress.tier_name(tiers[i]), r.get_center(), 12,
			Color(accent.r, accent.g, accent.b, 1.0 if on else 0.4))
		x += tw + 12.0

	# --- Board tabs + scope toggle ---
	var bw := 150.0
	var bp := Rect2(Vector2(cx - bw - 8.0, 104.0), Vector2(bw, 28.0))
	var bf := Rect2(Vector2(cx + 8.0, 104.0), Vector2(bw, 28.0))
	_rects["board_progress"] = bp
	_rects["board_finishers"] = bf
	for pair in [[bp, "PROGRESS", not board_finishers], [bf, "FINISHERS", board_finishers]]:
		var r: Rect2 = pair[0]
		var on: bool = pair[2]
		draw_rect(r, Color(0, 0, 0, 0.3 if on else 0.15), true)
		draw_rect(r, Color(1, 1, 1, 0.4 if on else 0.1), false, 1.0)
		_centre(font, String(pair[1]), r.get_center(), 12, Color(1, 1, 1, 0.9 if on else 0.35))

	if not Consent.country.is_empty():
		var gr := Rect2(Vector2(screen.x - 220.0, 104.0), Vector2(92.0, 28.0))
		var cr := Rect2(Vector2(screen.x - 122.0, 104.0), Vector2(92.0, 28.0))
		_rects["scope_global"] = gr
		_rects["scope_country"] = cr
		for pair in [[gr, "GLOBAL", not scope_country], [cr, Consent.country, scope_country]]:
			var r: Rect2 = pair[0]
			var on: bool = pair[2]
			draw_rect(r, Color(0, 0, 0, 0.3 if on else 0.15), true)
			draw_rect(r, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.5 if on else 0.12), false, 1.0)
			_centre(font, String(pair[1]), r.get_center(), 12,
				Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 1.0 if on else 0.35))

	# --- The list, inside a glass panel ---
	var top := 152.0
	var row_h := 36.0
	var list_w := minf(680.0, screen.x - 80.0)
	var lx := cx - list_w * 0.5

	var panel := Rect2(Vector2(lx - 10.0, top - 10.0), Vector2(list_w + 20.0, ROWS * row_h + 20.0))
	draw_rect(panel, Color(1, 1, 1, 0.035), true)
	_glow_rect(panel, Palette.EDGE, 0.4, 1.0)

	if loading and entries.size() <= view_page * ROWS:
		_draw_loading_dots(Vector2(cx, top + 120.0))
	elif not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, top + 100.0), 14, Palette.HAZ)
		var rr := Rect2(Vector2(cx - 70.0, top + 130.0), Vector2(140.0, 32.0))
		_rects["retry"] = rr
		draw_rect(rr, Color(0, 0, 0, 0.3), true)
		draw_rect(rr, Color(1, 1, 1, 0.3), false, 1.0)
		_centre(font, "RETRY", rr.get_center(), 13, Color(1, 1, 1, 0.8))
	elif entries.is_empty():
		var msg := "NOBODY HAS CLEARED THE LOOP YET" if board_finishers else "NOBODY HERE YET"
		_centre(font, msg, Vector2(cx, top + 100.0), 16, Color(1, 1, 1, 0.5))
		_centre(font, "Be the first.", Vector2(cx, top + 128.0), 13,
			Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.7))
	else:
		var start := view_page * ROWS
		for i in range(start, mini(start + ROWS, entries.size())):
			_draw_row(font, entries[i], i, Vector2(lx, top + (i - start) * row_h), list_w, row_h)

	# --- Paging ---
	var py := panel.end.y + 14.0
	if view_page > 0:
		var pr := Rect2(Vector2(cx - 110.0, py), Vector2(90.0, 30.0))
		_rects["prev"] = pr
		draw_rect(pr, Color(0, 0, 0, 0.25), true)
		draw_rect(pr, Color(1, 1, 1, 0.25), false, 1.0)
		_centre(font, "< PREV", pr.get_center(), 12, Color(1, 1, 1, 0.7))
	if (view_page + 1) * ROWS < entries.size() \
			or (not _last_server_page and not entries.is_empty()):
		var nr := Rect2(Vector2(cx + 20.0, py), Vector2(90.0, 30.0))
		_rects["next"] = nr
		draw_rect(nr, Color(0, 0, 0, 0.25), true)
		draw_rect(nr, Color(1, 1, 1, 0.25), false, 1.0)
		_centre(font, "NEXT >", nr.get_center(), 12, Color(1, 1, 1, 0.7))

	# --- Join banner for guests: full-width, bottom of screen ---
	if not Talo.logged_in():
		var jw := minf(560.0, screen.x - 48.0)
		var jr := Rect2(Vector2(cx - jw * 0.5, screen.y - 58.0), Vector2(jw, 40.0))
		_rects["join"] = jr
		draw_rect(jr, Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.07), true)
		_glow_rect(jr, Palette.GOAL, 1.0, 1.5)
		_centre(font, "JOIN THE LEADERBOARD", jr.get_center(), 15, Palette.GOAL)


func _draw_row(font, entry: Dictionary, index: int, pos: Vector2, w: float, h: float) -> void:
	var alias: Dictionary = entry.get("playerAlias", {})
	var mine: bool = int(alias.get("id", -2)) == Talo.alias_id
	var row := Rect2(pos, Vector2(w, h - 4.0))

	if mine:
		draw_rect(row, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.10), true)
		_glow_rect(row, Palette.EDGE, 0.8, 1.0)
		draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), Palette.EDGE, true)
	elif index % 2 == 0:
		draw_rect(row, Color(1, 1, 1, 0.02), true)

	var name_col := Palette.EDGE if mine else Palette.TEXT
	var ty := pos.y + h * 0.5 + 5.0
	var rank := index + 1

	# Top 3 read bigger and brighter — the rest of the list stays quiet.
	var rank_size := 15
	var rank_col := Color(1, 1, 1, 0.45)
	if rank == 1:
		rank_size = 22
		rank_col = Palette.GOAL
	elif rank <= 3:
		rank_size = 18
		rank_col = Color(1, 1, 1, 0.75)

	draw_string(font, Vector2(pos.x + 12.0, ty), "#%d" % rank,
		HORIZONTAL_ALIGNMENT_LEFT, -1, rank_size, rank_col)
	draw_string(font, Vector2(pos.x + 64.0, ty), str(alias.get("identifier", "?")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, name_col)

	# Props arrive as [{key, value}, ...].
	var deaths := ""
	var country := ""
	for p in entry.get("props", []):
		if p is Dictionary:
			if str(p.get("key", "")) == "deaths":
				deaths = str(p.get("value", ""))
			elif str(p.get("key", "")) == "country":
				country = str(p.get("value", ""))

	var score := float(entry.get("score", 0.0))
	var result := ""
	var result_col := Palette.TEXT
	if board_finishers:
		result = "%d DEATHS" % int(score)
	else:
		var lvl := Talo.progress_level(score)
		if lvl > level_count:
			result = "CLEAR"
			result_col = Palette.GOAL
		else:
			result = "LVL %d" % lvl
		if not deaths.is_empty():
			result += "  -  %s deaths" % deaths

	var rw: float = font.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(pos.x + w - rw - 70.0, ty), result,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, result_col)

	if not country.is_empty():
		draw_string(font, Vector2(pos.x + w - 44.0, ty), country,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.4))


func _centre(font, text: String, c: Vector2, size: int, col: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, c - Vector2(w * 0.5, -size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
