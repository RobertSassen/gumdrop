extends Node2D
## The playable proof of concept: one screen with the window cake on top, the
## kitchen board (loop and setting trays) in the middle and the toolbar below.
## Everything is drawn with plain shapes; there are no art assets yet.

const Level = preload("res://scripts/core/level.gd")
const Solver = preload("res://scripts/core/solver.gd")

const LEVEL_DIR := "res://levels/"
const SCREEN := Vector2(1080, 1920)
const BOARD_ORIGIN := Vector2(0, 590)
const CAKE_RECT := Rect2(150, 150, 780, 400)

const FLAVOR_COLORS := [
	Color("e2445c"),  # cherry
	Color("f28c38"),  # tangerine
	Color("f2c53d"),  # lemon
	Color("86c046"),  # lime
	Color("e8619f"),  # raspberry
	Color("8e5bc2"),  # grape
	Color("3f7fd9"),  # blueberry
]
const BG := Color("f6ebdd")
const WOOD := Color("d9b48a")
const WOOD_DARK := Color("8a6240")
const INK := Color("4a3426")
const INK_SOFT := Color("8c7462")
const TRAY_FILL := Color("fffaf3")
const CAVITY := Color("efe3d3")
const BELT := Color("c9c2ba")
const BELT_EDGE := Color("9d958c")
const CUP := Color("ffffff")

const CUBE_SIZE := 62.0
const CUP_SPACING := 50.0
const WOBBLE_TIME := 0.35

var level_files: PackedStringArray = PackedStringArray()
var level_index := 0
var level  # Level
var board  # BoardState: the true state, already resolved past any animation
var history: Array = []  # BoardState snapshots for undo

## Animation of the last tap. Empty when idle. Keys: trace, shown (a board
## that gains cubes as they land), t, step, applied.
var anim: Dictionary = {}
var tap_queue: Array = []
var wobble := {}  # tray -> time the wobble started
var time_sec := 0.0

var dead_end := false
var status_text := ""
var solver_text := ""
## Solver runs in flight on worker threads: [{task, solver, board, result, stale}]
var solver_jobs: Array = []

var font: Font
var tray_box: StyleBoxFlat
var tray_set_boxes: Array = []
var cube_boxes: Array = []
var pane_boxes: Array = []
var pane_empty_box: StyleBoxFlat
var counter_box: StyleBoxFlat
var cake_frame_box: StyleBoxFlat
var banner_box: StyleBoxFlat
var buttons := {}


func _ready() -> void:
	font = ThemeDB.fallback_font
	_make_styles()
	_build_toolbar()
	level_files = _find_levels()
	if level_files.is_empty():
		status_text = "No levels found in " + LEVEL_DIR
		return
	_load_level(0)


func _exit_tree() -> void:
	for job in solver_jobs:
		job["solver"].cancelled = true
		WorkerThreadPool.wait_for_task_completion(job["task"])
	solver_jobs.clear()


# --- Levels ----------------------------------------------------------------

func _find_levels() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(LEVEL_DIR):
		# Exported builds list imported files with a .remap or .import suffix.
		var fname := f.trim_suffix(".remap").trim_suffix(".import")
		if fname.ends_with(".json") and not out.has(fname):
			out.append(fname)
	out.sort()
	return out


func _load_level(i: int) -> void:
	level_index = clampi(i, 0, level_files.size() - 1)
	level = Level.load_file(LEVEL_DIR + level_files[level_index])
	if level == null:
		status_text = "Couldn't load " + level_files[level_index]
		return
	board = level.make_board()
	history.clear()
	anim = {}
	tap_queue.clear()
	wobble.clear()
	_update_buttons()
	_evaluate()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if level == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := make_input_local(event) as InputEventMouseButton
		var p: Vector2 = local.position - BOARD_ORIGIN
		for t in level.tray_count():
			if level.tray_rect(t).grow(12).has_point(p):
				_on_tray_tapped(t)
				get_viewport().set_input_as_handled()
				return


func _on_tray_tapped(t: int) -> void:
	if dead_end or board.is_won():
		return
	if not anim.is_empty():
		# Spec: taps made during animation are queued.
		tap_queue.append(t)
		return
	_do_tap(t)


func _do_tap(t: int) -> void:
	if not board.can_tap(t):
		wobble[t] = time_sec
		return
	var before = board.copy()
	var trace: Dictionary = board.tap(t)
	history.append(before)
	_cancel_solvers()
	status_text = ""
	solver_text = ""
	var shown = before.copy()
	for i in trace["launched"]:
		(shown.trays[t] as Array).pop_back()
	shown.riding = []
	var n: int = trace["steps"]
	anim = {
		"trace": trace,
		"shown": shown,
		"t": 0.0,
		"step": clampf(1.6 / n, 0.12, 0.3),
		"applied": {},
	}
	_update_buttons()


func _on_undo() -> void:
	if history.is_empty():
		return
	anim = {}
	tap_queue.clear()
	board = history.pop_back()
	_evaluate()
	_update_buttons()


func _on_restart() -> void:
	_load_level(level_index)


func _on_prev() -> void:
	_load_level(level_index - 1)


func _on_next() -> void:
	_load_level(level_index + 1)


# --- Turn flow -------------------------------------------------------------

func _process(delta: float) -> void:
	time_sec += delta
	if not anim.is_empty():
		_advance_anim(delta)
	_poll_solvers()
	queue_redraw()


func _advance_anim(delta: float) -> void:
	anim["t"] += delta
	var trace: Dictionary = anim["trace"]
	var step: float = anim["step"]
	var shown = anim["shown"]
	var cubes: Array = trace["cubes"]
	for i in cubes.size():
		var c: Dictionary = cubes[i]
		if c["land"] != -1 and not anim["applied"].has(i) and anim["t"] >= c["steps"] * step:
			(shown.trays[c["land"]] as Array).append(c["flavor"])
			shown._check_set(c["land"])
			anim["applied"][i] = true
	if anim["t"] >= trace["steps"] * step + 0.08:
		anim = {}
		while not tap_queue.is_empty():
			var queued: int = tap_queue.pop_front()
			if board.can_tap(queued):
				_do_tap(queued)
				return
			wobble[queued] = time_sec
		_evaluate()


## Decides what the board means now: won, stuck, or ask the solver.
func _evaluate() -> void:
	_cancel_solvers()
	dead_end = false
	status_text = ""
	if board.is_won():
		status_text = "Order complete! The window cake is ready."
		solver_text = ""
		return
	if board.is_stuck():
		dead_end = true
		status_text = "Every cup is full and nothing can land."
		solver_text = ""
		return
	solver_text = "Checking the recipe..."
	var job := {"solver": Solver.new(), "board": board.copy(), "result": {}, "stale": false}
	job["task"] = WorkerThreadPool.add_task(func(): job["result"] = job["solver"].solve(job["board"]))
	solver_jobs.append(job)


func _cancel_solvers() -> void:
	for job in solver_jobs:
		job["stale"] = true
		job["solver"].cancelled = true


func _poll_solvers() -> void:
	for job in solver_jobs.duplicate():
		if not WorkerThreadPool.is_task_completed(job["task"]):
			continue
		WorkerThreadPool.wait_for_task_completion(job["task"])
		solver_jobs.erase(job)
		if job["stale"]:
			continue
		var r: Dictionary = job["result"]
		var ms: float = r["usec"] / 1000.0
		solver_text = "Solver: %s in %.1f ms, %d boards checked" % [Solver.result_name(r["result"]), ms, r["states"]]
		if r["result"] == Solver.Result.UNSOLVABLE:
			dead_end = true
			status_text = "The loop stopped. This mix can't be finished from here."
		elif r["result"] == Solver.Result.UNKNOWN:
			solver_text += " (gave up)"


# --- Toolbar ---------------------------------------------------------------

func _build_toolbar() -> void:
	var specs := [
		["undo", "Undo", _on_undo],
		["restart", "Restart", _on_restart],
		["prev", "< Prev", _on_prev],
		["next", "Next >", _on_next],
	]
	var w := 236.0
	var gap := (SCREEN.x - 4 * w) / 5.0
	for i in specs.size():
		var b := Button.new()
		b.text = specs[i][1]
		b.position = Vector2(gap + i * (w + gap), 1800)
		b.size = Vector2(w, 92)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 36)
		b.pressed.connect(specs[i][2])
		add_child(b)
		buttons[specs[i][0]] = b


func _update_buttons() -> void:
	if buttons.is_empty():
		return
	buttons["undo"].disabled = history.is_empty()
	buttons["prev"].disabled = level_index <= 0
	buttons["next"].disabled = level_index >= level_files.size() - 1


# --- Drawing ---------------------------------------------------------------

func _make_styles() -> void:
	tray_box = _box(TRAY_FILL, 20, Color("d8c6b0"), 3)
	for c in FLAVOR_COLORS:
		cube_boxes.append(_box(c, 14, c.darkened(0.25), 2))
		tray_set_boxes.append(_box(c.lerp(Color.WHITE, 0.72), 20, c.darkened(0.1), 5))
		pane_boxes.append(_box(c, 10, c.darkened(0.3), 3))
	pane_empty_box = _box(Color(1, 1, 1, 0.55), 10, Color("cdbba6"), 2)
	counter_box = _box(WOOD, 40, WOOD_DARK, 4)
	cake_frame_box = _box(Color("5b4030"), 26, Color("3d2a1f"), 4)
	banner_box = _box(Color(1, 0.98, 0.94, 0.94), 28, WOOD_DARK, 4)


func _box(fill: Color, radius: int, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.anti_aliasing = true
	return sb


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), BG)
	if level == null:
		_text(status_text, Vector2(SCREEN.x / 2, 900), 36, INK)
		return
	var shown = board if anim.is_empty() else anim["shown"]
	_draw_header()
	_draw_cake(shown)

	draw_set_transform(BOARD_ORIGIN)
	draw_style_box(counter_box, Rect2(Vector2(8, 0), Vector2(1064, 1090)))
	_draw_loop()
	for t in level.tray_count():
		_draw_tray(shown, t)
	if anim.is_empty():
		_draw_resting_cubes()
	else:
		_draw_moving_cubes()
	draw_set_transform(Vector2.ZERO)

	_draw_cup_row()
	_text(status_text, Vector2(SCREEN.x / 2, 1752), 32, INK)
	_text(solver_text, Vector2(SCREEN.x / 2, 1785), 22, INK_SOFT)
	if anim.is_empty() and (dead_end or board.is_won()):
		_draw_banner()


func _text(s: String, center: Vector2, size: int, color: Color) -> void:
	if s.is_empty():
		return
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - w / 2.0, center.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_header() -> void:
	_text("%d. %s" % [level_index + 1, level.title], Vector2(SCREEN.x / 2, 70), 44, INK)
	var dir_word := "counterclockwise" if level.direction == "ccw" else "clockwise"
	var sub := "%s · loop runs %s" % [level.customer, dir_word] if level.customer != "" else "Loop runs " + dir_word
	_text(sub, Vector2(SCREEN.x / 2, 118), 26, INK_SOFT)


## The window cake: one pane per tray, filled with the tray's flavor once it sets.
func _draw_cake(shown) -> void:
	draw_style_box(cake_frame_box, CAKE_RECT)
	var n: int = level.tray_count()
	var cols: int = level.cake_cols
	if cols <= 0:
		cols = n if n <= 3 else ceili(n / 2.0)
	var rows := ceili(float(n) / cols)
	var inner := CAKE_RECT.grow(-22)
	var gap := 12.0
	var pw := (inner.size.x - gap * (cols - 1)) / cols
	var ph := (inner.size.y - gap * (rows - 1)) / rows
	for i in n:
		var r := Rect2(inner.position + Vector2((i % cols) * (pw + gap), (i / cols) * (ph + gap)), Vector2(pw, ph))
		if shown.set_flags[i]:
			var flavor: int = shown.trays[i][0]
			draw_style_box(pane_boxes[flavor], r)
			# Light passing through the glass.
			draw_colored_polygon(PackedVector2Array([
				r.position + Vector2(12, 10), r.position + Vector2(r.size.x * 0.45, 10),
				r.position + Vector2(12, r.size.y * 0.55)]), Color(1, 1, 1, 0.35))
		else:
			draw_style_box(pane_empty_box, r)


func _draw_loop() -> void:
	var pts: PackedVector2Array = level.loop.duplicate()
	pts.append(pts[0])
	draw_polyline(pts, BELT_EDGE, 66.0, true)
	for p in level.loop:
		draw_circle(p, 33.0, BELT_EDGE)
	draw_polyline(pts, BELT, 58.0, true)
	for p in level.loop:
		draw_circle(p, 29.0, BELT)
	# Direction chevrons along the belt.
	var spacing := 150.0
	var count := maxi(1, int(level.loop_length / spacing))
	for i in count:
		var d: float = (i + 0.5) * level.loop_length / count
		var p: Vector2 = level.point_at(d)
		var f: Vector2 = level.travel_tangent(d)
		var s := f.orthogonal()
		draw_polyline(PackedVector2Array([p - f * 9 + s * 12, p + f * 7, p - f * 9 - s * 12]), Color(1, 1, 1, 0.75), 6.0, true)


func _draw_tray(shown, t: int) -> void:
	var rect: Rect2 = level.tray_rect(t)
	var offset := Vector2.ZERO
	if wobble.has(t):
		var age: float = time_sec - wobble[t]
		if age > WOBBLE_TIME:
			wobble.erase(t)
		else:
			offset = level.tray_dir[t].orthogonal() * sin(age * 50.0) * 9.0 * (1.0 - age / WOBBLE_TIME)
	rect.position += offset
	var tray: Array = shown.trays[t]
	var is_set: bool = shown.set_flags[t]
	draw_style_box(tray_set_boxes[tray[0]] if is_set else tray_box, rect)
	# The open end: a lip on the side that faces the loop.
	var front: Vector2 = level.tray_front_point(t) + offset
	var side: Vector2 = level.tray_dir[t].orthogonal() * (Level.CELL / 2.0)
	draw_line(front - side, front + side, WOOD_DARK if not is_set else Color(1, 1, 1, 0.9), 6.0, true)
	for i in 4:
		var c: Vector2 = level.cavity_center(t, i) + offset
		var cav := Rect2(c - Vector2.ONE * (CUBE_SIZE / 2.0 + 2), Vector2.ONE * (CUBE_SIZE + 4))
		draw_rect(cav, CAVITY.lerp(TRAY_FILL, 0.3) if is_set else CAVITY)
		if i < tray.size():
			_draw_cube(c, tray[i], 1.0)


func _draw_cube(center: Vector2, flavor: int, size_factor: float) -> void:
	var s := CUBE_SIZE * size_factor
	var r := Rect2(center - Vector2(s, s) / 2.0, Vector2(s, s))
	draw_style_box(cube_boxes[flavor], r)
	draw_circle(r.position + Vector2(s * 0.3, s * 0.28), s * 0.12, Color(1, 1, 1, 0.65))


func _draw_cup(center: Vector2) -> void:
	draw_circle(center, 24.0, CUP)
	draw_arc(center, 24.0, 0, TAU, 24, BELT_EDGE, 2.0, true)


## Cubes waiting on the loop between taps, stacked behind their stop.
func _draw_resting_cubes() -> void:
	var at_stop := {}
	for r in board.riding:
		var k: int = at_stop.get(r.y, 0)
		at_stop[r.y] = k + 1
		var p: Vector2 = level.ride_point(r.y, 0.0, k * CUP_SPACING)
		_draw_cup(p)
		_draw_cube(p, r.x, 0.68)


func _draw_moving_cubes() -> void:
	var trace: Dictionary = anim["trace"]
	var step: float = anim["step"]
	var n: int = trace["steps"]
	var progress: float = anim["t"] / step
	var at_stop := {}
	for c in trace["cubes"]:
		var k: int = at_stop.get(c["start"], 0)
		at_stop[c["start"]] = k + 1
		var limit: float = c["steps"] if c["land"] != -1 else n
		if c["land"] != -1 and progress >= limit:
			continue  # already in its tray
		var p: Vector2 = level.ride_point(c["start"], minf(progress, limit), k * CUP_SPACING)
		_draw_cup(p)
		_draw_cube(p, c["flavor"], 0.68)


## A row of cups under the board: filled cups are riding cubes, empty cups are
## the room the player has left.
func _draw_cup_row() -> void:
	var riding_flavors := []
	if anim.is_empty():
		for r in board.riding:
			riding_flavors.append(r.x)
	else:
		var progress: float = anim["t"] / anim["step"]
		for c in anim["trace"]["cubes"]:
			if c["land"] == -1 or progress < c["steps"]:
				riding_flavors.append(c["flavor"])
	var n: int = level.cups
	var spacing := 64.0
	var x0 := SCREEN.x / 2.0 - (n - 1) * spacing / 2.0 + 60.0
	_text("Free cups: %d" % (n - riding_flavors.size()), Vector2(x0 - 170.0, 1712), 28, INK)
	for i in n:
		var p := Vector2(x0 + i * spacing, 1702)
		_draw_cup(p)
		if i < riding_flavors.size():
			_draw_cube(p, riding_flavors[i], 0.6)


func _draw_banner() -> void:
	var r := Rect2(Vector2(90, BOARD_ORIGIN.y + 420), Vector2(900, 230))
	draw_style_box(banner_box, r)
	if board.is_won():
		_text("Order complete!", r.get_center() + Vector2(0, -20), 52, INK)
		_text("Every tray has set. Tap Next for the next order.", r.get_center() + Vector2(0, 45), 28, INK_SOFT)
	else:
		_text("Gumdrop scratches its head...", r.get_center() + Vector2(0, -20), 46, INK)
		_text("This mix can't be finished. Undo or restart.", r.get_center() + Vector2(0, 45), 28, INK_SOFT)
