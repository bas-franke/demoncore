extends RefCounted
## Audio registry (owner: sfx role): which material and voice each enemy has, and each dialogue
## speaker's blip. Loaded once by the Sfx autoload from res://data/audio/enemy_audio.json.
##
## Resolution order for an EnemyData: its own `hit_material` / `voice` property or meta, then the
## JSON "enemies" entry for its id, then CharacterRoster.ENEMIES faction/tags (characters-new),
## then "keywords" matched against id + display_name, then "default". Results are cached per id.

const PATH := "res://data/audio/enemy_audio.json"
const MATERIALS := [&"flesh", &"stone", &"glass", &"metal", &"holy"]
## Hit / death sound per material (the flesh hit is the original hit_flesh set).
const HIT_SOUND := {
	&"flesh": &"hit_flesh", &"stone": &"hit_stone", &"glass": &"hit_glass", &"metal": &"hit_metal",
	&"holy": &"hit_holy",
}
const DEATH_SOUND := {
	&"flesh": &"death_flesh", &"stone": &"crumble", &"glass": &"angel_shatter",
	&"metal": &"armor_clatter", &"holy": &"light_burst",
}

var _enemies := {}  # String id -> Dictionary
var _keywords: Array = []
var _default := {"material": "flesh", "voice": ""}
var _speakers := {}  # String -> [String sound, float pitch]
var _cache := {}  # StringName id -> [StringName material, StringName voice]


func _init() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("SfxRegistry: %s missing, every enemy sounds like flesh" % PATH)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		push_warning("SfxRegistry: %s is not valid JSON" % PATH)
		return
	_enemies = d.get("enemies", {})
	_keywords = d.get("keywords", [])
	_default = d.get("default", _default)
	_speakers = d.get("speakers", {})


## Material of an enemy (EnemyData or anything with id / display_name), e.g. &"stone".
func material_of(data: Object) -> StringName:
	return _resolve(data)[0]


## Wind-up voice sound of an enemy, or &"" for none.
func voice_of(data: Object) -> StringName:
	return _resolve(data)[1]


## [blip sound, pitch] for a dialogue speaker id. Unknown speakers get a stable mid voice whose
## pitch is derived from the id, so each one still sounds like itself.
func blip_of(speaker: String) -> Array:
	var e: Variant = _speakers.get(speaker)
	if e is Array and (e as Array).size() >= 2:
		return [StringName(str(e[0])), float(e[1])]
	var h := absi(speaker.hash()) % 1000
	return [&"blip_mid", 0.88 + 0.3 * float(h) / 1000.0]


func _resolve(data: Object) -> Array:
	if data == null:
		return [StringName(str(_default.get("material", "flesh"))), &""]
	var id := StringName(str(data.get(&"id"))) if data.get(&"id") != null else &""
	if id != &"" and _cache.has(id):
		return _cache[id]
	var entry: Dictionary = _default.duplicate()
	if _enemies.has(String(id)):
		entry.merge(_enemies[String(id)], true)
	else:
		_roster_guess(id, entry)  # characters-new faction / tags, when the roster knows the id
		# Name keywords are more specific than a faction guess ("glass", "statue"), so they win.
		var hay := (String(id) + " " + str(data.get(&"display_name"))).to_lower()
		for kw: Variant in _keywords:
			if kw is Array and hay.contains(str(kw[0])):
				entry["material"] = str(kw[1])
				break
	# Per-resource overrides (property or meta), so data authors can tag without this file.
	for key: String in ["hit_material", "voice"]:
		var v: Variant = data.get(key)
		if v == null and data.has_meta(key):
			v = data.get_meta(key)
		if v != null and str(v) != "":
			entry["material" if key == "hit_material" else "voice"] = str(v)
	var mat := StringName(str(entry.get("material", "flesh")))
	if not MATERIALS.has(mat):
		mat = &"flesh"
	var out := [mat, StringName(str(entry.get("voice", "")))]
	if id != &"":
		_cache[id] = out
	return out


## Unlisted enemies the characters role registered in CharacterRoster.ENEMIES (faction + tags):
## guess a material and voice from those, so new enemies sound right before anyone edits the JSON.
## Returns false when the roster does not know `id`.
func _roster_guess(id: StringName, entry: Dictionary) -> bool:
	var roster := _roster()
	if roster == null:
		return false
	var all: Variant = roster.get_script_constant_map().get("ENEMIES")
	if not all is Dictionary or not (all as Dictionary).has(id):
		return false
	var meta: Dictionary = all[id]
	var tags: Array = meta.get("tags", [])
	var faction := StringName(str(meta.get("faction", "")))
	var mat := "flesh"
	var voice := ""
	match faction:
		&"construct":
			mat = "stone"
			voice = "voice_grind"
		&"elemental":
			mat = "holy"
			voice = "voice_hum"
		&"angel":
			mat = "metal" if tags.has(&"armored") else "flesh"
			voice = "voice_cherub" if tags.has(&"swarm") else "voice_angel"
		&"order":
			mat = "metal" if tags.has(&"armored") else "flesh"
			voice = "voice_knight"
		&"beast":
			voice = "voice_screech" if tags.has(&"flying") else "voice_roar"
		&"mortal":
			voice = "voice_villager"
	# Siege engines and clockwork are iron and gilt; spawned shades are wisps of light.
	if faction == &"construct":
		if tags.has(&"heaven"):
			mat = "metal"  # gilded clockwork
	elif tags.has(&"armored") or tags.has(&"siege"):
		mat = "metal"
	elif tags.has(&"spawned") and tags.has(&"flying"):
		mat = "holy"
		voice = "voice_hum"
	entry["material"] = mat
	entry["voice"] = voice
	return true


static var _roster_script: Script
static var _roster_looked := false


## CharacterRoster's script (a global class owned by characters-new), or null if it is absent.
static func _roster() -> Script:
	if not _roster_looked:
		_roster_looked = true
		for c: Dictionary in ProjectSettings.get_global_class_list():
			if c.get("class") == &"CharacterRoster":
				_roster_script = load(str(c["path"])) as Script
	return _roster_script
