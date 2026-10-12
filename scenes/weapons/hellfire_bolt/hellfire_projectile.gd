extends Projectile
## A bolt of hellfire: a screaming, cracked skull of charred bone with fire welling through it
## (Blender model, tools/blender/models/weapons/hellfire_core.py) facing its flight, wrapped in
## rolling flame (the "Visual"), a flame tail stretched back along the flight path, and a trail
## of embers. Flight and damage live in Projectile.

const CORE := Color(1.0, 0.78, 0.45)

const SKULL_SCALE := 1.15

var _tail: Node3D
var _skull: Node3D
var _tail_len := 1.0
var _age := 0.0


func _ready() -> void:
	var vis := Node3D.new()
	vis.name = &"Visual"
	add_child(vis)
	Art.part(vis, Art.sphere(), Art.glow(Art.HELLFIRE, 1.0, true, 0.3), Vector3.ZERO, Vector3.ONE * 0.56)
	# Flame tongues licking off the core; they roll with the Visual so the fire seems to churn.
	var tongue := Art.glow(Art.EMBER, 1.8, true, 0.7)
	for k in 6:
		var dir := Vector3(cos(k * 2.4), sin(k * 1.7) * 0.8, sin(k * 2.4)).normalized()
		var q := Quaternion(Vector3.UP, dir) if dir.dot(Vector3.UP) > -0.999 else Quaternion(Vector3.RIGHT, PI)
		var mi := Art.part(vis, Art.cone(0.5), tongue, dir * 0.22)
		mi.basis = Basis(q) * Basis.from_scale(Vector3(0.1, 0.24, 0.1))
	# The skull itself does not roll with the fire: it glares along its flight.
	_skull = Node3D.new()
	add_child(_skull)
	WeaponArt.build(WeaponArt.HELLFIRE_CORE, _skull)
	_skull.scale = Vector3.ONE * SKULL_SCALE

	_tail = Node3D.new()
	add_child(_tail)
	Art.part(_tail, Art.cone(0.5), Art.glow(Art.HELLFIRE, 1.6, true, 0.6), Vector3(0.0, 0.42, 0.0), Vector3(0.36, 0.86, 0.36))
	Art.part(_tail, Art.cone(0.5), Art.glow(CORE, 2.4, true, 0.8), Vector3(0.0, 0.24, 0.0), Vector3(0.15, 0.5, 0.15))
	_tail_len = randf_range(0.9, 1.15)

	var trail := InfernalFx.embers(self, Art.EMBER, 16, 0.4, 0.12)
	trail.initial_velocity_min = 0.1
	trail.initial_velocity_max = 0.6
	trail.gravity = Vector3(0.0, 1.8, 0.0)
	super()


func _physics_process(delta: float) -> void:
	super(delta)
	_age += delta
	if _tail == null:
		return
	if velocity.length_squared() > 0.0001:
		var back := -velocity.normalized()
		var q := Quaternion(Vector3.UP, back) if back.dot(Vector3.UP) > -0.999 else Quaternion(Vector3.RIGHT, PI)
		var flicker := 1.0 + sin(_age * 37.0) * 0.12 + sin(_age * 23.0) * 0.08
		var k := 1.0
		if _spent:
			k = maxf(lifetime / _POP_TIME, 0.05)
		_tail.basis = Basis(q) * Basis.from_scale(Vector3(k, _tail_len * flicker * k, k))
		var fwd := velocity.normalized()
		var up := Vector3.UP if absf(fwd.y) < 0.98 else Vector3.BACK
		# Slight shudder, like a thing that is screaming.
		var shake := Basis(fwd, sin(_age * 31.0) * 0.12) * Basis.looking_at(fwd, up)
		_skull.basis = shake.scaled(Vector3.ONE * SKULL_SCALE * k * (1.0 + _squash * 0.25))


func _on_body_entered(body: Node3D) -> void:
	var before := _hit.size()
	super(body)
	if _hit.size() > before:
		InfernalFx.burst(global_position, Art.HELLFIRE, 10, 3.2, 0.9)
		Sfx.play(&"impact", 0.15, -9.0)
		Sfx.play_element(&"fire", &"hit", global_position, -4.0, 0.12)
