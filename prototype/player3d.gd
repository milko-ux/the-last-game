extends CharacterBody3D
# ============================================================
# PLAYER (3D) — a white capsule with one black eye. Moves freely
# on the field in x and z at PLAYER_SPEED, plus jump. The only
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
var dead := false:
	set(v):
		dead = v
		_mesh.material_override = Mats.player(Palette.HAZ) if v else Mats.player(Color.WHITE)

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _eye_pivot: Node3D = $EyePivot
@onready var _eye: MeshInstance3D = $EyePivot/Eye


func _ready() -> void:
	_mesh.material_override = Mats.player(Color.WHITE)
	_eye.material_override = Mats.player(Color(0.02, 0.02, 0.03))
	_eye.material_override.render_priority = 11


func reset_to(x: float, z: float) -> void:
	position = Vector3(x, 0.0, z)
	prev_position = position
	y = 0.0
	vy = 0.0
	on_ground = true
	move_dir = Vector2.ZERO
	_eye_pivot.rotation.y = 0.0


func tick(delta: float, z_front: float, field: Node3D) -> void:
	prev_position = position
	var v := move_dir
	if v.length() > 1.0:
		v = v.normalized()
	position.x += v.x * SCREEN_X * Rules.player_speed() * delta
	position.z = minf(position.z + v.y * Rules.player_speed() * delta, z_front - HALF_D)

	var floor_here: bool = field.floor_at(position.x, position.z)
	if on_ground and not floor_here:
		on_ground = false
	if not on_ground:
		vy -= GRAVITY_PX * WORLD_PER_PX * delta
		y += vy * delta
		if y <= 0.0 and floor_here:
			y = 0.0
			vy = 0.0
			on_ground = true
	position.y = y


func jump() -> bool:
	if not on_ground:
		return false
	vy = JUMP_VELOCITY_PX * WORLD_PER_PX
	on_ground = false
	return true


func fell() -> bool:
	return y < Rules.FALL_DEATH_Y


# The eye turns toward the nearest thing that will be lethal within the
# next beat; forward when nothing is. (Milko's one-eyed creature: the eye
# telegraphing danger is gameplay, so it lives in the gray-box.)
func look_at_danger(target: Variant) -> void:
	var yaw := 0.0
	if target != null:
		var d: Vector3 = target - position
		yaw = atan2(d.x, d.z)
	_eye_pivot.rotation.y = lerp_angle(_eye_pivot.rotation.y, yaw, 0.35)


# World-space box used for hazard hit tests.
func bounds() -> AABB:
	return Rules.player_box(position)
