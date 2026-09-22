extends Node
# ============================================================
# TALO — the thin client for the Talo game backend.
#
# An autoload (a script Godot loads once at startup that any other
# script can reach). This is the ONLY file that talks to the internet:
# accounts (register / log in / log out / delete) and leaderboards
# (submit a score, fetch the rankings). Everything goes over HTTPS to
# Talo's REST API — no third-party addon, so every request the game
# ever makes is readable right here.
#
# CONFIG: reads res://talo.cfg (gitignored — the repo is public, the
# key is not). Copy talo.cfg.example to talo.cfg and paste the access
# key in. With no key, configured() is false and the whole feature
# stays invisible in the UI — the game plays exactly as before.
#
# PRIVACY: nothing in this file runs until the player has passed the
# consent screen (Consent.granted) and chosen to create an account.
# Guests never generate network traffic.
#
# The wire format (headers, endpoints, response shapes) was taken from
# Talo's own Godot plugin source, so it matches what their server
# actually expects:
#   auth:         POST /v1/players/auth/{register,login,logout,refresh}
#                 DELETE /v1/players/auth   (account deletion, GDPR)
#   identify:     GET  /v1/players/identify (rebuilds identity on relaunch)
#   leaderboards: GET/POST /v1/leaderboards/<name>/entries
# Every authed request carries X-Talo-Alias / X-Talo-Player /
# X-Talo-Session headers plus the access key as a Bearer token.
# ============================================================

signal auth_changed

const CONFIG_PATH := "res://talo.cfg"
const SESSION_PATH := "user://talo_session.cfg"
const TIMEOUT := 15.0

# ------------------------------------------------------------
# WEB TRANSPORT
# Godot 4.7.1's own HTTPRequest is broken in web exports - it stalls
# before ever calling the browser (verified: the browser-side fetch
# never fires, every request dies as RESULT_TIMEOUT with status 0,
# native builds run the identical code fine). So on web the game does
# its HTTP through the browser directly: this snippet is installed
# once at startup, GDScript starts a request by id, then polls
# __taloTake(id) each frame until the response is dropped off.
# Arguments travel base64-encoded so no password or JSON can ever
# escape the string literal. Native builds never touch this.
# ------------------------------------------------------------
const JS_HELPER := """
window.__talo = { res: {} };
window.__taloFetch = function (id, method, url, headersB64, bodyB64) {
	try {
		var dec = function (b) { return b ? decodeURIComponent(escape(atob(b))) : ''; };
		var init = { method: method, headers: JSON.parse(dec(headersB64)) };
		var body = dec(bodyB64);
		if (body.length) { init.body = body; }
		fetch(url, init).then(function (r) {
			return r.text().then(function (t) {
				window.__talo.res[id] = JSON.stringify({ status: r.status, body: t });
			});
		}).catch(function (e) {
			window.__talo.res[id] = JSON.stringify({ status: 0, body: '', error: String(e) });
		});
	} catch (e) {
		window.__talo.res[id] = JSON.stringify({ status: 0, body: '', error: String(e) });
	}
};
window.__taloTake = function (id) {
	var r = window.__talo.res[id];
	if (r === undefined) { return ''; }
	delete window.__talo.res[id];
	return r;
};
"""

var base_url := "https://api.trytalo.com"
var access_key := ""

# --- Who is signed in right now. Cleared = playing as a guest. ---
var alias_id := -1
var player_id := ""
var identifier := ""
var _session_token := ""

# Talo's machine-readable error codes, translated to something a
# player can act on. Anything unlisted falls back to the raw message.
const ERROR_TEXT := {
	"INVALID_CREDENTIALS": "Wrong name or password.",
	"IDENTIFIER_TAKEN": "That name is already taken.",
	"IDENTIFIER_PROFANITY": "That name isn't allowed.",
	"INVALID_EMAIL": "That email doesn't look right.",
	"EMAIL_TAKEN": "That email is already in use.",
	"INVALID_SESSION": "Your session expired - log in again.",
	"MISSING_SESSION": "You're not logged in.",
}


func _ready() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(JS_HELPER, true)
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		access_key = str(cfg.get_value("talo", "access_key", ""))
		base_url = str(cfg.get_value("talo", "base_url", base_url))
	auth_changed.connect(_sync_profile)
	if configured():
		resume_session()


# Keeps the local guest name in step with the account: signing in claims
# the name, signing out (or deleting the account) releases it, and a
# released account's best is no longer "posted" — a new account has to
# post it again. This was main.gd's job while the 2D game was the only
# caller; the menu and the run both need it now, so it lives with the
# signal it answers.
func _sync_profile() -> void:
	# A tool's sign-in (tools/talo_check.gd) must never rename the guest
	# profile of whoever owns this machine: the check claimed its throwaway
	# account's name into Milko's own profile.save on 2026-09-22.
	if not Progress.save_enabled:
		return
	if logged_in():
		Profile.claim(identifier)
	else:
		if Profile.claimed:
			Profile.unclaim()
		Progress.unpost_best()


func configured() -> bool:
	return not access_key.is_empty()


func logged_in() -> bool:
	return alias_id != -1


# ============================================================
# BOARD NAMES + SCORE ENCODING
# Six leaderboards: a "progress" and a "finishers" board per tier.
# These names must match the internal names created in the Talo
# dashboard — see docs/TALO_SETUP.md.
#
# Progress boards rank the furthest level reached, with deaths as the
# tiebreak, packed into one number because Talo sorts on one number:
#   score = level*1000 + (999 - deaths, floored at 0)
# so level always wins, and at the same level fewer deaths wins.
# A finished run scores as level_count+1 — clearing beats any death.
# Finishers boards are simply deaths, sorted ascending (fewest wins).
# ============================================================
func progress_board(d: int) -> String:
	return "progress-" + Progress.tier_name(d).to_lower()


func finishers_board(d: int) -> String:
	return "finishers-" + Progress.tier_name(d).to_lower()


static func encode_progress(reached_level: int, deaths: int) -> float:
	return reached_level * 1000.0 + clampf(999.0 - deaths, 0.0, 999.0)


static func progress_level(score: float) -> int:
	return int(score / 1000.0)


# ============================================================
# THE ENDLESS RUN'S BOARD (Phase E section 8)
# One board, `distance`: descending, unique — one entry per player,
# replaced only by a better run (Talo's own rule for unique boards).
# The season is a prop on the entry, not part of the name; so are the
# things a later cheat check needs (laps, run_seconds, deaths, build,
# layout). Created by hand in the dashboard: docs/TALO_SETUP.md.
# ============================================================
const DISTANCE_BOARD := "distance"
# Bots and screenshot tools turn saving off (Milko's rule 6) and that
# same switch keeps them off the board: a bot's run is not a score. The
# one tool that MUST post — tools/talo_check.gd, the live acceptance,
# with a throwaway account it deletes again — says so here.
var allow_tool_posts := false


# Posts the player's BEST run of `season` — once. The run scene calls it
# when a run ends, the menu when the player signs in; whichever comes
# first posts, the other finds it already posted and does nothing. A
# new best clears the flag (Progress.record_distance), so the next call
# posts again, and Talo only replaces the entry if it really is better.
# Returns the rank line for the screen ("#12 GLOBAL   ·   #3 SE"), or
# "" when there was nothing to do, or the error text.
func post_best_distance(season: int) -> String:
	if not Progress.save_enabled and not allow_tool_posts:
		return ""
	if not (configured() and logged_in() and Consent.granted):
		return ""
	var metres: int = Progress.best_distance_for(season)
	if metres <= 0 or Progress.best_posted(season):
		return ""
	var props: Dictionary = Progress.best_run_for(season).duplicate()
	props.erase("posted")
	props["season"] = season
	var with_country: bool = Consent.show_country and not Consent.country.is_empty()
	if with_country:
		props["country"] = Consent.country
	var res: Dictionary = await submit_score(DISTANCE_BOARD, float(metres), props)
	if not res.ok:
		return str(res.error)
	Progress.mark_best_posted(season)
	var pos := int(res.data.get("entry", {}).get("position", -1))
	var line := ("#%d GLOBAL" % (pos + 1)) if pos >= 0 else "POSTED"
	if with_country:
		var rank: int = await country_rank(DISTANCE_BOARD, Consent.country)
		if rank > 0:
			line += "   ·   #%d %s" % [rank, Consent.country]
	return line


# The player's rank among ONE country's entries, 1-based, or 0 if not on
# the first `max_pages` pages of 50. Talo filters on the prop server-side
# and hands the entries back best first, so the rank is the index.
func country_rank(board: String, country: String, max_pages: int = 3) -> int:
	for page in max_pages:
		var res: Dictionary = await get_entries(board, page, "country", country)
		if not res.ok:
			return 0
		var entries: Array = res.data.get("entries", [])
		for i in entries.size():
			var alias: Dictionary = entries[i].get("playerAlias", {})
			if int(alias.get("id", -2)) == alias_id:
				return page * 50 + i + 1
		if bool(res.data.get("isLastPage", true)):
			return 0
	return 0


# ============================================================
# ACCOUNTS
# All of these return {ok, status, data, error} — callers show
# `error` to the player when ok is false.
# ============================================================

# Email is optional and only enables password recovery. Verification
# (email codes on every login) stays off — we never force email.
func register_account(account_name: String, password: String, email: String) -> Dictionary:
	var res := await _request(HTTPClient.METHOD_POST, "/v1/players/auth/register", {
		"identifier": account_name,
		"password": password,
		"email": email,
		"verificationEnabled": false,
		"withRefresh": true,
	})
	if res.ok:
		_adopt_session(res.data)
	return res


func login(account_name: String, password: String) -> Dictionary:
	var res := await _request(HTTPClient.METHOD_POST, "/v1/players/auth/login", {
		"identifier": account_name,
		"password": password,
		"withRefresh": true,
	})
	if res.ok:
		if bool(res.data.get("verificationRequired", false)):
			# Can only happen to an account created outside this game.
			res.ok = false
			res.error = "This account requires email verification, which isn't supported here."
		else:
			_adopt_session(res.data)
	return res


func logout() -> void:
	# Best-effort server call; locally we're logged out no matter what.
	await _request(HTTPClient.METHOD_POST, "/v1/players/auth/logout")
	_clear_session()
	auth_changed.emit()


# The GDPR "delete my data" path: removes the account, its alias and
# its leaderboard entries on Talo's side. Verified live (2026-09-02):
# register -> play -> delete -> the entry was gone from a fresh
# dashboard check afterward. Note Talo's public API has no dedicated
# endpoint to delete a leaderboard entry directly (only GET/POST exist
# on /v1/leaderboards/:name/entries) - the entry disappearing is a
# side effect of deleting the alias it belongs to, not a deliberate
# step, and reads can lag briefly (an immediate re-check right after
# deletion once showed the entry still listed, before a later check
# showed it gone - looked like a short-lived cache, not a real gap).
func delete_account(current_password: String) -> Dictionary:
	var res := await _request(HTTPClient.METHOD_DELETE, "/v1/players/auth", {
		"currentPassword": current_password,
	})
	if res.ok:
		_clear_session()
		auth_changed.emit()
	return res


# Called once at startup: if a previous session left a refresh token,
# trade it for a fresh session token and re-identify. Fire-and-forget —
# the game doesn't wait on it, the UI just updates when it lands.
func resume_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	var refresh := str(cfg.get_value("session", "refreshToken", ""))
	var stored_name := str(cfg.get_value("session", "identifier", ""))
	if refresh.is_empty() or stored_name.is_empty():
		return

	var res := await _request(HTTPClient.METHOD_POST, "/v1/players/auth/refresh", {
		"refreshToken": refresh,
	})
	if not res.ok:
		# An expired/revoked token means logged out; a network failure
		# means try again next launch — keep the token for that.
		if res.status == 401 or res.status == 403:
			_clear_session()
		return

	_session_token = str(res.data.get("sessionToken", ""))
	_save_session(str(res.data.get("refreshToken", "")), stored_name)

	var idres := await _request(HTTPClient.METHOD_GET,
		"/v1/players/identify?service=talo&identifier=" + stored_name.uri_encode())
	if idres.ok and idres.data is Dictionary and idres.data.has("alias"):
		var alias: Dictionary = idres.data.alias
		alias_id = int(alias.get("id", -1))
		identifier = str(alias.get("identifier", stored_name))
		player_id = str(alias.get("player", {}).get("id", ""))
		auth_changed.emit()


# ============================================================
# LEADERBOARDS
# ============================================================

# Talo keeps ONE entry per player on these boards and only replaces it
# when the new score is better (verified in their server source), so
# it's safe to submit every finished run. The response includes the
# entry's current position — 0-based, so +1 for display.
func submit_score(board: String, score: float, props: Dictionary) -> Dictionary:
	var plist := []
	for key in props:
		plist.append({"key": str(key), "value": str(props[key])})
	return await _request(HTTPClient.METHOD_POST,
		"/v1/leaderboards/%s/entries" % board, {"score": score, "props": plist})


# One page = up to 50 entries, best first. prop_key/prop_value filter
# server-side — used for the country view (propKey=country).
func get_entries(board: String, page: int, prop_key := "", prop_value := "") -> Dictionary:
	var path := "/v1/leaderboards/%s/entries?page=%d" % [board, page]
	if not prop_key.is_empty():
		path += "&propKey=%s&propValue=%s" % [prop_key.uri_encode(), prop_value.uri_encode()]
	return await _request(HTTPClient.METHOD_GET, path)


# ============================================================
# PLUMBING
# ============================================================
func _adopt_session(data: Dictionary) -> void:
	var alias: Dictionary = data.get("alias", {})
	alias_id = int(alias.get("id", -1))
	identifier = str(alias.get("identifier", ""))
	player_id = str(alias.get("player", {}).get("id", ""))
	_session_token = str(data.get("sessionToken", ""))
	_save_session(str(data.get("refreshToken", "")), identifier)
	auth_changed.emit()


func _save_session(refresh_token: String, stored_name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "refreshToken", refresh_token)
	cfg.set_value("session", "identifier", stored_name)
	cfg.save(SESSION_PATH)


func _clear_session() -> void:
	alias_id = -1
	player_id = ""
	identifier = ""
	_session_token = ""
	var cfg := ConfigFile.new()
	cfg.save(SESSION_PATH)


func _request(method: HTTPClient.Method, path: String, body: Dictionary = {}) -> Dictionary:
	var headers := {
		"Authorization": "Bearer %s" % access_key,
		"Content-Type": "application/json",
		"Accept": "application/json",
	}
	if alias_id != -1:
		headers["X-Talo-Alias"] = str(alias_id)
	if not player_id.is_empty():
		headers["X-Talo-Player"] = player_id
	if not _session_token.is_empty():
		headers["X-Talo-Session"] = _session_token

	var body_text := "" if body.is_empty() else JSON.stringify(body)

	# {status: int, body: String, error: String} - status 0 = no response.
	var raw: Dictionary
	if OS.has_feature("web"):
		raw = await _transport_web(method, path, headers, body_text)
	else:
		raw = await _transport_native(method, path, headers, body_text)

	if int(raw.status) == 0:
		return {"ok": false, "status": 0, "data": {},
			"error": "No connection. Check your internet and try again."}

	var status := int(raw.status)
	var text := str(raw.body).strip_edges()
	# An empty body (a 204 from logout / delete) is not a parse error.
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else {}
	if data == null:
		data = {}
	var out := {"ok": status >= 200 and status < 300, "status": status, "data": data, "error": ""}
	if not out.ok:
		out.error = _friendly_error(status, data)
	return out


func _method_name(method: HTTPClient.Method) -> String:
	match method:
		HTTPClient.METHOD_POST: return "POST"
		HTTPClient.METHOD_DELETE: return "DELETE"
		_: return "GET"


# Web: hand the request to the browser (see JS_HELPER above), then
# poll once a frame for the dropped-off response.
var _js_seq := 0

func _transport_web(method: HTTPClient.Method, path: String, headers: Dictionary, body_text: String) -> Dictionary:
	_js_seq += 1
	var id := _js_seq
	var h64 := Marshalls.utf8_to_base64(JSON.stringify(headers))
	var b64 := "" if body_text.is_empty() else Marshalls.utf8_to_base64(body_text)
	JavaScriptBridge.eval("__taloFetch(%d,'%s','%s','%s','%s');" % [
		id, _method_name(method), base_url + path, h64, b64], true)

	var deadline := Time.get_ticks_msec() + int(TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var out := str(JavaScriptBridge.eval("__taloTake(%d);" % id, true))
		if not out.is_empty():
			var parsed: Variant = JSON.parse_string(out)
			if parsed is Dictionary:
				return {"status": int(parsed.get("status", 0)), "body": str(parsed.get("body", "")),
					"error": str(parsed.get("error", ""))}
			return {"status": 0, "body": "", "error": "Bad bridge response."}
	return {"status": 0, "body": "", "error": "Timed out."}


# Native (desktop/mobile builds): plain HTTPRequest, which works there.
# One node per request, freed afterwards, so requests can overlap.
func _transport_native(method: HTTPClient.Method, path: String, headers: Dictionary, body_text: String) -> Dictionary:
	var packed := PackedStringArray()
	for key in headers:
		packed.append("%s: %s" % [key, headers[key]])

	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)

	var err := req.request(base_url + path, packed, method, body_text)
	if err != OK:
		req.queue_free()
		return {"status": 0, "body": "", "error": "Couldn't start the request."}

	var raw: Array = await req.request_completed
	req.queue_free()
	if int(raw[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": "", "error": "Request failed (%d)." % int(raw[0])}
	return {"status": int(raw[1]), "body": (raw[3] as PackedByteArray).get_string_from_utf8(), "error": ""}


func _friendly_error(status: int, data: Variant) -> String:
	if data is Dictionary:
		var code := str(data.get("errorCode", ""))
		if ERROR_TEXT.has(code):
			return ERROR_TEXT[code]
		if data.has("message"):
			return str(data.message)
		# Validation failures come back as {errors: {field: [msgs]}}.
		if data.get("errors") is Dictionary:
			for field in data.errors:
				var msgs: Variant = data.errors[field]
				if msgs is Array and not msgs.is_empty():
					return str(msgs[0])
	return "Something went wrong (error %d)." % status
