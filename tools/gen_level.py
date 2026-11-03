"""Searches random shuffles of a tray layout for solvable levels in a difficulty range.

Example:
    python3 tools/gen_level.py '{"tpl":"A","flavors":{"cherry":4,"lemon":4,"lime":8},"cups":4,"direction":"cw","want_min":4,"want_max":10,"easy":true}'

Prints the best match as a level JSON (add a title and customer by hand).
"""
import json, random, sys, time
from sim import Board, solve, analyze

def rect(x0, y0, x1, y1):
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]

def columns(rows, left_x=238, right_x=842):
    trays = []
    for y in rows:
        trays.append({"pos": [left_x, y], "facing": "left"})
        trays.append({"pos": [right_x, y], "facing": "right"})
    return trays

TEMPLATES = {
    "A": dict(loop=rect(40, 300, 1040, 860), trays=columns([440, 720])),
    "B": dict(loop=rect(40, 160, 1040, 1000), trays=columns([300, 580, 860])),
    "C": dict(loop=[[240, 40], [840, 40], [1040, 240], [1040, 840], [840, 1040], [240, 1040], [40, 840], [40, 240]],
              trays=[{"pos": [540, 230], "facing": "up"}] + columns([440, 640]) + [{"pos": [540, 850], "facing": "down"}]),
    "D": dict(loop=rect(40, 30, 1040, 1050), trays=columns([140, 340, 540, 740, 940])),
}

def make(tpl, flavors, cups, direction, seed):
    rnd = random.Random(seed)
    t = TEMPLATES[tpl]
    cubes = []
    for f, n in flavors.items():
        cubes += [f] * n
    rnd.shuffle(cubes)
    trays = []
    for i, tr in enumerate(t["trays"]):
        d = dict(tr)
        d["cubes"] = cubes[i * 4:(i + 1) * 4]
        trays.append(d)
    return {"loop": t["loop"], "direction": direction, "cups": cups, "trays": trays}

def search(tpl, flavors, cups, direction, want_min, want_max, tries=400, limit=400000, easy=False):
    best = None
    for seed in range(tries):
        lv = make(tpl, flavors, cups, direction, seed)
        b = Board(lv)
        if any(b.set):
            continue
        ok, n = solve(b, limit)
        if not ok:
            continue
        sh, states, dead, full = analyze(b, limit)
        if sh is None:
            continue
        if want_min <= sh <= want_max:
            score = dead / max(states, 1)
            if easy: score = -score
            if best is None or score > best[0]:
                best = (score, seed, sh, states, dead, full, n, lv)
    return best

if __name__ == "__main__":
    spec = json.loads(sys.argv[1])
    t0 = time.time()
    r = search(**spec)
    if r:
        score, seed, sh, states, dead, full, n, lv = r
        print(f"seed={seed} shortest={sh} states={states} stuck={dead} complete={full} dfs={n} ({time.time()-t0:.1f}s)")
        print(json.dumps(lv))
    else:
        print("none")
