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
#
# DISTANCE MODE (Phase E section 8, 2026-09-22): the endless run's
# board, opened from the main menu with open_distance(). One board
# (Talo.DISTANCE_BOARD), so the difficulty tabs and the PROGRESS /
# FINISHERS switch are hidden and only GLOBAL / MY COUNTRY remain; a
# row is rank, name, country, metres. The menu keeps the live world
# behind it and dims it, so this mode paints no opaque background. Its
# tap targets are 66 units tall — 48 pt on the phone (menu.gd TAP_MIN).
# The 2D game's mode is untouched.
#
# THE MENU'S LOOK (2026-10-23, roadmap step 4: "the leaderboard and
# settings pages need to resemble the main menu", Milko). Distance mode
# is drawn with the menu's parts (prototype/hud.gd's kit): a round glass
# BACK, the tracked title, GLOBAL / MY COUNTRY as capsules (the chosen
# one cyan), the list on a rounded glass card, #1 on an amber badge,
# #2 and #3 on glass ones, the player's own row cyan with a YOU tag,
# round PREV / NEXT either side of the card (DISABLED when there is no
# page that way) and the amber JOIN. Buttons act when the finger lifts
# (prototype/press.gd). The 2D game's mode keeps its old look.
# ============================================================

signal closed
signal join_requested

const Hud := preload("res://prototype/hud.gd")
const Press := preload("res://prototype/press.gd")
const LapGen := preload("res://prototype/lap_gen.gd")
const ROWS := 8
const DISTANCE_ROWS := 5      # fewer rows: the tabs and pills are taller in that mode
const TAP := 66.0

var distance_mode := false

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
var _press := Press.new()


func open(d: int, count: int) -> void:
	distance_mode = false
	diff = d
	level_count = count
	board_finishers = false
	scope_country = false
	visible = true
	_refetch()


# The endless run's board (section 8). Anyone may read it.
func open_distance() -> void:
	distance_mode = true
	board_finishers = false
	scope_country = false
	visible = true
	_refetch()


func _rows() -> int:
	return DISTANCE_ROWS if distance_mode else ROWS


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
	if distance_mode:
		return Talo.DISTANCE_BOARD
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
	if (view_page + 1) * _rows() < entries.size():
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

	# A button acts when the finger lifts on it (press.gd: real touches and
	# a real mouse only, the click on the way down).
	var tapped := _press.feed(event, _rects)
	if tapped != "":
		_tap(tapped)


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

	if distance_mode:
		# The dim over the menu's live world, drawn here, BEHIND the rows
		# (the menu's own dim was drawn over them). Same darkness as before.
		draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.55), true)
		_draw_distance(screen, font, cx)
		return

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
	_draw_list(font, cx, lx, top, list_w, row_h, panel, screen)


# The rows, the empty / error / loading states, the paging and the join
# banner — shared by both modes. `rows` per page differs between them.
func _draw_list(font, cx: float, lx: float, top: float, list_w: float, row_h: float, panel: Rect2, screen: Vector2) -> void:
	var rows := _rows()
	var th := 60.0 if distance_mode else 30.0
	if loading and entries.size() <= view_page * rows:
		_draw_loading_dots(Vector2(cx, top + 120.0))
	elif not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, top + 100.0), 14, Palette.HAZ)
		var rr := Rect2(Vector2(cx - 70.0, top + 130.0), Vector2(140.0, 32.0))
		_rects["retry"] = rr
		draw_rect(rr, Color(0, 0, 0, 0.3), true)
		draw_rect(rr, Color(1, 1, 1, 0.3), false, 1.0)
		_centre(font, "RETRY", rr.get_center(), 13, Color.WHITE)
	elif entries.is_empty():
		var msg := "NOBODY HAS CLEARED THE LOOP YET" if board_finishers else "NOBODY HERE YET"
		if distance_mode:
			msg = "NOBODY HAS RUN YET"
		_centre(font, msg, Vector2(cx, top + 100.0), 16, Color.WHITE)
		_centre(font, "Be the first.", Vector2(cx, top + 128.0), 13, Palette.GOAL)
	else:
		var start := view_page * rows
		for i in range(start, mini(start + rows, entries.size())):
			_draw_row(font, entries[i], i, Vector2(lx, top + (i - start) * row_h), list_w, row_h)

	# --- Paging ---
	var py := panel.end.y + 14.0
	if view_page > 0:
		var pr := Rect2(Vector2(cx - 110.0, py), Vector2(90.0, th))
		_rects["prev"] = pr
		draw_rect(pr, Color(0, 0, 0, 0.25), true)
		draw_rect(pr, Color(1, 1, 1, 0.25), false, 1.0)
		_centre(font, "< PREV", pr.get_center(), 12, Color.WHITE)
	if (view_page + 1) * rows < entries.size() \
			or (not _last_server_page and not entries.is_empty()):
		var nr := Rect2(Vector2(cx + 20.0, py), Vector2(90.0, th))
		_rects["next"] = nr
		draw_rect(nr, Color(0, 0, 0, 0.25), true)
		draw_rect(nr, Color(1, 1, 1, 0.25), false, 1.0)
		_centre(font, "NEXT >", nr.get_center(), 12, Color.WHITE)

	# --- Join banner for guests: full-width, bottom of screen ---
	if not Talo.logged_in():
		var jw := minf(560.0, screen.x - 48.0)
		var jh := TAP if distance_mode else 40.0
		var jr := Rect2(Vector2(cx - jw * 0.5, screen.y - 30.0 - jh), Vector2(jw, jh))
		_rects["join"] = jr
		draw_rect(jr, Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.07), true)
		_glow_rect(jr, Palette.GOAL, 1.0, 1.5)
		_centre(font, "JOIN TO POST YOUR DISTANCE" if distance_mode else "JOIN THE LEADERBOARD",
			jr.get_center(), 15, Palette.GOAL)


# Distance mode, in the menu's look (see the header). Laid out for a
# phone, 540 units tall: BACK top-left clear of the notch, the title
# centred, the two tabs under it, the card, JOIN at the bottom. The frame
# readout (dev builds) lives top-right, so nothing is put there.
const D_MARGIN := 88.0
const D_ROW := 46.0
const D_CARD_TOP := 180.0
const D_PAGE := 60.0

func _draw_distance(screen: Vector2, font, cx: float) -> void:
	Hud.title(self, Hud.bold(), "LEADERBOARD", cx, 58.0, 30, 5.0, Color.WHITE)
	Hud.title(self, font, "SEASON %d  ·  FURTHEST DISTANCE" % LapGen.SEASON_SEED, cx, 84.0, 12, 2.0, Color(1, 1, 1, 0.75))

	var back := Rect2(Vector2(D_MARGIN, 22.0), Vector2(TAP, TAP))
	_rects["back"] = back
	var bs := _press.state("back")
	Hud.capsule_button(self, back, Hud.GLASS_TOP, Hud.GLASS_BOTTOM, 1.0, 0.0, bs)
	_chevron(back.get_center() + Hud.sink(bs), -1.0, Color.WHITE)

	# GLOBAL / MY COUNTRY, centred; MY COUNTRY only when there is one to show.
	var tw := 190.0
	var ty := 100.0
	var gr := Rect2(Vector2(cx - tw * 0.5, ty), Vector2(tw, TAP))
	if not Consent.country.is_empty():
		gr.position.x = cx - tw - 8.0
		var cr := Rect2(Vector2(cx + 8.0, ty), Vector2(tw, TAP))
		_rects["scope_country"] = cr
		Hud.button(self, cr, "MY COUNTRY  ·  " + Consent.country, "go" if scope_country else "glass", _press.state("scope_country"), 15)
	_rects["scope_global"] = gr
	Hud.button(self, gr, "GLOBAL", "go" if not scope_country else "glass", _press.state("scope_global"), 15)

	var join_h := TAP if not Talo.logged_in() else 0.0
	var card_bottom := screen.y - 24.0 - join_h - (14.0 if join_h > 0.0 else 0.0)
	var list_w := minf(700.0, screen.x - 2.0 * (D_MARGIN + D_PAGE + 24.0))
	var card := Rect2(Vector2(cx - list_w * 0.5, D_CARD_TOP), Vector2(list_w, card_bottom - D_CARD_TOP))
	Hud.card(self, card)
	_draw_distance_list(font, card)

	# PREV / NEXT, round, either side of the card.
	var mid_y := card.get_center().y
	var can_prev := view_page > 0
	var can_next := (view_page + 1) * DISTANCE_ROWS < entries.size() or (not _last_server_page and not entries.is_empty())
	for side in [["prev", -1.0, can_prev], ["next", 1.0, can_next]]:
		var key: String = side[0]
		var dir: float = side[1]
		var on: bool = side[2]
		var x: float = card.position.x - 24.0 - D_PAGE if dir < 0.0 else card.end.x + 24.0
		var r := Rect2(Vector2(x, mid_y - D_PAGE * 0.5), Vector2(D_PAGE, D_PAGE))
		if on:
			_rects[key] = r
		var st := _press.state(key, on)
		Hud.capsule_button(self, r, Hud.GLASS_TOP, Hud.GLASS_BOTTOM, 1.0, 0.0, st)
		_chevron(r.get_center() + Hud.sink(st), dir, Color(1, 1, 1, 0.5 if not on else 1.0))

	if join_h > 0.0:
		var jw := minf(460.0, screen.x - 48.0)
		var jr := Rect2(Vector2(cx - jw * 0.5, screen.y - 24.0 - join_h), Vector2(jw, join_h))
		_rects["join"] = jr
		Hud.button(self, jr, "JOIN TO POST YOUR DISTANCE", "goal", _press.state("join"), 17)


# A chevron pointing left (dir -1) or right (+1): BACK, PREV, NEXT.
func _chevron(at: Vector2, dir: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([at + Vector2(-4.0 * dir, -11.0), at + Vector2(5.0 * dir, 0.0),
		at + Vector2(-4.0 * dir, 11.0)]), col, 4.0, true)


# The rows on the card, or what stands in for them: loading, an error
# with RETRY, or nobody yet.
func _draw_distance_list(font, card: Rect2) -> void:
	var cx := card.get_center().x
	var mid := card.get_center().y
	if loading and entries.size() <= view_page * DISTANCE_ROWS:
		_draw_loading_dots(Vector2(cx, mid))
		return
	if not error_text.is_empty():
		_centre(font, error_text, Vector2(cx, mid - 30.0), 14, Color(1, 1, 1, 0.85))
		var rr := Rect2(Vector2(cx - 80.0, mid), Vector2(160.0, TAP))
		_rects["retry"] = rr
		Hud.button(self, rr, "RETRY", "glass", _press.state("retry"), 15)
		return
	if entries.is_empty():
		Hud.title(self, Hud.bold(), "NOBODY HAS RUN YET", cx, mid - 4.0, 20, 2.0, Color.WHITE)
		Hud.title(self, font, "Be the first.", cx, mid + 26.0, 14, 1.0, Palette.GOAL)
		return
	var top := card.position.y + (card.size.y - DISTANCE_ROWS * D_ROW) * 0.5
	var start := view_page * DISTANCE_ROWS
	for i in range(start, mini(start + DISTANCE_ROWS, entries.size())):
		_draw_distance_row(font, entries[i], i, Rect2(Vector2(card.position.x + 18.0, top + (i - start) * D_ROW + 3.0),
			Vector2(card.size.x - 36.0, D_ROW - 6.0)))


# One row: a rank badge, the name (YOU on the player's own), the country
# on a small glass chip, the metres. Every word solid (2026-09-29).
func _draw_distance_row(font, entry: Dictionary, index: int, row: Rect2) -> void:
	var alias: Dictionary = entry.get("playerAlias", {})
	var mine: bool = int(alias.get("id", -2)) == Talo.alias_id
	var rank := index + 1
	if mine:
		Hud._round(self, row, -1.0, Color(WorldPalette.SAFE, 0.32), Color(WorldPalette.SAFE.darkened(0.3), 0.32))
		Hud._outline(self, row, -1.0, Color(WorldPalette.SAFE.lightened(0.3), 0.9))
	elif index % 2 == 0:
		Hud._round(self, row, -1.0, Color(1, 1, 1, 0.05))
	var cy := row.get_center().y
	var badge := Vector2(row.position.x + 26.0, cy)
	var label := str(rank)
	if rank == 1:
		draw_circle(badge, 16.0, Palette.GOAL)
		draw_arc(badge, 16.0, 0.0, TAU, 24, Palette.GOAL.lightened(0.4), 1.5, true)
		_centre(Hud.bold(), label, badge, 16, Color(0.2, 0.11, 0.0))
	elif rank <= 3:
		draw_circle(badge, 16.0, Hud.GLASS_TOP)
		draw_arc(badge, 16.0, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 1.5, true)
		_centre(Hud.bold(), label, badge, 16, Color.WHITE)
	else:
		_centre(Hud.bold(), label, badge, 15, Color(1, 1, 1, 0.7))

	var who := str(alias.get("identifier", "?"))
	var nx := row.position.x + 58.0
	draw_string(Hud.bold(), Vector2(nx, cy + 7.0), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		WorldPalette.SAFE.lightened(0.5) if mine else Color.WHITE)
	if mine:
		var nw: float = Hud.bold().get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var tag := Rect2(Vector2(nx + nw + 12.0, cy - 11.0), Vector2(46.0, 22.0))
		Hud._round(self, tag, -1.0, WorldPalette.SAFE.lightened(0.3), WorldPalette.SAFE.darkened(0.1))
		_centre(Hud.bold(), "YOU", tag.get_center(), 11, Hud.INK)

	var country := ""
	for p in entry.get("props", []):
		if p is Dictionary and str(p.get("key", "")) == "country":
			country = str(p.get("value", ""))
	var metres := Hud.metres(int(float(entry.get("score", 0.0))))
	var mw: float = Hud.bold().get_string_size(metres, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var mx := row.end.x - 18.0 - mw
	draw_string(Hud.bold(), Vector2(mx, cy + 7.0), metres, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	if not country.is_empty():
		var chip := Rect2(Vector2(mx - 60.0, cy - 12.0), Vector2(44.0, 24.0))
		Hud._round(self, chip, -1.0, Color(Hud.GLASS_TOP, 0.9), Color(Hud.GLASS_BOTTOM, 0.9))
		_centre(Hud.bold(), country, chip.get_center(), 12, Color(1, 1, 1, 0.9))


func _draw_row(font, entry: Dictionary, index: int, pos: Vector2, w: float, h: float) -> void:
	var alias: Dictionary = entry.get("playerAlias", {})
	var mine: bool = int(alias.get("id", -2)) == Talo.alias_id
	var row := Rect2(pos, Vector2(w, h - 4.0))

	if mine:
		draw_rect(row, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.10), true)
		_glow_rect(row, Palette.EDGE, 0.8, 1.0)
		draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), Palette.EDGE, true)
	elif index % 2 == 0:
		draw_rect(row, Color(1, 1, 1, 0.05), true)

	# Every word on a row is solid (2026-09-29): the rank and the country
	# step back by colour (Palette.TEXT), never by transparency.
	var name_col := Palette.EDGE if mine else Color.WHITE
	var ty := pos.y + h * 0.5 + 5.0
	var rank := index + 1

	# Top 3 read bigger and brighter — the rest of the list stays quiet.
	var rank_size := 15
	var rank_col := Palette.TEXT
	if rank == 1:
		rank_size = 22
		rank_col = Palette.GOAL
	elif rank <= 3:
		rank_size = 18
		rank_col = Color.WHITE

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
	if distance_mode:
		result = Hud.metres(int(score))
		result_col = Color.WHITE
	elif board_finishers:
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
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.TEXT)


func _centre(font, text: String, c: Vector2, size: int, col: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, c - Vector2(w * 0.5, -size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
