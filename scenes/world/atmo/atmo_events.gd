class_name AtmoEvents
extends Node
## Gameplay-driven atmosphere: child node "Events" of the Atmosphere autoload, ticked by it every
## frame while a preset is active (delta is 0 while the tree is paused).
##   - boss lighting: Game.boss_spawned -> "boss" overlay + heralding strike + judgement spotlight;
##     boss.is_enraged -> "boss_enraged" overlay, red flash; Game.boss_died -> flash, overlays clear
##   - corruption gloom: preset fx.gloom, deepened by Corruption.amount_at(player) and kill pulses
##   - cloud shadows: integrates the drift offset and feeds the atmo_cloud_* shader globals
##   - group &"hellfire_flicker": flickers any Light3D in it with the preset's fx.flicker
##   - heat haze: fire-tagged ability casts (Abilities.ability_cast) shimmer around the demon
##   - enemy shadows: off on Low / Medium (draw calls halve in big waves; docs/team/performance.md)
##   - per-boss tint: "boss_<id>" overlay (or the ProcBoss hazard_tint) on top of "boss"
##   - holy bloom: visible boss telegraphs (BossTelegraph / HolyTelegraph under a boss or a boss
##     hazard) drive a golden chromatic bloom centred on the strongest one (Medium quality and up)
## Everything is looked up by path, so a broken Game / Abilities script never breaks the lighting.

const BOSS_BLEND := 3.0
const GLOOM_PULSE_PER_KILL := 0.012
const GLOOM_PULSE_MAX := 0.3
const GLOOM_PULSE_DECAY := 0.05
const CLOUD_PARAMS: Array[StringName] = [&"atmo_cloud_strength", &"atmo_cloud_cover", &"atmo_cloud_offset"]
## Cloud drift speed (m/s) at weather.cloud_speed 1 (matches the old hard-coded CLOUD_WIND).
const CLOUD_DRIFT := 0.8
const TELEGRAPH_SCRIPTS: Array[String] = ["res://scenes/bosses/telegraph.gd", "res://scenes/enemies/holy_telegraph.gd"]
## Ability tags that count as hellfire for the heat haze.
const FIRE_TAGS: Array[String] = ["fire", "hellfire", "brimstone", "blood"]
const MAX_TELEGRAPHS := 96

## The Atmosphere autoload (set by it before adding this node).
var director: Node
var boss: Node3D
var boss_enraged := false
var gloom := 0.0

var _gloom_override := -1.0
var _gloom_pulse := 0.0
var _cloud_offset := Vector2.ZERO
var _has_cloud_globals := false
var _flicker_t := 0.0
var _telegraphs: Array[WeakRef] = []
var _bloom := 0.0
var _shadow_scan_left := 0.0


func _ready() -> void:
	# Declared in project.godot [shader_globals]; setting an undeclared one would spam errors.
	_has_cloud_globals = CLOUD_PARAMS.all(func(p: StringName) -> bool:
		return ProjectSettings.has_setting("shader_globals/" + String(p)))
	get_tree().node_added.connect(_on_tree_node_added)
	# Deferred: autoloads registered after Atmosphere are not in the tree yet during _ready.
	_connect_all.call_deferred()


func _connect_all() -> void:
	_connect(^"/root/Game", &"boss_spawned", _on_game_boss_spawned)
	_connect(^"/root/Game", &"boss_died", _on_game_boss_died)
	_connect(^"/root/Game", &"enemy_died", _on_game_enemy_died)
	_connect(^"/root/Abilities", &"ability_cast", _on_abilities_ability_cast)


## Forget everything scene-bound (called by the director on a scene change).
func reset() -> void:
	boss = null
	boss_enraged = false
	_gloom_override = -1.0
	_gloom_pulse = 0.0
	_telegraphs.clear()
	_bloom = 0.0


func tick(delta: float) -> void:
	var s: Dictionary = director.state
	var rig: AtmoRig = director.get_rig()
	_update_boss(rig)
	_update_gloom(delta, s, rig)
	update_clouds(delta, s)
	_update_group_flicker(delta)
	_update_bloom(delta, rig)
	_update_enemy_shadows(maxf(delta, 0.016))


func set_gloom(amount: float) -> void:
	_gloom_override = amount


func add_gloom(amount: float) -> void:
	_gloom_pulse = clampf(_gloom_pulse + amount, 0.0, 1.0)


## Cloud shadows: strength / cover from the state, drift integrated here so a wind change never
## makes the clouds jump (the shaders only see an offset). Also called without a preset (defaults).
func update_clouds(delta: float, s: Dictionary) -> void:
	if not _has_cloud_globals:
		return
	var w: Vector2 = s.get("weather.wind", Vector2(0.7, 0.4))
	var dir := w.normalized() if w.length() > 0.01 else Vector2(0.87, 0.5)
	_cloud_offset += dir * CLOUD_DRIFT * float(s.get("weather.cloud_speed", 1.0)) * delta
	# Restart the drift after ~14 h of play so shader float precision never degrades.
	if _cloud_offset.length() > 40000.0:
		_cloud_offset = Vector2.ZERO
	RenderingServer.global_shader_parameter_set(&"atmo_cloud_offset", _cloud_offset)
	RenderingServer.global_shader_parameter_set(&"atmo_cloud_strength", float(s.get("weather.clouds", 0.5)))
	RenderingServer.global_shader_parameter_set(&"atmo_cloud_cover", float(s.get("weather.cloud_cover", 0.5)))


# ---------------------------------------------------------------- boss

func _update_boss(rig: AtmoRig) -> void:
	if boss == null:
		return
	if not is_instance_valid(boss) or not boss.is_inside_tree():
		_end_boss(6.0)
		return
	var enraged := bool(boss.get(&"is_enraged")) if &"is_enraged" in boss else false
	if enraged and not boss_enraged:
		boss_enraged = true
		director.push_overlay(&"boss_enraged", "boss_enraged", 2.0)
		director.flash(Color(1.0, 0.25, 0.15), 0.3, 2.0)
		director.strike_lightning(boss.global_position, 0.1)
	if rig:
		rig.set_boss(boss, boss_enraged)


func _end_boss(blend: float) -> void:
	boss = null
	boss_enraged = false
	var rig: AtmoRig = director.get_rig()
	if rig:
		rig.set_boss(null, false)
	director.pop_overlay(&"boss_enraged", blend)
	director.pop_overlay(&"boss_tint", blend)
	director.pop_overlay(&"boss", blend)


func _on_game_boss_spawned(b: Node3D) -> void:
	if director.get_preset() == "":
		return
	boss = b
	boss_enraged = false
	director.push_overlay(&"boss", "boss", BOSS_BLEND)
	_push_boss_tint(b)
	# Herald the boss: a close strike right where it descends.
	get_tree().create_timer(0.5, false).timeout.connect(func() -> void:
		if is_instance_valid(b) and b.is_inside_tree():
			director.strike_lightning(b.global_position * Vector3(1, 0, 1), 0.05))


func _on_game_boss_died(_pos: Vector3) -> void:
	if boss == null:
		return
	director.flash(Color(1.0, 0.9, 0.7), 0.45, 1.2)
	var rig: AtmoRig = director.get_rig()
	if rig:
		rig.set_boss(null, false)
	boss = null
	boss_enraged = false
	# Let the death land before the sky clears.
	get_tree().create_timer(2.5, false).timeout.connect(func() -> void:
		if boss == null:
			_end_boss(6.0))


## Per-boss colour: presets.json overlay "boss_<id>" (id = the boss EnemyData file name, e.g.
## boss_war_chariot), else a light tint from a ProcBoss's cfg.hazard_tint, else nothing.
func _push_boss_tint(b: Node3D) -> void:
	var data: Variant = b.get(&"data") if &"data" in b else null
	var id := (data as Resource).resource_path.get_file().get_basename() if data is Resource else ""
	if id != "" and director.has_overlay_def("boss_" + id):
		director.push_overlay(&"boss_tint", "boss_" + id, BOSS_BLEND)
		return
	var cfg: Variant = b.get(&"cfg") if &"cfg" in b else null
	var tint: Variant = (cfg as Dictionary).get("hazard_tint") if cfg is Dictionary else null
	if tint is Color:
		director.push_overlay(&"boss_tint", {
			"grade.highlight_tint~": [[tint.r * 1.1, tint.g * 1.1, tint.b * 1.1], 0.25],
			"weather.lightning_color": [tint.r, tint.g, tint.b],
			"weather.ray_color~": [[tint.r, tint.g, tint.b], 0.5],
		}, BOSS_BLEND)


# ---------------------------------------------------------------- enemy shadows

## Low / Medium quality: enemies (group &"enemies", bosses included) cast no shadows. Swept twice a
## second; each enemy is touched once per quality change (meta atmo_shadow_q), original casting
## modes are remembered per mesh so High restores exactly what the model asked for.
func _update_enemy_shadows(delta: float) -> void:
	_shadow_scan_left -= delta
	if _shadow_scan_left > 0.0:
		return
	_shadow_scan_left = 0.5
	var q: int = director.quality()
	var cast := q >= 2
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if int(e.get_meta(&"atmo_shadow_q", -1)) == q:
			continue
		e.set_meta(&"atmo_shadow_q", q)
		_set_shadows(e, cast)


static func _set_shadows(n: Node, cast: bool) -> void:
	var g := n as GeometryInstance3D
	if g:
		if not g.has_meta(&"atmo_cast"):
			g.set_meta(&"atmo_cast", g.cast_shadow)
		g.cast_shadow = g.get_meta(&"atmo_cast") if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_shadows(c, cast)


# ---------------------------------------------------------------- gloom, flicker

func _update_gloom(delta: float, s: Dictionary, rig: AtmoRig) -> void:
	_gloom_pulse = maxf(_gloom_pulse - GLOOM_PULSE_DECAY * delta, 0.0)
	var g: float
	if _gloom_override >= 0.0:
		g = _gloom_override
	else:
		g = float(s.get("fx.gloom", 0.0))
		# Blighted ground under the player (Corruption autoload, art-style) deepens the gloom.
		var crp := get_node_or_null(^"/root/Corruption")
		var pl := AtmoRig.find_player(self)
		if crp and crp.has_method(&"amount_at") and pl:
			g *= 0.6 + 0.6 * clampf(float(crp.amount_at(pl.global_position)), 0.0, 1.0)
		g += _gloom_pulse
	gloom = lerpf(gloom, clampf(g, 0.0, 1.5), minf(delta * 2.0, 1.0))
	if rig:
		rig.set_gloom(gloom)


func _on_game_enemy_died(_pos: Vector3, _data: Resource) -> void:
	_gloom_pulse = minf(_gloom_pulse + GLOOM_PULSE_PER_KILL, GLOOM_PULSE_MAX)


func _update_group_flicker(delta: float) -> void:
	_flicker_t += delta
	var strength: float = director.flicker_strength()
	for n in get_tree().get_nodes_in_group(&"hellfire_flicker"):
		var l := n as Light3D
		if l == null or l is HellfireLight:
			continue
		if not l.has_meta(&"atmo_base_energy"):
			l.set_meta(&"atmo_base_energy", l.light_energy)
			l.set_meta(&"atmo_phase", randf() * 100.0)
		l.light_energy = float(l.get_meta(&"atmo_base_energy")) * HellfireLight.flicker_at(
				_flicker_t + float(l.get_meta(&"atmo_phase")), HellfireLight.Style.FIRE, strength)


# ---------------------------------------------------------------- heat haze, holy bloom

func _on_abilities_ability_cast(id: StringName) -> void:
	var rig: AtmoRig = director.get_rig()
	var pl := AtmoRig.find_player(self)
	var ab := get_node_or_null(^"/root/Abilities")
	if rig == null or pl == null or ab == null:
		return
	var defs: Variant = ab.get(&"defs")
	var def: Variant = (defs as Dictionary).get(id) if defs is Dictionary else null
	var tags: Variant = def.get(&"tags") if def is Object else null
	if not tags is PackedStringArray:
		return
	for t: String in tags:
		if t in FIRE_TAGS:
			rig.heat_burst(pl.global_position, 3.4, 1.2, 1.0)
			return


func _on_tree_node_added(node: Node) -> void:
	if not node is MeshInstance3D:
		return
	var s: Script = node.get_script()
	if s == null or not s.resource_path in TELEGRAPH_SCRIPTS:
		return
	if _telegraphs.size() >= MAX_TELEGRAPHS:
		_telegraphs = _telegraphs.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
		if _telegraphs.size() >= MAX_TELEGRAPHS:
			return
	_telegraphs.append(weakref(node))


## The strongest visible boss telegraph drives the rig's holy bloom (screen-space, Medium+).
func _update_bloom(delta: float, rig: AtmoRig) -> void:
	if rig == null:
		return
	var target := 0.0
	var at := Vector2(0.5, 0.5)
	if boss != null and is_instance_valid(boss) and int(director.quality()) >= 1:
		var cam := get_viewport().get_camera_3d()
		var size := get_viewport().get_visible_rect().size
		for w in _telegraphs:
			var t := w.get_ref() as MeshInstance3D
			if t == null or not t.is_visible_in_tree() or not _is_boss_telegraph(t):
				continue
			var fill := 0.6
			var m := t.material_override as ShaderMaterial
			if m:
				var f: Variant = m.get_shader_parameter(&"fill")
				if f is float:
					fill = f
			var k := 0.35 + 0.65 * clampf(fill, 0.0, 1.0)
			if k > target and cam and not cam.is_position_behind(t.global_position):
				target = k
				at = cam.unproject_position(t.global_position) / size
	if target > 0.0 and _bloom <= 0.0:
		print_verbose("Atmosphere: holy bloom on a boss telegraph at ", at)
	_bloom = move_toward(_bloom, target, delta * (6.0 if target > _bloom else 2.0))
	rig.set_holy_bloom(at, _bloom)


## A telegraph belongs to a boss fight if a boss or a boss hazard owns it (cached per node).
func _is_boss_telegraph(t: Node) -> bool:
	if t.has_meta(&"atmo_boss_tg"):
		return t.get_meta(&"atmo_boss_tg")
	var n := t.get_parent()
	var yes := false
	for i in 6:
		if n == null:
			break
		if n.is_in_group(&"boss") or n.is_in_group(&"boss_hazards"):
			yes = true
			break
		n = n.get_parent()
	t.set_meta(&"atmo_boss_tg", yes)
	return yes


func _connect(path: NodePath, sig: StringName, cb: Callable) -> void:
	var n := get_node_or_null(path)
	if n and n.has_signal(sig):
		n.connect(sig, cb)
