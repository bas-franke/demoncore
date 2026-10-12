class_name AtmoRig
extends Node3D
## In-scene half of the Atmosphere autoload (added by it as "AtmosphereRig" under the current scene,
## so everything is freed with the scene). Owns the nodes a preset needs beyond the scene's own
## WorldEnvironment / Sun / post pass:
##   - weather layers (AtmoLayers: ash, embers, feathers, snow, rain + splash, holy rays, cloud wisps),
##     built lazily and kept centred on the player
##   - the moon (second DirectionalLight3D, no shadows)
##   - hellglow: the demon's own flickering hellfire light, following the player
##   - corruption gloom: a negative OmniLight3D (and, at High, a dark FogVolume) that darkens the area
##     around the player as the gloom rises
##   - boss judgement light: a SpotLight3D from above that tracks the boss (crimson when enraged)
##   - lightning (AtmoLightning); screen FX (AtmoScreenFX: corruption vignette, holy bloom, flashes);
##     heat haze (AtmoHeat); Basecamp Hell's extra dressing (AtmoHubDressing, hub scenes only)
##   - fallbacks when the scene has none: WorldEnvironment, Sun, post-process pass
## Driven entirely by Atmosphere (apply_state / set_quality / set_gloom / set_boss); no game logic.

const LIGHTNING := preload("res://scenes/world/atmo/atmo_lightning.gd")

## Multiplier on the layer counts per quality tier (Low, Medium, High, Ultra), on top of
## Settings.particle_density.
const TIER_AMOUNT := [0.6, 0.85, 1.0, 1.0]
## Layers that need at least this tier.
const MIN_TIER := {&"wisps": 1, &"splash": 1}
## Negative-light energy at gloom 1 (it subtracts from every light in range, sun included).
const GLOOM_ENERGY := 0.8
## Extra gloom energy per unit of sun energy (so ~half the sunlight is eaten at gloom 1).
const GLOOM_SUN_SHARE := 0.7
## Hellglow energy multiplier over the preset's fx.hellglow_energy.
const HELLGLOW_GAIN := 1.6

var lightning: AtmoLightning
var moon: DirectionalLight3D

var _layers := {}  # StringName -> GPUParticles3D
var _quality := 2
var _density := 1.0
var _state := {}
var _gust := 0.0
var _time := 0.0
var _wind := Vector2(0.45, 0.18)

var _hellglow: OmniLight3D
var _glow_energy := 0.0
var _gloom_light: OmniLight3D
var _gloom_fog: FogVolume
var _gloom_fog_mat: FogMaterial
var _gloom := 0.0

var _boss: Node3D
var _boss_light: SpotLight3D
var _boss_w := 0.0
var _boss_enraged := false

var _screen: AtmoScreenFX
var _heat: AtmoHeat
var _hub: Node3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_energy = 0.0
	moon.visible = false
	moon.light_volumetric_fog_energy = 0.6
	add_child(moon)

	_hellglow = OmniLight3D.new()
	_hellglow.name = "Hellglow"
	_hellglow.top_level = true
	_hellglow.omni_range = 6.0
	_hellglow.omni_attenuation = 1.6
	_hellglow.light_specular = 0.3
	_hellglow.visible = false
	add_child(_hellglow)

	_gloom_light = OmniLight3D.new()
	_gloom_light.name = "Gloom"
	_gloom_light.top_level = true
	_gloom_light.light_negative = true
	_gloom_light.light_specular = 0.0
	_gloom_light.omni_attenuation = 0.0  # flat disk; the range window gives the soft edge
	_gloom_light.visible = false
	add_child(_gloom_light)

	_gloom_fog = FogVolume.new()
	_gloom_fog.name = "GloomFog"
	_gloom_fog.top_level = true
	_gloom_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	_gloom_fog_mat = FogMaterial.new()
	_gloom_fog_mat.density = 0.0
	_gloom_fog_mat.edge_fade = 1.0
	_gloom_fog.material = _gloom_fog_mat
	_gloom_fog.visible = false
	add_child(_gloom_fog)

	_boss_light = SpotLight3D.new()
	_boss_light.name = "JudgementLight"
	_boss_light.top_level = true
	_boss_light.spot_range = 26.0
	_boss_light.spot_angle = 16.0
	_boss_light.spot_angle_attenuation = 0.6
	_boss_light.light_color = Color(1.0, 0.93, 0.78)
	_boss_light.light_volumetric_fog_energy = 2.0
	_boss_light.visible = false
	add_child(_boss_light)

	lightning = LIGHTNING.new()
	lightning.name = "Lightning"
	add_child(lightning)

	_screen = AtmoScreenFX.new()
	_screen.name = "ScreenFX"
	add_child(_screen)
	_heat = AtmoHeat.new()
	_heat.name = "Heat"
	add_child(_heat)
	# Basecamp Hell gets its extra dressing (lava bounce, warm pools, heat haze over the lava).
	if get_tree().get_first_node_in_group(&"basecamp"):
		_hub = AtmoHubDressing.new()
		_hub.name = "HubDressing"
		add_child(_hub)


func _process(delta: float) -> void:
	_time += delta
	var focus := focus_point()
	lightning.focus = focus
	_update_gusts()
	_follow_layers(focus)
	_update_hellglow(focus)
	_update_gloom(focus)
	_update_boss_light(delta)


# ---------------------------------------------------------------- driven by Atmosphere

## Quality tier (Atmosphere.Quality) and Settings.particle_density: resizes built layers.
func set_quality(tier: int, density: float) -> void:
	var changed := tier != _quality or not is_equal_approx(density, _density)
	_quality = tier
	_density = density
	lightning.quality = tier
	_screen.quality = tier
	_heat.quality = tier
	if _hub and _hub.has_method(&"set_quality"):
		_hub.call(&"set_quality", tier)
	if changed:
		for kind: StringName in _layers:
			var p: GPUParticles3D = _layers[kind]
			var n := _amount_for(kind)
			if n <= 0:
				p.emitting = false
				p.visible = false
			elif p.amount != n:
				p.amount = n
	if not _state.is_empty():
		apply_state(_state)


## Applies one (blended) flat preset state: layer intensities and colours, moon, lightning, glow.
func apply_state(s: Dictionary) -> void:
	_state = s
	_wind = s.get("weather.wind", _wind)
	var sun_down := _sun_down()
	_set_layer(&"ash", s["weather.ash"])
	_set_layer(&"embers", s["weather.embers"])
	_set_layer(&"feathers", s["weather.feathers"])
	_set_layer(&"snow", s["weather.snow"])
	_set_layer(&"rain", s["weather.rain"])
	_set_layer(&"splash", s["weather.rain"])
	_set_layer(&"rays", minf(float(s["weather.rays"]), 1.0))
	_set_layer(&"wisps", s["weather.wisps"])
	_mat_param(&"ash", &"tint", s["weather.ash_color"])
	_mat_param(&"embers", &"tint", s["weather.ember_color"])
	_mat_param(&"feathers", &"color", s["weather.feather_color"])
	_mat_param(&"snow", &"color", s["weather.snow_color"])
	_mat_param(&"wisps", &"color", s["weather.wisp_color"])
	_mat_param(&"rays", &"color", s["weather.ray_color"])
	_mat_param(&"rays", &"intensity", 0.3 * maxf(float(s["weather.rays"]), 1.0))
	_mat_param(&"rays", &"sun_down", sun_down)
	_mat_param(&"rain", &"base_color", s["weather.rain_color"])
	_mat_param(&"rain", &"shaft_color", s["weather.ray_color"])
	_mat_param(&"rain", &"sun_down", sun_down)
	_mat_param(&"splash", &"color", (s["weather.rain_color"] as Color).lightened(0.15))
	# Moon
	var me: float = s["moon.energy"]
	moon.visible = me > 0.001
	moon.light_energy = me
	moon.light_color = s["moon.color"]
	moon.rotation = Vector3(deg_to_rad(s["moon.pitch"]), deg_to_rad(s["moon.yaw"]), 0.0)
	# Lightning
	lightning.rate = s["weather.lightning"]
	lightning.color = s["weather.lightning_color"]
	# Hellglow
	_glow_energy = s["fx.hellglow_energy"]
	_hellglow.light_color = s["fx.hellglow_color"]
	_hellglow.omni_range = s["fx.hellglow_range"]
	# A negative light subtracts its colour: subtract the complement of the gloom colour so what is
	# left over leans toward it (dark violet-crimson by default).
	var gc: Color = s["fx.gloom_color"]
	_gloom_light.light_color = Color(1.0 - gc.r * 3.0, 1.0 - gc.g * 3.0, 1.0 - gc.b * 3.0).clamp()
	_gloom_fog_mat.albedo = gc


## Gloom (corruption darkness) around the player, 0..1.5.
func set_gloom(g: float) -> void:
	_gloom = g
	_screen.set_corruption(g, _state.get("fx.gloom_color", Color(0.09, 0.02, 0.06)))


## The boss to light (null = none) and whether it is enraged.
func set_boss(boss: Node3D, enraged: bool) -> void:
	_boss = boss
	_boss_enraged = enraged


## Full-screen additive flash (`strength` ~0.1..0.6), fading over ~1/decay seconds.
func flash(color: Color, strength: float, decay: float = 4.0) -> void:
	_screen.flash(color, strength * flash_scale(self), decay)


## One-shot heat shimmer (see AtmoHeat; off on Low quality).
func heat_burst(pos: Vector3, radius: float, duration: float, strength: float = 1.0) -> void:
	_heat.burst(pos, radius, duration, strength)


## Holy chromatic bloom around a boss telegraph (screen UV, intensity 0..1).
func set_holy_bloom(center: Vector2, intensity: float) -> void:
	_screen.set_holy_bloom(center, intensity)


## Where weather follows: the player, else the first Node3D in group &"atmo_focus" (hub avatars,
## cutscene actors), else the camera's ground point.
func focus_point() -> Vector3:
	var pl := find_player(self)
	if pl:
		return pl.get_global_transform_interpolated().origin
	var f := get_tree().get_first_node_in_group(&"atmo_focus") as Node3D
	if f:
		return f.get_global_transform_interpolated().origin
	var cam := get_viewport().get_camera_3d()
	if cam:
		var o := cam.global_position
		var d := -cam.global_transform.basis.z
		if d.y < -0.05:
			return o + d * (o.y / -d.y)
		return Vector3(o.x, 0.0, o.z)
	return Vector3.ZERO


## Game.player if it is alive in the tree (looked up by path, so a broken Game script never stops
## the atmosphere from compiling).
static func find_player(from: Node) -> Node3D:
	var game := from.get_node_or_null(^"/root/Game")
	var pl: Variant = game.get(&"player") if game else null
	# QA: is_instance_valid first; `is` on a freed player (after a run ends) is a script error.
	if is_instance_valid(pl) and pl is Node3D and (pl as Node3D).is_inside_tree():
		return pl
	return null


## 1, or 0.2 when the player asked for fewer flashes (Settings.reduce_flashes, accessibility).
static func flash_scale(from: Node) -> float:
	var st := from.get_node_or_null(^"/root/Settings")
	return 0.2 if st and st.get(&"reduce_flashes") == true else 1.0


# ---------------------------------------------------------------- internals

func _amount_for(kind: StringName) -> int:
	if _quality < int(MIN_TIER.get(kind, 0)):
		return 0
	var mult: float = TIER_AMOUNT[clampi(_quality, 0, 3)]
	var n := roundi(AtmoLayers.base_amount(kind) * _density * mult)
	if kind == &"rays" or kind == &"wisps":
		n = maxi(n, 3) if _density > 0.0 else 0  # few, big sprites: keep a minimum
	return n


func _set_layer(kind: StringName, intensity: float) -> void:
	var on := intensity > 0.004
	var p: GPUParticles3D = _layers.get(kind)
	if p == null:
		if not on:
			return
		var n := _amount_for(kind)
		if n <= 0:
			return
		p = AtmoLayers.build(kind, n)
		add_child(p)
		p.global_position = focus_point() + AtmoLayers.offset(kind)
		_layers[kind] = p
	p.amount_ratio = clampf(intensity, 0.0, 1.0)
	var can := _amount_for(kind) > 0
	p.visible = can
	if p.emitting != (on and can):
		p.emitting = on and can


func _mat_param(kind: StringName, param: StringName, value: Variant) -> void:
	var p: GPUParticles3D = _layers.get(kind)
	if p:
		var m := AtmoLayers.material_of(p)
		if m:
			m.set_shader_parameter(param, value)


func _sun_down() -> Vector3:
	var pitch := deg_to_rad(float(_state.get("sun.pitch", -31.0)))
	var yaw := deg_to_rad(float(_state.get("sun.yaw", -122.7)))
	return -Basis.from_euler(Vector3(pitch, yaw, 0.0)).z.normalized()


## Wind gusts: a slow lumpy noise scaled by weather.gust; pushes ash, snow, feathers, rain, wisps.
func _update_gusts() -> void:
	var strength: float = _state.get("weather.gust", 0.0)
	var n := 0.5 + 0.5 * sin(_time * 0.31) * sin(_time * 0.83 + 1.7)
	n = n * n * (0.75 + 0.25 * sin(_time * 3.1))
	_gust = strength * n
	var w := Vector3(_wind.x, 0.0, _wind.y) * (1.0 + 4.0 * _gust)
	for kind: StringName in [&"ash", &"snow", &"feathers"]:
		var p: GPUParticles3D = _layers.get(kind)
		if p and p.emitting:
			var pm := p.process_material as ParticleProcessMaterial
			var base_y := -0.32 if kind == &"ash" else (-0.05 if kind == &"feathers" else 0.0)
			pm.gravity = Vector3(w.x * 0.6, base_y, w.z * 0.6)
	var rain: GPUParticles3D = _layers.get(&"rain")
	if rain and rain.emitting:
		var dir := Vector3(0.08 + 0.35 * _gust + _wind.x * 0.05, -1.0, 0.04 + 0.12 * _gust + _wind.y * 0.05).normalized()
		(rain.process_material as ParticleProcessMaterial).direction = dir
		_mat_param(&"rain", &"fall_dir", dir)
	var wisps: GPUParticles3D = _layers.get(&"wisps")
	if wisps and wisps.emitting and _wind.length() > 0.01:
		var wd := Vector3(_wind.x, 0.0, _wind.y).normalized()
		(wisps.process_material as ParticleProcessMaterial).direction = wd


func _follow_layers(focus: Vector3) -> void:
	for kind: StringName in _layers:
		var p: GPUParticles3D = _layers[kind]
		if not p.emitting:
			continue
		var at := focus + AtmoLayers.offset(kind)
		if kind == &"rain":
			# Emit up-wind so the slanted streaks land around the player.
			var dir := (p.process_material as ParticleProcessMaterial).direction
			at = focus + Vector3(0.0, 0.0, 2.0) - dir * (13.0 / maxf(-dir.y, 0.2))
		p.global_position = at


func _update_hellglow(focus: Vector3) -> void:
	var e := _glow_energy
	_hellglow.visible = e > 0.01
	if not _hellglow.visible:
		return
	var strength := 1.0
	var atmo := get_node_or_null(^"/root/Atmosphere")
	if atmo:
		strength = atmo.flicker_strength()
	_hellglow.global_position = focus + Vector3(0.0, 1.7, 0.0)
	_hellglow.light_energy = HELLGLOW_GAIN * e * HellfireLight.flicker_at(_time * 1.1, HellfireLight.Style.FIRE, strength)


func _update_gloom(focus: Vector3) -> void:
	var g := _gloom
	var radius: float = _state.get("fx.gloom_radius", 9.0)
	_gloom_light.visible = g > 0.01
	if _gloom_light.visible:
		# Negative light: subtracts from everything in range; high above the player so it reads as a
		# soft pool of darkness rather than a hot spot. Slow breathing keeps it alive.
		# A negative light only removes what lights add, so it must scale with the sun to read on
		# bright maps as well as dark ones.
		var sun_e: float = _state.get("sun.energy", 2.0)
		_gloom_light.global_position = focus + Vector3(0.0, 3.0, 0.0)
		_gloom_light.omni_range = radius * (1.0 + 0.15 * g)
		_gloom_light.light_energy = g * (GLOOM_ENERGY + sun_e * GLOOM_SUN_SHARE) * (0.85 + 0.15 * sin(_time * 0.9))
	# Dark fog around the player: only when volumetric fog is actually on (High+ with volumetrics).
	var settings := get_node_or_null(^"/root/Settings")
	var fog_on := g > 0.01 and _quality >= 2 and settings != null and bool(settings.get(&"volumetrics"))
	_gloom_fog.visible = fog_on
	if fog_on:
		_gloom_fog.global_position = focus + Vector3(0.0, 0.6, 0.0)
		_gloom_fog.size = Vector3(radius * 2.2, 3.0, radius * 2.2)
		_gloom_fog_mat.density = 0.35 * g


func _update_boss_light(delta: float) -> void:
	var has_boss := is_instance_valid(_boss) and _boss.is_inside_tree()
	_boss_w = move_toward(_boss_w, 1.0 if has_boss else 0.0, delta * 0.6)
	_boss_light.visible = _boss_w > 0.001 and has_boss
	if not _boss_light.visible:
		return
	var bp := _boss.global_position
	_boss_light.global_position = bp + Vector3(1.5, 20.0, 3.0)
	_boss_light.look_at(bp, Vector3.FORWARD)
	var target := Color(1.0, 0.93, 0.78)
	var e := 3.5
	if _boss_enraged:
		target = Color(1.0, 0.32, 0.18)
		e = 4.5 + 1.5 * sin(_time * 5.0)
	_boss_light.light_color = _boss_light.light_color.lerp(target, minf(delta * 2.0, 1.0))
	_boss_light.light_energy = e * _boss_w
	_boss_light.shadow_enabled = _quality >= 2
