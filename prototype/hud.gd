extends Node2D
# ============================================================
# PHASE R HUD — the progress bar and the one-word demo label, in the
# same frosted-glass language as the touch controls (ui/ui.gd's
# draw_glass_disc), drawn here so ui.gd stays untouched.
#
# Progress bar (addendum 2): fill = song_time / duration, ticks at
# checkpoint bars, a "best" marker at the furthest point reached
# (persisted per level in Progress). On death the fill jumps back to
# the checkpoint; the best marker stays — that gap is the retry hook.
# ============================================================

const BAR_H := 6.0
const BAR_Y := 10.0
const MARGIN := 18.0

var fill := 0.0             # 0..1
var best := 0.0             # 0..1
var ticks: Array = []       # 0..1 positions
var lit := 0                # brief 3: the first `lit` ticks have been reached
var word := ""
var word_alpha := 0.0
# The endless run (Phase E section 5): no song progress bar. Top centre is
# the distance (a Label the run scene owns); this node draws what sits
# beside it, in the same glass language: the lives, left of the number,
# and the shield meter, right of it — a small glass ring that fills amber
# as notes charge it and turns cyan when the shield is armed.
var endless := false
var lives := 0
var lives_max := 0          # 0 = lives are off (a new player's lap 0): nothing drawn
var shield := 0.0           # 0..1
var shield_armed := false
var shield_pop := 0.0       # 1 -> 0 after the shield was used (the ring flashes)
const SIDE_GAP := 120.0     # from the screen's centre line to the lives / the ring
const HEART_SIZE := 26.0
const HEART_GAP := 32.0
const HEART_POP_S := 0.45
var _heart_pop := []        # per heart, 1 -> 0 after it was lost
var _lives_seen := -1
const HUD_Y := 38.0
# The end screen (section 6, minimal: the share / roast screen is its own
# brief). Distance big, BEST, NEW BEST when it is, RETRY (big) and MENU.
var end_shown := false
var end_distance := ""
var end_best := ""
var end_new_best := false
var end_alpha := 0.0
var retry_rect := Rect2()
var menu_rect := Rect2()
# Section 8: the rank line ("#12 GLOBAL   ·   #3 SE", or "POSTING…", or
# an error) under BEST, and for a guest the JOIN pill that leads to the
# account panel.
var end_rank := ""
var end_join := false
var join_rect := Rect2()
# PAUSE (2026-09-22): a small glass pill top-left while the run is on,
# the panel (RESUME · RESTART · HOME) while paused, and the 3-2-1 count
# back in. The run scene owns the state; this only draws it.
var show_pause := false
var paused := false
var countin := 0.0          # seconds left of the count-in, 0 = none
var pause_rect := Rect2()
var resume_rect := Rect2()
var restart_rect := Rect2()
var home_rect := Rect2()
const PAUSE_AT := Vector2(88.0, 20.0)   # clear of the notch (menu.gd MARGIN)
const PAUSE_SIZE := 66.0                 # 48 pt on the phone


func _process(delta: float) -> void:
	shield_pop = maxf(0.0, shield_pop - delta * 2.5)
	if _heart_pop.size() != lives_max:
		_heart_pop.resize(lives_max)
		_heart_pop.fill(0.0)
	if _lives_seen >= 0 and lives < _lives_seen:
		for i in range(lives, mini(_lives_seen, lives_max)):
			_heart_pop[i] = 1.0
	_lives_seen = lives
	for i in _heart_pop.size():
		_heart_pop[i] = maxf(0.0, float(_heart_pop[i]) - delta / HEART_POP_S)
	end_alpha = minf(1.0, end_alpha + delta * 3.0) if end_shown else 0.0
	if word_alpha > 0.0 and word == "":
		word_alpha = maxf(0.0, word_alpha - delta * 2.5)
	# Repaint only when something drawn has changed (2026-09-24). Every
	# draw_circle / draw_arc below is a GPU buffer built and deleted per
	# repaint, and iOS Safari's GPU process crashes on that churn (see
	# ui/ui.gd's header). Steady play repaints nothing.
	var key := [endless, end_shown, end_alpha, paused, countin, fill, best, ticks, lit, word, word_alpha,
		lives, lives_max, _heart_pop.duplicate(), shield, shield_armed, shield_pop, show_pause, end_distance, end_best, end_new_best,
		end_rank, end_join, get_viewport_rect().size]
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()


var _drawn_key: Array = []


func show_word(w: String) -> void:
	word = w
	word_alpha = 1.0


func hide_word() -> void:
	word = ""


func _draw() -> void:
	var screen := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var x0 := MARGIN
	var w := screen.x - MARGIN * 2.0
	var rect := Rect2(Vector2(x0, BAR_Y), Vector2(w, BAR_H))

	if endless and end_shown:
		_draw_end_screen(screen, font)
		return
	if endless and paused:
		_draw_pause_panel(screen, font)
		return
	if endless:
		_draw_run_hud(screen)
		if countin > 0.0:
			_draw_countin(screen, font)
	else:
		# glass trough
		draw_rect(Rect2(rect.position - Vector2(2, 2), rect.size + Vector2(4, 4)), Color(1, 1, 1, 0.05), true)
		draw_rect(rect, Color(1, 1, 1, 0.07), true)
		draw_rect(rect, Color(1, 1, 1, 0.22), false, 1.0)
		draw_line(rect.position + Vector2(1, 0), rect.position + Vector2(w - 1, 0), Color(1, 1, 1, 0.35), 1.0)

		# fill (cyan = where you are)
		var fw := w * clampf(fill, 0.0, 1.0)
		if fw > 0.0:
			draw_rect(Rect2(rect.position, Vector2(fw, BAR_H)), Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.55), true)
			draw_line(rect.position + Vector2(fw, -1), rect.position + Vector2(fw, BAR_H + 1), Palette.EDGE, 1.5)

		# checkpoint ticks (amber; a reached one is lit: wider and full)
		for i in ticks.size():
			var tx := x0 + w * float(ticks[i])
			var on := i < lit
			draw_line(Vector2(tx, BAR_Y - (5 if on else 3)), Vector2(tx, BAR_Y + BAR_H + (5 if on else 3)),
				Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 1.0 if on else 0.6), 3.0 if on else 1.5)

		# best marker (white)
		if best > 0.001:
			var bx := x0 + w * clampf(best, 0.0, 1.0)
			draw_line(Vector2(bx, BAR_Y - 4), Vector2(bx, BAR_Y + BAR_H + 4), Color(1, 1, 1, 0.9), 2.0)

	# demo word: a glass pill below the bar
	if word_alpha > 0.0 and (word != "" or word_alpha > 0.0):
		var label := word if word != "" else _last_word
		if label != "":
			var size := 26
			var tw: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var pw := tw + 56.0
			var ph := 44.0
			var c := Vector2(screen.x * 0.5, (HUD_Y + 72.0) if endless else (BAR_Y + BAR_H + 46.0))
			var prect := Rect2(c - Vector2(pw * 0.5, ph * 0.5), Vector2(pw, ph))
			var a := word_alpha
			glass_pill(self, prect, Palette.HAZ, a)   # dark glass: readable on the canyon's light sky
			draw_string(font, c + Vector2(-tw * 0.5, size * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
				Color(1, 1, 1, 0.92 * a))
	if word != "":
		_last_word = word

var _last_word := ""


# Lives (left of the distance) and the shield ring (right of it).
func _draw_run_hud(screen: Vector2) -> void:
	_draw_pause_button()
	var cx := screen.x * 0.5
	# The lives as clay hearts (2026-10-22): a lost one is a dent, and for
	# HEART_POP_S after the loss the heart squashes flat over its dent.
	for i in lives_max:
		var c := Vector2(cx - SIDE_GAP - i * HEART_GAP, HUD_Y)
		var on := i < lives
		clay_heart(self, c, HEART_SIZE, WorldPalette.HEART, 1.0, on)
		var pop: float = _heart_pop[i] if i < _heart_pop.size() else 0.0
		if not on and pop > 0.0:
			clay_heart(self, c, HEART_SIZE, WorldPalette.HEART, pop, true, 1.0 - pop)
	var rc := Vector2(cx + SIDE_GAP, HUD_Y)
	var r := 11.0 + 5.0 * shield_pop
	draw_circle(rc, r, Color(1, 1, 1, 0.05))
	draw_arc(rc, r, 0.0, TAU, 32, Color(1, 1, 1, 0.22), 1.5, true)
	var col: Color = Palette.EDGE if shield_armed else Palette.GOAL
	if shield_pop > 0.0:
		col = Palette.EDGE.lerp(Color.WHITE, shield_pop)
	var f := 1.0 if shield_armed else clampf(shield, 0.0, 1.0)
	if f > 0.0 or shield_pop > 0.0:
		draw_arc(rc, r, -PI * 0.5, -PI * 0.5 + TAU * maxf(f, shield_pop), 32, Color(col.r, col.g, col.b, 0.95), 3.0, true)
	if shield_armed:
		draw_circle(rc, 4.0, Color(col.r, col.g, col.b, 0.9))


# The pause pill: two bars in a glass square, top-left.
func _draw_pause_button() -> void:
	pause_rect = Rect2(PAUSE_AT, Vector2(PAUSE_SIZE, PAUSE_SIZE))
	if not show_pause:
		return
	_pill(pause_rect, Color(1, 1, 1), 0.7)
	var c := pause_rect.get_center()
	for dx in [-6.0, 6.0]:
		draw_rect(Rect2(c + Vector2(dx - 2.5, -11.0), Vector2(5.0, 22.0)), Color(1, 1, 1, 0.85), true)


# Near-opaque on purpose: a paused screen must not be a way to study the
# hazards at leisure (the end screen's dim is lighter; there is nothing
# left to study there).
func _draw_pause_panel(screen: Vector2, font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.93), true)
	var c := screen * 0.5
	_text(font, "PAUSED", c + Vector2(0, -110), 30, Color(1, 1, 1, 0.92))
	resume_rect = Rect2(c + Vector2(-150, -60), Vector2(300, 72))
	_pill(resume_rect, Palette.EDGE, 1.0)
	_text(font, "RESUME", resume_rect.get_center(), 28, Color(1, 1, 1, 0.95))
	restart_rect = Rect2(c + Vector2(-150, 26), Vector2(300, 66))
	_pill(restart_rect, Color(1, 1, 1), 0.8)
	_text(font, "RESTART", restart_rect.get_center(), 18, Color(1, 1, 1, 0.85))
	home_rect = Rect2(c + Vector2(-150, 106), Vector2(300, 66))
	_pill(home_rect, Color(1, 1, 1), 0.8)
	_text(font, "HOME", home_rect.get_center(), 18, Color(1, 1, 1, 0.85))


# 3 · 2 · 1, big, with the world visible behind it so what is coming can
# be seen coming.
#
# The digit is drawn at ONE font size (COUNTIN_SIZE, its largest) and
# scaled down to the size of the moment: every font size is its own glyph
# cache, and the old int(96 + 40 * frac) made 41 of them -- +160 MB on
# the phone after the first PAUSE -> RESUME (2026-10-06). Same sizes, same
# place: the scale is the old size over COUNTIN_SIZE, around the same point.
const COUNTIN_SIZE := 136

func _draw_countin(screen: Vector2, font: Font) -> void:
	var n := int(ceil(countin))
	var frac: float = countin - floorf(countin)   # 1 -> 0 within the second
	var k := float(int(96 + 40 * frac)) / COUNTIN_SIZE
	draw_set_transform(screen * 0.5 + Vector2(0, -20), 0.0, Vector2(k, k))
	_text(font, str(n), Vector2.ZERO, COUNTIN_SIZE, Color(1, 1, 1, 0.5 + 0.5 * frac))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func show_end(distance: String, best: String, new_best: bool) -> void:
	end_shown = true
	end_distance = distance
	end_best = best
	end_new_best = new_best


# THE GLASS PILL — the one copy. The end screen's buttons below and the
# main menu's (prototype/menu.gd) are the same button, so they are drawn
# by the same six lines: a soft outer glow, a white and a tinted fill, a
# white and a tinted outline, and the highlight along the top edge.
# `c` is whatever is drawing (any Node2D): a static so menu.gd can call
# it without owning a Hud.
# The canyon (2026-10-21, Milko: "all the buttons are barely visible"):
# the body is DARK glass now -- a deep plum fill under the tint -- so the
# white label reads on the light sky; the grey world's pill was 7 % white
# and 8 % tint, made for a near-black background. Outlines up with it.
const PILL_BODY := Color(0.13, 0.11, 0.22)

static func glass_pill(c: CanvasItem, rect: Rect2, tint: Color, a: float) -> void:
	c.draw_rect(Rect2(rect.position - Vector2(3, 3), rect.size + Vector2(6, 6)), Color(tint.r, tint.g, tint.b, 0.1 * a), true)
	c.draw_rect(rect, Color(PILL_BODY, 0.55 * a), true)
	c.draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.2 * a), true)
	c.draw_rect(rect, Color(1, 1, 1, 0.4 * a), false, 1.5)
	c.draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.7 * a), false, 1.0)
	c.draw_line(rect.position + Vector2(6, 1), rect.position + Vector2(rect.size.x - 6, 1), Color(1, 1, 1, 0.42 * a), 1.5)


# THE CLAY HEART (2026-10-22, step 4: "clay hearts for lives"). One life,
# drawn as a puffy lump of clay: the heart outline as rings shrinking to
# its middle, each ring shaded as a dome lit from the upper left (so it
# reads round, not flat), a darker lip under it like the buttons', a soft
# highlight on the left lobe and a few pressed-in specks. `full` false:
# the life is gone -- a flat, pale dent where the heart was. `squash` > 0
# squashes it flat and wide (the moment a life is lost).
const HEART_RINGS := [1.0, 0.82, 0.6, 0.34, 0.0]

static func clay_heart(c: CanvasItem, centre: Vector2, size: float, col: Color, a: float, full := true, squash := 0.0) -> void:
	var k := Vector2(1.0 + 0.35 * squash, 1.0 - 0.45 * squash) * size / 34.0
	var outline := _heart_points(32)
	if not full:
		var dent := PackedVector2Array()
		for p in outline:
			dent.append(centre + p * k)
		c.draw_colored_polygon(dent, Color(PILL_BODY, 0.28 * a))
		var ring := dent.duplicate()
		ring.append(dent[0])
		c.draw_polyline(ring, Color(1, 1, 1, 0.35 * a), 1.2, true)
		return
	# The lip: the same heart a little lower, in the clay's shadow.
	var lip := PackedVector2Array()
	for p in outline:
		lip.append(centre + (p + Vector2(0, 2.6)) * k)
	c.draw_colored_polygon(lip, Color(col.darkened(0.45), a))
	# The body: ring by ring, each band shaded as a dome. draw_primitive,
	# not draw_polygon: a band piece is drawn as given (a quad, or the
	# centre's triangle), never triangulated -- near the notch a piece can
	# fold over itself, which the triangulator refuses with an error.
	var light := Vector3(-0.55, -0.6, 0.6).normalized()
	for ri in HEART_RINGS.size() - 1:
		var s0: float = HEART_RINGS[ri]
		var s1: float = HEART_RINGS[ri + 1]
		for i in outline.size():
			var j := (i + 1) % outline.size()
			var corners := [[outline[i], s0], [outline[j], s0], [outline[j], s1], [outline[i], s1]]
			if s1 == 0.0:
				corners.pop_back()       # the middle: one point, a triangle
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			for q in corners:
				pts.append(centre + q[0] * q[1] * k)
				cols.append(_clay_shade(col, q[0], q[1], light, a))
			c.draw_primitive(pts, cols, PackedVector2Array())
	var edge := PackedVector2Array()
	for p in outline:
		edge.append(centre + p * k)
	edge.append(edge[0])
	c.draw_polyline(edge, Color(col.darkened(0.3), a), 1.0, true)
	# The highlight on the left lobe, and three specks pressed into the clay.
	c.draw_circle(centre + Vector2(-8.5, -6.0) * k, 3.4 * k.y, Color(1, 1, 1, 0.38 * a))
	c.draw_circle(centre + Vector2(-9.5, -7.0) * k, 1.5 * k.y, Color(1, 1, 1, 0.5 * a))
	for sp in [Vector2(5.0, -3.0), Vector2(-2.0, 6.0), Vector2(8.0, 4.0)]:
		c.draw_circle(centre + sp * k, 0.8 * k.y, Color(col.darkened(0.3), 0.6 * a))


# The heart's outline around its middle, ~34 units across (the classic
# heart curve, x = 16 sin^3 t, y = 13 cos t - 5 cos 2t - 2 cos 3t - cos 4t,
# turned screen-way up and centred on its bulk rather than its box).
static func _heart_points(n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var t := TAU * float(i) / n
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(x, -y - 2.5))
	return pts


# A point of the heart at ring `s` (1 = its edge, 0 = its middle), shaded
# as if the heart were a dome: the edge faces out, the middle faces you.
static func _clay_shade(col: Color, p: Vector2, s: float, light: Vector3, a: float) -> Color:
	var d := p.normalized() if p.length() > 0.001 else Vector2.ZERO
	var n := Vector3(d.x * s, d.y * s, sqrt(maxf(0.0, 1.0 - s * s * 0.85))).normalized()
	var lit := clampf(n.dot(light), 0.0, 1.0)
	return Color(col.darkened(0.32).lerp(col.lightened(0.22), lit), a)


# A distance the way the game writes it: "1 240 m". Thin groups of three,
# a space (never a comma: it reads the same in every country).
static func metres(m: int) -> String:
	var txt := str(m)
	var out := ""
	while txt.length() > 3:
		out = " " + txt.substr(txt.length() - 3) + out
		txt = txt.substr(0, txt.length() - 3)
	return txt + out + " m"


# Text centred on a point (the baseline maths is the fiddly part, so it
# lives in one place too).
static func centre_text(c: CanvasItem, font: Font, text: String, at: Vector2, size: int, col: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	c.draw_string(font, at - Vector2(w * 0.5, -size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _pill(rect: Rect2, tint: Color, a: float) -> void:
	glass_pill(self, rect, tint, a)


func _text(font: Font, text: String, c: Vector2, size: int, col: Color) -> void:
	centre_text(self, font, text, c, size, col)


# Every pill here is at least 66 units tall: 48 pt on the phone (the
# sum is in menu.gd, TAP_MIN), and the last one stops clear of the home
# indicator.
func _draw_end_screen(screen: Vector2, font: Font) -> void:
	var a := end_alpha
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.74 * a), true)
	var c := screen * 0.5
	_text(font, end_distance, c + Vector2(0, -104), 72, Color(1, 1, 1, 0.96 * a))
	if end_new_best:
		_text(font, "NEW BEST", c + Vector2(0, -48), 20, Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, a))
	else:
		_text(font, end_best, c + Vector2(0, -48), 18, Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.9 * a))
	if end_rank != "":
		_text(font, end_rank, c + Vector2(0, -20), 15, Color(Palette.EDGE.r, Palette.EDGE.g, Palette.EDGE.b, 0.95 * a))
	retry_rect = Rect2(c + Vector2(-150, 4), Vector2(300, 72))
	_pill(retry_rect, Palette.EDGE, a)
	_text(font, "RETRY", retry_rect.position + retry_rect.size * 0.5, 30, Color(1, 1, 1, 0.95 * a))
	menu_rect = Rect2(c + Vector2(-90, 90), Vector2(180, 66))
	_pill(menu_rect, Color(1, 1, 1), a * 0.8)
	_text(font, "MENU", menu_rect.position + menu_rect.size * 0.5, 18, Color(1, 1, 1, 0.8 * a))
	join_rect = Rect2()
	if end_join:
		join_rect = Rect2(c + Vector2(-170, 160), Vector2(340, 66))
		_pill(join_rect, Palette.GOAL, a * 0.9)
		_text(font, "JOIN TO POST YOUR DISTANCE", join_rect.position + join_rect.size * 0.5, 15,
			Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, 0.95 * a))
