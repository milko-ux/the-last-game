extends RefCounted
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
#                                               (track_test.FINISH_DEFAULT)
#   scale     the 3D render scale (track_test.RENDER_SCALE_MOBILE)
#   pillars   fraction of the pillars kept (monoliths.gd), 1.0 = all
#   slab      the slab's thickness (field.THICK)
#
# Sections 2, 3 and 5 of the brief add entries (light fog, tops in frame,
# the camera tests) and the keys they need. A value lives where it lives
# today; a variant only names the change.
#
# On the phone: on TAP TO START, a TAP on the frame readout (top right)
# = the next variant; a LONG PRESS = the probe (track_test.gd). The name
# is on the readout. The choice lasts until the app is closed.
# ============================================================

const LOOKS := [
	["today", {}],
]

static var current := 0


static func name_of() -> String:
	return String(LOOKS[current][0])


static func next() -> void:
	current = (current + 1) % LOOKS.size()


# The shipped look, then the current variant, then `extra` (a probe setup,
# or the run's dev URL switches) on top.
static func apply(scene: Node, extra: Dictionary = {}) -> void:
	var change: Dictionary = LOOKS[current][1].duplicate()
	change.merge(extra, true)
	scene.finish = scene.FINISH_DEFAULT.duplicate()
	for k in ["tonemap", "glow", "vignette", "grain", "msaa"]:
		if change.has(k):
			scene.finish[k] = change[k]
	scene.apply_finish()
	scene.apply_render_scale(float(change.get("scale", -1.0)))
	scene.field.set_pillar_density(float(change.get("pillars", 1.0)))
	scene.field.set_slab_thickness(float(change.get("slab", scene.field.THICK)))
