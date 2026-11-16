extends SceneTree
## Headless tests for the rules engine, the loop ordering and the levels.
##
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Exits with code 0 when everything passes, 1 otherwise.

const BoardState = preload("res://scripts/core/board_state.gd")
const Level = preload("res://scripts/core/level.gd")
const Solver = preload("res://scripts/core/solver.gd")
const Tuning = preload("res://scripts/core/tuning.gd")
const GooSim = preload("res://scripts/goo/goo_sim.gd")

const R := 0  # cherry
const O := 1  # tangerine
const Y := 2  # lemon
const G := 3  # lime
const HOP := 100  # pixels between stops on test boards

var failures := 0
var checks := 0


func _init() -> void:
	test_tap_sends_whole_front_run()
	test_partial_run_when_cups_run_out()
	test_nothing_lands_until_the_belt_moves()
	test_cube_lands_in_first_accepting_tray()
	test_own_tray_is_checked_last()
	test_unlanded_cube_keeps_riding()
	test_empty_tray_takes_first_cube()
	test_waiting_cube_lands_later()
	test_tray_sets_and_level_wins()
	test_no_free_cups_means_stuck()
	test_solvers()
	test_counterclockwise_reverses_order()
	test_tuning_file_loads()
	test_levels_match_python_model()
	test_levels_are_solvable()
	test_goo_pours_rides_and_lands()
	test_goo_splits_a_run_between_tray_and_belt()
	test_goo_rests_when_the_belt_stops()
	test_goo_cost_per_step()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + what)


## A board whose travel order is tray 0, 1, 2, ... with stops HOP pixels
## apart on a belt of HOP * trays pixels. Trays are given back..front.
func make(trays: Array, cups: int):
	var order := PackedInt32Array()
	var pos := PackedInt32Array()
	for i in trays.size():
		order.append(i)
		pos.append(i * HOP)
	var b = BoardState.new()
	b.setup(trays, order, pos, HOP * trays.size(), cups, [], 4)
	return b


func test_tap_sends_whole_front_run() -> void:
	var b = make([[R, G, G], [R, R, Y]], 4)
	check(b.tap(0) == 2, "tap reports two cubes sent")
	check(b.trays[0] == [R], "tap sends the whole same-flavor front run")
	check(b.riding.size() == 2, "both cubes of the run ride the belt")


func test_partial_run_when_cups_run_out() -> void:
	var b = make([[R, G, G, G], [R, R, Y, O]], 2)
	b.tap(0)
	check(b.trays[0] == [R, G], "only as many cubes leave as there are free cups")
	check(b.free_cups() == 0, "all cups now hold a cube")


func test_nothing_lands_until_the_belt_moves() -> void:
	var b = make([[R, Y], [R, R, Y]], 4)
	b.tap(0)
	check(b.trays[1] == [R, R, Y], "no landing at the moment of the tap")
	check(b.advance(HOP - 1).is_empty(), "nothing lands before the cube reaches the next tray")
	check(b.advance(1).size() == 1, "it lands on reaching the tray")


func test_cube_lands_in_first_accepting_tray() -> void:
	var b = make([[R, Y], [R, R, Y], [G, Y]], 4)
	b.tap(0)
	b.advance(3 * HOP)
	check(b.trays[1] == [R, R, Y, Y], "lemon lands in the first tray downstream that accepts it")
	check(b.trays[2] == [G, Y], "later trays are not reached")


func test_own_tray_is_checked_last() -> void:
	var b = make([[Y, R, Y], [Y]], 4)
	b.tap(0)
	b.advance(2 * HOP)
	check(b.trays[1] == [Y, Y], "a cube visits other trays before its own")
	var c = make([[Y, Y, R, Y], [R, R, R, O]], 4)
	c.tap(0)
	c.advance(2 * HOP)
	check(c.trays[0] == [Y, Y, R], "lemon can't return onto a red front")


func test_unlanded_cube_keeps_riding() -> void:
	var b = make([[Y, Y, R, Y], [R, R, R, O]], 4)
	b.tap(0)
	b.advance(2 * HOP + 50)
	check(b.riding.size() == 1, "a cube with no home keeps riding")
	check(b.riding[0].y == 50, "and keeps moving past its own tray")
	b.advance(10 * HOP)
	check(b.riding.size() == 1 and b.trays[0] == [Y, Y, R], "lap after lap")


func test_empty_tray_takes_first_cube() -> void:
	var b = make([[R, G], [], [G, G]], 4)
	b.tap(0)
	b.advance(3 * HOP)
	check(b.trays[1] == [G], "an empty tray takes the first cube that passes")
	check(b.trays[2] == [G, G], "the tray behind it gets nothing")


func test_waiting_cube_lands_later() -> void:
	# Lime rides. Then tray 1's lemon leaves and lands in tray 2, exposing lime
	# at tray 1's front, which the riding lime then takes.
	var b = make([[R, R, G], [G, Y], [Y, Y, Y]], 4)
	b.tap(0)
	b.advance(3 * HOP)
	check(b.riding.size() == 1, "lime finds no home and keeps riding")
	b.tap(1)
	b.advance(3 * HOP)
	check(b.trays[2] == [Y, Y, Y, Y], "lemon lands and sets tray 2")
	check(b.set_flags[2], "tray 2 is set")
	check(b.trays[1] == [G, G], "the riding lime lands once a tray accepts it")
	check(b.riding.is_empty(), "belt is empty again")


func test_tray_sets_and_level_wins() -> void:
	var w = make([[R, R, R], [Y, Y, Y, R]], 4)
	w.tap(1)
	var landed: Array = w.advance(2 * HOP)
	check(w.set_flags[0], "four reds set the tray")
	check(landed == [Vector2i(R, 0)], "advance reports the landing")
	check(not w.is_won(), "not won while a tray is unset")
	var x = make([[R, R, R, R], [Y, Y, Y, Y]], 4)
	check(x.is_won(), "all trays set means the level is won")


func test_no_free_cups_means_stuck() -> void:
	var b = make([[R, Y, R, Y], [Y, R, Y, R]], 1)
	b.tap(0)
	check(b.free_cups() == 0, "the only cup is used")
	check(b.is_stuck(), "no free cups and nothing can land is a dead end")
	check(b.tap(1) == 0, "a tap with no free cups does nothing")


func test_solvers() -> void:
	var dead = make([[R, Y, R, Y], [Y, R, Y, R]], 1)
	var r: Dictionary = Solver.new().check_dead_end(dead)
	check(r["result"] == Solver.Result.UNSOLVABLE, "alternating flavors with one cup is a dead end")
	r = Solver.new().solve_patient(dead)
	check(r["result"] == Solver.Result.UNSOLVABLE, "and the patient player can't solve it either")

	var easy = make([[R, R, R, Y], [Y, Y, Y, R]], 2)
	r = Solver.new().check_dead_end(easy)
	check(r["result"] == Solver.Result.SOLVABLE, "a simple swap is not a dead end")
	r = Solver.new().solve_patient(easy)
	check(r["result"] == Solver.Result.SOLVABLE, "a simple swap is solvable")
	for m in r["path"]:
		easy.tap(m)
		easy.advance(easy.belt_length)
	check(easy.is_won(), "replaying the patient solution wins")


func test_counterclockwise_reverses_order() -> void:
	var d := {
		"loop": [[0, 0], [1000, 0], [1000, 1000], [0, 1000]],
		"direction": "cw",
		"cups": 2,
		"trays": [
			{"pos": [500, 200], "facing": "up", "cubes": ["cherry"]},
			{"pos": [800, 500], "facing": "right", "cubes": ["lemon"]},
			{"pos": [500, 800], "facing": "down", "cubes": ["lime"]},
		],
	}
	var lv = Level.new()
	lv.from_dict(d)
	check(lv.travel_order == PackedInt32Array([0, 1, 2]), "clockwise passes top, right, bottom")
	check(lv.stop_pos == PackedInt32Array([500, 1500, 2500]), "stops sit where the trays meet the belt")
	d["direction"] = "ccw"
	lv = Level.new()
	lv.from_dict(d)
	check(lv.travel_order == PackedInt32Array([2, 1, 0]), "counterclockwise reverses it")
	check(lv.stop_pos == PackedInt32Array([1500, 2500, 3500]), "positions count the other way round")


func test_tuning_file_loads() -> void:
	Tuning.reload()
	check(Tuning.last_message() == "Tuning loaded", "tuning.json parses: " + Tuning.last_message())
	check(Tuning.integer("rules", "tray_capacity") >= 2, "tray capacity is sensible")
	check(Tuning.num("loop", "belt_speed_px_per_sec") > 0.0, "belt speed is positive")
	for f in Level.FLAVORS:
		check(Tuning.flavor_color(f).a > 0.0, "flavor %s has a color" % f)


func _level_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at("res://levels/"):
		if f.ends_with(".json"):
			out.append("res://levels/" + f)
	out.sort()
	return out


func test_levels_match_python_model() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/traces.json")
	check(not text.is_empty(), "fixtures exist (run tools/sim.py --fixtures)")
	if text.is_empty():
		return
	var walks: Array = JSON.parse_string(text)
	for w in walks:
		var lv = Level.load_file("res://levels/" + w["level"])
		var b = lv.make_board()
		check(b.key() == w["start"], "%s: start board matches Python" % w["level"])
		var ok := true
		for i in (w["moves"] as Array).size():
			b.play(int(w["moves"][i]))
			if b.key() != w["keys"][i]:
				printerr("  %s move %d: godot %s python %s" % [w["level"], i, b.key(), w["keys"][i]])
				ok = false
				break
		check(ok, "%s: replay matches the Python model" % w["level"])


func test_levels_are_solvable() -> void:
	for path in _level_paths():
		var lv = Level.load_file(path)
		check(lv != null, path + " loads")
		if lv == null:
			continue
		var b = lv.make_board()
		var flavors := {}
		for t in lv.tray_cubes:
			for c in t:
				flavors[c] = true
		check(flavors.size() == lv.tray_count(), path + " has one flavor per tray")
		check(lv.start_riding.is_empty(), path + " starts with an empty belt")
		var solver = Solver.new()
		solver.max_msec = 60000
		solver.max_states = 1000000
		var r: Dictionary = solver.solve_patient(b)
		print("%s: %s, %d boards, %.1f ms, %d taps" % [path.get_file(), Solver.result_name(r["result"]),
				r["states"], r["usec"] / 1000.0, r["path"].size()])
		check(r["result"] == Solver.Result.SOLVABLE, path + " is solvable")
		var d: Dictionary = Solver.new().check_dead_end(lv.make_board())
		print("  dead-end check at start: %s, %d boards, %.1f ms" % [Solver.result_name(d["result"]),
				d["states"], d["usec"] / 1000.0])


# --- Flowing jelly -----------------------------------------------------------

const GOO_BELT := 2400  # pixels round the test belt, a circle


## A board with two trays on opposite sides of a round belt, and the goo for it.
## Returns [board, goo].
func make_goo(trays: Array, cups: int) -> Array:
	var b = BoardState.new()
	b.setup(trays, PackedInt32Array([0, 1]), PackedInt32Array([0, GOO_BELT / 2]), GOO_BELT, cups, [], 4)
	var g = GooSim.new()
	var pts := PackedVector2Array()
	var n := GOO_BELT / 6
	for k in n:
		pts.append(Vector2.from_angle(TAU * k / n) * (GOO_BELT / TAU))
	g.set_path(pts, GOO_BELT)
	g.fit_cubes(cups)
	return [b, g]


func goo_point(pos: float) -> Vector2:
	return Vector2.from_angle(TAU * pos / GOO_BELT) * (GOO_BELT / TAU)


## Taps tray t the way the game does: the rules first, then the pour.
func goo_tap(b, g, t: int) -> void:
	var flavor: int = b.front(t)
	var held: int = b.trays[t].size()
	var left: int = b.tap(t)
	var slots := PackedInt32Array()
	var offsets := PackedFloat32Array()
	for i in left:
		slots.append(held - 1 - i)
		offsets.append(i * g.clump_length)
	var stop: float = b.stop_pos[b.stop_of[t]]
	var mouth := goo_point(stop) * 0.85
	g.pour(t, flavor, slots, offsets, mouth, mouth.normalized(), stop)


## Runs belt and goo together for `steps` sixtieths of a second.
func goo_run(b, g, steps: int, moving := true) -> void:
	for _i in steps:
		if moving and not b.riding.is_empty():
			var px := 15
			var before: Array = b.riding.duplicate()
			var landed: Array = b.advance(px)
			if not landed.is_empty():
				var targets := []
				for l in landed:
					var stop: float = b.stop_pos[b.stop_of[l.y]]
					var mouth := goo_point(stop) * 0.85
					targets.append({"flavor": l.x, "tray": l.y, "slot": b.trays[l.y].size() - 1,
							"front": mouth, "cavity": mouth * 0.8, "stop": stop})
				g.cubes_landed(before, b.riding, px, b.belt_length, targets)
		var positions := PackedFloat32Array()
		for r in b.riding:
			positions.append(r.y)
		g.step(1.0 / 60.0, moving, positions)


func goo_all_on_belt(g) -> bool:
	for i in g.pos.size():
		var off: float = absf(g.pos[i].length() - GOO_BELT / TAU)
		if is_nan(off) or (g.state[i] == GooSim.RIDE and off > g.half_width + 10.0):
			print("  gob %d is %.1f px off the center line" % [i, off])
			return false
	return true


func test_goo_pours_rides_and_lands() -> void:
	var made := make_goo([[R], [R, R, R]], 4)
	var b = made[0]
	var g = made[1]
	check(is_equal_approx(g.clump_length * 4, GOO_BELT), "four cubes of goo cover the whole belt")
	goo_tap(b, g, 0)
	check(g.tray_leaving(0).size() == 1, "a tapped cube starts pouring out of its tray")
	goo_run(b, g, 50)
	check(g.gob_count() == g.gobs_per_cube, "one cube pours out as %d gobs" % g.gobs_per_cube)
	check(g.tray_leaving(0).is_empty(), "the pour finishes")
	check(goo_all_on_belt(g), "riding goo stays between the rails")
	# The leash: every gob stays near where the rules say its cube is.
	var near := true
	for i in g.pos.size():
		var along: float = fposmod(g.pos[i].angle(), TAU) / TAU * GOO_BELT
		var behind: float = fposmod(b.riding[0].y - along + GOO_BELT / 2.0, GOO_BELT) - GOO_BELT / 2.0
		if behind < -40.0 or behind > g.clump_length + 40.0:
			near = false
	check(near, "the goo stays with its cube's place on the belt")
	goo_run(b, g, 35)
	check(b.riding.is_empty() and b.trays[1].size() == 4, "the rules land the cube in tray 1")
	check(g.tray_fill(1).has(3), "its goo is still flowing into the tray")
	goo_run(b, g, 120)
	check(g.gob_count() == 0 and g.clumps.is_empty(), "all the goo ends up in the tray")
	check(g.tray_fill(1).is_empty(), "the landed cube shows whole")


func test_goo_splits_a_run_between_tray_and_belt() -> void:
	# Two cherries leave together; tray 1 only has room for one.
	var made := make_goo([[G, R, R], [R, R, R]], 4)
	var b = made[0]
	var g = made[1]
	goo_tap(b, g, 0)
	goo_run(b, g, 280)
	check(b.riding.size() == 1 and g.ride.size() == 1, "one cube rides on, with one clump")
	check(g.gob_count() == g.gobs_per_cube, "the other cube's goo has gone into the tray")
	check(goo_all_on_belt(g), "the riding half stays on the belt")


func test_goo_rests_when_the_belt_stops() -> void:
	var made := make_goo([[R], [G]], 4)
	var b = made[0]
	var g = made[1]
	goo_tap(b, g, 0)
	goo_run(b, g, 60)
	goo_run(b, g, 300, false)
	check(g.asleep, "goo on a stopped belt comes to rest and sleeps")
	check(g.gob_count() == g.gobs_per_cube, "resting keeps the goo")
	check(not g.step(1.0 / 60.0, false, PackedFloat32Array([b.riding[0].y])), "a sleeping step does no work")


## Not a pass or fail on speed (machines differ); it prints the cost so a
## change that makes the goo heavier shows up, and checks nothing blew up.
func test_goo_cost_per_step() -> void:
	var made := make_goo([[Y, R, R, R], [O, G, G, G]], 6)
	var b = made[0]
	var g = made[1]
	goo_tap(b, g, 0)
	goo_run(b, g, 30)
	goo_tap(b, g, 1)
	goo_run(b, g, 240)
	var t0 := Time.get_ticks_usec()
	goo_run(b, g, 600)
	var usec := (Time.get_ticks_usec() - t0) / 600.0
	print("goo: %d gobs, %.0f microseconds per step (a 60 fps frame is 16667)" % [g.gob_count(), usec])
	check(g.gob_count() == 6 * g.gobs_per_cube, "a full belt of six cubes keeps all its goo")
	check(goo_all_on_belt(g), "a full belt stays between the rails")
	# Full belt: the goo reaches all the way round, with no bare stretch longer
	# than a couple of gobs.
	var marks := []
	for i in g.pos.size():
		marks.append(fposmod(g.pos[i].angle(), TAU) / TAU * GOO_BELT)
	marks.sort()
	var widest: float = GOO_BELT - marks[marks.size() - 1] + marks[0]
	for i in range(1, marks.size()):
		widest = maxf(widest, marks[i] - marks[i - 1])
	check(widest < g.spacing * 2.5, "a full belt is covered end to end (widest bare stretch %.0f px)" % widest)
