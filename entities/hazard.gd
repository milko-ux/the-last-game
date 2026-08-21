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

# Motion ribbon. Lives on the base so every hazard type gets one and
# they all behave identically.
var trail := Trail.new(9)


# Called once when the level loads. `data` is one entry from levels.json.
func setup(data: Dictionary) -> void:
	speed = float(data.get("speed", 1.0))
	_configure(data)
	trail.clear()


# Overridden by each hazard type.
func _configure(_data: Dictionary) -> void:
	pass


# `elapsed` is time since the level started; `player_pos` lets chasers home in.
# Subclasses override _move(); the trail and the redraw are handled here so
# every hazard type keeps them in step.
func tick(delta: float, elapsed: float, player_pos: Vector2) -> void:
	_move(delta, elapsed, player_pos)
	trail.update(delta, world_pos)
	queue_redraw()


func _move(_delta: float, _elapsed: float, _player_pos: Vector2) -> void:
	pass


# Did this hazard catch the player?
#
# WHAT YOU SEE IS WHAT KILLS YOU. This test used to be measured on the flat
# grid underneath, but everything is DRAWN in isometric, which squashes the
# vertical axis to half. That made the real kill zone roughly half as tall as
# the ball looks on screen, so you could overlap the art from above or below
# and survive — while the same gap from the side killed you. Measuring the
# offset in SCREEN space instead makes contact mean contact from every
# direction, and is what makes the hazards feel sharp rather than mushy.
#
# `player_r` is the drawn size of the player, not its wall-collision box —
# wall collision stays on the grid, where it belongs.
func hits(player_pos: Vector2, player_r: float, player_airborne: bool) -> bool:
	if jumpable and player_airborne:
		return false
	var offset := Iso.project_offset(world_pos - player_pos)
	return offset.length() < RADIUS + player_r


# Shared motion ribbon, drawn under the orb so the orb stays the brightest part.
func _draw_trail(tint: Color, height: float) -> void:
	trail.draw_into(self, tint, RADIUS * 0.8, height, 1.3)


# Shared floor shadow, drawn by every hazard type.
func _draw_shadow() -> void:
	draw_circle(Iso.to_screen(world_pos, 0.0), RADIUS * 0.8, Color(0, 0, 0, 0.5))


# Shared glowing orb look for the low hazards.
func _draw_orb(tint: Color, height: float) -> void:
	var sp := Iso.to_screen(world_pos, height)
	draw_circle(sp, RADIUS + 7.0, Color(tint.r, tint.g, tint.b, 0.2))
	draw_circle(sp, RADIUS, Palette.glow(tint, 1.3))
	draw_circle(sp - Vector2(3, 3), RADIUS * 0.35, Color(1, 1, 1, 0.55))
