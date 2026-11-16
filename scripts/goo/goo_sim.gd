extends RefCounted
## The flowing jelly on the belt, as a small crowd of soft "gobs".
##
## The rules (board_state.gd) still decide everything that matters: where each
## cube's worth of jelly is on the belt and which tray takes it. This file only
## makes that jelly move like goo. Each riding cube owns a clump of gobs that
## are free to jostle, stretch round corners and cling to their own flavor, and
## a soft leash keeps the clump near the cube's place on the belt. When the
## rules land a cube, its gobs ride on to the tray's mouth and stream in.
##
## There is no drawing here, so tests can run it headless. goo_layer.gd draws it.
##
## Kept cheap for phones: a handful of gobs per cube, plain arrays, one pass
## over the pairs per step, and it goes to sleep when nothing moves.

const POUR := 0   # leaving a tray, not on the belt yet
const RIDE := 1   # on the belt
const HOME := 2   # on the belt, heading for the tray that took it
const ENTER := 3  # sliding from the belt into its tray

const REPEL := 900.0
const COHESION := 320.0
const VISCOSITY_SAME := 2.2
const VISCOSITY_OTHER := 0.8
const DRAG := 10.0
const WALL := 1500.0
const CENTER := 10.0
const LEASH := 80.0
const GATHER := 6.0
const NOISE := 300.0
const MAX_SPEED := 2600.0

# Set from tuning.json by the layer.
var gobs_per_cube := 7
var spacing := 24.0
var clump_length := 96.0
var half_width := 18.0
var cling := 1.0
var slosh := 0.6
var jostle := 1.0
var belt_speed := 900.0
var enter_seconds := 0.16
var pour_speed := 800.0

# The belt's center line in travel order, one point every `ds` rule pixels.
var path := PackedVector2Array()
var tangent := PackedVector2Array()
## Turn per screen pixel, pointing at the inside of the bend.
var bend := PackedVector2Array()
## Screen pixels travelled per rule pixel (under 1 on the rounded corners).
var rate := PackedFloat32Array()
var ds := 6.0
var belt_len := 1.0

# Gobs, as parallel arrays.
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var acc := PackedVector2Array()
var flavor := PackedInt32Array()
var state := PackedInt32Array()
var clump_of := PackedInt32Array()
var seg := PackedInt32Array()
var timer := PackedFloat32Array()
var from := PackedVector2Array()

## Clump id -> Dictionary. One clump per cube's worth of jelly.
var clumps := {}
## Clump ids in the same order as BoardState.riding.
var ride: Array = []
var asleep := true

var _next_id := 1
var _seed := 20240229
var _quiet_steps := 0


func set_path(points: PackedVector2Array, length: float) -> void:
	path = points
	belt_len = maxf(length, 1.0)
	var n := path.size()
	ds = belt_len / n
	tangent.resize(n)
	bend.resize(n)
	rate.resize(n)
	for i in n:
		var step := path[(i + 1) % n] - path[i]
		rate[i] = step.length() / ds
		tangent[i] = (path[(i + 1) % n] - path[(i - 1 + n) % n]).normalized()
	for i in n:
		var span := path[(i + 1) % n].distance_to(path[(i - 1 + n) % n])
		bend[i] = (tangent[(i + 1) % n] - tangent[(i - 1 + n) % n]) / maxf(span, 0.001)


func clear() -> void:
	for a in [pos, vel, acc, from]:
		a.clear()
	for a in [flavor, state, clump_of, seg]:
		a.clear()
	timer.clear()
	clumps.clear()
	ride.clear()
	asleep = true


func gob_count() -> int:
	return pos.size()


## Rebuilds the jelly for a board that changed all at once (level start, undo).
## flavors, positions and offsets are in BoardState.riding order.
func reset(flavors: PackedInt32Array, positions: PackedFloat32Array, offsets: PackedFloat32Array) -> void:
	clear()
	for i in flavors.size():
		var c := _new_clump(flavors[i], offsets[i])
		ride.append(c["id"])
		for j in gobs_per_cube:
			var s := positions[i] - offsets[i] - (j + 0.5) / gobs_per_cube * clump_length
			var k := _index_at(s)
			var side := tangent[k].orthogonal() * spacing * (0.45 if j % 2 == 0 else -0.45)
			_add_gob(c, path[k] + side, tangent[k] * belt_speed * rate[k], k, RIDE)
	asleep = flavors.is_empty()


## A tray was tapped and `offsets.size()` cubes left it. The jelly pours out at
## `point` (the tray's open end) toward the belt over the time the belt takes
## to carry one clump past, so it lands where the rules say the cube is.
## slots: the cavity each cube leaves, front cube first.
func pour(tray: int, cube_flavor: int, slots: PackedInt32Array, offsets: PackedFloat32Array,
		point: Vector2, toward_belt: Vector2, stop: float) -> void:
	for i in slots.size():
		var c := _new_clump(cube_flavor, offsets[i])
		c["to_emit"] = gobs_per_cube
		c["emit_gap"] = clump_length / belt_speed / gobs_per_cube
		c["emit_clock"] = offsets[i] / belt_speed + c["emit_gap"] * 0.5
		c["src_tray"] = tray
		c["src_slot"] = slots[i]
		c["src_point"] = point
		c["src_dir"] = toward_belt
		c["src_seg"] = _index_at(stop)
		ride.append(c["id"])
	asleep = false


## The rules moved the belt `px` pixels and landed some cubes. `before` and
## `after` are BoardState.riding around that move. targets has one entry per
## landing, in order: {flavor, tray, slot, front, cavity, stop}.
func cubes_landed(before: Array, after: Array, px: int, rule_len: int, targets: Array) -> void:
	var kept: Array = []
	var used := []
	used.resize(targets.size())
	used.fill(false)
	var j := 0
	for i in before.size():
		var b: Vector3i = before[i]
		if j < after.size() and after[j].x == b.x and after[j].y == (b.y + px) % rule_len:
			kept.append(ride[i])
			j += 1
			continue
		var c: Dictionary = clumps[ride[i]]
		var found := -1
		for k in targets.size():
			if not used[k] and targets[k]["flavor"] == b.x:
				found = k
				break
		if found < 0:
			_drop_clump(c)
			continue
		used[found] = true
		var t: Dictionary = targets[found]
		c["home_tray"] = t["tray"]
		c["home_slot"] = t["slot"]
		c["home_front"] = t["front"]
		c["home_cavity"] = t["cavity"]
		c["home_stop"] = t["stop"]
		c["home_clock"] = (c["off"] + clump_length) / belt_speed + 0.6
		for g in pos.size():
			if clump_of[g] == c["id"] and state[g] == RIDE:
				state[g] = HOME
	ride = kept
	asleep = false


## How much of the cube arriving in cavity `slot` of each tray is there yet:
## {slot: 0..1} for tray t. A cavity that isn't listed is complete.
func tray_fill(t: int) -> Dictionary:
	var out := {}
	for c in clumps.values():
		if c["home_tray"] == t:
			out[c["home_slot"]] = float(c["arrived"]) / gobs_per_cube
	return out


## Cubes still pouring out of tray t: [[slot, flavor, fraction left], ...].
func tray_leaving(t: int) -> Array:
	var out := []
	for c in clumps.values():
		if c["src_tray"] == t and c["to_emit"] > 0:
			out.append([c["src_slot"], c["flavor"], float(c["to_emit"]) / gobs_per_cube])
	return out


## Advances the jelly by dt seconds. positions holds the belt position of each
## riding cube (BoardState.riding order). moving says whether the belt runs.
## Returns false once everything has come to rest.
func step(dt: float, moving: bool, positions: PackedFloat32Array) -> bool:
	if asleep and not moving:
		return false
	for i in mini(ride.size(), positions.size()):
		clumps[ride[i]]["pos"] = positions[i]
	_emit(dt)
	_pair_forces()
	var fastest := 0.0
	var busy := false
	var half_len := clump_length / 2.0
	var arrived := PackedInt32Array()
	for i in pos.size():
		var c: Dictionary = clumps[clump_of[i]]
		if state[i] == ENTER:
			busy = true
			timer[i] += dt / enter_seconds
			var u := minf(timer[i], 1.0)
			var e := u * u * (3.0 - 2.0 * u)
			var a: Vector2 = from[i].lerp(c["home_front"], e)
			var b: Vector2 = (c["home_front"] as Vector2).lerp(c["home_cavity"], e)
			pos[i] = a.lerp(b, e)
			if u >= 1.0:
				arrived.append(i)
			continue
		var p := pos[i]
		var k := _follow(i, p)
		var t := tangent[k]
		var n := t.orthogonal()
		var across := (p - path[k]).dot(n)
		var along := k * ds + (p - path[k]).dot(t) / maxf(rate[k], 0.2)
		var st := state[i]
		var carried := moving or st == HOME
		var belt_v := t * (belt_speed * rate[k]) if carried else Vector2.ZERO
		var a := acc[i] + (belt_v - vel[i]) * DRAG
		# The rails keep the jelly on the belt; a pour comes in over the inner rail.
		var wall := WALL if st != POUR else WALL * 0.2
		if across > half_width:
			a -= n * wall * (across - half_width)
		elif across < -half_width:
			a -= n * wall * (across + half_width)
		a -= n * CENTER * across
		if carried:
			# Round a bend the jelly swings to the outside.
			a -= bend[k] * (belt_speed * rate[k]) ** 2 * slosh
			a += Vector2(_rand() - 0.5, _rand() - 0.5) * NOISE * jostle
		if st == RIDE:
			# The leash: free inside the clump's stretch of belt, pulled back outside it.
			var off := _wrap(along - (c["pos"] - c["off"] - half_len))
			if off > half_len:
				a -= t * LEASH * (off - half_len)
			elif off < -half_len:
				a -= t * LEASH * (off + half_len)
			a -= t * GATHER * off
		var v := vel[i] + a * dt
		var speed := v.length()
		if speed > MAX_SPEED:
			v *= MAX_SPEED / speed
		vel[i] = v
		pos[i] = p + v * dt
		fastest = maxf(fastest, speed)
		if st == POUR:
			busy = true
			timer[i] += dt
			if absf(across) <= half_width + 4.0 or timer[i] > 0.3:
				state[i] = HOME if c["home_tray"] >= 0 else RIDE
		elif st == HOME:
			busy = true
			if _wrap(along - c["home_stop"]) >= -10.0 or c["home_clock"] <= 0.0:
				state[i] = ENTER
				timer[i] = 0.0
				from[i] = pos[i]
	for i in range(arrived.size() - 1, -1, -1):
		var g := arrived[i]
		var c: Dictionary = clumps[clump_of[g]]
		c["arrived"] += 1
		c["alive"] -= 1
		_remove_gob(g)
	for id in clumps.keys():
		var c: Dictionary = clumps[id]
		if c["home_tray"] >= 0:
			c["home_clock"] -= dt
			if c["alive"] <= 0 and c["to_emit"] <= 0:
				clumps.erase(id)
		if c["to_emit"] > 0:
			busy = true
	if moving or busy or fastest > 3.0:
		_quiet_steps = 0
	else:
		_quiet_steps += 1
		if _quiet_steps > 20:
			asleep = true
			for i in vel.size():
				vel[i] = Vector2.ZERO
	return not asleep


# --- Inside ------------------------------------------------------------------

func _new_clump(cube_flavor: int, off: float) -> Dictionary:
	var c := {
		"id": _next_id, "flavor": cube_flavor, "off": off, "pos": 0.0, "alive": 0,
		"to_emit": 0, "emit_gap": 0.0, "emit_clock": 0.0,
		"src_tray": -1, "src_slot": 0, "src_point": Vector2.ZERO, "src_dir": Vector2.ZERO, "src_seg": 0,
		"home_tray": -1, "home_slot": 0, "home_front": Vector2.ZERO, "home_cavity": Vector2.ZERO,
		"home_stop": 0.0, "home_clock": 0.0, "arrived": 0,
	}
	clumps[_next_id] = c
	_next_id += 1
	return c


func _add_gob(c: Dictionary, p: Vector2, v: Vector2, k: int, st: int) -> void:
	pos.append(p)
	vel.append(v)
	acc.append(Vector2.ZERO)
	from.append(p)
	flavor.append(c["flavor"])
	state.append(st)
	clump_of.append(c["id"])
	seg.append(k)
	timer.append(0.0)
	c["alive"] += 1


func _remove_gob(i: int) -> void:
	var last := pos.size() - 1
	if i != last:
		pos[i] = pos[last]
		vel[i] = vel[last]
		acc[i] = acc[last]
		from[i] = from[last]
		flavor[i] = flavor[last]
		state[i] = state[last]
		clump_of[i] = clump_of[last]
		seg[i] = seg[last]
		timer[i] = timer[last]
	for a in [pos, vel, acc, from]:
		a.resize(last)
	for a in [flavor, state, clump_of, seg]:
		a.resize(last)
	timer.resize(last)


func _drop_clump(c: Dictionary) -> void:
	for g in range(pos.size() - 1, -1, -1):
		if clump_of[g] == c["id"]:
			_remove_gob(g)
	clumps.erase(c["id"])


func _emit(dt: float) -> void:
	for c in clumps.values():
		if c["to_emit"] <= 0:
			continue
		c["emit_clock"] -= dt
		while c["emit_clock"] <= 0.0 and c["to_emit"] > 0:
			c["emit_clock"] += c["emit_gap"]
			c["to_emit"] -= 1
			var k: int = c["src_seg"]
			var side: Vector2 = (c["src_dir"] as Vector2).orthogonal() * (_rand() - 0.5) * 14.0
			var v: Vector2 = c["src_dir"] * pour_speed + tangent[k] * belt_speed * rate[k] * 0.5
			_add_gob(c, c["src_point"] + side, v, k, POUR)


## Pushes gobs apart when they overlap, lets one flavor cling to itself, and
## makes neighbors drag each other along a little so the goo moves as a mass.
func _pair_forces() -> void:
	var n := pos.size()
	for i in n:
		acc[i] = Vector2.ZERO
	var r0 := spacing
	var rc := spacing * 1.9
	var rc2 := rc * rc
	var pull := COHESION * cling
	for i in n:
		if state[i] == ENTER:
			continue
		var pi := pos[i]
		var vi := vel[i]
		var fi := flavor[i]
		var ai := Vector2.ZERO
		for j in range(i + 1, n):
			var d := pos[j] - pi
			var d2 := d.length_squared()
			if d2 > rc2 or d2 < 0.0001 or state[j] == ENTER:
				continue
			var dist := sqrt(d2)
			var same := flavor[j] == fi
			var f := 0.0
			if dist < r0:
				f = -REPEL * (r0 - dist)
			elif same:
				f = pull * sin(PI * (dist - r0) / (rc - r0))
			var a := d * (f / dist) + (vel[j] - vi) * ((VISCOSITY_SAME if same else VISCOSITY_OTHER) * (1.0 - dist / rc))
			ai += a
			acc[j] -= a
		acc[i] += ai


## Keeps gob i's nearest point on the belt's center line up to date. Gobs move
## a few points per step at most, so a short walk from the last one is enough.
func _follow(i: int, p: Vector2) -> int:
	var n := path.size()
	var k := seg[i]
	var best := p.distance_squared_to(path[k])
	for _step in 12:
		var fwd := (k + 1) % n
		var back := (k - 1 + n) % n
		var df := p.distance_squared_to(path[fwd])
		var db := p.distance_squared_to(path[back])
		if df < best and df <= db:
			k = fwd
			best = df
		elif db < best:
			k = back
			best = db
		else:
			break
	seg[i] = k
	return k


func _index_at(rule_pos: float) -> int:
	return int(round(fposmod(rule_pos, belt_len) / ds)) % path.size()


func _wrap(d: float) -> float:
	return fposmod(d + belt_len / 2.0, belt_len) - belt_len / 2.0


## A small fixed random source, so a replayed game shows the same goo.
func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return _seed / 2147483647.0
