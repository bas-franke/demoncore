extends SceneTree
## Dev: compiles every script under res://scenes/characters/ (autoloads present, unlike
## --check-only) and prints the ones that fail. Exit 1 on failure.
##   godot --headless --path . -s res://scenes/characters/_script_check.gd


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var bad := 0
	var n := 0
	for path in _scripts("res://scenes/characters/"):
		if path.ends_with("_script_check.gd") or path.ends_with("_roster_check.gd"):
			continue
		n += 1
		var s := load(path) as GDScript
		if s == null or not s.can_instantiate():
			print("FAIL  ", path)
			bad += 1
	print("script check: %d scripts, %d failed" % [n, bad])
	quit(1 if bad > 0 else 0)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in ResourceLoader.list_directory(dir):
		if f.ends_with("/"):
			out.append_array(_scripts(dir + f))
		elif f.ends_with(".gd"):
			out.append(dir + f)
	return out
