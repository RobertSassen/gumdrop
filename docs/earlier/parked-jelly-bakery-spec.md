# Gumdrop's jelly bakery: core mechanic spec

Nov 3, 2026 · @Robert

The player taps jelly jars to pour cubes onto a conveyor that circles the cake mold, and each cube drops into the mold row that needs its color next. The challenge is that the conveyor only has so many slots.

## The pieces

Four pieces make up every level; nothing else is needed for the first chapters.

| Piece | What it does | In Gumdrop's world |
| --- | --- | --- |
| Jars | Stacks of jelly cubes, all colors visible from the start. Tapping a jar pours its top cube onto the conveyor. | Jelly pots lined up on the counter below the mold |
| Conveyor | A loop of fixed slots that circles the mold and carries cubes past every row. It has a set number of slots per level. | A little candy-factory belt with cups, ticking round gently |
| Mold rows | The picture, cut into horizontal rows. Each row needs a sequence of colors and shows the next one it wants. | Lanes of the cake mold, each with a small chute facing the belt |
| Ramekins | A few spare spots off the belt where one cube can wait. The base game gives none or one; boosts add more. | Small dishes on the counter beside the belt |

Each jelly color is a fruit flavor with its own small icon (cherry, tangerine, lemon, lime, raspberry, grape, blueberry). The icon makes colors readable for color-blind players and fits the bakery theme.

## How a move works

The player's only real decision is which jar to tap next. Everything after the tap happens on its own.

1. The player taps a jar. Its top cube pours into the next free conveyor slot. If every slot is full, the jar wobbles and nothing happens.
2. The conveyor carries the cube around the mold. As it passes a row's chute, it drops in if that row's next color matches.
3. A cube that matches no row keeps circling. Nothing is ever lost, so waiting never costs anything.
4. When a drop finishes a color run, the row asks for its next color, which may let another circling cube drop on its next pass. Chains like this are the main source of satisfaction.
5. When the board settles (no cube can drop on this lap), the player taps again. A fast-forward button lets impatient players skip the wait.
6. The level ends when every row is full. The jelly sets glossy, the cake slides out of the mold, and the picture is revealed.

Because the belt is a loop and no cube is ever lost, the exact timing of taps never changes the outcome. The logical state is just: what is left in each jar, which colors are on the belt, and how far each row has filled. That keeps the game free of time pressure and makes levels easy to solve by computer.

One tie-break rule keeps this true: when two rows want the same color, the cube always goes to the topmost of them, wherever it is on the belt. Without that rule, where the cube happened to be would decide which row it fed.

## Picture format

One cube fills one color run in a row, not one pixel. A run is a stretch of the same color, and the jelly flows along to fill it, which looks lovely and keeps the cube count manageable.

Example row, filled left to right: three blue cells, then two white, then four blue. That row needs three cubes in order: blueberry, then coconut (white), then blueberry.

- **Grid size:** about 8 x 8 for the first levels, up to about 16 x 16 for late pictures. Pictures stay bold and simple, like Art Puzzle's cut-out shapes.
- **Fill direction:** every row fills from the side nearest its chute, so the next color needed is always obvious.
- **Colors per level:** 3 to 4 early, up to 7 late.
- **Cubes per level:** about 15 to 25 early, 60 to 90 for the hardest levels.
- **Authoring:** a level is a small image plus a jar layout. A tool can convert the image into rows of runs automatically, so the work is in arranging the jars.

## Space and difficulty

Difficulty comes almost entirely from how much room the player has, in line with pillar 4. New rules arrive rarely, at most one per chapter.

| Lever | Easier | Harder |
| --- | --- | --- |
| Conveyor slots | Many slots, e.g. 10 | Few slots, e.g. 4 |
| Ramekins | 1 or 2 | None |
| Jar depth | Shallow jars, wanted colors near the top | Deep jars, wanted colors buried under others |
| Rows wanting the same color | Few, so cubes have one obvious home | Several, so the tie-break order matters |
| Colors in play | 3 to 4 | 6 to 7 |

The core skill is reading ahead: which jar to open now so that the cubes underneath come out when a row is ready for them, without clogging the belt in the meantime.

Occasional extra rules for later chapters, each one a simple twist on the same loop:

- **Frosted jars:** colors below the top are hidden until they reach the top. Use sparingly, since it bends pillar 1.
- **Locked rows:** a row opens only after the row above it is finished.
- **Twin cubes:** one tap pours two cubes at once, which eats belt space fast.

## Dead ends, undo and boosts

The game checks after every tap whether the level can still be finished, and says so straight away when it can't.

- **What counts as a dead end:** not only a jammed belt, but any position from which no sequence of taps can finish the picture. A small solver runs in the background after each tap to check this. Because the logical state is small (jars, belt contents, row progress), this is fast enough on a phone for the planned level sizes.
- **How it looks:** the conveyor slows to a stop, Gumdrop scratches its head over the recipe card, and a gentle line appears: "This batch can't be finished from here." Two buttons: Undo and Start over. No failure sound, no lost progress.
- **Undo:** unlimited and free, back to the start of the level. It is the main help the game offers.
- **Boosts (buy room, never show answers):** an extra ramekin for this level; a wider belt with two more slots for this level; a spatula that lifts one cube off the belt and puts it back into any jar top. None of them tells the player what to tap.

The warning comes on the first tap that makes the level unsolvable, not only once the player is fully stuck, because the pillar says straight away.

## Pillar check

Every rule above passes all six pillars; frosted jars are the one place to stay careful.

| Pillar | How the spec meets it |
| --- | --- |
| 1. Clever, not lucky | All jar contents are visible and fixed. The tie-break rule means timing never changes the result. |
| 2. No time pressure | The belt loops forever and never drops a cube. No timers, move limits or lives. |
| 3. Progress you can see | Every drop fills a run of the picture, and chains fill several at once. |
| 4. Space is the challenge | The main levers are belt slots, ramekins and jar depth. New rules come at most once per chapter. |
| 5. No hints, no skips | Help is only undo and room-buying boosts. |
| 6. Honest dead ends | A background solver flags an unsolvable position on the tap that causes it. |

## Open questions for Robert

These are the choices that most change how the game feels. The spec above uses the first answer in each case, and the prototype in step 2 can test the alternatives.

- [ ] **One cube per color run, or one cube per cell?** Runs keep cube counts low and pictures detailed. Cells feel more like classic sorting but make big pictures slow.
- [ ] **Does the belt keep moving, or advance only after a tap?** Continuous movement looks alive; tap-driven steps feel more like a board game.
- [ ] **Are ramekins part of the base board or only a boost?** Base ramekins make early levels kinder; boost-only makes them feel special.
- [ ] **Tie-break when two rows want the same color: topmost row, or nearest chute?** Topmost is predictable; nearest feels more physical but makes timing matter.
- [ ] **Should players see the whole picture faintly before they start?** A faint outline helps them plan; a hidden picture makes the reveal a surprise.
