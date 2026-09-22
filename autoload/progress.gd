extends Node
# ============================================================
# PROGRESS — which difficulties are unlocked, and the rules of each.
#
# An autoload (a script Godot loads once at startup that any other
# script can reach). It's the single place that answers "how many
# lives does this mode give?" and "is Extreme unlocked yet?".
#
# The save file only records progression — no personal data — so
# this needs no GDPR consent. That question starts at Phase 3, when
# accounts and leaderboards arrive.
# ============================================================

const SAVE_PATH := "user://progress.save"

enum Diff { STANDARD, HARD, EXTREME }

# The rules for each tier, exactly as Milko specified them.
const RULES := {
	Diff.STANDARD: {
		"name": "STANDARD",
		"lives": 3,
		"checkpoints": true,
		"blurb": "3 lives. Checkpoints along the way.",
	},
	Diff.HARD: {
		"name": "HARD",
		"lives": 3,
		"checkpoints": false,
		"blurb": "3 lives. No checkpoints.",
	},
	Diff.EXTREME: {
		"name": "EXTREME",
		"lives": 1,
		"checkpoints": false,
		"blurb": "One life. No checkpoints. No mercy.",
	},
}

# Set once the player clears every level on Standard. Unlocks BOTH
# Hard and Extreme — Milko's wording was "unlock the difficulties".
var standard_cleared := false

# Which tier the player is currently playing.
var selected: Diff = Diff.STANDARD

# Phase R: furthest song time reached per level ("best" marker on the
# progress bar). Progression only, no personal data.
var best_song_time := {}
# Phase R (addendum 4): best score per level and which levels have been
# cleared (reaching a level's goal unlocks the next one).
var best_score := {}
var levels_cleared := {}


func _ready() -> void:
	load_progress()
	apply_sound()


func rules(d: Diff = selected) -> Dictionary:
	return RULES[d]


func lives_for(d: Diff = selected) -> int:
	return int(RULES[d]["lives"])


func checkpoints_allowed(d: Diff = selected) -> bool:
	return bool(RULES[d]["checkpoints"])


func tier_name(d: Diff = selected) -> String:
	return String(RULES[d]["name"])


func is_unlocked(d: Diff) -> bool:
	if d == Diff.STANDARD:
		return true
	return standard_cleared


# Called when a run clears the final level. Only clearing STANDARD
# unlocks anything.
func mark_cleared(d: Diff) -> void:
	if d == Diff.STANDARD and not standard_cleared:
		standard_cleared = true
		save_progress()


# ------------------------------------------------------------
# The endless run (Phase E brief 1). `graduated`: the player has crossed
# into lap 1 once, so lap 0 no longer teaches (no demo bars) and lives
# count from the start. One flag, no per-hazard bookkeeping.
# `best_distance`: metres, per SEASON_SEED (a new season starts at 0).
# Progression only, no personal data: still no consent needed.
# ------------------------------------------------------------
var graduated := false
var best_distance := {}
# The best run's facts, per season, kept for the leaderboard (Phase E
# section 8): laps, run_seconds, deaths, build, layout — the entry props a
# later cheat check needs — and `posted`, true once Talo has this best.
var best_run := {}
# The bots and tools turn this off: they must never write to the save file
# of whoever owns the machine.
var save_enabled := true

# ------------------------------------------------------------
# SETTINGS (Phase E section 7 — the menu's SETTINGS panel)
# ------------------------------------------------------------
# Sound off MUTES the master bus; it never stops the stream. BeatClock
# reads the song's playback position every frame to stay in sync, and a
# stopped stream has no position — a muted one keeps running silently.
var sound_on := true


func set_sound(on: bool) -> void:
	sound_on = on
	apply_sound()
	save_progress()


func apply_sound() -> void:
	AudioServer.set_bus_mute(0, not sound_on)


func set_graduated() -> void:
	if not graduated:
		graduated = true
		save_progress()


func best_distance_for(season: int) -> int:
	return int(best_distance.get(str(season), 0))


# Returns true when it is a new best (and saves it). `props` are the
# run's facts (see best_run); a new best is not yet posted.
func record_distance(season: int, metres: int, props: Dictionary = {}) -> bool:
	if metres <= best_distance_for(season):
		return false
	best_distance[str(season)] = metres
	if not props.is_empty():
		var run := props.duplicate()
		run["posted"] = false
		best_run[str(season)] = run
	save_progress()
	return true


func best_run_for(season: int) -> Dictionary:
	return best_run.get(str(season), {})


func best_posted(season: int) -> bool:
	return bool(best_run_for(season).get("posted", false))


func mark_best_posted(season: int) -> void:
	if best_run.has(str(season)):
		best_run[str(season)]["posted"] = true
		save_progress()


# On sign-out / account deletion: whoever signs in next has to post again.
func unpost_best() -> void:
	var changed := false
	for k in best_run:
		if bool(best_run[k].get("posted", false)):
			best_run[k]["posted"] = false
			changed = true
	if changed:
		save_progress()


func best_for(level: int) -> float:
	return float(best_song_time.get(str(level), 0.0))


# Records a new furthest point for a level and saves if it improved.
func record_best(level: int, song_time: float) -> void:
	if song_time > best_for(level):
		best_song_time[str(level)] = song_time
		save_progress()


func best_score_for(level: int) -> int:
	return int(best_score.get(str(level), 0))


func record_score(level: int, score: int) -> void:
	if score > best_score_for(level):
		best_score[str(level)] = score
		save_progress()


func is_level_cleared(level: int) -> bool:
	return bool(levels_cleared.get(str(level), false))


func mark_level_cleared(level: int) -> void:
	if not is_level_cleared(level):
		levels_cleared[str(level)] = true
		save_progress()


# DEV SWITCH (Phase R playtesting): true opens every level the level
# select can play (1-6) without clearing the one before. Set to false
# before anything ships. Does not touch the 2D game's difficulty unlocks.
const UNLOCK_ALL := true


# Level 1 is always open; level n opens when level n-1 has been cleared.
func is_level_unlocked(level: int) -> bool:
	return UNLOCK_ALL or level <= 1 or is_level_cleared(level - 1)


func save_progress() -> void:
	if not save_enabled:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify({"standard_cleared": standard_cleared, "best_song_time": best_song_time,
		"best_score": best_score, "levels_cleared": levels_cleared,
		"graduated": graduated, "best_distance": best_distance, "best_run": best_run, "sound_on": sound_on}))
	f.close()


func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		standard_cleared = bool(parsed.get("standard_cleared", false))
		var b = parsed.get("best_song_time", {})
		if b is Dictionary:
			best_song_time = b
		var sc = parsed.get("best_score", {})
		if sc is Dictionary:
			best_score = sc
		var lc = parsed.get("levels_cleared", {})
		if lc is Dictionary:
			levels_cleared = lc
		graduated = bool(parsed.get("graduated", false))
		var bd = parsed.get("best_distance", {})
		if bd is Dictionary:
			best_distance = bd
		var br = parsed.get("best_run", {})
		if br is Dictionary:
			best_run = br
		sound_on = bool(parsed.get("sound_on", true))
