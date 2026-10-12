extends Node
## Map registry + live-map facade (autoload "Maps").
##
## Registry: every res://data/maps/*.json file is one map definition (see docs/team/maps.md for the
## full schema). Definitions are plain Dictionaries, normalised on load so every documented key exists.
##
##   Maps.all()                    # Array[Dictionary], sorted by "order"
##   Maps.get_def(&"cathedral_city")
##   Maps.select(&"frozen_monastery")      # remembered for the next run (emits map_selected)
##   Maps.start_run(&"sunlit_citadel")     # select + change scene to the run (main.tscn)
##
## During a run the map loader (scenes/maps/map_loader.gd, node Main/Map) builds the selected map
## and registers it here; `Maps.current_map` is then the live GameMap and `map_loaded` fires.
## Spatial helpers below are safe to call at any time: without a bounded map they fall back to the
## plain open-field behaviour (the input is returned unchanged).
##
## Command line (dev): --map=<id> picks the map for the run (e.g. `-- --map=cathedral_city`).

signal map_selected(id: StringName)
## Emitted by the loader once the map is built, the player placed and the spawner configured.
signal map_loaded(map: Node3D, def: Dictionary)
signal map_unloaded(id: StringName)

const MAP_DIR := "res://data/maps/"
const RUN_SCENE := "res://scenes/main.tscn"
const DEFAULT_MAP := &"ruined_sanctum"
const ENEMY_DIR := "res://data/enemies/"
const BOSS_DIR := "res://data/bosses/"

## Defaults merged under every definition (shallow for top level, one level deep for sub-dicts).
const DEFAULTS := {
	"id": "",
	"name": "",
	"subtitle": "",
	"description": "",
	"order": 100,
	"realm": "mortal",
	"biome": "",
	"difficulty": 1,
	"difficulty_minutes": 0.0,
	"scene": "",
	"generator": "",
	"seed": 0,
	"decor": "none",
	"atmosphere_preset": "",
	"music": "backyard",
	"music_fallback": "backyard",
	"ambience": "",
	"weather": {"moods": [], "durations": [], "particles": ""},
	"unlock": {"default": true, "cost": 0, "requires": ""},
	"spawner": {},
	"enemy_pool": [],
	"elite": "",
	"boss": "",
	"env": {},
	"ground": {},
	"portal": {"color": [0.9, 0.3, 0.1], "glyph": ""},
	"tags": [],
}

var _defs := {}  # StringName -> Dictionary
var _order: Array[StringName] = []
## Map picked for the next run.
var selected_id: StringName = DEFAULT_MAP
## The live map node (a GameMap) during a run, else null.
var current_map: GameMap
## Definition of the live map (empty outside a run).
var current_def: Dictionary = {}


func _ready() -> void:
	reload()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			var id := StringName(arg.substr(6))
			if has_map(id):
				selected_id = id
			else:
				push_warning("Maps: unknown --map=%s (known: %s)" % [id, ", ".join(ids())])


# ================================================================ registry

## Re-reads every data/maps/*.json file.
func reload() -> void:
	_defs.clear()
	_order.clear()
	var files := DirAccess.get_files_at(MAP_DIR)
	for f in files:
		# Exported builds may list "x.json.remap"-style names; only plain .json is a definition.
		if not f.ends_with(".json"):
			continue
		var def := _load_def(MAP_DIR + f)
		if def.is_empty():
			continue
		_defs[StringName(def["id"])] = def
	var list: Array = _defs.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["order"]) != int(b["order"]):
			return int(a["order"]) < int(b["order"])
		return String(a["id"]) < String(b["id"]))
	for d: Dictionary in list:
		_order.append(StringName(d["id"]))
	if not _defs.has(selected_id) and not _order.is_empty():
		selected_id = _order[0]


func _load_def(path: String) -> Dictionary:
	var raw := JsonIO.read_dict(path, "Maps")
	if raw.is_empty():
		return {}
	if String(raw.get("id", "")) == "":
		raw["id"] = path.get_file().get_basename()
	var def := DEFAULTS.duplicate(true)
	for k: String in raw:
		if def.has(k) and def[k] is Dictionary and raw[k] is Dictionary:
			(def[k] as Dictionary).merge(raw[k], true)
		else:
			def[k] = raw[k]
	if String(def["name"]) == "":
		def["name"] = String(def["id"]).capitalize()
	def["source"] = path
	return def


## All map definitions, sorted by "order".
func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _order:
		out.append(_defs[id])
	return out


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _order:
		out.append(String(id))
	return out


func has_map(id: StringName) -> bool:
	return _defs.has(id)


## Definition for `id` (empty Dictionary if unknown). Treat it as read-only.
func get_def(id: StringName) -> Dictionary:
	return _defs.get(id, {})


func selected_def() -> Dictionary:
	return get_def(selected_id)


## Picks the map for the next run. Returns false for an unknown id.
func select(id: StringName) -> bool:
	if not has_map(id):
		push_warning("Maps.select: unknown map %s" % id)
		return false
	selected_id = id
	map_selected.emit(id)
	return true


## Selects `id` (if given) and changes scene to the run.
func start_run(id: StringName = &"") -> void:
	if id != &"":
		select(id)
	get_tree().change_scene_to_file(RUN_SCENE)


## Is the map unlocked by default (ignores meta progression, which Meta owns)?
func is_unlocked_by_default(id: StringName) -> bool:
	var u: Dictionary = get_def(id).get("unlock", {})
	return bool(u.get("default", true))


## Display colour for portals / UI ("portal.color" in the definition).
func portal_color(id: StringName) -> Color:
	return color_of(get_def(id).get("portal", {}).get("color", [0.9, 0.3, 0.1]))


## The enemy pool of `id` as loaded EnemyData resources (unknown ids are skipped).
func enemy_pool(id: StringName) -> Array[Resource]:
	var out: Array[Resource] = []
	for e: Dictionary in get_def(id).get("enemy_pool", []):
		var r := load_enemy(String(e.get("enemy", "")))
		if r:
			out.append(r)
	return out


# ================================================================ resource helpers

## "choir_wisp" -> res://data/enemies/choir_wisp.tres; full res:// paths are used as-is.
func load_enemy(key: String) -> Resource:
	return _load_ref(key, ENEMY_DIR)


## "sariel" -> res://data/bosses/sariel.tres; full res:// paths are used as-is.
func load_boss(key: String) -> Resource:
	return _load_ref(key, BOSS_DIR)


func _load_ref(key: String, dir: String) -> Resource:
	if key == "":
		return null
	var path := key if key.begins_with("res://") else dir + key + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("Maps: missing resource %s" % path)
		return null
	return load(path)


## [r, g, b] / [r, g, b, a] / "#hex" -> Color.
static func color_of(v: Variant, fallback := Color.WHITE) -> Color:
	if v is Color:
		return v
	if v is String:
		return Color.from_string(v, fallback)
	if v is Array:
		var a: Array = v
		if a.size() >= 3:
			return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return fallback


# ================================================================ live map (called by the loader)

func _register(map: GameMap, def: Dictionary) -> void:
	current_map = map
	current_def = def
	map.tree_exiting.connect(_on_map_exiting.bind(map), CONNECT_ONE_SHOT)
	# Deferred: listeners get a fully-ready run scene (the loader runs inside Main._ready setup).
	map_loaded.emit.call_deferred(map, def)


func _on_map_exiting(map: GameMap) -> void:
	if current_map != map:
		return
	var id := StringName(current_def.get("id", ""))
	current_map = null
	current_def = {}
	map_unloaded.emit(id)


func _live() -> bool:
	return is_instance_valid(current_map) and current_map.is_inside_tree()


# ================================================================ spatial helpers (safe anytime)

## Enemy steering: `dir` (unit, toward the player) bent around walls using the map's flow field.
func steer(from: Vector3, dir: Vector3) -> Vector3:
	if not _live():
		return dir
	return current_map.steer(from, dir)


## A valid enemy spawn spot near `ideal` (inside the bounds, not inside a wall); some spawns are
## redirected to the map's authored spawn points (gates, chapel doors) when they are in range.
func spawn_position(ideal: Vector3, allow_authored: bool = true) -> Vector3:
	if not _live():
		return ideal
	return current_map.spawn_position(ideal, allow_authored)


## Un-stick nudge for a body pinned against a wall: direction to the centre of the best open nav
## cell nearby, or ZERO when no wall is adjacent (so crowd jams are left alone).
func unstick(from: Vector3, dir: Vector3) -> Vector3:
	if not _live():
		return Vector3.ZERO
	return current_map.unstick(from, dir)


## Nearest walkable position inside the bounds.
func clamp_to_bounds(pos: Vector3) -> Vector3:
	if not _live():
		return pos
	return current_map.clamp_to_bounds(pos)


func is_walkable(pos: Vector3) -> bool:
	if not _live():
		return true
	return current_map.is_walkable(pos)


## Random walkable point at least `min_dist` and at most `max_dist` from `around`.
func random_point(around: Vector3, min_dist: float = 0.0, max_dist: float = 30.0) -> Vector3:
	if not _live():
		var a := randf() * TAU
		return around + Vector3(cos(a), 0.0, sin(a)) * randf_range(min_dist, max_dist)
	return current_map.random_point(around, min_dist, max_dist)


## Landmark markers (Marker3D, group "map_landmark"). Each has meta: id, display_name, radius, tag.
func landmarks(tag: StringName = &"") -> Array[Node3D]:
	if not _live():
		return []
	return current_map.get_landmarks(tag)


## Objective anchor markers (Marker3D, group "map_objective"). Meta: kind, id. kind "" = all.
func objective_points(kind: StringName = &"") -> Array[Node3D]:
	if not _live():
		return []
	return current_map.get_objective_points(kind)


## Authored enemy spawn markers (group "map_enemy_spawn").
func enemy_spawn_points() -> Array[Node3D]:
	if not _live():
		return []
	return current_map.get_enemy_spawn_points()


## Player start position of the live map (Vector3.ZERO without one).
func player_spawn() -> Vector3:
	if not _live():
		return Vector3.ZERO
	return current_map.get_player_spawn()
