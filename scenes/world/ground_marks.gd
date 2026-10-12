class_name GroundMarks
extends Node3D
## Persistent ground marks: holy burns and feathers where angels die, cracked craters for elites and
## bosses, dark blood drops where the player is hurt. Everything is drawn by two MultiMeshes of flat
## quads (one draw call each) using a texture atlas built by res://tools/build_decals.gd; fading,
## glow cooling and the stamp "pop" all run in ground_marks.gdshader, so the CPU only writes one
## instance per new mark. Ring-buffer pools: the oldest mark is reused. Lifetimes shrink when marks
## are spawned faster than the pool can hold them, so a mark has always faded before it is reused.
##
## Add as a child of Main (anywhere; it is top-level and works in world space).

enum Cell { HOLY_BURN, SIGIL, SPLATTER, DROPS, CRATER, FEATHERS, SCORCH, SMEAR }

## Small marks: burns, feathers, blood.
const POOL_SIZE := 160
## Craters (elites, bosses) live in their own pool so the swarm never recycles them.
const BIG_POOL_SIZE := 12
## Enemy.ELITE_XP: enemies worth at least this much XP are elites.
const ELITE_XP := 20
const HEIGHT := 0.035
const GOLD := Color(1.0, 0.72, 0.3)
const PALE_GOLD := Color(1.0, 0.86, 0.58)
const BLOOD_GLOW := Color(0.85, 0.1, 0.04)

const SHADER := preload("res://scenes/world/ground_marks.gdshader")
const ALBEDO_TEX := preload("res://assets/textures/decal_atlas_albedo.png")
const DATA_TEX := preload("res://assets/textures/decal_atlas_data.png")

@export_range(10.0, 60.0) var min_life := 20.0
@export_range(10.0, 90.0) var max_life := 40.0

var _time := 0.0
var _small: _Pool
var _big: _Pool
var _blood_acc := 0.0
var _blood_cd := 0.0
var _shared_mat: ShaderMaterial
var _big_mat: ShaderMaterial


class _Pool:
	var mm: MultiMesh
	var size: int
	var next := 0
	## Marks/second, smoothed; used to cap lifetimes so the ring buffer never cuts a visible mark.
	var rate := 0.0
	var window := 0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_shared_mat = ShaderMaterial.new()
	_shared_mat.shader = SHADER
	_shared_mat.set_shader_parameter(&"albedo_tex", ALBEDO_TEX)
	_shared_mat.set_shader_parameter(&"data_tex", DATA_TEX)
	_big_mat = _shared_mat.duplicate()
	_big = _make_pool(BIG_POOL_SIZE, _big_mat, "Craters")
	_small = _make_pool(POOL_SIZE, _shared_mat, "Marks")
	# Craters sort as if slightly farther, so burns / blood / feathers usually land on top of them.
	# (No render_priority: that would also put them under transparent ground mist / fog cards.)
	(get_node("Craters") as GeometryInstance3D).sorting_offset = -2.0
	Game.enemy_died.connect(_on_enemy_died)
	Game.player_hit.connect(_on_player_hit)
	Game.boss_died.connect(_on_boss_died)
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_update_rates)
	add_child(t)


func _make_pool(n: int, mat: Material, node_name: String) -> _Pool:
	var p := _Pool.new()
	p.size = n
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = n
	mm.custom_aabb = AABB(Vector3(-2000, -1, -2000), Vector3(4000, 2, 4000))
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0))
	for i in n:
		mm.set_instance_transform(i, hidden)
		mm.set_instance_custom_data(i, Color(0, -1000, 1, 0))
		mm.set_instance_color(i, Color(0, 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi)
	p.mm = mm
	return p


func _process(delta: float) -> void:
	_time += delta
	_shared_mat.set_shader_parameter(&"now", _time)
	_big_mat.set_shader_parameter(&"now", _time)
	_blood_cd -= delta
	_blood_acc = maxf(_blood_acc - delta * 1.5, 0.0)
	if _blood_acc >= 2.0 and _blood_cd <= 0.0 and is_instance_valid(Game.player):
		_bleed(Game.player.global_position, clampi(int(_blood_acc / 8.0) + 1, 1, 3))
		_blood_acc = 0.0
		_blood_cd = 0.45


func _update_rates() -> void:
	for p in [_small, _big]:
		p.rate = lerpf(p.rate, float(p.window), 0.35)
		p.window = 0


# ------------------------------------------------------------------ public API

## Stamps one mark. `diameter` in world units, `heat` 0 = no glow, ~1 = bright, >1 = white-hot.
func add_mark(cell: int, pos: Vector3, diameter: float, heat := 0.0, tint := GOLD,
		opacity := 1.0, big := false, life := -1.0) -> void:
	var p := _big if big else _small
	if life < 0.0:
		life = randf_range(min_life, max_life)
	# Cap so the pool turns over no faster than marks fade (with the burst headroom of 15%).
	var cap := 0.85 * p.size / maxf(p.rate, 0.1)
	life = clampf(minf(life, cap), 6.0, life)
	var i := p.next
	p.next = (p.next + 1) % p.size
	p.window += 1
	var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(diameter, 1.0, diameter))
	p.mm.set_instance_transform(i, Transform3D(b, Vector3(pos.x, HEIGHT, pos.z)))
	p.mm.set_instance_custom_data(i, Color(float(cell), _time, life, heat))
	p.mm.set_instance_color(i, Color(tint.r, tint.g, tint.b, opacity))


## Elite / boss impact: golden seal burnt around a cracked crater, feathers flung outward.
func add_crater(pos: Vector3, diameter: float, heat := 1.5, with_seal := false) -> void:
	var life := max_life * 1.25
	if with_seal:
		add_mark(Cell.SIGIL, pos, diameter * 1.55, heat * 0.9, GOLD, 1.0, true, life)
	else:
		add_mark(Cell.HOLY_BURN, pos, diameter * 1.35, heat * 0.8, GOLD, 0.85, true, life)
	add_mark(Cell.CRATER, pos, diameter, heat, PALE_GOLD, 1.0, true, life)
	var n := 3 if not with_seal else 4
	for k in n:
		var a := TAU * (k + randf() * 0.6) / n
		var off := Vector3(cos(a), 0.0, sin(a)) * diameter * randf_range(0.45, 0.75)
		add_mark(Cell.FEATHERS, pos + off, diameter * randf_range(0.35, 0.5), 0.4, PALE_GOLD)


# ------------------------------------------------------------------ events

func _on_enemy_died(pos: Vector3, data: Resource) -> void:
	var size := 1.0
	var xp := 0
	if data:
		var s: Variant = data.get(&"size")
		if s != null:
			size = float(s)
		var x: Variant = data.get(&"xp_value")
		if x != null:
			xp = int(x)
	if xp >= ELITE_XP:
		add_crater(pos, 2.6 * size + 1.0, 1.5)
		return
	var heat := randf_range(0.85, 1.25)
	if size < 0.8:
		# Small wisps: a modest scorch, sometimes a burn ring.
		var wisp_cell := Cell.HOLY_BURN if randf() < 0.45 else Cell.SCORCH
		add_mark(wisp_cell, pos, randf_range(1.2, 1.6) * size + 0.5, heat * 0.8, GOLD, 0.9)
		if randf() < 0.2:
			_feathers(pos, size)
		return
	var cell := Cell.SIGIL if randf() < 0.2 else Cell.HOLY_BURN
	add_mark(cell, pos, randf_range(1.5, 2.0) * size + 0.4, heat, GOLD, 0.9)
	if randf() < 0.4:
		_feathers(pos, size)


func _feathers(pos: Vector3, size: float) -> void:
	var off := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3)) * size
	add_mark(Cell.FEATHERS, pos + off, randf_range(1.0, 1.35) * size + 0.3, 0.35, PALE_GOLD, 0.9)


func _on_boss_died(pos: Vector3) -> void:
	add_crater(pos, 9.0, 2.2, true)


func _on_player_hit(amount: float) -> void:
	_blood_acc += amount


func _bleed(at: Vector3, count: int) -> void:
	for k in count:
		var a := randf() * TAU
		var off := Vector3(cos(a), 0.0, sin(a)) * randf_range(0.25, 0.8)
		var cell: int = [Cell.DROPS, Cell.DROPS, Cell.SPLATTER, Cell.SMEAR].pick_random()
		var d := randf_range(0.55, 0.95) if cell != Cell.SPLATTER else randf_range(0.6, 0.85)
		add_mark(cell, at + off, d, 0.3, BLOOD_GLOW, 0.95)
