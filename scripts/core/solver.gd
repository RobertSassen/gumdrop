extends RefCounted
## Two searches over boards, one for each question the game asks.
##
## With a belt that never stops, the moment of a tap can matter, and an exact
## search over every possible timing is far too big. So each question gets a
## search that can only err on the safe side:
##
## - solve_patient(): "can this level be finished?" It plays a patient player
##   who lets the belt run a full lap after every tap. Any solution it finds
##   can really be played, so SOLVABLE is trustworthy. Used to check levels.
##
## - check_dead_end(): "is this board hopeless?" It plays a relaxed game where
##   riding cubes may land in any tray that accepts them, whenever the player
##   likes. That player can do everything a real one can and more, so when
##   even it can't finish, the board really is a dead end. It may notice some
##   dead ends a few moves late, but it never calls one that isn't real.
##
## Both report how many boards they visited and how long they took.

enum Result { SOLVABLE, UNSOLVABLE, UNKNOWN }

var max_states: int = 300000
var max_msec: int = 3000
## Set from another thread to stop a search early. The result is then UNKNOWN.
var cancelled: bool = false


## Patient-player search on a real BoardState. Returns
## {"result", "states", "usec", "path"} where "path" lists the taps of a
## solution when the result is SOLVABLE.
func solve_patient(board) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + max_msec
	var seen := {}
	var stack: Array = [[board, PackedInt32Array()]]
	var result := Result.UNSOLVABLE
	var path := PackedInt32Array()
	while not stack.is_empty():
		var frame: Array = stack.pop_back()
		var b = frame[0]
		if b.is_won():
			result = Result.SOLVABLE
			path = frame[1]
			break
		var k: String = b.key()
		if seen.has(k):
			continue
		seen[k] = true
		if _over_budget(seen.size(), deadline):
			result = Result.UNKNOWN
			break
		var moves := PackedInt32Array()
		if b.free_cups() > 0:
			for t in b.tray_count():
				if b.can_tap(t):
					moves.append(t)
		for i in range(moves.size() - 1, -1, -1):
			var nb = b.copy()
			nb.tap(moves[i])
			nb.advance(nb.belt_length)
			if not seen.has(nb.key()):
				var p: PackedInt32Array = (frame[1] as PackedInt32Array).duplicate()
				p.append(moves[i])
				stack.append([nb, p])
	return {"result": result, "states": seen.size(), "usec": Time.get_ticks_usec() - t0, "path": path}


## Relaxed search from a real BoardState. UNSOLVABLE means a true dead end.
func check_dead_end(board) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + max_msec
	var cap: int = board.capacity
	var cups: int = board.cups
	var pool := []
	for r in board.riding:
		pool.append(r.x)
	pool.sort()
	var seen := {}
	var stack: Array = [[board.trays.duplicate(true), pool]]
	var result := Result.UNSOLVABLE
	while not stack.is_empty():
		var node: Array = stack.pop_back()
		var trays: Array = node[0]
		var riding: Array = node[1]
		if _all_set(trays, cap):
			result = Result.SOLVABLE
			break
		var k := _relaxed_key(trays, riding)
		if seen.has(k):
			continue
		seen[k] = true
		if _over_budget(seen.size(), deadline):
			result = Result.UNKNOWN
			break
		# Landings first: they tidy the board, so solutions turn up sooner.
		var children := []
		var last_flavor := -1
		for i in riding.size():
			var f: int = riding[i]
			if f == last_flavor:
				continue
			last_flavor = f
			for t in trays.size():
				var tray: Array = trays[t]
				if _is_set(tray, cap) or tray.size() >= cap:
					continue
				if tray.is_empty() or tray[tray.size() - 1] == f:
					var nt: Array = trays.duplicate(true)
					(nt[t] as Array).append(f)
					var np: Array = riding.duplicate()
					np.remove_at(i)
					children.append([nt, np])
		var free := cups - riding.size()
		if free > 0:
			for t in trays.size():
				var tray: Array = trays[t]
				if tray.is_empty() or _is_set(tray, cap):
					continue
				var f: int = tray[tray.size() - 1]
				var nt: Array = trays.duplicate(true)
				var np: Array = riding.duplicate()
				var moved := 0
				while moved < free and not (nt[t] as Array).is_empty() and (nt[t] as Array).back() == f:
					(nt[t] as Array).pop_back()
					np.append(f)
					moved += 1
				np.sort()
				children.append([nt, np])
		for i in range(children.size() - 1, -1, -1):
			stack.append(children[i])
	return {"result": result, "states": seen.size(), "usec": Time.get_ticks_usec() - t0, "path": PackedInt32Array()}


func _over_budget(states: int, deadline: int) -> bool:
	return states > max_states or cancelled or (states % 2048 == 0 and Time.get_ticks_msec() > deadline)


static func _is_set(tray: Array, cap: int) -> bool:
	if tray.size() != cap:
		return false
	for c in tray:
		if c != tray[0]:
			return false
	return true


static func _all_set(trays: Array, cap: int) -> bool:
	for tray in trays:
		if not _is_set(tray, cap):
			return false
	return true


static func _relaxed_key(trays: Array, riding: Array) -> String:
	var parts := PackedStringArray()
	for tray in trays:
		var s := ""
		for c in tray:
			s += char(97 + c)
		parts.append(s)
	var k := "/".join(parts) + "|"
	for c in riding:
		k += char(97 + c)
	return k


static func result_name(r: int) -> String:
	match r:
		Result.SOLVABLE:
			return "solvable"
		Result.UNSOLVABLE:
			return "unsolvable"
	return "unknown"
