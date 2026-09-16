extends RefCounted
# ============================================================
# HAZARD MATH — the pure "where is it and is it lethal at time t"
# functions for every hazard type. Shared by the hazard nodes (to
# pose themselves) AND the fairness validator (to test layouts
# before the scene runs), so both always agree.
#
# Every hazard is periodic with the level's hazard PERIOD (addendum
# 3: one bar on level 1, see BeatClock.period_beats) and locked to
# its downbeats, so it is live whenever it is on screen, not only
# during "its" bar. Nothing here keeps state.
# ============================================================

const Rules := preload("res://prototype/rules.gd")

const WALL_H := 3.0
const WALL_D := 0.6
# Sweeper gap / gate opening widths are level knobs: Rules.sweep_gap(),
# Rules.gate_gap().
const VOLLEY_R := 0.75          # orb radius; top at 1.5 so a jump clears it
const ORBIT_R := 3.0
const ORB_R := 0.6
const ORB_Y := 1.0
const PILLAR_R := 0.45
const SLAM_W := 1.9
const SLAM_H := 0.6
const SLAM_D := 1.9
const SLAM_HOVER := 3.0
const SLAM_DROP_S := 0.10
const SLAM_LETHAL_BELOW := 1.2


# Continuous period count (e.g. 12.37 = 37 % through period 12). Runs
# through the intro too (0, -1, ...) so hazards can rehearse there.
static func period_float(t: float) -> float:
	return BeatClock.period_float_at(t)


# The "thrown" family (volley, slammer) works on a two-period cycle:
# one period of warning, then it fires at the start of the next. Which
# periods fire is set per instance by `cycle` (0 or 1).
static func fires_in_period(spec: Dictionary, idx: int) -> bool:
	return idx >= 1 and posmod(idx + int(spec.get("cycle", 0)), 2) == 0


# --- Sweeper: a gap that crosses the field once per period (ping-pong
# over two periods, so it never teleports). `phase` offsets consecutive
# sweepers.
static func sweeper_gap_x(spec: Dictionary, t: float) -> float:
	var travel := Rules.FIELD_WIDTH - Rules.sweep_gap()
	var u := fposmod(period_float(t) * 0.5 + float(spec.get("phase", 0.0)), 1.0)
	var tri := 1.0 - absf(2.0 * u - 1.0)
	var x := -travel * 0.5 + travel * tri
	return x * float(spec.get("dir", 1))


# --- Gate: the opening jumps to a new seeded x at the start of every
# period (and rehearses that through the intro grid).
static func gate_opening_x(spec: Dictionary, t: float) -> float:
	var idx := BeatClock.period_index_at(t)
	var h := hash(Vector2i(int(spec.get("seed", 0)), idx))
	var span := Rules.FIELD_WIDTH - Rules.gate_gap()
	return -span * 0.5 + span * float(h % 10007) / 10006.0


# True if the segment prev->pos crossed the gate's plane outside its
# opening (player half-width included). Swept, so frame rate does not
# matter and the wall's visual thickness is irrelevant.
# If the opening jumped between the two frame times, the crossing counts
# as safe when it fits EITHER opening: the jump can never catch a player
# who was already in the old opening.
static func gate_crossed(spec: Dictionary, prev: Vector3, pos: Vector3, half_w: float, t_prev: float, t: float) -> bool:
	if not BeatClock.hazards_armed_at(t) or bool(spec.get("demo", false)):
		return false
	var z := float(spec["z"])
	var a := prev.z - z
	var b := pos.z - z
	if a == b or (a < 0.0) == (b < 0.0):
		return false
	var u := a / (a - b)
	var x := lerpf(prev.x, pos.x, u)
	for ot in [t, t_prev]:
		if absf(x - gate_opening_x(spec, ot)) + half_w <= Rules.gate_gap() * 0.5:
			return false
	return true


# --- Orbiter: one revolution per period, phase locked to its start.
static func orbiter_orb_pos(spec: Dictionary, t: float) -> Vector3:
	var a := TAU * period_float(t) * float(spec.get("dir", 1)) + float(spec.get("phase", 0.0))
	return Vector3(float(spec["x"]) + ORBIT_R * cos(a), ORB_Y, float(spec["z"]) + ORBIT_R * sin(a))


# --- Slammer: hovers, drops at the start of its firing periods (see
# fires_in_period), lifts by the next beat. Hot (bright) for the whole
# period before a drop.
static func slammer_bottom(spec: Dictionary, t: float) -> float:
	var idx := BeatClock.period_index_at(t)
	if idx < 0:
		return SLAM_HOVER
	var best := SLAM_HOVER
	for i in [idx, idx + 1]:
		if fires_in_period(spec, i):
			best = minf(best, _slam_curve(t - BeatClock.period_start(i)))
	return best


static func slammer_hot(spec: Dictionary, t: float) -> bool:
	var idx := BeatClock.period_index_at(t)
	if fires_in_period(spec, idx + 1):
		return true
	return fires_in_period(spec, idx) and t - BeatClock.period_start(idx) < BeatClock.beat_interval


# --- Volley: an orb fired from one side of the field along one tile-row
# (constant z), across the full width in exactly one period. The period
# before it fires is the warning (a line along the row, a muzzle block
# at the edge it comes from). Lethal only on contact with the orb.
# Returns the orb's x, or null while nothing is in flight.
static func volley_orb_x(spec: Dictionary, t: float) -> Variant:
	var idx := BeatClock.period_index_at(t)
	if not fires_in_period(spec, idx):
		return null
	var d := float(spec.get("dir", 1))
	var reach := Rules.half_width() + VOLLEY_R
	return lerpf(-d * reach, d * reach, BeatClock.period_progress_at(t))


static func volley_warning(spec: Dictionary, t: float) -> bool:
	return fires_in_period(spec, BeatClock.period_index_at(t) + 1)


static func _slam_curve(dt: float) -> float:
	var beat := BeatClock.beat_interval
	if dt < -SLAM_DROP_S:
		return SLAM_HOVER
	if dt < 0.0:
		var k := (dt + SLAM_DROP_S) / SLAM_DROP_S
		return SLAM_HOVER * (1.0 - k * k)
	if dt < beat * 0.5:
		return 0.0
	if dt < beat:
		var k := (dt - beat * 0.5) / (beat * 0.5)
		return SLAM_HOVER * k * k
	return SLAM_HOVER


# World-space boxes that kill at time t. Empty while hazards are inert,
# and always empty for a demo hazard (it shows, it never kills).
static func boxes_at(spec: Dictionary, t: float) -> Array:
	if not BeatClock.hazards_armed_at(t) or bool(spec.get("demo", false)):
		return []
	return shape_boxes_at(spec, t)


# The hazard's boxes regardless of arming / demo state (for visuals and
# the eye).
static func shape_boxes_at(spec: Dictionary, t: float) -> Array:
	var x := float(spec["x"])
	var z := float(spec["z"])
	var hw := Rules.half_width()
	match String(spec["kind"]):
		"sweeper":
			var gx := sweeper_gap_x(spec, t)
			return _walls_with_gap(gx, Rules.sweep_gap(), z, hw)
		"gate":
			var ox := gate_opening_x(spec, t)
			return _walls_with_gap(ox, Rules.gate_gap(), z, hw)
		"volley":
			var vx: Variant = volley_orb_x(spec, t)
			if vx == null:
				return []
			return [AABB(Vector3(float(vx) - VOLLEY_R, 0.0, z - VOLLEY_R), Vector3(VOLLEY_R, VOLLEY_R, VOLLEY_R) * 2.0)]
		"orbiter":
			var p := orbiter_orb_pos(spec, t)
			return [AABB(p - Vector3(ORB_R, ORB_R, ORB_R), Vector3(ORB_R, ORB_R, ORB_R) * 2.0)]
		"slammer":
			var bottom := slammer_bottom(spec, t)
			if bottom >= SLAM_LETHAL_BELOW:
				return []
			return [AABB(Vector3(x - SLAM_W * 0.5, bottom, z - SLAM_D * 0.5), Vector3(SLAM_W, SLAM_H, SLAM_D))]
	return []


static func _walls_with_gap(gx: float, gap: float, z: float, hw: float) -> Array:
	var out := []
	var lw := (gx - gap * 0.5) + hw
	var rw := hw - (gx + gap * 0.5)
	if lw > 0.01:
		out.append(AABB(Vector3(-hw, 0.0, z - WALL_D * 0.5), Vector3(lw, WALL_H, WALL_D)))
	if rw > 0.01:
		out.append(AABB(Vector3(hw - rw, 0.0, z - WALL_D * 0.5), Vector3(rw, WALL_H, WALL_D)))
	return out
