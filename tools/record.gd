extends SceneTree
## Saves a run of frames from the game, for checking motion without a phone.
##
##   xvfb-run -s "-screen 0 1200x2400x24" godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##       -s res://tools/record.gd -- out_dir level frames every 30:0 90:3 ...
##
## The level is counted from 0. Each "frame:tray" taps that tray on that frame
## ("frame:u" is Undo). One picture is saved every `every` frames, so
## `ffmpeg -framerate 30 -i out_dir/f%04d.png clip.mp4` with every = 2 plays at
## real speed.

var frame := 0
var saved := 0
var game: Node
var out_dir := "frames"
var total := 120
var every := 2
var taps := {}  # frame -> Array of actions


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	DisplayServer.window_set_size(Vector2i(1080, 2340))
	if args.size() > 1:
		game.call_deferred("_load_level", int(args[1]))
	if args.size() > 2:
		total = int(args[2])
	if args.size() > 3:
		every = maxi(1, int(args[3]))
	for i in range(4, args.size()):
		var parts := args[i].split(":")
		var f := int(parts[0])
		if not taps.has(f):
			taps[f] = []
		taps[f].append(parts[1])


func _process(_delta: float) -> bool:
	frame += 1
	for a in taps.get(frame, []):
		if a == "u":
			game._on_undo()
		else:
			game._on_tray_tapped(int(a))
	if frame > 10 and frame % every == 0:
		root.get_texture().get_image().save_png("%s/f%04d.png" % [out_dir, saved])
		saved += 1
	if frame >= total + 10:
		print("saved %d frames to %s" % [saved, out_dir])
		return true
	return false
