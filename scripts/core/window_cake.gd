extends RefCounted
## One window cake: a stained-glass scene the player fills in over a run of
## levels. The scene is cut into a grid of panels, one per level, and each
## panel holds exactly as many flavors of glass as its level has trays. When a
## tray sets, all the glass of its flavor in that level's panel fills in.
##
## The files in windows/ and the pictures in art/windows/ are both written by
## tools/art/render-windows.js from the scenes in tools/art/windows.js.

const Level = preload("res://scripts/core/level.gd")

const DIR := "res://windows/"

var id: String = ""
var title: String = ""
var customer: String = ""
var cols: int = 2
var rows: int = 2
## Level numbers (1 = the first level file) of the panels, row by row.
var levels: PackedInt32Array = PackedInt32Array()
## Flavor ids of the glass in each panel, in Level.FLAVORS order.
var panels: Array = []
## Size of one panel in the pictures, in pixels.
var panel_px: int = 320


## Every window in windows/, in file order.
static func load_all() -> Array:
	var out := []
	var names := PackedStringArray()
	for f in DirAccess.get_files_at(DIR):
		var fname := f.trim_suffix(".remap").trim_suffix(".import")
		if fname.ends_with(".json") and not names.has(fname):
			names.append(fname)
	names.sort()
	for fname in names:
		var data = JSON.parse_string(FileAccess.get_file_as_string(DIR + fname))
		if typeof(data) != TYPE_DICTIONARY:
			push_error("Window isn't a JSON object: " + fname)
			continue
		var w = load("res://scripts/core/window_cake.gd").new()
		w.from_dict(data)
		out.append(w)
	return out


func from_dict(d: Dictionary) -> void:
	id = d.get("id", "")
	title = d.get("title", "Untitled window")
	customer = d.get("customer", "")
	cols = int(d.get("cols", 2))
	rows = int(d.get("rows", 2))
	panel_px = int(d.get("panel_px", 320))
	levels = PackedInt32Array()
	for n in d.get("levels", []):
		levels.append(int(n))
	panels = []
	for p in d.get("panels", []):
		var ids := []
		for name in p:
			ids.append(Level.flavor_id(name))
		ids.sort()
		panels.append(ids)


func panel_count() -> int:
	return levels.size()


## The panel that level number n (counted from 1) fills, or -1.
func panel_of(level_number: int) -> int:
	return levels.find(level_number)


## Where a panel sits in the window pictures, in pixels.
func panel_region(panel: int) -> Rect2:
	return Rect2((panel % cols) * panel_px, (panel / cols) * panel_px, panel_px, panel_px)


## Maps a level's flavors onto the glass of its panel, lowest flavor id to
## lowest. Swapping flavors doesn't change how a level plays, so the picture
## is free to choose them. Empty if the counts differ.
func flavor_map(panel: int, level_flavors: Array) -> Dictionary:
	var glass: Array = panels[panel]
	if glass.size() != level_flavors.size():
		return {}
	var out := {}
	for i in glass.size():
		out[level_flavors[i]] = glass[i]
	return out
