extends RefCounted
# ============================================================
# FRAME GOVERNOR (2026-10-21) — holds 60 fps on a phone that heats up by
# trading a little 3D sharpness for it, and gives it back when it can.
#
# Why: the probe (bars 9-12 of lap 0, a cool phone) read 16.7 ms on every
# row, and a few minutes of play later the same phone read 23 avg / 47.7
# worst (Milko's iPhone 14 Pro). The app is capped at 60 on a 120 Hz
# screen, so a frame that needs a hair over 16.7 ms is shown for 25: once
# a warm phone slows its GPU the run sits just over the edge, every
# frame. The GPU has no timer we can read and the phone has no thermal
# API (prototype/README.md, 2026-10-06), so the governor watches the one
# thing it can: how many frames came out slow.
#
# Every CHECK_S seconds of a run: more than SLOW_SHARE of the frames
# slow -> the 3D render scale steps down by STEP (never under MIN); no
# slow frame at all for RAISE_AFTER_S -> it steps back up (never over the
# shipped scale, track_test.RENDER_SCALE_MOBILE). A step down holds
# HOLD_S before the next decision, so a single hitch (a strip being
# built, a lap) never moves it. The HUD and the touch controls are 2D at
# full resolution whatever the 3D scale is.
#
# Not while the probe runs or a look sets its own scale (they measure a
# fixed scale), and only in a run (the menu is cheap).
# ============================================================

const SLOW_S := 0.0205          # a frame shown for longer than 1/60 s: on the 120 Hz screen the next step is 25 ms
const CHECK_S := 1.0
const SLOW_SHARE := 0.15
const STEP := 0.05
const MIN := 0.5
const HOLD_S := 2.0
const RAISE_AFTER_S := 12.0

var top := 0.75                 # the shipped scale; never above it
var scale := 0.75
var _frames := 0
var _slow := 0
var _t := 0.0
var _hold := 0.0
var _calm := 0.0


func _init(shipped: float) -> void:
	top = shipped
	scale = shipped


# Called every frame of a run with the frame's delta. Returns the scale
# to use (unchanged most frames).
func tick(delta: float) -> float:
	_frames += 1
	if delta > SLOW_S:
		_slow += 1
	_t += delta
	_hold = maxf(0.0, _hold - delta)
	if _t < CHECK_S:
		return scale
	var share := float(_slow) / maxf(_frames, 1.0)
	_calm = _calm + _t if _slow == 0 else 0.0
	if share > SLOW_SHARE and _hold <= 0.0 and scale > MIN + 0.001:
		scale = maxf(MIN, scale - STEP)
		_hold = HOLD_S
		_calm = 0.0
	elif _calm >= RAISE_AFTER_S and scale < top - 0.001:
		scale = minf(top, scale + STEP)
		_calm = 0.0
	_frames = 0
	_slow = 0
	_t = 0.0
	return scale
