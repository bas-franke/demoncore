class_name PyreBurst
extends Node3D
## "Sanctified Pyre" / "Censer Sweep" (Grand Inquisitor): a disc or sector of holy fire. The sigil
## charges for `tell` seconds, then the area erupts in white-gold flame and damages the demon once
## if it stands inside. Use PyreBurst.cast(center, radius, tell, damage, dir, half_angle)
## (half_angle >= PI = full disc). In group "boss_hazards".

const BURN_LIFE := 0.6
const PLAYER_RADIUS := 0.35

var radius := 6.0
var tell := 1.4
var damage := 24.0
var dir := Vector3.FORWARD
var half_angle := PI + 0.1

var _t := 0.0
var _burst := false
var _sigil: BossTelegraph


## characters-new: hazard tint. Read from HolyFX.hazard_tint when created (ProcBoss sets it around
## its casts); Art.HOLY = the original look.
var tint: Color = HolyFX.hazard_tint


static func cast(center: Vector3, r: float, tell_s: float, dmg: float, direction := Vector3.FORWARD,
		half: float = PI + 0.1) -> PyreBurst:
	if Game.world == null:
		return null
	var p := PyreBurst.new()
	p.radius = r
	p.tell = tell_s
	p.damage = dmg
	var d := Vector3(direction.x, 0.0, direction.z)
	p.dir = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	p.half_angle = half
	Game.spawn(p, Vector3(center.x, 0.0, center.z))
	return p


func _ready() -> void:
	add_to_group(&"boss_hazards")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sigil = BossTelegraph.new()
	add_child(_sigil)


func _physics_process(delta: float) -> void:
	_t += delta
	if not _burst:
		var k := clampf(_t / maxf(tell, 0.01), 0.0, 1.0)
		var pulse := 0.85 + 0.15 * sin(_t * 20.0)
		_sigil.show_sector(global_position, dir, radius, half_angle, tint, k, minf(_t * 5.0, 1.0) * pulse, 1.3 + k)
		if _t >= tell:
			_erupt()
		return
	var fk := clampf((_t - tell) / BURN_LIFE, 0.0, 1.0)
	_sigil.show_sector(global_position, dir, radius, half_angle, HolyFX.white_of(tint), 1.0, (1.0 - fk) * 0.9, 2.4)
	if fk >= 1.0:
		queue_free()


func _erupt() -> void:
	_burst = true
	Sfx.play(&"brimstone", 0.1, -2.0)
	Sfx.play(&"smite", 0.1, -4.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.22)
	# Flame tongues scattered over the area.
	var n := clampi(int(radius * radius * (half_angle / PI) * 0.35), 4, 18)
	for i in n:
		var a := randf_range(-half_angle, half_angle) if half_angle < PI else randf() * TAU
		var at := global_position + dir.rotated(Vector3.UP, a) * sqrt(randf()) * radius
		HolyFX.column(at, 0.35, randf_range(2.0, 4.0), randf_range(0.4, 0.7), tint, 2.0)
	HolyFX.motes(global_position + Vector3(0.0, 0.3, 0.0), 14, tint, radius * 0.6, 2.4, 0.9)
	var p := Game.player
	if p and is_instance_valid(p) and not p.is_dead and hits(p.global_position):
		p.take_damage(damage)
		Sfx.play(&"holy_hit", 0.08)


func hits(point: Vector3) -> bool:
	var d := point - global_position
	d.y = 0.0
	var dist := d.length()
	if dist > radius + PLAYER_RADIUS:
		return false
	if half_angle >= PI or dist < 0.01:
		return true
	return absf(dir.signed_angle_to(d / dist, Vector3.UP)) <= half_angle + PLAYER_RADIUS / maxf(dist, 0.5)


func dissipate() -> void:
	if _burst:
		return
	queue_free()
