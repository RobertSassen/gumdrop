extends RefCounted
## One level loaded from a JSON file in levels/, plus the loop geometry that
## decides the order in which cubes pass the trays.
##
## Board coordinates run 0..1080 wide and 0..1080 tall. The loop is one closed
## path whose points are listed clockwise on screen. Each tray has a center
## and a facing (the side its open end points to). The open end's point is
## projected onto the loop, and that position along the loop orders the trays.

const BoardState = preload("res://scripts/core/board_state.gd")
const Tuning = preload("res://scripts/core/tuning.gd")

const FLAVORS := ["cherry", "tangerine", "lemon", "lime", "raspberry", "grape", "blueberry"]
const FACINGS := {
	"left": Vector2(-1, 0),
	"right": Vector2(1, 0),
	"up": Vector2(0, -1),
	"down": Vector2(0, 1),
}
const CELL := 76.0
const TRAY_PAD := 6.0

var id: String = ""
var title: String = ""
var customer: String = ""
var direction: String = "cw"
var cups: int = 4
var loop: PackedVector2Array = PackedVector2Array()
var tray_pos: PackedVector2Array = PackedVector2Array()
var tray_dir: PackedVector2Array = PackedVector2Array()
var tray_cubes: Array = []  # back..front, flavor ids
var start_riding: Array = []  # Vector2i(flavor, tray)
var cake_cols: int = 0

var loop_length: float = 0.0
var _seg_start: PackedFloat32Array = PackedFloat32Array()
## Distance along the loop of each tray's open end, by tray index.
var tray_dist: PackedFloat32Array = PackedFloat32Array()
## Tray indices in travel order.
var travel_order: PackedInt32Array = PackedInt32Array()


static func flavor_id(name: String) -> int:
	var i := FLAVORS.find(name)
	assert(i >= 0, "Unknown flavor: " + name)
	return i


## Loads a level file. Returns null and prints an error if it can't.
static func load_file(path: String):
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Can't read level " + path)
		return null
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Level isn't a JSON object: " + path)
		return null
	var lv = load("res://scripts/core/level.gd").new()
	lv.from_dict(data)
	lv.id = path.get_file().get_basename()
	return lv


func from_dict(d: Dictionary) -> void:
	title = d.get("title", "Untitled order")
	customer = d.get("customer", "")
	direction = d.get("direction", "cw")
	cups = int(d.get("cups", Tuning.integer("rules", "default_cups")))
	cake_cols = int(d.get("cake_cols", 0))
	loop = PackedVector2Array()
	for p in d["loop"]:
		loop.append(Vector2(p[0], p[1]))
	tray_pos = PackedVector2Array()
	tray_dir = PackedVector2Array()
	tray_cubes = []
	for t in d["trays"]:
		tray_pos.append(Vector2(t["pos"][0], t["pos"][1]))
		tray_dir.append(FACINGS[t["facing"]])
		# Files list cubes front first, which reads naturally from the loop inward.
		var cubes := []
		for name in t["cubes"]:
			cubes.push_front(flavor_id(name))
		tray_cubes.append(cubes)
	start_riding = []
	for r in d.get("riding", []):
		start_riding.append(Vector2i(flavor_id(r["flavor"]), int(r["tray"])))
	_build_geometry()


func make_board():
	var b = BoardState.new()
	b.setup(tray_cubes, travel_order, cups, start_riding)
	return b


func tray_count() -> int:
	return tray_pos.size()


# --- Tray geometry ---------------------------------------------------------

func tray_long() -> float:
	return Tuning.integer("rules", "tray_capacity") * CELL + TRAY_PAD * 2.0


func tray_rect(t: int) -> Rect2:
	var d := tray_dir[t]
	var size := Vector2(tray_long(), CELL + TRAY_PAD * 2.0)
	if d.x == 0.0:
		size = Vector2(size.y, size.x)
	return Rect2(tray_pos[t] - size / 2.0, size)


## The middle of the tray's open end, the spot that faces the loop.
func tray_front_point(t: int) -> Vector2:
	return tray_pos[t] + tray_dir[t] * tray_long() / 2.0


## Center of a cavity counted from the back of the tray (0 = furthest from
## the loop). Cubes stack from the back, so a tray with 2 cubes fills cavities
## 0 and 1 and leaves the two nearest the loop empty.
func cavity_center(t: int, slot_from_back: int) -> Vector2:
	var back := tray_pos[t] - tray_dir[t] * (tray_long() / 2.0 - TRAY_PAD)
	return back + tray_dir[t] * CELL * (slot_from_back + 0.5)


# --- Loop geometry ---------------------------------------------------------

func _build_geometry() -> void:
	_seg_start = PackedFloat32Array()
	loop_length = 0.0
	for i in loop.size():
		_seg_start.append(loop_length)
		loop_length += loop[i].distance_to(loop[(i + 1) % loop.size()])
	tray_dist = PackedFloat32Array()
	for t in tray_count():
		tray_dist.append(project(tray_front_point(t)))
	var idx := []
	for t in tray_count():
		idx.append(t)
	idx.sort_custom(func(a, b):
		if is_equal_approx(tray_dist[a], tray_dist[b]):
			return a < b
		return tray_dist[a] < tray_dist[b])
	if direction == "ccw":
		idx.reverse()
	travel_order = PackedInt32Array(idx)


## Distance along the loop of the point on it closest to p.
func project(p: Vector2) -> float:
	var best_d := INF
	var best := 0.0
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var e := b - a
		var l2 := e.length_squared()
		var t := 0.0 if l2 == 0.0 else clampf((p - a).dot(e) / l2, 0.0, 1.0)
		var d := (a + e * t).distance_squared_to(p)
		if d < best_d - 0.000001:
			best_d = d
			best = _seg_start[i] + sqrt(l2) * t
	return best


func point_at(dist: float) -> Vector2:
	dist = fposmod(dist, loop_length)
	for i in range(loop.size() - 1, -1, -1):
		if dist >= _seg_start[i]:
			var a := loop[i]
			var b := loop[(i + 1) % loop.size()]
			var seg := a.distance_to(b)
			return a if seg == 0.0 else a.lerp(b, (dist - _seg_start[i]) / seg)
	return loop[0]


## +1 when cubes travel the way the loop points are listed, -1 otherwise.
func travel_sign() -> float:
	return -1.0 if direction == "ccw" else 1.0


## Distance travelled from one stop to the next one in travel order.
func hop_length(from_stop: int) -> float:
	var n := travel_order.size()
	var a := tray_dist[travel_order[from_stop]]
	var b := tray_dist[travel_order[(from_stop + 1) % n]]
	var hop := fposmod((b - a) * travel_sign(), loop_length)
	return loop_length if hop == 0.0 else hop


## Unit vector pointing the way cubes travel at distance d along the loop.
func travel_tangent(dist: float) -> Vector2:
	return (point_at(dist + 2.0) - point_at(dist - 2.0)).normalized() * travel_sign()


## Distance along the belt from a stop to the stop `steps` further on.
func ride_distance(start_stop: int, steps: int) -> float:
	var n := travel_order.size()
	var d := 0.0
	for i in steps:
		d += hop_length((start_stop + i) % n)
	return d


## Where a cube is after travelling `travelled` pixels from its start stop,
## held `back` pixels behind so cubes that share a stop don't overlap.
func ride_point_at(start_stop: int, travelled: float, back: float = 0.0) -> Vector2:
	return point_at(tray_dist[travel_order[start_stop]] + (travelled - back) * travel_sign())


func stop_point(stop: int) -> Vector2:
	return point_at(tray_dist[travel_order[stop]])
