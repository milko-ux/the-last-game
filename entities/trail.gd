class_name Trail
extends RefCounted
# ============================================================
# TRAIL — a short motion ribbon behind anything that moves.
#
# It just remembers where something has been, then draws those
# past positions as shrinking, fading dots. Because it draws
# through Palette.glow(), the trail blooms like the rest of the
# neon instead of needing its own particle material.
#
# Positions are sampled on a FIXED time interval, not once per
# frame, so the trail is the same length in seconds whether the
# phone is running at 30, 60 or 120fps.
# ============================================================

# Seconds between samples. Smaller = smoother but shorter reach.
const SAMPLE_DT := 0.028

var _points: Array[Vector2] = []
var _max: int
var _acc := 0.0


func _init(length: int = 9) -> void:
	_max = length


func clear() -> void:
	_points.clear()
	_acc = 0.0


func update(delta: float, p: Vector2) -> void:
	_acc += delta
	# `while`, not `if`, so a long frame drops the right number of
	# samples instead of stretching the trail.
	while _acc >= SAMPLE_DT:
		_acc -= SAMPLE_DT
		_points.append(p)
		while _points.size() > _max:
			_points.remove_at(0)


# Oldest points are smallest and faintest, so the ribbon reads as
# "came from there, going this way".
func draw_into(ci: CanvasItem, tint: Color, radius: float, height: float,
		glow_amount: float, peak_alpha: float = 0.45) -> void:
	var n := _points.size()
	if n < 2:
		return
	var col := Palette.glow(tint, glow_amount)
	for i in range(n - 1):
		var t := float(i) / float(n - 1)
		var p := Iso.to_screen(_points[i], height)
		# squared falloff keeps the tail subtle and the head punchy
		ci.draw_circle(p, radius * (0.2 + 0.65 * t),
			Color(col.r, col.g, col.b, peak_alpha * t * t))
