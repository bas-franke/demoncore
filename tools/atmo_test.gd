extends Node3D
## Atmosphere test arena (tools/atmo_test.tscn): a self-contained stand-in for a run, independent of
## the gameplay scenes, for looking at presets and weather:
##   godot --path . res://tools/atmo_test.tscn -- --atmo=storm_spire
##   godot --path . res://tools/atmo_test.tscn -- --atmo-tour=C:/tmp/shots [--atmo-tour-boss]
## Builds main.tscn's lighting rig (a copy of its Environment, a Sun, the stock Atmosphere node),
## a stone floor with pillars and rubble, two hellfire braziers, a "demon" capsule in group
## &"atmo_focus" walking a slow circle, and the run camera angle. Shift+F7 / Shift+F8 work here too.

const LEGACY_ATMO := preload("res://scenes/world/atmosphere.gd")

var _demon: Node3D
var _t := 0.0


func _ready() -> void:
	_build_lighting()
	_build_arena()
	_demon = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.8
	(_demon as MeshInstance3D).mesh = cap
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.05, 0.04)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.25, 0.05)
	m.emission_energy_multiplier = 0.4
	(_demon as MeshInstance3D).material_override = m
	_demon.position = Vector3(0, 0.9, 0)
	_demon.add_to_group(&"atmo_focus")
	add_child(_demon)
	var cam := Camera3D.new()
	cam.fov = 35.0
	cam.near = 1.0
	cam.far = 100.0
	cam.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-55.0)), Vector3(0, 21.7, 14.91))
	add_child(cam)
	cam.current = true
	if not " ".join(OS.get_cmdline_user_args()).contains("--atmo"):
		Atmosphere.apply_preset("cathedral_city")


func _process(delta: float) -> void:
	_t += delta
	_demon.position = Vector3(cos(_t * 0.25) * 3.0, 0.9, sin(_t * 0.25) * 3.0)


func _build_lighting() -> void:
	# main.tscn's authored Environment, rebuilt here (instancing main would pull in every gameplay
	# script, so a broken one elsewhere would take this harness down with it).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.volumetric_fog_length = 72.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.2
	var w := WorldEnvironment.new()
	w.name = "WorldEnvironment"
	w.environment = env
	add_child(w)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.4
	sun.directional_shadow_max_distance = 55.0
	sun.rotation = Vector3(-0.541, -2.142, 0.0)
	add_child(sun)
	var atmo := LEGACY_ATMO.new()
	atmo.name = "Atmosphere"
	atmo.set(&"sun", sun)
	add_child(atmo)


func _build_arena() -> void:
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.3, 0.27)
	fm.roughness = 0.9
	floor_mi.material_override = fm
	add_child(floor_mi)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.55, 0.52, 0.47)
	stone.roughness = 0.85
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 10:
		var a := TAU * float(i) / 10.0
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.6
		cyl.bottom_radius = 0.75
		cyl.height = rng.randf_range(2.5, 6.0)
		pillar.mesh = cyl
		pillar.material_override = stone
		pillar.position = Vector3(cos(a) * 9.0, cyl.height * 0.5, sin(a) * 7.0)
		add_child(pillar)
	for i in 30:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randf_range(0.4, 1.6), rng.randf_range(0.3, 1.0), rng.randf_range(0.4, 1.6))
		box.mesh = bm
		box.material_override = stone
		box.position = Vector3(rng.randf_range(-20, 20), bm.size.y * 0.5, rng.randf_range(-15, 15))
		box.rotation.y = rng.randf() * TAU
		add_child(box)
	for x: float in [-4.0, 4.0]:
		var l := HellfireLight.new()
		l.base_energy = 3.0
		l.omni_range = 6.0
		l.position = Vector3(x, 1.4, -3.0)
		add_child(l)
		var bowl := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		bowl.mesh = sm
		var em := StandardMaterial3D.new()
		em.emission_enabled = true
		em.emission = Color(1.0, 0.4, 0.1)
		em.emission_energy_multiplier = 3.0
		bowl.material_override = em
		bowl.position = Vector3(x, 1.0, -3.0)
		add_child(bowl)
