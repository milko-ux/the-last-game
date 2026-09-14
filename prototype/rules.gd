extends RefCounted
# ============================================================
# RULES — the Phase R field constants from the addendum, in one
# place. Anything spatial reads from here.
# ============================================================

const FIELD_WIDTH := 14.0            # x, seven 2-unit columns; movement is continuous
const COLS := 7
const ROWS := 4                      # tile-rows per bar, one per beat
const TILE := 2.0
const BAR_LENGTH := 8.0              # z per bar (BeatClock.BAR_UNITS)
const WINDOW_DEPTH := 2.5 * BAR_LENGTH
const PLAYER_SPEED_FACTOR := 2.2     # the player can outrun the scroll
# A pulse plate is lethal for this fraction of its beat (bright magenta),
# and "armed" (dark magenta) for the same fraction before it. The gap is
# what makes stepping on the beat physically possible.
const LETHAL_BEAT_FRACTION := 0.5
const PIT_MAX_Z := 3.0               # a pit deeper than this in z is not jumpable
const FALL_DEATH_Y := -3.0

const PATTERNS := ["checker", "row", "column_wave", "spiral"]


static func scroll_speed() -> float:
	return BeatClock.track_speed


static func player_speed() -> float:
	return PLAYER_SPEED_FACTOR * scroll_speed()


static func half_width() -> float:
	return FIELD_WIDTH * 0.5


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
			var q := 0
			if row < 2:
				q = 0 if col <= 3 else 1
			else:
				q = 2 if col > 3 else 3
			return q == k
	return false
