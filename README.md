# Gumdrop's Jelly Kitchen

A cozy loop-sorting puzzle for phones. Jelly cubes ride a conveyor loop around a
rack of **setting trays**. A tray sets when it holds four cubes of one flavor, and
every tray that sets becomes one pane of the customer's window cake.

This repository holds the **Godot proof of concept**. It tests the core rules and
the dead-end solver with plain shapes and no art. The design lives in the spec
doc, *Gumdrop's Jelly Kitchen: core mechanic spec*.

## Running it

1. Install **Godot 4.7.2** or newer (standard build, no .NET needed).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5**. The window opens at half size in portrait (540 × 960).

Click a tray to send its front run of same-flavor cubes onto the loop. Use the
toolbar for Undo, Restart and switching levels.

## What the PoC covers

| In | Not yet |
| --- | --- |
| Tap a tray, whole front run leaves, cubes ride and drop into the first tray that takes them | Press-and-hold landing preview |
| Clockwise and counterclockwise loops, a different loop shape per level | Boosts (ramekin, extra cup) |
| Trays set, panes fill in the window cake, win screen | Gumdrop, the shop, sound, real art |
| Unlimited undo and restart; taps during animation are queued | Real pictures in the cake (each pane takes its tray's flavor for now) |
| Dead ends: "stuck" right away, "unsolvable" from the solver, with timing shown | Level select, progress saving |

### One rule the spec left open

A cube that rides a full lap without landing **waits in its cup where it
started**. On every later tap the whole loop runs one more lap, so waiting cubes
get another chance to land. This keeps "the loop only moves when you tap" from
the no-time-pressure pillar.

## Project layout

```
project.godot            Portrait 1080 × 1920, mobile renderer
scenes/game.tscn         The one screen
scripts/game.gd          Drawing, input, animation, toolbar
scripts/core/
  board_state.gd         The rules: trays, cups, tap and delivery
  level.gd               Level loading and loop geometry (tray order, direction)
  solver.gd              Dead-end check: depth-first search over all boards
levels/*.json            Levels, loaded in file-name order
tests/run_tests.gd       Headless tests
tests/fixtures/          Move traces recorded by the Python model
tools/sim.py             Python copy of the rules, for checking levels
tools/gen_level.py       Searches shuffles for solvable levels
```

## Level files

```json
{
 "title": "Plum sunset",
 "customer": "Theo from the bike shop",
 "direction": "ccw",
 "cups": 3,
 "cake_cols": 3,
 "loop": [[40, 160], [1040, 160], [1040, 1000], [40, 1000]],
 "trays": [
  {"pos": [238, 300], "facing": "left", "cubes": ["lime", "grape", "grape", "grape"]}
 ]
}
```

- Board coordinates are 1080 × 1080. List the loop's points **clockwise** on
  screen. `direction` sets which way cubes travel.
- `facing` is the side of the tray with the open end, toward the loop.
- `cubes` are listed **front first**, from the loop inward. Trays can hold fewer
  than four.
- Flavors: cherry, tangerine, lemon, lime, raspberry, grape, blueberry.
- Optional `"riding": [{"flavor": "lime", "tray": 2}]` starts cubes in cups at a
  tray's stop.

The order in which cubes pass the trays comes from projecting each tray's open
end onto the loop, so moving a tray along the loop changes the puzzle.

## Tests

```
godot --headless --path . -s res://tests/run_tests.gd
```

The tests cover the delivery rules, setting, dead ends, clockwise and
counterclockwise ordering, and check that every level is solvable. They also
replay random games recorded by `tools/sim.py` and fail if Godot and the Python
model ever disagree. After changing a rule in one, change the other and refresh
the fixtures:

```
python3 tools/sim.py levels/*.json                         # solvable? shortest? dead ends?
python3 tools/sim.py --fixtures levels/*.json > tests/fixtures/traces.json
```

## Solver findings so far

The spec named the solver as the main technical risk. From the Python model:

- Boards with 4 to 6 trays are trivial: a full search takes a few milliseconds.
- With 10 trays, 4 cups is easy for the solver (hundreds of boards), but 3 cups
  is a cliff. Most random 10-tray, 3-cup mixes are unsolvable, and proving that
  takes 20,000 to 250,000+ boards, which is seconds in Python. The game runs the
  solver on a worker thread with a 300,000-board and 3-second budget and says
  "gave up" when it runs out, rather than calling a dead end it can't prove.

Watch the solver line under the board on a real phone. If tough levels are slow,
the next steps are caching boards already proven dead and treating riding cubes
at the same stop as interchangeable to shrink the search.
