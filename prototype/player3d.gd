extends CharacterBody3D
# ============================================================
# PLAYER (3D) — a flat white capsule. No character art yet.
#
# Forward position is NOT velocity: z is set every frame from the
# song clock (position = time). The only inputs are left/right
# and jump. The jump numbers are the 2D game's, which Milko has
# confirmed feel right on-device; they are scaled from screen
# pixels into world units but keep the same air time.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")

# Cross one full lane (2 units) in ~0.25 s.
const LATERAL_SPEED := 8.0
# The camera looks down +z from behind, so world +x is screen LEFT.
const SCREEN_X := -1.0
const HALF_W := 0.4
const HEIGHT := 1.6
const HALF_D := 0.4
const X_LIMIT := 3.0 - HALF_W

# entities/player.gd numbers, unchanged: apex 53.9 px, 0.67 s in the air.
const JUMP_VELOCITY_PX := 320.0
const GRAVITY_PX := 950.0
# Pixels -> world units, chosen so the apex is 2.0 units: clears a
# slammer (0.6) with room, never a pulser (3.0).
const WORLD_PER_PX := 2.0 / 53.9

var move_axis := 0.0
var y := 0.0
var vy := 0.0
var on_ground := true
var dead := false:
	set(v):
		dead = v
		_mesh.material_override = Mats.magenta() if v else Mats.white()

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_mesh.material_override = Mats.white()


func reset_to(x: float, z: float) -> void:
	position = Vector3(x, 0.0, z)
	y = 0.0
	vy = 0.0
	on_ground = true
	move_axis = 0.0


func tick(delta: float, z: float) -> void:
	position.x = clampf(position.x + move_axis * SCREEN_X * LATERAL_SPEED * delta, -X_LIMIT, X_LIMIT)
	if not on_ground:
		vy -= GRAVITY_PX * WORLD_PER_PX * delta
		y += vy * delta
		if y <= 0.0:
			y = 0.0
			vy = 0.0
			on_ground = true
	position.y = y
	position.z = z


func jump() -> bool:
	if not on_ground:
		return false
	vy = JUMP_VELOCITY_PX * WORLD_PER_PX
	on_ground = false
	return true


# World-space box used for hazard hit tests.
func bounds() -> AABB:
	return AABB(position + Vector3(-HALF_W, 0.0, -HALF_D), Vector3(HALF_W * 2.0, HEIGHT, HALF_D * 2.0))
