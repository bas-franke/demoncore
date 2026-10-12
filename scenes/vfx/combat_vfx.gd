class_name CombatVFX
extends Node3D
## Combat VFX driven by Game's global events. Add one under the run root (main.tscn); it builds
## fixed pools in _ready and never spawns nodes afterwards.
##
##   enemy_hit    -> holy-gold spark spray thrown away from the player + impact flare + small light
##                   (scaled by damage); big hits add a heat-haze shimmer.
##   enemy_died   -> light branded into the ground under the fallen angel (complements EnemyModel's
##                   flash / motes / feathers / dissolving corpse).
##   player_hit   -> crimson blood mist + glowing hellblood droplets + red light at the demon.
##                   Contact damage arrives every frame, so damage is accumulated and burst out at
##                   most every BLOOD_GAP seconds.
##   boss_spawned -> brand of light + heat-haze ring where the Herald arrives.
##   boss_died    -> heat-haze shockwave, 160 rising light shards and a lingering brand (complements
##                   the Boss's own flash / light column / feathers / ash).
##
## Caps: every effect comes from a fixed pool (oldest instance is recycled), plus per-frame budgets
## for mass hits / kills, so a screen full of enemies can never spawn unbounded work.

const SPARK_SHADER := preload("res://shaders/vfx_spark.gdshader")
const MIST_SHADER := preload("res://shaders/vfx_mist.gdshader")
const FLARE_SHADER := preload("res://shaders/vfx_flare.gdshader")
const GROUND_SHADER := preload("res://shaders/vfx_ground_flash.gdshader")
const HAZE_SHADER := preload("res://shaders/vfx_haze.gdshader")

## Pool sizes = hard caps on concurrent effects of each kind.
const SPARK_POOL := 12
const FLARE_POOL := 10
const HIT_LIGHT_POOL := 3
const GROUND_POOL := 12
const HAZE_POOL := 4
const BLOOD_POOL := 3
## Per-frame spawn budgets (excess events that frame are simply skipped).
const HITS_PER_FRAME := 3
const DEATHS_PER_FRAME := 2
## Minimum seconds between hit lights / haze puffs / blood bursts.
const HIT_LIGHT_GAP := 0.06
const HAZE_GAP := 0.15
const BLOOD_GAP := 0.16
## Hits at or above this damage add a heat-haze shimmer.
const BIG_HIT := 18.0
## Enemy positions are at their feet; impacts happen around the chest.
const HIT_HEIGHT := 0.8

const GOLD_SPARK := Color(1.0, 0.72, 0.3)
const BLOOD_MIST := Color(0.22, 0.012, 0.018)
const HELLBLOOD := Color(1.0, 0.16, 0.06)


## A pooled, progress-driven effect (quad, plane or light).
class Fx:
	var node: Node3D
	var t := 1.0
	var life := 1.0
	var energy := 0.0
	var active := false


var _sparks: Array[GPUParticles3D] = []
var _spark_i := 0
var _mists: Array[GPUParticles3D] = []
var _drops: Array[GPUParticles3D] = []
var _blood_i := 0
var _boss_shards: GPUParticles3D
var _flares: Array[Fx] = []
var _grounds: Array[Fx] = []
var _hazes: Array[Fx] = []
var _lights: Array[Fx] = []
var _blood_light: Fx
var _haze_ring_mat: ShaderMaterial
var _haze_puff_mat: ShaderMaterial
var _quad_mesh: QuadMesh
var _plane_mesh: PlaneMesh

var _frame := -1
var _hits_frame := 0
var _deaths_frame := 0
var _light_cd := 0.0
var _haze_cd := 0.0
var _blood_cd := 0.0
var _blood_acc := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build_pools()
	Game.enemy_hit.connect(_on_enemy_hit)
	Game.enemy_died.connect(_on_enemy_died)
	Game.player_hit.connect(_on_player_hit)
	Game.boss_spawned.connect(_on_boss_spawned)
	Game.boss_died.connect(_on_boss_died)


# ---------------------------------------------------------------- events

func _on_enemy_hit(pos: Vector3, amount: float) -> void:
	if not _budget(true):
		return
	var at := pos + Vector3(0.0, HIT_HEIGHT, 0.0)
	var away := _away_from_player(pos)
	var k := clampf(amount / 20.0, 0.25, 1.6)
	var p := _sparks[_spark_i]
	_spark_i = (_spark_i + 1) % _sparks.size()
	p.global_transform = Transform3D(Basis.looking_at(away, Vector3.UP), at)
	p.amount_ratio = clampf(0.25 + amount / 28.0, 0.25, 1.0)
	p.restart()
	_flare(at + away * 0.2, 0.45 + 0.4 * k, 0.14 + 0.04 * k, Art.HOLY, 3.0 + k)
	if _light_cd <= 0.0:
		_light_cd = HIT_LIGHT_GAP
		_light(_lights, at, Art.HOLY, 1.6 + 2.2 * k, 2.5 + 1.5 * k, 0.16)
	if amount >= BIG_HIT and _haze_cd <= 0.0:
		_haze_cd = HAZE_GAP
		_haze(at, 0.8 + 0.4 * k, 0.45, true, 1.0)


func _on_enemy_died(pos: Vector3, data: Resource) -> void:
	if not _budget(false):
		return
	var s := 1.0
	if data:
		var v: Variant = data.get(&"size")
		if v is float:
			s = v
	_ground(Vector3(pos.x, 0.04, pos.z), 1.25 * s, 0.6, Art.HOLY, 1.8)


func _on_player_hit(amount: float) -> void:
	_blood_acc += amount


func _on_boss_spawned(boss: Node3D) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var at := boss.global_position
	at.y = 0.04
	_ground(at, 5.0, 1.6, Art.HOLY, 2.2)
	_haze(at + Vector3(0.0, 0.05, 0.0), 8.0, 0.9, false, 1.4)


func _on_boss_died(pos: Vector3) -> void:
	var ground := Vector3(pos.x, 0.04, pos.z)
	_haze(ground + Vector3(0.0, 0.06, 0.0), 14.0, 1.3, false, 2.2)
	_ground(ground, 10.0, 3.2, Art.HOLY, 0.8)
	_boss_shards.global_transform = Transform3D(Basis.IDENTITY, Vector3(pos.x, 1.4, pos.z))
	_boss_shards.restart()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_light_cd -= delta
	_haze_cd -= delta
	_blood_cd -= delta
	if _blood_acc > 0.0 and _blood_cd <= 0.0:
		if _blood_acc >= 1.0:
			_blood_burst(_blood_acc)
			_blood_cd = BLOOD_GAP
		_blood_acc = maxf(_blood_acc - delta * 2.0, 0.0) if _blood_acc < 1.0 else 0.0
	for list: Array[Fx] in [_flares, _grounds, _hazes]:
		for fx in list:
			if fx.active:
				_advance_quad(fx, delta)
	for fx in _lights:
		if fx.active:
			_advance_light(fx, delta)
	if _blood_light.active:
		_advance_light(_blood_light, delta)


func _advance_quad(fx: Fx, delta: float) -> void:
	fx.t += delta / fx.life
	if fx.t >= 1.0:
		fx.active = false
		fx.node.visible = false
		return
	(fx.node as GeometryInstance3D).set_instance_shader_parameter(&"progress", fx.t)


func _advance_light(fx: Fx, delta: float) -> void:
	fx.t += delta / fx.life
	var l := fx.node as OmniLight3D
	if fx.t >= 1.0:
		fx.active = false
		l.visible = false
		return
	var f := 1.0 - fx.t
	l.light_energy = fx.energy * f * f


## Per-frame budget for mass events (counts reset on a new process frame).
func _budget(hit: bool) -> bool:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_hits_frame = 0
		_deaths_frame = 0
	if hit:
		_hits_frame += 1
		return _hits_frame <= HITS_PER_FRAME
	_deaths_frame += 1
	return _deaths_frame <= DEATHS_PER_FRAME


func _away_from_player(pos: Vector3) -> Vector3:
	var p := Game.player
	var d := Vector3.FORWARD
	if p and is_instance_valid(p):
		d = pos - p.global_position
		d.y = 0.0
	if d.length_squared() < 0.0001:
		d = Vector3.FORWARD
	return d.normalized()


# ---------------------------------------------------------------- spawners (pooled)

func _blood_burst(amount: float) -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	var at := p.global_position + Vector3(0.0, 1.0, 0.0)
	var r := clampf(0.35 + amount / 18.0, 0.35, 1.0)
	var mist := _mists[_blood_i]
	var drops := _drops[_blood_i]
	_blood_i = (_blood_i + 1) % _mists.size()
	mist.global_transform = Transform3D(Basis.IDENTITY, at)
	drops.global_transform = Transform3D(Basis.IDENTITY, at)
	mist.amount_ratio = r
	drops.amount_ratio = r
	mist.restart()
	drops.restart()
	_blood_light.node.global_position = at
	_start_light(_blood_light, Color(1.0, 0.12, 0.08), 1.2 + 2.0 * r, 0.3)


func _flare(at: Vector3, size: float, life: float, color: Color, energy: float) -> void:
	var fx := _take(_flares)
	var g := fx.node as GeometryInstance3D
	g.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), at)
	g.set_instance_shader_parameter(&"tint", color)
	g.set_instance_shader_parameter(&"energy", energy)
	g.set_instance_shader_parameter(&"roll", randf_range(-0.5, 0.5))
	_start_quad(fx, life)


func _ground(at: Vector3, radius: float, life: float, color: Color, energy: float) -> void:
	var fx := _take(_grounds)
	var g := fx.node as GeometryInstance3D
	g.global_transform = Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3(radius, 1.0, radius)), at)
	g.set_instance_shader_parameter(&"tint", color)
	g.set_instance_shader_parameter(&"energy", energy)
	g.set_instance_shader_parameter(&"seed", randf() * 10.0)
	_start_quad(fx, life)


## `puff` = camera-facing shimmer (radius `size`), else a flat expanding ring on the ground.
func _haze(at: Vector3, size: float, life: float, puff: bool, power: float) -> void:
	var fx := _take(_hazes)
	var g := fx.node as MeshInstance3D
	# Puffs are camera-facing XY quads (diameter `size`); rings are flat 2 x 2 planes (radius `size`).
	g.mesh = _quad_mesh if puff else _plane_mesh
	g.material_override = _haze_puff_mat if puff else _haze_ring_mat
	g.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size if puff else Vector3(size, 1.0, size)), at)
	g.set_instance_shader_parameter(&"power", power)
	_start_quad(fx, life)


func _light(pool: Array[Fx], at: Vector3, color: Color, energy: float, rng: float, life: float) -> void:
	var fx := _take(pool)
	var l := fx.node as OmniLight3D
	l.global_position = at
	l.omni_range = rng
	_start_light(fx, color, energy, life)


func _start_light(fx: Fx, color: Color, energy: float, life: float) -> void:
	var l := fx.node as OmniLight3D
	l.light_color = color
	l.light_energy = energy
	l.visible = true
	fx.energy = energy
	fx.life = life
	fx.t = 0.0
	fx.active = true


func _start_quad(fx: Fx, life: float) -> void:
	fx.t = 0.0
	fx.life = maxf(life, 0.01)
	fx.active = true
	fx.node.visible = true
	(fx.node as GeometryInstance3D).set_instance_shader_parameter(&"progress", 0.0)


## A free pooled effect, or the most advanced one (recycled) when all are busy.
func _take(pool: Array[Fx]) -> Fx:
	var best: Fx = pool[0]
	for fx in pool:
		if not fx.active:
			return fx
		if fx.t > best.t:
			best = fx
	return best


# ---------------------------------------------------------------- pools

func _build_pools() -> void:
	# Hit sparks: gold ichor-light streaks flung away from the blow.
	var spark_mat := _spark_draw(5.0, 0.08, 1.5)
	var spark_proc := _process_mat({
		"direction": Vector3(0.0, 0.35, -1.0), "spread": 55.0, "vel": Vector2(3.5, 9.5),
		"gravity": Vector3(0.0, -16.0, 0.0), "damping": Vector2(2.0, 5.0), "scale": Vector2(0.35, 0.7),
		"radius": 0.15, "align": true,
		"ramp": [[0.0, Color(1.0, 0.95, 0.8, 1.0)], [0.25, Color(1.0, 0.78, 0.38, 1.0)],
			[0.7, Color(0.95, 0.42, 0.12, 0.8)], [1.0, Color(0.6, 0.15, 0.05, 0.0)]],
		"curve": [[0.0, 1.0], [1.0, 0.25]],
	})
	for i in SPARK_POOL:
		_sparks.append(_emitter(spark_proc, spark_mat, 22, 0.42, AABB(Vector3(-4, -3, -4), Vector3(8, 6, 8))))

	# Player hit: dark crimson mist + glowing hellblood droplets.
	var mist_draw := ShaderMaterial.new()
	mist_draw.shader = MIST_SHADER
	var mist_proc := _process_mat({
		"direction": Vector3(0.0, 1.0, 0.0), "spread": 180.0, "vel": Vector2(0.6, 2.2),
		"gravity": Vector3(0.0, -0.8, 0.0), "damping": Vector2(2.5, 4.0), "scale": Vector2(0.35, 0.7),
		"radius": 0.3, "align": false,
		"ramp": [[0.0, Color(0.3, 0.02, 0.025, 0.0)], [0.08, Color(0.24, 0.012, 0.018, 0.75)],
			[0.5, Color(0.14, 0.008, 0.012, 0.4)], [1.0, Color(0.07, 0.005, 0.008, 0.0)]],
		"curve": [[0.0, 0.35], [0.35, 0.75], [1.0, 1.0]],
	})
	var drop_draw := _spark_draw(3.0, 0.08, 0.8)
	var drop_proc := _process_mat({
		"direction": Vector3(0.0, 1.0, 0.0), "spread": 75.0, "vel": Vector2(2.5, 6.0),
		"gravity": Vector3(0.0, -15.0, 0.0), "damping": Vector2(0.5, 1.5), "scale": Vector2(0.25, 0.5),
		"radius": 0.25, "align": true,
		"ramp": [[0.0, Color(1.0, 0.4, 0.2, 1.0)], [0.3, HELLBLOOD], [1.0, Color(0.35, 0.02, 0.02, 0.0)]],
		"curve": [[0.0, 1.0], [1.0, 0.4]],
	})
	for i in BLOOD_POOL:
		_mists.append(_emitter(mist_proc, mist_draw, 22, 0.75, AABB(Vector3(-3, -2, -3), Vector3(6, 5, 6)), 1.6))
		_drops.append(_emitter(drop_proc, drop_draw, 12, 0.6, AABB(Vector3(-3, -2, -3), Vector3(6, 5, 6))))

	# Boss death: a storm of light shards rising out of the Herald.
	var shard_proc := _process_mat({
		"direction": Vector3(0.0, 1.0, 0.0), "spread": 75.0, "vel": Vector2(5.0, 17.0),
		"gravity": Vector3(0.0, -2.5, 0.0), "damping": Vector2(1.0, 3.0), "scale": Vector2(0.6, 1.4),
		"radius": 1.6, "align": true,
		"ramp": [[0.0, Color(1.0, 0.98, 0.92, 1.0)], [0.3, Color(1.0, 0.86, 0.5, 1.0)],
			[0.75, Color(1.0, 0.7, 0.3, 0.6)], [1.0, Color(0.9, 0.5, 0.2, 0.0)]],
		"curve": [[0.0, 1.0], [1.0, 0.2]],
	})
	_boss_shards = _emitter(shard_proc, _spark_draw(5.0, 0.05, 1.4), 160, 2.2,
			AABB(Vector3(-25, -5, -25), Vector3(50, 40, 50)))
	_boss_shards.randomness = 0.5

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	var flare_mat := ShaderMaterial.new()
	flare_mat.shader = FLARE_SHADER
	for i in FLARE_POOL:
		_flares.append(_quad_fx(quad, flare_mat))
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = GROUND_SHADER
	for i in GROUND_POOL:
		_grounds.append(_quad_fx(plane, ground_mat))
	_haze_ring_mat = ShaderMaterial.new()
	_haze_ring_mat.shader = HAZE_SHADER
	_haze_ring_mat.set_shader_parameter(&"strength", 0.03)
	# Refract before the ground mist / sunbeams are drawn, or the copy (taken without them) shows as a dark hole.
	_haze_ring_mat.render_priority = -20
	_haze_puff_mat = ShaderMaterial.new()
	_haze_puff_mat.shader = HAZE_SHADER
	_haze_puff_mat.set_shader_parameter(&"billboard", true)
	_haze_puff_mat.set_shader_parameter(&"strength", 0.018)
	_haze_puff_mat.render_priority = -20
	_quad_mesh = quad
	_plane_mesh = plane
	for i in HAZE_POOL:
		_hazes.append(_quad_fx(plane, _haze_ring_mat))
	for i in HIT_LIGHT_POOL:
		_lights.append(_light_fx())
	_blood_light = _light_fx()


func _spark_draw(energy: float, width: float, stretch: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SPARK_SHADER
	m.set_shader_parameter(&"energy", energy)
	m.set_shader_parameter(&"width", width)
	m.set_shader_parameter(&"stretch", stretch)
	return m


func _process_mat(o: Dictionary) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = o["direction"]
	m.spread = o["spread"]
	m.initial_velocity_min = o["vel"].x
	m.initial_velocity_max = o["vel"].y
	m.gravity = o["gravity"]
	m.damping_min = o["damping"].x
	m.damping_max = o["damping"].y
	m.scale_min = o["scale"].x
	m.scale_max = o["scale"].y
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = o["radius"]
	m.particle_flag_align_y = o["align"]
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for stop: Array in o["ramp"]:
		offs.append(stop[0])
		cols.append(stop[1])
	var g := Gradient.new()
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	var c := Curve.new()
	for pt: Array in o["curve"]:
		c.add_point(Vector2(pt[0], pt[1]))
	var ct := CurveTexture.new()
	ct.curve = c
	m.scale_curve = ct
	return m


func _emitter(proc: ParticleProcessMaterial, draw: Material, amount: int, life: float, aabb: AABB,
		quad_size: float = 1.0) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.randomness = 0.3
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.fixed_fps = 60
	p.process_material = proc
	var q := QuadMesh.new()
	q.size = Vector2(quad_size, quad_size)
	q.material = draw
	p.draw_pass_1 = q
	p.visibility_aabb = aabb
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0.0, -200.0, 0.0)
	add_child(p)
	return p


func _quad_fx(mesh: Mesh, mat: Material) -> Fx:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	# Billboards are built in the vertex shader; give culling room.
	mi.extra_cull_margin = 2.0
	add_child(mi)
	var fx := Fx.new()
	fx.node = mi
	return fx


func _light_fx() -> Fx:
	var l := OmniLight3D.new()
	l.shadow_enabled = false
	l.light_specular = 0.6
	l.omni_attenuation = 1.6
	l.visible = false
	add_child(l)
	var fx := Fx.new()
	fx.node = l
	return fx
