extends Node
## Draws the flowing jelly (goo_sim.gd) and hands the game one picture of it.
##
## Two small off-screen passes, both only re-rendered on frames where the goo
## actually moved:
##   1. the field: every gob as a soft dot, added together, at a quarter of the
##      screen resolution, one color channel per riding flavor;
##   2. the shade: shaders/goo.gdshader turns that field into smooth jelly.
## The game then draws the shaded picture between the trays and the screen UI.

const GooSim = preload("res://scripts/goo/goo_sim.gd")
const Tuning = preload("res://scripts/core/tuning.gd")

const STEP := 1.0 / 60.0
const MAX_CHANNELS := 6
## Field value where jelly starts. A lone gob then shows at about half its dot.
const THRESHOLD := 0.5

var sim := GooSim.new()
var flavor_colors: Array = []
## The part of the board the goo picture covers, in board coordinates.
var rect := Rect2()

var _field_vp: SubViewport
var _shade_vp: SubViewport
var _dots: Node2D
var _quad: ColorRect
var _mat: ShaderMaterial
var _dot_tex: Texture2D
var _dot_radius := 34.0
var _field_scale := 0.25
var _shade_scale := 0.75
var _tiles := 1
var _carry := 0.0
var _visible_gobs := false
## flavor id -> field channel, for the flavors that have gobs right now.
var _channel := {}


func _ready() -> void:
	_field_vp = _make_viewport()
	_dots = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_dots.material = add
	_dots.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_dots.draw.connect(_draw_dots)
	_field_vp.add_child(_dots)

	_shade_vp = _make_viewport()
	_quad = ColorRect.new()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/goo.gdshader")
	_mat.set_shader_parameter("field", _field_vp.get_texture())
	_quad.material = _mat
	_shade_vp.add_child(_quad)


func _make_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(vp)
	return vp


## Reads the goo values from tuning.json. Call before set_belt().
func apply_tuning(colors: Array, belt_speed: float, belt_width: float) -> void:
	flavor_colors = colors
	sim.gobs_per_cube = clampi(Tuning.integer("goo", "gobs_per_cube"), 3, 16)
	sim.spacing = maxf(Tuning.num("goo", "gob_spacing_px"), 8.0)
	sim.clump_length = maxf(Tuning.num("goo", "clump_length_px"), 20.0)
	sim.cling = Tuning.num("goo", "cling")
	sim.slosh = Tuning.num("goo", "slosh")
	sim.jostle = Tuning.num("goo", "jostle")
	sim.belt_speed = belt_speed
	_dot_radius = maxf(Tuning.num("goo", "blob_radius_px"), 8.0)
	# A gob's center stays this far inside the rails, so the jelly's edge
	# reaches them without spilling far over.
	sim.half_width = maxf(belt_width / 2.0 - _dot_radius * 0.42, 2.0)
	_field_scale = clampf(Tuning.num("goo", "field_scale"), 0.1, 1.0)
	_shade_scale = clampf(Tuning.num("goo", "render_scale"), 0.25, 1.0)
	_dot_tex = _make_dot()
	_mat.set_shader_parameter("threshold", THRESHOLD)
	_mat.set_shader_parameter("gloss", Tuning.num("look", "jelly_gloss"))


## Gives the goo the belt it rides on. points: the belt's center line in travel
## order (board coordinates), evenly spaced in rule pixels. cups decides how
## many flavors can ride at once.
func set_belt(points: PackedVector2Array, length: float, cups: int) -> void:
	sim.clear()
	sim.set_path(points, length)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	# Room for the belt's width, a gob's dot and its shadow.
	var margin := sim.half_width + _dot_radius + 20.0
	rect = Rect2(lo - Vector2.ONE * margin, hi - lo + Vector2.ONE * margin * 2.0)
	_tiles = 2 if cups > 3 else 1
	var field_size := Vector2i((rect.size * _field_scale).ceil())
	_field_vp.size = Vector2i(field_size.x * _tiles, field_size.y)
	_shade_vp.size = Vector2i((rect.size * _shade_scale).ceil())
	_quad.size = _shade_vp.size
	_mat.set_shader_parameter("tiles", _tiles)
	_mat.set_shader_parameter("px", Vector2.ONE / rect.size)
	_channel.clear()
	_carry = 0.0
	_refresh()


## The shaded goo, to draw into `rect` on the board. Null when the belt is bare.
func picture() -> Texture2D:
	return _shade_vp.get_texture() if _visible_gobs else null


## Runs the goo for one frame. Returns true while it still moves, which is when
## the game needs to redraw.
func advance(delta: float, moving: bool, positions: PackedFloat32Array) -> bool:
	if sim.asleep and not moving:
		return false
	_carry = minf(_carry + delta, STEP * 3.0)
	var active := true
	var stepped := false
	while _carry >= STEP:
		_carry -= STEP
		active = sim.step(STEP, moving, positions)
		stepped = true
	if stepped:
		_refresh()
	return active


## Re-renders the two goo passes once. Call after anything changes the gobs.
func _refresh() -> void:
	var had := _visible_gobs
	_visible_gobs = sim.gob_count() > 0
	if not _visible_gobs and not had:
		return
	_assign_channels()
	_dots.queue_redraw()
	_field_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_shade_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func refresh() -> void:
	_refresh()


## Gives each flavor on the belt its own field channel and keeps it while that
## flavor has gobs, so colors never swap mid-ride.
func _assign_channels() -> void:
	var present := {}
	for f in sim.flavor:
		present[f] = true
	for f in _channel.keys():
		if not present.has(f):
			_channel.erase(f)
	var limit := mini(MAX_CHANNELS, _tiles * 3)
	for f in present:
		if _channel.has(f):
			continue
		var taken := _channel.values()
		var ch := 0
		while ch < limit - 1 and taken.has(ch):
			ch += 1
		_channel[f] = ch
	var colors := PackedVector3Array()
	colors.resize(MAX_CHANNELS)
	for f in _channel:
		var c: Color = flavor_colors[f]
		colors[_channel[f]] = Vector3(c.r, c.g, c.b)
	_mat.set_shader_parameter("colors", colors)


func _draw_dots() -> void:
	var tile_w := float(_field_vp.size.x) / _tiles
	var size := Vector2.ONE * _dot_radius * 2.0 * _field_scale
	var tints := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]
	for i in sim.pos.size():
		var ch: int = _channel.get(sim.flavor[i], 0)
		var at := (sim.pos[i] - rect.position) * _field_scale + Vector2(tile_w * (ch / 3), 0)
		_dots.draw_texture_rect(_dot_tex, Rect2(at - size / 2.0, size), false, tints[ch % 3])


## One gob's dot: full in the middle, fading smoothly to nothing at the rim.
func _make_dot() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
			var k := clampf(1.0 - r * r, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, k * k))
	return ImageTexture.create_from_image(img)
