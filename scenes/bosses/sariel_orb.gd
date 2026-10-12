class_name SarielOrb
extends Node3D
## A slow orb of holy light drifting outward in a straight line (the Herald's enraged "Dawn Ring").
## Hits the player once on contact, then bursts. Distance-checked (no physics body), so hundreds
## are cheap. In group "boss_hazards".

const HEIGHT := 0.75
const RADIUS := 0.38
const PLAYER_RADIUS := 0.4
const FADE_IN := 0.35

var velocity := Vector3.ZERO
var damage := 14.0
var life := 6.0

var _t := 0.0
var _core: MeshInstance3D
var _aura: MeshInstance3D
var _aura_mat: StandardMaterial3D
var _gone := false


## characters-new: hazard tint. Read from HolyFX.hazard_tint when created (ProcBoss sets it around
## its casts); Art.HOLY = the original look.
var tint: Color = HolyFX.hazard_tint


static func fire(at: Vector3, vel: Vector3, dmg: float, lifetime: float) -> SarielOrb:
	if Game.world == null:
		return null
	var o := SarielOrb.new()
	o.velocity = vel
	o.damage = dmg
	o.life = lifetime
	Game.spawn(o, Vector3(at.x, HEIGHT, at.z))
	return o


func _ready() -> void:
	add_to_group(&"boss_hazards")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_core = Art.part(self, Art.sphere(), Art.glow(HolyFX.white_of(tint), 2.4), Vector3.ZERO, Vector3.ONE * RADIUS * 1.5)
	_aura = HolyFX.glow_part(self, Art.sphere(), tint, 0.7, Vector3.ZERO, Vector3.ONE * RADIUS * 3.2)
	_aura_mat = _aura.material_override as StandardMaterial3D
	scale = Vector3.ONE * 0.01


func _physics_process(delta: float) -> void:
	if _gone:
		return
	_t += delta
	global_position += velocity * delta
	var grow := clampf(_t / FADE_IN, 0.0, 1.0)
	var fade := clampf((life - _t) / 0.5, 0.0, 1.0)
	var pulse := 1.0 + 0.08 * sin(_t * 9.0)
	scale = Vector3.ONE * maxf(grow * fade * pulse, 0.01)
	_aura_mat.albedo_color = HolyFX.scaled(tint, 0.7 * (0.8 + 0.2 * sin(_t * 5.0)))
	if _t >= life:
		queue_free()
		return
	if grow < 0.6:
		return
	var p := Game.player
	if p == null or not is_instance_valid(p) or p.is_dead:
		return
	var d := p.global_position - global_position
	d.y = 0.0
	if d.length() <= RADIUS + PLAYER_RADIUS:
		p.take_damage(damage)
		Sfx.play(&"holy_hit", 0.1)
		_burst()


func _burst() -> void:
	_gone = true
	HolyFX.flash(global_position, 1.2, 0.3, HolyFX.white_of(tint), 2.0)
	queue_free()


func dissipate() -> void:
	if _gone:
		return
	_gone = true
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
