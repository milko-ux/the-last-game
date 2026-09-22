extends Node
# ============================================================
# CONSENT — GDPR consent state, plus the player's country choice.
#
# The rule (from CLAUDE.md, non-negotiable): no feature may send or
# store player data without consent handled FIRST. This autoload is
# the single source of truth for "did they agree, when, and to which
# version of the text". The account panel shows the consent screen
# and calls grant(); Talo-facing code checks `granted` before any
# personal data moves.
#
# Country is SELF-DECLARED (guessed once from the device's locale,
# then freely editable or hidden). Deliberately no geolocation, no
# IP lookup — the player tells us, or we don't know. It's only ever
# attached to leaderboard entries, and only while show_country is on.
#
# If the consent text ever changes materially, bump VERSION — players
# who agreed to an older version will be shown the screen again.
# ============================================================

const SAVE_PATH := "user://consent.save"
const VERSION := 2   # 2: the short copy of 2026-09-22 (the long text is one tap away, unchanged)

var granted := false
var granted_at := ""       # ISO date, e.g. "2026-08-26" — proof of when
var granted_version := 0   # which text they agreed to
var country := ""          # ISO 3166-1 alpha-2, "" = none chosen
var show_country := true   # whether it goes on leaderboard entries

# Every ISO 3166-1 alpha-2 code, for validating what the player types.
const ISO_CODES := "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW"


func _ready() -> void:
	load_consent()
	if country.is_empty():
		country = _detect_country()


# Consent must be re-asked if the text version moved on.
func needs_consent() -> bool:
	return not granted or granted_version < VERSION


func grant() -> void:
	granted = true
	granted_at = Time.get_date_string_from_system(true)
	granted_version = VERSION
	save_consent()


func valid_code(code: String) -> bool:
	return code.length() == 2 and code.to_upper() in ISO_CODES.split(" ")


# Returns true if accepted. "" is allowed — it means "no country".
func set_country(code: String) -> bool:
	var clean := code.strip_edges().to_upper()
	if not clean.is_empty() and not valid_code(clean):
		return false
	country = clean
	save_consent()
	return true


func set_show_country(on: bool) -> void:
	show_country = on
	save_consent()


# Locale looks like "sv_SE" or "en_US" — the country is the 2-letter
# UPPERCASE token. A bare "sv" (no region) just yields no country.
func _detect_country() -> String:
	for token in OS.get_locale().replace("-", "_").split("_"):
		if token.length() == 2 and token == token.to_upper() and valid_code(token):
			return token
	return ""


func save_consent() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify({
		"granted": granted,
		"granted_at": granted_at,
		"granted_version": granted_version,
		"country": country,
		"show_country": show_country,
	}))
	f.close()


func load_consent() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		granted = bool(parsed.get("granted", false))
		granted_at = String(parsed.get("granted_at", ""))
		granted_version = int(parsed.get("granted_version", 0))
		country = String(parsed.get("country", ""))
		show_country = bool(parsed.get("show_country", true))
