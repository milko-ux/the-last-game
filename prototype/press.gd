extends RefCounted
# ============================================================
# PRESS (2026-10-23, roadmap step 4: pressed / disabled states). A
# button acts when the finger LIFTS on it, as a phone's buttons do: the
# finger goes down on a button and the button shows PRESSED (Hud.Btn,
# the body sinks onto its lip); slide off and it pops back up and nothing
# happens; lift on it and it acts. The click sounds and a light haptic
# tick plays on the way down, so the touch is answered at once. scale()
# gives the drawing its squash while held and its spring after the tap
# (2026-10-23, the motion pass).
#
# One per screen (the menu, its settings sheet, the leaderboard, the
# account panel, the run's pause and end screens). The screen feeds it
# every input event with its tap rects ({name: Rect2}, the same dictionary
# it draws with) and acts on the name feed() returns. Real touches and a
# real mouse only: the mouse events a phone synthesises from a touch
# (device -1) would press every button twice.
# ============================================================

const Hud := preload("res://prototype/hud.gd")

var key := ""               # the button held down now, "" = none
var inside := false         # the finger is still on it
var _id := -100
var _up_ms := {}            # name -> when it was tapped (the spring back)
const SQUASH := 0.95
const SPRING_MS := 280.0
const HAPTIC_MS := 10


# Feeds one event. Returns the name of a button released on (a tap), or "".
func feed(event: InputEvent, rects: Dictionary) -> String:
	var pos = null
	var down := false
	var id := 0
	if event is InputEventScreenTouch:
		pos = event.position
		down = event.pressed
		id = event.index
	elif event is InputEventScreenDrag:
		if key != "" and event.index == _id:
			inside = rects.has(key) and (rects[key] as Rect2).has_point(event.position)
		return ""
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		pos = event.position
		down = event.pressed
		id = -1
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if key != "" and _id == -1:
			inside = rects.has(key) and (rects[key] as Rect2).has_point(event.position)
		return ""
	if pos == null:
		return ""
	if down:
		key = hit(rects, pos)
		inside = key != ""
		_id = id
		if key != "":
			Sfx.play("tap")
			Input.vibrate_handheld(HAPTIC_MS, 0.5)
		return ""
	if key == "" or id != _id:
		return ""
	var k := key
	key = ""
	_id = -100
	if rects.has(k) and (rects[k] as Rect2).has_point(pos):
		_up_ms[k] = Time.get_ticks_msec()
		return k
	return ""


# Which button is under `pos`, or "".
static func hit(rects: Dictionary, pos: Vector2) -> String:
	for k in rects:
		if (rects[k] as Rect2).has_point(pos):
			return str(k)
	return ""


# Is this event a finger (or the real mouse) going down? For the screens
# that also react to a tap that lands on no button.
static func is_down(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
		and event.device != InputEvent.DEVICE_ID_EMULATION


# How to draw button `name` now. `enabled` false = DISABLED.
func state(name: String, enabled := true) -> int:
	if not enabled:
		return Hud.Btn.DISABLED
	return Hud.Btn.PRESSED if name == key and inside else Hud.Btn.NORMAL


# How big to draw button `name` now: squashed while held, a small
# overshoot just after it was tapped, 1 otherwise.
func scale(name: String) -> float:
	if name == key and inside:
		return SQUASH
	if _up_ms.has(name):
		var u := float(Time.get_ticks_msec() - int(_up_ms[name])) / SPRING_MS
		if u < 1.0:
			return 1.0 + 0.06 * sin(u * PI) * (1.0 - u)
		_up_ms.erase(name)
	return 1.0


func clear() -> void:
	key = ""
	inside = false
	_id = -100
