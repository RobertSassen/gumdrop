"""Reference model of the jelly kitchen rules.

A line-for-line Python copy of scripts/core/board_state.gd and the loop
geometry in scripts/core/level.gd. Use it to check and design levels without
opening Godot:

    python3 tools/sim.py levels/*.json          # solvable? how many taps? casual win rate?
    python3 tools/sim.py --fixtures levels/*.json > tests/fixtures/traces.json

The fixtures are replayed by tests/run_tests.gd, so the two models can't drift
apart without a failing test.

The belt never stops. Positions are whole pixels along the belt, measured in
the direction of travel. A riding cube is [flavor, position, next stop]. Time
only matters through the order in which cubes reach trays, so the fixtures
use "wait until the next cube reaches a tray" as a move next to the taps.
"""
import json, math, os, random, sys, time

FLAVORS = ["cherry", "tangerine", "lemon", "lime", "mint", "soda", "blueberry",
           "grape", "raspberry", "cola", "licorice", "peach"]
WAIT = -1


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
TRAY_PAD = 6.0


def iround(x):
    return int(math.floor(x + 0.5))


def front_point(tray):
    x, y = tray["pos"]
    dx, dy = FACING[tray["facing"]]
    half = (CAP * CELL + TRAY_PAD * 2) / 2
    return (x + dx * half, y + dy * half)


def loop_length(loop):
    n = len(loop)
    return sum(math.dist(loop[i], loop[(i + 1) % n]) for i in range(n))


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
        if best is None or d < best[0] - 1e-6:
            best = (d, acc + seg * t)
        acc += seg
    return best[1]


def geometry(level):
    """Returns (belt length, tray order, stop positions) in travel coordinates."""
    L = iround(loop_length(level["loop"]))
    u = []
    for t in level["trays"]:
        d = iround(project(level["loop"], front_point(t))) % L
        u.append(d if level["direction"] != "ccw" else (L - d) % L)
    order = sorted(range(len(u)), key=lambda i: (u[i], i))
    return L, order, [u[t] for t in order]


class Board:
    def __init__(self, level):
        self.cups = level.get("cups", DEFAULT_CUPS)
        self.L, self.order, self.stop_u = geometry(level)
        self.stop_of = [0] * len(self.order)
        for s, t in enumerate(self.order):
            self.stop_of[t] = s
        # tray cubes listed back..front (front is last)
        self.trays = [list(reversed(t["cubes"])) for t in level["trays"]]
        self.set = [False] * len(self.trays)
        self.riding = []
        n = len(self.order)
        for r in level.get("riding", []):
            s = self.stop_of[r["tray"]]
            self.riding.append([r["flavor"], self.stop_u[s], (s + 1) % n])
        for i in range(len(self.trays)):
            self._check_set(i)

    def copy(self):
        b = Board.__new__(Board)
        b.cups, b.L, b.order, b.stop_u, b.stop_of = self.cups, self.L, self.order, self.stop_u, self.stop_of
        b.trays = [list(t) for t in self.trays]
        b.set = list(self.set)
        b.riding = [list(r) for r in self.riding]
        return b

    def key(self):
        return (tuple(tuple(t) for t in self.trays), tuple(tuple(r) for r in self.riding))

    def key_str(self):
        """Same format as BoardState.key() in Godot."""
        trays = "/".join("".join(chr(97 + FLAVORS.index(c)) for c in t) for t in self.trays)
        return trays + "|" + "".join("%s%d:%d," % (chr(97 + FLAVORS.index(f)), u, s) for f, u, s in self.riding)

    def free(self):
        return self.cups - len(self.riding)

    def accepts(self, t, c):
        tr = self.trays[t]
        return (not self.set[t]) and len(tr) < CAP and (len(tr) == 0 or tr[-1] == c)

    def _check_set(self, t):
        tr = self.trays[t]
        if not self.set[t] and len(tr) == CAP and all(c == tr[0] for c in tr):
            self.set[t] = True
            return True
        return False

    def can_tap(self, t):
        return (not self.set[t]) and len(self.trays[t]) > 0 and self.free() > 0

    def tap(self, t):
        """Puts the front run on the belt at the tray's stop. Nothing lands yet."""
        tr = self.trays[t]
        c = tr[-1]
        run = 0
        for x in reversed(tr):
            if x != c:
                break
            run += 1
        k = min(run, self.free())
        s = self.stop_of[t]
        for _ in range(k):
            tr.pop()
            self.riding.append([c, self.stop_u[s], (s + 1) % len(self.order)])
        return k

    def gap(self, r):
        return (self.stop_u[r[2]] - r[1]) % self.L

    def advance(self, px):
        """Moves the belt px pixels. Returns [(flavor, tray)] for each landing, in order."""
        landed = []
        n = len(self.order)
        guard = 0
        while self.riding and guard < 100000:
            guard += 1
            g = min(self.gap(r) for r in self.riding)
            if g > px:
                for r in self.riding:
                    r[1] = (r[1] + px) % self.L
                break
            for r in self.riding:
                r[1] = (r[1] + g) % self.L
            px -= g
            keep = []
            for r in self.riding:
                if r[1] == self.stop_u[r[2]]:
                    t = self.order[r[2]]
                    r[2] = (r[2] + 1) % n
                    if self.accepts(t, r[0]):
                        self.trays[t].append(r[0])
                        self._check_set(t)
                        landed.append((r[0], t))
                        continue
                keep.append(r)
            self.riding = keep
        return landed

    def wait(self):
        """Moves the belt until the next cube reaches a tray."""
        if self.riding:
            self.advance(min(self.gap(r) for r in self.riding))

    def won(self):
        return all(self.set)

    def stuck(self):
        """No free cups and a full lap of the belt lands nothing."""
        if self.won() or self.free() > 0:
            return False
        return not self.copy().advance(self.L)

    def moves(self):
        ms = [WAIT] if self.riding else []
        if self.free() > 0:
            ms += [t for t in range(len(self.trays)) if self.can_tap(t)]
        return ms

    def play(self, m):
        if m == WAIT:
            self.wait()
        else:
            self.tap(m)


def solve(board, limit=2_000_000):
    """Patient-player search: after every tap, let the belt run one full lap.

    Any solution found this way can really be played (just wait for the belt
    to come round between taps), so True means the level is solvable. It may
    miss solutions that need quick taps, so False only means "not solvable
    for a patient player". Returns (True/False/None if the limit was hit,
    boards visited, taps in the found solution).
    """
    seen = set()
    stack = [(board, 0)]
    while stack:
        b, taps = stack.pop()
        if b.won():
            return True, len(seen), taps
        k = b.key()
        if k in seen:
            continue
        seen.add(k)
        if len(seen) > limit:
            return None, len(seen), 0
        moves = [t for t in range(len(b.trays)) if b.can_tap(t)]
        for m in reversed(moves):
            nb = b.copy(); nb.tap(m); nb.advance(nb.L)
            if nb.key() not in seen:
                stack.append((nb, taps + 1))
    return False, len(seen), 0


def _patient_step(board, t):
    nb = board.copy(); nb.tap(t); nb.advance(nb.L)
    return nb


def casual_game(board, rnd, cap=200):
    """One game by the casual player, the difficulty yardstick for level design.

    The casual player looks one tap ahead and plays patiently. It prefers a tap
    that sets a tray, then one that leaves the fewest cubes riding, and avoids
    boards it has already seen. It never taps a tray whose cubes would only ride
    a lap and drop straight back in. Returns True if it wins.
    """
    b = board.copy()
    seen = {b.key()}
    for _ in range(cap):
        if b.won():
            return True
        options = []
        for t in range(len(b.trays)):
            if not b.can_tap(t):
                continue
            nb = _patient_step(b, t)
            if nb.key() == b.key():
                continue
            options.append((nb.key() in seen, -sum(nb.set), len(nb.riding), rnd.random(), t, nb))
        if not options:
            return False
        b = min(options)[-1]
        seen.add(b.key())
    return False


def casual_win_rate(board, games=40, seed=0):
    """Share of games the casual player wins. Difficulty bands (see README):
    tutorial 0.90 and up, normal 0.60 to 0.90, hard 0.25 to 0.60, expert under 0.25."""
    rnd = random.Random(seed)
    return sum(casual_game(board, rnd) for _ in range(games)) / games


def random_win_rate(board, games=200, seed=0, cap=150):
    """Share of games won by a random tapper: someone who taps any tray that can
    send, then waits for the belt to come round. It's the forgiveness check for
    tutorials, where a new player still taps around to see what happens."""
    rnd = random.Random(seed)
    wins = 0
    for _ in range(games):
        b = board.copy()
        for _ in range(cap):
            if b.won() or b.stuck():
                break
            moves = [t for t in range(len(b.trays)) if b.can_tap(t)]
            if not moves:
                break
            b = _patient_step(b, rnd.choice(moves))
        wins += b.won()
    return wins / games


def fixtures(paths, walks=3, length=60):
    """Random legal move sequences per level, with the board key after each move."""
    out = []
    for path in paths:
        lv = json.load(open(path))
        for w in range(walks):
            rnd = random.Random(w)
            b = Board(lv)
            moves, keys = [], []
            for _ in range(length):
                ms = b.moves()
                if not ms:
                    break
                m = rnd.choice(ms)
                b.play(m)
                moves.append(m); keys.append(b.key_str())
            out.append({"level": os.path.basename(path), "start": Board(lv).key_str(), "moves": moves, "keys": keys})
    return out


if __name__ == "__main__":
    if sys.argv[1] == "--fixtures":
        print(json.dumps(fixtures(sys.argv[2:]), indent=1))
        sys.exit(0)
    for path in sys.argv[1:]:
        lv = json.load(open(path))
        b = Board(lv)
        t0 = time.time(); ok, n, taps = solve(b, 3_000_000); t1 = time.time()
        cw = casual_win_rate(b, 200)
        print(f"{path}: order={b.order} solvable={ok} boards={n} ({(t1-t0)*1000:.0f} ms) "
              f"taps_in_found_solution={taps} casual_win={cw:.0%}")
