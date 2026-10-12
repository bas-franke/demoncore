class_name CharacterRoster
## Registry of the procedural characters (characters-new, docs/team/characters-new.md):
## the holy enemy roster (EnemyData in res://data/enemies/<id>.tres, models in
## res://scenes/characters/enemies/), demonic ally models (res://data/allies/allies.json) and
## Basecamp NPC models (res://data/npcs/npcs.json).
##
##   var data := CharacterRoster.enemy_data(&"paladin")              # EnemyData
##   spawner.rules.append_array(CharacterRoster.spawn_rules([&"mortal"]))
##   var imp := CharacterRoster.make_ally(&"imp")                    # ProcModel, add as a visual
##   var pip := CharacterRoster.spawn_npc(hub, &"pip", Vector3(3, 0, 1), PI)

## Enemy metadata: faction, tier (1 fodder .. 4 elite), tags (realm / theme, used by maps and
## spawn_rules), the suggested first appearance (s into a run) and spawn weight.
const ENEMIES := {
	&"cherub": {"faction": &"angel", "tier": 1, "tags": [&"heaven", &"swarm", &"flying"], "start": 0.0, "weight": 5.0},
	&"seraph": {"faction": &"angel", "tier": 2, "tags": [&"heaven", &"ranged", &"flying"], "start": 60.0, "weight": 3.0},
	&"throne": {"faction": &"angel", "tier": 3, "tags": [&"heaven", &"charger"], "start": 120.0, "weight": 2.0},
	&"archangel": {"faction": &"angel", "tier": 4, "tags": [&"heaven", &"elite", &"slam"], "start": 300.0, "weight": 0.3},
	&"paladin": {"faction": &"order", "tier": 3, "tags": [&"mortal", &"heaven", &"slam", &"armored"], "start": 120.0, "weight": 2.0},
	&"holy_knight": {"faction": &"order", "tier": 2, "tags": [&"mortal", &"melee"], "start": 30.0, "weight": 4.0},
	&"inquisitor": {"faction": &"order", "tier": 2, "tags": [&"mortal", &"ranged"], "start": 60.0, "weight": 3.0},
	&"grand_inquisitor": {"faction": &"order", "tier": 4, "tags": [&"mortal", &"elite", &"ranged"], "start": 300.0, "weight": 0.2},
	&"monk": {"faction": &"order", "tier": 2, "tags": [&"mortal", &"charger", &"snow"], "start": 20.0, "weight": 4.0},
	&"censer_nun": {"faction": &"order", "tier": 2, "tags": [&"mortal", &"ranged"], "start": 45.0, "weight": 3.0},
	&"zealot": {"faction": &"order", "tier": 1, "tags": [&"mortal", &"swarm", &"melee"], "start": 30.0, "weight": 3.0},
	&"villager_torch": {"faction": &"mortal", "tier": 1, "tags": [&"mortal", &"swarm", &"urban"], "start": 0.0, "weight": 4.0},
	&"villager_pitchfork": {"faction": &"mortal", "tier": 1, "tags": [&"mortal", &"swarm", &"urban"], "start": 0.0, "weight": 4.0},
	&"holy_lion": {"faction": &"beast", "tier": 2, "tags": [&"heaven", &"leaper"], "start": 40.0, "weight": 3.0},
	&"griffon": {"faction": &"beast", "tier": 2, "tags": [&"heaven", &"charger", &"flying"], "start": 100.0, "weight": 2.5},
	&"unicorn": {"faction": &"beast", "tier": 2, "tags": [&"heaven", &"charger"], "start": 70.0, "weight": 3.0},
	&"pegasus": {"faction": &"beast", "tier": 2, "tags": [&"heaven", &"flying"], "start": 50.0, "weight": 3.0},
	&"saint_statue": {"faction": &"construct", "tier": 3, "tags": [&"mortal", &"slam", &"armored"], "start": 120.0, "weight": 1.5},
	&"glass_golem": {"faction": &"construct", "tier": 3, "tags": [&"mortal", &"urban", &"armored"], "start": 160.0, "weight": 1.5},
	&"valkyrie": {"faction": &"angel", "tier": 2, "tags": [&"heaven", &"snow", &"leaper"], "start": 80.0, "weight": 3.0},
	&"light_elemental": {"faction": &"elemental", "tier": 2, "tags": [&"heaven", &"ranged", &"flying"], "start": 70.0, "weight": 2.5},
	# Round 2.
	&"ophan": {"faction": &"angel", "tier": 1, "tags": [&"heaven", &"swarm", &"flying"], "start": 0.0, "weight": 5.0},
	&"cherubim": {"faction": &"angel", "tier": 3, "tags": [&"heaven", &"charger", &"armored"], "start": 150.0, "weight": 1.5},
	&"martyr": {"faction": &"mortal", "tier": 1, "tags": [&"mortal", &"urban", &"melee"], "start": 40.0, "weight": 3.0},
	&"martyr_shade": {"faction": &"mortal", "tier": 1, "tags": [&"spawned", &"flying"], "start": 0.0, "weight": 0.0},
	&"plague_doctor": {"faction": &"order", "tier": 2, "tags": [&"mortal", &"urban", &"ranged"], "start": 70.0, "weight": 2.5},
	&"choir_wraith": {"faction": &"angel", "tier": 1, "tags": [&"mortal", &"ranged", &"flying"], "start": 30.0, "weight": 3.0},
	&"bell_gargoyle": {"faction": &"construct", "tier": 2, "tags": [&"mortal", &"urban", &"leaper"], "start": 90.0, "weight": 2.5},
	&"templar_ballista": {"faction": &"order", "tier": 3, "tags": [&"mortal", &"ranged", &"siege"], "start": 180.0, "weight": 1.2},
	&"mobile_reliquary": {"faction": &"order", "tier": 3, "tags": [&"mortal", &"heaven", &"support", &"siege"], "start": 150.0, "weight": 1.2},
	&"witch_hunter_captain": {"faction": &"order", "tier": 3, "tags": [&"mortal", &"charger"], "start": 140.0, "weight": 1.5},
	&"light_wyrm": {"faction": &"beast", "tier": 2, "tags": [&"heaven", &"ranged", &"flying"], "start": 90.0, "weight": 2.5},
	&"frost_hermit": {"faction": &"order", "tier": 2, "tags": [&"mortal", &"snow", &"ranged"], "start": 30.0, "weight": 3.0},
	&"clockwork_cherub": {"faction": &"construct", "tier": 1, "tags": [&"heaven", &"swarm", &"bomber"], "start": 45.0, "weight": 3.0},
	&"dryad_priestess": {"faction": &"elemental", "tier": 2, "tags": [&"heaven", &"support"], "start": 60.0, "weight": 2.0},
	&"exorcist": {"faction": &"order", "tier": 2, "tags": [&"mortal", &"ranged", &"drain"], "start": 100.0, "weight": 2.0},
	# Round 3.
	&"mounted_knight": {"faction": &"order", "tier": 3, "tags": [&"mortal", &"charger"], "start": 120.0, "weight": 1.5},
	&"crossbow_militia": {"faction": &"mortal", "tier": 2, "tags": [&"mortal", &"urban", &"ranged", &"squad"], "start": 60.0, "weight": 2.5},
	&"flagellant": {"faction": &"mortal", "tier": 1, "tags": [&"mortal", &"melee", &"frenzy"], "start": 30.0, "weight": 3.0},
	&"holy_water_friar": {"faction": &"order", "tier": 2, "tags": [&"mortal", &"urban", &"ranged", &"area"], "start": 70.0, "weight": 2.5},
	&"mortal_choir": {"faction": &"mortal", "tier": 2, "tags": [&"mortal", &"urban", &"support", &"squad"], "start": 90.0, "weight": 1.5},
	&"dominion": {"faction": &"angel", "tier": 3, "tags": [&"heaven", &"support", &"armored"], "start": 150.0, "weight": 1.2},
	&"virtue": {"faction": &"angel", "tier": 2, "tags": [&"heaven", &"support", &"flying"], "start": 120.0, "weight": 1.2},
	&"power": {"faction": &"angel", "tier": 3, "tags": [&"heaven", &"armored", &"melee", &"hunter"], "start": 140.0, "weight": 1.5},
	&"gryphon_rider": {"faction": &"beast", "tier": 3, "tags": [&"heaven", &"leaper", &"flying"], "start": 110.0, "weight": 1.5},
	&"herald_trumpeter": {"faction": &"angel", "tier": 2, "tags": [&"heaven", &"summoner"], "start": 80.0, "weight": 1.5},
	&"paschal_lamb": {"faction": &"beast", "tier": 1, "tags": [&"heaven", &"mortal", &"sacrifice"], "start": 45.0, "weight": 1.5},
	# Round 4: map signature enemies ("signature" tag + "map": the only map whose pool has them).
	&"icebound_penitent": {"faction": &"mortal", "tier": 2, "tags": [&"snow", &"armored", &"signature"], "start": 0.0, "weight": 0.0, "map": &"frozen_monastery"},
	&"bell_ringer_monk": {"faction": &"order", "tier": 2, "tags": [&"snow", &"area", &"signature"], "start": 0.0, "weight": 0.0, "map": &"frozen_monastery"},
	&"watch_pikeman": {"faction": &"mortal", "tier": 2, "tags": [&"urban", &"melee", &"signature"], "start": 0.0, "weight": 0.0, "map": &"cathedral_city"},
	&"rooftop_archer": {"faction": &"mortal", "tier": 2, "tags": [&"urban", &"ranged", &"signature"], "start": 0.0, "weight": 0.0, "map": &"cathedral_city"},
	&"thorn_guardian": {"faction": &"elemental", "tier": 3, "tags": [&"heaven", &"armored", &"signature"], "start": 0.0, "weight": 0.0, "map": &"outer_gardens"},
	&"hummingbird_cherub": {"faction": &"beast", "tier": 1, "tags": [&"heaven", &"swarm", &"flying", &"signature"], "start": 0.0, "weight": 0.0, "map": &"outer_gardens"},
	&"sun_priest": {"faction": &"order", "tier": 2, "tags": [&"heaven", &"ranged", &"signature"], "start": 0.0, "weight": 0.0, "map": &"sunlit_citadel"},
	&"golden_legionary": {"faction": &"angel", "tier": 2, "tags": [&"heaven", &"armored", &"melee", &"signature"], "start": 0.0, "weight": 0.0, "map": &"sunlit_citadel"},
	&"crusader_revenant": {"faction": &"order", "tier": 2, "tags": [&"melee", &"undying", &"signature"], "start": 0.0, "weight": 0.0, "map": &"ashen_wastes"},
	&"carrion_angel": {"faction": &"angel", "tier": 2, "tags": [&"leaper", &"flying", &"signature"], "start": 0.0, "weight": 0.0, "map": &"ashen_wastes"},
	&"rod_acolyte": {"faction": &"order", "tier": 2, "tags": [&"ranged", &"signature"], "start": 0.0, "weight": 0.0, "map": &"storm_spire"},
	&"cloud_djinn": {"faction": &"elemental", "tier": 3, "tags": [&"flying", &"blinker", &"signature"], "start": 0.0, "weight": 0.0, "map": &"storm_spire"},
	&"mimic_reliquary": {"faction": &"construct", "tier": 3, "tags": [&"ambusher", &"signature"], "start": 0.0, "weight": 0.0, "map": &"gilded_isles"},
	&"gilded_harpy": {"faction": &"beast", "tier": 2, "tags": [&"leaper", &"flying", &"drain", &"signature"], "start": 0.0, "weight": 0.0, "map": &"gilded_isles"},
	&"gate_warden": {"faction": &"angel", "tier": 3, "tags": [&"heaven", &"armored", &"support", &"signature"], "start": 0.0, "weight": 0.0, "map": &"heavens_gate"},
	&"honour_guard": {"faction": &"angel", "tier": 3, "tags": [&"heaven", &"charger", &"pair", &"signature"], "start": 0.0, "weight": 0.0, "map": &"heavens_gate"},
}

const ENEMY_DIR := "res://data/enemies/"
const ALLIES_JSON := "res://data/allies/allies.json"
const NPCS_JSON := "res://data/npcs/npcs.json"

static var _allies := {}
static var _npcs := {}


## Every roster enemy id.
static func enemy_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in ENEMIES.keys():
		out.append(k)
	return out


## Roster ids that carry every tag in `tags` (empty = all), optionally limited to `faction`.
static func enemies_with(tags: Array = [], faction: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in ENEMIES.keys():
		var e: Dictionary = ENEMIES[k]
		if faction != &"" and e["faction"] != faction:
			continue
		var ok := true
		for tg in tags:
			if not (StringName(tg) in e["tags"]):
				ok = false
				break
		if ok:
			out.append(k)
	return out


## Loads res://data/enemies/<id>.tres (null if missing).
static func enemy_data(id: StringName) -> EnemyData:
	var path := ENEMY_DIR + String(id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as EnemyData


## SpawnRules for the roster enemies matching `tags` (see enemies_with), using each entry's
## suggested start time (x `time_scale`) and weight (x `weight_scale`). Elites (tier 4) are
## included only when `include_elites`.
static func spawn_rules(tags: Array = [], time_scale: float = 1.0, weight_scale: float = 1.0,
		include_elites: bool = false) -> Array[SpawnRule]:
	var out: Array[SpawnRule] = []
	for id in enemies_with(tags):
		var e: Dictionary = ENEMIES[id]
		if (int(e["tier"]) >= 4 and not include_elites) or float(e["weight"]) <= 0.0:
			continue
		var d := enemy_data(id)
		if d == null:
			continue
		var r := SpawnRule.new()
		r.enemy = d
		r.start_time = float(e["start"]) * time_scale
		r.weight = float(e["weight"]) * weight_scale
		out.append(r)
	return out


# ---------------------------------------------------------------- allies

## Ally definitions from res://data/allies/allies.json: id -> {name, scene, role, hp, ...}.
static func allies() -> Dictionary:
	if _allies.is_empty():
		_allies = _load_json(ALLIES_JSON).get("allies", {})
	return _allies


## A fresh ally model (ProcModel; drives itself unless parented to an Enemy, set autoplay =
## false to drive it with animate() yourself). null for an unknown id.
static func make_ally(id: StringName) -> ProcModel:
	var def: Dictionary = allies().get(String(id), {})
	return _instance(def)


# ---------------------------------------------------------------- npcs

## NPC definitions from res://data/npcs/npcs.json: id -> {name, scene, speaker, height, ...}.
static func npcs() -> Dictionary:
	if _npcs.is_empty():
		_npcs = _load_json(NPCS_JSON).get("npcs", {})
	return _npcs


## Instances NPC `id` under `parent` at local `pos`, facing `yaw` (0 = -Z). The model idles and
## gestures by itself; call talk() on it when the player interacts. null for an unknown id.
## `extra` overrides exported variant switches (e.g. {"patrol": [3, 0, 0]}).
static func spawn_npc(parent: Node3D, id: StringName, pos: Vector3 = Vector3.ZERO, yaw: float = 0.0,
		extra: Dictionary = {}) -> ProcModel:
	var def: Dictionary = npcs().get(String(id), {}).duplicate()
	def.merge(extra, true)
	var m := _instance(def)
	if m == null:
		return null
	m.position = pos
	m.rotation.y = yaw
	parent.add_child(m)
	var r := float(def.get("collision", 0.0))
	if r > 0.0:
		add_collision(parent, pos, r, float(def.get("height", 1.8)))
	return m


## A solid cylinder (StaticBody3D, world layer 1) at `pos` under `parent`, so the Basecamp avatar
## walks around an NPC / prop instead of through it. Kept as a sibling of the model so the
## model's turning and scaling never move it.
static func add_collision(parent: Node3D, pos: Vector3, radius: float, height: float) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "NpcCollision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = maxf(height, 0.4)
	cs.shape = cyl
	cs.position.y = cyl.height * 0.5
	sb.add_child(cs)
	sb.position = pos
	parent.add_child(sb)
	return sb


static func _instance(def: Dictionary) -> ProcModel:
	var path := String(def.get("scene", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var m := (load(path) as PackedScene).instantiate() as ProcModel
	if m == null:
		return null
	# Optional exported variant switches from the JSON entry.
	for key in ["outfit", "resting", "tool", "variant", "grand", "task", "barkeep", "patrol"]:
		if def.has(key) and key in m:
			var v: Variant = def[key]
			if m.get(key) is int:
				v = int(v)  # JSON numbers are floats
			elif m.get(key) is Vector3 and v is Array and (v as Array).size() == 3:
				v = Vector3(float(v[0]), float(v[1]), float(v[2]))
			m.set(key, v)
	return m


static func _load_json(path: String) -> Dictionary:
	return JsonIO.read_dict(path, "CharacterRoster")


## Places the Basecamp NPCs listed under "basecamp" in res://data/npcs/npcs.json into `hub`
## (hub-local positions). They idle and gesture by themselves. Entries whose npc has
## "talk": true are wrapped in a HubNpc (an interactable; added through hub.add_interactable when
## the hub has it). Returns npc id -> model (or HubNpc for talkers).
static func populate_basecamp(hub: Node3D) -> Dictionary:
	var out := {}
	for e: Dictionary in _load_json(NPCS_JSON).get("basecamp", []):
		var p: Array = e.get("pos", [0.0, 0.0, 0.0])
		var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var yaw := deg_to_rad(float(e.get("yaw", 0.0)))
		var id := StringName(String(e.get("npc", "")))
		var def: Dictionary = npcs().get(String(id), {})
		if bool(def.get("talk", false)):
			var talker := HubNpc.create(String(id))
			if talker == null:
				continue
			talker.position = at
			talker.rotation.y = yaw
			if hub.has_method(&"add_interactable"):
				hub.call(&"add_interactable", talker)
			else:
				hub.add_child(talker)
			out[id] = talker
			continue
		var extra := {}
		if e.has("patrol"):
			extra["patrol"] = e["patrol"]
		var m := spawn_npc(hub, id, at, yaw, extra)
		if m:
			out[id] = m
	return out
