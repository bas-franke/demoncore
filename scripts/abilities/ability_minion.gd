class_name AbilityMinion
extends Node3D
## A summoned servant: a procedural thrall / wraith / shade / locust, or one of the demonic ally
## models (imp, hellhound, succubus, hell_brute via CharacterRoster.make_ally, driven here with
## autoplay off; casters strike from range). Hunts the nearest angel, strikes it every
## `hit_rate` seconds through AbilityCombat.hit and crumbles after `lifetime`. No physics body:
## it glides over the crowd, so it never blocks the player or enemies.
## Group "ability_minions"; meta &"ability" holds the summoning ability id (for summon limits).

const GROUP := &"ability_minions"
const RETARGET := 0.3
const LEASH := 16.0

var style: StringName = &"thrall"
var damage := 6.0
var speed := 5.0
var lifetime := 10.0
var hit_rate := 0.6
var src := {}
var color := Color.WHITE

var _target: Enemy
var _retarget_t := 0.0
var _hit_t := 0.0
var _age := 0.0
var _body: Node3D
var _dying := false
var _hover := 0.0
## Demonic ally model (CharacterRoster.make_ally) when `style` names one in data/allies/allies.json.
var _model: EnemyModel
## Strike range: melee by default; ally roles "caster" strike from their "range".
var _range := 0.0
var _last_pos := Vector3.ZERO
var _speed_now := 0.0


static func spawn(at: Vector3, ability_id: StringName, p_style: StringName, p_damage: float,
		p_speed: float, p_lifetime: float, p_hit_rate: float, p_src: Dictionary, p_color: Color) -> AbilityMinion:
	if Game.world == null:
		return null
	var m := AbilityMinion.new()
	m.style = p_style
	m.damage = p_damage
	m.speed = p_speed
	m.lifetime = p_lifetime
	m.hit_rate = p_hit_rate
	m.src = p_src
	m.color = p_color
	m.set_meta(&"ability", ability_id)
	Game.spawn(m, at)
	return m


func _ready() -> void:
	add_to_group(GROUP)
	_body = Node3D.new()
	add_child(_body)
	_build()
	_body.scale = Vector3.ONE * 0.1
	create_tween().tween_property(_body, ^"scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	InfernalFx.burst(global_position + Vector3(0.0, 0.3, 0.0), color, 8, 2.0, 0.8)


func _physics_process(delta: float) -> void:
	if _dying:
		return
	_age += delta
	if _age >= lifetime:
		expire()
		return
	var player := Game.player
	_retarget_t -= delta
	if _retarget_t <= 0.0 or not is_instance_valid(_target) or _target.is_dying:
		_retarget_t = RETARGET
		_target = Targeting.nearest_enemy(get_tree(), global_position, 12.0)
	var goal := global_position
	if is_instance_valid(_target) and not _target.is_dying:
		goal = _target.global_position
	elif player:
		# Nothing to hunt: drift back to heel.
		goal = player.global_position + Vector3(cos(_age), 0.0, sin(_age)) * 1.8
	if player and global_position.distance_to(player.global_position) > LEASH:
		global_position = player.global_position + Targeting.flat_dir(player.global_position, global_position) * 3.0
		reset_physics_interpolation()
	var to := goal - global_position
	to.y = 0.0
	var dist := to.length()
	var reach := 0.75 + _range
	if is_instance_valid(_target) and _target.data:
		reach += 0.35 * _target.data.size
	var spd := speed
	if style == &"locust":
		# Erratic swarm flight.
		to += Vector3(sin(_age * 9.0 + get_instance_id()), 0.0, cos(_age * 11.0)) * 1.2
	if dist > reach * 0.6 or style == &"wraith":
		global_position += to.normalized() * minf(spd * delta, maxf(dist, spd * delta * 0.5))
	if to.length_squared() > 0.001:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-12.0 * delta))
	_hit_t -= delta
	if _hit_t <= 0.0 and dist <= reach and is_instance_valid(_target):
		_hit_t = hit_rate
		_strike()
	_animate(delta)
	_speed_now = lerpf(_speed_now, global_position.distance_to(_last_pos) / maxf(delta, 0.001), 0.3)
	_last_pos = global_position


## Crumbles away (also called when a summon cap is exceeded).
func expire() -> void:
	if _dying:
		return
	_dying = true
	remove_from_group(GROUP)
	Abilities.on_minion_expired(self)
	InfernalFx.burst(global_position + Vector3(0.0, 0.4, 0.0), color, 8, 1.8, 0.7)
	var tw := create_tween()
	tw.tween_property(_body, ^"scale", Vector3(0.05, 0.05, 0.05), 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _strike() -> void:
	var s := src.duplicate()
	s["origin"] = global_position
	var amount := damage * Abilities.summon_amp()
	if _range > 0.0:
		AbilityFx.lightning(global_position + Vector3(0.0, 1.3, 0.0), _target.global_position + Vector3(0.0, 0.8, 0.0), color, 0.18, 0.05)
	AbilityCombat.hit(_target, amount, s)
	_hover = 1.0
	if _model:
		_model.play_attack()
	match style:
		&"shade", &"wraith":
			# Cut through and lunge on toward the next foe.
			var next := Targeting.nearest_enemies(get_tree(), global_position, 3, 8.0)
			for e in next:
				if e != _target:
					_target = e
					_retarget_t = RETARGET * 2.0
					break
			InfernalFx.burst(global_position + Vector3(0.0, 0.7, 0.0), color, 5, 2.5, 0.6)
		_:
			InfernalFx.burst(_target.global_position + Vector3(0.0, 0.6, 0.0), color, 4, 1.6, 0.6)


func _animate(delta: float) -> void:
	_hover = move_toward(_hover, 0.0, delta * 5.0)
	if _model:
		_model.ground_speed = _speed_now
		_model.body_scale = 1.0
		_model.state_progress = 0.0
		_model.state_duration = 0.0
		_model.animate(delta, clampf(_speed_now / maxf(speed, 0.01), 0.0, 1.0), EnemyModel.State.MOVING)
		return
	match style:
		&"thrall":
			_body.position.y = absf(sin(_age * 9.0)) * 0.08
			_body.rotation.x = -_hover * 0.5
		&"wraith":
			_body.position.y = 0.9 + sin(_age * 4.0) * 0.15
		&"shade":
			_body.position.y = 0.0
			_body.rotation.x = -_hover * 0.4
		&"locust":
			_body.position.y = 0.8 + sin(_age * 23.0 + get_instance_id()) * 0.2


func _build() -> void:
	var ally: Dictionary = CharacterRoster.allies().get(String(style), {})
	if not ally.is_empty():
		var m := CharacterRoster.make_ally(style)
		if m:
			m.set(&"autoplay", false)
			m.scale = Vector3.ONE * float(ally.get("scale", 1.0))
			_body.add_child(m)
			_model = m
			if str(ally.get("role", "")) == "caster":
				_range = float(ally.get("range", 6.0))
			# A faint summoning sigil under its feet in the ability's colour.
			Art.part(_body, Art.torus(0.9, 1.0), Art.glow(color, 1.4, true, 0.5), Vector3(0.0, 0.04, 0.0), Vector3(0.6, 0.04, 0.6))
			return
	var eye := Art.glow(color, 4.0, true, 1.0)
	match style:
		&"thrall":
			var bone := Art.mat(Art.BONE, 0.85)
			Art.part(_body, Art.capsule(0.18, 0.7), bone, Vector3(0.0, 0.55, 0.0), Vector3(1.0, 1.0, 0.8))
			Art.part(_body, Art.sphere(), bone, Vector3(0.0, 1.05, -0.03), Vector3.ONE * 0.3)
			Art.part(_body, Art.sphere(), eye, Vector3(-0.06, 1.07, -0.15), Vector3.ONE * 0.06)
			Art.part(_body, Art.sphere(), eye, Vector3(0.06, 1.07, -0.15), Vector3.ONE * 0.06)
			for side: float in [-1.0, 1.0]:
				Art.part(_body, Art.box(), bone, Vector3(0.22 * side, 0.7, -0.15), Vector3(0.07, 0.07, 0.45), Vector3(0.4, 0.0, 0.0))
			Art.part(_body, Art.cylinder(), Art.glow(color, 1.2, true, 0.35), Vector3(0.0, 0.03, 0.0), Vector3(0.7, 0.02, 0.7))
		&"wraith":
			var ghost := Art.glow(color, 1.8, true, 0.55)
			Art.part(_body, Art.sphere(), ghost, Vector3.ZERO, Vector3(0.45, 0.5, 0.45))
			Art.part(_body, Art.cone(0.5), ghost, Vector3(0.0, 0.0, 0.45), Vector3(0.4, 0.9, 0.4), Vector3(PI * 0.5, 0.0, 0.0))
			Art.part(_body, Art.sphere(), Art.glow(Art.SOUL, 4.0), Vector3(-0.08, 0.05, -0.2), Vector3.ONE * 0.07)
			Art.part(_body, Art.sphere(), Art.glow(Art.SOUL, 4.0), Vector3(0.08, 0.05, -0.2), Vector3.ONE * 0.07)
			InfernalFx.embers(self, color, 8, 0.5, 0.2, Vector3(0.0, 0.9, 0.0), 2.0)
		&"shade":
			var dark := Art.mat(Art.OBSIDIAN, 0.4, 0.2)
			Art.part(_body, Art.capsule(0.22, 1.3), dark, Vector3(0.0, 0.75, 0.0))
			Art.part(_body, Art.cone(0.5), dark, Vector3(-0.12, 1.5, 0.0), Vector3(0.08, 0.3, 0.08), Vector3(0.0, 0.0, 0.3))
			Art.part(_body, Art.cone(0.5), dark, Vector3(0.12, 1.5, 0.0), Vector3(0.08, 0.3, 0.08), Vector3(0.0, 0.0, -0.3))
			Art.part(_body, Art.sphere(), eye, Vector3(-0.07, 1.25, -0.18), Vector3.ONE * 0.06)
			Art.part(_body, Art.sphere(), eye, Vector3(0.07, 1.25, -0.18), Vector3.ONE * 0.06)
			InfernalFx.embers(self, color, 10, 0.5, 0.25, Vector3(0.0, 0.8, 0.0), 1.5)
		_:
			Art.part(_body, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.5), Vector3.ZERO, Vector3(0.14, 0.12, 0.22))
			Art.part(_body, Art.sphere(), Art.glow(color, 2.0, true, 0.5), Vector3(0.0, 0.05, 0.0), Vector3(0.3, 0.04, 0.12))
