class_name AbilityZone
extends Node3D
## A lingering ground effect (fire pillar, plague cloud, magma pool) that hits every enemy inside
## `radius` once per `tick`. No physics: it polls AbilityCombat.enemies_in_radius each tick.
##
##   AbilityZone.spawn(pos, 2.0, 4.0, 0.5, dmg, src, color, &"cloud")

var radius := 2.0
var duration := 3.0
var tick := 0.5
var damage := 2.0
var src := {}
var color := Color.WHITE
var style: StringName = &"pool"

var _t := 0.0
var _tick_t := 0.0
var _disc: MeshInstance3D
var _fx: CPUParticles3D
var _column: MeshInstance3D


static func spawn(at: Vector3, p_radius: float, p_duration: float, p_tick: float, p_damage: float,
		p_src: Dictionary, p_color: Color, p_style: StringName) -> AbilityZone:
	if Game.world == null:
		return null
	var z := AbilityZone.new()
	z.radius = p_radius
	z.duration = p_duration
	z.tick = maxf(p_tick, 0.1)
	z.damage = p_damage
	z.src = p_src.duplicate()
	z.src["origin"] = at
	z.color = p_color
	z.style = p_style
	z.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(z, Vector3(at.x, 0.0, at.z))
	return z


func _ready() -> void:
	# Kept faint: additive discs bloom hard, and several zones often overlap.
	var alpha := 0.14 if style == &"cloud" else 0.18
	_disc = Art.part(self, Art.cylinder(), Art.glow(color, 0.8, true, alpha), Vector3(0.0, 0.05, 0.0),
		Vector3(radius * 2.0, 0.02, radius * 2.0))
	Art.part(self, Art.torus(0.94, 1.0), Art.glow(color, 1.4, true, 0.55), Vector3(0.0, 0.07, 0.0),
		Vector3(radius, 0.05, radius))
	match style:
		&"pillar":
			_column = Art.part(self, Art.cylinder(0.35, 0.5), Art.glow(color, 0.9, true, 0.16),
				Vector3(0.0, 1.5, 0.0), Vector3(radius * 1.1, 3.0, radius * 1.1))
			_fx = InfernalFx.embers(self, color, 18, 0.9, radius * 0.6)
			_fx.initial_velocity_min = 2.0
			_fx.initial_velocity_max = 4.5
		&"cloud":
			_fx = InfernalFx.embers(self, color, 20, 1.6, radius * 0.85, Vector3(0.0, 0.4, 0.0), 1.6)
			_fx.scale_amount_min = 2.0
			_fx.scale_amount_max = 4.0
			_fx.initial_velocity_max = 0.5
		_:
			_fx = InfernalFx.embers(self, color, 10, 0.8, radius * 0.7)
	scale = Vector3(0.2, 1.0, 0.2)
	create_tween().tween_property(self, ^"scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	if _column:
		_column.rotation.y += delta * 3.0
		_column.scale.x = radius * (1.1 + sin(_t * 17.0) * 0.08)
		_column.scale.z = _column.scale.x
	if _t >= duration:
		set_process(false)
		set_physics_process(false)
		_fx.emitting = false
		var tw := create_tween()
		tw.tween_property(self, ^"scale", Vector3(0.05, 1.0, 0.05), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(queue_free)


func _physics_process(delta: float) -> void:
	_tick_t -= delta
	if _tick_t > 0.0:
		return
	_tick_t = tick
	for e in AbilityCombat.enemies_in_radius(global_position, radius):
		AbilityCombat.hit(e, damage, src)
