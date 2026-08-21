extends Node2D
class_name Hazard
# ============================================================
# HAZARD — shared base for everything that can kill you.
#
# Each hazard type is its own scene that knows how to move itself,
# how to test whether it caught the player, and how to draw itself.
# Adding a new hazard type means adding one scene here and one
# entry in levels.json — no changes to the main game loop.
# ============================================================

const RADIUS := 15.0

# Where the hazard is on the flat grid underneath.
var world_pos := Vector2.ZERO

# Set from levels.json.
var speed := 1.0

# Tall hazards (the chain) cannot be jumped over.
var jumpable := true


# Called once when the level loads. `data` is one entry from levels.json.
func setup(data: Dictionary) -> void:
	speed = float(data.get("speed", 1.0))
	_configure(data)


# Overridden by each hazard type.
func _configure(_data: Dictionary) -> void:
	pass


# `elapsed` is time since the level started; `player_pos` lets chasers home in.
func tick(_delta: float, _elapsed: float, _player_pos: Vector2) -> void:
	pass


# Did this hazard catch the player? Uses the same box-vs-circle test the
# original single-file version used, so difficulty is unchanged.
func hits(player_pos: Vector2, player_half: float, player_airborne: bool) -> bool:
	if jumpable and player_airborne:
		return false
	var closest := Vector2(
		clamp(world_pos.x, player_pos.x - player_half, player_pos.x + player_half),
		clamp(world_pos.y, player_pos.y - player_half, player_pos.y + player_half)
	)
	return closest.distance_to(world_pos) < RADIUS


# Shared floor shadow, drawn by every hazard type.
func _draw_shadow() -> void:
	draw_circle(Iso.to_screen(world_pos, 0.0), RADIUS * 0.8, Color(0, 0, 0, 0.5))


# Shared glowing orb look for the low hazards.
func _draw_orb(tint: Color, height: float) -> void:
	var sp := Iso.to_screen(world_pos, height)
	draw_circle(sp, RADIUS + 7.0, Color(tint.r, tint.g, tint.b, 0.2))
	draw_circle(sp, RADIUS, tint)
	draw_circle(sp - Vector2(3, 3), RADIUS * 0.35, Color(1, 1, 1, 0.55))
