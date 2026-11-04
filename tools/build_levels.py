"""Builds the level files in levels/ from the level plan below.

Every level has a difficulty band, a tray layout, a cup count and a belt
direction. For each one the script tries shuffles until it finds one that

  - starts with no tray already set,
  - the patient solver can finish within the board budget the Godot test allows
    comfortably, and
  - the casual player (tools/sim.py) wins as close as possible to the band's
    target, and inside the band.

The bands and targets come from the difficulty study ("Jelly Kitchen: what makes
a level hard"):

    tutorial   90% or more casual wins
    normal     60 to 90%
    hard       25 to 60%
    expert     under 25%

The schedule follows the progression plan: levels 1 to 6 are tutorials, from
level 12 every 5th level is hard (12, 17, 22, ...), and from level 20 every 10th
level is expert. Everything else is normal. Cups stay between 4 and 7.

The tutorials are not shuffled. Each is a hand-picked board that teaches one
idea (see TUTORIALS below), and the build only checks it.

    python3 tools/build_levels.py              # rebuild every level
    python3 tools/build_levels.py 12 17        # rebuild only these levels
"""
import json, os, random, sys, time
from multiprocessing import Pool

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sim import Board, solve, casual_win_rate, random_win_rate, CAP

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LEVEL_DIR = os.path.join(ROOT, "levels")

BANDS = {
    #          low   high  target
    "tutorial": (0.90, 1.01, 1.00),
    "normal":   (0.60, 0.90, 0.75),
    "hard":     (0.25, 0.60, 0.42),
    "expert":   (0.05, 0.25, 0.15),
}

# Flavors join the palette a few at a time, most distinct first. Look-alike
# pairs (cherry and raspberry, lime and mint, soda and blueberry, tangerine and
# peach) arrive later, once the player knows the board.
FLAVOR_ORDER = ["cherry", "lemon", "blueberry", "lime", "grape", "tangerine",
                "soda", "raspberry", "mint", "cola", "peach", "licorice"]
FLAVOR_POOL = [(1, 6), (7, 8), (13, 10), (21, 12)]  # (from level, flavors available)

# ---------------------------------------------------------------------------
# Layouts. Board coordinates are 1080 x 1080. Side trays sit in two columns
# with their open ends 40 px from the belt; vertical trays sit along the top
# (facing up) or bottom (facing down). "oct" cuts the loop's corners.

LEFT_X, RIGHT_X = 238, 842
HALF = (CAP * 76 + 12) / 2  # half a tray's length: 158 px


def make_layout(kind, top, bottom, rows=(), top_xs=(), bottom_xs=(), cake_cols=None):
    if kind == "rect":
        loop = [[40, top], [1040, top], [1040, bottom], [40, bottom]]
    else:
        c = 200
        loop = [[40 + c, top], [1040 - c, top], [1040, top + c], [1040, bottom - c],
                [1040 - c, bottom], [40 + c, bottom], [40, bottom - c], [40, top + c]]
    trays = []
    for x in top_xs:
        trays.append({"pos": [x, int(top + 40 + HALF)], "facing": "up"})
    for y in rows:
        trays.append({"pos": [LEFT_X, y], "facing": "left"})
        trays.append({"pos": [RIGHT_X, y], "facing": "right"})
    for x in bottom_xs:
        trays.append({"pos": [x, int(bottom - 40 - HALF)], "facing": "down"})
    n = len(trays)
    if cake_cols is None:
        cake_cols = {3: 3, 4: 2, 5: 3, 6: 3, 7: 4, 8: 4, 9: 3, 10: 5}.get(n, (n + 1) // 2)
    return {"loop": loop, "trays": trays, "cake_cols": cake_cols}


LAYOUTS = {
    # 3 trays: one along the top, one each side.
    "tri":       make_layout("rect", 330, 850, rows=[700], top_xs=[540]),
    # 4 trays
    "rect4":     make_layout("rect", 300, 860, rows=[440, 720]),
    "oct4":      make_layout("oct", 140, 940, rows=[540], top_xs=[540], bottom_xs=[540]),
    # 5 trays
    "rect5":     make_layout("rect", 160, 1000, rows=[520, 800], top_xs=[540]),
    "wide5":     make_layout("rect", 80, 1000, top_xs=[240, 540, 840], bottom_xs=[390, 690]),
    # 6 trays
    "rect6":     make_layout("rect", 160, 1000, rows=[300, 580, 860]),
    "oct6":      make_layout("oct", 40, 1040, rows=[440, 640], top_xs=[540], bottom_xs=[540]),
    "wide6":     make_layout("rect", 100, 980, top_xs=[240, 540, 840], bottom_xs=[240, 540, 840]),
    # 7 trays
    "rect7":     make_layout("rect", 160, 1000, rows=[420, 640, 860], top_xs=[540]),
    "oct7":      make_layout("oct", 40, 1040, rows=[340, 540, 740], top_xs=[540]),
    # 8 trays
    "rect8":     make_layout("rect", 50, 990, rows=[190, 410, 630, 850]),
    "oct8":      make_layout("oct", 40, 1040, rows=[340, 540, 740], top_xs=[540], bottom_xs=[540]),
    "wide8":     make_layout("rect", 60, 1020, top_xs=[165, 395, 625, 855], bottom_xs=[165, 395, 625, 855]),
    # 9 trays
    "rect9":     make_layout("rect", 30, 1050, rows=[270, 480, 690, 900], top_xs=[540]),
    "wide9":     make_layout("rect", 60, 1020, rows=[540], top_xs=[165, 395, 625, 855], bottom_xs=[240, 540, 840]),
    # 10 trays
    "rect10":    make_layout("rect", 30, 1050, rows=[140, 340, 540, 740, 940]),
    "wide10":    make_layout("rect", 60, 1020, rows=[540], top_xs=[165, 395, 625, 855], bottom_xs=[165, 395, 625, 855]),
}

# ---------------------------------------------------------------------------
# The plan: (band, layout, cups, direction, title, customer[, target]).
# The first normal levels after the tutorial aim a little gentler (80%).

PLAN = [
    ("tutorial", "tri",    5, "cw",  "A lemon sun",            "Mrs. Pell, the florist"),
    ("tutorial", "rect4",  5, "cw",  "Two tulips",             "Theo from the bike shop"),
    ("tutorial", "rect4",  5, "cw",  "Garden gate",            "Grandma Rosa"),
    ("tutorial", "rect5",  5, "cw",  "Bluebird on a branch",   "The twins next door"),
    ("tutorial", "rect5",  5, "ccw", "Spring kite",            "Coach Lin"),
    ("tutorial", "rect6",  5, "cw",  "Strawberry patch",       "Juniper, the mail carrier"),
    ("normal",   "wide5",  5, "cw",  "Rainy-day boots",        "Mr. Okafor, the librarian", 0.80),
    ("normal",   "rect6",  5, "ccw", "Duck pond",              "The twins next door", 0.80),
    ("normal",   "oct6",   5, "cw",  "Cherry blossom",         "Grandma Rosa", 0.80),
    ("normal",   "rect7",  5, "ccw", "Picnic blanket",         "Theo from the bike shop", 0.80),
    ("normal",   "wide6",  5, "cw",  "Butterfly wings",        "Dr. Hale, the vet", 0.80),
    ("hard",     "oct7",   5, "cw",  "Bike race trophy",       "Theo from the bike shop"),
    ("normal",   "rect6",  5, "cw",  "Robin's nest",           "Mrs. Pell, the florist"),
    ("normal",   "rect8",  6, "ccw", "Lemonade stand",         "The twins next door"),
    ("normal",   "rect7",  5, "cw",  "Spring rainbow",         "The school choir"),
    ("normal",   "wide8",  6, "cw",  "Hopscotch",              "Coach Lin"),
    ("hard",     "oct8",   5, "ccw", "Library mural",          "Mr. Okafor, the librarian"),
    ("normal",   "oct7",   5, "ccw", "Seed packets",           "Mrs. Pell, the florist"),
    ("normal",   "rect8",  6, "cw",  "Puddle jumper",          "Juniper, the mail carrier"),
    ("expert",   "rect5",  4, "ccw", "Grand opening sign",     "The mayor's office"),
    ("normal",   "oct8",   6, "cw",  "Kitten in a basket",     "Dr. Hale, the vet"),
    ("hard",     "rect7",  5, "ccw", "Market awning",          "Bea from the cheese stall"),
    ("normal",   "rect9",  6, "cw",  "Paper boats",            "The twins next door"),
    ("normal",   "wide8",  6, "ccw", "Orchard in bloom",       "Grandma Rosa"),
    ("normal",   "wide9",  6, "ccw", "Choir robes",            "The school choir"),
    ("normal",   "rect8",  6, "cw",  "Sunday bunting",         "The mayor's office"),
    ("hard",     "wide8",  5, "cw",  "Clock tower",            "Mr. Okafor, the librarian"),
    ("normal",   "rect9",  6, "ccw", "Fruit basket",           "Bea from the cheese stall"),
    ("normal",   "wide10", 6, "cw",  "Parade float",           "Coach Lin"),
    ("expert",   "wide9",  5, "cw",  "Spring festival window", "The mayor's office"),
]

# ---------------------------------------------------------------------------
# Tutorials. Levels 1 to 6 are hand-picked boards, each teaching one idea. They
# were found by searching gently scrambled boards for one whose best solution
# shows the lesson, and are checked here on every build:
#
#   - the casual player wins at least 90% (the tutorial band),
#   - a random tapper wins at least `random_min`, so a new player who taps
#     around to see what happens still gets through, and
#   - cubes that start on the belt can't land until the player taps.
#
# Flavors arrive one or two at a time: cherry, lemon and blueberry in level 1,
# lime in 2, grape in 4 and tangerine in 6. Cubes are listed front first.
# "riding" cubes start in cups at that tray's stop; they let a tray start with a
# gap, so a tap can land and set a tray straight away.

C, L, B, G, P, T = "cherry", "lemon", "blueberry", "lime", "grape", "tangerine"

TUTORIALS = {
    1: dict(lesson="Tap and land: a tap sends the front cube to the tray that matches, "
                   "and four of a kind sets. Every tap sets a tray (2 taps).",
            random_min=0.95,
            trays=[[C, C, C], [C, L, L, L], [L, B, B, B]],
            riding=[{"flavor": B, "tray": 1}]),
    2: dict(lesson="Front runs: one tap sends every matching cube at the front, and they "
                   "land together (3 taps).",
            random_min=0.90,
            trays=[[L, L, C, C], [L, L], [C, B, B, B], [B, G, G, G]],
            riding=[{"flavor": C, "tray": 1}, {"flavor": G, "tray": 2}]),
    3: dict(lesson="The belt waits: every tray starts full, so the first cube rides "
                   "round in a cup until a tap opens a spot for it (5 taps).",
            random_min=0.85,
            trays=[[L, L, G, L], [B, G, G, G], [L, C, C, C], [C, B, B, B]]),
    4: dict(lesson="First tray that takes it: a cube lands in the first tray along the "
                   "belt that accepts it, and an empty tray takes anything (7 taps).",
            random_min=0.70,
            trays=[[L, L, L, P], [P, P, P, L], [B, C, C, C], [B, B, B, G], [C, G, G, G]]),
    5: dict(lesson="Counterclockwise: the same board shape with the belt running the "
                   "other way, so the order of the trays flips (8 taps).",
            random_min=0.55,
            trays=[[P, L, L, L], [C, B, B, B], [G, G, L, G], [P, C, C, C], [P, G, B, P]]),
    6: dict(lesson="Graduation: six trays and five cups. Careless taps can fill every "
                   "cup, so this is the first level where Undo matters (10 taps).",
            random_min=0.25,
            trays=[[B, C, C, C], [B, L, L, B], [B, P, P, P], [T, T, G, L], [C, G, G, G],
                   [P, T, T, L]]),
}

SOLVE_LIMIT = 150_000   # boards; the Godot test allows 1,000,000
QUICK_GAMES = 16
FINAL_GAMES = 80
REPORT_GAMES = 400      # fresh games for the casual_win_pct note, so picking the
                        # shuffle closest to target doesn't flatter the number
TRIES = 80


def flavors_for(level_no, n, rnd):
    """Picks n flavors from the palette unlocked so far. A level that unlocks
    new flavors always uses them."""
    size = max(s for start, s in FLAVOR_POOL if level_no >= start)
    pool = FLAVOR_ORDER[:size]
    new = []
    if level_no in [start for start, _ in FLAVOR_POOL]:
        prev = max([s for start, s in FLAVOR_POOL if start < level_no] + [0])
        new = pool[prev:]
    rest = [f for f in pool if f not in new]
    rnd.shuffle(rest)
    chosen = (new + rest)[:n]
    rnd.shuffle(chosen)
    return chosen


def make_level(level_no, spec, seed):
    band, layout_name, cups, direction, title, customer = spec[:6]
    layout = LAYOUTS[layout_name]
    rnd = random.Random(level_no * 100_000 + seed)
    n = len(layout["trays"])
    flavors = flavors_for(level_no, n, rnd)
    cubes = [f for f in flavors for _ in range(CAP)]
    rnd.shuffle(cubes)
    trays = []
    for i, tr in enumerate(layout["trays"]):
        trays.append(dict(tr, cubes=cubes[i * CAP:(i + 1) * CAP]))
    return {"title": title, "customer": customer, "band": band, "direction": direction,
            "cups": cups, "cake_cols": layout["cake_cols"], "loop": layout["loop"], "trays": trays}


def flavor_changes(level):
    return sum(1 for t in level["trays"] for a, b in zip(t["cubes"], t["cubes"][1:]) if a != b)


def build_tutorial(level_no, spec):
    band, layout_name, cups, direction, title, customer = spec[:6]
    tut = TUTORIALS[level_no]
    layout = LAYOUTS[layout_name]
    lv = {"title": title, "customer": customer, "band": band, "lesson": tut["lesson"],
          "direction": direction, "cups": cups, "cake_cols": layout["cake_cols"], "loop": layout["loop"],
          "trays": [dict(tr, cubes=c) for tr, c in zip(layout["trays"], tut["trays"])]}
    if tut.get("riding"):
        lv["riding"] = tut["riding"]
    b = Board(lv)
    low = BANDS[band][0]
    problems = []
    if any(b.set):
        problems.append("a tray starts set")
    if b.copy().advance(b.L):
        problems.append("a riding cube lands before the first tap")
    ok, boards, _ = solve(b, SOLVE_LIMIT)
    if not ok:
        problems.append("not solvable")
    casual = casual_win_rate(b, REPORT_GAMES, 999)
    if casual < low:
        problems.append(f"casual player wins only {casual:.0%}")
    rand = random_win_rate(b, 400, 999)
    if rand < tut["random_min"]:
        problems.append(f"random tapper wins only {rand:.0%}, below {tut['random_min']:.0%}")
    lv["casual_win_pct"] = round(casual * 100)
    lv["random_win_pct"] = round(rand * 100)
    if problems:
        return level_no, None, "tutorial board fails its checks: " + "; ".join(problems)
    return level_no, lv, f"hand-picked, casual {casual:.0%}, random tapper {rand:.0%}, solver {boards} boards"


def build_one(args):
    level_no, spec = args
    if level_no in TUTORIALS:
        return build_tutorial(level_no, spec)
    band = spec[0]
    low, high, target = BANDS[band]
    if len(spec) > 6:
        target = spec[6]
    best = None
    t0 = time.time()
    for seed in range(TRIES):
        lv = make_level(level_no, spec, seed)
        b = Board(lv)
        if any(b.set):
            continue
        quick = casual_win_rate(b, QUICK_GAMES, seed)
        if quick < low - 0.15 or quick > high + 0.15:
            continue
        ok, boards, _ = solve(b, SOLVE_LIMIT)
        if not ok:
            continue
        win = casual_win_rate(b, FINAL_GAMES, seed + 1)
        if not (low <= win <= high):
            continue
        # Closest to the target; tutorials also prefer less mixing, so they stay short.
        score = (abs(win - target), flavor_changes(lv) if band == "tutorial" else 0, boards)
        if best is None or score < best[0]:
            best = (score, seed, win, boards, lv)
        if band != "tutorial" and abs(win - target) <= 0.03:
            break
    if best is None:
        return level_no, None, f"no shuffle in band after {TRIES} tries"
    score, seed, win, boards, lv = best
    report = casual_win_rate(Board(lv), REPORT_GAMES, 999)
    lv["casual_win_pct"] = round(report * 100)
    warn = "" if low <= report <= high else f", WARNING: {report:.0%} over {REPORT_GAMES} games is outside the band"
    return level_no, lv, (f"seed {seed}, casual {report:.0%}, solver {boards} boards, "
                          f"{time.time() - t0:.0f}s{warn}")


def slug(title):
    keep = "".join(c.lower() if c.isalnum() else "_" for c in title)
    while "__" in keep:
        keep = keep.replace("__", "_")
    return keep.strip("_")


def write_level(level_no, lv):
    key_order = ["title", "customer", "band", "lesson", "casual_win_pct", "random_win_pct", "direction",
                 "cups", "cake_cols", "loop", "trays", "riding"]
    lines = ["{"]
    body = []
    for k in key_order:
        if k not in lv:
            continue
        if k == "loop" or k == "riding":
            body.append(f' "{k}": {json.dumps(lv[k])}')
        elif k == "trays":
            trays = ",\n".join("  " + json.dumps(t) for t in lv["trays"])
            body.append(' "trays": [\n' + trays + "\n ]")
        else:
            body.append(f" {json.dumps(k)}: {json.dumps(lv[k])}")
    lines.append(",\n".join(body))
    lines.append("}")
    os.makedirs(LEVEL_DIR, exist_ok=True)
    path = os.path.join(LEVEL_DIR, f"{level_no:03d}_{slug(lv['title'])}.json")
    for old in os.listdir(LEVEL_DIR):
        if old.startswith(f"{level_no:03d}_") and old.endswith(".json"):
            os.remove(os.path.join(LEVEL_DIR, old))
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return path


if __name__ == "__main__":
    wanted = [int(a) for a in sys.argv[1:]] or list(range(1, len(PLAN) + 1))
    jobs = [(n, PLAN[n - 1]) for n in wanted]
    with Pool() as pool:
        for level_no, lv, note in pool.imap_unordered(build_one, jobs):
            if lv is None:
                print(f"level {level_no:3d}: FAILED, {note}")
                continue
            path = write_level(level_no, lv)
            print(f"level {level_no:3d} {lv['band']:8s} {len(lv['trays']):2d} trays {lv['cups']} cups: "
                  f"{os.path.basename(path)} ({note})", flush=True)
