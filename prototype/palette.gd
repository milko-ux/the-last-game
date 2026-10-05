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

# The fog (brief 6 section 3, with Milko's correction 2026-09-23: the
# brief had it backwards). The concept is LIGHT at the top and in the
# distance, dark below: four stops, top of frame, a third down, the
# middle, the bottom. The backdrop is this gradient; every distant thing
# fades toward it at its own screen height, so far things get lighter,
# never black; below the slab everything sinks toward BG_BOTTOM.
# LIGHT FOG (step 3 brief 1 section 2, 2026-10-05): the old stops were the
# concept's colours as measured, but ACES (track_test TONEMAP_DEFAULT)
# crushes everything under ~30/255 (12 -> 2, 18 -> 5, 24 -> 10), so the
# lower fog came out near black. These are solved so that what reaches
# the SCREEN (Compatibility, ACES, measured on the web shot) is
# (85,97,115) / (70,79,94) / (54,61,74) / (36,41,51): the old top, and a
# dark blue-grey bottom instead of black.
const BG_TOP := Color("#4e5662")
const BG_THIRD := Color("#454b55")
const BG_MIDDLE := Color("#3b4049")
const BG_BOTTOM := Color("#2e323a")
const TILE := Color("#243141")          # the concept's blue slate, the tile face (brief 6 section 4: was #1c2830 teal)
const SLAB_SIDE := Color("#0c151c")     # the slab's body: its front face, outer sides and pit walls, dark stone (the concept's)
const TILE_SEAM := Color("#0f5f5a")     # the thin dim line between tiles
const TILE_EDGE := Color("#19d3c9")     # the bright line along the slab's outer rim
const SAFE := Color("#19d3c9")          # pillars, checkpoint, death line
const LETHAL_ARMED := Color("#5a1638")  # dark wine magenta, the warning state
const LETHAL_LIVE := Color("#d8267f")   # magenta, lethal now -- deeper and more muted than the hot pink it was (stage B, 2026-09-24: the concept's walls), checked through ACES and glow
const LETHAL_SEAM := Color("#ffd6ec")   # a live plate's seam: white-magenta
const GOAL := Color("#ffb020")          # amber
const HERO_RIM := Color("#ffb9a0")      # brief 6 section 5: the rim on the hero's side away from the light -- the only warm light in the world
const MONOLITH := Color("#2a2f37")
const MONOLITH_FAR := Color("#3a404a")
# The carved stone of the building models (2026-09-20: their material is
# procedural now, so the stone's colour lives here instead of in the
# model's baked texture). Near ones, and the far huge ones the fog carries.
# 2026-09-23 (brief 6): 30 % lighter than before, because the light's
# tones top out at 1.0 where the old ramp lit a facet to 1.3 -- so a lit
# face is as bright as it was, and the tops and shadow sides fall from it.
# Look pass v2 section 3 (2026-09-23): the pillars around the field in
# three bands -- near ones dark silhouettes, mid between, far ones
# fading into the light fog. The brightness order of the concept: fog
# lightest, floor the brightest thing in the play area, near pillars
# darkest.
# Light fog (2026-10-05): lighter, and every band now takes some of the
# fog (props.PILLAR_SIDE_FOG / PILLAR_FLATTEN), so a baked shadow face is
# stone at ~25/255 on screen instead of 0. Tuned on the web shot.
const NEAR_PILLAR := Color("#2a333e")
const MID_PILLAR := Color("#38424f")
const FAR_PILLAR := Color("#4a5464")
# THE LOOK BEFORE "light fog" (step 3 brief 1 section 2, 2026-10-05):
# the fog stops and band tints as they were, reachable on the phone as
# the look variant "today" (looks.gd) until Milko has compared the two.
const TODAY_FOG := [Color("#556173"), Color("#38404e"), Color("#1b2029"), Color("#0c1016")]
const TODAY_PILLAR := [Color("#1b232c"), Color("#222a34"), Color("#384150")]
const BUILDING_STONE := Color("#5c6272")
const BUILDING_STONE_FAR := Color("#4f5664")
# Brief 6 section 1: the one light. Every unshaded block (tiles, slab
# sides, pit walls, monoliths, markers) is shaded by its face's normal
# against the light as THREE tones of its base colour -- top / lit side /
# shadow side -- and the shadow side is pulled SHADE_TINT_AMOUNT toward a
# cool blue so shadow reads as shadow, not as a darker grey. The light's
# direction is the scene's CreatureLight, published as `pr_light_dir`.
const LIGHT_TOP := 1.0
const LIGHT_SIDE := 0.74
const LIGHT_SHADE := 0.46
const SHADE_TINT := Color("#0f1a26")
const SHADE_TINT_AMOUNT := 0.15
