class_name AbilityConstruct
extends Node3D
## A stationary thing an ability leaves on the ground: a turret, a mine or a mirror decoy.
## Group "ability_constructs"; meta &"ability" = the ability id (for limits).
##
##   turret  fires at the nearest enemy within `reach` every `rate` s (bolts, or a flame cone
##           when `flamer`), for `lifetime` s.
##   mine    arms after ARM_TIME, then bursts (radius `reach`) when an enemy comes within 0.9 m.
##   decoy   a glassy double of the demon that taunts angels within TAUNT_RADIUS (they chase it
##           instead of the demon), flings mirror shards every `rate` s and shatters (radius
##           `reach`) when its time is up or 4+ angels crowd it.
## Damage goes through AbilityCombat with `src`.

const GROUP := &"ability_constructs"
const ARM_TIME := 0.6
const MINE_TRIGGER := 0.9
## Decoys taunt angels within this radius (Enemy.set_taunt_target), refreshed every TAUNT_EVERY s.
const TAUNT_RADIUS := 6.0
const TAUNT_EVERY := 0.4

var type: StringName = &"turret"
var damage := 8.0
var rate := 0.8
var reach := 8.0
var lifetime := 10.0
var flamer := false
var src := {}
var color := Color.WHITE

var _age := 0.0
var _t := 0.0
var _head: Node3D
var _done := false
var _taunt_t := 0.0


static func spawn(at: Vector3, ability_id: StringName, p_type: StringName, p_damage: float, p_rate: float,
		p_reach: float, p_lifetime: float, p_src: Dictionary, p_color: Color) -> AbilityConstruct:
	if Game.world == null:
		return null
	var c := AbilityConstruct.new()
	c.type = p_type
	c.damage = p_damage
	c.rate = p_rate
	c.reach = p_reach
	c.lifetime = p_lifetime
	c.src = p_src.duplicate()
	c.color = p_color
	c.set_meta(&"ability", ability_id)
	c.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(c, Vector3(at.x, 0.0, at.z))
	return c


func _ready() -> void:
	add_to_group(GROUP)
	match type:
		&"mine":
			_build_mine()
		&"decoy":
			_build_decoy()
		_:
			_build_turret()
	scale = Vector3.ONE * 0.1
	create_tween().tween_property(self, ^"scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_t = rate * 0.5


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta
	if _age >= lifetime:
		finish()
		return
	match type:
		&"mine":
			if _age >= ARM_TIME and not AbilityCombat.enemies_in_radius(global_position, MINE_TRIGGER).is_empty():
				finish()
		&"decoy":
			_head.rotation.y += delta * 1.5
			_taunt_t -= delta
			if _taunt_t <= 0.0:
				_taunt_t = TAUNT_EVERY
				_taunt()
			_t -= delta
			if _t <= 0.0:
				_t = rate
				_shoot(&"shard")
			if AbilityCombat.enemies_in_radius(global_position, 1.2).size() >= 4:
				finish()
		_:
			_t -= delta
			if _t <= 0.0:
				_t = rate
				_shoot(&"flame" if flamer else &"orb")


## Draws nearby angels to the decoy (the gameplay role's taunt hook; skipped without it).
func _taunt() -> void:
	for e in AbilityCombat.enemies_in_radius(global_position, TAUNT_RADIUS):
		if e.has_method(&"set_taunt_target") and not e.is_in_group(&"boss"):
			e.call(&"set_taunt_target", self, TAUNT_EVERY + 0.3)


## Ends the construct: mines and decoys burst, turrets just sink.
func finish() -> void:
	if _done:
		return
	_done = true
	remove_from_group(GROUP)
	if type == &"mine" or type == &"decoy":
		var s := src.duplicate()
		s["origin"] = global_position
		s["knockback"] = 4.0
		AbilityCombat.explode(global_position, reach, damage * (1.5 if type == &"decoy" else 1.0), s, color)
		Sfx.play_at(&"decoy_hit" if type == &"decoy" else &"mine_hit", global_position, 0.1, -3.0)
	var tw := create_tween()
	tw.tween_property(self, ^"scale", Vector3(0.05, 0.05, 0.05), 0.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _shoot(kind: StringName) -> void:
	var muzzle := global_position + Vector3(0.0, 0.9, 0.0)
	var target := Targeting.nearest_enemy(get_tree(), global_position, reach)
	if target == null:
		return
	var dir := Targeting.flat_dir(global_position, target.global_position)
	if _head and type != &"decoy":
		_head.rotation.y = atan2(-dir.x, -dir.z)
	Sfx.play_at(&"fire_cast" if kind == &"flame" else &"turret_hit", muzzle, 0.1, -9.0)
	var s := src.duplicate()
	s["origin"] = global_position
	if kind == &"flame":
		AbilityFx.fan(global_position, dir, reach * 0.5, 60.0, color, 0.25)
		for e in AbilityCombat.enemies_in_radius(global_position, reach * 0.5):
			if Targeting.flat_dir(global_position, e.global_position).angle_to(dir) < 0.55:
				AbilityCombat.hit(e, damage, s)
		return
	var b := AbilityBolt.create(s, damage, dir * 16.0, color, kind, 0.16)
	b.lifetime = reach / 16.0 + 0.2
	Game.spawn.call_deferred(b, muzzle)


func _build_turret() -> void:
	var iron := Art.mat(Art.OBSIDIAN, 0.4, 0.7)
	for k in 3:
		var a := TAU * k / 3.0
		Art.part(self, Art.cylinder(0.3, 0.5), iron, Vector3(cos(a) * 0.3, 0.25, sin(a) * 0.3), Vector3(0.1, 0.6, 0.1),
			Vector3(sin(a) * 0.4, 0.0, -cos(a) * 0.4))
	_head = Art.pivot(self, Vector3(0.0, 0.7, 0.0))
	Art.part(_head, Art.sphere(), iron, Vector3.ZERO, Vector3.ONE * 0.45)
	Art.part(_head, Art.cylinder(0.4, 0.5), iron, Vector3(0.0, 0.05, -0.35), Vector3(0.14, 0.5, 0.14), Vector3(-PI * 0.5, 0.0, 0.0))
	Art.part(_head, Art.sphere(), Art.glow(color, 3.0, true, 0.9), Vector3(0.0, 0.05, -0.62), Vector3.ONE * 0.12)
	Art.part(_head, Art.torus(0.8, 1.0), Art.glow(color, 2.0, true, 0.7), Vector3.ZERO, Vector3(0.3, 0.1, 0.3))
	InfernalFx.embers(_head, color, 6, 0.5, 0.15)


func _build_mine() -> void:
	Art.part(self, Art.cylinder(0.4, 0.5), Art.mat(Art.OBSIDIAN, 0.4, 0.6), Vector3(0.0, 0.06, 0.0), Vector3(0.5, 0.12, 0.5))
	for k in 6:
		var a := TAU * k / 6.0
		Art.part(self, Art.cone(0.5), Art.mat(Art.STEEL, 0.4, 0.8), Vector3(cos(a) * 0.22, 0.1, sin(a) * 0.22),
			Vector3(0.06, 0.18, 0.06), Vector3(sin(a) * 1.2, 0.0, -cos(a) * 1.2))
	_head = Art.part(self, Art.sphere(), Art.glow(color, 3.0, true, 1.0), Vector3(0.0, 0.16, 0.0), Vector3.ONE * 0.12)


func _build_decoy() -> void:
	var glass := Art.glow(color.lerp(Color.WHITE, 0.4), 1.2, true, 0.35)
	_head = Art.pivot(self)
	Art.part(_head, Art.capsule(0.3, 1.5), glass, Vector3(0.0, 0.85, 0.0))
	Art.part(_head, Art.sphere(), glass, Vector3(0.0, 1.75, 0.0), Vector3.ONE * 0.38)
	for side: float in [-1.0, 1.0]:
		Art.part(_head, Art.cone(0.5), glass, Vector3(0.12 * side, 2.0, 0.0), Vector3(0.08, 0.3, 0.08), Vector3(0.0, 0.0, -0.4 * side))
	for k in 4:
		var a := TAU * k / 4.0
		Art.part(_head, Art.box(), Art.glow(color, 2.0, true, 0.6), Vector3(cos(a) * 0.7, 1.0 + k * 0.15, sin(a) * 0.7),
			Vector3(0.18, 0.3, 0.02), Vector3(0.0, a, 0.3))
	InfernalFx.embers(self, color, 8, 0.8, 0.4, Vector3(0.0, 1.0, 0.0), 1.5)
