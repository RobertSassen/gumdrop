extends Node2D
## The playable proof of concept: one portrait screen with the window cake on
## top, the kitchen board (loop and setting trays) on an oak table in the
## middle, and the Spare, Undo and Restart buttons below.
##
## The look follows the approved mockup. Sprites, the table, the card and the
## buttons are pictures in art/, made by tools/art/render.js. Jelly sprites are
## white and get their flavor color from tuning.json when the game starts, so
## the palette stays editable without re-rendering art.

const Level = preload("res://scripts/core/level.gd")
const Solver = preload("res://scripts/core/solver.gd")
const Tuning = preload("res://scripts/core/tuning.gd")

const LEVEL_DIR := "res://levels/"
const SCREEN := Vector2(1080, 2340)
## The board is centered on this point, whatever the level's loop shape.
const BOARD_CENTER_Y := 1360.0
## Art pieces are rendered with this much transparent padding around them.
const ART_PAD := 60.0

# Screen layout, in screen pixels.
const PAUSE_RECT := Rect2(60, 60, 104, 104)
const CARD_POS := Vector2(190, 164)
const CAKE_GRID := Rect2(246, 280, 588, 320)
const CAKE_GRID_PAD := 20.0
const CAKE_GRID_GAP := 16.0
const RIBBON_CENTER := Vector2(540, 160)
const CUSTOMER_Y := 242.0
const PILL_TOP := 636.0
const PILL_HEIGHT := 80.0
const BUTTON_Y := 2060.0
const BUTTON_SIZE := 148.0
const BUTTON_XS := [272.0, 466.0, 660.0]
const LABEL_Y := 2256.0

## Values from tuning.json, refreshed by _apply_tuning().
var flavor_colors: Array = []
var col_belt: Color
var col_rail: Color
var col_arrow: Color
var col_ink: Color
var col_ink_soft: Color
var cube_size := 70.0
var riding_scale := 0.86
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

## Fraction of a pixel the belt has moved but the rules haven't seen yet.
var belt_carry := 0.0
var belt_speed := 1400.0
var wobble := {}  # tray -> time the wobble started
var jiggle := {}  # tray -> time a cube last landed in it
var time_sec := 0.0

var dead_end := false
var paused := false
var status_text := ""
var toast_text := ""
var toast_until := 0.0
var solver_text := ""
## Solver runs in flight on worker threads: [{task, solver, board, result, stale}]
var solver_jobs: Array = []

## The drawn belt: the level's loop with rounded corners. Rules still use the
## sharp loop; _belt_draw_point() moves points onto the rounded corners.
var belt_path := PackedVector2Array()
var corners: Array = []  # [{dist, reach, center, radius}]

# Art
var font: Font
var font_semibold: Font
var tex := {}
var cube_tex: Array = []  # per flavor, tinted
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
	Tuning.reload()
	_apply_tuning()
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
	paused = false
	_build_belt_path()
	_evaluate()


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
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
	var bp := p - board_origin
	for t in level.tray_count():
		if level.tray_rect(t).grow(12).has_point(bp):
			_on_tray_tapped(t)
			return


func _on_tray_tapped(t: int) -> void:
	if dead_end or board.is_won():
		return
	if not board.can_tap(t):
		wobble[t] = time_sec
		return
	history.append(board.copy())
	board.tap(t)
	_evaluate()


func _on_spare() -> void:
	_toast("The spare ramekin isn't in the prototype yet.")


func _on_undo() -> void:
	if history.is_empty():
		return
	board = history.pop_back()
	belt_carry = 0.0
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
	if board != null and not dead_end and not paused and not board.riding.is_empty():
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
	riding_scale = Tuning.num("look", "riding_cube_scale")
	cube_gap = Tuning.num("loop", "riding_cube_gap_px")
	belt_width = Tuning.num("look", "belt_width_px")
	rail_width = Tuning.num("look", "rail_width_px")
	corner_radius = Tuning.num("look", "belt_corner_radius_px")
	arrow_spacing = maxf(Tuning.num("look", "arrow_spacing_px"), 40.0)
	wobble_time = maxf(Tuning.num("feedback", "wobble_seconds"), 0.01)
	wobble_px = Tuning.num("feedback", "wobble_px")
	wobble_speed = Tuning.num("feedback", "wobble_speed")
	belt_speed = maxf(Tuning.num("loop", "belt_speed_px_per_sec"), 1.0)
	_make_jelly_art()
	_make_styles()


## Tints the white jelly sprites with each flavor color: shadow, then the body
## multiplied by the color, then the gloss added on top.
func _make_jelly_art() -> void:
	cube_tex = []
	slab_tex_h = []
	slab_tex_v = []
	var layers := {}
	for n in ["cube", "slab_h", "slab_v"]:
		layers[n] = []
		for k in ["shadow", "body", "gloss"]:
			var img: Image = load("res://art/%s_%s.png" % [n, k]).get_image()
			img.convert(Image.FORMAT_RGBA8)
			layers[n].append(img)
	for c in flavor_colors:
		cube_tex.append(ImageTexture.create_from_image(_tint(layers["cube"], c, 0.0)))
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
			# The body is rendered softly lit; a square curve brings back the
			# darker sides of the mockup. The gloss loses its faint overall
			# haze so only real highlights brighten the color.
			var shade := Color(b.r * b.r, b.g * b.g, b.b * b.b)
			var col := Color(shade.r * c.r, shade.g * c.g, shade.b * c.b).lerp(Color.WHITE, glow)
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


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	draw_texture(tex["background"], Vector2.ZERO)
	if level == null:
		_text(status_text, Vector2(SCREEN.x / 2, 1200), 40, Color.WHITE, 4, col_ink)
		return
	_layout_board()
	draw_set_transform(board_origin)
	_draw_belt()
	for t in level.tray_count():
		_draw_tray(t)
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


## Centers the level's loop in the board area.
func _layout_board() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in level.loop:
		lo = lo.min(p)
		hi = hi.max(p)
	board_origin = Vector2(SCREEN.x / 2.0 - (lo.x + hi.x) / 2.0, BOARD_CENTER_Y - (lo.y + hi.y) / 2.0).round()


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
		draw_polyline(sh, Color(0.24, 0.12, 0.04, 0.07), full + 6.0 + k * 8.0, true)
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
	if board.set_flags[t]:
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
		_draw_cube(c, tray[i], k)


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


## Cubes riding the belt, each in a cup. Cubes that left a tray together share
## a position in the rules, so they're drawn one behind the other.
func _draw_riding_cubes() -> void:
	var at_pos := {}
	var carry := 0.0 if dead_end or paused else belt_carry
	var cup: Texture2D = tex["cup"]
	for r in board.riding:
		var k: int = at_pos.get(r.y, 0)
		at_pos[r.y] = k + 1
		var p := _belt_draw_point(r.y + carry - k * cube_gap)
		draw_texture(cup, (p - cup.get_size() / 2.0).round())
		_draw_cube(p + Vector2(0, -8), r.x, riding_scale)


## The window cake: a card with the order's name on a ribbon and one pane per
## tray, filled with the tray's flavor once it sets.
func _draw_cake() -> void:
	draw_texture(tex["card"], CARD_POS - Vector2.ONE * ART_PAD)
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


## The free cups: a pill with one cup icon per cup. Free cups are white,
## cups that hold a riding cube are faded.
func _draw_cup_pill() -> void:
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


func _button_rect(i: int) -> Rect2:
	return Rect2(BUTTON_XS[i], BUTTON_Y, BUTTON_SIZE, BUTTON_SIZE)


func _draw_buttons() -> void:
	var names := ["btn_spare", "btn_undo", "btn_restart"]
	var labels := ["Spare", "Undo", "Restart"]
	for i in 3:
		var mod := Color.WHITE
		draw_texture(tex[names[i]], Vector2(BUTTON_XS[i], BUTTON_Y) - Vector2.ONE * ART_PAD, mod)
		_text(labels[i], Vector2(BUTTON_XS[i] + 74.0, LABEL_Y), 38, Color(1, 1, 1, mod.a), 4, Color("6b3510", mod.a), font, 2.0)


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
		_text("Order complete!", r.get_center() + Vector2(0, -40), 64, Color.WHITE, 5, Color("a8264a"), font, 3.0)
		_text("Every tray has set. Tap for the next order.", r.get_center() + Vector2(0, 58), 30, Color("a06a3f"), 0, Color.BLACK, font_semibold)
	else:
		_text("Gumdrop scratches its head...", r.get_center() + Vector2(0, -40), 52, Color.WHITE, 5, Color("6b3510"), font, 3.0)
		_text("Every cup is full and no cube can land. Undo or restart.", r.get_center() + Vector2(0, 58), 30, Color("a06a3f"), 0, Color.BLACK, font_semibold)


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
