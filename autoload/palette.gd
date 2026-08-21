extends Node
# ============================================================
# PALETTE — the fixed colour language of the game.
#
# These are a NON-NEGOTIABLE part of the visual identity:
#   magenta = death, cyan = safe, amber = goal.
# Every entity reads its colours from here so the meaning stays
# consistent no matter which script does the drawing.
# ============================================================

const BG := Color("0a0612")
const FLOOR := Color("160c28")
const FLOOR_LINE := Color("2b1b4d")
const WALL_TOP := Color("311a5c")
const WALL_LEFT := Color("1a0e33")
const WALL_RIGHT := Color("120a24")
const EDGE := Color("00fff2")        # cyan - safe
const PLAYER := Color("7dfaff")      # cyan - safe
const HAZ := Color("ff2bd6")         # magenta - death
const CHAIN := Color("ff7a1f")
const CHASER := Color("ff2b6b")
const GOAL := Color("ffd23d")        # amber - goal
const PIT := Color("05030a")
const TEXT := Color("a89fc2")
