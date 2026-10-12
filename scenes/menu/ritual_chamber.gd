class_name RitualChamber
extends Node3D
## The demon-select set: a ruined ritual chamber at night (environment, moonlight and mist, floor,
## walls and window, broken ceiling, pillars, chains, altar, rubble, the summoning circle with its
## ember spotlight, braziers and candles). Purely visual; split out of demon_select.gd, which owns
## the camera, the demons on their plinths, the UI and the selection logic.
##
## Usage: `var c := RitualChamber.new(); add_child(c); c.build()`, then call `update_lights(t)`
## every frame. `prop()` places further Blender set pieces (the select screen uses it for plinths).
## Set pieces are Blender models from tools/blender/models/menu/*.py (res://assets/models/menu/*.glb).

const SIGIL_SHADER := preload("res://scenes/weapons/brimstone_sigil/sigil.gdshader")
## Blender-made set pieces (they face Godot +Z, i.e. the camera, at yaw 0).
const M_ALTAR := "res://assets/models/menu/altar.glb"
const M_BRAZIER := "res://assets/models/menu/brazier.glb"
const M_CANDLE := "res://assets/models/menu/candle.glb"
const M_CANDLES := "res://assets/models/menu/candles.glb"
const M_PILLAR := "res://assets/models/menu/pillar_full.glb"
const M_PILLAR_BROKEN := "res://assets/models/menu/pillar_broken.glb"
const M_WINDOW := "res://assets/models/menu/window.glb"
const M_CHAIN := "res://assets/models/menu/hanging_chain.glb"
const M_RING := "res://assets/models/menu/summoning_ring.glb"

## Centre of the stage (shifted right so the info panel has room on the left).
const STAGE := Vector3(2.0, 0.0, 0.0)
## Centre and radius of the arc of plinths (the rubble keeps clear of it).
const ARC_CENTER := Vector3(2.0, 0.0, -0.4)
const ARC_RADIUS := 3.9
## Where the chosen demon stands: the heart of the summoning circle.
const FRONT := Vector3(2.0, 0.0, 1.6)
const CIRCLE_RADIUS := 2.1
const MOON_DIR := Vector3(0.22, -1.0, 0.3)
const CEILING_Y := 10.0
const BACK_WALL_Z := -9.0
const FLOOR_X0 := -11.0
const FLOOR_X1 := 15.0
const FLOOR_Z0 := -9.0
const FLOOR_Z1 := 8.0
const FLAME := Color(1.0, 0.6, 0.25)

var _spot: SpotLight3D
var _shaft: MeshInstance3D
var _sigil: MeshInstance3D
var _flicker_lights: Array[OmniLight3D] = []
var _flicker_base: PackedFloat32Array = PackedFloat32Array()


## Builds the whole set under this node. Call once, after adding the node to the tree.
func build() -> void:
	_build_environment()
	_build_chamber()
	_build_circle()
	_build_braziers()
	_build_candles()


## Animates the flickering fires, the pulsing ember spotlight and the turning light shaft.
## `t` is the menu's running clock (seconds).
func update_lights(t: float) -> void:
	for k in _flicker_lights.size():
		var l := _flicker_lights[k]
		var ph := float(k) * 1.7
		l.light_energy = _flicker_base[k] * (1.0 + sin(t * 9.0 + ph) * 0.07 + sin(t * 15.3 + ph * 2.0) * 0.05 \
				+ sin(t * 2.1 + ph) * 0.05)
	if _spot:
		_spot.light_energy = 14.0 * (1.0 + sin(t * 1.4) * 0.06)
	if _shaft:
		_shaft.rotation.y = t * 0.1


# ---------------------------------------------------------------- environment & lights

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.009, 0.014)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.45)
	env.ambient_light_energy = 0.16
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0

	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.ssao_power = 1.5

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.7, 0.72, 0.8)
	env.volumetric_fog_emission = Color(0.012, 0.008, 0.01)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 42.0
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.0

	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.08

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Cold moonlight. The ceiling blocks it except through the hole above the stage, which
	# turns it into a shaft in the fog.
	var moon := DirectionalLight3D.new()
	moon.basis = Basis.looking_at(MOON_DIR.normalized(), Vector3.UP)
	moon.light_color = Color(0.55, 0.64, 0.92)
	moon.light_energy = 1.3
	moon.light_angular_distance = 0.8
	moon.light_volumetric_fog_energy = 4.0
	moon.shadow_enabled = true
	moon.shadow_blur = 1.2
	moon.directional_shadow_max_distance = 40.0
	add_child(moon)

	# Low-lying mist.
	var mist := FogVolume.new()
	mist.size = Vector3(FLOOR_X1 - FLOOR_X0, 1.4, FLOOR_Z1 - FLOOR_Z0)
	mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var fm := FogMaterial.new()
	fm.density = 0.06
	fm.albedo = Color(0.55, 0.55, 0.62)
	fm.height_falloff = 1.5
	fm.edge_fade = 0.8
	mist.material = fm
	mist.position = Vector3((FLOOR_X0 + FLOOR_X1) * 0.5, 0.2, (FLOOR_Z0 + FLOOR_Z1) * 0.5)
	add_child(mist)


# ---------------------------------------------------------------- chamber

func _build_chamber() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6661
	var stones: Array[Material] = [
		Art.mat(Art.STONE.darkened(0.35), 0.9, 0.0, 0.55, false),
		Art.mat(Art.STONE.darkened(0.45), 0.85, 0.0, 0.6, false),
		Art.mat(Art.ASH.darkened(0.1), 0.92, 0.0, 0.5, false),
	]
	var grout := Art.mat(Art.OBSIDIAN, 0.95, 0.0, 0.3, false)
	var wall_mat := Art.mat(Art.STONE.darkened(0.5), 0.92, 0.0, 0.6, false)
	var trim_mat := Art.mat(Art.STONE.darkened(0.3), 0.85, 0.0, 0.5, false)

	# Floor: dark grout bed with uneven flagstones.
	_static(Art.part(self, Art.box(), grout, Vector3((FLOOR_X0 + FLOOR_X1) * 0.5, -0.3, (FLOOR_Z0 + FLOOR_Z1) * 0.5),
			Vector3(FLOOR_X1 - FLOOR_X0, 0.4, FLOOR_Z1 - FLOOR_Z0)))
	var tile := 1.5
	var x := FLOOR_X0
	while x < FLOOR_X1:
		var z := FLOOR_Z0
		while z < FLOOR_Z1:
			if rng.randf() > 0.04:
				var h := rng.randf_range(-0.03, 0.01)
				var tilt := Vector3(rng.randf_range(-0.015, 0.015), 0.0, rng.randf_range(-0.015, 0.015))
				_static(Art.part(self, Art.box(), stones[rng.randi() % stones.size()],
						Vector3(x + tile * 0.5, -0.1 + h, z + tile * 0.5), Vector3(tile - 0.06, 0.2, tile - 0.06), tilt))
			z += tile
		x += tile

	# Back wall with a tall pointed window onto a red, burning sky.
	var win_x := STAGE.x
	var win_w := 3.0
	var win_y0 := 2.6
	var t := 0.8
	var win_top := 8.8  # top of the rectangular wall opening (the window model fills its corners)
	_static(Art.part(self, Art.box(), wall_mat, Vector3((FLOOR_X0 + win_x - win_w * 0.5) * 0.5, CEILING_Y * 0.5, BACK_WALL_Z),
			Vector3(win_x - win_w * 0.5 - FLOOR_X0, CEILING_Y, t)))
	_static(Art.part(self, Art.box(), wall_mat, Vector3((win_x + win_w * 0.5 + FLOOR_X1) * 0.5, CEILING_Y * 0.5, BACK_WALL_Z),
			Vector3(FLOOR_X1 - win_x - win_w * 0.5, CEILING_Y, t)))
	_static(Art.part(self, Art.box(), wall_mat, Vector3(win_x, win_y0 * 0.5, BACK_WALL_Z), Vector3(win_w, win_y0, t)))
	_static(Art.part(self, Art.box(), wall_mat, Vector3(win_x, (win_top + CEILING_Y) * 0.5, BACK_WALL_Z),
			Vector3(win_w, CEILING_Y - win_top, t)))
	# Carved pointed-arch frame, mullions, tracery and sill (Blender model).
	prop(M_WINDOW, Vector3(win_x, 0.0, BACK_WALL_Z))
	var sky := Art.part(self, Art.box(), Art.glow(Color(0.5, 0.07, 0.04), 1.1, false), Vector3(win_x, 5.5, BACK_WALL_Z - 1.2),
			Vector3(win_w + 2.0, 7.0, 0.1))
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sky_light := Art.light(self, Color(1.0, 0.25, 0.1), 1.6, 9.0, Vector3(win_x, 5.0, BACK_WALL_Z + 1.0))
	sky_light.light_volumetric_fog_energy = 1.5
	# Wall pilasters and a cornice.
	for px: float in [-8.0, -4.0, 8.0, 12.0]:
		_static(Art.part(self, Art.box(), trim_mat, Vector3(STAGE.x + px * 0.75, CEILING_Y * 0.5, BACK_WALL_Z + 0.5),
				Vector3(0.7, CEILING_Y, 0.4)))
	_static(Art.part(self, Art.box(), trim_mat, Vector3((FLOOR_X0 + FLOOR_X1) * 0.5, 0.25, BACK_WALL_Z + 0.5),
			Vector3(FLOOR_X1 - FLOOR_X0, 0.5, 0.4)))
	# Side walls.
	for sx: float in [FLOOR_X0, FLOOR_X1]:
		_static(Art.part(self, Art.box(), wall_mat, Vector3(sx, CEILING_Y * 0.5, (FLOOR_Z0 + FLOOR_Z1) * 0.5),
				Vector3(t, CEILING_Y, FLOOR_Z1 - FLOOR_Z0)))

	_build_ceiling(wall_mat, rng)
	_build_pillars(rng)
	_build_altar()
	_build_rubble(stones, rng)


## Ceiling slabs with a ragged hole above the stage; the moon shines through it.
func _build_ceiling(mat: Material, rng: RandomNumberGenerator) -> void:
	var d := MOON_DIR.normalized()
	var target := FRONT + Vector3(0.0, 0.0, -1.2)
	var hole := target - d * (CEILING_Y / -d.y)
	var cell := 2.0
	var x := FLOOR_X0
	while x < FLOOR_X1:
		var z := FLOOR_Z0
		while z < FLOOR_Z1 + 4.0:
			var c := Vector3(x + cell * 0.5, CEILING_Y, z + cell * 0.5)
			var dist := Vector2(c.x - hole.x, c.z - hole.z).length()
			var ragged := 2.6 + rng.randf_range(-0.8, 0.8)
			if dist > ragged:
				_static(Art.part(self, Art.box(), mat, c + Vector3(0.0, rng.randf_range(0.0, 0.2), 0.0),
						Vector3(cell + 0.05, 0.6, cell + 0.05)))
			elif dist > ragged - 0.9 and rng.randf() < 0.5:
				# Broken slab hanging into the hole.
				_static(Art.part(self, Art.box(), mat, c + Vector3(0.0, -0.4, 0.0), Vector3(cell * 0.7, 0.4, cell * 0.5),
						Vector3(rng.randf_range(-0.5, 0.5), rng.randf(), rng.randf_range(-0.5, 0.5))))
			z += cell
		x += cell
	# A cracked beam still spanning the hole.
	_static(Art.part(self, Art.box(), Art.mat(Art.LEATHER.darkened(0.3), 0.9, 0.0, 0.6, false),
			hole + Vector3(0.3, -0.5, 0.0), Vector3(6.0, 0.35, 0.4), Vector3(0.0, 0.5, 0.12)))


func _build_pillars(rng: RandomNumberGenerator) -> void:
	var spots: Array[Vector3] = [
		Vector3(-5.2, 0.0, -6.0), Vector3(-6.0, 0.0, -1.0), Vector3(-6.4, 0.0, 4.0),
		Vector3(9.2, 0.0, -6.0), Vector3(10.0, 0.0, -1.0), Vector3(10.4, 0.0, 4.0),
	]
	for i in spots.size():
		var p := spots[i]
		if i == 1 or i == 5:
			# Broken pier; its fallen drums lie on the model's +X side: turn them away from the stage.
			prop(M_PILLAR_BROKEN, p, PI if p.x < STAGE.x else 0.0)
		else:
			prop(M_PILLAR, p, rng.randf_range(-0.1, 0.1))
	# Hanging chains (the model is 5.6 m to the hook; the excess is hidden in the ceiling).
	for c: Vector3 in [Vector3(-3.0, 0.0, -3.5), Vector3(7.0, 0.0, -4.0), Vector3(-1.5, 0.0, 2.5)]:
		var length := rng.randf_range(3.5, 5.5)
		prop(M_CHAIN, Vector3(c.x, CEILING_Y - 0.3 + (5.6 - length), c.z), rng.randf() * TAU)


## Gothic altar: carved arcade, skull pile, torn runner, candles and the great candelabrum.
func _build_altar() -> void:
	prop(M_ALTAR, Vector3(STAGE.x, 0.0, -6.9))


func _build_rubble(stones: Array[Material], rng: RandomNumberGenerator) -> void:
	for k in 40:
		var p := Vector3(rng.randf_range(FLOOR_X0 + 1.0, FLOOR_X1 - 1.0), 0.0, rng.randf_range(FLOOR_Z0 + 1.0, FLOOR_Z1 - 1.0))
		# Keep the stage and the walk paths clear.
		if Vector2(p.x - ARC_CENTER.x, p.z - ARC_CENTER.z).length() < ARC_RADIUS + 1.6 and p.z > FLOOR_Z0 + 2.5:
			continue
		var s := rng.randf_range(0.15, 0.55)
		_static(Art.part(self, Art.box(), stones[rng.randi() % stones.size()], p + Vector3(0.0, s * 0.35, 0.0),
				Vector3(s, s * 0.7, s * rng.randf_range(0.7, 1.3)),
				Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4))))


# ---------------------------------------------------------------- summoning circle & lights

func _build_circle() -> void:
	var sm := ShaderMaterial.new()
	sm.shader = SIGIL_SHADER
	sm.set_shader_parameter(&"intensity", 0.75)
	sm.set_shader_parameter(&"spin", 0.012)
	sm.set_shader_parameter(&"rune_count", 20.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.material = sm
	_sigil = MeshInstance3D.new()
	_sigil.mesh = plane
	_sigil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sigil.position = FRONT + Vector3(0.0, 0.03, 0.0)
	_sigil.scale = Vector3(CIRCLE_RADIUS, 1.0, CIRCLE_RADIUS)
	_sigil.set_instance_shader_parameter(&"radius", CIRCLE_RADIUS)
	add_child(_sigil)
	# Carved stone floor ring with a glowing groove around the sigil.
	prop(M_RING, FRONT, 0.3)
	var under := Art.light(self, Art.HELLFIRE, 1.4, CIRCLE_RADIUS * 2.2, FRONT + Vector3(0.0, 0.35, 0.0))
	_flicker(under)

	# Pillar of ember-light on the chosen demon.
	_spot = SpotLight3D.new()
	_spot.position = FRONT + Vector3(0.0, 8.5, 0.0)
	_spot.basis = Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
	_spot.light_color = Color(1.0, 0.5, 0.22)
	_spot.light_energy = 14.0
	_spot.spot_range = 12.0
	_spot.spot_angle = 11.0
	_spot.spot_attenuation = 0.6
	_spot.light_volumetric_fog_energy = 1.4
	_spot.shadow_enabled = true
	add_child(_spot)
	_shaft = Art.part(self, Art.cylinder(0.75, 1.0), Art.glow(Art.EMBER, 0.5, true, 0.07), FRONT + Vector3(0.0, 4.5, 0.0),
			Vector3(1.6, 9.0, 1.6))
	var column := InfernalFx.make_particles(Art.EMBER, 46, 4.0, 3.0)
	column.local_coords = false
	column.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	column.emission_box_extents = Vector3(0.8, 0.1, 0.8)
	column.direction = Vector3.UP
	column.spread = 12.0
	column.initial_velocity_min = 0.4
	column.initial_velocity_max = 1.0
	column.gravity = Vector3(0.0, 0.5, 0.0)
	column.damping_min = 0.0
	column.damping_max = 0.2
	column.scale_amount_curve = InfernalFx.swell_curve()
	column.position = FRONT + Vector3(0.0, 0.1, 0.0)
	add_child(column)


func _build_braziers() -> void:
	_brazier(FRONT + Vector3(-3.4, 0.0, 0.9), true)
	_brazier(FRONT + Vector3(3.4, 0.0, 0.9), true)
	_brazier(Vector3(STAGE.x - 3.4, 0.0, -6.4), false)
	_brazier(Vector3(STAGE.x + 3.4, 0.0, -6.4), false)


func _brazier(pos: Vector3, shadows: bool) -> void:
	var root := Art.pivot(self, pos)
	prop(M_BRAZIER, Vector3.ZERO, randf() * TAU, 1.0, root)
	var tongue := CylinderMesh.new()
	tongue.top_radius = 0.0
	tongue.bottom_radius = 0.09
	tongue.height = 0.5
	tongue.radial_segments = 6
	tongue.rings = 1
	var flames := InfernalFx.make_particles(Art.HELLFIRE, 22, 0.7, 2.6)
	flames.mesh = tongue
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.22
	flames.direction = Vector3.UP
	flames.spread = 10.0
	flames.initial_velocity_min = 0.6
	flames.initial_velocity_max = 1.3
	flames.gravity = Vector3(0.0, 1.0, 0.0)
	flames.scale_amount_curve = InfernalFx.swell_curve()
	flames.scale_amount_min = 0.8
	flames.scale_amount_max = 1.6
	flames.position = Vector3(0.0, 1.35, 0.0)
	root.add_child(flames)
	InfernalFx.embers(root, Art.EMBER, 14, 2.2, 0.2, Vector3(0.0, 1.5, 0.0), 3.0)
	var l := Art.light(root, Color(1.0, 0.48, 0.16), 2.4, 8.0, Vector3(0.0, 1.9, 0.0), shadows)
	l.light_volumetric_fog_energy = 0.6
	_flicker(l)


func _build_candles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	# Ring of candles standing on the stone ring around the summoning circle.
	for k in 14:
		var a := TAU * float(k) / 14.0 + 0.1
		var r := CIRCLE_RADIUS + 0.38 + rng.randf_range(-0.04, 0.12)
		var p := FRONT + Vector3(cos(a) * r, 0.05, sin(a) * r)
		_candle(p, rng.randf_range(0.14, 0.4), rng.randf_range(0.04, 0.065))
	# Clusters on the altar steps and by the walls (the altar slab carries its own candles).
	for c: Vector3 in [Vector3(STAGE.x - 1.6, 0.55, -5.9), Vector3(STAGE.x + 1.5, 0.55, -5.95),
			Vector3(-3.5, 0.0, -7.5), Vector3(8.4, 0.0, -7.6), Vector3(-4.6, 0.0, 3.2)]:
		prop(M_CANDLES, c, rng.randf() * TAU, rng.randf_range(0.9, 1.15))
	# One warm light over the altar; the wall clusters glow by bloom alone (2 fewer lights).
	_flicker(Art.light(self, FLAME, 1.4, 5.0, Vector3(STAGE.x, 2.3, -6.4)))


## A single pillar candle (Blender model) scaled to `height` / `radius`.
func _candle(base: Vector3, height: float, radius: float) -> void:
	var k := radius / 0.05
	prop(M_CANDLE, base, randf() * TAU).scale = Vector3(k, height / 0.3, k)


## Static Blender set piece (flashable = false) placed at `pos`, turned `yaw` about Y.
func prop(path: String, pos: Vector3, yaw: float = 0.0, scl: float = 1.0, parent: Node3D = null) -> GlbModel:
	var m := GlbModel.create(path, false)
	m.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	m.position = pos
	m.rotation.y = yaw
	m.scale = Vector3.ONE * scl
	if parent:
		parent.add_child(m)
	else:
		add_child(m)
	return m


static func find_mesh(root: Node, mesh_name: String) -> MeshInstance3D:
	if root is MeshInstance3D and root.name == mesh_name:
		return root as MeshInstance3D
	for c in root.get_children():
		var f := find_mesh(c, mesh_name)
		if f:
			return f
	return null


func _flicker(l: OmniLight3D) -> void:
	_flicker_lights.append(l)
	_flicker_base.append(l.light_energy)


func _static(mi: MeshInstance3D) -> MeshInstance3D:
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	return mi
