# Gumdrop's Jelly Kitchen

A cozy loop-sorting puzzle for phones. Jelly cubes ride a conveyor loop around a
rack of **setting trays**. A tray sets when it holds four cubes of one flavor, and
every tray that sets becomes one pane of the customer's window cake.

This repository holds the **Godot proof of concept**. It tests the core rules and
the dead-end solver, drawn in the approved look: glossy jelly on mint silicone
trays, a cream conveyor with coral rails, all on an oak kitchen table. The design
lives in the spec doc, *Gumdrop's Jelly Kitchen: core mechanic spec*.

## Running it

1. Install **Godot 4.7.2** or newer (standard build, no .NET needed).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5**. The window opens at 40% size in portrait (432 × 936; the game
   screen is 1080 × 2340, a modern phone).

Click a tray to send its front run of same-flavor cubes onto the loop. The
buttons at the bottom are **Spare** (the ramekin boost, not in the PoC yet),
**Undo** and **Restart**. The pause button at the top left opens a menu for the
next and previous level; **Page Down** and **Page Up** do the same. After a win,
tap anywhere for the next order.

## What the PoC covers

| In | Not yet |
| --- | --- |
| Tap a tray, whole front run leaves, cubes ride and drop into the first tray that takes them | Press-and-hold landing preview |
| Clockwise and counterclockwise loops, a different loop shape per level | Boosts (the Spare button is there but does nothing yet) |
| Trays set, panes fill in the window cake, win screen | Gumdrop, the shop, sound |
| Unlimited undo and restart | Real pictures in the cake (each pane takes its tray's flavor for now) |
| 12 flavors, one per tray in every level | Level select, progress saving |
| Game stops only when every cup is full and no cube can land | Twists (hidden cubes from level 41) |
| 30 levels on the difficulty schedule: tutorial, normal, hard and expert | |

### How the belt works

The belt never stops while cubes ride it, at one steady speed. A cube that
finds no home keeps going round until a tray takes it. Because the belt keeps
moving, *when* you tap can matter: it decides which tray a riding cube reaches
first.

The **Free cups** pill between the window cake and the board shows one cup
per cup on the loop: white cups are free, faded cups hold a riding cube. Only
cups with a cube are drawn on the belt.

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
| `look` | `cube_size_px`, `riding_cube_scale`, `jelly_gloss`, `belt_width_px`, `rail_width_px`, `belt_corner_radius_px`, `arrow_spacing_px`, `flavors`, `colors` | Sizes, the belt's shape and the whole palette. Jelly art is white and is tinted with `flavors` at startup, so color tests need no new art. |

Per-level values (loop shape, direction, cups, trays) stay in the level files.
Screen layout positions stay in code, since they move with the art.

## Art

Everything you see is in `art/`: the oak table, the corner dressing (mint,
lemon, strawberries), the order card, the buttons, and sprites for trays, cups
and jelly. The pictures are rendered by `tools/art/`, so the look can be changed
in one place and rendered again:

```
cd tools/art
npm install
npx playwright install chromium
node render.js        # writes ../../art/*.png
```

`sprites.js` builds the 3D sprites with three.js (trays, cups, jelly cubes, set
slabs and the table), and `ui.html` holds the flat pieces as HTML and CSS. Jelly
comes out in three white layers (shadow, body, gloss) that the game tints with
each flavor's color. The font is Fredoka (SIL Open Font License, in
`art/fonts/`).

The drawn belt rounds the loop's corners; the rules still use the level's
sharp loop, and cups near a corner are moved onto the curve only when drawn.

## Project layout

```
project.godot            Portrait 1080 × 2340, mobile renderer
tuning.json              Global game values (speeds, solver budget, palette)
scenes/game.tscn         The one screen
scripts/game.gd          Drawing, input, the moving belt, buttons and pause menu
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
tools/screenshot.gd      Saves a full-size screenshot, optionally after some taps
tools/art/               Renders the pictures in art/ (Node, three.js, Playwright)
art/                     Sprites, background, UI pieces and the font
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
- Levels always start with an empty belt, so every tray starts with four
  cubes. (The loader still reads an optional `"riding"` list of cubes that start
  in cups, but no level may use it, and the tests check that.)
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
| Tutorial | 90% or more | Levels 1 to 4, then about once every 40 levels as a breather |
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

New flavors unlock a few at a time (6 at first, 8 from level 5, 10 from level 13,
all 12 from level 21), most distinct first, so look-alike pairs such as cherry
and raspberry arrive once the player knows the board.

### Tutorials

Levels 1 to 4 aren't shuffled. Each is a hand-picked board that teaches one
idea, kept in `TUTORIALS` in `tools/build_levels.py`:

| Level | Lesson | Taps | Random tapper wins |
| --- | --- | --- | --- |
| 1 | Tap and land: the first cube waits, then every tap sets a tray | 3 | 100% |
| 2 | Front runs: one tap sends the matching cubes together | 4 | 86% |
| 3 | Counterclockwise: the belt runs the other way | 8 | 63% |
| 4 | Graduation: six trays, five cups, the first level where Undo matters | 10 | 29% |

Taps are the fewest a level needs. Because the belt starts empty and every tray
starts full, the first cube a player sends can never land straight away: it
rides until a later tap opens a spot. Level 1 makes that the whole lesson, and
from its second tap on, every tap sets a tray.

The casual player looks ahead, so it wins every tutorial. Tutorials get a second
check: a **random tapper**, who taps any tray and waits for the belt, stands in
for a new player trying things out. It has to win at least 95% of level 1, down
to 25% of level 4. Flavors arrive one or two at a time: cherry, lemon and
blueberry in level 1, lime in 2, grape in 3 and tangerine in 4.

## Tests

```
godot --headless --path . -s res://tests/run_tests.gd
```

The tests cover the belt and delivery rules, setting, getting stuck, clockwise
and counterclockwise ordering. They check that every level is solvable, uses
one flavor per tray and starts with an empty belt. They also replay random games recorded by `tools/sim.py` and fail if Godot and the Python
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
