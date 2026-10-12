class_name WorldBarks
extends Node
## Enemy chatter floating over the battlefield (child node "WorldBarks" of the Dialogue
## autoload, not created in test mode): paladin taunts, villager screams, inquisitor sermons.
## Lines come from data/dialogue/enemies.json pools:
##   enemy_taunt.<enemy id>   said by a living enemy near the demon, every TAUNT_GAP s or so
##   enemy_death.<enemy id>   said where an enemy fell (rarely, rate limited)
## falling back to enemy_taunt.<faction> / enemy_death.<faction> (CharacterRoster factions:
## angel, order, mortal, beast, construct, elemental). Enemy id = its EnemyData file name.
## Text appears as a small Label3D that rises and fades; it never pauses or blocks anything.

const TAUNT_GAP := Vector2(7.0, 13.0)
## Roughly the visible area around the demon.
const TAUNT_RANGE := 17.0
const DEATH_CHANCE := 0.07
const DEATH_GAP := 3.5
const LIFE := 2.6
## Factions for the original enemy roster (CharacterRoster.ENEMIES only lists the newer ones).
const EXTRA_FACTIONS := {
	"choir_wisp": "angel", "dawn_lancer": "angel", "seraph_sentinel": "angel", "ophanim": "angel",
	"archon": "angel", "thurible_priest": "order", "penitent_statue": "construct",
}

var _taunt_cd := 6.0
var _death_cd := 0.0


func _ready() -> void:
	Game.enemy_died.connect(_on_enemy_died)


func _process(delta: float) -> void:
	_death_cd -= delta
	var rs := get_node_or_null(^"/root/RunState")
	if rs == null or rs.get(&"active") != true or get_tree().paused or not is_instance_valid(Game.player):
		return
	_taunt_cd -= delta
	if _taunt_cd > 0.0:
		return
	_taunt_cd = randf_range(TAUNT_GAP.x, TAUNT_GAP.y)
	var e := _pick_taunter()
	if e == null:
		_taunt_cd = 2.0  # nobody close yet; look again soon
	else:
		var text := line_for("enemy_taunt", e.get(&"data"))
		if text != "":
			_float(e, text, Vector3(0.0, _height(e), 0.0), true)


## A formatted line from pool `<kind>.<enemy id>` or `<kind>.<faction>`; "" if there is none.
func line_for(kind: String, data: Variant) -> String:
	if not data is Resource:
		return ""
	var id := (data as Resource).resource_path.get_file().get_basename()
	var d := get_parent()
	var conv_id: String = d.pick("%s.%s" % [kind, id])
	if conv_id == "":
		var meta: Dictionary = CharacterRoster.ENEMIES.get(StringName(id), {})
		var faction := String(meta.get("faction", EXTRA_FACTIONS.get(id, "")))
		if faction != "":
			conv_id = d.pick("%s.%s" % [kind, faction])
	if conv_id == "":
		return ""
	for line: Variant in d.db.get_conv(conv_id)["lines"]:
		if line is Dictionary and line.has("text"):
			return d.format(str(line["text"]))
	return ""


func _on_enemy_died(pos: Vector3, data: Resource) -> void:
	if _death_cd > 0.0 or randf() > DEATH_CHANCE or Game.world == null:
		return
	if is_instance_valid(Game.player) and pos.distance_to(Game.player.global_position) > TAUNT_RANGE:
		return
	var text := line_for("enemy_death", data)
	if text == "":
		return
	_death_cd = DEATH_GAP
	_float(Game.world, text, pos + Vector3(0.0, 1.6, 0.0), false)


## A random living, non-boss enemy within TAUNT_RANGE of the demon (sampled, not exhaustive).
func _pick_taunter() -> Node3D:
	var all := Perf.enemies()  # cached group list; read-only here
	if all.is_empty():
		return null
	var p := Game.player.global_position
	for _i in 12:
		var e := all.pick_random() as Node3D
		if e == null or e.is_in_group(&"boss") or e.get(&"is_dying") == true:
			continue
		if e.global_position.distance_to(p) < TAUNT_RANGE:
			return e
	return null


func _height(e: Node3D) -> float:
	var data: Variant = e.get(&"data")
	var s: Variant = data.get(&"model_scale") if data is Resource else null
	return 2.3 * (float(s) if s is float else 1.0)


## Spawns the rising text under `parent` at local `at`. Holy speech is pale gold, screams red.
func _float(parent: Node3D, text: String, at: Vector3, holy: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.font_size = 26
	l.outline_size = 9
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	l.modulate = Color("f4e3b0") if holy else Color("ffb08a")
	l.width = 420.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.render_priority = 9
	l.position = at
	parent.add_child(l)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(l, "position:y", at.y + 0.7, LIFE).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(LIFE - 0.5)
	tw.tween_callback(l.queue_free)
