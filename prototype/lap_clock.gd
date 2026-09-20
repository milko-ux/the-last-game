extends RefCounted
# ============================================================
# LAP CLOCK — one lap of the endless run, seen as if it were a level.
#
# The generator (placement.gd), the validator (fairness.gd) and the field
# (field.gd) were written for "a song with N bars": they ask a clock for
# bar_count(), bar_start(bar), the beat list, z_at(t). This object answers
# those questions for LAP `lap` of the looped song: bars are numbered
# 1..72 inside the lap, but every TIME it hands out is run time (the
# lap's bar 1 starts at loop start + lap x loop length) and so every z is
# absolute. That is what lets a lap be generated, validated and built on
# its own, with the code the levels use, unchanged.
#
# The beat list covers the lap plus one beat before it (the validator
# looks one beat back) and three bars after it (the window still holds the
# lap's last bars while the back edge is already in the next lap, whose
# first bar is always plain).
# ============================================================

const TRAIL_BEATS := 12

var lap := 0
var base: Node                      # the BeatClock autoload
var beats := PackedFloat64Array()
var first_bar_beat := 1
var beat_interval := 0.5
var track_speed := 4.0
var start_offset := 0.0
var bar_offset := 0                 # run bar = bar_offset + bar


func _init(clock: Node, lap_index: int) -> void:
	base = clock
	lap = lap_index
	beat_interval = clock.beat_interval
	track_speed = clock.track_speed
	start_offset = clock.start_offset
	bar_offset = lap * clock.loop_bars
	var g0: int = clock.loop_first_beat + lap * clock.loop_beats
	if g0 >= 1:
		beats.append(clock.beat_time(g0 - 1))
	else:
		beats.append(clock.beat_time(g0) - clock.beat_interval)
	for g in range(g0, g0 + clock.loop_beats + TRAIL_BEATS):
		beats.append(clock.beat_time(g))


# The run-wide index of this lap's first beat (the bots' path starts there).
func global_first_beat() -> int:
	return base.loop_first_beat + lap * base.loop_beats


func bar_count() -> int:
	return base.loop_bars


func bar_start(bar: int) -> float:
	return base.bar_start(bar_offset + bar)


func bar_end(bar: int) -> float:
	return base.bar_start(bar_offset + bar + 1)


func bar_energy(bar: int) -> float:
	return base.bar_energy(bar_offset + bar)


# Lap-local bar number (the validator's messages name it; the re-roll
# logic reads it back).
func bar_at(t: float) -> int:
	return base.bar_at(t) - bar_offset


func beat_in_bar_at(t: float) -> int:
	return base.beat_in_bar_at(t)


func hazards_armed_at(t: float) -> bool:
	return base.hazards_armed_at(t)


func z_at(t: float) -> float:
	return base.z_at(t)


func t_at(z: float) -> float:
	return base.t_at(z)
