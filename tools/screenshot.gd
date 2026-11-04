extends SceneTree
## Saves a screenshot of the game for checking layout without a phone.
##
##   xvfb-run godot --path . --rendering-driver opengl3 -s res://tools/screenshot.gd -- out.png [level] [taps...]
##
## Taps are tray indices, played one per half second so the belt can move.

var frames := 0
var game: Node
var args: PackedStringArray
var taps: Array = []
var next_tap_frame := 30


func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	if args.size() > 1:
		game.call_deferred("_load_level", int(args[1]))
	for i in range(2, args.size()):
		taps.append(int(args[i]))


func _process(_delta: float) -> bool:
	frames += 1
	if not taps.is_empty() and frames >= next_tap_frame:
		game._on_tray_tapped(taps.pop_front())
		next_tap_frame = frames + 30
	if taps.is_empty() and frames > next_tap_frame + 20:
		var img := root.get_texture().get_image()
		var out := args[0] if args.size() > 0 else "screenshot.png"
		img.save_png(out)
		print("saved ", out)
		return true
	return false
