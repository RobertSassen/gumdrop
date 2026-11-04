extends RefCounted
## The rules of the jelly kitchen, with no drawing in it.
##
## A tray is a stack of flavor ids listed back to front: the last entry is the
## front cube at the open end that faces the loop.
##
## The belt never stops. Positions are whole pixels along the belt, measured
## in the direction of travel from 0 to belt_length - 1. Each tray has a stop:
## the spot where its open end meets the belt. A riding cube is
## Vector3i(flavor, position, next stop), and it lands in the first tray it
## reaches that accepts it. A cube that finds no home just keeps riding.
##
## tools/sim.py is a line-for-line Python copy of this file, used to design and
## verify levels. Keep the two in step: tests/run_tests.gd replays games
## recorded by the Python model and fails if they disagree.

const Tuning = preload("res://scripts/core/tuning.gd")

## A move for the solver: let the belt run until the next cube reaches a tray.
const WAIT := -1

## Cavities per tray (tuning.json: rules.tray_capacity).
var capacity: int = 4
var cups: int = 0
var belt_length: int = 1
## stop index -> tray index, in travel order.
var order: PackedInt32Array = PackedInt32Array()
## stop index -> position on the belt.
var stop_pos: PackedInt32Array = PackedInt32Array()
## tray index -> stop index.
var stop_of: PackedInt32Array = PackedInt32Array()
## Array of Arrays of int, back..front.
var trays: Array = []
## Array of bool: true once a tray has set.
var set_flags: Array = []
## Array of Vector3i(flavor, position, next stop), in processing order.
var riding: Array = []


## trays_back_to_front: Array of Arrays of flavor ids.
## travel_order: tray indices in the order a cube passes them.
## stop_positions: belt position of each stop, in travel order (ascending).
## start_riding: Array of Vector2i(flavor, tray index); they start at that stop.
## tray_capacity: 0 means use tuning.json.
func setup(trays_back_to_front: Array, travel_order: PackedInt32Array, stop_positions: PackedInt32Array,
		length: int, cup_count: int, start_riding: Array = [], tray_capacity: int = 0) -> void:
	capacity = tray_capacity if tray_capacity > 0 else Tuning.integer("rules", "tray_capacity")
	cups = cup_count
	belt_length = maxi(length, 1)
	order = travel_order.duplicate()
	stop_pos = stop_positions.duplicate()
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
		var s: int = stop_of[r.y]
		riding.append(Vector3i(r.x, stop_pos[s], (s + 1) % order.size()))
	for i in trays.size():
		_check_set(i)


func copy():
	var b = get_script().new()
	b.capacity = capacity
	b.cups = cups
	b.belt_length = belt_length
	b.order = order
	b.stop_pos = stop_pos
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


## True when no cup is free and a full lap of the belt would land nothing.
## Nothing can change after that, so the level can't be finished.
func is_stuck() -> bool:
	if is_won() or free_cups() > 0:
		return false
	return copy().advance(belt_length).is_empty()


func front(t: int) -> int:
	var tray: Array = trays[t]
	return -1 if tray.is_empty() else tray[tray.size() - 1]


func accepts(t: int, flavor: int) -> bool:
	if set_flags[t]:
		return false
	var tray: Array = trays[t]
	if tray.size() >= capacity:
		return false
	return tray.is_empty() or tray[tray.size() - 1] == flavor


func can_tap(t: int) -> bool:
	return not set_flags[t] and not (trays[t] as Array).is_empty() and free_cups() > 0


## Moves the solver can try: WAIT while anything rides, then every legal tap.
func legal_moves() -> PackedInt32Array:
	var out := PackedInt32Array()
	if not riding.is_empty():
		out.append(WAIT)
	if free_cups() <= 0:
		return out
	for t in trays.size():
		if can_tap(t):
			out.append(t)
	return out


## Number of same-flavor cubes at the front of tray t.
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


## Puts tray t's front run on the belt at the tray's stop, as many cubes as
## there are free cups. Nothing lands until the belt moves. Returns how many
## cubes left (0 when the tap does nothing).
func tap(t: int) -> int:
	if not can_tap(t):
		return 0
	var tray: Array = trays[t]
	var flavor: int = tray[tray.size() - 1]
	var k := mini(run_length(t), free_cups())
	var s: int = stop_of[t]
	for i in k:
		tray.pop_back()
		riding.append(Vector3i(flavor, stop_pos[s], (s + 1) % order.size()))
	return k


## Pixels until cube r reaches its next stop.
func gap(r: Vector3i) -> int:
	return posmod(stop_pos[r.z] - r.y, belt_length)


## Moves the belt px pixels and lands cubes as they reach trays that accept
## them. Returns the landings in order, as Vector2i(flavor, tray).
func advance(px: int) -> Array:
	var landed := []
	var n := order.size()
	var guard := 0
	while not riding.is_empty() and guard < 100000:
		guard += 1
		var g := belt_length
		for r in riding:
			g = mini(g, gap(r))
		if g > px:
			for i in riding.size():
				var r: Vector3i = riding[i]
				riding[i] = Vector3i(r.x, (r.y + px) % belt_length, r.z)
			break
		px -= g
		var keep := []
		for r in riding:
			var pos: int = (r.y + g) % belt_length
			var next: int = r.z
			if pos == stop_pos[next]:
				var t: int = order[next]
				next = (next + 1) % n
				if accepts(t, r.x):
					(trays[t] as Array).append(r.x)
					_check_set(t)
					landed.append(Vector2i(r.x, t))
					continue
			keep.append(Vector3i(r.x, pos, next))
		riding = keep
	return landed


## Lets the belt run until the next cube reaches a tray.
func wait() -> void:
	if riding.is_empty():
		return
	var g := belt_length
	for r in riding:
		g = mini(g, gap(r))
	advance(g)


## Plays a solver move: a tray index, or WAIT.
func play(move: int) -> void:
	if move == WAIT:
		wait()
	else:
		tap(move)


func _check_set(t: int) -> bool:
	if set_flags[t]:
		return false
	var tray: Array = trays[t]
	if tray.size() != capacity:
		return false
	for c in tray:
		if c != tray[0]:
			return false
	set_flags[t] = true
	return true


## A compact string that identifies the board, used by the solver and tests.
## Same format as tools/sim.py: each tray back..front as letters a.., then "/",
## then "|" and each riding cube as letter + position + ":" + next stop + ",".
func key() -> String:
	var parts := PackedStringArray()
	for tray in trays:
		var s := ""
		for c in tray:
			s += char(97 + c)
		parts.append(s)
	var k := "/".join(parts) + "|"
	for r in riding:
		k += "%s%d:%d," % [char(97 + r.x), r.y, r.z]
	return k
