extends Node
## Sound effects + music (autoload "Sfx"). Everything is synthesized procedurally at startup
## (on a worker thread, so the game never hitches) into mono 22050 Hz AudioStreamWAVs.
## Sound world: dark, cinematic, sacred-profane. Formant choirs, struck bells, low drums.
##
## API (stable):
##   Sfx.play(&"hit")                       # 2D, pitch-jittered one-shot
##   Sfx.play(&"smite", 0.15, -6.0)         # jitter, volume_db
##   Sfx.play_music(&"backyard") / Sfx.stop_music()
## Sounds: hit, impact, holy_hit, angel_death, choir, beam, smite, wingbeat, soul, gold, chalice,
##   heal, level_up, hurt, faint, death, cast, fire_bolt, cleave, chain, scythe, brimstone,
##   ui_click, ui_hover, ui_back, select, toast, toll, triumph, boss_intro, boss_roar,
##   boss_charge, boss_death, unmade.
## Old names still work as aliases (see ALIASES): pickup→soul, poof→angel_death, swipe→cleave,
##   hairball→fire_bolt, yarn/boomerang→scythe, catnip→brimstone, laser→beam, bark→smite,
##   squeak→holy_hit, spray→cast, vroom/whoosh→wingbeat, chomp→cleave, boing→impact,
##   ring→toll, cheer→triumph, boss_suck→boss_charge, game_over→unmade. Unknown names are ignored.
## Music tracks: &"menu" (mournful choir, low strings, distant bell) and &"backyard" (the battle
## track: low drums, ostinato strings, choir swells). play_music crossfades; the same track
## keeps playing.
## Buses (created at runtime if missing): "SFX" and "Music", both sending to Master, which gets
## a hard limiter; both get a cathedral reverb. Bus volumes follow Settings live.
## The main scene ("Main") automatically starts &"backyard"; the demon select starts &"menu".
##
## Positional audio:
##   Sfx.play_at(&"angel_death", world_pos)          # pooled AudioStreamPlayer3D on the SFX bus
##   Sfx.play_at(&"step_stone", pos, 0.06, -8.0)     # jitter, volume_db (same limits as play())
## play() and play_at() share voice limits and MIN_GAP, so a play_at() followed in the same
## frame by a play() of the same sound (e.g. Game.enemy_died -> Enemy.die()) plays only once.
## While a run is active Sfx keeps an AudioListener3D floating LISTENER_DIST above/behind the
## player along the camera axis (camera orientation), so screen-edge sounds pan and fade.
## Footsteps: &"step_stone", &"step_grass" (each picks one of three variants at random).
## Ambience (looping, for res://scenes/world/ambience.gd): Sfx.get_stream(&"amb_wind" /
##   &"amb_choir" / &"amb_fire" / &"amb_storm" / &"bell_distant") -> AudioStreamWAV or null
##   until the worker thread has rendered it. Sfx.ambience_ready() -> bool.
## The "Ambience" bus (reverb, follows Settings.sfx_volume, or Settings.ambience_volume if such
## a property exists) is created at runtime. Sfx adds an "Ambience" node to "Main" automatically
## if the scene does not already contain one.
##
## More sounds (scripts/audio/sfx_recipes.gd, see docs/team/sfx.md for the full list):
##   Elements: Sfx.play_element(&"fire" | &"blood" | &"shadow" | &"plague" | &"lightning" | &"necro",
##     &"cast" | &"hit", position = null, volume_db = 0.0)  -> plays &"<element>_<kind>"
##   hit_flesh, angel_shatter, holy_chime, dash, pickup_item, coin, shop_buy, shop_deny,
##   portal_open, portal_enter, unlock, ability_ready.
## Looping emitters: Sfx.play_loop(&"amb_portal", parent_node, volume_db) -> player (Node; 3D when
##   the parent is a Node3D). It starts once the stream is rendered; free it (or the parent) to stop.
##   Loops: amb_portal, amb_hellfire, amb_hell_choir, amb_fire, amb_wind, amb_choir, amb_storm.
## UI: Sfx.wire_button(button) gives any BaseButton hover + click sounds.
## Every play gets a little volume jitter (VOL_JITTER_DB) on top of the pitch jitter.
## Gameplay hooks (Game bus -> sounds) live in scripts/audio/sfx_hooks.gd (child node of Sfx).

const RECIPES := preload("res://scripts/audio/sfx_recipes.gd")
const HOOKS_SCRIPT := preload("res://scripts/audio/sfx_hooks.gd")
const WORLD := preload("res://scripts/audio/sfx_recipes_world.gd")
const REGISTRY := preload("res://scripts/audio/sfx_registry.gd")
const CACHE := preload("res://scripts/audio/sfx_cache.gd")
const SINS := preload("res://scripts/audio/sfx_recipes_sins.gd")
const SIGNATURE := preload("res://scripts/audio/sfx_recipes_signature.gd")
## Per-demon sound identity: DemonData.model_id -> {generic player sound -> replacement}.
## SfxHooks calls set_demon() when a run's Player appears; play()/play_at() then swap the names.
const DEMON_SOUNDS := {
	"nhazgul": {&"hurt": &"hurt_swarm", &"faint": &"death_swarm", &"dash": &"dash_swarm"},
	"iscariel": {&"hurt": &"hurt_turncoat", &"faint": &"death_turncoat", &"dash": &"dash_turncoat"},
}
## Looping sound a demon carries while it moves (SfxHooks adds a MoveLoop under the Player).
const DEMON_LOOPS := {"nhazgul": &"amb_fly_buzz"}
## Legacy music synthesis (only without MusicManager); see _render_track().
const LEGACY_MUSIC := preload("res://scripts/audio/sfx_legacy_music.gd")
const UI_BUS := &"UI"
## Sounds that play on the dry UI bus instead of SFX (menus, toasts, dialogue).
const UI_SOUNDS := [&"ui_click", &"ui_hover", &"ui_back", &"select", &"toast", &"shop_buy",
		&"shop_deny", &"unlock", &"blip_low", &"blip_mid", &"blip_high", &"blip_holy",
		&"blip_whisper"]
## Big moments duck the music: sound -> [duck dB, seconds] (MusicManager.duck).
const DUCK := {
	&"stinger_boss": [-9.0, 2.6], &"boss_intro": [-8.0, 4.0], &"boss_roar": [-6.0, 1.8],
	&"boss_death": [-9.0, 4.5], &"unmade": [-12.0, 4.0], &"level_up": [-5.0, 2.0],
	&"desecrate": [-6.0, 2.6], &"relic_corrupt": [-6.0, 2.6], &"portal_enter": [-5.0, 1.4],
	&"evolve": [-7.0, 3.0], &"synergy": [-4.0, 1.2], &"relic_epic": [-5.0, 2.4],
	&"relic_legendary": [-8.0, 3.2], &"triumph": [-6.0, 3.0], &"thunder": [-2.0, 1.5],
	&"last_stand": [-8.0, 2.4],
}
## Elite wind-up voices: louder, deeper and rarer than the rank and file.
const ELITE_VOICE_DB := 4.0
const ELITE_VOICE_PITCH := 0.84
const ELITE_VOICE_GAP := 2.5
## Every script whose code shapes a rendered sound: editing one invalidates the user:// cache.
const CACHE_SOURCES := ["res://autoload/sfx.gd", "res://scripts/audio/sfx_recipes.gd",
		"res://scripts/audio/sfx_recipes_world.gd", "res://scripts/audio/sfx_recipes_sins.gd",
		"res://scripts/audio/sfx_legacy_music.gd", "res://scripts/audio/sfx_recipes_signature.gd"]
## Bump by hand when recipes change in a build without .gd sources (exports hash this instead).
const RECIPE_VERSION := "3"
## Random volume cut per play, in dB (0..-VOL_JITTER_DB), so repeated sounds do not machine-gun.
const VOL_JITTER_DB := 1.5

const SR := 22050
const POOL_SIZE := 22
const POOL_3D_SIZE := 20
const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const AMB_BUS := &"Ambience"
const AMBIENCE_SCRIPT := "res://scenes/world/ambience.gd"
## Listener offset from the player along the camera's backward axis (camera is ~26 away).
const LISTENER_DIST := 9.0
## 3D attenuation tuned for the high camera: on-screen sounds sit 9..18 units from the listener.
const UNIT_SIZE_3D := 10.0
const MAX_DISTANCE_3D := 60.0
## Random variants: base name -> rendered streams. Voice limits use the base name.
const VARIANTS := {
	&"step_stone": [&"step_stone_a", &"step_stone_b", &"step_stone_c"],
	&"step_grass": [&"step_grass_a", &"step_grass_b", &"step_grass_c"],
}
const AMBIENCE_STREAMS := [&"amb_wind", &"amb_choir", &"amb_fire", &"amb_storm", &"bell_distant"]
const MUSIC_BASE_DB := -3.0
const MUSIC_FADE := 2.2
const MAIN_SCENE := "res://scenes/main.tscn"
const MENU_SCENES := ["res://scenes/menu/demon_select.tscn", "res://scenes/menu/cat_select.tscn"]
const MENU_NODE_NAMES := [&"DemonSelect", &"CatSelect"]

const ALIASES := {
	&"pickup": &"soul", &"poof": &"angel_death", &"swipe": &"cleave", &"hairball": &"fire_bolt",
	&"yarn": &"scythe", &"boomerang": &"scythe", &"catnip": &"brimstone", &"laser": &"beam",
	&"bark": &"smite", &"squeak": &"holy_hit", &"spray": &"cast", &"vroom": &"wingbeat",
	&"whoosh": &"wingbeat", &"chomp": &"cleave", &"boing": &"impact", &"ring": &"toll",
	&"cheer": &"triumph", &"boss_suck": &"boss_charge", &"game_over": &"unmade",
	&"death": &"faint", &"hellfire": &"brimstone", &"fire": &"brimstone", &"heal": &"chalice",
}

## Max simultaneous voices per sound (default DEFAULT_VOICES). Extra plays steal the oldest one.
const MAX_VOICES := {
	&"hit": 4, &"impact": 2, &"holy_hit": 3, &"angel_death": 3, &"soul": 3, &"gold": 2,
	&"chalice": 2, &"level_up": 1, &"hurt": 1, &"faint": 1, &"choir": 1, &"beam": 2, &"smite": 2,
	&"wingbeat": 2, &"cast": 2, &"fire_bolt": 3, &"cleave": 2, &"chain": 2, &"scythe": 2,
	&"brimstone": 2, &"ui_click": 2, &"ui_hover": 1, &"ui_back": 1, &"select": 1, &"toast": 2,
	&"toll": 1, &"triumph": 1, &"boss_intro": 1, &"boss_roar": 1, &"boss_charge": 1,
	&"boss_death": 1, &"unmade": 1, &"step_stone": 2, &"step_grass": 2,
}
const DEFAULT_VOICES := 3
## Minimum seconds between two plays of the same sound (default DEFAULT_GAP).
const MIN_GAP := {
	&"hit": 0.035, &"impact": 0.08, &"holy_hit": 0.04, &"angel_death": 0.04, &"soul": 0.03,
	&"hurt": 0.45, &"faint": 0.8, &"level_up": 0.4, &"choir": 0.5, &"ui_hover": 0.04,
	&"ui_click": 0.05, &"cleave": 0.06, &"scythe": 0.08, &"brimstone": 0.15, &"toast": 0.15,
	&"toll": 0.3, &"boss_intro": 1.0, &"boss_roar": 0.6, &"boss_charge": 0.4, &"boss_death": 1.0,
	&"unmade": 1.0, &"wingbeat": 0.06, &"beam": 0.06, &"chain": 0.05, &"step_stone": 0.12,
	&"step_grass": 0.12,
}
const DEFAULT_GAP := 0.02
## Soul combo: rapid pickups climb this minor-pentatonic ladder (semitones), kept narrow.
const COMBO_STEPS := [0, 3, 5, 7, 10, 12, 15]
const COMBO_WINDOW := 0.45

# Oscillator shapes.
const W_SINE := 0
const W_TRI := 1
const W_SAW := 2
const W_SOFTSQ := 3
const W_PULSE := 4
# Filter outputs.
const F_LOW := 0
const F_BAND := 1
const F_HIGH := 2
# Vowels for the choir (formant freq, gain, Q) x3.
const V_AH := 0
const V_OH := 1
const V_OO := 2
const V_EH := 3
const VOWELS := [
	[[700.0, 1.0, 8.0], [1150.0, 0.55, 10.0], [2650.0, 0.22, 12.0]],
	[[460.0, 1.0, 8.0], [820.0, 0.5, 10.0], [2800.0, 0.12, 12.0]],
	[[330.0, 1.0, 8.0], [720.0, 0.32, 10.0], [2500.0, 0.08, 12.0]],
	[[540.0, 1.0, 8.0], [1750.0, 0.45, 11.0], [2550.0, 0.25, 12.0]],
]
# Church bell partial ratios / gains / decay factors (hum, prime, tierce, quint, nominal...).
const BELL_RATIOS := [0.5, 1.0, 1.19, 1.5, 2.0, 2.52, 2.66, 3.01, 4.17]
const BELL_GAINS := [0.55, 1.0, 0.6, 0.3, 0.5, 0.22, 0.18, 0.12, 0.07]
const BELL_DECAYS := [1.0, 0.75, 0.55, 0.45, 0.4, 0.28, 0.25, 0.18, 0.12]

const TAB_SIZE := 4096
const PHASE_MASK := 0x0FFFFFFF  # 4096 << 16 fixed-point phase range
const WAV_OPTIONS := {
	"force/8_bit": false, "force/mono": false, "force/max_rate": false, "force/max_rate_hz": 44100,
	"edit/trim": false, "edit/normalize": false, "edit/loop_mode": 0, "edit/loop_begin": 0,
	"edit/loop_end": -1, "compress/mode": 0,
}

var _streams := {}  # StringName -> AudioStreamWAV (main thread only)
var _music_streams := {}  # StringName -> AudioStreamWAV (main thread only)
var _players: Array[AudioStreamPlayer] = []
var _player_names: Array[StringName] = []
var _player_starts := PackedFloat64Array()
var _last_play := {}  # StringName -> seconds
var _combo := 0
var _last_pickup := -10.0
# Lookup tables: the consts above merged with RECIPES' tables in _ready().
var _variants := {}  # StringName -> Array[StringName]
var _aliases := {}  # StringName -> StringName
var _max_voices := {}  # StringName -> int
var _min_gap := {}  # StringName -> float
var _play_counts := {}  # StringName -> int, sounds actually started (see get_play_counts)
var _last_elite_voice := -10.0
var _demon_remap := {}  # StringName -> StringName, from DEMON_SOUNDS (see set_demon)
var _ui_bus := -1
var _last_ui_vol := -1.0
## Enemy material / voice and speaker blip lookups (data/audio/enemy_audio.json).
var registry: RefCounted

var _music_players: Array[AudioStreamPlayer] = []
var _music_gain := PackedFloat32Array([0.0, 0.0])
var _music_tweens: Array[Tween] = [null, null]
var _music_idx := 0
var _current_track := &""
var _pending_track := &""  # guarded by _mutex

var _players3d: Array[AudioStreamPlayer3D] = []
var _player3d_names: Array[StringName] = []
var _player3d_starts := PackedFloat64Array()
var _listener: AudioListener3D

var _sfx_bus := -1
var _music_bus := -1
var _amb_bus := -1
var _last_sfx_vol := -1.0
var _last_music_vol := -1.0
var _last_amb_vol := -1.0

# Worker-thread generation.
var _mutex := Mutex.new()
var _gen_task := -1
var _incoming_sfx := {}  # guarded by _mutex
var _incoming_music := {}  # guarded by _mutex
var _rendered := {}  # worker thread only: every sfx stream published, saved to the cache at the end
## True once the sfx came from the user:// cache (debug / tests).
var loaded_from_cache := false
# Thread-only scratch state.
var _buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _sin_tab := PackedFloat32Array()
var _pad_tab := PackedFloat32Array()
var _saw_tab := PackedFloat32Array()
var _float_wav := 0  # 0 = untested, 1 = load_from_buffer float WAV works, -1 = fall back


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_variants = VARIANTS.merged(RECIPES.VARIANTS).merged(WORLD.VARIANTS).merged(SINS.VARIANTS)
	_aliases = ALIASES.merged(RECIPES.ALIASES).merged(WORLD.ALIASES).merged(SINS.ALIASES)
	_max_voices = MAX_VOICES.merged(RECIPES.MAX_VOICES).merged(WORLD.MAX_VOICES) \
			.merged(SINS.MAX_VOICES).merged(SIGNATURE.MAX_VOICES)
	_min_gap = MIN_GAP.merged(RECIPES.MIN_GAP).merged(WORLD.MIN_GAP).merged(SINS.MIN_GAP) \
			.merged(SIGNATURE.MIN_GAP)
	registry = REGISTRY.new()
	_setup_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)
		_player_names.append(&"")
		_player_starts.append(0.0)
	for i in POOL_3D_SIZE:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = SFX_BUS
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = UNIT_SIZE_3D
		p3.max_distance = MAX_DISTANCE_3D
		p3.max_db = 3.0
		p3.panning_strength = 0.8
		p3.attenuation_filter_cutoff_hz = 6000.0
		p3.attenuation_filter_db = -18.0
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p3)
		_players3d.append(p3)
		_player3d_names.append(&"")
		_player3d_starts.append(0.0)
	_listener = AudioListener3D.new()
	add_child(_listener)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = MUSIC_BUS
		m.volume_db = -80.0
		add_child(m)
		_music_players.append(m)
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)
	_check_current_scene.call_deferred()
	var hooks: Node = HOOKS_SCRIPT.new()
	hooks.name = &"SfxHooks"
	add_child(hooks)
	_gen_task = WorkerThreadPool.add_task(_generate, false, "Sfx synthesis")


func _exit_tree() -> void:
	if _gen_task != -1:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1


func _process(_delta: float) -> void:
	_apply_volumes()
	_update_listener()
	if _gen_task != -1:
		var done := WorkerThreadPool.is_task_completed(_gen_task)
		_mutex.lock()
		if not _incoming_sfx.is_empty():
			_streams.merge(_incoming_sfx, true)
			_incoming_sfx = {}
		if not _incoming_music.is_empty():
			_music_streams.merge(_incoming_music, true)
			_incoming_music = {}
		var want := _pending_track
		_mutex.unlock()
		if want != &"" and _music_streams.has(want):
			_set_pending(&"")
			_start_music(want)
		if done:
			WorkerThreadPool.wait_for_task_completion(_gen_task)
			_gen_task = -1


# ================================================================ public API

func play(sound: StringName, pitch_jitter: float = 0.08, volume_db: float = 0.0) -> void:
	sound = _aliases.get(sound, sound)
	sound = _demon_remap.get(sound, sound)
	var stream := _pick_stream(sound)
	if stream == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = _min_gap.get(sound, DEFAULT_GAP)
	if now - float(_last_play.get(sound, -10.0)) < gap:
		return
	_last_play[sound] = now

	var idx := _pick_voice(sound, false)
	if idx == -1:
		return

	var pitch := 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	if sound == &"soul":
		if now - _last_pickup < COMBO_WINDOW:
			_combo = mini(_combo + 1, COMBO_STEPS.size() - 1)
		else:
			_combo = 0
		_last_pickup = now
		pitch = (1.0 + randf_range(-0.01, 0.01)) * pow(2.0, float(COMBO_STEPS[_combo]) / 12.0)

	var player := _players[idx]
	player.stop()
	player.stream = stream
	player.bus = UI_BUS if UI_SOUNDS.has(sound) and _ui_bus >= 0 else SFX_BUS
	player.pitch_scale = maxf(pitch, 0.1)
	player.volume_db = volume_db - randf() * VOL_JITTER_DB
	player.play()
	_play_counts[sound] = int(_play_counts.get(sound, 0)) + 1
	_player_names[idx] = sound
	_player_starts[idx] = now
	_duck_for(sound)


## Positional one-shot at a world position (pooled AudioStreamPlayer3D, SFX bus). Shares voice
## limits and MIN_GAP with play(). Returns true if it played.
func play_at(sound: StringName, position: Vector3, pitch_jitter: float = 0.08,
		volume_db: float = 0.0) -> bool:
	sound = _aliases.get(sound, sound)
	sound = _demon_remap.get(sound, sound)
	var stream := _pick_stream(sound)
	if stream == null:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	var gap: float = _min_gap.get(sound, DEFAULT_GAP)
	if now - float(_last_play.get(sound, -10.0)) < gap:
		return false
	_last_play[sound] = now
	var idx := _pick_voice(sound, true)
	if idx == -1:
		return false
	var player := _players3d[idx]
	player.stop()
	player.stream = stream
	player.global_position = position
	player.pitch_scale = maxf(1.0 + randf_range(-pitch_jitter, pitch_jitter), 0.1)
	player.volume_db = volume_db - randf() * VOL_JITTER_DB
	player.play()
	_play_counts[sound] = int(_play_counts.get(sound, 0)) + 1
	_player3d_names[idx] = sound
	_player3d_starts[idx] = now
	_duck_for(sound)
	return true


## Ducks the music under a big sound (DUCK table) through MusicManager.duck, when both exist.
func _duck_for(sound: StringName) -> void:
	var d: Variant = DUCK.get(sound)
	if d == null:
		return
	var mm := get_node_or_null(^"/root/MusicManager")
	if mm and mm.has_method(&"duck"):
		mm.call(&"duck", float(d[0]), float(d[1]))


## A rendered stream by name (aliases resolved; a random variant for variant sets), e.g. the
## looping ambience beds. Null until ready.
func get_stream(sound: StringName) -> AudioStreamWAV:
	return _pick_stream(_aliases.get(sound, sound))


## Picks the playable demon's sound identity (DemonData.model_id, e.g. "nhazgul"); unknown ids
## and "" restore the generic hurt / faint / dash sounds.
func set_demon(model_id: String) -> void:
	_demon_remap = DEMON_SOUNDS.get(model_id, {})


## How many times each sound actually started since launch (debug / smoke tests).
func get_play_counts() -> Dictionary:
	return _play_counts.duplicate()


## True if `sound` (or its alias) is a known sound that has been rendered.
func has_sound(sound: StringName) -> bool:
	return get_stream(sound) != null


## Plays an element's &"cast" or &"hit" sound (&"fire", &"blood", &"shadow", &"plague",
## &"lightning", &"necro"; aliases such as &"poison" or &"shock" work too). Pass a Vector3
## `position` for a positional play, or null for 2D. Returns false for an unknown element.
func play_element(element: StringName, kind: StringName = &"cast", position: Variant = null,
		volume_db: float = 0.0, pitch_jitter: float = 0.08) -> bool:
	var e: StringName = RECIPES.ELEMENT_ALIASES.get(element,
			SINS.SCHOOL_ALIASES.get(element, element))
	if not RECIPES.ELEMENTS.has(e) and not SINS.SCHOOLS.has(e):
		return false
	var sound := StringName("%s_%s" % [e, kind])
	if position is Vector3:
		return play_at(sound, position, pitch_jitter, volume_db)
	play(sound, pitch_jitter, volume_db)
	return true


## Hit sound for a surface material (&"flesh", &"stone", &"glass", &"metal", &"holy") at `position`.
func play_material_hit(material: StringName, position: Vector3, volume_db: float = 0.0) -> bool:
	var snd: StringName = REGISTRY.HIT_SOUND.get(material, &"hit_flesh")
	return play_at(snd, position, 0.1, volume_db)


## Death sound for a surface material at `position`.
func play_material_death(material: StringName, position: Vector3, volume_db: float = 0.0) -> bool:
	var snd: StringName = REGISTRY.DEATH_SOUND.get(material, &"death_flesh")
	return play_at(snd, position, 0.08, volume_db)


## An enemy's wind-up voice (from the registry; silent if it has none). `data` is its EnemyData.
func play_enemy_voice(data: Resource, position: Vector3, volume_db: float = -6.0,
		elite: bool = false) -> bool:
	var v: StringName = registry.voice_of(data)
	if v == &"":
		return false
	if not elite:
		return play_at(v, position, 0.1, volume_db)
	# Elites: a shared, longer gap (rarer), louder and pitched down (bigger), and they bypass the
	# per-sound gap so the rank and file cannot starve them.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_elite_voice < ELITE_VOICE_GAP:
		return false
	var stream := _pick_stream(v)
	var idx := _pick_voice(v, true) if stream else -1
	if idx == -1:
		return false
	_last_elite_voice = now
	var player := _players3d[idx]
	player.stop()
	player.stream = stream
	player.global_position = position
	player.pitch_scale = ELITE_VOICE_PITCH * (1.0 + randf_range(-0.04, 0.04))
	player.volume_db = volume_db + ELITE_VOICE_DB
	player.play()
	_play_counts[v] = int(_play_counts.get(v, 0)) + 1
	_player3d_names[idx] = v
	_player3d_starts[idx] = now
	return true


## Relic pickup sound by rarity tier (0 common .. 4 legendary, matches Rarity's enum).
func play_relic(tier: int, volume_db: float = -2.0) -> void:
	play(StringName("relic_%s" % SINS.RARITIES[clampi(tier, 0, SINS.RARITIES.size() - 1)]), 0.02,
			volume_db)


## One dialogue blip in `speaker`'s voice (speaker id, e.g. "grimmaul"; "" = narrator).
func play_blip(speaker: String, volume_db: float = -12.0) -> void:
	var b: Array = registry.blip_of(speaker if speaker != "" else "narrator")
	var stream := _pick_stream(b[0])
	if stream == null:
		return
	# Blips bypass play(): their pitch is the speaker's identity, only lightly jittered.
	var idx := _pick_voice(b[0], false)
	if idx == -1:
		return
	var player := _players[idx]
	player.stop()
	player.stream = stream
	player.bus = UI_BUS if _ui_bus >= 0 else SFX_BUS
	player.pitch_scale = float(b[1]) * (1.0 + randf_range(-0.06, 0.06))
	player.volume_db = volume_db
	player.play()
	_player_names[idx] = b[0]
	_player_starts[idx] = Time.get_ticks_msec() / 1000.0
	_play_counts[b[0]] = int(_play_counts.get(b[0], 0)) + 1


## Starts a looping sound as a child of `parent` (AudioStreamPlayer3D when `parent` is a Node3D,
## else a plain AudioStreamPlayer) and returns the player. It waits for the stream to be
## rendered, starts at a random offset (so two emitters never phase), and stops when freed.
## `unit_size` sets how far it carries (3D only).
func play_loop(sound: StringName, parent: Node, volume_db: float = 0.0, bus: StringName = SFX_BUS,
		unit_size: float = 6.0) -> Node:
	var p: Node
	if parent is Node3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.unit_size = unit_size
		p3.max_distance = MAX_DISTANCE_3D
		p3.panning_strength = 0.8
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p3.volume_db = volume_db
		p3.bus = bus
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.volume_db = volume_db
		p2.bus = bus
		p = p2
	p.name = "Loop_%s" % sound
	parent.add_child(p)
	_start_loop_when_ready(p, sound)
	return p


## Gives a button hover (mouse or focus) and click sounds. Safe to call twice.
func wire_button(button: BaseButton, click: StringName = &"ui_click",
		hover: StringName = &"ui_hover") -> void:
	if button.has_meta(&"sfx_wired"):
		return
	button.set_meta(&"sfx_wired", true)
	var on_hover := func() -> void:
		if not button.disabled:
			play(hover, 0.03, -4.0)
	button.mouse_entered.connect(on_hover)
	button.focus_entered.connect(on_hover)
	button.pressed.connect(play.bind(click, 0.03, 0.0))


func _start_loop_when_ready(p: Node, sound: StringName) -> void:
	while get_stream(sound) == null:
		await get_tree().process_frame
		if not is_instance_valid(p):
			return
	if not is_instance_valid(p) or not p.is_inside_tree():
		return
	var stream := get_stream(sound)
	p.set(&"stream", stream)
	p.call(&"play", randf() * stream.get_length())


## True once every ambience stream has been rendered.
func ambience_ready() -> bool:
	for s: StringName in AMBIENCE_STREAMS:
		if not _streams.has(s):
			return false
	return true


func _pick_stream(sound: StringName) -> AudioStreamWAV:
	if _variants.has(sound):
		var list: Array = _variants[sound]
		var s: AudioStreamWAV = _streams.get(list[randi() % list.size()])
		if s:
			return s
		for v: StringName in list:
			if _streams.has(v):
				return _streams[v]
		return null
	return _streams.get(sound)


## Picks a voice index in the 2D (`spatial` false) or 3D pool. Voice limits count both pools;
## when the limit is hit the oldest voice of the same sound is stolen (in either pool).
func _pick_voice(sound: StringName, spatial: bool) -> int:
	var max_voices: int = _max_voices.get(sound, DEFAULT_VOICES)
	var count := 0
	var oldest_t := INF
	var oldest_pool := -1  # 0 = 2D, 1 = 3D
	var oldest_i := -1
	for i in POOL_SIZE:
		if _players[i].playing and _player_names[i] == sound:
			count += 1
			if _player_starts[i] < oldest_t:
				oldest_t = _player_starts[i]
				oldest_pool = 0
				oldest_i = i
	for i in POOL_3D_SIZE:
		if _players3d[i].playing and _player3d_names[i] == sound:
			count += 1
			if _player3d_starts[i] < oldest_t:
				oldest_t = _player3d_starts[i]
				oldest_pool = 1
				oldest_i = i
	var own := 1 if spatial else 0
	if count >= max_voices and oldest_i != -1:
		if oldest_pool == own:
			return oldest_i
		if oldest_pool == 0:
			_players[oldest_i].stop()
		else:
			_players3d[oldest_i].stop()
	# A free voice in our own pool, else the oldest one.
	var size := POOL_3D_SIZE if spatial else POOL_SIZE
	var oldest_any := -1
	var oldest_any_t := INF
	for i in size:
		var playing: bool = _players3d[i].playing if spatial else _players[i].playing
		if not playing:
			return i
		var st: float = _player3d_starts[i] if spatial else _player_starts[i]
		if st < oldest_any_t:
			oldest_any_t = st
			oldest_any = i
	return oldest_any


## Keeps the 3D listener above/behind the player along the camera axis during a run.
func _update_listener() -> void:
	var cam := get_viewport().get_camera_3d()
	var active := cam != null and is_instance_valid(Game.player) and Game.player.is_inside_tree()
	if not active:
		if _listener.is_current():
			_listener.clear_current()
		return
	var b := cam.global_basis.orthonormalized()
	_listener.global_transform = Transform3D(b, Game.player.global_position + Vector3(0.0, 1.0, 0.0)
			+ b.z * LISTENER_DIST)
	if not _listener.is_current():
		_listener.make_current()


## Music lives in the MusicManager autoload (docs/team/music.md); these three forward to it and
## only fall back to the built-in two-track player when MusicManager is not registered.
func play_music(track: StringName) -> void:
	var mm := get_node_or_null(^"/root/MusicManager")
	if mm:
		mm.call(&"play", track)
		return
	if track == _current_track:
		_set_pending(&"")
		return
	if not _music_streams.has(track):
		_set_pending(track)  # starts as soon as the worker thread finishes it
		return
	_set_pending(&"")
	_start_music(track)


func stop_music() -> void:
	var mm := get_node_or_null(^"/root/MusicManager")
	if mm:
		mm.call(&"stop")
		return
	_set_pending(&"")
	_current_track = &""
	for i in 2:
		if _music_players[i].playing:
			_fade_music(i, 0.0, 1.6, true)


## True if the music system can play `track` (map loader uses this to pick its fallback).
func has_track(track: StringName) -> bool:
	var mm := get_node_or_null(^"/root/MusicManager")
	if mm:
		return mm.call(&"has_track", track)
	return track in [&"menu", &"backyard"]


# ================================================================ playback internals

func _set_pending(track: StringName) -> void:
	_mutex.lock()
	_pending_track = track
	_mutex.unlock()


func _start_music(track: StringName) -> void:
	var stream: AudioStreamWAV = _music_streams.get(track)
	if stream == null:
		return
	var old := _music_idx
	_music_idx = 1 - _music_idx
	var nu := _music_players[_music_idx]
	if _music_tweens[_music_idx] and _music_tweens[_music_idx].is_valid():
		_music_tweens[_music_idx].kill()
	_set_music_gain(0.0, _music_idx)
	nu.stream = stream
	nu.play()
	_fade_music(_music_idx, 1.0, MUSIC_FADE, false)
	if _music_players[old].playing:
		_fade_music(old, 0.0, MUSIC_FADE, true)
	_current_track = track


func _fade_music(i: int, to: float, duration: float, stop_after: bool) -> void:
	if _music_tweens[i] and _music_tweens[i].is_valid():
		_music_tweens[i].kill()
	var tw := create_tween()
	tw.tween_method(_set_music_gain.bind(i), _music_gain[i], to, duration)
	if stop_after:
		tw.tween_callback(_music_players[i].stop)
	_music_tweens[i] = tw


func _set_music_gain(g: float, i: int) -> void:
	_music_gain[i] = g
	_music_players[i].volume_db = linear_to_db(maxf(g, 0.0001)) + MUSIC_BASE_DB


func _setup_buses() -> void:
	_sfx_bus = _ensure_bus(SFX_BUS)
	_music_bus = _ensure_bus(MUSIC_BUS)
	_amb_bus = _ensure_bus(AMB_BUS)
	_ui_bus = _ensure_bus(UI_BUS)  # dry, no effects (default_bus_layout.tres, docs/team/music.md)
	if AudioServer.get_bus_effect_count(_amb_bus) == 0:
		# Open-air ruins: long, dark, mostly wet so the beds feel far away.
		var averb := AudioEffectReverb.new()
		averb.room_size = 0.9
		averb.damping = 0.7
		averb.spread = 1.0
		averb.wet = 0.3
		averb.dry = 0.85
		averb.predelay_msec = 60.0
		averb.hipass = 0.15
		AudioServer.add_bus_effect(_amb_bus, averb)
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			has_limiter = true
	if not has_limiter:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.8
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(0, lim)
	if AudioServer.get_bus_effect_count(_music_bus) == 0:
		var verb := AudioEffectReverb.new()
		verb.room_size = 0.8
		verb.damping = 0.55
		verb.spread = 0.8
		verb.wet = 0.24
		verb.dry = 0.9
		verb.predelay_msec = 40.0
		AudioServer.add_bus_effect(_music_bus, verb)
	if AudioServer.get_bus_effect_count(_sfx_bus) == 0:
		var sverb := AudioEffectReverb.new()
		sverb.room_size = 0.6
		sverb.damping = 0.6
		sverb.spread = 0.6
		sverb.wet = 0.1
		sverb.dry = 1.0
		sverb.predelay_msec = 25.0
		AudioServer.add_bus_effect(_sfx_bus, sverb)


func _ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	return idx


func _apply_volumes() -> void:
	var sv: float = clampf(Settings.sfx_volume, 0.0, 1.0)
	var mv: float = clampf(Settings.music_volume, 0.0, 1.0)
	if sv != _last_sfx_vol:
		_last_sfx_vol = sv
		_set_bus_volume(_sfx_bus, sv)
	if mv != _last_music_vol:
		_last_music_vol = mv
		_set_bus_volume(_music_bus, mv)
	var av := sv
	var custom: Variant = Settings.get(&"ambience_volume")
	if custom is float or custom is int:
		av = clampf(float(custom), 0.0, 1.0)
	if av != _last_amb_vol:
		_last_amb_vol = av
		_set_bus_volume(_amb_bus, av)
	var uv := sv
	var ui_custom: Variant = Settings.get(&"ui_volume")
	if ui_custom is float or ui_custom is int:
		uv = clampf(float(ui_custom), 0.0, 1.0)
	if uv != _last_ui_vol:
		_last_ui_vol = uv
		_set_bus_volume(_ui_bus, uv)


func _set_bus_volume(idx: int, v: float) -> void:
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


func _on_node_added(node: Node) -> void:
	if node.get_parent() != get_tree().root:
		return
	_music_for_scene(node)


func _check_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene:
		_music_for_scene(scene)


func _music_for_scene(node: Node) -> void:
	var path := node.scene_file_path
	if path == MAIN_SCENE or node.name == &"Main":
		play_music(&"backyard")
		_ensure_ambience.call_deferred(node)
	elif MENU_SCENES.has(path) or MENU_NODE_NAMES.has(node.name):
		play_music(&"menu")


## Adds the Ambience node to the main scene unless the scene already has one.
func _ensure_ambience(main: Node) -> void:
	if not is_instance_valid(main) or not main.is_inside_tree():
		return
	if main.get_node_or_null(^"Ambience") != null:
		return
	for n in get_tree().get_nodes_in_group(&"ambience"):
		if main.is_ancestor_of(n):
			return
	var script: Script = load(AMBIENCE_SCRIPT)
	if script == null:
		return
	var amb := Node3D.new()
	amb.set_script(script)
	amb.name = &"Ambience"
	main.add_child(amb)


# ================================================================ generation (worker thread)

func _generate() -> void:
	var key := CACHE.version_key(PackedStringArray(CACHE_SOURCES), RECIPE_VERSION)
	var use_cache := not OS.get_cmdline_user_args().has("--sfx-nocache")
	var cached := CACHE.load_streams(key) if use_cache else {}
	if not cached.is_empty():
		loaded_from_cache = true
		_publish_sfx(cached)
		# Legacy music only renders when MusicManager is absent (then _render_track does work).
		if not ProjectSettings.has_setting("autoload/MusicManager"):
			_build_tables()
			_publish_music(&"menu", _render_track(&"menu"))
			_publish_music(&"backyard", _render_track(&"backyard"))
		return
	_rng.seed = 0x5117B0
	_build_tables()
	_publish_sfx(_build_light_sfx())
	_publish_sfx(RECIPES.build(self))
	_publish_sfx(WORLD.build(self))
	_publish_sfx(SINS.build(self))
	_publish_sfx(SIGNATURE.build(self))
	_mutex.lock()
	var first := _pending_track
	_mutex.unlock()
	var order: Array[StringName] = [&"menu", &"backyard"]
	if first == &"backyard":
		order = [&"backyard", &"menu"]
	_publish_music(order[0], _render_track(order[0]))
	_publish_sfx(_build_heavy_sfx())
	if order[0] == &"backyard":
		_publish_sfx(_build_ambience())
		_publish_music(order[1], _render_track(order[1]))
	else:
		_publish_music(order[1], _render_track(order[1]))
		_publish_sfx(_build_ambience())
	_publish_sfx(RECIPES.build_loops(self))
	_publish_sfx(WORLD.build_heavy(self))
	CACHE.save_streams(key, _rendered)


func _publish_sfx(d: Dictionary) -> void:
	_rendered.merge(d, true)
	_mutex.lock()
	_incoming_sfx.merge(d, true)
	_mutex.unlock()


func _publish_music(track: StringName, s: AudioStreamWAV) -> void:
	_mutex.lock()
	_incoming_music[track] = s
	_mutex.unlock()


func _build_tables() -> void:
	_sin_tab.resize(TAB_SIZE)
	_pad_tab.resize(TAB_SIZE)
	_saw_tab.resize(TAB_SIZE)
	var saw_peak := 0.0
	for i in TAB_SIZE:
		var x := TAU * float(i) / TAB_SIZE
		_sin_tab[i] = sin(x)
		_pad_tab[i] = (sin(x) + 0.35 * sin(2.0 * x) + 0.12 * sin(3.0 * x) + 0.05 * sin(4.0 * x)) / 1.3
		var s := 0.0
		for h in range(1, 15):
			s += sin(x * h) / float(h)
		_saw_tab[i] = s
		saw_peak = maxf(saw_peak, absf(s))
	for i in TAB_SIZE:
		_saw_tab[i] /= saw_peak


## Short, frequent sounds: ready within moments of launch.
func _build_light_sfx() -> Dictionary:
	var d := {}
	d[&"ui_click"] = _sfx_ui_click()
	d[&"ui_hover"] = _sfx_ui_hover()
	d[&"ui_back"] = _sfx_ui_back()
	d[&"select"] = _sfx_select()
	d[&"hit"] = _sfx_hit()
	d[&"impact"] = _sfx_impact()
	d[&"holy_hit"] = _sfx_holy_hit()
	d[&"soul"] = _sfx_soul()
	d[&"gold"] = _sfx_gold()
	d[&"chalice"] = _sfx_chalice()
	d[&"hurt"] = _sfx_hurt()
	d[&"cast"] = _sfx_cast()
	d[&"fire_bolt"] = _sfx_fire_bolt()
	d[&"cleave"] = _sfx_cleave()
	d[&"chain"] = _sfx_chain()
	d[&"scythe"] = _sfx_scythe()
	d[&"brimstone"] = _sfx_brimstone()
	d[&"wingbeat"] = _sfx_wingbeat()
	d[&"beam"] = _sfx_beam()
	d[&"smite"] = _sfx_smite()
	d[&"toast"] = _sfx_toast()
	# Own RNG stream, so the older sounds render exactly as before.
	var keep := _rng.state
	_rng.seed = 0x57E95
	for i in 3:
		d[VARIANTS[&"step_stone"][i]] = _sfx_step_stone(i)
		d[VARIANTS[&"step_grass"][i]] = _sfx_step_grass(i)
	_rng.state = keep
	return d


## Long, choir- and bell-heavy sounds.
func _build_heavy_sfx() -> Dictionary:
	var d := {}
	d[&"angel_death"] = _sfx_angel_death()
	d[&"level_up"] = _sfx_level_up()
	d[&"faint"] = _sfx_faint()
	d[&"choir"] = _sfx_choir()
	d[&"toll"] = _sfx_toll()
	d[&"triumph"] = _sfx_triumph()
	d[&"boss_roar"] = _sfx_boss_roar()
	d[&"boss_charge"] = _sfx_boss_charge()
	d[&"boss_intro"] = _sfx_boss_intro()
	d[&"boss_death"] = _sfx_boss_death()
	d[&"unmade"] = _sfx_unmade()
	return d


# ---------------------------------------------------------------- sound recipes: combat

func _sfx_hit() -> AudioStreamWAV:
	# Meaty thud: falling low body, a muffled flesh smack, a whisper of click.
	_begin(0.2)
	_tone(0.0, 0.16, 170.0, 52.0, 1.0, W_SINE, 0.001, 2.6)
	_tone(0.0, 0.05, 320.0, 140.0, 0.35, W_TRI, 0.001, 3.0)
	_noise(0.0, 0.07, 0.7, 1400.0, 260.0, 0.9, F_LOW, 0.001, 2.4)
	_noise(0.0, 0.012, 0.18, 3200.0, 2400.0, 1.0, F_BAND, 0.0005, 1.5)
	return _finish(0.55)


func _sfx_impact() -> AudioStreamWAV:
	_begin(0.55)
	_tone(0.0, 0.5, 120.0, 34.0, 1.0, W_SINE, 0.002, 2.2)
	_tone(0.0, 0.12, 240.0, 90.0, 0.4, W_SOFTSQ, 0.001, 2.5)
	_noise(0.0, 0.25, 0.8, 900.0, 140.0, 0.8, F_LOW, 0.002, 2.0)
	_noise(0.0, 0.03, 0.3, 2600.0, 1200.0, 1.2, F_BAND, 0.0005, 2.0)
	return _finish(0.62)


func _sfx_holy_hit() -> AudioStreamWAV:
	# Bright metallic chime: a struck sacred blade.
	_begin(0.75)
	_bell(0.0, 1760.0, 1.0, 0.11, true)
	_bell(0.0, 2489.0, 0.45, 0.07, true)
	_bell(0.004, 3729.0, 0.2, 0.04, true)
	_noise(0.0, 0.01, 0.3, 3600.0, 3600.0, 1.0, F_HIGH, 0.0003, 1.5)
	_tone(0.0, 0.06, 260.0, 120.0, 0.25, W_SINE, 0.001, 2.5)
	return _finish(0.3)


func _sfx_angel_death() -> AudioStreamWAV:
	# Shattering glass, then a soft descending choir sigh.
	_begin(1.8)
	for i in 16:
		var t := _rng.randf_range(0.0, 0.22) * pow(_rng.randf(), 0.7)
		_bell(t, _rng.randf_range(2300.0, 5200.0), _rng.randf_range(0.25, 0.7),
			_rng.randf_range(0.02, 0.07), true)
	_noise(0.0, 0.3, 0.55, 3600.0, 2800.0, 0.8, F_HIGH, 0.001, 3.0)
	_noise(0.0, 0.08, 0.35, 1800.0, 900.0, 1.0, F_BAND, 0.001, 2.0)
	var sigh := _tpl_choir([69, 76], 1.35, 0.12, 0.9, V_OH, 1.0, 0.9, 0.12, 2)
	_add(sigh, 0.06, 0.55)
	_reverb(0.35, 0.78, 0.45)
	return _finish(0.42)


func _sfx_beam() -> AudioStreamWAV:
	# A lance of holy light: shimmering high tones over a hum.
	_begin(0.8)
	_bell(0.0, 1318.5, 0.5, 0.12)
	_tone(0.0, 0.75, 1318.5, 1310.0, 0.6, W_SINE, 0.02, 1.2, 6.0, 0.004, 32.0, 0.35)
	_tone(0.0, 0.75, 1975.5, 1960.0, 0.3, W_SINE, 0.03, 1.3, 5.0, 0.004, 40.0, 0.4)
	_tone(0.0, 0.75, 659.25, 650.0, 0.35, W_TRI, 0.04, 1.5)
	_noise(0.0, 0.7, 0.18, 3400.0, 3000.0, 1.0, F_HIGH, 0.03, 1.3)
	return _finish(0.32)


func _sfx_smite() -> AudioStreamWAV:
	# Judgement from above: a ringing strike and a heavy downward blow.
	_begin(1.1)
	_bell(0.0, 1046.5, 0.8, 0.22, true)
	_bell(0.0, 1567.98, 0.35, 0.15, true)
	_tone(0.0, 0.6, 150.0, 38.0, 1.0, W_SINE, 0.002, 2.0)
	_noise(0.0, 0.35, 0.7, 3200.0, 300.0, 0.9, F_BAND, 0.001, 2.2)
	_reverb(0.25, 0.7, 0.5)
	return _finish(0.52)


func _sfx_wingbeat() -> AudioStreamWAV:
	# Two heavy feathered strokes.
	_begin(0.5)
	for k in 2:
		var t := k * 0.17
		_noise(t, 0.16, 1.0 - k * 0.25, 280.0, 900.0, 1.2, F_BAND, 0.05, 2.2, 38.0, 0.35)
		_noise(t, 0.12, 0.3, 1800.0, 1200.0, 1.0, F_BAND, 0.04, 2.0)
	_tone(0.0, 0.12, 90.0, 60.0, 0.25, W_SINE, 0.03, 2.0)
	return _finish(0.36)


func _sfx_soul() -> AudioStreamWAV:
	# Low whispery pickup: a breath drawn inward with a faint hollow tone.
	_begin(0.26)
	_noise(0.0, 0.22, 0.8, 500.0, 1500.0, 3.5, F_BAND, 0.05, 1.6)
	_tone(0.0, 0.22, 311.0, 392.0, 0.35, W_SINE, 0.04, 1.6)
	_tone(0.0, 0.22, 622.0, 784.0, 0.08, W_SINE, 0.05, 1.8)
	return _finish(0.24)


func _sfx_gold() -> AudioStreamWAV:
	# A relic's chime: old gold, warm and slightly inharmonic.
	_begin(1.6)
	var notes := [880.0, 1046.5, 1318.5, 1760.0]
	for i in notes.size():
		_bell(i * 0.055, float(notes[i]), 1.0 - i * 0.15, 0.22)
	_bell(0.0, 440.0, 0.45, 0.35, true)
	_reverb(0.3, 0.75, 0.4)
	return _finish(0.4)


func _sfx_chalice() -> AudioStreamWAV:
	# Dark liquid poured, then a warm low tone wells up.
	_begin(1.4)
	for i in 7:
		var t := _rng.randf_range(0.0, 0.32)
		var f := _rng.randf_range(180.0, 320.0)
		_tone(t, 0.07, f, f * 2.2, _rng.randf_range(0.25, 0.5), W_SINE, 0.004, 2.0)
	_noise(0.0, 0.35, 0.18, 700.0, 400.0, 2.0, F_BAND, 0.02, 1.4, 14.0, 0.5)
	_tone(0.1, 1.2, 196.0, 196.0, 0.5, W_TRI, 0.35, 1.8, 4.5, 0.004)
	_tone(0.1, 1.2, 293.66, 293.66, 0.3, W_SINE, 0.4, 1.8, 4.5, 0.004)
	_tone(0.15, 1.1, 392.0, 392.0, 0.12, W_SINE, 0.45, 2.0)
	_lowpass(2400.0)
	return _finish(0.42)


func _sfx_hurt() -> AudioStreamWAV:
	# A low grunting growl.
	_begin(0.34)
	_meow(0.0, 0.3, 118.0, 132.0, 86.0, 1.0, 620.0, 720.0, 430.0, 0.0, 0.0, 34.0)
	_tone(0.0, 0.12, 110.0, 55.0, 0.5, W_SINE, 0.002, 2.4)
	_noise(0.0, 0.2, 0.18, 700.0, 400.0, 2.0, F_BAND, 0.01, 1.8)
	return _finish(0.46)


func _sfx_faint() -> AudioStreamWAV:
	# A deep fall: a dying roar sinking into a rumble.
	_begin(2.6)
	_meow(0.0, 1.1, 150.0, 130.0, 58.0, 1.0, 720.0, 620.0, 320.0, 3.0, 0.02, 24.0)
	_tone(0.0, 2.2, 96.0, 28.0, 0.8, W_SINE, 0.05, 1.4)
	_noise(0.0, 2.0, 0.45, 500.0, 90.0, 0.7, F_LOW, 0.1, 1.5)
	_tone(0.5, 1.8, 73.4, 72.0, 0.25, W_SAW, 0.4, 1.6)
	_lowpass(1800.0)
	_reverb(0.35, 0.82, 0.5)
	return _finish(0.55)


func _sfx_cast() -> AudioStreamWAV:
	# A profane incantation: rising breathy surge with a dark chord tone.
	_begin(0.5)
	_noise(0.0, 0.42, 0.8, 300.0, 2400.0, 2.0, F_BAND, 0.14, 1.4)
	_tone(0.0, 0.42, 146.8, 220.0, 0.35, W_TRI, 0.12, 1.5)
	_tone(0.0, 0.42, 174.6, 261.6, 0.25, W_TRI, 0.12, 1.5)
	_bell(0.3, 880.0, 0.25, 0.08, true)
	return _finish(0.34)


func _sfx_fire_bolt() -> AudioStreamWAV:
	# Whoosh-burn: a rushing sweep with crackling embers.
	_begin(0.5)
	_noise(0.0, 0.45, 1.0, 400.0, 1800.0, 1.3, F_BAND, 0.06, 1.8)
	_noise(0.0, 0.45, 0.5, 260.0, 160.0, 0.8, F_LOW, 0.04, 1.6)
	_crackle(0.02, 0.4, 0.45, 70.0)
	_tone(0.0, 0.3, 80.0, 55.0, 0.25, W_SINE, 0.02, 1.8)
	return _finish(0.38)


func _sfx_cleave() -> AudioStreamWAV:
	# Heavy swing: a broad blade cutting the air, with weight behind it.
	_begin(0.38)
	_noise(0.0, 0.32, 1.0, 220.0, 1500.0, 1.4, F_BAND, 0.11, 2.6)
	_noise(0.05, 0.2, 0.3, 2400.0, 1800.0, 1.2, F_BAND, 0.05, 2.0)
	_tone(0.04, 0.24, 95.0, 58.0, 0.35, W_SINE, 0.05, 2.0)
	return _finish(0.42)


func _sfx_chain() -> AudioStreamWAV:
	# Crackling chain: rattling iron links and sparking discharge.
	_begin(0.42)
	for i in 9:
		_bell(_rng.randf_range(0.0, 0.26), _rng.randf_range(1400.0, 3200.0), _rng.randf_range(0.2, 0.5),
			_rng.randf_range(0.015, 0.035), true)
	_crackle(0.0, 0.35, 0.6, 150.0)
	_tone(0.0, 0.3, 60.0, 58.0, 0.25, W_SAW, 0.01, 1.6, 0.0, 0.0, 50.0, 0.8)
	_noise(0.0, 0.3, 0.2, 3400.0, 3000.0, 1.0, F_HIGH, 0.005, 2.0)
	return _finish(0.34)


func _sfx_scythe() -> AudioStreamWAV:
	# Whirring blade.
	_begin(0.55)
	_noise(0.0, 0.5, 0.9, 1100.0, 1700.0, 2.2, F_BAND, 0.05, 1.3, 17.0, 0.85)
	_tone(0.0, 0.5, 520.0, 600.0, 0.18, W_TRI, 0.05, 1.3, 0.0, 0.0, 17.0, 0.8)
	_tone(0.0, 0.5, 120.0, 130.0, 0.15, W_SINE, 0.05, 1.3, 0.0, 0.0, 17.0, 0.6)
	return _finish(0.3)


func _sfx_brimstone() -> AudioStreamWAV:
	# Roaring fire.
	_begin(1.2)
	_noise(0.0, 1.15, 1.0, 260.0, 800.0, 0.8, F_LOW, 0.08, 1.2, 7.0, 0.35)
	_noise(0.0, 1.1, 0.35, 900.0, 1400.0, 1.2, F_BAND, 0.1, 1.3, 11.0, 0.4)
	_crackle(0.0, 1.0, 0.4, 55.0)
	_tone(0.0, 1.0, 52.0, 46.0, 0.35, W_SINE, 0.1, 1.4)
	return _finish(0.48)


# ---------------------------------------------------------------- sound recipes: ritual

func _sfx_choir() -> AudioStreamWAV:
	_begin(2.9)
	var tpl := _tpl_choir([50, 57, 62, 65], 2.4, 0.35, 1.0, V_AH, 1.0, 1.0, 0.1, 2)
	_add(tpl, 0.0, 1.0)
	_reverb(0.35, 0.82, 0.45)
	return _finish(0.45)


func _sfx_level_up() -> AudioStreamWAV:
	# Deep resonant gong, then a rising choir.
	_begin(3.4)
	_add(_tpl_bell(98.0, 2.6, 1.0), 0.0, 0.9)
	_tone(0.0, 0.7, 70.0, 36.0, 0.7, W_SINE, 0.002, 2.0)
	var rise := _tpl_choir([50, 57, 62, 69], 2.4, 0.9, 0.9, V_AH, 0.89, 1.0, 0.08, 2)
	_add(rise, 0.25, 0.8)
	_reverb(0.32, 0.84, 0.45)
	return _finish(0.6)


func _sfx_toast() -> AudioStreamWAV:
	# A low, distant bell.
	_begin(2.4)
	_add(_tpl_bell(196.0, 1.6, 0.9), 0.0, 0.8)
	_lowpass(2600.0)
	_reverb(0.3, 0.8, 0.5)
	return _finish(0.28)


func _sfx_toll() -> AudioStreamWAV:
	_begin(3.4)
	_add(_tpl_bell(146.8, 2.4, 1.0), 0.0, 1.0)
	_lowpass(3000.0)
	_reverb(0.32, 0.84, 0.45)
	return _finish(0.4)


func _sfx_triumph() -> AudioStreamWAV:
	# A dark victory: gong and a grave major chord in the choir.
	_begin(3.6)
	_add(_tpl_bell(73.4, 2.8, 1.0), 0.0, 0.8)
	var ch := _tpl_choir([50, 57, 62, 66], 2.8, 0.3, 1.2, V_AH, 1.0, 1.0, 0.08, 2)
	_add(ch, 0.1, 0.9)
	_reverb(0.32, 0.84, 0.45)
	return _finish(0.5)


func _sfx_boss_roar() -> AudioStreamWAV:
	# A seraphic war-cry: a choir shout over a rumbling low body.
	_begin(2.2)
	var shout := _tpl_choir([45, 52, 57, 60], 1.7, 0.08, 0.7, V_EH, 1.03, 0.97, 0.18, 2)
	_add(shout, 0.0, 1.0)
	_tone(0.0, 1.6, 55.0, 48.0, 0.6, W_SAW, 0.1, 1.2, 6.0, 0.02)
	_noise(0.0, 1.4, 0.5, 300.0, 1200.0, 1.2, F_BAND, 0.15, 1.3, 18.0, 0.25)
	_lowpass(2800.0)
	_reverb(0.25, 0.8, 0.5)
	return _finish(0.6)


func _sfx_boss_charge() -> AudioStreamWAV:
	# Gathering power: rising wind and a choir crescendo.
	_begin(1.6)
	_noise(0.0, 1.3, 1.0, 300.0, 2400.0, 2.0, F_BAND, 1.0, 0.25)
	var ch := _tpl_choir([57, 64], 1.3, 1.1, 0.15, V_OO, 0.92, 1.0, 0.15, 2)
	_add(ch, 0.0, 0.8)
	_tone(0.0, 1.3, 55.0, 82.0, 0.3, W_SAW, 1.0, 0.3)
	_lowpass(3000.0)
	return _finish(0.45)


func _sfx_boss_intro() -> AudioStreamWAV:
	# A massive choir chord with a cataclysmic impact beneath.
	_begin(5.2)
	var ch := _tpl_choir([38, 45, 50, 57, 62], 3.8, 0.12, 2.0, V_AH, 1.0, 1.0, 0.1, 2)
	_add(ch, 0.0, 1.0)
	_add(_tpl_bell(73.4, 3.0, 0.8), 0.0, 0.5)
	_tone(0.0, 1.6, 80.0, 26.0, 1.2, W_SINE, 0.002, 1.8)
	_noise(0.0, 0.9, 0.9, 1400.0, 120.0, 0.8, F_LOW, 0.002, 2.0)
	_noise(0.0, 0.05, 0.4, 3000.0, 1500.0, 1.0, F_BAND, 0.0005, 2.0)
	_reverb(0.36, 0.86, 0.4)
	return _finish(0.75)


func _sfx_boss_death() -> AudioStreamWAV:
	# A long reverberant gong as the great foe falls; a sigh of the Host beneath.
	_begin(7.5)
	_add(_tpl_bell(65.4, 4.5, 1.0), 0.0, 1.0)
	_add(_tpl_bell(130.8, 2.5, 0.8), 0.02, 0.3)
	_tone(0.0, 1.8, 70.0, 24.0, 0.9, W_SINE, 0.002, 1.8)
	_noise(0.0, 1.2, 0.6, 1200.0, 100.0, 0.8, F_LOW, 0.002, 2.0)
	var sigh := _tpl_choir([57, 64, 69], 3.2, 0.4, 2.2, V_OO, 1.0, 0.86, 0.1, 2)
	_add(sigh, 0.5, 0.5)
	_reverb(0.45, 0.9, 0.4)
	return _finish(0.72)


func _sfx_unmade() -> AudioStreamWAV:
	# Death of the demon: a low boom, a funereal bell and a dark minor chord sinking away.
	_begin(6.0)
	_tone(0.0, 2.8, 58.0, 26.0, 1.0, W_SINE, 0.002, 1.5)
	_noise(0.0, 1.0, 0.6, 900.0, 80.0, 0.8, F_LOW, 0.002, 2.0)
	_add(_tpl_bell(73.4, 3.6, 0.7), 0.15, 0.6)
	var ch := _tpl_choir([38, 45, 50, 53], 4.2, 1.0, 2.4, V_OO, 1.0, 0.94, 0.08, 2)
	_add(ch, 0.3, 0.75)
	_lowpass(2200.0)
	_reverb(0.4, 0.88, 0.45)
	return _finish(0.65)


# ---------------------------------------------------------------- sound recipes: interface

func _sfx_ui_click() -> AudioStreamWAV:
	# A stone-and-metal click.
	_begin(0.09)
	_tone(0.0, 0.04, 260.0, 170.0, 0.8, W_SINE, 0.0005, 3.0)
	_noise(0.0, 0.014, 0.9, 2400.0, 1800.0, 5.0, F_BAND, 0.0003, 2.0)
	_bell(0.0, 2349.0, 0.12, 0.02, true)
	return _finish(0.22)


func _sfx_ui_hover() -> AudioStreamWAV:
	_begin(0.06)
	_noise(0.0, 0.01, 0.6, 3000.0, 2600.0, 5.0, F_BAND, 0.0003, 2.0)
	_tone(0.0, 0.035, 1174.7, 1174.7, 0.25, W_SINE, 0.001, 3.0)
	return _finish(0.09)


func _sfx_ui_back() -> AudioStreamWAV:
	_begin(0.12)
	_tone(0.0, 0.08, 220.0, 120.0, 0.9, W_SINE, 0.0005, 2.6)
	_noise(0.0, 0.02, 0.7, 1500.0, 900.0, 4.0, F_BAND, 0.0005, 2.0)
	return _finish(0.2)


func _sfx_select() -> AudioStreamWAV:
	# Confirmation: a heavy latch and a low ring of metal.
	_begin(1.2)
	_tone(0.0, 0.05, 240.0, 140.0, 0.8, W_SINE, 0.0005, 3.0)
	_noise(0.0, 0.016, 0.7, 2000.0, 1500.0, 5.0, F_BAND, 0.0003, 2.0)
	_bell(0.01, 523.25, 0.6, 0.2, true)
	_bell(0.01, 784.0, 0.3, 0.14, true)
	return _finish(0.3)


# ---------------------------------------------------------------- sound recipes: footsteps

func _sfx_step_stone(v: int) -> AudioStreamWAV:
	# A heavy hoof/clawed foot on flagstones: deep thud, a knock, gritty scrape and pebbles.
	_begin(0.4)
	var f := 74.0 + v * 7.0 + _rng.randf_range(-3.0, 3.0)
	_tone(0.0, 0.26, f, f * 0.45, 1.0, W_SINE, 0.002, 2.6)
	_tone(0.0, 0.06, f * 2.7, f * 1.4, 0.3, W_TRI, 0.001, 3.0)
	_noise(0.0, 0.14, 0.7, 700.0, 160.0, 0.9, F_LOW, 0.001, 2.4)
	_noise(0.004, 0.07, 0.35, 2600.0 - v * 300.0, 1500.0, 1.4, F_BAND, 0.0008, 2.2)
	_crackle(0.01, 0.09, 0.22, 140.0 + v * 30.0)
	_lowpass(4200.0)
	return _finish(0.5)


func _sfx_step_grass(v: int) -> AudioStreamWAV:
	# A heavy foot in dead grass and soft earth: muffled thud and a dry swish of blades.
	_begin(0.4)
	var f := 68.0 + v * 6.0 + _rng.randf_range(-3.0, 3.0)
	_tone(0.0, 0.22, f, f * 0.47, 0.8, W_SINE, 0.004, 2.4)
	_noise(0.0, 0.12, 0.6, 500.0, 140.0, 0.9, F_LOW, 0.002, 2.2)
	_noise(0.0, 0.2, 0.4, 2200.0 + v * 250.0, 3200.0, 1.1, F_BAND, 0.02, 1.8)
	_noise(0.02, 0.16, 0.18, 3400.0, 3400.0, 1.0, F_HIGH, 0.03, 2.0)
	return _finish(0.45)


# ---------------------------------------------------------------- ambience beds

func _build_ambience() -> Dictionary:
	var keep := _rng.state
	_rng.seed = 0xA4B1E
	var d := {}
	d[&"amb_fire"] = _amb_fire()
	d[&"bell_distant"] = _amb_bell()
	d[&"amb_wind"] = _amb_wind()
	d[&"amb_storm"] = _amb_storm()
	d[&"amb_choir"] = _amb_choir()
	_rng.state = keep
	return d


## Low moaning wind with slow gusts (24 s loop).
func _amb_wind() -> AudioStreamWAV:
	_begin(26.0)
	_wind_layer(1.0, 110.0, 340.0, 2.4, 0.125, 0.0)
	_wind_layer(0.45, 280.0, 950.0, 1.5, 0.0833, 2.1)
	_wind_layer(0.1, 1300.0, 2500.0, 6.0, 0.2083, 4.4)
	return _finish_loop(24.0, 0.7)


## Distant choir drone: two slow overlapping chords (20 s loop).
func _amb_choir() -> AudioStreamWAV:
	_begin(22.0)
	_add(_tpl_choir([50, 57, 62], 12.0, 0.02, 3.0, V_OO, 1.0, 1.0, 0.05, 2), 0.0, 0.6)
	_add(_tpl_choir([46, 53, 62], 13.0, 3.0, 0.02, V_OH, 1.0, 1.0, 0.05, 2), 9.0, 0.6)
	_lowpass(1600.0)
	return _finish_loop(20.0, 0.7)


## Brazier fire: low roar, hiss, crackles and the odd pop (6 s loop).
func _amb_fire() -> AudioStreamWAV:
	_begin(6.5)
	_noise(0.0, 6.5, 0.5, 220.0, 260.0, 0.8, F_LOW, 0.01, 0.0, 5.3, 0.35)
	_noise(0.0, 6.5, 0.16, 900.0, 1100.0, 1.0, F_BAND, 0.01, 0.0, 3.1, 0.5)
	for s in 13:
		_crackle(s * 0.5, 0.5, _rng.randf_range(0.35, 0.8), _rng.randf_range(18.0, 55.0))
	for k in 7:
		var t := _rng.randf_range(0.0, 6.3)
		var f := _rng.randf_range(800.0, 1500.0)
		_tone(t, 0.03, f, f * 0.6, 0.12, W_SINE, 0.0005, 3.0)
	return _finish_loop(6.0, 0.6)


## Ash storm: a constant airy hiss with big rolling whooshes (16 s loop).
func _amb_storm() -> AudioStreamWAV:
	_begin(18.0)
	_noise(0.0, 18.0, 0.25, 1800.0, 2200.0, 0.9, F_BAND, 0.01, 0.0, 0.19, 0.6)
	_noise(0.0, 18.0, 0.35, 90.0, 120.0, 0.7, F_LOW, 0.01, 0.0, 0.11, 0.5)
	for k in 7:
		var t := k * 2.4 + _rng.randf_range(-0.4, 0.4)
		var length := _rng.randf_range(2.0, 3.2)
		var up := _rng.randf() < 0.5
		_noise(maxf(t, 0.0), length, _rng.randf_range(0.6, 1.0), 300.0 if up else 1600.0,
				1600.0 if up else 350.0, 1.6, F_BAND, length * 0.45, 1.6)
	return _finish_loop(16.0, 0.6)


## A great bell tolling far away (one-shot).
func _amb_bell() -> AudioStreamWAV:
	_begin(5.0)
	_add(_tpl_bell(110.0, 1.5, 0.35), 0.0, 1.0)
	_lowpass(1100.0)
	_lowpass(1500.0)
	return _finish(0.4)


## One wind band: SVF bandpass whose cutoff and level follow a slow two-sine gust curve.
func _wind_layer(amp: float, fc_lo: float, fc_hi: float, q: float, gust_hz: float, phase: float) -> void:
	var n := _buf.size()
	var damp := clampf(1.0 / maxf(q, 0.1), 0.1, 1.4)
	var low := 0.0
	var band := 0.0
	var g := 0.0
	var lvl := 0.0
	for i in n:
		if (i & 31) == 0:
			var t := float(i) / SR
			var g1 := 0.5 + 0.5 * sin(TAU * gust_hz * t + phase)
			var g2 := 0.5 + 0.5 * sin(TAU * gust_hz * 2.7 * t + phase * 1.7)
			var gust := pow(0.65 * g1 + 0.35 * g2, 1.6)
			g = 2.0 * sin(PI * lerpf(fc_lo, fc_hi, gust) / SR)
			lvl = amp * (0.25 + 0.75 * gust)
		var w := _rng.randf() * 2.0 - 1.0
		low += g * band
		var high := w - low - damp * band
		band += g * high
		_buf[i] += band * lvl


## Normalizes the sfx buffer and folds its tail (beyond `loop_s`) over its head with an
## equal-power crossfade, returning a seamless looping stream of exactly `loop_s` seconds.
func _finish_loop(loop_s: float, peak: float) -> AudioStreamWAV:
	var n_loop := int(loop_s * SR)
	var xf := _buf.size() - n_loop
	var m := 0.0
	for i in _buf.size():
		m = maxf(m, absf(_buf[i]))
	var k := peak / m if m > 0.0 else 0.0
	var out := _buf.slice(0, n_loop)
	for i in xf:
		var t := float(i) / float(xf)
		out[i] = out[i] * sqrt(t) + _buf[n_loop + i] * sqrt(1.0 - t)
	for i in n_loop:
		out[i] *= k
	return _to_stream(out, true)


# ---------------------------------------------------------------- sfx synthesis helpers

func _begin(dur: float) -> void:
	_buf = PackedFloat32Array()
	_buf.resize(int(dur * SR))
	_buf.fill(0.0)


func _finish(peak: float) -> AudioStreamWAV:
	var n := _buf.size()
	var m := 0.0
	for i in n:
		m = maxf(m, absf(_buf[i]))
	var k := peak / m if m > 0.0 else 0.0
	@warning_ignore("integer_division")  # intentional truncation
	var fade := mini(256, n / 4)
	for i in n:
		var g := k
		if i < 8:
			g *= float(i) / 8.0
		elif i >= n - fade:
			g *= float(n - 1 - i) / float(fade)
		_buf[i] *= g
	return _to_stream(_buf, false)


## Adds a rendered template into the sfx buffer at `t0` seconds.
func _add(tpl: PackedFloat32Array, t0: float, gain: float) -> void:
	var start := int(t0 * SR)
	var n := mini(tpl.size(), _buf.size() - start)
	for j in n:
		_buf[start + j] += tpl[j] * gain


func _env(i: int, n: int, atk: float, curve: float) -> float:
	var a := maxf(atk * SR, 1.0)
	var e := minf(1.0, float(i) / a)
	return e * pow(1.0 - float(i) / float(n), curve)


func _wave(phase: float, kind: int) -> float:
	var p := phase - floorf(phase)
	match kind:
		W_TRI:
			return 4.0 * absf(p - 0.5) - 1.0
		W_SAW:
			return 2.0 * p - 1.0
		W_SOFTSQ:
			return tanh(3.0 * sin(TAU * p)) * 0.8
		W_PULSE:
			return 1.0 if p < 0.3 else -0.43
	return sin(TAU * p)


## Oscillator with an exponential glide f0 -> f1, attack + (1-x)^curve decay,
## optional vibrato (pitch) and amplitude wobble.
func _tone(t0: float, dur: float, f0: float, f1: float, amp: float, wave: int = W_SINE,
		atk: float = 0.004, curve: float = 2.0, vib_hz: float = 0.0, vib_depth: float = 0.0,
		am_hz: float = 0.0, am_depth: float = 0.0) -> void:
	var start := int(t0 * SR)
	var n := mini(int(dur * SR), _buf.size() - start)
	if n <= 0:
		return
	var phase := 0.0
	var f := f0
	var step := pow(f1 / f0, 1.0 / float(n))
	for i in n:
		var t := float(i) / SR
		var ff := f
		if vib_depth > 0.0:
			ff *= 1.0 + vib_depth * sin(TAU * vib_hz * t)
		phase += ff / SR
		var env := _env(i, n, atk, curve)
		if am_depth > 0.0:
			env *= 1.0 - am_depth * (0.5 + 0.5 * sin(TAU * am_hz * t))
		_buf[start + i] += _wave(phase, wave) * env * amp
		f *= step


## White noise through a state-variable filter whose cutoff sweeps fc0 -> fc1.
func _noise(t0: float, dur: float, amp: float, fc0: float, fc1: float, q: float, mode: int,
		atk: float, curve: float, am_hz: float = 0.0, am_depth: float = 0.0) -> void:
	var start := int(t0 * SR)
	var n := mini(int(dur * SR), _buf.size() - start)
	if n <= 0:
		return
	var damp := clampf(1.0 / maxf(q, 0.1), 0.2, 1.4)
	var low := 0.0
	var band := 0.0
	for i in n:
		var x := float(i) / float(n)
		var fc := clampf(lerpf(fc0, fc1, x), 20.0, 3600.0)
		var g := 2.0 * sin(PI * fc / SR)
		var w := _rng.randf() * 2.0 - 1.0
		low += g * band
		var high := w - low - damp * band
		band += g * high
		var s := low
		if mode == F_BAND:
			s = band
		elif mode == F_HIGH:
			s = high
		var env := _env(i, n, atk, curve)
		if am_depth > 0.0:
			env *= 1.0 - am_depth * (0.5 + 0.5 * sin(TAU * am_hz * float(i) / SR))
		_buf[start + i] += s * env * amp


## Random sharp clicks (embers, sparks), density per second, fading out over `dur`.
func _crackle(t0: float, dur: float, amp: float, density: float) -> void:
	var count := int(density * dur)
	for c in count:
		var x := _rng.randf()
		var start := int((t0 + x * dur) * SR)
		var length := _rng.randi_range(12, 70)
		var a := amp * _rng.randf_range(0.3, 1.0) * (1.0 - x * 0.7)
		var tau := float(length) * 0.3
		var prev := 0.0
		for j in length:
			var idx := start + j
			if idx >= _buf.size():
				break
			var w := _rng.randf() * 2.0 - 1.0
			var hp := w - prev  # crude high-pass for a crisp snap
			prev = w
			_buf[idx] += hp * a * exp(-float(j) / tau)


## Struck bell / chime: three decaying partials (harmonic, or inharmonic for metal).
func _bell(t0: float, f: float, amp: float, decay: float, inharmonic: bool = false) -> void:
	var start := int(t0 * SR)
	var n := mini(int(decay * 6.0 * SR), _buf.size() - start)
	if n <= 0:
		return
	var r2 := 2.76 if inharmonic else 2.0
	var r3 := 5.4 if inharmonic else 3.0
	var g2 := 0.5 if inharmonic else 0.3
	var g3 := 0.25 if inharmonic else 0.1
	if f * r2 > SR * 0.45:
		g2 = 0.0
	if f * r3 > SR * 0.45:
		g3 = 0.0
	var k1 := exp(-1.0 / (decay * SR))
	var k2 := exp(-2.2 / (decay * SR))
	var k3 := exp(-4.0 / (decay * SR))
	var e1 := 1.0
	var e2 := 1.0
	var e3 := 1.0
	var w := TAU * f / SR
	for i in n:
		var a := minf(1.0, float(i) / 30.0)
		var v := sin(w * i) * e1 + g2 * sin(w * r2 * i) * e2 + g3 * sin(w * r3 * i) * e3
		_buf[start + i] += v * a * amp
		e1 *= k1
		e2 *= k2
		e3 *= k3


## Vocal: saw source gliding f_a -> f_b -> f_c through two moving formant bandpasses.
## trill_hz > 0 adds a rough amplitude flutter (growl).
func _meow(t0: float, dur: float, f_a: float, f_b: float, f_c: float, amp: float,
		fm_a: float, fm_b: float, fm_c: float, vib_hz: float, vib_depth: float, trill_hz: float) -> void:
	var start := int(t0 * SR)
	var n := mini(int(dur * SR), _buf.size() - start)
	if n <= 0:
		return
	var phase := 0.0
	var lp := 0.0
	var low := 0.0
	var band := 0.0
	var low2 := 0.0
	var band2 := 0.0
	for i in n:
		var x := float(i) / float(n)
		var t := float(i) / SR
		var f: float
		var fm: float
		if x < 0.35:
			var u := _smooth(x / 0.35)
			f = lerpf(f_a, f_b, u)
			fm = lerpf(fm_a, fm_b, u)
		else:
			var u := _smooth((x - 0.35) / 0.65)
			f = lerpf(f_b, f_c, u)
			fm = lerpf(fm_b, fm_c, u)
		if vib_depth > 0.0:
			f *= 1.0 + vib_depth * sin(TAU * vib_hz * t)
		phase += f / SR
		phase -= floorf(phase)
		var src := 2.0 * phase - 1.0
		lp += (src - lp) * 0.5
		var g := 2.0 * sin(PI * minf(fm, 3600.0) / SR)
		low += g * band
		var high := lp - low - 0.35 * band
		band += g * high
		var g2 := 2.0 * sin(PI * minf(fm * 2.2, 3600.0) / SR)
		low2 += g2 * band2
		var high2 := lp - low2 - 0.5 * band2
		band2 += g2 * high2
		var env := minf(1.0, t / 0.025)
		if x > 0.6:
			env *= pow(1.0 - (x - 0.6) / 0.4, 1.5)
		if trill_hz > 0.0:
			env *= 0.55 + 0.45 * sin(TAU * trill_hz * t)
		_buf[start + i] += (band * 0.5 + band2 * 0.3 + lp * 0.12) * env * amp


func _lowpass(cut: float) -> void:
	var a := 1.0 - exp(-TAU * cut / SR)
	var y := 0.0
	for i in _buf.size():
		y += (_buf[i] - y) * a
		_buf[i] = y


## Small Schroeder reverb baked into the sfx buffer (4 damped combs + 2 allpasses).
func _reverb(wet: float, room: float, damp: float) -> void:
	var n := _buf.size()
	var dry := _buf.duplicate()
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	for d: int in [557, 593, 641, 677]:
		var line := PackedFloat32Array()
		line.resize(d)
		line.fill(0.0)
		var idx := 0
		var lp := 0.0
		for i in n:
			var y := line[idx]
			lp = y * (1.0 - damp) + lp * damp
			line[idx] = dry[i] * 0.3 + lp * room
			out[i] += y
			idx += 1
			if idx >= d:
				idx = 0
	for d: int in [225, 341]:
		var line := PackedFloat32Array()
		line.resize(d)
		line.fill(0.0)
		var idx := 0
		for i in n:
			var x := out[i]
			var b := line[idx]
			out[i] = b - x
			line[idx] = x + b * 0.5
			idx += 1
			if idx >= d:
				idx = 0
	for i in n:
		_buf[i] = dry[i] + out[i] * wet


static func _smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)


static func _phase_inc(f: float) -> int:
	return int(f * float(TAB_SIZE) * 65536.0 / SR)


# ---------------------------------------------------------------- shared templates

## Formant choir: `voices` detuned saw voices per note, summed, sung through three vowel
## formants, with slow shared vibrato, breath noise and an optional pitch glide
## (glide_from -> glide_to over the first 70% of the note).
func _tpl_choir(notes: Array, dur: float, atk: float, rel: float, vowel: int,
		glide_from: float = 1.0, glide_to: float = 1.0, breath: float = 0.08,
		voices: int = 2) -> PackedFloat32Array:
	var n := int(dur * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var nv := notes.size() * voices
	var base := PackedFloat64Array()
	var q := PackedInt64Array()
	var dep := PackedFloat32Array()
	var ca := PackedFloat32Array()
	var cb := PackedFloat32Array()
	var d := PackedInt64Array()
	base.resize(nv)
	q.resize(nv)
	dep.resize(nv)
	ca.resize(nv)
	cb.resize(nv)
	d.resize(nv)
	var k := 0
	for note in notes:
		var f := _hz(int(note))
		for v in voices:
			var det := 1.0 + (float(v) - float(voices - 1) * 0.5) * 0.007 + _rng.randf_range(-0.0015, 0.0015)
			base[k] = f * det * float(TAB_SIZE) * 65536.0 / SR
			q[k] = _rng.randi() & PHASE_MASK
			dep[k] = _rng.randf_range(0.0035, 0.0065)
			var ph := _rng.randf() * TAU
			ca[k] = cos(ph)
			cb[k] = sin(ph)
			k += 1
	var fm: Array = VOWELS[vowel]
	var g1 := 2.0 * sin(PI * minf(float(fm[0][0]), 3600.0) / SR)
	var g2 := 2.0 * sin(PI * minf(float(fm[1][0]), 3600.0) / SR)
	var g3 := 2.0 * sin(PI * minf(float(fm[2][0]), 3600.0) / SR)
	var d1 := 1.0 / float(fm[0][2])
	var d2 := 1.0 / float(fm[1][2])
	var d3 := 1.0 / float(fm[2][2])
	var a1 := float(fm[0][1]) * d1
	var a2 := float(fm[1][1]) * d2
	var a3 := float(fm[2][1]) * d3
	var l1 := 0.0
	var b1 := 0.0
	var l2 := 0.0
	var b2 := 0.0
	var l3 := 0.0
	var b3 := 0.0
	# Vibrato LFO (5.1 Hz) + slow drift (0.21 Hz) as rotating phasors.
	var vs := 0.0
	var vc := 1.0
	var vr_c := cos(TAU * 5.1 / SR * 16.0)
	var vr_s := sin(TAU * 5.1 / SR * 16.0)
	var ds := 0.0
	var dc := 1.0
	var dr_c := cos(TAU * 0.21 / SR * 16.0)
	var dr_s := sin(TAU * 0.21 / SR * 16.0)
	var atk_n := maxf(atk * SR, 1.0)
	var rel_n := maxf(rel * SR, 1.0)
	var rel_start := float(n) - rel_n
	var norm := 1.0 / sqrt(float(nv))
	for i in n:
		if (i & 15) == 0:
			# Control-rate update: LFOs, glide, per-voice increments.
			var ns := vs * vr_c + vc * vr_s
			vc = vc * vr_c - vs * vr_s
			vs = ns
			var ms := ds * dr_c + dc * dr_s
			dc = dc * dr_c - ds * dr_s
			ds = ms
			var x := float(i) / float(n)
			var gl := lerpf(glide_from, glide_to, _smooth(x / 0.7))
			for v in nv:
				var lfo := vs * ca[v] + vc * cb[v]
				var drift := ds * cb[v] - dc * ca[v]
				d[v] = int(base[v] * gl * (1.0 + dep[v] * lfo + 0.002 * drift))
		var src := 0.0
		for v in nv:
			var qq := (q[v] + d[v]) & PHASE_MASK
			q[v] = qq
			src += _saw_tab[qq >> 16]
		src = src * norm + breath * (_rng.randf() * 2.0 - 1.0)
		l1 += g1 * b1
		var h1 := src - l1 - d1 * b1
		b1 += g1 * h1
		l2 += g2 * b2
		var h2 := src - l2 - d2 * b2
		b2 += g2 * h2
		l3 += g3 * b3
		var h3 := src - l3 - d3 * b3
		b3 += g3 * h3
		var env := 1.0
		if i < atk_n:
			var u := float(i) / atk_n
			env = u * u * (3.0 - 2.0 * u)
		if i > rel_start:
			var r := (float(i) - rel_start) / rel_n
			env *= (1.0 - r) * (1.0 - r)
		a[i] = (b1 * a1 + b2 * a2 + b3 * a3) * env * 0.5
	return a


## Church bell: inharmonic partials (hum, prime, tierce, quint, nominal...) with a strike.
func _tpl_bell(f: float, decay: float, bright: float) -> PackedFloat32Array:
	var n := int(decay * 3.2 * SR)
	var a := PackedFloat32Array()
	a.resize(n)
	var np := BELL_RATIOS.size()
	var incs := PackedInt64Array()
	var gains := PackedFloat32Array()
	var ks := PackedFloat32Array()
	var es := PackedFloat32Array()
	var qs := PackedInt64Array()
	for p in np:
		var fr := f * float(BELL_RATIOS[p])
		if fr > SR * 0.42:
			continue
		incs.append(_phase_inc(fr * (1.0 + _rng.randf_range(-0.002, 0.002))))
		var g := float(BELL_GAINS[p])
		if p >= 4:
			g *= bright
		gains.append(g)
		ks.append(exp(-1.0 / (decay * float(BELL_DECAYS[p]) * SR)))
		es.append(1.0)
		qs.append(0)
	var m := incs.size()
	for i in n:
		var v := 0.0
		for p in m:
			var qq := (qs[p] + incs[p]) & PHASE_MASK
			qs[p] = qq
			v += _sin_tab[qq >> 16] * es[p] * gains[p]
			es[p] *= ks[p]
		var atk := minf(1.0, float(i) / 40.0)
		var tail := minf(1.0, float(n - i) / 512.0)
		a[i] = v * atk * tail * 0.4
	# Strike transient.
	var strike := int(0.025 * SR)
	for i in mini(strike, n):
		a[i] += (_rng.randf() * 2.0 - 1.0) * 0.25 * bright * (1.0 - float(i) / strike)
	return a


# ---------------------------------------------------------------- music

## Legacy GDScript music (scripts/audio/sfx_legacy_music.gd). MusicManager owns music, so this
## returns null whenever that autoload is registered and the slow synthesis never runs.
func _render_track(track: StringName) -> AudioStreamWAV:
	if ProjectSettings.has_setting("autoload/MusicManager"):
		return null
	return LEGACY_MUSIC.new(self).render_track(track)


# ---------------------------------------------------------------- stream conversion

func _to_stream(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n := data.size()
	var s: AudioStreamWAV = null
	if _float_wav >= 0:
		s = _from_float_wav(data)
		if s == null or s.data.size() < n:
			s = null
			_float_wav = -1
		else:
			_float_wav = 1
	if s == null:
		var bytes := PackedByteArray()
		bytes.resize(n * 2)
		for i in n:
			bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))
		s = AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = SR
		s.stereo = false
		s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = n
	else:
		s.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return s


## Fast path: wrap the floats in a 32-bit IEEE-float WAV and let the engine convert in C++.
func _from_float_wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var pcm := data.to_byte_array()
	var wav := PackedByteArray()
	wav.resize(44)
	wav.encode_u32(0, 0x46464952)  # "RIFF"
	wav.encode_u32(4, 36 + pcm.size())
	wav.encode_u32(8, 0x45564157)  # "WAVE"
	wav.encode_u32(12, 0x20746d66)  # "fmt "
	wav.encode_u32(16, 16)
	wav.encode_u16(20, 3)  # IEEE float
	wav.encode_u16(22, 1)  # mono
	wav.encode_u32(24, SR)
	wav.encode_u32(28, SR * 4)
	wav.encode_u16(32, 4)
	wav.encode_u16(34, 32)
	wav.encode_u32(36, 0x61746164)  # "data"
	wav.encode_u32(40, pcm.size())
	wav.append_array(pcm)
	return AudioStreamWAV.load_from_buffer(wav, WAV_OPTIONS)
