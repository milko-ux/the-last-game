extends Node
# ============================================================
# PROFILE — who the player is, before they have an account.
#
# Guest-first: a name is handed out the moment the game starts, so
# nobody is ever staring at an empty text field wondering what to
# type. They can reroll it or write their own, and it's saved
# locally so it sticks between sessions.
#
# `claimed` stays false until Phase 3, when an account can actually
# be registered with Talo. Until then this is purely a local
# nickname — no personal data, so no consent handling needed yet.
# ============================================================

const SAVE_PATH := "user://profile.save"
const MAX_LENGTH := 16
const MIN_LENGTH := 2

# Two halves that read like the game looks: cold, neon, a bit menacing.
const FIRST := [
	"Neon", "Void", "Ghost", "Chrome", "Static", "Pulse", "Vapor", "Ember",
	"Cobalt", "Nova", "Rift", "Echo", "Onyx", "Prism", "Zero", "Hex",
	"Flux", "Drift", "Cinder", "Halo", "Glitch", "Solar", "Iron", "Dusk",
]
const SECOND := [
	"Wraith", "Runner", "Circuit", "Dodger", "Vector", "Spectre", "Drifter",
	"Blade", "Signal", "Phantom", "Rider", "Cipher", "Nomad", "Shard",
	"Warden", "Comet", "Husk", "Relay", "Falcon", "Ronin", "Pilot", "Widow",
]

signal username_changed(name: String)

var username := ""
# Set once a real account exists (Phase 3). Guests are unclaimed.
var claimed := false


func _ready() -> void:
	load_profile()
	if username.is_empty():
		username = generate()
		save_profile()


# A fresh random name. Never returns the current one, so hitting
# reroll always visibly does something.
func generate() -> String:
	var candidate := username
	var guard := 0
	while candidate == username and guard < 12:
		candidate = FIRST[randi() % FIRST.size()] + SECOND[randi() % SECOND.size()]
		guard += 1
	return candidate


func reroll() -> void:
	username = generate()
	save_profile()
	username_changed.emit(username)


# Returns true if the name was accepted. Rejects blank/too-short input
# so the player can't end up nameless by clearing the field.
func set_username(raw: String) -> bool:
	var clean := _sanitise(raw)
	if clean.length() < MIN_LENGTH:
		return false
	username = clean
	save_profile()
	username_changed.emit(username)
	return true


# Keeps it to something a leaderboard can display: letters, digits,
# and single spaces, trimmed and length-capped. Deliberately does NOT
# filter profanity — Talo does that server-side at registration, and
# doing it here too would just be a worse duplicate.
func _sanitise(raw: String) -> String:
	var out := ""
	for c in raw.strip_edges():
		if c.is_valid_identifier() or c.to_upper() != c.to_lower() or c.is_valid_int() or c == " ":
			out += c
		if out.length() >= MAX_LENGTH:
			break
	return out.strip_edges()


func save_profile() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify({"username": username, "claimed": claimed}))
	f.close()


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		username = String(parsed.get("username", ""))
		claimed = bool(parsed.get("claimed", false))
