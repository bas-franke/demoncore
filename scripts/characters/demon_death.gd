class_name DemonDeath
extends RefCounted
## Per-demon death (characters-polish round 3). DemonModel plays the demon's own Blender "death"
## clip, then hands each part of the body to this helper as a burning line sweeps down it:
##   &"ash"      Vharok: the ravager burns out, each part crumbling to ash where it stands.
##   &"feathers" Lilaeth: the parts rise and spin away like burning feathers, embers and feathers
##               bursting from her.
##   &"hex"      Morvane: the parts spiral into the grimoire's light and vanish, a hex ring
##               flaring on the ground.
##   &"crumble"  Skarn: the furnace bursts, the iron body falls apart in heavy pieces that drop,
##               tumble and settle, then go dark.
##   &"unravel"  Ysolde: the robes sink empty into the ground, swaying, while the souls she
##               carried fly free.
##   &"turncoat" Iscariel: the charred wing crumbles first (its pieces drop and tumble), then
##               the body burns away top-down, and the pale wing burns last in a burst of
##               white-gold feathers.
##   &"swarm"    Nhazgul: the hive bursts: every part shudders, then pops outward and is gone in
##               a buzzing cloud of flies (with a few glowing larvae) that swirls up and away.
## Styles are picked by the demon's model id (STYLE_BY_DEMON); unknown demons burn to ash.

const STYLE_BY_DEMON := {
	&"vharok": &"ash", &"lilaeth": &"feathers", &"morvane": &"hex", &"skarn": &"crumble",
	&"ysolde": &"unravel", &"nhazgul": &"swarm", &"iscariel": &"turncoat",
}
## How much of the body (normalized height) the sweep is "inside" at once per style: wider =
## slower, overlapping part motion.
const WINDOW := {&"ash": 0.14, &"feathers": 0.35, &"hex": 0.5, &"crumble": 0.4, &"unravel": 0.55,
	&"swarm": 0.3, &"turncoat": 0.3}

var style := &"ash"
var _model: DemonModel
## Per part: [mesh, rest local xf, base global xf, out dir (flat), spin axis, phase, wing side
## (-1 left wing, +1 right wing, 0 body)]
var _parts: Array = []
var _center := Vector3.ZERO
var _ground := 0.0


static func style_for(model_id: StringName) -> StringName:
	return STYLE_BY_DEMON.get(model_id, &"ash")


func _init(model: DemonModel, death_style: StringName) -> void:
	_model = model
	style = death_style


## Captures the parts (at the end of the death clip) and fires the style's opening effect.
func start(meshes: Array[MeshInstance3D]) -> void:
	_parts.clear()
	_ground = _model.global_position.y
	var c := Vector3.ZERO
	for mi in meshes:
		c += mi.global_transform * mi.get_aabb().get_center()
	_center = c / float(maxi(meshes.size(), 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for mi in meshes:
		var mc := mi.global_transform * mi.get_aabb().get_center()
		var out := mc - _center
		out.y = 0.0
		out = out.normalized() if out.length_squared() > 0.0001 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		_parts.append([mi, mi.transform, mi.global_transform, out, axis, rng.randf() * TAU, _wing_side(mi)])
	for p: Array in _parts:
		var mi := p[0] as MeshInstance3D
		if int(p[6]) != 0 and mi.mesh:
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si)
				if m and m.resource_name.to_lower().contains("burnt"):
					_charred = int(p[6])
	_opening()


## d: 0..1 through the dissolve; sweep: the burning line (normalized height, 1.08 -> -0.14);
## heights: per part normalized height (DemonModel's dissolve list order = start() order).
func step(d: float, sweep: float, heights: Array) -> void:
	var win: float = WINDOW.get(style, 0.14)
	for i in _parts.size():
		var p: Array = _parts[i]
		var mi := p[0] as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		var k := clampf((float(heights[i]) - sweep) / win, 0.0, 1.0)
		var side: int = p[6]
		if style == &"turncoat":
			# Normalize: -1 = the charred wing, +1 = the pale one.
			side = 0 if side == 0 else (-1 if side == _charred else 1)
			k = _turncoat_k(d, side, float(heights[i]))
		var base: Transform3D = p[2]
		var out: Vector3 = p[3]
		var axis: Vector3 = p[4]
		var ph: float = p[5]
		var e := k * k * (3.0 - 2.0 * k)
		var xf := base
		var s := 1.0
		match style:
			&"feathers":
				xf.origin = base.origin + Vector3(0.0, 1.3 * k * k, 0.0) + out * 0.35 * e \
					+ Vector3(sin(ph + k * 5.0), 0.0, cos(ph + k * 5.0)) * 0.12 * k
				xf.basis = Basis(axis, k * 3.0) * base.basis
				s = 1.0 - e
			&"hex":
				var rel := base.origin - _center
				xf.origin = _center + Vector3(0.0, 0.25 * e, 0.0) + rel.rotated(Vector3.UP, e * 4.0) * (1.0 - e)
				xf.basis = Basis(Vector3.UP, e * 4.0) * base.basis
				s = 1.0 - e
			&"crumble":
				var h0 := maxf(base.origin.y - _ground - 0.08, 0.0)
				var fall := minf(k * 1.25, 1.0)
				xf.origin = base.origin - Vector3(0.0, h0 * fall * fall, 0.0) + out * 0.3 * e
				if k > 0.8:
					xf.origin.y += 0.08 * sin((k - 0.8) / 0.2 * PI)  # one bounce
				xf.basis = Basis(axis, 1.6 * e) * base.basis
				s = 1.0 - clampf((d - 0.8) / 0.2, 0.0, 1.0)
			&"turncoat":
				if side < 0:
					# Charred wing: crumbles, the pieces dropping and tumbling to the ground.
					var h0 := maxf(base.origin.y - _ground - 0.05, 0.0)
					xf.origin = base.origin - Vector3(0.0, h0 * minf(k * 1.3, 1.0) ** 2, 0.0) + out * 0.25 * e
					xf.basis = Basis(axis, 2.0 * e) * base.basis
					s = 1.0 - clampf((k - 0.75) / 0.25, 0.0, 1.0)
				elif side > 0:
					# Pale wing: burns last, lifting and curling as it goes.
					xf.origin = base.origin + Vector3(0.0, 0.5 * e, 0.0) + out * 0.2 * e
					xf.basis = Basis(axis, 1.2 * e) * base.basis
					s = 1.0 - e
				else:
					s = 1.0 - k
			&"swarm":
				# A shudder while the sweep approaches, then the part pops outward and is gone.
				var pre := clampf((float(heights[i]) - sweep + 0.25) / 0.25, 0.0, 1.0) * (1.0 - k)
				var shake := Vector3(sin(ph * 7.0 + d * 90.0), sin(ph * 3.0 + d * 113.0), cos(ph * 5.0 + d * 97.0))
				xf.origin = base.origin + shake * 0.025 * pre + (out * 0.55 + Vector3(0.0, 0.35, 0.0)) * e
				xf.basis = Basis(axis, 2.5 * e) * base.basis
				s = 1.0 - minf(e * 1.4, 1.0)
			&"unravel":
				xf.origin = base.origin - Vector3(0.0, 1.5 * e, 0.0) + Vector3(sin(ph + k * 6.0), 0.0, 0.0) * 0.06 * k
				s = 1.0 - 0.4 * e
				if xf.origin.y < _ground - 0.3:
					s = 0.0
			_:
				s = 1.0 - k
		var sc := Basis.from_scale(Vector3.ONE * maxf(s, 0.001))
		if style == &"ash":
			var rest: Transform3D = p[1]
			mi.transform = Transform3D(rest.basis * sc, rest.origin)
		else:
			mi.global_transform = Transform3D(xf.basis * sc, xf.origin)
		mi.visible = s > 0.002


var _pale_burst := false
## Which wing chain is the charred one (-1 / +1, see _wing_side); found from its "Burnt" material.
var _charred := -1


## Turncoat timing: charred wing (side -1) over d 0..0.35, body sweep 0.25..0.8, pale wing 0.75..1.
func _turncoat_k(d: float, side: int, height: float) -> float:
	if side < 0:
		return clampf(d / 0.35, 0.0, 1.0)
	if side > 0:
		if d >= 0.75 and not _pale_burst:
			_pale_burst = true
			EnemyModel.spawn_feathers(_center + Vector3(0.0, 0.4, 0.0), 16, 1.2, Art.HOLY_WHITE)
			_model._burst_local(_model.to_local(_center) + Vector3(0.0, 0.3, 0.0), Art.HOLY, 26, 2.8)
		return clampf((d - 0.75) / 0.25, 0.0, 1.0)
	var sweep := 1.08 - clampf((d - 0.25) / 0.55, 0.0, 1.0) * 1.22
	return clampf((height - sweep) / 0.3, 0.0, 1.0)


## -1 if the mesh hangs from the left wing chain, +1 right, 0 otherwise (sb rig names).
func _wing_side(mi: Node) -> int:
	var n := mi.get_parent()
	while n and n != _model:
		var nm := String(n.name)
		if nm.begins_with("wing") or nm.begins_with("pfan"):
			if nm.ends_with("_L"):
				return -1
			if nm.ends_with("_R"):
				return 1
		n = n.get_parent()
	return 0


## Puts every part back (revive / rebuild).
func restore() -> void:
	_pale_burst = false
	for p: Array in _parts:
		var mi := p[0] as MeshInstance3D
		if is_instance_valid(mi):
			mi.transform = p[1]
			mi.visible = true
	_parts.clear()


func _opening() -> void:
	var glow := _model.glow_color
	var chest := _model.to_local(_center)
	match style:
		&"feathers":
			_model._burst_local(chest, glow, 30, 3.0)
			EnemyModel.spawn_feathers(_center, 14, 1.2, glow.lerp(Art.OBSIDIAN, 0.5))
		&"hex":
			_model._burst_local(chest, glow, 20, 2.0)
			EnemyModel.shockwave(Vector3(_center.x, _ground + 0.06, _center.z), 2.4, glow, 0.7)
			EnemyModel.spawn_motes(_center, 10, 1.0, glow)
		&"crumble":
			# The furnace gives out: a blast of fire from the chest, then the iron falls.
			_model._burst_local(chest, glow, 45, 4.5)
			EnemyModel.poof(Vector3(_center.x, _ground + 0.2, _center.z), Art.STONE, Art.ASH, 8, 0.45, 1.1)
			EnemyModel.light_flash(_center, 1.1, glow, false)
		&"unravel":
			EnemyModel.spawn_motes(_center + Vector3(0.0, 0.4, 0.0), 16, 1.3, glow)
		&"swarm":
			_swarm(chest, glow)
		&"turncoat":
			# The charred wing gives way first: a puff of soot and cinders.
			EnemyModel.poof(_center, Art.ASH, Art.OBSIDIAN, 6, 0.35, 0.7)
			_model._burst_local(chest, glow, 16, 2.0)
		_:
			_model._burst_local(chest, glow, 26, 3.0)


## Nhazgul's flies: a dark, swirling cloud bursting out of the body (plus a few glowing larvae),
## spreading and rising as it thins out. Parented to the model so it works on menus too.
func _swarm(at: Vector3, glow: Color) -> void:
	var fly_m := StandardMaterial3D.new()
	fly_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fly_m.albedo_color = Color(0.04, 0.05, 0.02)
	var mesh := SphereMesh.new()
	mesh.radius = 0.022
	mesh.height = 0.03
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.material = fly_m
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = 140
	p.lifetime = 2.4
	p.one_shot = true
	p.explosiveness = 0.55
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.55
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0.0, 0.7, 0.0)
	p.radial_accel_min = 0.6
	p.radial_accel_max = 2.2
	p.tangential_accel_min = 4.0
	p.tangential_accel_max = 9.0
	p.damping_min = 0.8
	p.damping_max = 1.6
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.7, 0.9))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.position = at
	_model.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	_model._burst_local(at, glow, 18, 2.4)
	Sfx.play(&"plague", 0.1, -6.0)
