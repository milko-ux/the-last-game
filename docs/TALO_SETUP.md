# Talo setup — the one-time checklist

The game is fully wired for accounts and leaderboards, but it ships
"dark": until a real access key exists in `talo.cfg`, every
leaderboard button is hidden and the game behaves exactly as before.
This is the checklist that turns it on. It takes about 10 minutes and
happens once.

## 1. Create the Talo account and game

1. Go to <https://trytalo.com> and sign up (this is YOUR developer
   account, not a player account — use your normal email).
2. In the dashboard, create a new game. Name: `The Last Game`.

## 2. Create the access key

1. In the dashboard go to **Access keys** and create one.
2. Give it exactly these scopes (permissions):
   - `read:players`
   - `write:players`
   - `read:leaderboards`
   - `write:leaderboards`
3. Copy the key — it's shown once.

## 3. Create the six leaderboards

In **Leaderboards → Create**, make these six. The **internal name must
match exactly** (the game addresses boards by these names), the
display name is yours to choose.

| Internal name        | Sort mode | Unique entries | What it is |
|----------------------|-----------|----------------|------------|
| `progress-standard`  | Descending | Yes | Furthest level, Standard |
| `progress-hard`      | Descending | Yes | Furthest level, Hard |
| `progress-extreme`   | Descending | Yes | Furthest level, Extreme |
| `finishers-standard` | Ascending  | Yes | Fewest deaths to clear, Standard |
| `finishers-hard`     | Ascending  | Yes | Fewest deaths to clear, Hard |
| `finishers-extreme`  | Ascending  | Yes | Fewest deaths to clear, Extreme |

Why these settings matter:

- **Unique = Yes** means one entry per player. Talo only replaces a
  player's entry when the new score is BETTER, so nobody can wipe out
  their own best run.
- **Progress boards, Descending:** the score is packed as
  `level × 1000 + (999 − deaths)`, so a higher level always wins and
  fewer deaths breaks ties. A full clear is stored as level 31 —
  finishing beats dying on the last level. The game unpacks this for
  display; the dashboard shows the raw packed number, which is normal.
- **Finishers boards, Ascending:** the score is simply deaths on a
  winning run — fewest first. Only submitted when the loop is cleared.

## 3b. The endless run's board — `distance` (Phase E section 8, 2026-09-22)

The endless run posts ONE number, the furthest distance in metres, to
ONE board. The six boards above belong to the old level game and stay
as they are. This is the one to create now. Click by click:

1. Dashboard → **Leaderboards** → **Create leaderboard**.
2. **Internal name:** `distance` — exactly that, lower case. The game
   addresses the board by this name (`Talo.DISTANCE_BOARD`); a typo
   here means an empty board and no error anywhere.
3. **Display name:** anything, e.g. `Distance`.
4. **Sort mode:** **Descending** (a longer run ranks higher).
5. **Unique entries:** **Yes** (one entry per player; Talo replaces it
   only when the new run is better — the player cannot wipe their own
   best, and the game may post every run safely).
6. **Refresh interval:** **None / never.** (Talo can reset a board
   daily, weekly, monthly or yearly and archive the old entries. It
   exists, it is real — but seasons are NOT built on it yet; the season
   travels as a prop on each entry instead. Leave it off.)
7. Save. Nothing else — no props to declare up front: an entry's props
   (`season`, `country`, `laps`, `run_seconds`, `deaths`, `build`,
   `layout`) are sent with the entry and appear in the dashboard's
   entry view on their own.

Then, the check that it works end to end (I do this part): a throwaway
account registers, posts a distance, it appears under GLOBAL and under
its country, and deleting the account removes it. If the board name is
wrong, the very first post fails with a 404 and I will say so.

### The access key — is it safe to ship in a web build? (checked 2026-09-22)

Yes, as the key is scoped now. The verdict in plain language:

- **Talo's model IS that the key ships with the game.** Their Godot and
  Unity packages embed it in the client; there is no other way for a
  player's copy of the game to talk to Talo. The key identifies the
  GAME, not a person, and has no billing or admin power.
- **What our four scopes let a stranger who extracts the key do:** read
  the leaderboards (public anyway), look up players by name, register
  accounts (rate-limited), and post scores **as themselves**. What they
  **cannot** do: post as another player — Talo requires that player's
  session token (`x-talo-session`, "required for this player") for any
  action on a Talo-registered alias; delete anyone; read emails; see the
  dashboard; touch game settings.
- **What a key holder can still do, and always will:** register and post
  a made-up distance from outside the game. That is true of every
  client-submitted leaderboard on earth, not a Talo weakness. It is why
  every entry carries `laps`, `run_seconds`, `deaths`, `build` and
  `layout` from day one — the cheat check comes later, with prizes.
- **Nothing to change in the dashboard,** as long as the key has ONLY
  the four scopes in section 2. If you ever add `write:game-config`,
  `read:game-config`, `write:events` or anything broader, make a
  separate key for the tool that needs it and keep the game's key at
  four.

## 4. Put the key in the game

```bash
cp talo.cfg.example talo.cfg
```

Open `talo.cfg` and paste the access key between the quotes:

```
[talo]
access_key="PASTE-THE-KEY-HERE"
base_url="https://api.trytalo.com"
```

`talo.cfg` is gitignored on purpose — the repo is public, the key is
not. (The key does ship inside the exported web build; that's how
Talo is designed to work, and the scopes above are all it can do.)

**Both export presets now name `talo.cfg` in their `include_filter`**
("Web" and "Web (Phase R)"). `.cfg` is not a Godot resource, so the
exporter drops it silently unless it is named there — the build then
ships dark with no error anywhere (docs/TALO_GOTCHAS.md, item 2).

Then re-export the build and the leaderboard UI appears everywhere.

## What players see (and the GDPR story)

- Guests never touch the network. Nothing is sent anywhere until a
  player passes the consent screen AND creates an account.
- Registration needs only a name and password. **Email is optional**
  and only enables password recovery. No verification emails.
- Country is self-declared (guessed from the phone's language
  settings, editable, hideable). No geolocation, no IP lookups.
- Deleting the account in-game (Account → Delete) removes the account,
  login, and — confirmed with a real live test (2026-09-02: register →
  play → delete → recheck the dashboard) — its leaderboard entry too.
  That's the GDPR "right to erasure" path, self-serve. One nuance:
  Talo's public API has no dedicated endpoint to delete a leaderboard
  entry directly (only GET/POST exist on `/v1/leaderboards/:name/entries`),
  so the entry going away is a side effect of deleting the player's
  alias, not a deliberate step — and reads can lag a little afterward
  (a same-session recheck right after deletion once still showed the
  old entry; a later dashboard check showed it gone — looked like a
  short cache delay, not a real gap).
- The consent text lives in `ui/account_panel.gd` (`_draw_consent`).
  If it ever changes materially, bump `VERSION` in
  `autoload/consent.gd` — players who agreed to the old text will be
  asked again.

## Known gaps (deliberate, for later)

- **No "forgot password" screen yet.** Talo supports it (for accounts
  that gave an email), but the in-game UI isn't built. A player who
  forgets their password and gave no email loses that identity —
  they can just make a new one.
- **A privacy policy page** will be required for the App Store /
  Play Store listings in Phase 5. The consent screen covers in-game
  consent; the stores want a URL too.
- Talo also has a **profanity filter for player names** — turn it on
  in the dashboard under the game's settings if rude names show up.
