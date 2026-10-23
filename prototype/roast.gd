extends RefCounted
# ============================================================
# THE ROAST LINES (roadmap step 5, the share screen): one short line on
# the end screen and on the share image, about the run that just ended.
# Drafted by Code 2026-10-23 -- MILKO'S VOICE, MILKO EDITS: change any
# line below, add or delete lines freely; nothing else depends on the
# wording. Keep a line short (it is one line on the phone) and kind
# underneath the teasing: the player should laugh and press RETRY.
#
# In a line, {m} is this run's distance ("212 m"), {gap} how far it fell
# short of the best ("38 m"), {best} the best ("250 m").
#
# Which list a run draws from, first match wins:
#   NEW_BEST    the run is a new best
#   EQUALLED    exactly the best
#   CLOSE       short of the best by at most CLOSE_M, or CLOSE_FRAC of it
#   WARM_UP     under WARM_UP_M
#   then a coin toss between the killer's list (KILLED_BY) and the time
#   of day the run ended in (the canyon's day: time_of_day.gd).
# The same line never comes twice in a row.
# ============================================================

const Hud := preload("res://prototype/hud.gd")
const TimeOfDay := preload("res://prototype/time_of_day.gd")

const CLOSE_M := 15
const CLOSE_FRAC := 0.12
const WARM_UP_M := 30

const NEW_BEST := [
	"New best. The canyon felt that.",
	"Personal record. Tell someone.",
	"Look at you. New best.",
	"Best run yet. Now do it again.",
	"New best. Who taught you that?",
]

const EQUALLED := [
	"Exactly your best. Spooky.",
	"Same as your best. To the metre.",
]

const CLOSE := [
	"{gap} short. So close it hurts.",
	"Your best is laughing. From {gap} away.",
	"Almost. Almost doesn't count.",
	"{gap} from glory.",
	"That close to {best}. Again.",
]

const WARM_UP := [
	"That was the warm-up. Right?",
	"{m}. The canyon didn't even notice.",
	"Blink and you missed it. So did you.",
	"Bold strategy: dying first.",
]

# The killer, as rules.gd names it (Rules.death_cause "kind").
const KILLED_BY := {
	"slammer": [
		"Flattened. Like a pancake with one eye.",
		"The slammer slammed. As advertised.",
	],
	"sweeper": [
		"Swept off your feet. Not the romantic way.",
		"It swept. You didn't jump.",
	],
	"gate": [
		"The gate was open. Just not there.",
		"Wrong door.",
	],
	"orbiter": [
		"You were in its orbit. Briefly.",
		"Round and round, then out.",
	],
	"volley": [
		"Caught one. Not the good kind.",
		"Dodgeball champion, you are not.",
	],
	"plate": [
		"Magenta means no. Now you know.",
		"Stood on the one tile you shouldn't.",
	],
	"fall": [
		"The clouds looked soft. They weren't.",
		"Gravity: still undefeated.",
	],
	"back_edge": [
		"Too slow. The edge caught up.",
		"Dawdling is fatal out here.",
	],
}

# The time of day the run ended in, by metres into the canyon's day
# (time_of_day.gd KEYS: morning to 300, sunset to 560, night to 800,
# dawn to 950).
const MORNING := [
	"{m}. A stroll, not a run.",
	"Respectable. For a tourist.",
	"The clay is willing. The thumbs are weak.",
	"Not bad. Not good either.",
]
const SUNSET := [
	"The sun went down. So did you.",
	"Golden hour. Not your finest one.",
	"{m}. Ride off into the sunset next time.",
]
const NIGHT := [
	"Lost in the dark at {m}.",
	"Out past bedtime and it showed.",
	"The stars saw everything.",
]
const DAWN := [
	"You ran through the night. Then this.",
	"{m}. The canyon is starting to worry.",
	"A whole day of running. Respect.",
]

static var _last := ""


# The line for a run. `killer` is the last death's kind ("" if unknown).
static func line(metres: int, best: int, new_best: bool, killer: String) -> String:
	var pool: Array = _pool(metres, best, new_best, killer)
	var pick: String = pool[randi() % pool.size()]
	if pool.size() > 1 and pick == _last:
		pick = pool[(pool.find(pick) + 1) % pool.size()]
	_last = pick
	return pick.format({"m": Hud.metres(metres), "gap": Hud.metres(best - metres), "best": Hud.metres(best)})


static func _pool(metres: int, best: int, new_best: bool, killer: String) -> Array:
	if new_best:
		return NEW_BEST
	if best > 0 and metres == best:
		return EQUALLED
	if best > 0 and best - metres <= maxi(CLOSE_M, int(best * CLOSE_FRAC)):
		return CLOSE
	if metres < WARM_UP_M:
		return WARM_UP
	if KILLED_BY.has(killer) and randf() < 0.5:
		return KILLED_BY[killer]
	var at := fposmod(float(metres), TimeOfDay.CYCLE_M)
	if at < 300.0:
		return MORNING
	if at < 560.0:
		return SUNSET
	if at < 800.0:
		return NIGHT
	return DAWN

