class_name BellRing
extends Node3D
## "Bell of Judgement" (the Grand Inquisitor's last phase): a ring of golden sound-light that
## expands from `center` at `speed` m/s up to `max_radius`. It damages the demon once when its
## front (`width` thick) passes over it, so the counter is to be outside the ring as it starts or
## to dash through it (dashing through the front shatters the ring and hurts the boss). A faint ground circle shows where it is heading.
## Use BellRing.cast(center, max_radius, speed, width, damage, delay). In group "boss_hazards".

const HEIGHT := 0.35
const PLAYER_RADIUS := 0.35
## Fraction of the ringing boss's max HP it loses when the demon dashes through a ring.
const SHATTER_RECOIL := 0.02

## One "The bell cracks" banner per run is plenty.
static var _toasted := false

var max_radius := 14.0
var speed := 6.5
var width := 0.8
var damage := 18.0
var delay := 0.0
## Dashing through it hurts the boss that rang it (false for rings not cast by a boss).
var recoil := true

var _r := 0.4
var _hit := false
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _torus: TorusMesh
var _edge: BossTelegraph
var _t := 0.0


## characters-new: hazard tint. Read from HolyFX.hazard_tint when created (ProcBoss sets it around
## its casts); Art.HOLY = the original look.
var tint: Color = HolyFX.hazard_tint


static func cast(center: Vector3, radius: float, spd: float, width_m: float, dmg: float,
		wait: float = 0.0, boss_recoil: bool = true) -> BellRing:
	if Game.world == null:
		return null
	var b := BellRing.new()
	b.max_radius = radius
	b.speed = spd
	b.width = width_m
	b.damage = dmg
	b.delay = wait
	b.recoil = boss_recoil
	Game.spawn(b, Vector3(center.x, 0.0, center.z))
	return b


func _ready() -> void:
	add_to_group(&"boss_hazards")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_torus = TorusMesh.new()
	var torus := _torus
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 64
	torus.ring_segments = 6
	_ring = HolyFX.glow_part(self, torus, tint, 2.4, Vector3(0.0, HEIGHT, 0.0), Vector3(1.0, 0.6, 1.0))
	_ring_mat = _ring.material_override as StandardMaterial3D
	_ring.visible = false
	_edge = BossTelegraph.new()
	add_child(_edge)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < delay:
		# Warning: the reach of the ring glows faintly on the ground.
		_edge.show_disc(global_position, max_radius, tint, 0.0, 0.35 * clampf(_t / maxf(delay, 0.01), 0.0, 1.0), 0.8)
		return
	if not _ring.visible:
		_ring.visible = true
		Sfx.play(&"toll", 0.05, 0.0)
	_r += speed * delta
	var k := clampf(_r / max_radius, 0.0, 1.0)
	# The mesh radii move with the ring so its thickness stays `width` in world units
	# (outer first, so inner never exceeds it).
	_torus.outer_radius = _r + width * 0.5
	_torus.inner_radius = maxf(_r - width * 0.5, 0.01)
	_ring_mat.albedo_color = HolyFX.scaled(tint.lerp(HolyFX.white_of(tint), 0.4), 2.4 * (1.0 - k * k))
	_edge.show_disc(global_position, max_radius, tint, k, 0.3 * (1.0 - k), 0.8)
	var p := Game.player
	if not _hit and p and is_instance_valid(p) and not p.is_dead:
		var d := p.global_position - global_position
		d.y = 0.0
		if absf(d.length() - _r) <= width * 0.5 + PLAYER_RADIUS:
			_hit = true
			if p.dash and p.dash.is_dashing():
				_shatter(p.global_position)
				return
			p.take_damage(damage)
			Sfx.play(&"holy_hit", 0.08)
	if _r >= max_radius:
		queue_free()


## Defiance: the demon dashed through the ring's front. The whole ring shatters harmlessly and the
## blow rebounds on the boss that rang it (SHATTER_RECOIL of its max HP).
func _shatter(at: Vector3) -> void:
	HolyFX.flash(at + Vector3(0.0, 0.6, 0.0), 2.2, 0.35, HolyFX.white_of(tint), 3.0)
	HolyFX.motes(global_position + Vector3(0.0, HEIGHT, 0.0), 24, tint, _r, 1.2, 0.8)
	EnemyModel.shockwave(global_position, _r, Art.HELLFIRE, 0.4)
	Sfx.play(&"smite", 0.0, 2.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.3)
	var boss := get_tree().get_first_node_in_group(&"boss") as Enemy if recoil else null
	if boss and not boss.is_dying:
		boss.take_damage(boss.max_hp * SHATTER_RECOIL)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if recoil and hud and hud.has_method(&"toast") and not _toasted:
		_toasted = true
		hud.call(&"toast", "The bell cracks", Art.HELLFIRE)
	queue_free()


func dissipate() -> void:
	queue_free()
