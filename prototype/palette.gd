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
const TILE_SIDE := Color("#081a1d")     # side faces of the slab, pit walls
const SAFE := Color("#19d3c9")          # pillars, checkpoint, death line
const LETHAL_ARMED := Color("#5a1638")  # dark wine magenta, the warning state
const LETHAL_LIVE := Color("#ff2d95")   # bright magenta, lethal now
const LETHAL_SEAM := Color("#ffd6ec")   # a live plate's seam: white-magenta
const GOAL := Color("#ffb020")          # amber
const MONOLITH := Color("#2a2f37")
const MONOLITH_FAR := Color("#3a404a")
