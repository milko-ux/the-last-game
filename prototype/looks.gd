extends RefCounted
const TimeOfDay := preload("res://prototype/time_of_day.gd")
# ============================================================
# LOOKS (step 3 brief 1 section 1, 2026-10-05) — named look variants for
# comparing before / after on the phone. DEBUG BUILDS ONLY: the switch is
# the frame readout (FrameMeter.enabled()), which a release never has.
#
# A variant is a small set of overrides on the shipped look, the same
# kind of change the probe's setups are (probe.gd): ONE mechanism. The
# probe applies its setup ON TOP of the current look, so its table
# measures whichever variant is on.
#
#   tonemap · glow · vignette · grain · msaa    the finishing layer
#                                               (track_test.FINISH_DEFAULT);
#                                               vignette may be an amount
#                                               at the corners (finish.gd)
#   scale     the 3D render scale (track_test.RENDER_SCALE_MOBILE)
#   pillars   fraction of the pillars kept (monoliths.gd), 1.0 = all
#   slab      the slab's thickness (field.THICK)
#   time      hold one time of day (time_of_day.gd): "sunset", "night"
#   scarf     true: the creature wears the 1 km scarf (scarf.gd) earned or not
#
# "canyon" is the shipped look: the palette's own values (step 3 brief 2,
# 2026-10-21; it replaced brief 1's grey "deep fog" and "today"). Brief
# 2's camera test ("low camera") won and is the camera now. A value lives where it lives
# today; a variant only names the change.
#
# On the phone: on TAP TO START, a TAP on the frame readout (top right)
# = the next variant; a LONG PRESS = the probe (track_test.gd). The name
# is on the readout. The choice lasts until the app is closed.
# ============================================================

const LOOKS := [
	["canyon", {}],
	# The time of day held still, to judge it without running to it.
	["sunset", {"time": "sunset"}],
	["night", {"time": "night"}],
	["scarf", {"scarf": true}],
]

static var current := 0


static func name_of() -> String:
	return String(LOOKS[current][0])


static func next() -> void:
	current = (current + 1) % LOOKS.size()


# The web's ?look=<name> (dashes for spaces, e.g. ?look=canyon): the
# headless web shot's way to pick a variant. An unknown name changes nothing.
static func select(look: String) -> void:
	for i in LOOKS.size():
		if String(LOOKS[i][0]).replace(" ", "-") == look:
			current = i


static func _change(extra: Dictionary) -> Dictionary:
	var change: Dictionary = LOOKS[current][1].duplicate()
	change.merge(extra, true)
	return change


# The part of a look that needs no scene: the time of day (its fog, sky
# and light). The menu calls this (its world uses the same shaders);
# apply() too.
static func apply_world(extra: Dictionary = {}) -> void:
	var change := _change(extra)
	TimeOfDay.forced = String(change.get("time", ""))
	TimeOfDay.reset()
	TimeOfDay.update(0.0)


# The shipped look, then the current variant, then `extra` (a probe setup,
# or the run's dev URL switches) on top.
static func apply(scene: Node, extra: Dictionary = {}) -> void:
	var change := _change(extra)
	apply_world(extra)
	scene.finish = scene.FINISH_DEFAULT.duplicate()
	for k in ["tonemap", "glow", "vignette", "grain", "msaa"]:
		if change.has(k):
			scene.finish[k] = change[k]
	scene.apply_finish()
	scene.apply_render_scale(float(change.get("scale", -1.0)))
	scene.field.set_pillar_density(float(change.get("pillars", 1.0)))
	scene.field.set_slab_thickness(float(change.get("slab", scene.field.THICK)))
	scene.player.creature.wear_scarf(bool(change.get("scarf", false)) or Progress.scarf_unlocked)
