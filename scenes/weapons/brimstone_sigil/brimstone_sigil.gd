extends Weapon
## A burning infernal circle beneath the demon. Enemies inside are scorched every tick.
## Carved obsidian rune stones (Blender model, tools/blender/models/weapons/rune_stone.py) rise out
## of the ground around its edge and lurch upward each time the circle burns something.

@export var base_radius := 2.2
@export var knockback := 1.6

var radius_mult := 1.0
var damage_mult := 1.0

var _radius := -1.0
var _pulse := 0.0
var _embers: CPUParticles3D
var _flames: CPUParticles3D
var _light: OmniLight3D
var _stone_root: Node3D
var _stones: Array[Node3D] = []
var _stone_life := 0.0

@onready var zone: Area3D = $Zone
@onready var shape: CylinderShape3D = $Zone/CollisionShape3D.shape
@onready var visual: MeshInstance3D = $Visual


func _ready() -> void:
	_embers = _make_embers()
	_flames = _make_flames()
	_light = Art.light(self, Art.HELLFIRE, 0.9, base_radius * 1.6, Vector3(0.0, 0.6, 0.0))
	_stone_root = Node3D.new()
	add_child(_stone_root)
	super()


func _on_level_changed() -> void:
	radius_mult = 1.0 + 0.2 * int(level >= 2) + 0.2 * int(level >= 4) + 0.25 * int(level >= 7)
	damage_mult = 1.0 + 0.3 * int(level >= 3) + 0.4 * int(level >= 6)
	cooldown_mult = 0.75 if level >= 5 else 1.0  # faster ticks


func _physics_process(delta: float) -> void:
	super(delta)
	if player == null:
		return
	var r := base_radius * radius_mult * get_area()
	if not is_equal_approx(_radius, r):
		_radius = r
		shape.radius = r
		visual.set_instance_shader_parameter(&"radius", r)
		_embers.emission_ring_radius = r * 0.95
		_embers.emission_ring_inner_radius = r * 0.2
		_embers.amount = clampi(int(r * r * 5.0), 16, 80)
		_flames.emission_ring_radius = r * 0.98
		_flames.emission_ring_inner_radius = r * 0.9
		_flames.amount = clampi(int(r * 9.0), 16, 60)
		_light.omni_range = r * 1.6
		_layout_stones(r)
	_pulse = move_toward(_pulse, 0.0, delta * 4.0)
	var t := Time.get_ticks_msec() * 0.001
	var breathe := 1.0 + sin(t * 3.1) * 0.012 + _pulse * 0.05
	visual.scale = Vector3(r * breathe, 1.0, r * breathe)
	visual.set_instance_shader_parameter(&"pulse", _pulse)
	_light.light_energy = 0.9 + sin(t * 13.0) * 0.12 + sin(t * 7.3) * 0.1 + _pulse * 1.2
	_update_stones(delta, t)


func attack() -> bool:
	var dmg := get_damage() * damage_mult
	var hit := false
	for body in zone.get_overlapping_bodies():
		var e := body as Enemy
		if e and not e.is_dying:
			Enemy.hit(e, dmg, Targeting.flat_dir(global_position, e.global_position) * knockback, self)
			hit = true
	_pulse = 1.0 if hit else maxf(_pulse, 0.3)
	if hit:
		Sfx.play(&"brimstone", 0.06, -3.0)
	return true


## One stone per ~0.4 m of radius (6..12); rebuilt (and risen again) when the circle grows.
func _layout_stones(r: float) -> void:
	var n := clampi(int(round(r * 2.6)), 6, 12)
	if n == _stones.size():
		return
	for st in _stones:
		st.queue_free()
	_stones.clear()
	for i in n:
		var pivot := Node3D.new()
		_stone_root.add_child(pivot)
		var st := WeaponArt.build(WeaponArt.RUNE_STONES, pivot, WeaponArt.NO_TINT, "stone%d" % (i % 3), true)
		st.scale = Vector3.ONE * (0.85 + 0.3 * fposmod(float(i) * 0.618, 1.0))
		st.rotation.y = (fposmod(float(i) * 0.37, 1.0) - 0.5) * 0.5
		_stones.append(pivot)
	_stone_life = 0.0


## Stones rise in a staggered wave, breathe, slowly circle, and jolt up on every scorching tick.
func _update_stones(delta: float, t: float) -> void:
	var n := _stones.size()
	if n == 0:
		return
	_stone_life += delta
	var ring := _radius * 1.03
	for i in n:
		var a := TAU * float(i) / float(n) + t * 0.12
		var rise := clampf(_stone_life * 1.8 - float(i) * 0.09, 0.0, 1.0)
		rise = 1.0 - pow(1.0 - rise, 3.0)
		var y := -0.95 * (1.0 - rise) + sin(t * 1.7 + float(i) * 1.3) * 0.03 + _pulse * 0.09 * rise
		var p := Vector3(cos(a) * ring, y, sin(a) * ring)
		var st := _stones[i]
		st.position = p
		# Rune face toward the centre, top leaning out.
		st.basis = Basis.looking_at(Vector3(-p.x, 0.0, -p.z), Vector3.UP) * Basis(Vector3.RIGHT, 0.14 + _pulse * 0.06)


## Embers drifting up out of the whole circle.
func _make_embers() -> CPUParticles3D:
	var p := InfernalFx.make_particles(Art.EMBER, 24, 1.6, 3.0)
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.05
	p.emission_ring_radius = base_radius * 0.95
	p.emission_ring_inner_radius = base_radius * 0.2
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0.0, 0.6, 0.0)
	p.position = Vector3(0.0, 0.1, 0.0)
	add_child(p)
	return p


## Short flame tongues licking up along the rim.
func _make_flames() -> CPUParticles3D:
	var tongue := CylinderMesh.new()
	tongue.top_radius = 0.0
	tongue.bottom_radius = 0.07
	tongue.height = 0.36
	tongue.radial_segments = 6
	tongue.rings = 1
	var p := InfernalFx.make_particles(Art.HELLFIRE, 24, 0.55, 2.4)
	p.mesh = tongue
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_height = 0.02
	p.emission_ring_radius = base_radius * 0.98
	p.emission_ring_inner_radius = base_radius * 0.9
	p.direction = Vector3.UP
	p.spread = 8.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0.0, 0.8, 0.0)
	p.scale_amount_curve = InfernalFx.swell_curve()
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	p.position = Vector3(0.0, 0.12, 0.0)
	add_child(p)
	return p
