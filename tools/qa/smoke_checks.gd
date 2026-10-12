extends SceneTree
## Headless static smoke checks (QA). Run:
##   godot --headless --path . --script res://tools/qa/smoke_checks.gd
## 1. Loads every .gd/.gdshader/.tres/.tscn under res:// (skips .godot, tools/blender, addons)
##    and instantiates every .tscn (without adding it to the tree, so no _ready runs).
## 2. Loads every .glb under res://assets/models through GlbModel and checks the animation set:
##      demons/, bosses/      : idle walk attack hit death
##      enemies/              : idle walk attack hit death windup
##    (files starting with "_" are examples and only need to load).
## 3. Checks every DemonData under res://data/demons points at an existing .glb.
## Output lines are prefixed QA_OK / QA_FAIL / QA_WARN; final line "QA_SUMMARY ...".
## Exit code = number of QA_FAIL lines (capped at 125).

const SKIP_DIRS := ["res://.godot", "res://tools/blender", "res://tools/qa/results", "res://addons"]
const CHAR_ANIMS := [&"idle", &"walk", &"attack", &"hit", &"death"]
const ENEMY_ANIMS := [&"idle", &"walk", &"attack", &"hit", &"death", &"windup"]

var fails := 0
var warns := 0
var oks := 0


func _init() -> void:
	# Wait one frame so autoloads are in the tree (some scripts reference them at load time).
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	files.sort()
	for f in files:
		var ext := f.get_extension()
		if ext in ["gd", "gdshader", "tres", "tscn"]:
			_check_resource(f)
	var glbs: Array[String] = []
	_collect("res://assets/models", glbs, ["glb"])
	glbs.sort()
	for g in glbs:
		_check_glb(g)
	_check_demons()
	print("QA_SUMMARY ok=%d warn=%d fail=%d" % [oks, warns, fails])
	quit(mini(fails, 125))


func _collect(dir: String, out: Array[String], exts: Array = ["gd", "gdshader", "tres", "tscn"]) -> void:
	for s in SKIP_DIRS:
		if dir.trim_suffix("/") == s:
			return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() in exts:
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_collect(dir.path_join(sub), out, exts)


func _fail(path: String, why: String) -> void:
	fails += 1
	print("QA_FAIL %s :: %s" % [path, why])


func _warn(path: String, why: String) -> void:
	warns += 1
	print("QA_WARN %s :: %s" % [path, why])


func _check_resource(path: String) -> void:
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null:
		_fail(path, "load() returned null")
		return
	if res is Script:
		var sc := res as Script
		# A script with parse/compile errors loads but cannot be instantiated.
		var abstract: bool = sc.has_method(&"is_abstract") and sc.call(&"is_abstract")
		if not sc.can_instantiate() and not abstract:
			_fail(path, "script failed to compile (can_instantiate() == false)")
			return
	elif res is PackedScene:
		var ps := res as PackedScene
		if not ps.can_instantiate():
			_fail(path, "PackedScene cannot be instantiated")
			return
		var inst := ps.instantiate()
		if inst == null:
			_fail(path, "instantiate() returned null")
			return
		inst.free()
	oks += 1


func _check_glb(path: String) -> void:
	var m := GlbModel.create(path)
	if m.scene_root == null:
		_fail(path, "GlbModel could not load the .glb")
		m.free()
		return
	var anims: PackedStringArray = m.anim_player.get_animation_list() if m.anim_player else PackedStringArray()
	var category := path.get_base_dir().get_file()
	var need: Array = []
	if not path.get_file().begins_with("_"):
		match category:
			"demons", "bosses":
				need = CHAR_ANIMS
			"enemies":
				need = ENEMY_ANIMS
	var missing: Array[String] = []
	var soft: Array[String] = []
	var flyer := anims.has("fly") or anims.has("hover")
	for a in need:
		if anims.has(String(a)):
			continue
		# Flyers may loop "fly"/"hover" instead of idle/walk (EnemyModel.move_anim / idle_anim).
		# Hovering enemies (ophanim) set move_anim = &"idle", so "walk" is optional when idle exists.
		if (flyer and a in [&"idle", &"walk"]) or (a == &"walk" and anims.has("idle")):
			soft.append(String(a))
		# Pure chasers never enter WINDUP/ATTACKING; EnemyModel falls back to the loop clip.
		elif category == "enemies" and a in [&"attack", &"windup"]:
			soft.append(String(a))
		# Bosses use bespoke clip names (glide/channel/summon...) driven by their own script.
		elif category == "bosses":
			soft.append(String(a))
		else:
			missing.append(String(a))
	if not missing.is_empty():
		_fail(path, "missing animations %s (has %s)" % [str(missing), str(anims)])
	elif not soft.is_empty():
		_warn(path, "missing %s (has %s; ok only if the model script remaps them / enemy never attacks)" % [str(soft), str(anims)])
	else:
		oks += 1
		print("QA_OK %s anims=%s" % [path, str(anims)])
	m.free()


func _check_demons() -> void:
	var d := DirAccess.open("res://data/demons")
	if d == null:
		_fail("res://data/demons", "directory missing")
		return
	for f in d.get_files():
		if not f.ends_with(".tres"):
			continue
		var path := "res://data/demons".path_join(f)
		var data := load(path)
		if data == null or not data.has_method(&"get_model_path"):
			_fail(path, "not a DemonData")
			continue
		var model: String = data.call(&"get_model_path")
		if not ResourceLoader.exists(model):
			_warn(path, "model %s does not exist (DemonModel will have no Blender mesh)" % model)
		if data.get(&"starting_weapon") == null:
			_warn(path, "no starting_weapon set")
