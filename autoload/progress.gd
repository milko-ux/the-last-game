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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify({"standard_cleared": standard_cleared, "best_song_time": best_song_time,
		"best_score": best_score, "levels_cleared": levels_cleared}))
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
