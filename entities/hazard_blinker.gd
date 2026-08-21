extends Hazard
# ============================================================
# BLINKER — a hazard that sits still and pulses ON and OFF.
#
# It kills only while lit. That turns a corridor into a timing
# puzzle: watch the rhythm, walk through on the beat. Several
# blinkers with different "phase" values alternate with each
# other, which is where it gets nasty.
#
# Low, so a well-timed jump also clears it.
# ============================================================

var period := 2.0    # seconds for a full on+off cycle
var duty := 0.5      # fraction of that cycle spent lethal
var phase := 0.0     # 0..1 offset, to stagger several blinkers

var _lit := true


func _configure(data: Dictionary) -> void:
	world_pos = Iso.cell_center(int(data["at"].x), int(data["at"].y))
	period = maxf(0.2, float(data.get("period", 2.0)))
	duty = clampf(float(data.get("duty", 0.5)), 0.05, 0.95)
	phase = float(data.get("phase", 0.0))


func _move(_delta: float, elapsed: float, _player_pos: Vector2) -> void:
	_lit = fmod(elapsed / period + phase, 1.0) < duty


func hits(player_pos: Vector2, player_r: float, player_airborne: bool) -> bool:
	if not _lit:
		return false
	return super(player_pos, player_r, player_airborne)


func _draw() -> void:
	var sp := Iso.to_screen(world_pos, 10.0)
	if _lit:
		_draw_shadow()
		draw_circle(sp, RADIUS + 7.0, Color(Palette.HAZ.r, Palette.HAZ.g, Palette.HAZ.b, 0.22))
		draw_circle(sp, RADIUS, Palette.glow(Palette.HAZ, 1.3))
		draw_circle(sp - Vector2(3, 3), RADIUS * 0.35, Color(1, 1, 1, 0.55))
	else:
		# Dormant: still visible, so the player can read the rhythm and
		# plan a route rather than being ambushed by something invisible.
		draw_arc(sp, RADIUS, 0.0, TAU, 28,
			Color(Palette.HAZ.r, Palette.HAZ.g, Palette.HAZ.b, 0.30), 1.5)
		draw_circle(sp, RADIUS * 0.25,
			Color(Palette.HAZ.r, Palette.HAZ.g, Palette.HAZ.b, 0.18))
