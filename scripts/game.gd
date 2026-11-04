extends Node2D
## The playable proof of concept: one screen with the window cake on top, the
## kitchen board (loop and setting trays) in the middle and the toolbar below.
## Everything is drawn with plain shapes; there are no art assets yet.

const Level = preload("res://scripts/core/level.gd")
const Solver = preload("res://scripts/core/solver.gd")
const Tuning = preload("res://scripts/core/tuning.gd")

const LEVEL_DIR := "res://levels/"
const SCREEN := Vector2(1080, 1920)
const BOARD_ORIGIN := Vector2(0, 590)
const CAKE_RECT := Rect2(150, 140, 780, 370)
## Vertical center of the cup tally, between the window cake and the board.
const TALLY_Y := 550.0

## Values from tuning.json, refreshed by _apply_tuning().
var flavor_colors: Array = []
var col_bg: Color
var col_counter: Color
var col_counter_edge: Color
var col_ink: Color
var col_ink_soft: Color
var col_tray: Color
var col_cavity: Color
var col_belt: Color
var col_belt_edge: Color
var col_cup: Color
var cube_size := 62.0
var riding_scale := 0.68
var cube_gap := 50.0
var belt_width := 58.0
var arrow_spacing := 150.0
var wobble_time := 0.35
var wobble_px := 9.0
var wobble_speed := 50.0

var level_files: PackedStringArray = PackedStringArray()
var level_index := 0
var level  # Level
var board  # BoardState: the live board; the belt moves it every frame
var history: Array = []  # BoardState snapshots for undo, taken before each tap

## Fraction of a pixel the belt has moved but the rules haven't seen yet.
var belt_carry := 0.0
var belt_speed := 1400.0
var wobble := {}  # tray -> time the wobble started
var jiggle := {}  # tray -> time a cube last landed in it
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
	Tuning.reload()
	_apply_tuning()
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
	belt_carry = 0.0
	wobble.clear()
	jiggle.clear()
	_update_buttons()
	_evaluate()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		Tuning.reload()
		_apply_tuning()
		if level != null:
			_load_level(level_index)
		solver_text = Tuning.last_message()
		return
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
	if not board.can_tap(t):
		wobble[t] = time_sec
		return
	history.append(board.copy())
	board.tap(t)
	_update_buttons()
	_evaluate()


func _on_undo() -> void:
	if history.is_empty():
		return
	board = history.pop_back()
	belt_carry = 0.0
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
	if board != null and not dead_end and not board.riding.is_empty():
		_run_belt(delta)
	_poll_solvers()
	queue_redraw()


## Moves the belt at a steady speed. The rules work in whole pixels, so the
## leftover fraction is carried to the next frame.
func _run_belt(delta: float) -> void:
	belt_carry += belt_speed * delta
	var px := floori(belt_carry)
	belt_carry -= px
	if px <= 0:
		return
	var landed: Array = board.advance(px)
	if landed.is_empty():
		return
	for l in landed:
		jiggle[l.y] = time_sec
	# The board changed, so check again for a win or a dead end.
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
		status_text = "Every cup is full and no cube can land."
		solver_text = ""
		return
	if not Tuning.flag("solver", "show_readout"):
		solver_text = ""
		return
	solver_text = "Checking the recipe..."
	var solver = Solver.new()
	solver.max_states = Tuning.integer("solver", "max_boards")
	solver.max_msec = Tuning.integer("solver", "max_milliseconds")
	# Between taps and landings the belt only rotates and comes back to the
	# same board each lap, so this answer holds until the next change.
	var job := {"solver": solver, "board": board.copy(), "result": {}, "stale": false}
	job["task"] = WorkerThreadPool.add_task(func(): job["result"] = job["solver"].check_dead_end(job["board"]))
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
		# A readout for testing only: the game itself stops only when every cup
		# is full and nothing can land (see _evaluate).
		if r["result"] == Solver.Result.UNSOLVABLE:
			solver_text = "Solver: this board can't be finished (%.1f ms, %d boards)" % [ms, r["states"]]
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

## Reads every look and feel value from tuning.json into this scene.
func _apply_tuning() -> void:
	flavor_colors = []
	for f in Level.FLAVORS:
		flavor_colors.append(Tuning.flavor_color(f))
	col_bg = Tuning.color("background")
	col_counter = Tuning.color("counter")
	col_counter_edge = Tuning.color("counter_edge")
	col_ink = Tuning.color("ink")
	col_ink_soft = Tuning.color("ink_soft")
	col_tray = Tuning.color("tray")
	col_cavity = Tuning.color("cavity")
	col_belt = Tuning.color("belt")
	col_belt_edge = Tuning.color("belt_edge")
	col_cup = Tuning.color("cup")
	cube_size = minf(Tuning.num("look", "cube_size_px"), Level.CELL - 4.0)
	riding_scale = Tuning.num("look", "riding_cube_scale")
	cube_gap = Tuning.num("loop", "riding_cube_gap_px")
	belt_width = Tuning.num("look", "belt_width_px")
	arrow_spacing = maxf(Tuning.num("look", "arrow_spacing_px"), 40.0)
	wobble_time = maxf(Tuning.num("feedback", "wobble_seconds"), 0.01)
	wobble_px = Tuning.num("feedback", "wobble_px")
	wobble_speed = Tuning.num("feedback", "wobble_speed")
	belt_speed = maxf(Tuning.num("loop", "belt_speed_px_per_sec"), 1.0)
	_make_styles()


func _make_styles() -> void:
	tray_set_boxes = []
	cube_boxes = []
	pane_boxes = []
	tray_box = _box(col_tray, 20, Color("d8c6b0"), 3)
	for c in flavor_colors:
		cube_boxes.append(_box(c, 14, c.darkened(0.25), 2))
		tray_set_boxes.append(_box(c.lerp(Color.WHITE, 0.72), 20, c.darkened(0.1), 5))
		pane_boxes.append(_box(c, 10, c.darkened(0.3), 3))
	pane_empty_box = _box(Color(1, 1, 1, 0.55), 10, Color("cdbba6"), 2)
	counter_box = _box(col_counter, 40, col_counter_edge, 4)
	cake_frame_box = _box(Color("5b4030"), 26, Color("3d2a1f"), 4)
	banner_box = _box(Color(1, 0.98, 0.94, 0.94), 28, col_counter_edge, 4)


func _box(fill: Color, radius: int, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.anti_aliasing = true
	return sb


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), col_bg)
	if level == null:
		_text(status_text, Vector2(SCREEN.x / 2, 900), 36, col_ink)
		return
	var shown = board
	_draw_header()
	_draw_cake(shown)

	draw_set_transform(BOARD_ORIGIN)
	draw_style_box(counter_box, Rect2(Vector2(8, 0), Vector2(1064, 1090)))
	_draw_loop()
	for t in level.tray_count():
		_draw_tray(shown, t)
	_draw_riding_cubes()
	draw_set_transform(Vector2.ZERO)

	_draw_cup_tally()
	_text(status_text, Vector2(SCREEN.x / 2, 1730), 32, col_ink)
	_text(solver_text, Vector2(SCREEN.x / 2, 1770), 22, col_ink_soft)
	if dead_end or board.is_won():
		_draw_banner()


func _text(s: String, center: Vector2, size: int, color: Color) -> void:
	if s.is_empty():
		return
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - w / 2.0, center.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_header() -> void:
	_text("%d. %s" % [level_index + 1, level.title], Vector2(SCREEN.x / 2, 70), 44, col_ink)
	var dir_word := "counterclockwise" if level.direction == "ccw" else "clockwise"
	var sub := "%s · loop runs %s" % [level.customer, dir_word] if level.customer != "" else "Loop runs " + dir_word
	_text(sub, Vector2(SCREEN.x / 2, 118), 26, col_ink_soft)


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
	draw_polyline(pts, col_belt_edge, belt_width + 8.0, true)
	for p in level.loop:
		draw_circle(p, belt_width / 2.0 + 4.0, col_belt_edge)
	draw_polyline(pts, col_belt, belt_width, true)
	for p in level.loop:
		draw_circle(p, belt_width / 2.0, col_belt)
	# Direction chevrons along the belt.
	var count := maxi(1, int(level.loop_length / arrow_spacing))
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
		if age > wobble_time:
			wobble.erase(t)
		else:
			offset = level.tray_dir[t].orthogonal() * sin(age * wobble_speed) * wobble_px * (1.0 - age / wobble_time)
	rect.position += offset
	var tray: Array = shown.trays[t]
	var is_set: bool = shown.set_flags[t]
	draw_style_box(tray_set_boxes[tray[0]] if is_set else tray_box, rect)
	# The open end: a lip on the side that faces the loop.
	var front: Vector2 = level.tray_front_point(t) + offset
	var side: Vector2 = level.tray_dir[t].orthogonal() * (Level.CELL / 2.0)
	draw_line(front - side, front + side, col_counter_edge if not is_set else Color(1, 1, 1, 0.9), 6.0, true)
	for i in shown.capacity:
		var c: Vector2 = level.cavity_center(t, i) + offset
		var cav := Rect2(c - Vector2.ONE * (cube_size / 2.0 + 2), Vector2.ONE * (cube_size + 4))
		draw_rect(cav, col_cavity.lerp(col_tray, 0.3) if is_set else col_cavity)
		if i < tray.size():
			var k := 1.0
			if i == tray.size() - 1 and jiggle.has(t):
				var age: float = time_sec - jiggle[t]
				if age > 0.3:
					jiggle.erase(t)
				else:
					k = 1.0 + 0.12 * sin(age * 30.0) * (1.0 - age / 0.3)
			_draw_cube(c, tray[i], k)


func _draw_cube(center: Vector2, flavor: int, size_factor: float) -> void:
	var s := cube_size * size_factor
	var r := Rect2(center - Vector2(s, s) / 2.0, Vector2(s, s))
	draw_style_box(cube_boxes[flavor], r)
	draw_circle(r.position + Vector2(s * 0.3, s * 0.28), s * 0.12, Color(1, 1, 1, 0.65))


func _draw_cup(center: Vector2) -> void:
	draw_circle(center, 24.0, col_cup)
	draw_arc(center, 24.0, 0, TAU, 24, col_belt_edge, 2.0, true)


## Cubes riding the belt. Cubes that left a tray together share a position
## in the rules, so they're drawn one behind the other.
func _draw_riding_cubes() -> void:
	var at_pos := {}
	var carry := 0.0 if dead_end else belt_carry
	for r in board.riding:
		var k: int = at_pos.get(r.y, 0)
		at_pos[r.y] = k + 1
		var p: Vector2 = level.belt_point(r.y + carry - k * cube_gap)
		_draw_cup(p)
		_draw_cube(p, r.x, riding_scale)


## The cup tally: how many free cups are left, shown as a row of cups
## between the window cake and the board. Filled cups hold riding cubes.
func _draw_cup_tally() -> void:
	var riding_flavors := []
	for r in board.riding:
		riding_flavors.append(r.x)
	var n: int = level.cups
	var spacing := 64.0
	var label := "Free cups: %d" % (n - riding_flavors.size())
	var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var total := label_w + 24.0 + (n - 1) * spacing + 48.0
	var x := SCREEN.x / 2.0 - total / 2.0
	draw_string(font, Vector2(x, TALLY_Y + 10.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col_ink)
	var x0 := x + label_w + 24.0 + 24.0
	for i in n:
		var p := Vector2(x0 + i * spacing, TALLY_Y)
		_draw_cup(p)
		if i < riding_flavors.size():
			_draw_cube(p, riding_flavors[i], 0.6)


func _draw_banner() -> void:
	var r := Rect2(Vector2(90, BOARD_ORIGIN.y + 420), Vector2(900, 230))
	draw_style_box(banner_box, r)
	if board.is_won():
		_text("Order complete!", r.get_center() + Vector2(0, -20), 52, col_ink)
		_text("Every tray has set. Tap Next for the next order.", r.get_center() + Vector2(0, 45), 28, col_ink_soft)
	else:
		_text("Gumdrop scratches its head...", r.get_center() + Vector2(0, -20), 46, col_ink)
		_text("Every cup is full and no cube can land. Undo or restart.", r.get_center() + Vector2(0, 45), 28, col_ink_soft)
