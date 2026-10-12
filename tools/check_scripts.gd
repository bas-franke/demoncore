extends SceneTree
## Headless script check: loads every .gd under res:// and reports the ones that fail to compile.
##   godot --headless --path . --script res://tools/check_scripts.gd
## Exits with code 1 if any script is broken. Owned by code-quality (docs/team/code-quality.md).
##
## The work happens on the first process frame, not in _init(): only then are the autoloads
## (Game, Sfx, Settings) registered, so scripts that use them compile.

## Folders that are never scanned (engine cache, add-ons we don't own).
const SKIP_DIRS: Array[String] = [".godot", "addons"]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var files: Array[String] = []
	_collect("res://", files)
	var broken: Array[String] = []
	for path in files:
		# load() keeps the cached copy, so live autoload scripts are not reloaded under our feet.
		var script := load(path) as Script
		# A script with a parse/compile error still loads as a resource but cannot instantiate.
		if script == null or not script.can_instantiate():
			broken.append(path)
	for path in broken:
		print("BROKEN: ", path)
	print("check_scripts: %d scripts, %d broken" % [files.size(), broken.size()])
	quit(1 if broken.size() > 0 else 0)
	return true


func _collect(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if sub in SKIP_DIRS or sub.begins_with("."):
			continue
		_collect(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
