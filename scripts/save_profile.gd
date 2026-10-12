class_name SaveProfile
## Save isolation for tests, sims and dev sessions (owned by progression, docs/team/progression.md).
## Every persistent save (Progression, Meta, Dialogue story) asks SaveProfile.path("<file>") for its
## location. Normally that is "user://<file>"; with a profile active it is
## "user://test/<profile>/<file>", so tests never touch (not even temporarily) the player's saves.
##
## Activate a profile, any of:
##   godot ... -- --save-profile=my_check        command line (also accepted: --save-dir=<name>)
##   DEMONCORE_SAVE_PROFILE=my_check godot ...    environment variable
##   SaveProfile.use(&"my_check")                 at runtime (tools), then call load_game() on the autoloads
##                                                (or SaveProfile.use_and_reload(tree, &"my_check"))
## Without any of those, headless runs and --autopilot / --shot= runs use the "bot" profile
## automatically; pass --real-save to opt out.
## SaveProfile.clear() wipes the active profile's folder (fresh state for a test).
## Autoloads should reference this file by preload (no class-cache dependency):
##   const SAVES := preload("res://scripts/save_profile.gd")

const ROOT := "user://test/"
const ENV_VAR := "DEMONCORE_SAVE_PROFILE"

static var _profile := ""
static var _resolved := false


## Active profile name ("" = the real saves).
static func profile() -> String:
	if not _resolved:
		_resolved = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--save-profile="):
				_profile = a.substr(15)
			elif a.begins_with("--save-dir="):
				_profile = a.substr(11)
		if _profile == "" and OS.has_environment(ENV_VAR):
			_profile = OS.get_environment(ENV_VAR)
		# Bots never touch the player's saves: headless runs, --autopilot and --shot= screenshot
		# runs default to the "bot" profile. "--real-save" opts out (e.g. a deliberate save migration).
		var args := OS.get_cmdline_user_args()
		if _profile == "" and not "--real-save" in args:
			var bot := "--autopilot" in args or DisplayServer.get_name() == "headless"
			for a in args:
				bot = bot or a.begins_with("--shot=")
			if bot:
				_profile = "bot"
		_profile = _sanitize(_profile)
	return _profile


static func is_active() -> bool:
	return profile() != ""


## Full path for save file `file` (e.g. "progression.json") under the active profile.
static func path(file: String) -> String:
	var p := profile()
	if p == "":
		return "user://" + file
	var dir := ROOT + p
	DirAccess.make_dir_recursive_absolute(dir)
	return dir + "/" + file


## Switches profile at runtime. Autoloads compute their paths per call, so later saves/loads follow.
static func use(name: String) -> void:
	_resolved = true
	_profile = _sanitize(name)


## Deletes every file in the active profile's folder (no-op for the real saves).
static func clear() -> void:
	if not is_active():
		return
	var dir := DirAccess.open(ROOT + profile())
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)


## use() + clear() + reload the save-owning autoloads present in `tree` (fresh, isolated state).
static func use_and_reload(tree: SceneTree, name: String, wipe: bool = true) -> void:
	use(name)
	if wipe:
		clear()
	for n: String in ["Progression", "Meta"]:
		var node := tree.root.get_node_or_null(NodePath(n))
		if node == null:
			continue
		if wipe and node.has_method(&"reset_progress"):
			node.call(&"reset_progress")
		elif wipe and node.has_method(&"reset_save"):
			node.call(&"reset_save")
		elif node.has_method(&"load_game"):
			node.call(&"load_game")


static func _sanitize(s: String) -> String:
	return s.strip_edges().replace("..", "").replace("/", "_").replace("\\", "_").replace(":", "_")
