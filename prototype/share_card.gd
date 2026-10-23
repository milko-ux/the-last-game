extends Node2D
# ============================================================
# THE SHARE IMAGE (roadmap step 5, "a screenshot moment"): what SHARE on
# the end screen hands the phone's share sheet. A 1080 x 1350 portrait
# card (4:5 -- the tallest Instagram's feed shows uncropped; Messages and
# stories show it whole too):
#   the moment   the frame the run ended on, without the HUD: the card's
#                slice of it, centred on the creature, kept on the
#                graphics chip (freeze(), track_test.gd
#                _capture_death_frame), filling the card
#   the words    THE LAST GAME at the top; at the bottom, on a dark fade:
#                NEW BEST or the best in amber, the distance big, the
#                roast line, and the dare in amber
# Drawn in the HUD's bold, tracked lettering (hud.gd bold) WITHOUT its
# outline (_title below), rendered once in a SubViewport of its own, saved
# as a JPEG (user://share.jpg) the native share sheet reads
# (native/share/share.mm).
#
# THE PHONE FROZE ON THE FIRST VERSION (2026-10-23, the black box: SHARE
# took ~5 s, the song's clock lost 4 s, the phone got hot). All of it was
# main-thread work, timed on the Mac: reading the whole screen back to the
# CPU at death (138-156 ms: the HDR screen is 8 bytes a pixel, 24 MB), the
# card's lettering rasterised at 168 px with outlines (190-220 ms in one
# frame), the readback and the JPEG (40-160 ms). Now: the moment never
# leaves the graphics chip (freeze()); the lettering has no outline (a
# shadow from the same glyphs instead -- the outlines were the slow part;
# MSDF was tried and drew dark blobs in the bold glyphs); the JPEG is
# written on a worker thread. Only the card's own readback (1080 x 1350,
# 5.8 MB) is left on the main thread. And the frozen copy is only the
# card's slice of the screen (~944 x 1179 on the phone, not 2556 x 1179):
# the whole screen held the end screen at 227 MB of textures, 114 before.
# The JPEG is deleted once the share sheet has closed (track_test.gd).
# ============================================================

const Hud := preload("res://prototype/hud.gd")

const SIZE := Vector2i(1080, 1350)
const PATH := "user://share.jpg"
# The link the share text carries, once the game has one (a TestFlight
# public link, then the store's). "" = the text goes without a link.
const LINK := ""

var frame: Texture2D = null     # the moment (freeze()'s texture); null = the plain dark card
var facts := {}                 # distance, best, new_best, roast, rank (strings / bool)


# Waits until a frame has been DRAWN since the call (Engine's count of
# drawn frames has moved), at most DRAWN_CEILING_MS: a frame that never
# comes (nothing drawing) must not hang the end screen. Resumes on a
# process frame, never inside a render callback (CLAUDE.md).
const DRAWN_CEILING_MS := 500

static func drawn(host: Node) -> void:
	var n := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() <= n and Time.get_ticks_msec() - t0 < DRAWN_CEILING_MS:
		await host.get_tree().process_frame


# The card's slice of `source` (the screen's texture), kept: a viewport
# that draws it once and holds it, on the graphics chip. The slice has the
# card's shape, as tall as the screen (never taller than the card), across
# at `focus` (0..1, where the creature stood) as far as the edges allow.
# It draws on the NEXT frame, from the screen's texture as it is then
# (the last frame).
static func freeze(host: Node, source: Texture2D, focus: float) -> SubViewport:
	var src := source.get_size()
	var k := minf(1.0, float(SIZE.y) / src.y)
	var slice := Vector2(minf(src.x, src.y * SIZE.x / SIZE.y), src.y)
	var x := clampf(focus * src.x - slice.x * 0.5, 0.0, src.x - slice.x)
	var vp := SubViewport.new()
	vp.size = Vector2i((slice * k).round())
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var pic := TextureRect.new()
	pic.texture = source
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vp.add_child(pic)
	pic.position = Vector2(-x, 0.0) * k
	pic.size = src * k
	host.add_child(vp)
	return vp


# Renders the card for `facts` over `frame` and saves it. Returns the
# saved file's path, or "" when it could not be made. Takes two frames
# and the JPEG's time on a worker thread.
static func save(host: Node, frame_tex: Texture2D, run_facts: Dictionary) -> String:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var card: Node2D = load("res://prototype/share_card.gd").new()
	card.frame = frame_tex
	card.facts = run_facts
	vp.add_child(card)
	host.add_child(vp)
	await drawn(host)
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return ""
	var err := [FAILED]
	var task := WorkerThreadPool.add_task(func(): err[0] = img.save_jpg(PATH, 0.9))
	while not WorkerThreadPool.is_task_completed(task):
		await host.get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	return PATH if err[0] == OK else ""


# The words that go with the image.
static func text(distance: String) -> String:
	var t := "I ran %s in The Last Game. Can you beat it?" % distance
	return t if LINK == "" else t + " " + LINK


const INK := Color(0.07, 0.06, 0.13)      # the fades: the HUD glass's plum, darker

func _draw() -> void:
	var w := float(SIZE.x)
	var h := float(SIZE.y)
	draw_rect(Rect2(0, 0, w, h), Hud.PILL_BODY, true)
	if frame != null:
		# Cover the card (crop, never stretch); freeze() already cut the
		# slice to the card's shape, so this only scales it up.
		var fs := frame.get_size()
		var size := fs * maxf(w / fs.x, h / fs.y)
		draw_texture_rect(frame, Rect2((Vector2(w, h) - size) * 0.5, size), false)
	_fade(0.0, 300.0, 0.55, 0.0)       # under the name
	_fade(h * 0.4, h * 0.66, 0.0, 0.84)   # under the words: dark well before
	_fade(h * 0.66, h, 0.84, 0.96)        # the number starts

	var white := Color(1, 1, 1, 0.97)
	var gold := Color(Palette.GOAL, 1.0)
	var f := Hud.bold()
	_title(f, "THE LAST GAME", w * 0.5, 96.0, 34, 9.0, white)

	var y := h - 412.0
	if bool(facts.get("new_best", false)):
		_title(f, "NEW BEST", w * 0.5, y, 40, 10.0, gold)
	elif str(facts.get("best", "")) != "":
		_title(f, str(facts["best"]), w * 0.5, y, 30, 4.0, gold)
	_title(f, str(facts.get("distance", "")), w * 0.5, y + 170.0, 168, 4.0, white)
	var roast := str(facts.get("roast", ""))
	if roast != "":
		var size := 42
		while size > 26 and Hud.tracked_width(f, roast, size, 1.0) > w - 100.0:
			size -= 2
		_title(f, roast, w * 0.5, y + 250.0, size, 1.0, Color(1, 1, 1, 0.92))
	var rank := str(facts.get("rank", ""))
	if rank != "":
		_title(f, rank, w * 0.5, y + 310.0, 26, 3.0, Color(1, 1, 1, 0.75))
	_title(f, "CAN YOU BEAT IT?", w * 0.5, h - 44.0, 30, 6.0, gold)


# The HUD's tracked lettering (hud.gd tracked) without its outline: the
# words sit on the dark fade, and an outline is a second, slow
# rasterisation of every glyph at every size. A soft shadow instead, from
# the same glyphs (nothing new to rasterise).
func _title(f: Font, text: String, cx: float, y: float, size: int, track: float, col: Color) -> void:
	var x := cx - Hud.tracked_width(f, text, size, track) * 0.5
	var shade := Color(INK, 0.55 * col.a)
	for i in text.length():
		var ch := text[i]
		draw_string(f, Vector2(x, y + size * 0.04), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shade)
		draw_string(f, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + track


# A vertical fade of INK from alpha a0 at y0 to a1 at y1.
func _fade(y0: float, y1: float, a0: float, a1: float) -> void:
	var w := float(SIZE.x)
	draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
		PackedColorArray([Color(INK, a0), Color(INK, a0), Color(INK, a1), Color(INK, a1)]))
