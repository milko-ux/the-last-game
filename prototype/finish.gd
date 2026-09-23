extends CanvasLayer
# ============================================================
# THE FINISHING LAYER (brief 6 sections 7-8, look pass v2 section 6):
# one unshaded full-screen quad UNDER the HUD -- a vignette of about
# 25 % at the corners, nothing at the centre, and a very subtle film
# grain. No colour-grading LUT, no screen read-back: the quad is
# alpha-blended over the 3D picture, so it costs one full-screen fill
# and nothing else. Glow, tonemapping and MSAA are the WorldEnvironment's
# and the viewport's (track_test.gd, apply_finish); this file is only
# what has to be drawn.
#
# ?vignette=0 and ?grain=0 (dev URL switches) turn each off for an A/B.
# ============================================================

const VIGNETTE := 0.25          # at the corners
const VIGNETTE_START := 0.55    # of the half diagonal, where it begins
const GRAIN := 0.02             # alpha of the speckle (0.035 read as noise, not film)

const SHADER := """
shader_type canvas_item;
render_mode blend_mix;
uniform float vignette = 0.25;
uniform float vignette_start = 0.55;
uniform float grain = 0.035;
uniform vec2 screen = vec2(2400.0, 1080.0);

float hash2(vec2 p) {
	p = fract(p * vec2(0.3183099, 0.3678794) + vec2(0.1, 0.7));
	p *= 23.0;
	return fract(p.x * p.y * (p.x + p.y));
}

void fragment() {
	float d = length(UV - 0.5) * 1.41421;
	float v = smoothstep(vignette_start, 1.0, d) * vignette;
	// Grain: a speckle that changes every frame, drawn as white or black
	// at a small alpha, so it adds and takes in equal measure.
	float n = hash2(floor(UV * screen * 0.5) + vec2(fract(TIME * 7.0) * 100.0, fract(TIME * 13.0) * 100.0));
	float bright = step(0.5, n);
	float g = grain * abs(n - 0.5) * 2.0;
	// Black for the vignette, the speckle's own tone for the grain.
	vec3 col = mix(vec3(0.0), vec3(bright), g / max(g + v, 0.0001));
	COLOR = vec4(col, clamp(v + g, 0.0, 1.0));
}
"""

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 0                       # above the 3D world, below the UI layer (1)
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("vignette", VIGNETTE)
	_mat.set_shader_parameter("vignette_start", VIGNETTE_START)
	_mat.set_shader_parameter("grain", GRAIN)
	_rect.material = _mat
	add_child(_rect)
	_resize()
	get_viewport().size_changed.connect(_resize)


func _resize() -> void:
	var s := get_viewport().get_visible_rect().size
	_mat.set_shader_parameter("screen", s)


func set_vignette(on: bool) -> void:
	_mat.set_shader_parameter("vignette", VIGNETTE if on else 0.0)


func set_grain(on: bool) -> void:
	_mat.set_shader_parameter("grain", GRAIN if on else 0.0)
