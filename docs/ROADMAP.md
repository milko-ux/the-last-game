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

## 2. Native iPhone build (TestFlight) — NEXT (moved up on 2026-09-24)
The game ships as an app, so we test what players will actually run instead of Safari.
- **Milko:** sign up for the Apple Developer Program now (approval can take days).
- Code: Godot iOS export → Xcode → TestFlight. The same tests as step 1, but on the app.
- Once the app runs, the Safari build is only a quick-preview tool. Don't hunt Safari-only bugs any more.
- Android (Google Play closed testing) comes later, before step 6.

**Done when:** the game installs from TestFlight on Milko's iPhone and plays a full run at 60 fps.

## 3. Look, round 3
- Monoliths like the concept: tall, lighter, sparse, fading into fog, with carvings you can actually see.
- Character model v2: one tail, better walk and motion.
- The rules stay: colour meaning (magenta = kills, cyan = safe, amber = goal); the world is stone, clay and fog; glass and glow only in the UI; no AI images as textures.

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
- Later: character skins/outfits.
- Later: monthly sponsored leaderboard prizes (top 3 globally and top 3 per country) once there are players.
