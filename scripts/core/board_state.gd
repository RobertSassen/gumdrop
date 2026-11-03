extends RefCounted
## The rules of the jelly kitchen, with no drawing or timing in it.
##
## A tray is a stack of flavor ids listed back to front: the last entry is the
## front cube at the open end that faces the loop. Riding cubes sit in cups on
## the loop and are stored as Vector2i(flavor, stop), where a stop is a tray's
## place in travel order around the loop.
##
## tools/sim.py is a line-for-line Python copy of this file, used to design and
## verify levels. Keep the two in step: tests/run_tests.gd replays traces
## recorded by the Python model and fails if they disagree.

const CAPACITY := 4

var cups: int = 0
## stop index -> tray index, in the level's travel direction.
var order: PackedInt32Array = PackedInt32Array()
## tray index -> stop index.
var stop_of: PackedInt32Array = PackedInt32Array()
## Array of Arrays of int, back..front.
var trays: Array = []
## Array of bool: true once a tray has set.
var set_flags: Array = []
## Array of Vector2i(flavor, stop), in the order cubes are processed.
var riding: Array = []


## trays_back_to_front: Array of Arrays of flavor ids.
## travel_order: tray indices in the order a cube passes them.
## start_riding: Array of Vector2i(flavor, tray index).
func setup(trays_back_to_front: Array, travel_order: PackedInt32Array, cup_count: int, start_riding: Array = []) -> void:
	cups = cup_count
	order = travel_order.duplicate()
	stop_of.resize(order.size())
	for s in order.size():
		stop_of[order[s]] = s
	trays = []
	set_flags = []
	for t in trays_back_to_front:
		trays.append((t as Array).duplicate())
		set_flags.append(false)
	riding = []
	for r in start_riding:
		riding.append(Vector2i(r.x, stop_of[r.y]))
	for i in trays.size():
		_check_set(i)


func copy():
	var b = get_script().new()
	b.cups = cups
	b.order = order
	b.stop_of = stop_of
	b.trays = trays.duplicate(true)
	b.set_flags = set_flags.duplicate()
	b.riding = riding.duplicate()
	return b


func tray_count() -> int:
	return trays.size()


func free_cups() -> int:
	return cups - riding.size()


func is_won() -> bool:
	for f in set_flags:
		if not f:
			return false
	return true


## True when no tap is possible and the level isn't won: every cup is full.
func is_stuck() -> bool:
	return not is_won() and legal_moves().is_empty()


func front(t: int) -> int:
	var tray: Array = trays[t]
	return -1 if tray.is_empty() else tray[tray.size() - 1]


func accepts(t: int, flavor: int) -> bool:
	if set_flags[t]:
		return false
	var tray: Array = trays[t]
	if tray.size() >= CAPACITY:
		return false
	return tray.is_empty() or tray[tray.size() - 1] == flavor


func can_tap(t: int) -> bool:
	return not set_flags[t] and not (trays[t] as Array).is_empty() and free_cups() > 0


func legal_moves() -> PackedInt32Array:
	var out := PackedInt32Array()
	if free_cups() <= 0:
		return out
	for t in trays.size():
		if can_tap(t):
			out.append(t)
	return out


## Number of cubes a tap on tray t would send out right now.
func run_length(t: int) -> int:
	var tray: Array = trays[t]
	if tray.is_empty():
		return 0
	var flavor: int = tray[tray.size() - 1]
	var run := 0
	for i in range(tray.size() - 1, -1, -1):
		if tray[i] != flavor:
			break
		run += 1
	return run


## Plays one tap and resolves the whole loop run. Returns a trace for the
## animation, or an empty Dictionary when the tap does nothing.
##
## Trace: {
##   "tray": tapped tray, "launched": cubes sent out, "steps": stops per lap,
##   "cubes": [{"flavor", "start" (stop), "land" (tray or -1), "steps"}],
##   "sets": trays that set during the run, in order,
## }
func tap(t: int, record: bool = true) -> Dictionary:
	if not can_tap(t):
		return {}
	var tray: Array = trays[t]
	var flavor: int = tray[tray.size() - 1]
	var k := mini(run_length(t), free_cups())
	for i in k:
		tray.pop_back()
		riding.append(Vector2i(flavor, stop_of[t]))

	var n := order.size()
	# Every riding cube rides exactly one lap, so its own stop is checked last.
	var flav := PackedInt32Array()
	var pos := PackedInt32Array()
	var land := PackedInt32Array()
	var steps := PackedInt32Array()
	var start := PackedInt32Array()
	for r in riding:
		flav.append(r.x)
		pos.append(r.y)
		start.append(r.y)
		land.append(-1)
		steps.append(n)
	var sets := PackedInt32Array()
	for step in range(1, n + 1):
		for c in flav.size():
			if land[c] != -1:
				continue
			pos[c] = (pos[c] + 1) % n
			var target := order[pos[c]]
			if accepts(target, flav[c]):
				(trays[target] as Array).append(flav[c])
				land[c] = target
				steps[c] = step
				if _check_set(target):
					sets.append(target)
	riding = []
	for c in flav.size():
		if land[c] == -1:
			riding.append(Vector2i(flav[c], pos[c]))

	if not record:
		return {"tray": t}
	var cubes := []
	for c in flav.size():
		cubes.append({"flavor": flav[c], "start": start[c], "land": land[c], "steps": steps[c]})
	return {"tray": t, "launched": k, "steps": n, "cubes": cubes, "sets": sets}


func _check_set(t: int) -> bool:
	if set_flags[t]:
		return false
	var tray: Array = trays[t]
	if tray.size() != CAPACITY:
		return false
	for c in tray:
		if c != tray[0]:
			return false
	set_flags[t] = true
	return true


## A compact string that identifies the board, used by the solver and tests.
## Same format as tools/sim.py: each tray back..front as letters a.., then "/",
## then "|" and each riding cube as letter + stop + ",".
func key() -> String:
	var parts := PackedStringArray()
	for tray in trays:
		var s := ""
		for c in tray:
			s += char(97 + c)
		parts.append(s)
	var k := "/".join(parts) + "|"
	for r in riding:
		k += char(97 + r.x) + str(r.y) + ","
	return k
