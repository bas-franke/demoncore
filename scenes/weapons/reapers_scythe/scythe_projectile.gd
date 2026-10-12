extends Area3D
## A reaper's scythe thrown like a boomerang (spawned by reapers_scythe.gd). The scythe is a
## Blender model (knuckled bone haft, black crescent blade with a burning crimson edge) spinning
## flat, with a faint smear of its arc. Flies out along `direction`, decelerates to a stop at `max_distance`, then accelerates
## back toward the player. Each enemy can be hit once per leg (out and back).

const HEIGHT := 0.8
## Safety net: free the scythe if it somehow never makes it home.
const MAX_LIFETIME := 6.0
## Blade arc radius; its centre is the spin centre, so the blade sweeps a clean circle.
const BLADE_R := 0.56

var player: Player
var direction := Vector3.FORWARD
var speed := 12.0
var max_distance := 6.0
var damage := 12.0
var knockback := 5.0
## The Weapon that threw it (Enemy.last_hit_source during the hit).
var source: Node
## Visual + hitbox scale.
var size := 1.0
## Radians per second the scythe spins (flat).
var spin_speed := 14.0

var _vel := Vector3.ZERO
var _decel := 1.0
var _returning := false
var _return_t := 0.0
var _life := 0.0
var _hit := {}  # enemy instance id -> true (cleared when turning around)
var _visual: Node3D
var _spinner: Node3D
var _smear: MeshInstance3D
var _bump := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4
	monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.6 * size
	cs.shape = sh
	add_child(cs)
	_visual = Art.pivot(self)
	_visual.scale = Vector3.ONE * size
	_spinner = Art.pivot(_visual)
	_spinner.rotation.y = randf() * TAU
	# Blender-made scythe (tools/blender/models/weapons/reaper_scythe.py), laid flat around the spin centre.
	WeaponArt.build(WeaponArt.SCYTHE, _spinner)
	# Faint smear of the spinning blade.
	_smear = Art.part(_visual, Art.torus(0.82, 1.0), Art.glow(Art.CRIMSON, 1.6, true, 0.22), Vector3.ZERO,
			Vector3(BLADE_R + 0.1, 0.25, BLADE_R + 0.1))
	var trail := InfernalFx.embers(self, Art.SOUL, 12, 0.45, 0.4 * size)
	trail.initial_velocity_max = 0.5
	trail.gravity = Vector3(0.0, 1.2, 0.0)
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	_decel = speed * speed / (2.0 * maxf(max_distance, 0.5))
	_vel = direction * speed


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFETIME:
		queue_free()
		return
	if not _returning:
		var s := maxf(_vel.length() - _decel * delta, 0.0)
		_vel = direction * s
		if s <= 0.05:
			_returning = true
			_hit.clear()
	else:
		_return_t += delta
		var ret_speed := minf(_decel * _return_t * 1.3, speed * 1.2)
		if is_instance_valid(player) and not player.is_dead:
			var to := player.global_position + Vector3(0.0, HEIGHT, 0.0) - global_position
			to.y = 0.0
			if to.length() < 0.6 + 0.2 * size and _return_t > 0.15:
				queue_free()
				return
			_vel = to.normalized() * ret_speed if to.length_squared() > 0.0001 else Vector3.ZERO
		else:
			_vel = -direction * ret_speed
	global_position += _vel * delta
	global_position.y = HEIGHT
	_check_hits()

	# Spin faster while flying fast, tilt a little like a thrown blade, jolt on hits.
	var fast := clampf(_vel.length() / maxf(speed, 0.1), 0.35, 1.0)
	_spinner.rotation.y = fmod(_spinner.rotation.y - spin_speed * fast * delta, TAU)
	_visual.rotation.z = sin(_life * 5.0) * 0.08
	_visual.rotation.x = 0.12
	_bump = move_toward(_bump, 0.0, delta * 6.0)
	_visual.scale = Vector3(1.0 + 0.2 * _bump, 1.0, 1.0 + 0.2 * _bump) * size
	_smear.transparency = 1.0 - fast * 0.9


func _check_hits() -> void:
	var push := _vel.normalized() if _vel.length_squared() > 0.01 else direction
	for body in get_overlapping_bodies():
		var e := body as Enemy
		if e == null or e.is_dying:
			continue
		var id := e.get_instance_id()
		if _hit.has(id):
			continue
		_hit[id] = true
		_bump = 1.0
		Enemy.hit(e, damage, push * knockback, source)
		InfernalFx.burst(e.global_position + Vector3(0.0, 0.7, 0.0), Art.CRIMSON, 7, 2.6, 0.8, 0.45)
