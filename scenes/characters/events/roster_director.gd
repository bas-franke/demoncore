class_name RosterDirector
extends Node
## Run-time side of the characters-new roster (added to every run by scenes/main.gd):
##  * Sanctified elites: each newly spawned regular enemy may be sanctified (Sanctified.apply) with
##    a chance that starts at `sanctified_start` s and grows per minute, capped, and never more than
##    `sanctified_max` alive at once. Bosses, elites and spawned-only minions are skipped.
##  * The Celestial Leviathan: on open-sky maps (map tag or biome in `whale_maps`), a whale of light
##    passes overhead every `whale_interval` s after `whale_first` s (CelestialWhale).
## Map overrides: a map definition may carry `"characters": {"sanctified_chance_per_minute": 0.01,
## "whale": true, ...}` (any export below by name). Dev: `-- --sanctify-all`, `-- --whale=<seconds>`.

@export var sanctified_start := 90.0
@export var sanctified_base_chance := 0.015
@export var sanctified_chance_per_minute := 0.006
@export var sanctified_max_chance := 0.06
@export var sanctified_max := 4
@export var whale_first := 100.0
@export var whale_interval := 170.0
## Map ids, biomes or tags that get the Celestial Leviathan.
@export var whale_maps: PackedStringArray = PackedStringArray(["heaven", "sky_islands", "storm", "eden", "citadel"])

var _whale_on := false
var _next_whale := 0.0
var _sanctify_all := false


func _ready() -> void:
	name = "RosterDirector"
	var def := _map_def()
	var tags: Array = def.get("tags", [])
	for key in [String(def.get("id", "")), String(def.get("biome", "")), String(def.get("realm", ""))]:
		if key != "" and key in whale_maps:
			_whale_on = true
	for tg in tags:
		if String(tg) in whale_maps:
			_whale_on = true
	var over: Variant = def.get("characters", {})
	if over is Dictionary:
		for k: String in (over as Dictionary).keys():
			if k == "whale":
				_whale_on = bool(over[k])
			elif k in self:
				set(k, over[k])
	_next_whale = whale_first
	for arg in OS.get_cmdline_user_args():
		if arg == "--sanctify-all":
			_sanctify_all = true
		elif arg.begins_with("--whale="):
			_whale_on = true
			_next_whale = arg.substr(8).to_float()
	get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
	if _whale_on and Game.elapsed >= _next_whale and Game.player and not Game.player.is_dead:
		_next_whale = Game.elapsed + whale_interval
		CelestialWhale.spawn_pass()


func _on_node_added(n: Node) -> void:
	var e := n as Enemy
	if e == null:
		return
	# Decide once the enemy is set up (data assigned, in its groups).
	_maybe_sanctify.call_deferred(e)


func _maybe_sanctify(e: Enemy) -> void:
	if not is_instance_valid(e) or e.is_dying or e.data == null or e.is_in_group(&"boss"):
		return
	if e.is_elite() or e.is_in_group(&"champions"):
		return
	var meta: Dictionary = CharacterRoster.ENEMIES.get(e.data.id, {})
	if meta.has("tags") and &"spawned" in (meta["tags"] as Array):
		return
	if not _sanctify_all:
		var t := Game.elapsed
		if t < sanctified_start:
			return
		if get_tree().get_node_count_in_group(&"sanctified") >= sanctified_max:
			return
		var chance := minf(sanctified_base_chance + sanctified_chance_per_minute * (t - sanctified_start) / 60.0, sanctified_max_chance)
		if randf() >= chance:
			return
	Sanctified.apply(e)


func _map_def() -> Dictionary:
	var maps := get_tree().root.get_node_or_null(^"Maps")
	if maps and maps.has_method(&"selected_def"):
		var d: Variant = maps.call(&"selected_def")
		if d is Dictionary:
			return d
	return {}
