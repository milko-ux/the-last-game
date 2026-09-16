extends RefCounted
# ============================================================
# RULES — the Phase R field constants from the addendum, in one
# place. Anything spatial reads from here.
# ============================================================

const FIELD_WIDTH := 18.0            # x, nine 2-unit columns; movement is continuous
const COLS := 9
const ROWS := 4                      # tile-rows per bar, one per beat
const TILE := 2.0
const BAR_LENGTH := 8.0              # z per bar (BeatClock.BAR_UNITS)
const WINDOW_DEPTH := 2.5 * BAR_LENGTH
const PLAYER_SPEED_FACTOR := 2.2     # the player can outrun the scroll
# A pulse plate is lethal for this fraction of its beat (bright magenta),
# and "armed" (dark magenta) for the same fraction before it. The gap is
# what makes stepping on the beat physically possible.
# Addendum 2 tuning step (1): 0.5 -> 0.4 after the human-bot test.
const LETHAL_BEAT_FRACTION := 0.4
const PIT_MAX_Z := 3.0               # a pit deeper than this in z is not jumpable
const FALL_DEATH_Y := -3.0

# The window's death line sits this far in front of the scrolled back
# edge, so it is drawn on screen (one tile-row above the frame bottom
# with the addendum-2 camera) and never a surprise.
const BACK_EDGE_MARGIN := 3.6

# Which level this build plays. Level 1 is the taught curriculum: no
# lives, no death screen. Lives and the share screen begin at level 2
# (not built in this phase).
const LEVEL := 1

# Difficulty knobs per level (addendum 3 section 4). Levels 2-30 are meant
# to be rows in this table, not code. Printed at level start.
#   hazard_rate        how often hazards act: "bar" (once per bar, ~2 s at
#                      117 BPM), "half_bar" (beats 1 and 3) or "beat"
#   plate_coverage     fraction of a bar's 36 tiles that may be plates
#   plate_patterns     allowed plate patterns
#   gate_opening       gate opening width in world units (a tile is 2)
#   sweeper_gap        sweeper gap width in world units
#   types_per_bar      how many hazard types may share a bar
#   orbiter_pairs      the opposite-spin orbiter pair allowed?
const LEVELS := {
	1: {"hazard_rate": "bar", "plate_coverage": 0.12, "plate_patterns": ["row", "block"],
		"gate_opening": 5.0, "sweeper_gap": 5.0, "types_per_bar": 1, "orbiter_pairs": false},
}
# The beat-rate patterns are level 3+ material (each gets a demo bar there).
const PATTERNS := ["checker", "row", "column_wave", "spiral"]
const BEAT_PATTERNS := ["checker", "column_wave", "spiral"]


static func level() -> Dictionary:
	return LEVELS[LEVEL]


static func period_beats() -> int:
	match String(level()["hazard_rate"]):
		"bar":
			return 4
		"half_bar":
			return 2
	return 1


static func gate_gap() -> float:
	return float(level()["gate_opening"])


static func sweep_gap() -> float:
	return float(level()["sweeper_gap"])


static func knobs_line() -> String:
	var l := level()
	return "LEVEL %d knobs: hazard_rate=%s plate_coverage=%.2f plate_patterns=%s gate_opening=%.1f sweeper_gap=%.1f types_per_bar=%d orbiter_pairs=%s" % [
		LEVEL, l["hazard_rate"], l["plate_coverage"], str(l["plate_patterns"]), l["gate_opening"],
		l["sweeper_gap"], l["types_per_bar"], l["orbiter_pairs"]]

# Player hit box (feet at pos, HEIGHT tall).
const PLAYER_HALF_W := 0.4
const PLAYER_HEIGHT := 1.6
const PLAYER_HALF_D := 0.4
# Hazards further than this in z are not tested against the player.
const HIT_RANGE_Z := 12.0

const HazardMath := preload("res://prototype/hazard_math.gd")


static func scroll_speed() -> float:
	return BeatClock.track_speed


static func player_speed() -> float:
	return PLAYER_SPEED_FACTOR * scroll_speed()


static func half_width() -> float:
	return FIELD_WIDTH * 0.5


# The window's back edge line, as geometry (drawn on screen).
static func back_edge(z_back: float) -> float:
	return z_back + BACK_EDGE_MARGIN


# Before the first downbeat: hazards are inert, and so is the back edge.
# z_back is the window's scrolled back edge, so this is the same clock
# hazards_armed_at() reads.
static func intro_at(z_back: float) -> bool:
	return not BeatClock.hazards_armed_at(BeatClock.t_at(z_back))


# z below which the player is dead ("the beat caught you").
#
# During the intro the back edge does NOT kill (-INF): a first-time
# player who has not touched the controls yet must survive until the
# first downbeat. Instead the window carries them forward, see
# carry_line(). One rule for the runtime, the death log, the validator
# and the bots.
static func death_line(z_back: float) -> float:
	if intro_at(z_back):
		return -INF
	return back_edge(z_back)


# During the intro the window carries the player: they are never left
# behind this z (one tile ahead of where the death line will be when it
# arms, so an idle player is in front of it on the first downbeat).
# -INF once hazards are armed: from then on the back edge kills.
static func carry_line(z_back: float) -> float:
	if intro_at(z_back):
		return back_edge(z_back) + TILE
	return -INF


# The lowest z the player can occupy right now: the death line, or during
# the intro the carry line. Planning (validator, bots) uses this; the
# death check uses death_line().
static func min_z(z_back: float) -> float:
	return maxf(death_line(z_back), carry_line(z_back))


static func lives_enabled() -> bool:
	return LEVEL >= 2


static func col_x(col: int) -> float:
	return (col - (COLS - 1) * 0.5) * TILE


static func col_at(x: float) -> int:
	return int(floor(x / TILE + COLS * 0.5))


# Which tiles of a pattern are lethal on beat k (0..3) of the bar.
static func pattern_lethal(pattern: String, col: int, row: int, k: int) -> bool:
	if k < 0:
		return false
	match pattern:
		"checker":
			return (col + row + k) % 2 == 0
		"row":
			# front to back: the row nearest the front edge first
			return row == (ROWS - 1) - k
		"column_wave":
			return posmod(col - k, 4) == 0
		"spiral":
			# a quadrant block that rotates one step per beat
			var half := (COLS - 1) / 2
			var q := 0
			if row < 2:
				q = 0 if col <= half else 1
			else:
				q = 2 if col > half else 3
			return q == k
	return false


# The plate under (col, row) of a bar at hazard time t: 0 safe, 1 armed
# (dark magenta, fires next), 2 lethal (bright). The ONE plate rule: the
# field's colours, the death check, the validator and the bots all use it.
#
# Two kinds of plate bar:
#  - "plates": an explicit tile list (level 1's short `row` segment or
#    2x2 `block`). Armed for the whole period, lethal for the first
#    LETHAL_BEAT_FRACTION of a beat after every period start. Warns one
#    full period, fires on the downbeat.
#  - "pattern": the beat-rate patterns (checker, column_wave, spiral,
#    full-row wave), step k = period index, lethal for the first
#    LETHAL_BEAT_FRACTION of the period, armed the period before.
# Before the first downbeat, and on a demo bar, plates only ever show
# the warning colour.
static func plate_state(entry: Dictionary, col: int, row: int, t: float) -> int:
	if entry["plain_rows"].has(row):
		return 0
	var lethal_allowed: bool = BeatClock.hazards_armed_at(t) and not bool(entry.get("demo", false))
	var tiles: Array = entry.get("plates", [])
	if not tiles.is_empty():
		if not tiles.has([col, row]):
			return 0
		var idx := BeatClock.period_index_at(t)
		var firing: bool = idx >= 1 and (t - BeatClock.period_start(idx)) < LETHAL_BEAT_FRACTION * BeatClock.beat_interval
		if firing and lethal_allowed:
			return 2
		return 1
	var pattern := String(entry.get("pattern", "none"))
	if pattern == "none":
		return 0
	var idx := BeatClock.period_index_at(t)
	var k := posmod(idx - 1, 4)
	var frac: float = LETHAL_BEAT_FRACTION * BeatClock.beat_interval / BeatClock.period_s()
	var firing := pattern_lethal(pattern, col, row, k) and BeatClock.period_progress_at(t) < frac
	if firing:
		return 2 if lethal_allowed else 1
	if pattern_lethal(pattern, col, row, (k + 1) % 4):
		return 1
	return 0


# ============================================================
# DEATH RULES — the one place that decides whether the player is
# dead. The runtime, the death log, the fairness validator and the
# autoplayer all come here. Meshes are visual only.
# ============================================================

# How far the player can travel between one beat's safe tile and the
# next: only the non-lethal part of the beat is usable for the move.
static func reach_per_beat() -> float:
	return player_speed() * BeatClock.beat_interval * (1.0 - LETHAL_BEAT_FRACTION) + 0.4


static func player_box(pos: Vector3) -> AABB:
	return AABB(pos + Vector3(-PLAYER_HALF_W, 0.0, -PLAYER_HALF_D),
		Vector3(PLAYER_HALF_W * 2.0, PLAYER_HEIGHT, PLAYER_HALF_D * 2.0))


# Is standing at pos lethal at hazard time t? (Point query: plates and
# hazard volumes. Swept events — crossing a gate plane, the back edge,
# falling — are decided in death_cause.)
static func point_lethal(field, pos: Vector3, on_ground: bool, t: float) -> bool:
	if on_ground and field.tile_state_at(pos.x, pos.z, t) == field.TileState.LETHAL:
		return true
	var box := player_box(pos)
	for spec in field.plan["hazards"]:
		if absf(float(spec["z"]) - pos.z) > HIT_RANGE_Z:
			continue
		if String(spec["kind"]) == "gate":
			continue
		for b in HazardMath.boxes_at(spec, t):
			var bb: AABB = b
			if bb.intersects(box):
				return true
	return false


# Why the player is dead right now, or {} if alive.
# prev/pos: feet positions last frame and now. Returns
#   {"kind": String, "pos": Vector3 (of the killer)}
static func death_cause(field, prev: Vector3, pos: Vector3, on_ground: bool, z_back: float, t_prev: float, t: float) -> Dictionary:
	if pos.z < death_line(z_back):
		return {"kind": "back_edge", "pos": Vector3(pos.x, 0.0, death_line(z_back))}
	if pos.y < FALL_DEATH_Y:
		return {"kind": "fall", "pos": pos}
	if on_ground and field.tile_state_at(pos.x, pos.z, t) == field.TileState.LETHAL:
		return {"kind": "plate", "pos": field.tile_centre_at(pos.x, pos.z)}
	var box := player_box(pos)
	for spec in field.plan["hazards"]:
		if absf(float(spec["z"]) - pos.z) > HIT_RANGE_Z:
			continue
		if String(spec["kind"]) == "gate":
			# A gate is a zero-thickness plane in the rules: you die by
			# CROSSING it outside the opening, never by "being inside" it,
			# so the opening jumping can never catch you in the wall.
			if HazardMath.gate_crossed(spec, prev, pos, PLAYER_HALF_W, t_prev, t):
				return {"kind": "gate", "pos": Vector3(HazardMath.gate_opening_x(spec, t), 0.0, float(spec["z"]))}
			continue
		for b in HazardMath.boxes_at(spec, t):
			var bb: AABB = b
			if bb.intersects(box):
				return {"kind": String(spec["kind"]), "pos": bb.get_center()}
	return {}
