extends Node3D
## Spatial ambience for a run (node "Ambience" under Main; Sfx adds one automatically if missing).
## All sounds are rendered by Sfx on its worker thread; this node only mixes them.
##
## Beds (looping, "Ambience" bus):
##   - low wind with gusts (level and pitch drift on a slow noise curve)
##   - distant choir drone that swells with the number of angels alive (and during a boss)
##   - ash-storm whooshes: a slow storm cycle, stronger in the ash-waste biome
##   - fire crackle: AudioStreamPlayer3Ds parked on the FIRE_VOICES nearest braziers
##     (group &"braziers" if anyone adds one, else non-pulsing OmniLight3Ds under Main/Decor)
##   - a far-off bell now and then, from a random direction
## Positional one-shots: enemy deaths (Game.enemy_died) -> Sfx.play_at(&"angel_death", pos).
## Footsteps: heavy demon steps in rhythm with Game.player.velocity; the surface (stone, grass,
## snow, wood, water, ash) comes from scripts/audio/surface_probe.gd, else the decor biome.

const FIRE_VOICES := 3
const FIRE_RANGE := 26.0
const FIRE_DB := -4.0
const WIND_DB := -15.0
const CHOIR_MIN_DB := -30.0
const CHOIR_MAX_DB := -9.0
const STORM_MIN_DB := -36.0
const STORM_MAX_DB := -11.0
const BELL_DB := -9.0
## Angels alive for the choir to reach full swell.
const CHOIR_FULL_COUNT := 140.0
const CHOIR_START_COUNT := 12.0
## Steps per second at full move speed (heavy, deliberate gait) and its limits.
const STEPS_PER_SEC := 2.4
const MIN_STEP_SPEED := 0.6
const STEP_DB := -9.0
const DEATH_DB := -4.0
## Decor chunk size (decor.gd CHUNK).
const DECOR_CHUNK := 14.0
const SURFACE_PROBE := preload("res://scripts/audio/surface_probe.gd")

var _wind: AudioStreamPlayer
var _choir: AudioStreamPlayer
var _storm: AudioStreamPlayer
var _bell: AudioStreamPlayer3D
var _fires: Array[AudioStreamPlayer3D] = []
var _fire_want: Array = []  # Vector3 or null per fire voice
var _fire_gain := PackedFloat32Array()
var _started := false
var _fade_in := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _choir_level := 0.0
var _storm_level := 0.0
var _boss_active := false
var _fire_timer := 0.0
var _bell_timer := 12.0
var _step_phase := 0.0
var _step_left := false
var _decor: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"ambience")
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = randi()
	_wind = _bed()
	_choir = _bed()
	_storm = _bed()
	for i in FIRE_VOICES:
		var f := AudioStreamPlayer3D.new()
		f.bus = Sfx.AMB_BUS
		f.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		f.unit_size = 4.5
		f.max_distance = FIRE_RANGE + 6.0
		f.panning_strength = 0.9
		f.volume_db = -80.0
		f.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		f.top_level = true
		add_child(f)
		_fires.append(f)
		_fire_want.append(null)
		_fire_gain.append(0.0)
	_bell = AudioStreamPlayer3D.new()
	_bell.bus = Sfx.AMB_BUS
	_bell.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_bell.panning_strength = 0.7
	_bell.top_level = true
	add_child(_bell)
	Game.enemy_died.connect(_on_enemy_died)
	Game.boss_spawned.connect(_on_boss_spawned)
	Game.boss_died.connect(_on_boss_died)
	_decor = get_parent().get_node_or_null(^"Decor") if get_parent() else null


func _bed() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = Sfx.AMB_BUS
	p.volume_db = -80.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	_time += delta
	if not _started:
		_try_start()
		if not _started:
			return
	_fade_in = minf(_fade_in + delta / 4.0, 1.0)
	var fade_db := linear_to_db(maxf(_fade_in, 0.0001))
	var focus := _focus()

	# Wind: slow gust curve drives level and a touch of pitch.
	var gust := 0.5 + 0.5 * _noise.get_noise_1d(_time * 0.07)
	_wind.volume_db = WIND_DB + lerpf(-5.0, 3.0, gust) + fade_db
	_wind.pitch_scale = lerpf(0.94, 1.06, gust)

	# Choir: swells with the size of the host (and a boss).
	var angels := float(get_tree().get_node_count_in_group(&"enemies"))
	var want_choir := clampf((angels - CHOIR_START_COUNT) / (CHOIR_FULL_COUNT - CHOIR_START_COUNT), 0.0, 1.0)
	if _boss_active:
		want_choir = maxf(want_choir, 0.75)
	_choir_level = move_toward(_choir_level, want_choir, delta * (0.12 if want_choir > _choir_level else 0.06))
	_choir.volume_db = lerpf(CHOIR_MIN_DB, CHOIR_MAX_DB, sqrt(_choir_level)) + fade_db

	# Ash storm: a slow cycle that occasionally rises; the ash waste always has some.
	var cycle := clampf(_noise.get_noise_1d(_time * 0.018 + 100.0) * 1.6 + 0.1, 0.0, 1.0)
	if _surface_biome(focus) == 3:
		cycle = maxf(cycle, 0.55)
	_storm_level = move_toward(_storm_level, cycle, delta * 0.08)
	_storm.volume_db = lerpf(STORM_MIN_DB, STORM_MAX_DB, _storm_level) + fade_db
	_storm.pitch_scale = 0.95 + 0.1 * _storm_level

	# Braziers.
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = 0.5
		_assign_fires(focus)
	_update_fires(delta)

	# Distant bell.
	_bell_timer -= delta
	if _bell_timer <= 0.0:
		_bell_timer = randf_range(16.0, 34.0)
		_ring_bell(focus)

	if not get_tree().paused:
		_footsteps(delta)


func _try_start() -> void:
	if not Sfx.ambience_ready():
		return
	_started = true
	_start_bed(_wind, &"amb_wind")
	_start_bed(_choir, &"amb_choir")
	_start_bed(_storm, &"amb_storm")
	var fire := Sfx.get_stream(&"amb_fire")
	for f in _fires:
		f.stream = fire
	_bell.stream = Sfx.get_stream(&"bell_distant")


func _start_bed(p: AudioStreamPlayer, sound: StringName) -> void:
	var s := Sfx.get_stream(sound)
	p.stream = s
	p.play(randf() * s.get_length() * 0.9)


func _focus() -> Vector3:
	if is_instance_valid(Game.player):
		return Game.player.global_position
	return Vector3.ZERO


# ---------------------------------------------------------------- fire

func _assign_fires(focus: Vector3) -> void:
	var spots := _brazier_positions(focus)
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(focus) < b.distance_squared_to(focus))
	if spots.size() > FIRE_VOICES:
		spots.resize(FIRE_VOICES)
	# Keep voices that are already on a wanted spot; give the rest to free voices.
	var unassigned: Array[Vector3] = []
	var kept := []
	kept.resize(FIRE_VOICES)
	for s in spots:
		var found := -1
		for i in FIRE_VOICES:
			if kept[i] == null and _fire_want[i] != null and (_fire_want[i] as Vector3).distance_squared_to(s) < 0.01:
				found = i
				break
		if found == -1:
			unassigned.append(s)
		else:
			kept[found] = s
	for i in FIRE_VOICES:
		if kept[i] == null:
			kept[i] = unassigned.pop_front() if not unassigned.is_empty() else null
	_fire_want = kept


func _update_fires(delta: float) -> void:
	for i in FIRE_VOICES:
		var f := _fires[i]
		var want: Variant = _fire_want[i]
		var g := _fire_gain[i]
		var moved := want != null and f.global_position.distance_squared_to(want) > 0.01
		if want == null or moved:
			g = maxf(g - delta * 3.0, 0.0)
			if g <= 0.0:
				if moved:
					f.global_position = want
				if f.playing and want == null:
					f.stop()
		else:
			if not f.playing and f.stream:
				f.play(randf() * 5.0)
				f.pitch_scale = randf_range(0.9, 1.1)
			g = minf(g + delta * 1.2, 1.0)
		_fire_gain[i] = g
		f.volume_db = FIRE_DB + linear_to_db(maxf(g * _fade_in, 0.0001))


func _brazier_positions(focus: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var range_sq := FIRE_RANGE * FIRE_RANGE
	var grouped := get_tree().get_nodes_in_group(&"braziers")
	if not grouped.is_empty():
		for n in grouped:
			if n is Node3D and (n as Node3D).global_position.distance_squared_to(focus) < range_sq:
				out.append((n as Node3D).global_position)
		return out
	if _decor == null or not is_instance_valid(_decor):
		_decor = get_tree().current_scene.get_node_or_null(^"Decor") if get_tree().current_scene else null
		if _decor == null:
			return out
	# Decor: chunk -> prop root -> OmniLight3D. Brazier lights flicker (no `pulse` meta).
	for chunk in _decor.get_children():
		if not chunk is Node3D:
			continue
		var c := chunk as Node3D
		# Chunks are 14 units square; skip ones that can't be in range.
		var cc := c.global_position + Vector3(DECOR_CHUNK, 0.0, DECOR_CHUNK) * 0.5
		if Vector2(cc.x - focus.x, cc.z - focus.z).length() > FIRE_RANGE + 10.0:
			continue
		for prop in c.get_children():
			for l in prop.get_children():
				if l is OmniLight3D and not l.has_meta(&"pulse"):
					var p := (l as Node3D).global_position
					p.y = 1.2
					if p.distance_squared_to(focus) < range_sq:
						out.append(p)
	return out


# ---------------------------------------------------------------- bell

func _ring_bell(focus: Vector3) -> void:
	if _bell.stream == null:
		return
	var a := randf() * TAU
	_bell.global_position = focus + Vector3(cos(a), 0.4, sin(a)) * 40.0
	_bell.pitch_scale = [1.0, 0.891, 0.749][randi() % 3]
	_bell.volume_db = BELL_DB + linear_to_db(maxf(_fade_in, 0.0001))
	_bell.play()


# ---------------------------------------------------------------- one-shots

func _on_boss_spawned(_boss: Node3D) -> void:
	_boss_active = true


func _on_boss_died(_pos: Vector3) -> void:
	_boss_active = false


func _on_enemy_died(pos: Vector3, data: Resource) -> void:
	var size := 1.0
	if data and &"size" in data:
		size = float(data.get(&"size"))
	# Same frame as Enemy.die()'s 2D angel_death; Sfx's MIN_GAP makes this the one that plays.
	Sfx.play_at(&"angel_death", pos + Vector3(0.0, 0.6, 0.0), 0.12,
			DEATH_DB + clampf((size - 1.0) * 3.0, -2.0, 4.0))


func _footsteps(delta: float) -> void:
	var p := Game.player
	if not is_instance_valid(p) or p.is_dead:
		_step_phase = 0.0
		return
	var v := Vector2(p.velocity.x, p.velocity.z)
	var speed := v.length()
	if speed < MIN_STEP_SPEED:
		# Next step lands soon after starting to move again.
		_step_phase = 0.7
		return
	var ratio := clampf(speed / maxf(p.move_speed, 0.1), 0.45, 1.4)
	_step_phase += delta * STEPS_PER_SEC * ratio
	if _step_phase < 1.0:
		return
	_step_phase -= 1.0
	_step_left = not _step_left
	# Map / terrain surface first (snow, wood, water, ash...), then the sanctum's decor biome.
	var surface := SURFACE_PROBE.surface_at(get_tree(), p.global_position)
	var sound := StringName("step_" + String(surface)) if surface != &"" else &""
	if sound == &"":
		var biome := _surface_biome(p.global_position)
		sound = &"step_grass" if biome == 0 or biome == 2 else &"step_stone"
	var foot := p.global_position + p.global_basis.x * (0.35 if _step_left else -0.35)
	Sfx.play_at(sound, foot, 0.07, STEP_DB + lerpf(-3.0, 1.5, clampf(ratio, 0.0, 1.0))
			+ (0.0 if _step_left else -1.0))


## Decor biome under `pos` (0 graveyard, 1 ruins, 2 dead wood, 3 ash), 1 (stone) on the plaza.
func _surface_biome(pos: Vector3) -> int:
	if Vector2(pos.x, pos.z).length() < 8.5:
		return 1
	if _decor == null or not is_instance_valid(_decor) or not _decor.has_method(&"_theme"):
		return 1
	return int(_decor.call(&"_theme", Vector2i(floori(pos.x / DECOR_CHUNK), floori(pos.z / DECOR_CHUNK))))
