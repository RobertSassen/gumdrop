extends SceneTree
## Headless tests for the rules engine, the loop ordering and the levels.
##
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Exits with code 0 when everything passes, 1 otherwise.

const BoardState = preload("res://scripts/core/board_state.gd")
const Level = preload("res://scripts/core/level.gd")
const Solver = preload("res://scripts/core/solver.gd")

const R := 0  # cherry
const O := 1  # tangerine
const Y := 2  # lemon
const G := 3  # lime

var failures := 0
var checks := 0


func _init() -> void:
	test_tap_sends_whole_front_run()
	test_partial_run_when_cups_run_out()
	test_cube_lands_in_first_accepting_tray()
	test_own_tray_is_checked_last()
	test_empty_tray_takes_first_cube()
	test_unlanded_cube_waits_and_lands_later()
	test_tray_sets_and_level_wins()
	test_no_free_cups_means_stuck()
	test_solver_finds_unsolvable()
	test_counterclockwise_reverses_order()
	test_levels_match_python_model()
	test_levels_are_solvable()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + what)


## Builds a board whose travel order is simply tray 0, 1, 2, ...
## Trays are given back..front.
func make(trays: Array, cups: int):
	var order := PackedInt32Array()
	for i in trays.size():
		order.append(i)
	var b = BoardState.new()
	b.setup(trays, order, cups)
	return b


func test_tap_sends_whole_front_run() -> void:
	# Tray 0 front run is G,G. Nothing else accepts lime, so both keep riding.
	var b = make([[R, G, G], [R, R, Y]], 4)
	b.tap(0)
	check(b.trays[0] == [R], "tap sends the whole same-flavor front run")
	check(b.riding.size() == 2, "both cubes of the run ride the loop")


func test_partial_run_when_cups_run_out() -> void:
	var b = make([[R, G, G, G], [R, R, Y, O]], 2)
	b.tap(0)
	check(b.trays[0] == [R, G], "only as many cubes leave as there are free cups")
	check(b.free_cups() == 0, "all cups now hold a cube")


func test_cube_lands_in_first_accepting_tray() -> void:
	# From tray 0 a cube passes tray 1, then tray 2. Both end in lemon.
	var b = make([[R, Y], [R, R, Y], [G, Y]], 4)
	b.tap(0)
	check(b.trays[1] == [R, R, Y, Y], "lemon lands in the first tray downstream that accepts it")
	check(b.trays[2] == [G, Y], "later trays are not reached")


func test_own_tray_is_checked_last() -> void:
	# Tray 1 accepts lemon, so the cube lands there and never comes home.
	var b = make([[Y, R, Y], [Y]], 4)
	b.tap(0)
	check(b.trays[1] == [Y, Y], "a cube visits other trays before its own")
	# Now only its own tray accepts: tray 1 is full of red.
	var c = make([[Y, Y, R, Y], [R, R, R, O]], 4)
	c.tap(0)
	check(c.trays[0] == [Y, Y, R], "lemon can't return onto a red front")
	check(c.riding.size() == 1, "the cube keeps riding")


func test_empty_tray_takes_first_cube() -> void:
	var b = make([[R, G], [], [G, G]], 4)
	b.tap(0)
	check(b.trays[1] == [G], "an empty tray takes the first cube that passes")
	check(b.trays[2] == [G, G], "the tray behind it gets nothing")


func test_unlanded_cube_waits_and_lands_later() -> void:
	# Lime rides; then tray 1's lemon leaves and lands in tray 2,
	# exposing lime at tray 1's front, which the resting lime then takes.
	var b = make([[R, R, G], [G, Y], [Y, Y, Y]], 4)
	b.tap(0)
	check(b.riding.size() == 1, "lime finds no home and waits on the loop")
	b.tap(1)
	check(b.trays[2] == [Y, Y, Y, Y], "lemon lands and sets tray 2")
	check(b.set_flags[2], "tray 2 is set")
	check(b.trays[1] == [G, G], "the waiting lime lands once a tray accepts it")
	check(b.riding.is_empty(), "loop is empty again")


func test_tray_sets_and_level_wins() -> void:
	# The red cube leaves tray 1 and completes tray 0.
	var w = make([[R, R, R], [Y, Y, Y, R]], 4)
	var trace: Dictionary = w.tap(1)
	check(w.set_flags[0], "four reds set the tray")
	check(trace["sets"] == PackedInt32Array([0]), "the trace reports the set")
	check(not w.is_won(), "not won while a tray is unset")
	var x = make([[R, R, R, R], [Y, Y, Y, Y]], 4)
	check(x.is_won(), "all trays set means the level is won")


func test_no_free_cups_means_stuck() -> void:
	var b = make([[R, Y, R, Y], [Y, R, Y, R]], 1)
	b.tap(0)
	check(b.free_cups() == 0, "the only cup is used")
	check(b.is_stuck(), "no free cups and not won is a dead end")
	check(b.tap(1).is_empty(), "a tap with no free cups does nothing")


func test_solver_finds_unsolvable() -> void:
	var stuck = make([[R, Y, R, Y], [Y, R, Y, R]], 1)
	var r: Dictionary = Solver.new().solve(stuck)
	check(r["result"] == Solver.Result.UNSOLVABLE, "alternating flavors with one cup can't be solved")
	var easy = make([[R, R, R, Y], [Y, Y, Y, R]], 2)
	r = Solver.new().solve(easy)
	check(r["result"] == Solver.Result.SOLVABLE, "a simple swap is solvable")
	# Replaying the path must win.
	for m in r["path"]:
		easy.tap(m)
	check(easy.is_won(), "the solver's path wins")


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
	d["direction"] = "ccw"
	lv = Level.new()
	lv.from_dict(d)
	check(lv.travel_order == PackedInt32Array([2, 1, 0]), "counterclockwise reverses it")


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
		for i in (w["taps"] as Array).size():
			b.tap(int(w["taps"][i]))
			if b.key() != w["keys"][i]:
				printerr("  %s tap %d: godot %s python %s" % [w["level"], i, b.key(), w["keys"][i]])
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
		var solver = Solver.new()
		solver.max_msec = 20000
		var r: Dictionary = solver.solve(b)
		print("%s: %s, %d boards, %.1f ms" % [path.get_file(), Solver.result_name(r["result"]), r["states"], r["usec"] / 1000.0])
		check(r["result"] == Solver.Result.SOLVABLE, path + " is solvable")
