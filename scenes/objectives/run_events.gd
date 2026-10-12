class_name RunEvents
extends Node
## Mid-run events (child of the ObjectiveDirector): every so often Heaven does something to the
## whole run: a Crusade invades, a Holy Eclipse empowers every angel (and their sin), or the Pale
## Reaper walks. Data: data/objectives/events.json (timings, per-map weights, each event's fields).
## Each event is an Objective (types crusade / eclipse / reaper) placed on the demon and engaged at
## once, so it shows in the tracker, pays rewards and counts toward the run score.
## Dev: --event=<id> starts one at 3 s. Signals: event_started(id), event_ended(id, success).

signal event_started(id: StringName)
signal event_ended(id: StringName, success: bool)

const DATA_PATH := "res://data/objectives/events.json"
const KIND_TYPE := {"crusade": "crusade", "eclipse": "eclipse", "reaper": "reaper"}
## Default tracker glyph + colour per kind.
const KIND_LOOK := {"crusade": ["⚔", "f2c66b"], "eclipse": ["◐", "c46bff"], "reaper": ["☠", "d8d8e8"]}

var director: ObjectiveDirector
var events: Array[Dictionary] = []
var settings: Dictionary = {}
var started := 0
var succeeded := 0
var enabled := true

var _next := 0.0
var _active: Objective


func _ready() -> void:
	var parsed := ObjectiveDirector._read_json(DATA_PATH)
	settings = parsed.get("settings", {})
	var map_w: Dictionary = (parsed.get("map_weights", {}) as Dictionary).get(director.map_id if director else "", {})
	for e: Variant in parsed.get("events", []):
		if e is Dictionary:
			var d: Dictionary = (e as Dictionary).duplicate(true)
			d["type"] = KIND_TYPE.get(str(d.get("kind", "")), str(d.get("kind", "")))
			d["no_variants"] = true
			d["event"] = true
			d["dormant_life"] = -1.0
			d["params"] = (e as Dictionary).duplicate(true)  # the type scripts read fields via param()
			d["title"] = d.get("name", d.get("title", "Event"))  # tracker row; params.title = banner
			var look: Array = KIND_LOOK.get(str(d.get("kind", "")), ["◆", "fff4cf"])
			if not d.has("glyph"):
				d["glyph"] = look[0]
			if not d.has("color"):
				d["color"] = look[1]
			if map_w.has(str(d.get("id", ""))):
				d["weight"] = float(d.get("weight", 1.0)) * float(map_w[str(d.get("id", ""))])
			events.append(d)
	_next = float(settings.get("first_at", 140.0))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--event="):
			_dev_start.call_deferred(arg.substr(8))


func _process(_delta: float) -> void:
	var p := Game.player
	if not enabled or p == null or not is_instance_valid(p) or p.is_dead or director == null or not director.enabled:
		return
	if is_instance_valid(_active) and not _active.is_finished():
		return
	if Game.elapsed < _next:
		return
	if bool(settings.get("skip_with_boss", true)) and get_tree().get_first_node_in_group(&"boss") != null:
		_next = Game.elapsed + 15.0
		return
	var def := _pick()
	_next = Game.elapsed + randf_range(float(settings.get("gap_min", 110.0)), float(settings.get("gap_max", 170.0)))
	if not def.is_empty():
		start(def)


## Starts an event definition now, on the demon.
func start(def: Dictionary) -> Objective:
	if director == null or Game.player == null:
		return null
	var obj := director.spawn_from_def(def, Game.player.global_position)
	if obj == null:
		return null
	_active = obj
	started += 1
	obj.activate()
	obj.state_changed.connect(_on_event_state_changed)
	event_started.emit(StringName(str(def.get("id", ""))))
	return obj


func find(id: String) -> Dictionary:
	for d in events:
		if str(d.get("id", "")) == id:
			return d
	return {}


func _pick() -> Dictionary:
	var pool: Array[Dictionary] = []
	var total := 0.0
	for d in events:
		if Game.elapsed >= float(d.get("min_time", 0.0)):
			pool.append(d)
			total += float(d.get("weight", 1.0))
	if pool.is_empty():
		return {}
	var roll := randf() * total
	for d in pool:
		roll -= float(d.get("weight", 1.0))
		if roll <= 0.0:
			return d
	return pool.back()


func _on_event_state_changed(obj: Objective) -> void:
	if obj.is_finished():
		var ok := obj.state == Objective.State.COMPLETED
		if ok:
			succeeded += 1
		event_ended.emit(obj.id, ok)


func _dev_start(id: String) -> void:
	await get_tree().create_timer(3.0, false).timeout
	var d := find(id)
	if d.is_empty():
		push_warning("RunEvents: no event '%s'" % id)
	else:
		start(d)
