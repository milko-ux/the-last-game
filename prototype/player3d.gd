extends CharacterBody3D
# ============================================================
# PLAYER (3D) — position, jump and the hit box. What you SEE is the
# creature (creature.gd, Phase A brief 1): purely visual, 3 units tall,
# while the hit box stays the gray-box capsule's (0.8 x 1.6 x 0.8 at the
# feet, Rules.player_box) — bigger to look at than to hit, on purpose.
# Moves freely on the field in x and z at PLAYER_SPEED, plus jump. The only
# constraints are the window: it cannot pass the front edge, and
# dropping out of the back edge is a death (handled by the scene).
#
# No side walls: off the edge you fall. Over a pit you fall.
#
# Jump numbers are the 2D game's (entities/player.gd), scaled from
# pixels to world units with the same air time.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Rules := preload("res://prototype/rules.gd")

# The camera looks down +z from behind, so world +x is screen LEFT.
const SCREEN_X := -1.0
const HALF_W := Rules.PLAYER_HALF_W
const HEIGHT := Rules.PLAYER_HEIGHT
const HALF_D := Rules.PLAYER_HALF_D

# entities/player.gd numbers, unchanged: apex 53.9 px, 0.67 s in the air.
const JUMP_VELOCITY_PX := 320.0
const GRAVITY_PX := 950.0
# Pixels -> world units, chosen so the apex is 2.0 units.
const WORLD_PER_PX := 2.0 / 53.9

var move_dir := Vector2.ZERO    # x: screen-right positive, y: forward positive
var prev_position := Vector3.ZERO   # feet position last frame, for swept checks
var y := 0.0
var vy := 0.0
var on_ground := true
var dead := false

@onready var creature: Node3D = $Creature


func reset_to(x: float, z: float) -> void:
	position = Vector3(x, 0.0, z)
	prev_position = position
	y = 0.0
	vy = 0.0
	on_ground = true
	move_dir = Vector2.ZERO


func tick(delta: float, z_back: float, z_front: float, field: Node3D) -> void:
	prev_position = position
	var v := move_dir
	if v.length() > 1.0:
		v = v.normalized()
	# The speed is a knob of the field being run on (its lap / level).
	var speed: float = Rules.player_speed(field.knobs_at(position.z))
	position.x += v.x * SCREEN_X * speed * delta
	position.z = minf(position.z + v.y * speed * delta, z_front - HALF_D)
	# The intro carry: the window pushes an idle player forward instead of
	# killing them (Rules.carry_line is -INF once hazards are armed).
	position.z = maxf(position.z, Rules.carry_line(z_back))

	var floor_here: bool = field.floor_at(position.x, position.z)
	if on_ground and not floor_here:
		on_ground = false
	if not on_ground:
		vy -= GRAVITY_PX * WORLD_PER_PX * delta
		var y_prev := y
		y += vy * delta
		# Landing: from above the floor (a jump coming down), or from no
		# deeper than the grace -- deeper than that is a pit, and a pit
		# keeps you (Rules.LAND_GRACE_Y).
		if y <= 0.0 and floor_here and (y_prev > 0.0 or y >= Rules.LAND_GRACE_Y):
			y = 0.0
			vy = 0.0
			on_ground = true
	position.y = y


func jump() -> bool:
	if not on_ground:
		return false
	vy = JUMP_VELOCITY_PX * WORLD_PER_PX
	on_ground = false
	creature.on_jump(2.0 * JUMP_VELOCITY_PX / GRAVITY_PX)
	return true


func fell() -> bool:
	return y < Rules.FALL_DEATH_Y


# The eye turns toward the nearest thing that will be lethal within the
# next beat; forward when nothing is. The eye telegraphing danger is
# gameplay; the turning itself (and the bracing when it is close) is the
# creature's job.
func look_at_danger(target: Variant) -> void:
	creature.set_look_target(target)


# World-space box used for hazard hit tests.
func bounds() -> AABB:
	return Rules.player_box(position)
