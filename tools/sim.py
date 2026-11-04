"""Reference model of the jelly kitchen rules.

A line-for-line Python copy of scripts/core/board_state.gd and the loop
ordering in scripts/core/level.gd. Use it to check and design levels without
opening Godot:

    python3 tools/sim.py levels/*.json          # solvable? shortest? dead ends?
    python3 tools/sim.py --fixtures levels/*.json > tests/fixtures/traces.json

The fixtures are replayed by tests/run_tests.gd, so the two models can't drift
apart without a failing test.
"""
import json, random, sys, time
from collections import deque

FLAVORS = ["cherry", "tangerine", "lemon", "lime", "raspberry", "grape", "blueberry"]

import os

def _tuning():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tuning.json")
    try:
        return json.load(open(path))
    except FileNotFoundError:
        return {}

# Same source as the game: tuning.json at the project root.
CAP = int(_tuning().get("rules", {}).get("tray_capacity", 4))
DEFAULT_CUPS = int(_tuning().get("rules", {}).get("default_cups", 4))
FACING = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}
CELL = 76.0
TRAY_GAP = 6.0


def front_point(tray):
    x, y = tray["pos"]
    dx, dy = FACING[tray["facing"]]
    half = (CAP * CELL + TRAY_GAP * 2) / 2
    return (x + dx * half, y + dy * half)


def project(loop, p):
    best = None
    acc = 0.0
    n = len(loop)
    for i in range(n):
        a = loop[i]; b = loop[(i + 1) % n]
        ex, ey = b[0] - a[0], b[1] - a[1]
        l2 = ex * ex + ey * ey
        seg = l2 ** 0.5
        t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ex + (p[1] - a[1]) * ey) / l2))
        qx, qy = a[0] + ex * t, a[1] + ey * t
        d = (qx - p[0]) ** 2 + (qy - p[1]) ** 2
        if best is None or d < best[0] - 1e-9:
            best = (d, acc + seg * t)
        acc += seg
    return best[1]


def stop_order(level):
    dists = [project(level["loop"], front_point(t)) for t in level["trays"]]
    idx = list(range(len(dists)))
    idx.sort(key=lambda i: (dists[i], i))
    if level["direction"] == "ccw":
        idx.reverse()
    return idx


class Board:
    def __init__(self, level):
        self.cups = level.get("cups", DEFAULT_CUPS)
        self.order = stop_order(level)
        self.stop_of = [0] * len(self.order)
        for s, t in enumerate(self.order):
            self.stop_of[t] = s
        # tray cubes listed back..front (front is last)
        self.trays = [list(reversed(t["cubes"])) for t in level["trays"]]
        self.set = [False] * len(self.trays)
        self.riding = [(r["color"], self.stop_of[r["tray"]]) for r in level.get("riding", [])]
        for i in range(len(self.trays)):
            self._check_set(i)

    def copy(self):
        b = Board.__new__(Board)
        b.cups, b.order, b.stop_of = self.cups, self.order, self.stop_of
        b.trays = [list(t) for t in self.trays]
        b.set = list(self.set)
        b.riding = list(self.riding)
        return b

    def key(self):
        return (tuple(tuple(t) for t in self.trays), tuple(self.riding))

    def key_str(self):
        """Same format as BoardState.key() in Godot."""
        trays = "/".join("".join(chr(97 + FLAVORS.index(c)) for c in t) for t in self.trays)
        return trays + "|" + "".join(chr(97 + FLAVORS.index(c)) + str(p) + "," for c, p in self.riding)

    def free(self):
        return self.cups - len(self.riding)

    def accepts(self, t, c):
        tr = self.trays[t]
        return (not self.set[t]) and len(tr) < CAP and (len(tr) == 0 or tr[-1] == c)

    def _check_set(self, t):
        tr = self.trays[t]
        if len(tr) == CAP and all(c == tr[0] for c in tr):
            self.set[t] = True

    def can_tap(self, t):
        return (not self.set[t]) and len(self.trays[t]) > 0 and self.free() > 0

    def tap(self, t):
        tr = self.trays[t]
        c = tr[-1]
        run = 0
        for x in reversed(tr):
            if x != c:
                break
            run += 1
        k = min(run, self.free())
        for _ in range(k):
            tr.pop()
            self.riding.append((c, self.stop_of[t]))
        n = len(self.order)
        cubes = [[c2, p, True] for (c2, p) in self.riding]
        for _ in range(n):
            for cube in cubes:
                if not cube[2]:
                    continue
                cube[1] = (cube[1] + 1) % n
                tt = self.order[cube[1]]
                if self.accepts(tt, cube[0]):
                    self.trays[tt].append(cube[0])
                    self._check_set(tt)
                    cube[2] = False
        self.riding = [(c2, p) for (c2, p, alive) in cubes if alive]

    def won(self):
        return all(self.set)

    def moves(self):
        return [t for t in range(len(self.trays)) if self.can_tap(t)]


def solve(board, limit=2_000_000):
    """DFS: returns (solvable or None if limit hit, states visited)."""
    seen = set()
    stack = [board]
    while stack:
        b = stack.pop()
        if b.won():
            return True, len(seen)
        k = b.key()
        if k in seen:
            continue
        seen.add(k)
        if len(seen) > limit:
            return None, len(seen)
        for m in reversed(b.moves()):
            nb = b.copy(); nb.tap(m)
            if nb.key() not in seen:
                stack.append(nb)
    return False, len(seen)


def analyze(board, limit=3_000_000):
    """BFS over the full reachable space: shortest solution, states, dead-end states."""
    seen = {board.key(): 0}
    q = deque([(board, 0)])
    shortest = None
    dead = 0
    while q:
        b, d = q.popleft()
        if b.won():
            if shortest is None:
                shortest = d
            continue
        ms = b.moves()
        if not ms:
            dead += 1
        for m in ms:
            nb = b.copy(); nb.tap(m)
            k = nb.key()
            if k not in seen:
                seen[k] = d + 1
                q.append((nb, d + 1))
                if len(seen) > limit:
                    return shortest, len(seen), dead, False
    return shortest, len(seen), dead, True


def fixtures(paths, walks=3, length=30):
    """Random legal tap sequences per level, with the board key after each tap."""
    out = []
    for path in paths:
        lv = json.load(open(path))
        for w in range(walks):
            rnd = random.Random(w)
            b = Board(lv)
            taps, keys = [], []
            for _ in range(length):
                ms = b.moves()
                if not ms:
                    break
                m = rnd.choice(ms)
                b.tap(m)
                taps.append(m); keys.append(b.key_str())
            out.append({"level": path.split("/")[-1], "start": Board(lv).key_str(), "taps": taps, "keys": keys})
    return out


if __name__ == "__main__":
    if sys.argv[1] == "--fixtures":
        print(json.dumps(fixtures(sys.argv[2:]), indent=1))
        sys.exit(0)
    for path in sys.argv[1:]:
        lv = json.load(open(path))
        b = Board(lv)
        t0 = time.time(); ok, n = solve(b); t1 = time.time()
        sh, states, dead, full = analyze(b, 200_000)
        print(f"{path}: order={b.order} solvable={ok} dfs_states={n} ({(t1-t0)*1000:.1f} ms) shortest={sh} reachable={states} stuck_states={dead} complete={full}")
