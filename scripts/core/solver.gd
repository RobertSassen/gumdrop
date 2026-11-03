extends RefCounted
## Answers "can this board still be finished?" with a depth-first search over
## every reachable board. The answer is exact unless the search hits its state
## or time budget, in which case it reports UNKNOWN.
##
## The spec calls this the main technical risk, so every result carries how
## many boards were visited and how long it took.

enum Result { SOLVABLE, UNSOLVABLE, UNKNOWN }

var max_states: int = 300000
var max_msec: int = 3000
## Set from another thread to stop a search early. The result is then UNKNOWN.
var cancelled: bool = false


## Returns {"result": Result, "states": int, "usec": int, "path": PackedInt32Array}.
## "path" is a winning sequence of taps when the result is SOLVABLE.
func solve(board) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + max_msec
	var seen := {}
	# Each frame: [board, path so far].
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
		if seen.size() > max_states or cancelled or (seen.size() % 2048 == 0 and Time.get_ticks_msec() > deadline):
			result = Result.UNKNOWN
			break
		var moves: PackedInt32Array = b.legal_moves()
		for i in range(moves.size() - 1, -1, -1):
			var nb = b.copy()
			nb.tap(moves[i], false)
			if not seen.has(nb.key()):
				var p: PackedInt32Array = (frame[1] as PackedInt32Array).duplicate()
				p.append(moves[i])
				stack.append([nb, p])
	return {
		"result": result,
		"states": seen.size(),
		"usec": Time.get_ticks_usec() - t0,
		"path": path,
	}


static func result_name(r: int) -> String:
	match r:
		Result.SOLVABLE:
			return "solvable"
		Result.UNSOLVABLE:
			return "unsolvable"
	return "unknown"
