class_name HolyPuddle
extends Node3D
## A pool of holy water (Holy-Water Friar): a shimmering pale-blue disc on the ground that scalds
## the demon every TICK seconds while it stands inside RADIUS, then dries away after LIFE seconds.
## The hit passes the puddle's centre as the source with a tiny amount, so knockback is minimal.
## HolyPuddle.create(at, damage_per_tick).

const RADIUS := 1.5
const LIFE := 4.5
const TICK := 0.6

var damage := 4.0

var _age := 0.0
var _tick := 0.2
var _disc: MeshInstance3D
var _sheen: MeshInstance3D


static func create(at: Vector3, dmg: float) -> HolyPuddle:
	if Game.world == null:
		return null
	var p := HolyPuddle.new()
	p.damage = dmg
	Game.spawn.call_deferred(p, Vector3(at.x, 0.0, at.z))
	return p


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_disc = Art.part(self, Art.cylinder(0.5, 0.5), Art.glow(Color(0.55, 0.8, 1.0), 0.6, true, 0.7), Vector3(0.0, 0.03, 0.0), Vector3(RADIUS * 2.0, 0.01, RADIUS * 2.0))
	_sheen = Art.part(self, Art.torus(0.9, 1.0), Art.glow(Color(0.85, 0.95, 1.0), 1.4), Vector3(0.0, 0.05, 0.0), Vector3.ONE * RADIUS)


func _physics_process(delta: float) -> void:
	_age += delta
	var fade := clampf((LIFE - _age) / 0.8, 0.0, 1.0)
	_disc.scale = Vector3(RADIUS * 2.0 * (0.4 + 0.6 * minf(_age / 0.25, 1.0)), 0.01, RADIUS * 2.0 * (0.4 + 0.6 * minf(_age / 0.25, 1.0))) * maxf(fade, 0.01)
	_sheen.scale = Vector3.ONE * RADIUS * (1.0 + 0.05 * sin(_age * 8.0)) * maxf(fade, 0.01)
	if _age >= LIFE:
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var p := Game.player
	if p == null or p.is_dead:
		return
	var d := p.global_position - global_position
	d.y = 0.0
	if d.length() <= RADIUS:
		p.take_damage(damage, p.global_position)
		EnemyModel.spawn_motes(p.global_position, 3, 0.5, Color(0.7, 0.9, 1.0))
