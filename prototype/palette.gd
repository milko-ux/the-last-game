class_name WorldPalette
extends RefCounted
# ============================================================
# WORLD PALETTE — every colour the Phase A world uses, in one place
# (brief 2 section 0). Nothing in prototype/ declares a world colour
# anywhere else; Milko tunes these from a screenshot.
#
# It is a global class, not an autoload: the 2D game already owns the
# autoload name `Palette` (autoload/palette.gd), which the prototype's
# HUD still reads for its text colours. Use it as `WorldPalette.TILE`.
#
# Meaning is unchanged: magenta = will kill you, cyan = safe, amber = goal.
# 2026-09-19 colour pass (Milko, from the screenshots): grey fog instead of
# black, dim seams, one bright rim, two-tone monoliths.
# ============================================================

# THE CANYON (step 3 brief 2, 2026-10-21: Milko picked concept D,
# docs/concept/directions/D_monolith_canyon.png). The colours below up to
# the next heading are THE TIME OF DAY -- today the only one, a warm low
# morning sun; a later sunset or night is a second set of the same names.
#
# The fog: the haze the world fades into, by screen height (four stops:
# top of frame, a third down, the middle, the bottom), and what the
# height fog sinks the mesas' feet toward (BG_BOTTOM: the clouds in
# shadow). The backdrop (camera_rig.gd) paints the sky, the far cliffs
# and the cloud sea ON this gradient, so a far thing fades toward what is
# behind it. Before the canyon these were the grey fog's blue-greys.
const BG_TOP := Color("#f2dccb")        # the haze at the horizon
const BG_THIRD := Color("#eadad9")
const BG_MIDDLE := Color("#ddd1e0")     # the cloud sea, lit and shaded, on average
const BG_BOTTOM := Color("#bdb7d8")     # the clouds in shadow, far below
# The backdrop's painting (camera_rig.gd BACKDROP_SHADER).
const SKY_TOP := Color("#b9b8dc")       # the sky at the top of the frame, soft lilac-blue
const SKY_HORIZON := Color("#f7dcc4")   # warm peach just above the horizon
const SUN := Color("#fff4e0")
const SUN_GLOW := Color("#ffd9b8")      # the sun's halo: peach, never the goal's amber
const CLIFF_FAR := Color("#d6c8da")     # the far mesas on the horizon, the furthest layer...
const CLIFF_NEAR := Color("#bfb3d0")    # ...and the nearer one
const CLOUD_LIT := Color("#fff6ef")
const CLOUD_SHADE := Color("#c3bcdc")
# The floor (step 3 brief 2 section 2): cream limestone, procedural
# (flat_mats.gd TILE_SHADER; the baked slate atlas retired). The grey
# look's slate was #243141 on a near-black body.
const TILE := Color("#d8c9b0")          # the tile face, warm cream
const SLAB_SIDE := Color("#cdb99c")     # the slab's body: its front face, outer sides and pit walls, the same stone a shade deeper
const TILE_EDGE := Color("#19d3c9")     # the bright line along the slab's outer rim
const SAFE := Color("#19d3c9")          # pillars, checkpoint, death line
const LETHAL_ARMED := Color("#5a1638")  # dark wine magenta, the warning state
const LETHAL_LIVE := Color("#d8267f")   # magenta, lethal now -- deeper and more muted than the hot pink it was (stage B, 2026-09-24: the concept's walls), checked through ACES and glow
const LETHAL_SEAM := Color("#ffd6ec")   # a live plate's seam: white-magenta
const GOAL := Color("#ffb020")          # amber
const HERO_RIM := Color("#ffb9a0")      # brief 6 section 5: the rim on the hero's side away from the light -- the only warm light in the world
# The mesas around the field (step 3 brief 2 section 3, monoliths.gd /
# props.gd): one of these per mesa, as it reaches the screen on a top
# face (the sides step down by the light's tones), and the sunlit grass a
# top leans toward. Pastel, and never magenta, cyan or amber. The grey
# look's three dark band tints (#1e252e / #262e38 / #3e4756) are gone.
const MESAS := [Color("#bcaad6"), Color("#a9c2a8"), Color("#e6cba5"), Color("#a3b4d6"), Color("#ddd2c4"), Color("#e9c3a9")]   # lilac, sage, sand, slate blue, pale stone, warm peach
const MESA_CAP := Color("#b8cf90")
const TREES := [Color("#6f9b68"), Color("#8db36e")]     # the pines, the round ones (monoliths.gd)
const HEART := Color("#ef7a64")          # the lives' clay hearts (hud.gd): a warm coral, well clear of the lethal magenta and the goal's amber
const SCARF := Color("#a3b98f")          # the 1 km scarf's wool, a soft grey sage (2026-10-22; #7fa06c read as hose green) (scarf.gd); never cyan, magenta or amber
# The carved stone of the building models (2026-09-20: their material is
# procedural now, so the stone's colour lives here instead of in the
# model's baked texture). Near ones, and the far huge ones the fog carries.
# 2026-09-23 (brief 6): 30 % lighter than before, because the light's
# tones top out at 1.0 where the old ramp lit a facet to 1.3 -- so a lit
# face is as bright as it was, and the tops and shadow sides fall from it.
# Only the menu still shows them (menu.gd).
const BUILDING_STONE := Color("#5c6272")
const BUILDING_STONE_FAR := Color("#4f5664")
# Brief 6 section 1: the one light. Every unshaded block (tiles, slab
# sides, pit walls, monoliths, markers) is shaded by its face's normal
# against the light as THREE tones of its base colour -- top / lit side /
# shadow side -- and the shadow side is pulled SHADE_TINT_AMOUNT toward a
# cool colour so shadow reads as shadow, not as a darker grey. The light's
# direction is the scene's CreatureLight, published as `pr_light_dir`.
# The canyon (step 3 brief 2 section 4, 2026-10-21): a low warm morning
# sun (33 degrees up, from the screen-left behind the camera; was 53),
# so the shadows run long; the sides step down gently and the shadow side
# goes LILAC, never toward black (the grey look had 0.74 / 0.46 and a
# 15 % pull toward near-black blue; 35 % lilac turned every mesa lilac).
const LIGHT_TOP := 1.0
const LIGHT_SIDE := 0.9
const LIGHT_SHADE := 0.6
const SHADE_TINT := Color("#8a82c2")
const SHADE_TINT_AMOUNT := 0.28
const SHADOW := Color("#4a4278")        # the drop shadows on the floor (shadows.gd), cool lilac at their alpha; was black

# THE TIMES OF DAY (2026-10-21, Milko: "the sunrise to a sunset and
# eventually the character is running at night"). time_of_day.gd blends
# between these as the run goes further. Every set has the same names:
#   fog          the four haze stops (BG_*), what the world fades into
#   sky_top / sky_horizon / sun / sun_glow / sun_pos   the backdrop's sky;
#                sun_pos is on screen (0..1); at night the sun is the moon
#   cliff_far / cliff_near / cloud_lit / cloud_shade   the backdrop below it
#   sun_tint     the light's colour on the scenery (floor, mesas; never the
#                hazards), multiplied in
#   shade_tint   what a shadow side leans toward (SHADE_TINT in the morning)
#   shadow       the drop shadows' colour
#   light_colour / light_energy   the CreatureLight (the hero, the clay)
#   night        0..1: the stars, and the sun turning into the moon
# MORNING is the canyon as built (the constants above); sunset and night
# keep the colour meaning: no amber in the sky (the goal), no magenta.
const TIMES := {
	"morning": {
		"fog": [BG_TOP, BG_THIRD, BG_MIDDLE, BG_BOTTOM],
		"sky_top": SKY_TOP, "sky_horizon": SKY_HORIZON, "sun": SUN, "sun_glow": SUN_GLOW, "sun_pos": Vector2(0.16, 0.085),
		"cliff_far": CLIFF_FAR, "cliff_near": CLIFF_NEAR, "cloud_lit": CLOUD_LIT, "cloud_shade": CLOUD_SHADE,
		"sun_tint": Color(1.0, 1.0, 1.0), "shade_tint": SHADE_TINT, "shadow": SHADOW,
		"light_colour": Color(1.0, 0.93, 0.84), "light_energy": 1.25, "night": 0.0,
	},
	"sunset": {
		"fog": [Color("#f3c6ae"), Color("#e2b6b8"), Color("#c6a6c6"), Color("#8b80b4")],
		"sky_top": Color("#6d68a9"), "sky_horizon": Color("#ffc4a2"), "sun": Color("#fff1dc"), "sun_glow": Color("#ffa98e"),
		"sun_pos": Vector2(0.2, 0.165),
		"cliff_far": Color("#c69eb3"), "cliff_near": Color("#a386a8"), "cloud_lit": Color("#ffd5c2"), "cloud_shade": Color("#9883b9"),
		"sun_tint": Color(1.04, 0.88, 0.82), "shade_tint": Color("#6656a6"), "shadow": Color("#3a2c66"),
		"light_colour": Color(1.0, 0.85, 0.78), "light_energy": 1.15, "night": 0.0,   # warmer turned the magenta hazards toward the goal's amber
	},
	"night": {
		"fog": [Color("#323a6c"), Color("#2b3261"), Color("#252b56"), Color("#1a1e40")],
		"sky_top": Color("#0c0f2e"), "sky_horizon": Color("#36427e"), "sun": Color("#eef2ff"), "sun_glow": Color("#7d8dd2"),
		"sun_pos": Vector2(0.78, 0.075),
		"cliff_far": Color("#313a6d"), "cliff_near": Color("#272d5b"), "cloud_lit": Color("#6070b0"), "cloud_shade": Color("#232a56"),
		"sun_tint": Color(0.52, 0.58, 0.84), "shade_tint": Color("#1d2254"), "shadow": Color("#0b0d28"),
		"light_colour": Color(0.64, 0.72, 1.0), "light_energy": 0.85, "night": 1.0,
	},
}
