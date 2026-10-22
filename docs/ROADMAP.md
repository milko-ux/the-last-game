# The Last Game — Roadmap to launch

Agreed with Milko: 2026-09-24/29. This is the one plan every session works from, in Cowork and in Claude Code.
- Current state and the next task: "Where we are" in `prototype/README.md`
- The old August roadmap (Phases 0–6) predates the endless-run pivot and is replaced by this one.

**Rule:** finish a step's "done when" before starting the next step. Small fixes can happen anywhere. New features wait for their step.

---

## 1. Stable and fast — DONE 2026-09-29
The web test build must be reliable, so the testing isn't fighting the tools.
- Understand the glitch on `?autoplay=1&kill_bar=6&kill_count=20` and `?probe=1`. The black box now reports to the Mac (`blackbox.log`).
- Cut the load time. The phone showed 12–15 s at the last test (engine file 37.7 MB + game data 26.5 MB, sent uncompressed).
- Set the graphics defaults from the `?probe=1` table.

**Done when:**
- no crash or glitch on the phone
- the normal run holds about 16.7 ms (60 fps)
- the load time is known, and cut where it's cheap

**Result (the phone, 2026-09-29, over the hotspot):**
- The glitch was a clock bug, not the phone: with no tap, iOS never runs the audio mix, and the clock landed every rewind ~10 s too far. Fixed (`2154b2f`). The 20-death link, `?probe=1` and a run from the menu: no storm, no context loss, every session ended cleanly.
- Load: the download is 22.7 MB instead of 64 MB (gzip + the song MP3s out of the pack). Downloads finished at 0.6–1.8 s instead of 8.5–12.6 s; first frame 2.3–4.2 s instead of 7.3–13.5 s; the menu is up at 4.1 s instead of 14.2 s.
- Graphics defaults from the probe table (all on 19.5 ms, glow off 16.9): glow off, everything else on. The run from the menu before that change read 16.7–18.4 ms; the next normal run is the first reading with glow off.

## 2. Native iPhone build (TestFlight) — DONE 2026-10-15
The game ships as an app, so we test what players will actually run instead of Safari.
- **Milko:** sign up for the Apple Developer Program now (approval can take days).
- Code: Godot iOS export → Xcode → TestFlight. The same tests as step 1, but on the app.
- Once the app runs, the Safari build is only a quick-preview tool. Don't hunt Safari-only bugs any more.
- Android (Google Play closed testing) comes later, before step 6.

**Rule:** Before the FIRST upload to App Store Connect / TestFlight, STOP and ask Milko to confirm the final bundle ID — confirmed 2026-10-15: `se.karrot.thelastgame`, one iOS preset, cable builds use it too. If App Store Connect refuses it, STOP and tell Milko before switching to the fallback `se.karrot.lastgame`. The first upload locks the bundle ID forever.

**Done when:** the game installs from TestFlight on Milko's iPhone and plays a full run at 60 fps.

**Result (2026-10-15):** build 0.8.0 (0.8.0), bundle ID `se.karrot.thelastgame`, App Store Connect name "The Last Game by KARROT" ("The Last Game" was taken), uploaded as **TestFlight Internal Only** (it carries the debug engine: the dev readout and look switch). Installed from TestFlight on Milko's iPhone: **16.7 ms throughout a run**, nothing different from the cable app. The app runs the Compatibility renderer (OpenGL ES 3.0, 2026-10-04) and is capped at 60 fps (2026-10-06). Android is still to come, before step 6.

## 3. Look, round 3
- The monolith canyon (concept D, `STEP_3_BRIEF_2_CANYON.md`, Milko's pick 2026-10-21 — it replaced "monoliths like the grey concept"): sky, cloud sea, cream floor, pastel mesas with trees, warm light. Built and approved on the phone 2026-10-21 ("We are really getting close now!! YES!").
- Character model v2: one tail, better walk and motion. **One tail and the brighter lavender done 2026-10-21** (Milko picked `docs/concept/hero/C_bright_lilac.jpg`); the 1 km scarf built (the first unlock; the menu shows it as a teaser). Still open: the better walk and motion.
- The rules stay: colour meaning (magenta = kills, cyan = safe, amber = goal); the world is stone, clay, cloud and haze; glass and glow only in the UI; no AI images as textures.
- The time of day changes with the run (morning → sunset → night → dawn, one day per 950 m; `prototype/time_of_day.gd`) — Milko's answer to "world zones per lap". Built 2026-10-21.

**Done when:** Milko would post a screenshot of a normal frame.

## 4. Feel and UI
- Sound effects: jump, land, death, near-miss, shield charge and shield use, menu clicks.
- The main menu styled like the approved mockup: Start Game, Leaderboard, Settings, Nickname, Register.
- Clay hearts for lives.
- A readable leaderboard (global and per country).
- Pressed and disabled states on buttons.
- Settings: sound and music on/off, and vibration if we add it.

**Done when:** every screen looks designed, and every action has a sound.

## 5. The share screen
The roast-style death/run-over screen people want to post. It's how the game spreads for free.
- Distance, best, a roast line, and a screenshot moment.
- A share button that opens the phone's own share sheet (image + link).

**Done when:** a friend who has never seen the game shares their result without being asked.

## 6. Soft launch
- TestFlight (and Android closed testing) with 20–50 people outside the team.
- Measure whether they come back the next day and the next week.
- Fix what they hit.
- Store pages: icon, screenshots, a short video, privacy policy. GDPR consent is already built.
- Before release: `Progress.UNLOCK_ALL = false`, bump the version, keep the MCP plugin off.

**Done when:** testers keep coming back, and there are no known crashes.

## 7. Launch, then money
- App Store + Google Play release.
- Rewarded video ads only, **never on death**.
- Later: character skins/outfits — the scarf (`prototype/scarf.gd`, 1 km) is the first item and the slot outfits use; some earned by distance, some bought.
- **Options discussed 2026-10-21, to decide at soft launch with real player numbers** (the rule above stands until then): a "watch an ad to continue" once per run; a "remove ads" or supporter purchase; occasional interstitials only with limits (never before a session's first run, never on day one, at most one per ~3 game overs, never after a new best). Milko asked about a short ad before every run and after every game over; Code advised against (the top reason players delete runners; ad length is the network's, 5–30 s, not 3–5).
- Later: monthly sponsored leaderboard prizes (top 3 globally and top 3 per country) once there are players.
- **The crown item: a golden top hat for the top 3 of the leaderboard, lost when you drop out of the top 3** (Milko, 2026-10-22). The scarf is the distance prize; the hat is the leaders' prize. Before it is built, the leaderboard needs a server-side plausibility check — today it trusts whatever the phone posts (a phone call carried a run to a fake 1097 m on 2026-10-22, fixed in `4154376`), and a prize only three people can hold is the first thing cheaters aim at. Every entry already carries `run_seconds` for that check. To decide when it is built: global or per country, and how often the top 3 is read (Talo caches listings 600 s).
