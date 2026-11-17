extends Node2D
## The playable proof of concept: one portrait screen with the window cake on
## top, the kitchen board (loop and setting trays) on an oak table in the
## middle, and the Spare, Undo and Restart buttons below.
##
## The look follows the approved mockup. Sprites, the table, the card and the
## buttons are pictures in art/, made by tools/art/render.js. Jelly sprites are
## white and get their flavor color from tuning.json when the game starts, so
## the palette stays editable without re-rendering art.
##
## Jelly on the belt flows as goo (scripts/goo/). The rules still place every
## cube; the goo layer only makes it look and move like jelly. Set goo.enabled
## to false in tuning.json to ride in cups instead.
##
## To spare the battery the screen is only redrawn while something moves.

const Level = preload("res://scripts/core/level.gd")
const Solver = preload("res://scripts/core/solver.gd")
const Tuning = preload("res://scripts/core/tuning.gd")
const GooLayer = preload("res://scripts/goo/goo_layer.gd")
const WindowCake = preload("res://scripts/core/window_cake.gd")

const LEVEL_DIR := "res://levels/"
const SCREEN := Vector2(1080, 2340)
## The board is centered on this point, whatever the level's loop shape.
const BOARD_CENTER_Y := 1360.0
## Least table showing between the belt's outer rail and the screen edge.
const BOARD_MARGIN := 48.0
## Art pieces are rendered with this much transparent padding around them.
const ART_PAD := 60.0

# Screen layout, in screen pixels.
const PAUSE_RECT := Rect2(60, 60, 104, 104)
const CARD_POS := Vector2(190, 164)
const CAKE_GRID := Rect2(246, 280, 588, 320)
const CAKE_GRID_PAD := 20.0
const CAKE_GRID_GAP := 16.0
## The window cake on the card: this level's panel, and the whole window.
const PANEL_RECT := Rect2(264, 290, 300, 300)
const WINDOW_RECT := Rect2(598, 306, 220, 220)
const WINDOW_LABEL_Y := 562.0
const PROGRESS_FILE := "user://progress.json"
## Seconds a flavor of glass takes to fill in once its tray sets.
const GLASS_FILL_SECONDS := 0.6
const LEAD_COLOR := Color("40312d")
const RIBBON_CENTER := Vector2(540, 160)
const CUSTOMER_Y := 242.0
const PILL_TOP := 636.0
const PILL_HEIGHT := 80.0
const BUTTON_Y := 2100.0
const BUTTON_SIZE := 148.0
const BUTTON_XS := [272.0, 466.0, 660.0]

## Values from tuning.json, refreshed by _apply_tuning().
var flavor_colors: Array = []
var col_belt: Color
var col_rail: Color
var col_arrow: Color
var col_ink: Color
var col_ink_soft: Color
var cube_size := 70.0
var cube_gap := 50.0
var belt_width := 64.0
var rail_width := 12.0
var corner_radius := 110.0
var arrow_spacing := 150.0
var wobble_time := 0.35
var wobble_px := 9.0
var wobble_speed := 50.0

var level_files: PackedStringArray = PackedStringArray()
var level_index := 0
var level  # Level
var board  # BoardState: the live board; the belt moves it every frame
var history: Array = []  # BoardState snapshots for undo, taken before each tap
var board_origin := Vector2(0, 820)
var board_scale := 1.0  # wide loops are drawn smaller so the table shows around them

## Fraction of a pixel the belt has moved but the rules haven't seen yet.
var belt_carry := 0.0
var belt_speed := 1400.0
var wobble := {}  # tray -> time the wobble started
var jiggle := {}  # tray -> time a cube last landed in it
var time_sec := 0.0

## Window cakes: the stained-glass pictures built over a run of levels.
var windows: Array = []  # WindowCake
var window_cake  # the window this level belongs to, or null
var window_panel := -1  # this level's panel in it
var window_tex := {}  # window id -> {"base", "lead", flavor id -> Texture2D}
var glass_since := {}  # flavor id -> time its tray set, for the fill-in
var won_levels := {}  # level id -> true, kept between sessions

var dead_end := false
var paused := false
var status_text := ""
var toast_text := ""
var toast_until := 0.0
var solver_text := ""
## Solver runs in flight on worker threads: [{task, solver, board, result, stale}]
var solver_jobs: Array = []

## The flowing jelly on the belt, and whether it's in use (tuning: goo.enabled).
var goo: Node
var goo_on := true
## Sparkles on set trays twinkle slowly, so they redraw at this pace when
## nothing else moves.
const IDLE_REDRAW_SECONDS := 0.1
var idle_clock := 0.0

## The drawn belt: the level's loop with rounded corners. Rules still use the
## sharp loop; _belt_draw_point() moves points onto the rounded corners.
var belt_path := PackedVector2Array()
var corners: Array = []  # [{dist, reach, center, radius}]

# Art
var font: Font
var font_semibold: Font
var tex := {}
var cube_tex: Array = []  # per flavor, tinted
var cup_fill_tex: Array = []  # per flavor: jelly filling a cup, drawn over the cup
var slab_tex_h: Array = []
var slab_tex_v: Array = []
var pane_empty_box: StyleBoxTexture
var pane_gloss_box: StyleBoxTexture
var pane_boxes: Array = []  # per flavor, tinted body
var pill_box: StyleBoxTexture
var banner_box: StyleBoxFlat
var menu_box: StyleBoxFlat


func _ready() -> void:
	font = load("res://art/fonts/fredoka-700.woff2")
	font_semibold = load("res://art/fonts/fredoka-600.woff2")
	for n in ["background", "decor", "card", "pill", "pause", "pane_empty", "pane_body", "pane_gloss",
			"btn_spare", "btn_undo", "btn_restart", "sparkle", "cup",
			"tray_right", "tray_left", "tray_up", "tray_down"]:
		tex[n] = load("res://art/%s.png" % n)
	goo = GooLayer.new()
	add_child(goo)
	Tuning.reload()
	_apply_tuning()
	level_files = _find_levels()
	windows = WindowCake.load_all()
	_load_progress()
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
	_find_window()
	board = level.make_board()
	history.clear()
	glass_since.clear()
	belt_carry = 0.0
	wobble.clear()
	jiggle.clear()
	paused = false
	_build_belt_path()
	_reset_goo()
	_evaluate()


# --- Window cakes ------------------------------------------------------------

## Finds the window this level is a panel of and gives the level the flavors
## of that panel's glass.
func _find_window() -> void:
	window_cake = null
	window_panel = -1
	for w in windows:
		var p: int = w.panel_of(level_index + 1)
		if p < 0:
			continue
		var map: Dictionary = w.flavor_map(p, level.flavors_used())
		if map.is_empty():
			push_error("Window %s panel %d doesn't match the trays of %s" % [w.id, p + 1, level.id])
			return
		level.remap_flavors(map)
		window_cake = w
		window_panel = p
		_window_art(w)
		return


## The pictures of a window, loaded the first time it's shown.
func _window_art(w) -> Dictionary:
	if not window_tex.has(w.id):
		var art := {}
		var dir := "res://art/windows/%s/" % w.id
		art["base"] = load(dir + "base.png")
		art["lead"] = load(dir + "lead.png")
		for glass in w.panels:
			for f in glass:
				if not art.has(f):
					art[f] = load(dir + Level.FLAVORS[f] + ".png")
		window_tex[w.id] = art
	return window_tex[w.id]


func _level_id(level_number: int) -> String:
	return level_files[level_number - 1].get_basename()


func _load_progress() -> void:
	won_levels = {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_FILE)) if FileAccess.file_exists(PROGRESS_FILE) else null
	if typeof(data) == TYPE_DICTIONARY:
		for id in data.get("won", []):
			won_levels[str(id)] = true


func _mark_won() -> void:
	if won_levels.has(level.id):
		return
	won_levels[level.id] = true
	var f := FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"won": won_levels.keys()}))


func _window_complete() -> bool:
	if window_cake == null:
		return false
	for n in window_cake.levels:
		if not won_levels.has(_level_id(n)):
			return false
	return true


## Notes which flavors of glass have a set tray, and when each one set, so
## the panel can fill in. Undo takes a flavor out again.
func _track_glass() -> void:
	var now := {}
	for t in level.tray_count():
		if board.set_flags[t]:
			now[board.trays[t][0]] = true
	for f in glass_since.keys():
		if not now.has(f):
			glass_since.erase(f)
	for f in now:
		if not glass_since.has(f):
			glass_since[f] = time_sec


func _glass_filling() -> bool:
	for f in glass_since:
		if time_sec - glass_since[f] < GLASS_FILL_SECONDS:
			return true
	return false


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		queue_redraw()
		match event.keycode:
			KEY_T:
				Tuning.reload()
				_apply_tuning()
				if level != null:
					_load_level(level_index)
				solver_text = Tuning.last_message()
			KEY_PAGEUP:
				_on_prev()
			KEY_PAGEDOWN:
				_on_next()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
	get_viewport().set_input_as_handled()
	queue_redraw()
	if paused:
		_menu_click(p)
		return
	if PAUSE_RECT.grow(16).has_point(p):
		paused = true
		return
	for i in 3:
		if _button_rect(i).grow(10).has_point(p):
			[_on_spare, _on_undo, _on_restart][i].call()
			return
	if level == null:
		return
	if board.is_won():
		_on_next()
		return
	var bp := (p - board_origin) / board_scale
	for t in level.tray_count():
		if level.tray_rect(t).grow(12).has_point(bp):
			_on_tray_tapped(t)
			return


func _on_tray_tapped(t: int) -> void:
	if dead_end or board.is_won():
		return
	if not board.can_tap(t):
		wobble[t] = time_sec
		queue_redraw()
		return
	history.append(board.copy())
	var flavor: int = board.front(t)
	var held: int = board.trays[t].size()
	var left: int = board.tap(t)
	if goo_on:
		_pour_goo(t, flavor, held, left)
	_evaluate()


func _on_spare() -> void:
	_toast("The spare ramekin isn't in the prototype yet.")


func _on_undo() -> void:
	if history.is_empty():
		return
	board = history.pop_back()
	belt_carry = 0.0
	_reset_goo()
	_evaluate()


func _on_restart() -> void:
	_load_level(level_index)


func _on_prev() -> void:
	_load_level(level_index - 1)


func _on_next() -> void:
	_load_level(level_index + 1)


func _toast(s: String) -> void:
	toast_text = s
	toast_until = time_sec + 2.5
	queue_redraw()


# --- Pause menu --------------------------------------------------------------

const MENU_RECT := Rect2(170, 760, 740, 720)


func _menu_items() -> Array:
	return [
		["Resume", func(): paused = false, true],
		["Next level", func(): _on_next(), level_index < level_files.size() - 1],
		["Previous level", func(): _on_prev(), level_index > 0],
		["Restart level", func(): _on_restart(), true],
	]


func _menu_item_rect(i: int) -> Rect2:
	return Rect2(MENU_RECT.position + Vector2(90, 220 + i * 120), Vector2(MENU_RECT.size.x - 180, 96))


func _menu_click(p: Vector2) -> void:
	var items := _menu_items()
	for i in items.size():
		if items[i][2] and _menu_item_rect(i).has_point(p):
			items[i][1].call()
			paused = false
			return
	if not MENU_RECT.has_point(p):
		paused = false


# --- Turn flow -------------------------------------------------------------

func _process(delta: float) -> void:
	time_sec += delta
	var running: bool = board != null and not dead_end and not paused and not board.riding.is_empty()
	if running:
		_run_belt(delta)
	var flowing := false
	if goo_on and board != null and not paused:
		flowing = goo.advance(delta, running, _riding_positions())
	_poll_solvers()
	# Redraw only while something on screen changes; an idle board costs nothing.
	if running or flowing or not wobble.is_empty() or not jiggle.is_empty() or _glass_filling():
		queue_redraw()
		return
	idle_clock += delta
	if idle_clock >= IDLE_REDRAW_SECONDS:
		idle_clock = 0.0
		if _has_slow_motion():
			queue_redraw()


## True while something that only changes slowly is on screen: a twinkling set
## tray, or a toast waiting to fade.
func _has_slow_motion() -> bool:
	if toast_text != "" and time_sec < toast_until + IDLE_REDRAW_SECONDS * 2.0:
		return true
	if board == null or paused:
		return false
	for f in board.set_flags:
		if f:
			return true
	return false


## Moves the belt at a steady speed. The rules work in whole pixels, so the
## leftover fraction is carried to the next frame.
func _run_belt(delta: float) -> void:
	belt_carry += belt_speed * delta
	var px := floori(belt_carry)
	belt_carry -= px
	if px <= 0:
		return
	var before: Array = board.riding.duplicate() if goo_on else []
	var landed: Array = board.advance(px)
	if landed.is_empty():
		return
	if goo_on:
		_land_goo(before, px, landed)
	for l in landed:
		jiggle[l.y] = time_sec
	# The board changed, so check again for a win or a dead end.
	_evaluate()


## Decides what the board means now: won, stuck, or ask the solver.
func _evaluate() -> void:
	queue_redraw()
	_cancel_solvers()
	dead_end = false
	status_text = ""
	_track_glass()
	if board.is_won():
		_mark_won()
		status_text = "Order complete! The window cake is ready."
		solver_text = ""
		return
	if board.is_stuck():
		dead_end = true
		status_text = "The belt is full and no jelly can land."
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
		queue_redraw()
		var r: Dictionary = job["result"]
		var ms: float = r["usec"] / 1000.0
		solver_text = "Solver: %s in %.1f ms, %d boards checked" % [Solver.result_name(r["result"]), ms, r["states"]]
		# A readout for testing only: the game itself stops only when every cup
		# is full and nothing can land (see _evaluate).
		if r["result"] == Solver.Result.UNSOLVABLE:
			solver_text = "Solver: this board can't be finished (%.1f ms, %d boards)" % [ms, r["states"]]
		elif r["result"] == Solver.Result.UNKNOWN:
			solver_text += " (gave up)"


# --- Look ------------------------------------------------------------------

## Reads every look and feel value from tuning.json into this scene.
func _apply_tuning() -> void:
	flavor_colors = []
	for f in Level.FLAVORS:
		flavor_colors.append(Tuning.flavor_color(f))
	col_belt = Tuning.color("belt")
	col_rail = Tuning.color("rail")
	col_arrow = Tuning.color("arrow")
	col_ink = Tuning.color("ink")
	col_ink_soft = Tuning.color("ink_soft")
	cube_size = minf(Tuning.num("look", "cube_size_px"), Level.CELL - 4.0)
	cube_gap = Tuning.num("loop", "riding_cube_gap_px")
	belt_width = Tuning.num("look", "belt_width_px")
	rail_width = Tuning.num("look", "rail_width_px")
	corner_radius = Tuning.num("look", "belt_corner_radius_px")
	arrow_spacing = maxf(Tuning.num("look", "arrow_spacing_px"), 40.0)
	wobble_time = maxf(Tuning.num("feedback", "wobble_seconds"), 0.01)
	wobble_px = Tuning.num("feedback", "wobble_px")
	wobble_speed = Tuning.num("feedback", "wobble_speed")
	belt_speed = maxf(Tuning.num("loop", "belt_speed_px_per_sec"), 1.0)
	goo_on = Tuning.flag("goo", "enabled")
	goo.apply_tuning(flavor_colors, belt_speed, belt_width)
	_make_jelly_art()
	_make_styles()


## Tints the white jelly sprites with each flavor color: shadow, then the body
## multiplied by the color, then the gloss added on top.
func _make_jelly_art() -> void:
	cube_tex = []
	cup_fill_tex = []
	slab_tex_h = []
	slab_tex_v = []
	var layers := {}
	for n in ["cube", "slab_h", "slab_v", "cupfill"]:
		layers[n] = []
		for k in ["shadow", "body", "gloss"]:
			var img: Image = load("res://art/%s_%s.png" % [n, k]).get_image()
			img.convert(Image.FORMAT_RGBA8)
			layers[n].append(img)
	for c in flavor_colors:
		cube_tex.append(ImageTexture.create_from_image(_tint(layers["cube"], c, 0.0)))
		cup_fill_tex.append(ImageTexture.create_from_image(_tint(layers["cupfill"], c, 0.0)))
		# A set slab glows a little brighter than loose cubes.
		slab_tex_h.append(ImageTexture.create_from_image(_tint(layers["slab_h"], c, 0.18)))
		slab_tex_v.append(ImageTexture.create_from_image(_tint(layers["slab_v"], c, 0.18)))


func _tint(l: Array, c: Color, glow: float) -> Image:
	var shadow: Image = l[0]
	var body: Image = l[1]
	var gloss: Image = l[2]
	var out := Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8)
	var gk := Tuning.num("look", "jelly_gloss")
	for y in body.get_height():
		for x in body.get_width():
			var s := shadow.get_pixel(x, y)
			var b := body.get_pixel(x, y)
			var g := gloss.get_pixel(x, y)
			# The body is rendered softly lit, so its shading already matches a
			# full-color render; a steeper curve would darken the rims. The
			# gloss loses its faint overall haze so only real highlights
			# brighten the color.
			var col := Color(b.r * c.r, b.g * c.g, b.b * c.b).lerp(Color.WHITE, glow)
			var gl := clampf((g.r - 0.22) / 0.78, 0.0, 1.0) * g.a * gk
			col = Color(minf(col.r + gl, 1.0), minf(col.g + gl, 1.0), minf(col.b + gl, 1.0))
			# body over shadow
			var a := b.a + s.a * (1.0 - b.a)
			if a <= 0.0:
				continue
			var rgb := (Color(col.r, col.g, col.b) * b.a + Color(s.r, s.g, s.b) * s.a * (1.0 - b.a)) / a
			out.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))
	return out


func _make_styles() -> void:
	pane_empty_box = _art_box(tex["pane_empty"], 24.0)
	pane_gloss_box = _art_box(tex["pane_gloss"], 24.0)
	pane_boxes = []
	for c in flavor_colors:
		var b := _art_box(tex["pane_body"], 24.0)
		b.modulate_color = c
		pane_boxes.append(b)
	pill_box = _art_box(tex["pill"], 40.0)
	banner_box = StyleBoxFlat.new()
	banner_box.bg_color = Color("fffaf0")
	banner_box.set_corner_radius_all(40)
	banner_box.border_color = Color("d8bf98")
	banner_box.border_width_bottom = 10
	banner_box.shadow_color = Color(0.24, 0.12, 0.04, 0.35)
	banner_box.shadow_size = 24
	banner_box.shadow_offset = Vector2(0, 12)
	banner_box.anti_aliasing = true
	menu_box = banner_box.duplicate()


## A 9-slice style box over an art piece that has ART_PAD of transparent
## padding: drawing it into a rect puts the piece itself in that rect.
func _art_box(t: Texture2D, corner: float) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = t
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		b.set_texture_margin(side, ART_PAD + corner)
		b.set_expand_margin(side, ART_PAD)
	return b


# --- The rounded belt ------------------------------------------------------

## Rounds each corner of the level's loop for drawing. A point of the sharp
## loop near a corner is moved onto the arc straight from the arc's center,
## which keeps cups moving smoothly and leaves the straight parts untouched.
func _build_belt_path() -> void:
	corners = []
	belt_path = PackedVector2Array()
	var pts: PackedVector2Array = level.loop
	var n := pts.size()
	for i in n:
		var v := pts[i]
		var a := pts[(i - 1 + n) % n]
		var b := pts[(i + 1) % n]
		var u1 := (a - v).normalized()
		var u2 := (b - v).normalized()
		var half := u1.angle_to(u2) / 2.0
		half = absf(half)
		if half < 0.01 or half > PI / 2.0 - 0.01:
			corners.append({})
			continue
		var reach := corner_radius / tan(half)
		reach = minf(reach, minf(v.distance_to(a), v.distance_to(b)) * 0.45)
		var r := reach * tan(half)
		var center := v + (u1 + u2).normalized() * (r / sin(half))
		corners.append({"dist": level._seg_start[i], "reach": reach, "center": center, "radius": r})
	var steps := int(level.loop_length / 6.0)
	for k in steps:
		belt_path.append(_round_point(level.loop_length * k / steps))


func _round_point(dist: float) -> Vector2:
	var p: Vector2 = level.point_at(dist)
	var L: float = level.loop_length
	for c in corners:
		if c.is_empty():
			continue
		var d := fposmod(dist - c["dist"] + L / 2.0, L) - L / 2.0
		if absf(d) < c["reach"]:
			return c["center"] + (p - c["center"]).normalized() * c["radius"]
	return p


## Board point of a belt position as the rules count it, on the rounded belt.
func _belt_draw_point(pos: float) -> Vector2:
	return _round_point(-pos if level.direction == "ccw" else pos)


# --- Flowing jelly -----------------------------------------------------------

## How far behind its rule position each riding cube's jelly sits: cubes that
## left a tray together share a position, so each one trails the one before.
func _riding_offsets() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var at_pos := {}
	for r in board.riding:
		var k: int = at_pos.get(r.y, 0)
		at_pos[r.y] = k + 1
		out.append(k * cube_gap)
	return out


func _riding_positions() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var carry := 0.0 if dead_end else belt_carry
	for r in board.riding:
		out.append(r.y + carry)
	return out


## Starts the goo afresh from the board: level start, undo, new tuning.
func _reset_goo() -> void:
	if level == null or belt_path.is_empty():
		return
	var points := PackedVector2Array()
	var steps := belt_path.size()
	for k in steps:
		points.append(_belt_draw_point(level.loop_length * k / steps))
	goo.set_belt(points, board.belt_length, level.cups)
	if not goo_on:
		return
	var flavors := PackedInt32Array()
	for r in board.riding:
		flavors.append(r.x)
	goo.sim.reset(flavors, _riding_positions(), _riding_offsets())
	goo.refresh()


## A tap sent `left` cubes of tray t onto the belt: pour them out as goo.
func _pour_goo(t: int, flavor: int, held: int, left: int) -> void:
	if left <= 0:
		return
	var slots := PackedInt32Array()
	for i in left:
		slots.append(held - 1 - i)
	var offsets := _riding_offsets().slice(board.riding.size() - left)
	var stop: float = board.stop_pos[board.stop_of[t]]
	goo.sim.pour(t, flavor, slots, offsets, level.tray_front_point(t), level.tray_dir[t], stop)


## The belt moved px pixels and the rules landed some cubes: send their goo home.
func _land_goo(before: Array, px: int, landed: Array) -> void:
	var total := {}
	for l in landed:
		total[l.y] = total.get(l.y, 0) + 1
	var seen := {}
	var targets := []
	for l in landed:
		var t: int = l.y
		var slot: int = board.trays[t].size() - total[t] + seen.get(t, 0)
		seen[t] = seen.get(t, 0) + 1
		targets.append({
			"flavor": l.x, "tray": t, "slot": slot,
			"front": level.tray_front_point(t), "cavity": level.cavity_center(t, slot),
			"stop": float(board.stop_pos[board.stop_of[t]]),
		})
	goo.sim.cubes_landed(before, board.riding, px, board.belt_length, targets)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	draw_texture(tex["background"], Vector2.ZERO)
	if level == null:
		_text(status_text, Vector2(SCREEN.x / 2, 1200), 40, Color.WHITE, 4, col_ink)
		return
	_layout_board()
	draw_set_transform(board_origin, 0.0, Vector2.ONE * board_scale)
	_draw_belt()
	for t in level.tray_count():
		_draw_tray(t)
	if goo_on:
		var jelly: Texture2D = goo.picture()
		if jelly != null:
			draw_texture_rect(jelly, goo.rect, false)
	else:
		_draw_riding_cubes()
	draw_set_transform(Vector2.ZERO)
	draw_texture(tex["decor"], Vector2.ZERO)

	_draw_cake()
	_draw_cup_pill()
	draw_texture(tex["pause"], PAUSE_RECT.position - Vector2.ONE * ART_PAD)
	_draw_buttons()
	_draw_readouts()
	if dead_end or board.is_won():
		_draw_banner()
	if paused:
		_draw_menu()


## Centers the level's loop in the board area, scaled down if its belt would
## reach the screen edges.
func _layout_board() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in level.loop:
		lo = lo.min(p)
		hi = hi.max(p)
	var outer := hi - lo + Vector2.ONE * (belt_width + rail_width * 2.0)
	board_scale = minf(1.0, (SCREEN.x - BOARD_MARGIN * 2.0) / outer.x)
	board_origin = (Vector2(SCREEN.x / 2.0, BOARD_CENTER_Y) - (lo + hi) / 2.0 * board_scale).round()


## Text centered on a point, with an optional outline and a drop below it.
func _text(s: String, center: Vector2, size: int, color: Color, outline := 0, outline_color := Color.BLACK, f: Font = null, drop := 0.0) -> void:
	if s.is_empty():
		return
	if f == null:
		f = font
	var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := Vector2(center.x - sz.x / 2.0, center.y + f.get_ascent(size) - sz.y / 2.0)
	if outline > 0:
		if drop > 0.0:
			draw_string_outline(f, pos + Vector2(0, drop), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline * 2, outline_color)
			draw_string(f, pos + Vector2(0, drop), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_color)
		draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline * 2, outline_color)
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw_belt() -> void:
	var path := belt_path.duplicate()
	path.append(path[0])
	var full := belt_width + rail_width * 2.0
	# soft shadow on the table
	for k in 4:
		var sh := path.duplicate()
		for i in sh.size():
			sh[i] += Vector2(4 + k * 2, 12 + k * 3)
		draw_polyline(sh, Color(0.24, 0.12, 0.04, 0.045), full + 6.0 + k * 8.0, true)
	draw_polyline(path, col_rail.darkened(0.22), full + 4.0, true)
	draw_polyline(path, col_rail, full - 2.0, true)
	# the belt is a little darker where it meets the rails
	draw_polyline(path, col_belt.darkened(0.12), belt_width + 2.0, true)
	draw_polyline(path, col_belt.darkened(0.05), belt_width - 4.0, true)
	draw_polyline(path, col_belt, belt_width - 16.0, true)
	# direction chevrons
	var count := maxi(1, int(level.loop_length / arrow_spacing))
	for i in count:
		var d: float = (i + 0.5) * level.loop_length / count
		var p := _round_point(d)
		var f: Vector2 = (_round_point(d + 3.0) - _round_point(d - 3.0)).normalized() * level.travel_sign()
		var s := f.orthogonal()
		var chev := PackedVector2Array([p - f * 11 + s * 19, p + f * 11, p - f * 11 - s * 19])
		draw_polyline(chev, col_arrow.darkened(0.15), 13.0, true)
		draw_polyline(chev, col_arrow, 10.0, true)
		for q in chev:
			draw_circle(q, 5.0, col_arrow)


func _draw_tray(t: int) -> void:
	var offset := Vector2.ZERO
	if wobble.has(t):
		var age: float = time_sec - wobble[t]
		if age > wobble_time:
			wobble.erase(t)
		else:
			offset = level.tray_dir[t].orthogonal() * sin(age * wobble_speed) * wobble_px * (1.0 - age / wobble_time)
	var dir: Vector2 = level.tray_dir[t]
	var facing := "right" if dir.x > 0 else "left" if dir.x < 0 else "down" if dir.y > 0 else "up"
	var center: Vector2 = level.tray_pos[t] + offset
	var tt: Texture2D = tex["tray_" + facing]
	draw_texture(tt, (center - tt.get_size() / 2.0).round())
	var tray: Array = board.trays[t]
	# Cubes whose jelly is still flowing in (slot -> how much has arrived) or out.
	var arriving: Dictionary = goo.sim.tray_fill(t) if goo_on else {}
	if board.set_flags[t] and arriving.is_empty():
		var slab: Texture2D = (slab_tex_v if dir.x == 0.0 else slab_tex_h)[tray[0]]
		draw_texture(slab, (center - slab.get_size() / 2.0).round())
		_draw_sparkles(center, dir.x == 0.0)
		return
	for i in tray.size():
		var c: Vector2 = level.cavity_center(t, i) + offset
		var k := 1.0
		if i == tray.size() - 1 and jiggle.has(t):
			var age: float = time_sec - jiggle[t]
			if age > 0.3:
				jiggle.erase(t)
			else:
				k = 1.0 + 0.12 * sin(age * 30.0) * (1.0 - age / 0.3)
		if arriving.has(i):
			if arriving[i] <= 0.0:
				continue
			k *= sqrt(arriving[i])
		_draw_cube(c, tray[i], k)
	if goo_on:
		for l in goo.sim.tray_leaving(t):
			_draw_cube(level.cavity_center(t, l[0]) + offset, l[1], sqrt(l[2]))


func _draw_cube(center: Vector2, flavor: int, size_factor: float) -> void:
	var t: Texture2D = cube_tex[flavor]
	# Cube sprites are rendered for a 70 px cube.
	var s: Vector2 = t.get_size() * size_factor * cube_size / 70.0
	draw_texture_rect(t, Rect2(center - s / 2.0, s), false)


func _draw_sparkles(center: Vector2, vertical: bool) -> void:
	var spots := [Vector2(-124, -28), Vector2(116, -44), Vector2(20, 32), Vector2(-40, -68)]
	var sizes := [78.0, 52.0, 36.0, 30.0]
	var st: Texture2D = tex["sparkle"]
	for i in spots.size():
		var o: Vector2 = spots[i]
		if vertical:
			o = Vector2(o.y, o.x)
		var tw := 0.75 + 0.25 * sin(time_sec * 3.0 + i * 1.7)
		var sz: float = sizes[i] / 60.0 * (st.get_width() - 2.0 * ART_PAD) * tw
		var full := st.get_size() * sz / (st.get_width() - 2.0 * ART_PAD)
		draw_texture_rect(st, Rect2(center + o - full / 2.0, full), false)


## Jelly riding the belt, filling a cup. Cubes that left a tray together share
## a position in the rules, so they're drawn one behind the other.
func _draw_riding_cubes() -> void:
	var at_pos := {}
	var carry := 0.0 if dead_end or paused else belt_carry
	var cup: Texture2D = tex["cup"]
	for r in board.riding:
		var k: int = at_pos.get(r.y, 0)
		at_pos[r.y] = k + 1
		var p := _belt_draw_point(r.y + carry - k * cube_gap)
		var at := (p - cup.get_size() / 2.0).round()
		draw_texture(cup, at)
		draw_texture(cup_fill_tex[r.x], at)


## The window cake: a card with the order's name on a ribbon and one pane per
## tray, filled with the tray's flavor once it sets.
func _draw_cake() -> void:
	draw_texture(tex["card"], CARD_POS - Vector2.ONE * ART_PAD)
	if window_cake != null:
		_draw_window_cake()
		return
	_text(level.title, RIBBON_CENTER, 46, Color.WHITE, 4, Color("a8264a"), font, 2.0)
	if level.customer != "":
		_text("for " + level.customer, Vector2(540, CUSTOMER_Y), 30, Color("a06a3f"), 0, Color.BLACK, font_semibold)
	var n: int = level.tray_count()
	var cols: int = level.cake_cols
	if cols <= 0:
		cols = n if n <= 3 else ceili(n / 2.0)
	var rows := ceili(float(n) / cols)
	var inner := CAKE_GRID.grow(-CAKE_GRID_PAD)
	var pw := (inner.size.x - CAKE_GRID_GAP * (cols - 1)) / cols
	var ph := (inner.size.y - CAKE_GRID_GAP * (rows - 1)) / rows
	for i in n:
		var r := Rect2(inner.position + Vector2((i % cols) * (pw + CAKE_GRID_GAP), (i / cols) * (ph + CAKE_GRID_GAP)), Vector2(pw, ph))
		if board.set_flags[i]:
			draw_style_box(pane_boxes[board.trays[i][0]], r)
			draw_style_box(pane_gloss_box, r)
		else:
			draw_style_box(pane_empty_box, r)


## A window cake on the card: this level's panel large on the left, filling
## in flavor by flavor as trays set, and the whole window small on the right
## with the panels of finished levels in color.
func _draw_window_cake() -> void:
	var w = window_cake
	_text(w.title, RIBBON_CENTER, 46, Color.WHITE, 4, Color("a8264a"), font, 2.0)
	var who := "panel %d of %d" % [window_panel + 1, w.panel_count()]
	if w.customer != "":
		who = "for %s  ·  %s" % [w.customer, who]
	_text(who, Vector2(540, CUSTOMER_Y), 30, Color("a06a3f"), 0, Color.BLACK, font_semibold)
	_draw_panel(w, window_panel, PANEL_RECT, true)
	draw_rect(PANEL_RECT.grow(3), LEAD_COLOR, false, 8.0)
	var size := Vector2(WINDOW_RECT.size.x / w.cols, WINDOW_RECT.size.y / w.rows)
	for p in w.panel_count():
		var r := Rect2(WINDOW_RECT.position + Vector2((p % w.cols) * size.x, (p / w.cols) * size.y), size)
		_draw_panel(w, p, r, p == window_panel)
		draw_rect(r, LEAD_COLOR, false, 4.0)
	var done := _window_complete()
	draw_rect(WINDOW_RECT.grow(3), LEAD_COLOR, false, 6.0)
	if done:
		draw_rect(WINDOW_RECT.grow(9), Color("ffd02b"), false, 6.0)
	else:
		var r := Rect2(WINDOW_RECT.position + Vector2((window_panel % w.cols) * size.x, (window_panel / w.cols) * size.y), size)
		draw_rect(r.grow(-3), Color("ee5677"), false, 5.0)
	_text("Window complete" if done else "The whole window", Vector2(WINDOW_RECT.get_center().x, WINDOW_LABEL_Y), 26, Color("a06a3f"), 0, Color.BLACK, font_semibold)


## One panel of a window: clear glass, then each flavor that has set, then the
## lead lines. The level's own panel follows the board; other panels are in
## color once their level has been won.
func _draw_panel(w, panel: int, rect: Rect2, live: bool) -> void:
	var art := _window_art(w)
	var region: Rect2 = w.panel_region(panel)
	draw_texture_rect_region(art["base"], rect, region)
	var won: bool = won_levels.has(_level_id(w.levels[panel]))
	for f in w.panels[panel]:
		var k := 1.0 if won else 0.0
		if live:
			k = clampf((time_sec - glass_since[f]) / GLASS_FILL_SECONDS, 0.0, 1.0) if glass_since.has(f) else 0.0
		if k <= 0.0:
			continue
		var c: Color = flavor_colors[f]
		# The glass eases in and flashes pale on the way, like jelly setting.
		var ease_in := 1.0 - pow(1.0 - k, 3.0)
		c = c.lerp(Color.WHITE, sin(PI * k) * 0.45)
		c.a = ease_in
		draw_texture_rect_region(art[f], rect, region, c)
	draw_texture_rect_region(art["lead"], rect, region)


## The room left on the belt: a pill with one mark per cube the belt can hold.
## With flowing jelly it's a gauge that fills with the flavors riding the belt;
## with cups, free cups are white and cups that hold a cube are faded.
func _draw_cup_pill() -> void:
	if goo_on:
		_draw_space_gauge()
		return
	var label := "Free cups"
	var lsize := 34
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsize).x
	var n: int = level.cups
	var used: int = board.riding.size()
	var icon_w := 48.0
	var gap := 14.0
	var inner_w := lw + 22.0 + n * icon_w + (n - 1) * gap
	var w := inner_w + 64.0
	var r := Rect2(SCREEN.x / 2.0 - w / 2.0, PILL_TOP, w, PILL_HEIGHT)
	draw_style_box(pill_box, r)
	var x := r.position.x + 32.0
	var cy := r.position.y + r.size.y / 2.0
	_text(label, Vector2(x + lw / 2.0, cy), lsize, Color("8a4f22"))
	x += lw + 22.0
	for i in n:
		var free := i < n - used
		var poly := PackedVector2Array([Vector2(x + 6, cy - 14), Vector2(x + 42, cy - 14), Vector2(x + 36, cy + 16), Vector2(x + 12, cy + 16)])
		var edge := Color("c9a77a")
		if free:
			draw_colored_polygon(poly, Color.WHITE)
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, edge, 4.8, true)
		else:
			var faded := Color(edge, 0.35)
			draw_colored_polygon(poly, faded)
		x += icon_w + gap


func _draw_space_gauge() -> void:
	var label := "Belt space"
	var lsize := 34
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lsize).x
	var n: int = level.cups
	var seg_w := 46.0
	var bar := Rect2(0, 0, n * seg_w, 30.0)
	var w := lw + 22.0 + bar.size.x + 64.0
	var r := Rect2(SCREEN.x / 2.0 - w / 2.0, PILL_TOP, w, PILL_HEIGHT)
	draw_style_box(pill_box, r)
	var cy := r.position.y + r.size.y / 2.0
	_text(label, Vector2(r.position.x + 32.0 + lw / 2.0, cy), lsize, Color("8a4f22"))
	bar.position = Vector2(r.position.x + 32.0 + lw + 22.0, cy - bar.size.y / 2.0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("e6d5b8")
	track.set_corner_radius_all(15)
	track.anti_aliasing = true
	draw_style_box(track, bar)
	# One stretch per riding cube, in its flavor, filling from the left.
	var used: int = board.riding.size()
	for i in used:
		var fill := StyleBoxFlat.new()
		fill.bg_color = flavor_colors[board.riding[i].x]
		fill.corner_radius_top_left = 15 if i == 0 else 0
		fill.corner_radius_bottom_left = 15 if i == 0 else 0
		fill.corner_radius_top_right = 15 if i == used - 1 else 0
		fill.corner_radius_bottom_right = 15 if i == used - 1 else 0
		fill.anti_aliasing = true
		draw_style_box(fill, Rect2(bar.position + Vector2(i * seg_w, 0), Vector2(seg_w, bar.size.y)))
	if used > 0:
		draw_rect(Rect2(bar.position + Vector2(10, 4), Vector2(used * seg_w - 20, 5)), Color(1, 1, 1, 0.35))
	# Faint ticks so the room left can be counted.
	for i in range(1, n):
		var x := bar.position.x + i * seg_w
		draw_line(Vector2(x, bar.position.y + 6), Vector2(x, bar.end.y - 6), Color(0.54, 0.31, 0.13, 0.25), 2.0)


func _button_rect(i: int) -> Rect2:
	return Rect2(BUTTON_XS[i], BUTTON_Y, BUTTON_SIZE, BUTTON_SIZE)


func _draw_buttons() -> void:
	var names := ["btn_spare", "btn_undo", "btn_restart"]
	for i in 3:
		draw_texture(tex[names[i]], Vector2(BUTTON_XS[i], BUTTON_Y) - Vector2.ONE * ART_PAD)


func _draw_readouts() -> void:
	var y := 1952.0
	var msg := toast_text if time_sec < toast_until else ""
	if msg != "":
		_text(msg, Vector2(540, y), 30, Color.WHITE, 3, Color("6b3510"), font_semibold)
	elif solver_text != "":
		_text(solver_text, Vector2(540, y), 24, Color(1, 0.97, 0.9, 0.85), 3, Color(0.35, 0.18, 0.06, 0.6), font_semibold)


func _draw_banner() -> void:
	var r := Rect2(Vector2(110, BOARD_CENTER_Y - 150), Vector2(860, 300))
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.2, 0.1, 0.03, 0.25))
	draw_style_box(banner_box, r)
	if board.is_won():
		var head := "Order complete!"
		var line := "Every tray has set. Tap for the next order."
		if window_cake != null and _window_complete():
			head = "Window complete!"
			line = "“%s” is ready. Tap for the next order." % window_cake.title
		elif window_cake != null:
			head = "Panel complete!"
			line = "Panel %d of %d is in the window. Tap for the next one." % [window_panel + 1, window_cake.panel_count()]
		_text(head, r.get_center() + Vector2(0, -40), 64, Color.WHITE, 5, Color("a8264a"), font, 3.0)
		_text(line, r.get_center() + Vector2(0, 58), 30, Color("a06a3f"), 0, Color.BLACK, font_semibold)
	else:
		_text("Gumdrop scratches its head...", r.get_center() + Vector2(0, -40), 52, Color.WHITE, 5, Color("6b3510"), font, 3.0)
		_text("The belt is full and no jelly can land. Undo or restart.", r.get_center() + Vector2(0, 58), 30, Color("a06a3f"), 0, Color.BLACK, font_semibold)


func _draw_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.2, 0.1, 0.03, 0.45))
	draw_style_box(menu_box, MENU_RECT)
	_text("Paused", MENU_RECT.position + Vector2(MENU_RECT.size.x / 2.0, 80), 64, Color.WHITE, 5, Color("a8264a"), font, 3.0)
	_text("Order %d of %d" % [level_index + 1, level_files.size()], MENU_RECT.position + Vector2(MENU_RECT.size.x / 2.0, 160), 32, Color("a06a3f"), 0, Color.BLACK, font_semibold)
	var items := _menu_items()
	for i in items.size():
		var r := _menu_item_rect(i)
		var on: bool = items[i][2]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("8ee04a") if i == 0 else Color("f3e6cf")
		sb.set_corner_radius_all(30)
		sb.border_color = Color("3fae22") if i == 0 else Color("d2b994")
		sb.border_width_bottom = 8
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var ink := Color.WHITE if i == 0 else Color("8a4f22")
		if not on:
			ink.a = 0.35
		_text(items[i][0], r.get_center(), 40, ink, 3 if i == 0 else 0, Color("2f8a17"))
