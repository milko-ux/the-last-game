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
var pressed := ""           # the pause panel's / end screen's button held down (press.gd), "" = none
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
		end_rank, end_join, pressed, get_viewport_rect().size]
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

	# demo word: a dark-glass capsule below the bar (the kit's, so it
	# reads on the canyon's light sky like every other label)
	if word_alpha > 0.0 and (word != "" or word_alpha > 0.0):
		var label := word if word != "" else _last_word
		if label != "":
			var size := 24
			var pw: float = bold().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 64.0
			var ph := 48.0
			var c := Vector2(screen.x * 0.5, (HUD_Y + 72.0) if endless else (BAR_Y + BAR_H + 46.0))
			button(self, Rect2(c - Vector2(pw * 0.5, ph * 0.5), Vector2(pw, ph)), label, "glass", Btn.NORMAL, size, word_alpha)
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


# The pause button: two bars on a round glass button, top-left (the
# menu's round buttons). It acts on the touch, not the lift: in a run a
# pause must be instant.
func _draw_pause_button() -> void:
	pause_rect = Rect2(PAUSE_AT, Vector2(PAUSE_SIZE, PAUSE_SIZE))
	if not show_pause:
		return
	capsule_button(self, pause_rect, GLASS_TOP, GLASS_BOTTOM, 0.85)
	var c := pause_rect.get_center()
	for dx in [-6.0, 6.0]:
		draw_rect(Rect2(c + Vector2(dx - 3.0, -11.0), Vector2(6.0, 22.0)), Color(1, 1, 1, 0.95), true)


# The buttons on screen now, by name, for press.gd: the pause panel's or
# the end screen's.
func button_rects() -> Dictionary:
	if paused:
		return {"resume": resume_rect, "restart": restart_rect, "home": home_rect}
	if end_shown:
		var r := {"retry": retry_rect, "menu": menu_rect}
		if end_join:
			r["join"] = join_rect
		return r
	return {}


func _state(name: String) -> int:
	return Btn.PRESSED if pressed == name else Btn.NORMAL


# Near-opaque on purpose: a paused screen must not be a way to study the
# hazards at leisure (the end screen's dim is lighter; there is nothing
# left to study there).
# The menu's look (2026-10-23): a glass card, RESUME cyan, the rest glass.
func _draw_pause_panel(screen: Vector2, font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.93), true)
	var c := screen * 0.5
	card(self, Rect2(c + Vector2(-200, -176), Vector2(400, 362)))
	title(self, bold(), "PAUSED", c.x, c.y - 112.0, 30, 6.0, Color.WHITE)
	resume_rect = Rect2(c + Vector2(-150, -84), Vector2(300, 72))
	button(self, resume_rect, "RESUME", "go", _state("resume"), 26)
	restart_rect = Rect2(c + Vector2(-150, 6), Vector2(300, 66))
	button(self, restart_rect, "RESTART", "glass", _state("restart"), 18)
	home_rect = Rect2(c + Vector2(-150, 86), Vector2(300, 66))
	button(self, home_rect, "HOME", "glass", _state("home"), 18)


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


# The dark glass every button and card is made of (the canyon's lesson,
# 2026-10-21, Milko: "all the buttons are barely visible": on the light
# sky a label needs a dark body under it). The square glass pill that was
# drawn with it is gone (2026-10-23): every button is the kit's capsule.
const PILL_BODY := Color(0.13, 0.11, 0.22)


# ============================================================
# THE UI KIT (2026-10-22/23, roadmap step 4: "every screen looks
# designed"). One set of parts every screen draws with -- the menu, its
# settings sheet, the leaderboard, the account panel, the pause panel and
# the end screen -- so they read as one game:
#   capsule_button  the layered button (below), in three states
#   button          a capsule_button with its label, in a named STYLE
#   card            the rounded dark-glass panel a sheet sits on
#   title / tracked the white, tracked, outlined lettering of the menu
# The layout and buttons follow docs/concept/UI/ref-menu.png and
# ref-button-layers.png; the states follow ref-button-states.png. A
# button acts when the finger LIFTS on it (prototype/press.gd), so the
# pressed state is what the finger is holding down.
# ============================================================
enum Btn { NORMAL, PRESSED, DISABLED }
const PRESS_SINK := 4.0              # how far a pressed body sinks onto its lip
const GLASS_TOP := Color(0.36, 0.32, 0.5)
const GLASS_BOTTOM := Color(0.13, 0.11, 0.22)       # PILL_BODY
const INK := Color(0.05, 0.17, 0.2)                 # the label on a light body
# A STYLE is [body top, body bottom, label colour, glow].
#   go     cyan: the way forward (PLAY, RESUME, RETRY, a chosen option)
#   glass  dark glass, white label: everything else
#   goal   amber: joining the leaderboard
#   danger the lethal magenta: deleting the account
#   scarf  the scarf's sage: its teaser
static func style(name: String) -> Array:
	match name:
		"go":
			return [WorldPalette.SAFE.lightened(0.45), WorldPalette.SAFE.darkened(0.2), INK, 1.0]
		"goal":
			return [WorldPalette.GOAL.lightened(0.35), WorldPalette.GOAL.darkened(0.15), Color(0.2, 0.11, 0.0), 0.5]
		"danger":
			return [WorldPalette.LETHAL_LIVE.lightened(0.2), WorldPalette.LETHAL_LIVE.darkened(0.3), Color.WHITE, 0.0]
		"scarf":
			return [WorldPalette.SCARF.darkened(0.15), WorldPalette.SCARF.darkened(0.5), Color.WHITE, 0.0]
	return [GLASS_TOP, GLASS_BOTTOM, Color.WHITE, 0.0]


# THE CAPSULE BUTTON (2026-10-22). The layers of ref-button-layers.png,
# bottom up: a soft glow in the tint, a drop shadow, a darker lip under
# the body, the body (a vertical gradient), a gloss band over its top
# half, and a thin light along the top edge. The references are neon on
# black; on the canyon's light sky the drop shadow and the lip carry the
# depth and the glow is only a breath. A square rect makes a round button.
# PRESSED: the body sinks PRESS_SINK onto its lip, the glow and the gloss
# go down, the body darkens a touch. DISABLED: the body goes grey and
# half see-through, no glow.
static func capsule_button(c: CanvasItem, rect: Rect2, top: Color, bottom: Color, a: float, glow := 0.0, state := Btn.NORMAL) -> void:
	var gloss_a := 0.35
	if state == Btn.DISABLED:
		var grey := Color(0.55, 0.55, 0.6)
		top = top.lerp(grey, 0.7)
		bottom = bottom.lerp(grey.darkened(0.4), 0.7)
		a *= 0.55
		glow = 0.0
		gloss_a = 0.2
	for i in 3:
		var g := 4.0 + 5.0 * i
		if glow > 0.0:
			_round(c, rect.grow(g), -1.0, Color(top, glow * (0.12 - 0.035 * i) * a * (0.35 if state == Btn.PRESSED else 1.0)))
	_round(c, Rect2(rect.position + Vector2(0, 9), rect.size).grow(1.0), -1.0, Color(PILL_BODY, 0.22 * a))
	_round(c, Rect2(rect.position + Vector2(0, 5), rect.size), -1.0, Color(bottom.darkened(0.35), a))
	var body := rect
	if state == Btn.PRESSED:
		body.position.y += PRESS_SINK
		top = top.darkened(0.08)
		bottom = bottom.darkened(0.08)
		gloss_a = 0.18
	_round(c, body, -1.0, Color(top, a), Color(bottom, a))
	var r := minf(body.size.x, body.size.y) * 0.5
	var gloss := Rect2(body.position + Vector2(r * 0.4, body.size.y * 0.07), Vector2(body.size.x - r * 0.8, body.size.y * 0.42))
	_round(c, gloss, -1.0, Color(1, 1, 1, gloss_a * a), Color(1, 1, 1, 0.0))
	_top_light(c, body, -1.0, 0.7 * a)


# How far a button's face has moved (labels and icons move with it).
static func sink(state: int) -> Vector2:
	return Vector2(0, PRESS_SINK) if state == Btn.PRESSED else Vector2.ZERO


# A capsule_button in a STYLE with its label centred on it (bold).
static func button(c: CanvasItem, rect: Rect2, label: String, style_name := "glass", state := Btn.NORMAL, size := 16, a := 1.0) -> void:
	var st := style(style_name)
	capsule_button(c, rect, st[0], st[1], a, st[3], state)
	var ink: Color = st[2]
	var ia := a * (0.5 if state == Btn.DISABLED else 1.0)
	centre_text(c, bold(), label, rect.get_center() + sink(state) + Vector2(0, -1), size, Color(ink, ia))


# THE CARD: a sheet's rounded dark-glass panel -- a drop shadow, the
# glass body (the buttons' glass, a gradient), a faint rim and the light
# along its top edge.
const CARD_RADIUS := 26.0

static func card(c: CanvasItem, rect: Rect2, a := 1.0) -> void:
	_round(c, Rect2(rect.position + Vector2(0, 12), rect.size).grow(2.0), CARD_RADIUS, Color(PILL_BODY, 0.3 * a))
	_round(c, rect, CARD_RADIUS, Color(GLASS_TOP.darkened(0.25), 0.96 * a), Color(GLASS_BOTTOM.darkened(0.15), 0.97 * a))
	_outline(c, rect, CARD_RADIUS, Color(1, 1, 1, 0.12 * a))
	_top_light(c, rect, CARD_RADIUS, 0.45 * a)


# A filled rounded shape: radius -1 = a capsule (a stadium: half circles
# at the ends). Flat, or a vertical gradient when `bottom` is given; its
# outline is drawn antialiased in the same colours so the edge is not
# stair-stepped.
static func _round(c: CanvasItem, rect: Rect2, radius: float, top: Color, bottom = null) -> void:
	var pts := _round_points(rect, radius)
	var cols := PackedColorArray()
	var low: Color = top if bottom == null else bottom
	for p in pts:
		cols.append(top.lerp(low, clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)))
	c.draw_polygon(pts, cols)
	var ring := pts.duplicate()
	ring.append(pts[0])
	var ring_cols := cols.duplicate()
	ring_cols.append(cols[0])
	c.draw_polyline_colors(ring, ring_cols, 1.0, true)


static func _outline(c: CanvasItem, rect: Rect2, radius: float, col: Color) -> void:
	var ring := _round_points(rect, radius)
	ring.append(ring[0])
	c.draw_polyline(ring, col, 1.0, true)


# The thin light along a shape's top edge.
static func _top_light(c: CanvasItem, rect: Rect2, radius: float, a: float) -> void:
	var r := minf(rect.size.x, rect.size.y) * 0.5 if radius < 0.0 else radius
	var edge := PackedVector2Array()
	for p in _round_points(rect, radius):
		if p.y < rect.position.y + r * 0.65:
			edge.append(p)
	# The points run clockwise from the top-right corner, so the top edge
	# can arrive in two pieces (the top-left corner last): put it in order.
	var sorted := Array(edge)
	sorted.sort_custom(func(u, v): return u.x < v.x)
	if sorted.size() > 1:
		c.draw_polyline(PackedVector2Array(sorted), Color(1, 1, 1, a), 1.2, true)


# The outline of a rounded rectangle, clockwise from the top-right
# corner; radius -1 (or anything past half the short side) = a capsule.
static func _round_points(rect: Rect2, radius: float, seg := 7) -> PackedVector2Array:
	var half := minf(rect.size.x, rect.size.y) * 0.5
	var r := half if radius < 0.0 else minf(radius, half)
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(rect.end.x - r, rect.position.y + r), -PI * 0.5],    # top-right
		[Vector2(rect.end.x - r, rect.end.y - r), 0.0],               # bottom-right
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],     # bottom-left
		[Vector2(rect.position.x + r, rect.position.y + r), PI],      # top-left
	]
	for cn in corners:
		for i in seg + 1:
			var t: float = float(cn[1]) + PI * 0.5 * float(i) / seg
			pts.append(cn[0] + Vector2(cos(t), sin(t)) * r)
	return pts


# THE LETTERING. Titles and labels are the default font emboldened (a
# FontVariation, not a new font file), tracked letter by letter, with a
# soft dark outline and shadow so white reads on the canyon's light sky.
static var _bold_font: FontVariation = null

static func bold() -> Font:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = ThemeDB.fallback_font
		_bold_font.variation_embolden = 0.9
	return _bold_font


static func tracked(c: CanvasItem, font: Font, text: String, at: Vector2, size: int, track: float, col: Color) -> float:
	var x := at.x
	var shade := Color(PILL_BODY, 0.3 * col.a)
	var rim := Color(PILL_BODY, 0.22 * col.a)
	for i in text.length():
		var ch := text[i]
		c.draw_string_outline(font, Vector2(x, at.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, size / 8), rim)
		c.draw_string(font, Vector2(x, at.y + 1.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shade)
		c.draw_string(font, Vector2(x, at.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + track
	return maxf(0.0, x - at.x - track)


static func tracked_width(font: Font, text: String, size: int, track: float) -> float:
	var w := 0.0
	for i in text.length():
		w += font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + track
	return maxf(0.0, w - track)


static func title(c: CanvasItem, font: Font, text: String, cx: float, y: float, size: int, track: float, col: Color) -> void:
	tracked(c, font, text, Vector2(cx - tracked_width(font, text, size, track) * 0.5, y), size, track, col)


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


func _text(font: Font, text: String, c: Vector2, size: int, col: Color) -> void:
	centre_text(self, font, text, c, size, col)


# Every pill here is at least 66 units tall: 48 pt on the phone (the
# sum is in menu.gd, TAP_MIN), and the last one stops clear of the home
# indicator.
func _draw_end_screen(screen: Vector2, font: Font) -> void:
	var a := end_alpha
	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.04, 0.05, 0.08, 0.74 * a), true)
	var c := screen * 0.5
	# The menu's look (2026-10-23): the menu's lettering, RETRY cyan, MENU
	# glass, JOIN amber. The share screen (roadmap step 5) replaces this.
	title(self, bold(), end_distance, c.x, c.y - 80.0, 72, 3.0, Color(1, 1, 1, 0.97 * a))
	var gold := Color(Palette.GOAL.r, Palette.GOAL.g, Palette.GOAL.b, a)
	if end_new_best:
		title(self, bold(), "NEW BEST", c.x, c.y - 40.0, 22, 4.0, gold)
	else:
		title(self, bold(), end_best, c.x, c.y - 40.0, 18, 2.0, gold)
	if end_rank != "":
		title(self, bold(), end_rank, c.x, c.y - 14.0, 15, 1.0, Color(WorldPalette.SAFE.lightened(0.4), a))
	retry_rect = Rect2(c + Vector2(-150, 4), Vector2(300, 72))
	button(self, retry_rect, "RETRY", "go", _state("retry"), 28, a)
	menu_rect = Rect2(c + Vector2(-90, 90), Vector2(180, 66))
	button(self, menu_rect, "MENU", "glass", _state("menu"), 18, a)
	join_rect = Rect2()
	if end_join:
		join_rect = Rect2(c + Vector2(-180, 166), Vector2(360, 66))
		button(self, join_rect, "JOIN TO POST YOUR DISTANCE", "goal", _state("join"), 16, a)
