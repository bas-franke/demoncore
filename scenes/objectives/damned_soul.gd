class_name DamnedSoul
extends Node3D
## A freed damned soul fighting for the demon: a crimson wisp that circles the demon for
## `duration` seconds and every `interval` seconds lashes the nearest angel within `reach`
## (damage scaled by the demon's Might). Purely distance-checked, no physics.
## Use DamnedSoul.summon(at, duration, damage, interval, reach).

const ORBIT_SPEED := 1.6
const HEIGHT := 1.3

var duration := 60.0
var damage := 9.0
var interval := 0.75
var reach := 6.0

var _t := 0.0
var _cd := 0.0
var _angle := 0.0
var _radius := 1.8
var _core: MeshInstance3D
var _aura_mat: StandardMaterial3D
var _trail_t := 0.0


## Spawns a soul at `at` that fights for `life` seconds, hitting for `dmg` every `every` seconds
## within `rng` metres. Returns null outside a run (no Game.world).
static func summon(at: Vector3, life: float, dmg: float, every: float, rng: float) -> DamnedSoul:
	if Game.world == null:
		return null
	var s := DamnedSoul.new()
	s.duration = life
	s.damage = dmg
	s.interval = every
	s.reach = rng
	Game.spawn(s, at + Vector3(0.0, HEIGHT, 0.0))
	return s


func _ready() -> void:
	add_to_group(&"allies")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_core = Art.part(self, Art.sphere(), Art.glow(Art.SOUL, 2.6), Vector3.ZERO, Vector3.ONE * 0.26)
	var aura := HolyFX.glow_part(self, Art.sphere(), Art.CRIMSON, 0.9, Vector3.ZERO, Vector3.ONE * 0.62)
	_aura_mat = aura.material_override as StandardMaterial3D
	Art.light(self, Art.SOUL, 0.8, 3.0)
	_angle = randf() * TAU
	_radius = randf_range(1.5, 2.3)
	_cd = randf() * interval


func _process(delta: float) -> void:
	_t += delta
	var p := Game.player
	if p == null or not is_instance_valid(p) or _t >= duration:
		_vanish()
		return
	_angle += delta * ORBIT_SPEED
	var target := p.global_position + Vector3(cos(_angle) * _radius, HEIGHT + sin(_t * 3.0) * 0.15, sin(_angle) * _radius)
	global_position = global_position.lerp(target, 1.0 - exp(-6.0 * delta))
	# Flickers out over the last seconds.
	var fade := clampf((duration - _t) / 3.0, 0.0, 1.0)
	var flick := 0.8 + 0.2 * sin(_t * 11.0)
	_aura_mat.albedo_color = HolyFX.scaled(Art.CRIMSON, 0.9 * flick * fade)
	_core.scale = Vector3.ONE * 0.26 * (0.4 + 0.6 * fade)
	_trail_t -= delta
	if _trail_t <= 0.0:
		_trail_t = 0.12
		HolyFX.motes(global_position, 1, Art.SOUL, 0.05, 0.3, 0.5, 0.05)
	_cd -= delta
	if _cd <= 0.0:
		var e := Targeting.nearest_enemy(get_tree(), global_position, reach)
		if e:
			_cd = interval
			_lash(e, p)
		else:
			_cd = 0.2


func _lash(e: Enemy, p: Player) -> void:
	var to := e.global_position + Vector3(0.0, 0.6 * e.data.size, 0.0)
	_bolt(global_position, to)
	var push := (e.global_position - p.global_position)
	push.y = 0.0
	e.take_damage(damage * p.might, push.normalized() * 2.0 if push.length_squared() > 0.01 else Vector3.ZERO)
	Sfx.play(&"chain", 0.15, -10.0)


## A short-lived crimson streak between two points.
func _bolt(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Game.spawn(root, mid)
	if not root.is_inside_tree():
		return
	var length := from.distance_to(to)
	var beam := HolyFX.glow_part(root, Art.box(), Art.SOUL, 2.4, Vector3.ZERO, Vector3(0.06, 0.06, length))
	if length > 0.01:
		root.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	var mat := beam.material_override as StandardMaterial3D
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color", Color(0.0, 0.0, 0.0, 1.0), 0.18)
	tw.tween_callback(root.queue_free)
	HolyFX.motes(to, 3, Art.SOUL, 0.2, 0.6, 0.4)


func _vanish() -> void:
	HolyFX.motes(global_position, 8, Art.SOUL, 0.4, 1.5, 0.9)
	queue_free()
