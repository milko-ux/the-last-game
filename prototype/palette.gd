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

const BG_TOP := Color("#14171d")
const BG_BOTTOM := Color("#262b34")
const TILE := Color("#1c2830")          # dark stone, the tile face
const TILE_SEAM := Color("#0f5f5a")     # the thin dim line between tiles
const TILE_EDGE := Color("#19d3c9")     # the bright line along the slab's outer rim
const SAFE := Color("#19d3c9")          # pillars, checkpoint, death line
const LETHAL_ARMED := Color("#5a1638")  # dark wine magenta, the warning state
const LETHAL_LIVE := Color("#ff2d95")   # bright magenta, lethal now
const LETHAL_SEAM := Color("#ffd6ec")   # a live plate's seam: white-magenta
const GOAL := Color("#ffb020")          # amber
const MONOLITH := Color("#2a2f37")
const MONOLITH_FAR := Color("#3a404a")
# The carved stone of the building models (2026-09-20: their material is
# procedural now, so the stone's colour lives here instead of in the
# model's baked texture). Near ones, and the far huge ones the fog carries.
# 2026-09-23 (brief 6): 30 % lighter than before, because the light's
# tones top out at 1.0 where the old ramp lit a facet to 1.3 -- so a lit
# face is as bright as it was, and the tops and shadow sides fall from it.
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
