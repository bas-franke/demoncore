extends Objective
## "Hunt the Fleeing Saint": a living saint prays at a wayside altar. When the demon comes within
## `wake_radius` it flees (SaintEnemy) and the hunt is on: kill it within `time_limit` seconds or
## it ascends. Its HP grows with the run (`hp` + `hp_per_minute` per minute survived).
## params: wake_radius, time_limit, hp, hp_per_minute, speed, model (enemy id whose model it
##         wears), blessing_interval, blessing_damage.

const SAINT_SCENE := preload("res://scenes/objectives/saint/saint.tscn")
const NAMES := ["Saint Aurelian", "Saint Benedicta", "Saint Corvin the Meek", "Saint Ismene",
		"Saint Odran of the Lamps", "Saint Pell the Unburnt", "Blessed Seraphine", "Saint Thaddeus"]

var _saint: SaintEnemy
var _name := "Saint"
var _altar: Node3D
var _zone: BossTelegraph
var _last_pos := Vector3.ZERO
## False when the saint could not be made (missing model data). A freed saint compares == null,
## so this is tracked separately.
var _has_saint := false


func _build() -> void:
	_name = NAMES.pick_random()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_altar = Art.pivot(self)
	var marble := Art.mat(Art.IVORY, 0.55, 0.0, 0.3, false, 0.0, &"marble")
	Art.part(_altar, Art.box(), marble, Vector3(0.0, 0.45, 0.0), Vector3(1.1, 0.9, 0.55))
	Art.part(_altar, Art.box(), Art.mat(Art.CRIMSON.darkened(0.3), 0.9, 0.0, 0.3, false, 0.0, &"cloth"),
			Vector3(0.0, 0.91, 0.0), Vector3(1.2, 0.04, 0.4))
	var c := Props.candles(rng, 4)
	c.position = Vector3(0.0, 0.92, 0.0)
	c.scale = Vector3.ONE * 0.5
	_altar.add_child(c)
	_zone = ObjectiveFX.zone(self)
	status_text = "Approach"
	# The saint kneels at the altar until the demon draws near.
	_saint = _make_saint()
	_has_saint = _saint != null


func _make_saint() -> SaintEnemy:
	var base := ObjectiveFX.enemy_data(str(param("model", "thurible_priest")))
	if base == null:
		return null
	var d := base.duplicate() as EnemyData
	d.display_name = _name
	d.size = base.size * 1.15
	d.max_hp = float(param("hp", 260.0)) + float(param("hp_per_minute", 90.0)) * Game.elapsed / 60.0
	d.speed = float(param("speed", 4.6))
	d.xp_value = 40
	d.knockback_scale = 0.25
	d.behavior = EnemyData.Behavior.CHASE
	var s := SAINT_SCENE.instantiate() as SaintEnemy
	s.setup(d, 1.0)
	s.flee_speed = d.speed
	s.blessing_interval = float(param("blessing_interval", 2.6))
	s.blessing_damage = float(param("blessing_damage", 16.0))
	s.set_physics_process(false)  # kneeling: woken by _on_activated
	Game.spawn.call_deferred(s, global_position + Vector3(0.0, 0.0, 1.0))
	return s


func marker_position() -> Vector3:
	if _saint and is_instance_valid(_saint) and _saint.is_inside_tree():
		return _saint.global_position
	return global_position


func _tick(_delta: float) -> void:
	if not _has_saint:
		fail()  # no model data: nothing to hunt
		return
	# Freed or dying without ascending = slain (ascend() only happens after the hunt failed).
	if not is_instance_valid(_saint) or _saint.is_dying:
		complete()
		return
	if not _saint.is_inside_tree():
		return
	_last_pos = _saint.global_position
	if state == State.DORMANT:
		_zone.show_disc(global_position, 2.0, Art.HOLY_WHITE, 0.0, 0.5, 1.0)
		if _player_distance(_saint.global_position) <= float(param("wake_radius", 16.0)) or _saint.hp < _saint.max_hp:
			activate()
		return
	var limit := float(param("time_limit", 38.0))
	var left := limit - active_time
	progress = 1.0 - clampf(_saint.hp / maxf(_saint.max_hp, 1.0), 0.0, 1.0)
	status_text = "%d%%  %s" % [roundi((1.0 - progress) * 100.0), fmt_time(left)]
	if left <= 0.0:
		_saint.ascend()
		_toast("%s has ascended" % _name, Art.HOLY_WHITE)
		fail()


func _on_activated() -> void:
	_zone.hide_now()
	if _saint and is_instance_valid(_saint):
		_saint.set_physics_process(true)
		_minimap_follow(_saint)
	_toast("%s flees for the heavens!" % _name, Color("9fd4ff"))
	Sfx.play(&"choir", 0.0, -2.0)


func _on_finished(completed: bool) -> void:
	_zone.hide_now()
	if completed:
		global_position = Vector3(_last_pos.x, 0.0, _last_pos.z)
		reset_physics_interpolation()
		ObjectiveFX.corruption_burst(_last_pos, 0.8)
		_toast("%s is martyred" % _name, Art.HELLFIRE)
	elif _saint and is_instance_valid(_saint) and not _saint.is_dying:
		_saint.ascend()
