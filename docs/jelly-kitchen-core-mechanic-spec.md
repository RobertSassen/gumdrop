# Gumdrop's Jelly Kitchen: core mechanic spec

Nov 3, 2026 · @Robert

## Summary

Jelly only sets when a tray holds four cubes of one flavor. That one kitchen fact turns your storage lanes into **setting trays**. It also explains why the player sorts.

Gumdrop's kitchen has a rack of setting trays with a small conveyor loop running around it. The player has one action: tap a tray to send its front cubes onto the loop. Depending on the level, they ride clockwise or counterclockwise and drop into the first tray that will take them. When a tray holds four cubes of one flavor, it sets glossy and becomes one pane of the customer's window cake. The level is won when every tray has set and the cake picture is complete.

The only scarce thing is free cups on the loop. That is where the puzzle lives.

## Why the first setting didn't fit

The first version treated rows as parts of the picture, so placing a color meant painting the image. Loop-sort play is about sorting a mix until each lane is pure, and where a lane sits has no link to the picture. The picture also needs uneven amounts of each color, while lanes always need exactly four of one.

The fix is to split the screen into two places with one link between them:

- **The kitchen board** is where the sorting happens. It has trays, the loop and cubes, and nothing on it is part of the picture.
- **The window cake** is where results land. Each tray that sets fills one pane of the picture, so sorting well visibly builds the cake.

The shop, Gumdrop, the customers, the seasons and the candy palette all carry over unchanged.

## Setting map

Every piece of the mechanic is something you would find on a jelly maker's counter.

| Mechanic term | In Gumdrop's kitchen | Why it makes sense |
| --- | --- | --- |
| Storage lane (4 spots) | Setting tray: a silicone mold with four cube cavities in a row, open at one end | Mixed flavors bleed together and won't set clean, so a tray only sets when all four cubes match |
| Lane completed | The tray sets: it jiggles, turns glossy, and Gumdrop slides a name card under it | The squish-then-gloss moment is the reward for every finished tray |
| Colors | Jelly flavors: cherry, tangerine, lemon, lime, raspberry, grape, blueberry | Seven flavors cover the full palette, and each has a clear name for colorblind support |
| The belt | The loop: a small conveyor around the tray rack, carrying cubes in little silicone cups | Cubes visibly travel and plop into trays, which is the tactile core of the game |
| Free space | Empty cups on the loop | You can see your remaining room at a glance by counting empty cups |
| The picture | The window cake: the customer's order, a stained-glass picture made of jelly panes | Each set tray fills one pane, so progress shows above the board |
| Dead end | The loop stops and Gumdrop scratches its head over the recipe card | Says plainly that this mix can't be finished, with no blame |
| Room boost | A ramekin on the counter that holds one cube off the loop | The holding space from the first concept, now a boost instead of a rule |
| Level | One customer order | Finished cakes go in the shop window and new regulars start dropping by |
| Chapter | A menu season (spring fruits, summer sodas, autumn spice, winter festival) | The shop interior upgrades as you go |

I considered two other looks for the lanes. Jam jars on a shelf read well as a stack, but jars suggest pouring liquid rather than moving cubes. Piping bags fit a bakery but don't show four separate spots clearly. Setting trays show four clear cavities and give the strongest reason to sort.

## Core rules

The player has one action, tapping a tray. Everything after the tap follows fixed rules, so the same tap from the same board always gives the same result.

**Setup**

1. A level has a number of trays, each with 4 cavities, and a loop with a fixed number of cups.
2. Each flavor appears in a multiple of 4 cubes, and the total number of cubes equals 4 × the number of trays.
3. At the start, trays hold mixed cubes. A few cubes may already be riding the loop, which leaves the same number of cavities empty.
4. A tray is a stack. Only its front cube, at the open end facing the loop, can leave or be covered.

**A move**

1. The player taps a tray that is not set and not empty.
2. Its front run leaves the tray. The front run is the front cube plus any cubes of the same flavor directly behind it.
3. Each cube needs a free cup. If there are fewer free cups than cubes in the run, only as many leave as there are free cups. If there are no free cups, the tray wobbles and nothing happens.

**Delivery**

1. Riding cubes travel in the level's direction, clockwise or counterclockwise, and check each tray they pass. Arrows on the loop show the direction.
2. A tray accepts a cube if it has an empty cavity, is not set, and its front cube is the same flavor or it is empty.
3. The cube drops into the first tray that accepts it. Its own tray is checked last, after a full lap.
4. A cube that completes a lap without being accepted stays in its cup and keeps riding. It drops in later, as soon as it passes a tray that accepts it.

**Setting and winning**

1. A tray with 4 cubes of one flavor sets at once. It is locked and its pane fills in the window cake.
2. The level is won when every tray has set. The loop is then empty and the picture is complete.

**Timing never matters**

The loop runs only to deliver cubes, and it rests once every cube has landed or completed a lap. Logic resolves the whole move before animation plays, so tapping fast or slow gives the same board. Taps made during animation are queued.

**Seeing where cubes will go**

Pressing and holding a tray shows a dotted path to where each cube in its front run will land, or a ring around the loop if it will keep riding. Releasing outside the tray cancels the move. This shows the rules, not the solution, so it fits the no-hints pillar.

## Screen layout

The top third shows what you're making, and the rest is the board you play on. Everything is in thumb reach on a portrait phone.

&#91;embedded content: portrait phone layout · order zone, board, toolbar\]

The loop's shape changes from level to level. It is always one closed path, and every tray's open end faces it. The drawing shows the simplest shape, with two columns of trays inside a rounded loop. Ten trays is the most a phone screen holds comfortably. The shop's cream and wood frame the board, so the jelly is the brightest thing on screen.

## Space, dead ends, undo and boosts

Free cups are the player's only working room. Every bad move spends room, and every set tray hands it back.

**Dead ends**

- **Stuck:** all cups are full and no riding cube can land. The loop stops right away.
- **Unsolvable:** moves remain, but no order of them can finish the cake. A solver checks the board after each move and stops the loop as soon as this happens.
- In both cases the loop halts and Gumdrop scratches its head over the recipe card. The player gets three buttons: Undo, Restart, or use a boost.

The solver is the main technical risk. Levels need to stay small enough that it can answer in well under a second on a mid-range phone. We should test this in the first prototype.

**Undo and restart**

Undo is unlimited and free, and so is Restart. Undo is the main help the game offers, as the pillars ask.

**Boosts that buy room**

| Boost | What it does | Why it fits |
| --- | --- | --- |
| Ramekin | Adds a holding spot on the counter for one level. With the ramekin selected, tapping a tray puts its front cube there. Tapping the ramekin sends the cube back onto the loop. | Gives one extra spot the player controls directly, without revealing anything |
| Extra cup | Adds one cup to the loop for the rest of the level | Adds one unit of room |

Both boosts add room and never show a move, so they fit the no-hints pillar. How players earn or buy them is an open question below.

## Difficulty knobs and level design

Difficulty comes from turning these knobs, not from adding rules. The ranges below are starting guesses to test in the prototype.

| Knob | Gentle level | Tough level |
| --- | --- | --- |
| Free cups at start | 4 or more | 1 or 2 |
| Trays | 4 to 5 | 10 to 12 |
| Flavors | 3 | 6 to 7 |
| Mixing | Long same-flavor runs at the front | Flavors alternate cube by cube |
| Tray order around the loop | Matching trays sit just downstream of each other | Empty trays sit where they catch the wrong cube first |

**Loop shape and direction** also vary per level. Neither one is a new rule. Both change the order in which cubes pass the trays, and that order is what makes one level easy and another tough. A level that reverses direction partway through a chapter forces the player to read the board again.

**Handcrafted, solver-checked**

Every level is designed by hand and then run through the same solver used for dead ends. Before a level ships, the solver must confirm it can be solved. It also reports the shortest solution and how many dead-end branches there are, which gives each level a difficulty score for ordering a chapter.

**One twist per season, at most**

Each chapter may add one new element, taught over a few levels and then mixed in. Two candidates:

- **Lidded tray:** stays closed until a named neighbour sets.
- **Frozen cube:** can't leave its tray until the tray next to it sets.

Neither adds hidden information, so the clever-not-lucky pillar still holds.

## Check against the design pillars

The mechanic meets all six pillars. Two of them depend on things we still need to build and test.

| Pillar | How the mechanic meets it | What to watch |
| --- | --- | --- |
| 1. Clever, not lucky | No random cubes arrive after the start, and delivery follows a fixed rule | Players must be able to predict where cubes land. Press-and-hold shows the path |
| 2. No time pressure | The loop moves only to deliver cubes, then rests. There are no timers, move limits or lives | Make the loop's idle motion slow enough that it doesn't feel like a clock |
| 3. Progress you can see | Each set tray fills a cake pane, and empty cups show room coming back | Long stretches with no tray setting can feel flat. Design levels so trays set steadily |
| 4. Space is the challenge | The only resource is free cups, and difficulty comes from the knobs | At most one twist per season |
| 5. No hints, no skips | Help is unlimited undo, plus boosts that add room | The landing preview shows the rules only, never a suggested move |
| 6. Honest dead ends | The loop stops as soon as the board can't be finished | Depends on the solver being fast enough. Test it early |

## Open questions for Robert

- [x] **Does the delivery rule match loop sort as you know it?** I based it on your description, with cubes riding until the first tray that takes them. If loop sort works differently, the rules section changes first.
- [x] **Should a tap send the whole front run, or one cube?** Decided: a tap sends the whole set of same-color cubes at the front, as the core rules say.
- [x] **Should an empty tray take the first cube that passes?** Decided: yes, an empty tray takes the first cube that passes it, as the core rules say.
- [ ] **Is one cake pane per tray right?** It keeps pictures chunky, at about 4 to 12 panes, which suits the Art Puzzle look.
- [ ] **How should boosts be earned?** Options are only through play, or through play plus purchase. This matters for the plan to sell the game.
- [x] **What should the trays be called?** Decided: setting tray.
