extends RefCounted
# ============================================================
# HAZARD MATH — the pure "where is it and is it lethal at time t"
# functions for every hazard type. Shared by the hazard nodes (to
# pose themselves) AND the fairness validator (to test layouts
# before the scene runs), so both always agree.
#
# Every hazard is periodic with the bar (or two bars) and locked
# to the downbeats, so it is live whenever it is on screen, not
# only during "its" bar. Nothing here keeps state.
# ============================================================

const Rules := preload("res://prototype/rules.gd")

const WALL_H := 3.0
const WALL_D := 0.6
const SWEEP_GAP := 3.0
const GATE_GAP := 4.0
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


# 0..1 progress through the current bar, locked to the real downbeats.
static func bar_cycle(t: float) -> float:
	var bar := BeatClock.bar_at(t)
	if bar < 1:
		return 0.0
	return BeatClock.bar_progress(bar, t)


# Continuous bar count (e.g. 12.37 = 37 % through bar 12). 0 in the intro.
static func bar_float(t: float) -> float:
	var bar := BeatClock.bar_at(t)
	if bar < 1:
		return 0.0
	return float(bar) + BeatClock.bar_progress(bar, t)


# --- Sweeper: a gap that crosses the field once per bar (ping-pong over
# two bars, so it never teleports). `phase` offsets consecutive sweepers.
static func sweeper_gap_x(spec: Dictionary, t: float) -> float:
	var travel := Rules.FIELD_WIDTH - SWEEP_GAP
	var u := fposmod(bar_float(t) * 0.5 + float(spec.get("phase", 0.0)), 1.0)
	var tri := 1.0 - absf(2.0 * u - 1.0)
	var x := -travel * 0.5 + travel * tri
	return x * float(spec.get("dir", 1))


# --- Gate: the opening jumps to a new seeded x on every downbeat.
static func gate_opening_x(spec: Dictionary, t: float) -> float:
	var bar := BeatClock.bar_at(t)
	var h := hash(Vector2i(int(spec.get("seed", 0)), bar))
	var span := Rules.FIELD_WIDTH - GATE_GAP
	return -span * 0.5 + span * float(h % 10007) / 10006.0


# --- Orbiter: one revolution per bar, phase locked to the downbeat.
static func orbiter_orb_pos(spec: Dictionary, t: float) -> Vector3:
	var a := TAU * bar_float(t) * float(spec.get("dir", 1)) + float(spec.get("phase", 0.0))
	return Vector3(float(spec["x"]) + ORBIT_R * cos(a), ORB_Y, float(spec["z"]) + ORBIT_R * sin(a))


# --- Slammer: hovers, drops on beat k of every bar, lifts by the next beat.
static func slammer_bottom(spec: Dictionary, t: float) -> float:
	var bar := BeatClock.bar_at(t)
	if bar < 1:
		return SLAM_HOVER
	var k := int(spec.get("beat", 0))
	var best := SLAM_HOVER
	for b in [bar, bar + 1]:
		if b > BeatClock.bar_count():
			continue
		var tb: float = BeatClock.bar_beats(b)[k]
		best = minf(best, _slam_curve(t - tb))
	return best


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


# World-space boxes that kill at time t. Empty while hazards are inert.
static func boxes_at(spec: Dictionary, t: float) -> Array:
	if not BeatClock.hazards_armed_at(t):
		return []
	var x := float(spec["x"])
	var z := float(spec["z"])
	var hw := Rules.half_width()
	match String(spec["kind"]):
		"sweeper":
			var gx := sweeper_gap_x(spec, t)
			return _walls_with_gap(gx, SWEEP_GAP, z, hw)
		"gate":
			var ox := gate_opening_x(spec, t)
			return _walls_with_gap(ox, GATE_GAP, z, hw)
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
