extends RefCounted
## Global game values, read from res://tuning.json at the project root.
##
## The defaults below are used for any key the file leaves out, so the file
## only needs the values you want to change. Keys starting with "_" are notes
## for people and are ignored. Press T in the running game to reload the file.
##
## tools/sim.py reads rules.tray_capacity from the same file, so the Python
## model and the game always agree on the rules.

const PATH := "res://tuning.json"

const DEFAULTS := {
	"rules": {
		"tray_capacity": 4,
		"default_cups": 4,
	},
	"loop": {
		"belt_speed_px_per_sec": 900.0,
		"riding_cube_gap_px": 50.0,
	},
	"feedback": {
		"wobble_seconds": 0.35,
		"wobble_px": 9.0,
		"wobble_speed": 50.0,
	},
	"solver": {
		"show_readout": true,
		"max_boards": 300000,
		"max_milliseconds": 3000,
	},
	"look": {
		"cube_size_px": 62.0,
		"riding_cube_scale": 0.68,
		"belt_width_px": 58.0,
		"arrow_spacing_px": 150.0,
		"flavors": {
			"cherry": "#e2445c",
			"tangerine": "#f28c38",
			"lemon": "#f2c53d",
			"lime": "#86c046",
			"mint": "#2fb59a",
			"soda": "#5cc6ee",
			"blueberry": "#3f6fd9",
			"grape": "#8e5bc2",
			"raspberry": "#e8619f",
			"cola": "#8a5a3c",
			"licorice": "#3a3348",
			"peach": "#f7a98b",
		},
		"colors": {
			"background": "#f6ebdd",
			"counter": "#d9b48a",
			"counter_edge": "#8a6240",
			"belt": "#c9c2ba",
			"belt_edge": "#9d958c",
			"tray": "#fffaf3",
			"cavity": "#efe3d3",
			"cup": "#ffffff",
			"ink": "#4a3426",
			"ink_soft": "#8c7462",
		},
	},
}

# The loaded values live on the Engine singleton rather than in static vars,
# which didn't keep their values when assigned from static functions in
# headless runs.
const _META := "gumdrop_tuning"


## Reads tuning.json again. Call from the main thread.
static func reload() -> void:
	var data: Dictionary = DEFAULTS.duplicate(true)
	var message := "Tuning loaded"
	if not FileAccess.file_exists(PATH):
		message = "tuning.json not found, using defaults"
		push_warning(message)
	else:
		var json := JSON.new()
		var err := json.parse(FileAccess.get_file_as_string(PATH))
		if err != OK or typeof(json.data) != TYPE_DICTIONARY:
			message = "tuning.json line %d: %s" % [json.get_error_line(), json.get_error_message()]
			push_error(message)
		else:
			_merge(data, json.data, "")
	Engine.set_meta(_META, {"data": data, "message": message})


## What happened on the last load, for showing in the game.
static func last_message() -> String:
	return _state()["message"]


static func _state() -> Dictionary:
	if not Engine.has_meta(_META):
		reload()
	return Engine.get_meta(_META)


static func _merge(dst: Dictionary, src: Dictionary, where: String) -> void:
	for k in src:
		if str(k).begins_with("_"):
			continue
		if not dst.has(k):
			push_warning("tuning.json: unknown key %s%s (ignored)" % [where, k])
			continue
		if typeof(dst[k]) == TYPE_DICTIONARY and typeof(src[k]) == TYPE_DICTIONARY:
			_merge(dst[k], src[k], where + str(k) + ".")
		else:
			dst[k] = src[k]


static func value(section: String, key: String):
	return _state()["data"][section][key]


static func num(section: String, key: String) -> float:
	return float(value(section, key))


static func integer(section: String, key: String) -> int:
	return int(value(section, key))


static func flag(section: String, key: String) -> bool:
	return bool(value(section, key))


static func color(key: String) -> Color:
	return Color.html(str(value("look", "colors")[key]))


static func flavor_color(flavor_name: String) -> Color:
	return Color.html(str(value("look", "flavors")[flavor_name]))
