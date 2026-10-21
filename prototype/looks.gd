extends RefCounted
const Mats := preload("res://prototype/flat_mats.gd")
const Props := preload("res://prototype/props/props.gd")
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
#   fog             the four fog stops (WorldPalette.BG_*), live globals
#   low_fog_max     the height fog's most (flat_mats.LOW_FOG_MAX)
#   pillar_tint     the three band tints (WorldPalette.*_PILLAR)
#   pillar_flatten  the bands' far flattening (props.PILLAR_FLATTEN)
#   pillar_side_fog the bands' haze by distance out (props.PILLAR_SIDE_FOG)
#
# "deep fog" (section 2) is the shipped look: the palette's own values
# (Milko's phone verdict, 2026-10-06; "light fog", the first try, was
# flatter than today and is gone).
# "today" is the look before section 2, kept in the palette as TODAY_*
# until section 3 is judged.
#
# Sections 3 and 5 of the brief add entries (tops in frame,
# the camera tests) and the keys they need. A value lives where it lives
# today; a variant only names the change.
#
# On the phone: on TAP TO START, a TAP on the frame readout (top right)
# = the next variant; a LONG PRESS = the probe (track_test.gd). The name
# is on the readout. The choice lasts until the app is closed.
# ============================================================

const LOOKS := [
	["deep fog", {}],
	["today", {"fog": WorldPalette.TODAY_FOG, "pillar_tint": WorldPalette.TODAY_PILLAR, "pillar_flatten": [0.3, 0.6, 0.92],
		"pillar_side_fog": [Vector3(16.0, 60.0, 0.85), Vector3(16.0, 60.0, 0.85), Vector3(16.0, 60.0, 0.85)], "vignette": 0.25}],
]

static var current := 0


static func name_of() -> String:
	return String(LOOKS[current][0])


static func next() -> void:
	current = (current + 1) % LOOKS.size()


# The web's ?look=<name> (dashes for spaces, e.g. ?look=deep-fog): the
# headless web shot's way to pick a variant. An unknown name changes nothing.
static func select(look: String) -> void:
	for i in LOOKS.size():
		if String(LOOKS[i][0]).replace(" ", "-") == look:
			current = i


static func _change(extra: Dictionary) -> Dictionary:
	var change: Dictionary = LOOKS[current][1].duplicate()
	change.merge(extra, true)
	return change


# The part of a look that needs no scene: the fog and the pillar bands.
# The menu calls this (its world uses the same shaders); apply() too.
static func apply_world(extra: Dictionary = {}) -> void:
	var change := _change(extra)
	Mats.publish_fog(change.get("fog", Mats.shipped_fog()), float(change.get("low_fog_max", Mats.LOW_FOG_MAX)))
	Props.set_pillar_look(change.get("pillar_tint", Props.shipped_pillar_tint()), change.get("pillar_flatten", Props.PILLAR_FLATTEN),
		change.get("pillar_side_fog", Props.PILLAR_SIDE_FOG))


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
