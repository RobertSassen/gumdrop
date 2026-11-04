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
| Unlimited undo and restart | Real pictures in the cake (each pane takes its tray's flavor for now) |
| 12 flavors, one per tray in every level | Level select, progress saving |
| Game stops only when every cup is full and no cube can land | Twists (hidden cubes from level 41) |
| 30 levels on the difficulty schedule: tutorial, normal, hard and expert | |

### How the belt works

The belt never stops while cubes ride it, at one steady speed. A cube that
finds no home keeps going round until a tray takes it. Because the belt keeps
moving, *when* you tap can matter: it decides which tray a riding cube reaches
first.

The **cup tally** between the window cake and the board shows how many free
cups are left. Filled cups in the tally show the flavors riding the belt.

The game stops only when every cup is full and a full lap would land nothing.
A solver readout under the board says whether the board can still be finished.
It's there for testing and never stops the game; turn it off with
`solver.show_readout` in `tuning.json`.

## Tuning

Global values live in [`tuning.json`](tuning.json) at the project root. Edit it,
save, and press **T** in the running game to reload (this restarts the current
level). Any key you leave out falls back to its default in
`scripts/core/tuning.gd`, and each section has a `_notes` line explaining it.

| Section | Values | What they change |
| --- | --- | --- |
| `rules` | `tray_capacity`, `default_cups` | Cavities per tray, and cups for levels that don't set their own. These change every puzzle, so re-check levels with `tools/sim.py` after editing. |
| `loop` | `belt_speed_px_per_sec`, `riding_cube_gap_px` | How fast the belt runs, and how far apart cubes that left a tray together are drawn. |
| `feedback` | `wobble_seconds`, `wobble_px`, `wobble_speed` | The tray wobble when a tap can't send anything. |
| `solver` | `show_readout`, `max_boards`, `max_milliseconds` | The testing readout under the board and its budget. |
| `look` | `cube_size_px`, `riding_cube_scale`, `belt_width_px`, `arrow_spacing_px`, `flavors`, `colors` | Sizes and the whole palette, so color tests need no code. |

Per-level values (loop shape, direction, cups, trays) stay in the level files.
Screen layout positions stay in code, since they move with the art.

## Project layout

```
project.godot            Portrait 1080 × 1920, mobile renderer
tuning.json              Global game values (speeds, solver budget, palette)
scenes/game.tscn         The one screen
scripts/game.gd          Drawing, input, the moving belt, toolbar
scripts/core/
  board_state.gd         The rules: trays, cups, taps and the moving belt
  level.gd               Level loading and loop geometry (tray order, direction)
  solver.gd              Level check (patient player) and dead-end readout
  tuning.gd              Loads tuning.json, with defaults for missing keys
levels/*.json            Levels, loaded in file-name order
tests/run_tests.gd       Headless tests
tests/fixtures/          Move traces recorded by the Python model
tools/sim.py             Python copy of the rules, for checking and scoring levels
tools/build_levels.py    The level plan; builds levels/ to hit each level's difficulty band
tools/gen_level.py       Searches shuffles for solvable levels
tools/screenshot.gd      Saves a screenshot, optionally after some taps
```

## Level files

```json
{
 "title": "Duck pond",
 "customer": "The twins next door",
 "band": "normal",
 "casual_win_pct": 77,
 "direction": "ccw",
 "cups": 5,
 "cake_cols": 3,
 "loop": [[40, 160], [1040, 160], [1040, 1000], [40, 1000]],
 "trays": [
  {"pos": [238, 300], "facing": "left", "cubes": ["lime", "grape", "soda", "grape"]}
 ]
}
```

- Board coordinates are 1080 × 1080. List the loop's points **clockwise** on
  screen. `direction` sets which way cubes travel.
- `facing` is the side of the tray with the open end, toward the loop.
- `cubes` are listed **front first**, from the loop inward. Trays can hold fewer
  than four.
- Flavors: cherry, tangerine, lemon, lime, mint, soda, blueberry, grape,
  raspberry, cola, licorice, peach. Colors are in `tuning.json`.
- Optional `"riding": [{"flavor": "lime", "tray": 2}]` starts cubes in cups at a
  tray's stop.
- `band`, `lesson`, `casual_win_pct` and `random_win_pct` are notes for
  designers: the level's difficulty band, what a tutorial teaches, and how often
  the casual player and a random tapper won it when it was built. The game
  ignores them.
- Files are named `001_title.json`, `002_…`, and load in that order.

The order in which cubes pass the trays comes from projecting each tray's open
end onto the loop, so moving a tray along the loop changes the puzzle.

## Level plan and difficulty

Levels follow a difficulty schedule, measured with a **casual player**: a
simulated player in `tools/sim.py` that looks one tap ahead, prefers taps that
set a tray, then taps that leave the fewest cubes riding. Its win rate puts each
level in a band:

| Band | Casual player wins | Where it goes |
| --- | --- | --- |
| Tutorial | 90% or more | Levels 1 to 6, then about once every 40 levels as a breather |
| Normal | 60 to 90% | Every other level (the baseline) |
| Hard | 25 to 60% | From level 12, every 5th level (12, 17, 22…) |
| Expert | under 25% | From level 20, every 10th level |

Cups are the main dial and stay between 4 and 7: normal levels need about 5
cups at 6 trays, 6 at 9 to 10 trays and 7 at 11 to 12 trays, and one cup fewer
makes them hard. Never use 4 cups above 8 trays. Within a setup, a flavor that
sits on no tray's bottom row makes a level harder.

`tools/build_levels.py` holds the plan for every level (band, layout, cups,
direction, title, customer) and searches shuffles until the casual player's win
rate lands in the band, near its target:

```
python3 tools/build_levels.py          # rebuild every level
python3 tools/build_levels.py 12 17    # rebuild only levels 12 and 17
```

New flavors unlock a few at a time (6 at first, 8 from level 7, 10 from level 13,
all 12 from level 21), most distinct first, so look-alike pairs such as cherry
and raspberry arrive once the player knows the board.

### Tutorials

Levels 1 to 6 aren't shuffled. Each is a hand-picked board that teaches one
idea, kept in `TUTORIALS` in `tools/build_levels.py`:

| Level | Lesson | Taps | Random tapper wins |
| --- | --- | --- | --- |
| 1 | Tap and land: every tap sets a tray | 2 | 100% |
| 2 | Front runs: one tap sends the matching cubes together | 3 | 94% |
| 3 | The belt waits: trays start full, a cube rides until a spot opens | 5 | 90% |
| 4 | First tray that takes it: belt order, and empty trays take anything | 7 | 77% |
| 5 | Counterclockwise: the same board shape, the belt reversed | 8 | 63% |
| 6 | Graduation: six trays, five cups, the first level where Undo matters | 10 | 29% |

Taps are the fewest a level needs. Cubes that start on the belt (`riding`) let
levels 1 and 2 begin with a gap in a tray, so the very first tap lands and sets
a tray. They can't land until the player taps.

The casual player looks ahead, so it wins every tutorial. Tutorials get a second
check: a **random tapper**, who taps any tray and waits for the belt, stands in
for a new player trying things out. It has to win at least 95% of level 1, down
to 25% of level 6. Flavors arrive one or two at a time: cherry, lemon and
blueberry in level 1, lime in 2, grape in 4 and tangerine in 6.

## Tests

```
godot --headless --path . -s res://tests/run_tests.gd
```

The tests cover the belt and delivery rules, setting, getting stuck, clockwise
and counterclockwise ordering, and check that every level is solvable and uses
one flavor per tray. They also
replay random games recorded by `tools/sim.py` and fail if Godot and the Python
model ever disagree. After changing a rule in one, change the other and refresh
the fixtures:

```
python3 tools/sim.py levels/*.json                         # solvable? casual win rate?
python3 tools/sim.py --fixtures levels/*.json > tests/fixtures/traces.json
```

Screenshots without a phone (needs a display, or `xvfb-run` on Linux):

```
godot --path . --rendering-driver opengl3 --resolution 540x960 -s res://tools/screenshot.gd -- out.png 3 0 1 2
```

This opens level 4 (index 3), taps trays 0, 1 and 2, and saves `out.png`.

## Solver findings so far

With a belt that never stops, an exact search over every tap timing is far too
big. So there are two searches, each wrong only on the safe side:

- **Level check (patient player):** after every tap, let the belt run a full
  lap. Any solution it finds can really be played, so a level it passes is
  solvable. Every level passes; the biggest check needs about 400 boards.
- **Dead-end readout (relaxed player):** riding cubes may land in any tray that
  accepts them, whenever the player likes. When even that can't finish, the
  board is truly hopeless. It may notice some dead ends a few moves late.

Speed on this machine, in Godot: level checks take up to 0.3 s (about 400
boards), and the dead-end readout takes under 30 ms at the start of every level.
GDScript runs these searches about 2 to 3 times slower than Python.
