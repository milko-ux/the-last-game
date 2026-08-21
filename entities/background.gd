extends Node2D
# ============================================================
# BACKGROUND — the far starfield, drawn behind everything.
#
# It's scaled to COVER the screen (never stretched out of shape):
# whichever axis needs more scaling wins, and the overflow is
# centred and cropped. That keeps the stars round on any phone.
#
# Note on "parallax": real parallax needs a moving camera, and this
# game's view is fixed per level, so there is nothing for the layer
# to move against yet. If the camera ever pans, this is the node to
# give a slower scroll to.
# ============================================================

const TEX := preload("res://assets/space_far.png")

# The art is brighter than the game needs; this keeps the neon on top.
const TINT := Color(0.48, 0.48, 0.56)


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func _draw() -> void:
	var screen := get_viewport_rect().size
	var tex_size := Vector2(TEX.get_width(), TEX.get_height())
	var cover: float = max(screen.x / tex_size.x, screen.y / tex_size.y)
	var draw_size := tex_size * cover
	var pos := (screen - draw_size) * 0.5
	draw_texture_rect(TEX, Rect2(pos, draw_size), false, TINT)
