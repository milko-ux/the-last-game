#!/usr/bin/env python3
"""Validates levels.json.  Run:  python3 tools/check_levels.py

Checks, in order of how much pain each one has already caused:

1. FAIR SPAWNS — nothing lethal parked on the player the instant a level
   loads. Seven levels were doing this before it was measured.
2. AVOIDABLE HAZARDS — a level whose shortest route to the goal never
   goes near any hazard is just a walk. Level 19 shipped like that:
   pillars and blinkers guarding a corridor nobody needed to enter.
3. Solvability, pit runs you cannot jump, hazards buried in walls.
"""
import json, sys, math, collections, os

LEVELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "levels.json")

MIN_SPAWN_CLEAR = 3.0    # tiles, anything already on the board
MIN_CHASER_CLEAR = 6.0   # chasers home in, so they need more room
MIN_ORBIT_CLEAR = 1.6    # a chain's whole RING must miss the spawn
THREAT_RANGE = 2.2       # a hazard this far from the route is doing nothing
MAX_PIT_RUN = 2          # jump airtime covers about 3 tiles


def spawn_points(h):
    t = h["type"]
    if t in ("patrol", "sweep"): return [tuple(h["a"])]
    if t == "blinker":           return [tuple(h["at"])]
    if t == "chaser":            return [tuple(h["start"])]
    if t == "chain":
        px, py = h["pivot"]; r = h.get("radius", 2.0); n = h.get("arms", 1)
        return [(px + r * math.cos(2 * math.pi * i / n),
                 py + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return []


def dist_to_region(p, h):
    """Closest a player at tile p can be to anywhere this hazard travels."""
    t = h["type"]
    if t == "blinker":
        return math.dist(p, tuple(h["at"]))
    if t in ("patrol", "sweep"):
        a, b = h["a"], h["b"]
        ax, ay = a; bx, by = b
        vx, vy = bx - ax, by - ay
        L2 = vx * vx + vy * vy
        if L2 == 0:
            return math.dist(p, (ax, ay))
        s = max(0.0, min(1.0, ((p[0] - ax) * vx + (p[1] - ay) * vy) / L2))
        return math.dist(p, (ax + s * vx, ay + s * vy))
    if t == "chain":
        return abs(math.dist(p, tuple(h["pivot"])) - h.get("radius", 2.0))
    return 0.0   # chaser follows you anywhere; never "avoidable"


def shortest_path(grid, start, goal):
    H, W = len(grid), len(grid[0])
    prev = {start: None}
    q = collections.deque([start])
    while q:
        c, r = q.popleft()
        if (c, r) == goal:
            break
        for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (c + dc, r + dr)
            if 0 <= n[0] < W and 0 <= n[1] < H and n not in prev and grid[n[1]][n[0]] != "#":
                prev[n] = (c, r); q.append(n)
    if goal not in prev:
        return None
    path, cur = [], goal
    while cur:
        path.append(cur); cur = prev[cur]
    return path


def check(entry):
    grid = entry["grid"]; errs = []; warns = []
    flat = "".join(grid)
    if flat.count("P") != 1: errs.append(f"{flat.count('P')} start points")
    if flat.count("G") != 1: errs.append(f"{flat.count('G')} goals")
    if flat.count("C") > 1:  errs.append("more than one coin")

    H, W = len(grid), len(grid[0])
    start = goal = None
    for r in range(H):
        for c in range(W):
            if grid[r][c] == "P": start = (c, r)
            if grid[r][c] == "G": goal = (c, r)
    if not (start and goal):
        return errs, warns

    path = shortest_path(grid, start, goal)
    if path is None:
        errs.append("goal unreachable from start")

    for r in range(H):
        run = 0
        for c in range(W):
            run = run + 1 if grid[r][c] == "O" else 0
            if run > MAX_PIT_RUN:
                errs.append(f"horizontal pit run > {MAX_PIT_RUN} at row {r}"); break
    for c in range(W):
        run = 0
        for r in range(H):
            run = run + 1 if grid[r][c] == "O" else 0
            if run > MAX_PIT_RUN:
                errs.append(f"vertical pit run > {MAX_PIT_RUN} at col {c}"); break

    threatening = 0
    non_chaser = 0
    for h in entry["hazards"]:
        for key in ("a", "b", "pivot", "start", "at"):
            if key in h:
                c, r = h[key]
                if not (0 <= c < W and 0 <= r < H):
                    errs.append(f"{h['type']}.{key} off grid")
                elif grid[r][c] == "#":
                    errs.append(f"{h['type']}.{key} inside a wall at [{c},{r}]")

        need = MIN_CHASER_CLEAR if h["type"] == "chaser" else MIN_SPAWN_CLEAR
        for (x, y) in spawn_points(h):
            d = math.hypot(x - start[0], y - start[1])
            if d < need:
                errs.append(f"{h['type']} spawns {d:.2f} tiles from player (need {need})")
        if h["type"] == "chain":
            gap = abs(math.hypot(h["pivot"][0] - start[0], h["pivot"][1] - start[1])
                      - h.get("radius", 2.0))
            if gap < MIN_ORBIT_CLEAR:
                errs.append(f"chain ring passes {gap:.2f} tiles from spawn (need {MIN_ORBIT_CLEAR})")

        if h["type"] != "chaser" and path:
            non_chaser += 1
            closest = min(dist_to_region(p, h) for p in path)
            if closest <= THREAT_RANGE:
                threatening += 1
            else:
                warns.append(f"{h['type']} is {closest:.1f} tiles off the route — decorative")

    if non_chaser and threatening == 0:
        errs.append("NOTHING guards the route — the level is a straight walk")

    return errs, warns


def main() -> None:
    data = json.load(open(LEVELS))
    bad = 0
    for i, e in enumerate(data["levels"], 1):
        errs, warns = check(e)
        if errs or warns:
            print(f"L{i:2d} {e['name']}")
            for m in errs:
                bad += 1; print(f"      ERROR  {m}")
            for m in warns:
                print(f"      warn   {m}")
    print(f"\n{len(data['levels'])} levels, {bad} errors")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
