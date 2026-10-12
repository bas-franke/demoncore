class_name AbilityBolt
extends Area3D
## Projectile fired by "bolt" abilities. Built entirely in code (no scene): a collision sphere on
## the enemy layer plus a procedural look chosen by `style`. Damage goes through AbilityCombat.hit
## so statuses, crits and triggers apply. Optional homing and an explosion on every hit.
##
##   var b := AbilityBolt.create(src, damage, velocity, color, &"dagger", 0.15)
##   Game.spawn.call_deferred(b, origin)   # deferred: may be fired from a physics callback

const POP_TIME := 0.08

var src := {}
var damage := 10.0
var velocity := Vector3.ZERO
var pierce := 0
var lifetime := 1.2
## Turn rate toward the nearest enemy in radians per second (0 = straight).
var homing := 0.0
## Explosion radius on every hit (0 = none); deals 60% of the bolt damage.
var explode_radius := 0.0
var color := Color.WHITE
var style: StringName = &"orb"
var size := 0.2

var _hit := {}  # Enemy -> true
var _visual: Node3D
var _spent := false
var _retarget := 0.0
var _target: Enemy


static func create(p_src: Dictionary, p_damage: float, p_velocity: Vector3, p_color: Color,
		p_style: StringName, p_size: float) -> AbilityBolt:
	var b := AbilityBolt.new()
	b.src = p_src
	b.damage = p_damage
	b.velocity = p_velocity
	b.color = p_color
	b.style = p_style
	b.size = p_size
	return b


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # enemies
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(size * 1.4, 0.2)
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_build_visual()


func _physics_process(delta: float) -> void:
	if homing > 0.0 and not _spent:
		_retarget -= delta
		if _retarget <= 0.0:
			_retarget = 0.15
			_target = Targeting.nearest_enemy(get_tree(), global_position, 8.0)
		if is_instance_valid(_target) and not _target.is_dying and not _hit.has(_target):
			var want := Targeting.flat_dir(global_position, _target.global_position) * velocity.length()
			velocity = velocity.lerp(want, clampf(homing * delta * 0.5, 0.0, 1.0))
	global_position += velocity * delta
	lifetime -= delta
	if _visual and velocity.length_squared() > 0.001:
		var fwd := velocity.normalized()
		_visual.basis = Basis.looking_at(fwd, Vector3.UP) if absf(fwd.y) < 0.98 else Basis.IDENTITY
		if _spent:
			_visual.scale = Vector3.ONE * maxf(lifetime / POP_TIME, 0.05)
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	var e := body as Enemy
	if e == null or e.is_dying or _hit.has(e):
		return
	_hit[e] = true
	var s := src.duplicate()
	s["origin"] = global_position - velocity.normalized()
	AbilityCombat.hit(e, damage, s)
	InfernalFx.burst(global_position, color, 6, 2.4, 0.7)
	if explode_radius > 0.0:
		AbilityCombat.explode(global_position, explode_radius, damage * 0.6,
			AbilityCombat.child_source(src, src.get("status", [])), color)
	pierce -= 1
	if pierce < 0:
		_spent = true
		set_deferred(&"monitoring", false)
		velocity *= 0.1
		lifetime = minf(lifetime, POP_TIME)


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var glow := Art.glow(color, 2.6, true, 0.9)
	var core := Art.glow(color.lerp(Color.WHITE, 0.6), 2.2, true, 1.0)
	match style:
		&"dagger":
			# Thin black blade with a glowing edge, pointing along -Z (looking_at forward).
			Art.part(_visual, Art.prism(), Art.mat(Art.OBSIDIAN, 0.3, 0.6), Vector3.ZERO,
				Vector3(size * 0.8, size * 0.25, size * 4.0), Vector3(-PI * 0.5, 0.0, 0.0))
			Art.part(_visual, Art.box(), glow, Vector3(0.0, 0.0, size * 1.2), Vector3(size * 0.15, size * 0.15, size * 3.0))
		&"spear":
			Art.part(_visual, Art.cylinder(0.3, 0.5), Art.mat(Art.BONE, 0.7), Vector3.ZERO,
				Vector3(size * 0.6, size * 9.0, size * 0.6), Vector3(-PI * 0.5, 0.0, 0.0))
			Art.part(_visual, Art.cone(0.5), Art.mat(Art.IVORY, 0.5), Vector3(0.0, 0.0, -size * 5.0),
				Vector3(size * 1.2, size * 2.4, size * 1.2), Vector3(-PI * 0.5, 0.0, 0.0))
		&"coin":
			# A spinning burning coin, flat side to the camera.
			Art.part(_visual, Art.cylinder(), Art.mat(Art.GOLD, 0.25, 1.0), Vector3.ZERO,
				Vector3(size * 2.4, size * 0.3, size * 2.4), Vector3(PI * 0.5, 0.0, 0.0))
			Art.part(_visual, Art.sphere(), glow, Vector3.ZERO, Vector3.ONE * size * 2.0)
		&"holy", &"shard":
			# Stolen light / a sliver of mirror: a bright elongated diamond.
			Art.part(_visual, Art.prism(), core, Vector3.ZERO, Vector3(size * 1.2, size * 1.2, size * 4.0), Vector3(-PI * 0.5, 0.0, 0.0))
			Art.part(_visual, Art.sphere(), glow, Vector3.ZERO, Vector3.ONE * size * 2.6)
		&"soul":
			Art.part(_visual, Art.sphere(), glow, Vector3.ZERO, Vector3.ONE * size * 2.2)
			Art.part(_visual, Art.sphere(), core, Vector3.ZERO, Vector3.ONE * size * 1.1)
			Art.part(_visual, Art.cone(0.5), glow, Vector3(0.0, 0.0, size * 2.0),
				Vector3(size * 1.6, size * 4.0, size * 1.6), Vector3(PI * 0.5, 0.0, 0.0))
		_:
			Art.part(_visual, Art.sphere(), glow, Vector3.ZERO, Vector3.ONE * size * 2.4)
			Art.part(_visual, Art.sphere(), core, Vector3.ZERO, Vector3.ONE * size * 1.2)
	var trail := InfernalFx.embers(self, color, 8, 0.35, size * 0.5)
	trail.initial_velocity_max = 0.4
