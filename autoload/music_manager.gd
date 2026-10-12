extends Node
## Adaptive music (autoload "MusicManager"). Owned by the music role, see docs/team/music.md.
##
## Every track is a set of sample-locked, seamlessly looping stems rendered offline by
## tools/music/gen_music.py into res://assets/audio/music/ (listed in manifest.json). A track
## plays as one AudioStreamSynchronized, so stems never drift (a 4-bar stem simply loops twice
## per 8-bar stem); layers fade in and out by changing per-stem volume. Switching tracks waits
## for the playing track's next bar (or beat) line, then crossfades two decks.
##
## Stem roles: "base" (always on), "combat" (intensity >= COMBAT), "frenzy" (intensity >= FRENZY),
## "enrage" (the boss is enraged / below half HP), "phase2" / "phase3" (boss phase_index >= 1 / 2),
## "archons" / "throne" (staged ending: after the stage_archons / stage_throne dialogue events).
##
## Story: the staged ending (scenes/dialogue/ending_stage.tscn) plays ending_climb; its stage_sit /
## stage_break events cut to the ending_sit / ending_break resolutions; once
## Dialogue.has_flag("story.ended") the hub plays basecamp_ended. Stingers start on the next beat.
##
## API:
##   MusicManager.play(&"basecamp")           # track id or alias (menu, backyard, battle, boss...)
##   MusicManager.play(&"boss", 1.0, &"beat") # custom crossfade, quantize &"bar"/&"beat"/&"none"
##   MusicManager.stop(2.0)
##   MusicManager.has_track(&"battle_city") -> bool   (aliases count)
##   MusicManager.stinger(&"relic_rare")      # named event from music.json "stingers"
##   MusicManager.play_stinger(&"victory")    # any one-shot track; the music ducks under it
##   MusicManager.play_run_end(victory)       # defeat dirge, or the "run won" theme
##   MusicManager.duck(-6.0, 2.0)             # dip the music (Sfx uses this under big sounds)
##   MusicManager.set_intensity_override(MusicManager.FRENZY)  # -1 = automatic (default)
##   MusicManager.bump(MusicManager.COMBAT, 10.0)  # at least this level for N seconds
##   MusicManager.intensity -> int, MusicManager.current_track -> StringName
##   signals track_changed(track), intensity_changed(level), stinger_played(event)
## Sfx.play_music()/stop_music()/has_track() forward here; Sfx.play_music(&"run_end") (the game
## over screen) plays the defeat dirge or the victory stinger.
##
## Automatic hooks (all optional; each is skipped if the emitter does not exist):
##   Game.boss_spawned/boss_died, Game.objective_started/completed, Game.player_hit/enemy_died,
##   RunState.wave_started (surge -> bump) / run_ended (death -> fade), Player.leveled_up,
##   Progression.relic_gained (stinger by rarity; off by default), Meta/Progression.upgrade_bought
##   (hub purchase), Dialogue.event_triggered (stage_* events of the ending).
##   While the tree is paused the Music bus is low-passed and dipped; stingers play on their own
##   "MusicStingers" bus so a level-up or purchase stinger stays clear.

signal track_changed(track: StringName)
signal intensity_changed(level: int)
signal stinger_played(event: StringName)

const CALM := 0
const COMBAT := 1
const FRENZY := 2

const MANIFEST_PATH := "res://assets/audio/music/manifest.json"
const CONFIG_PATH := "res://data/music/music.json"
const BUS := &"Music"
## Stingers bypass the pause muffle; this bus mirrors the Music bus volume and mute.
const STINGER_BUS := &"MusicStingers"
## Headroom so the loudest full mix sits a little under the SFX.
const BASE_DB := -2.0
const SILENT_DB := -60.0
## Pause muffle: Music bus low-pass cutoff and dip while the tree is paused.
const PAUSED_CUTOFF := 900.0
const OPEN_CUTOFF := 20000.0
const PAUSED_DIP_DB := -5.0
## How fast ducks glide in and out (dB per second).
const DUCK_RATE := 24.0
const INTENSITY_POLL := 0.4
const RARITY_IDS: Array[StringName] = [&"common", &"uncommon", &"rare", &"epic", &"legendary"]

## Current intensity level (CALM / COMBAT / FRENZY).
var intensity := CALM
## Track id that is playing or queued to start at the next bar line, &"" when silent.
var current_track: StringName = &""

var _tracks := {}  # StringName -> manifest Dictionary
var _config := {}
var _streams := {}  # file path -> AudioStreamWAV
var _decks: Array[Deck] = []
var _active := -1  # index into _decks of the current deck
var _pending := {}  # queued switch: {id, fade, at}
var _stinger: AudioStreamPlayer
var _stinger_prio := -1
var _stinger_until := 0.0
var _stinger_last := {}  # event -> _clock of last play (cooldowns)
var _duck_db := 0.0
var _duck_until := 0.0
var _duck_now := 0.0  # smoothed duck level actually applied
var _override := -1
var _bump_level := CALM
var _bump_until := 0.0
var _poll_t := 0.0
var _lower_since := -1.0
var _last_hit := -100.0
var _kill_times: PackedFloat64Array = PackedFloat64Array()
var _boss: Node = null
var _map_track: StringName = &""  # track to return to after the boss
var _music_bus := -1
var _stinger_bus := -1
var _lowpass: AudioEffectLowPassFilter
var _muffle := 0.0  # 0 open .. 1 fully muffled
var _clock := 0.0  # unscaled seconds since start
var _hooked_player: Node = null  # player whose leveled_up we listen to
var _pending_stinger := {}  # stinger waiting for the next beat: {event, track, duck, prio, at}
## Staged ending progress: 0 none, 1 climbing, 2 archons, 3 throne (drives the climb layers).
var _ending_step := 0


## One playback deck: a player + the synchronized stream of a track and its stem gains.
class Deck:
	var player: AudioStreamPlayer
	var sync: AudioStreamSynchronized
	var track: StringName = &""
	var roles: PackedStringArray = PackedStringArray()
	var stem_gain := PackedFloat32Array()
	var gain := 0.0
	var target := 0.0
	var fade_rate := 1.0  # gain units per second
	var started := 0.0  # _clock when it started (fallback beat clock)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_json()
	_setup_bus()
	for i in 2:
		var d := Deck.new()
		d.player = AudioStreamPlayer.new()
		d.player.bus = BUS
		d.player.volume_db = -80.0
		add_child(d.player)
		_decks.append(d)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = STINGER_BUS
	add_child(_stinger)
	_prefetch()
	Game.boss_spawned.connect(_on_game_boss_spawned)
	Game.boss_died.connect(_on_game_boss_died)
	Game.player_hit.connect(_on_game_player_hit)
	Game.enemy_died.connect(_on_game_enemy_died)
	_connect_optional(Game, &"objective_started", _on_game_objective_started)
	_connect_optional(Game, &"objective_completed", _on_game_objective_completed)
	get_tree().node_added.connect(_on_tree_node_added)
	_connect_autoloads.call_deferred()
	_check_current_scene.call_deferred()
	if "--music-log" in OS.get_cmdline_user_args():  # dev: `godot --path . -- --music-log`
		track_changed.connect(func(t: StringName) -> void: print("[music] track -> ", t))
		intensity_changed.connect(func(l: int) -> void: print("[music] intensity -> ", l))
		stinger_played.connect(func(e: StringName) -> void: print("[music] stinger ", e))


func _process(delta: float) -> void:
	# Real (unscaled) time: hitstop and pause must not stall fades.
	var dt := minf(delta / maxf(Engine.time_scale, 0.001), 0.1) if Engine.time_scale > 0.0 else 0.016
	_clock += dt
	_poll_t -= dt
	if _poll_t <= 0.0:
		_poll_t = INTENSITY_POLL
		_update_intensity()
		_hook_player()
	if not _pending.is_empty() and _clock >= float(_pending.at):
		var p := _pending
		_pending = {}
		_switch_now(p.id, p.fade)
	if not _pending_stinger.is_empty() and _clock >= float(_pending_stinger.at):
		var s := _pending_stinger
		_pending_stinger = {}
		_fire_stinger(s)
	_update_decks(dt)
	_update_muffle(dt)
	_mirror_stinger_bus()


# ================================================================ public API

## Plays a track (id or alias). The switch waits for the current track's next bar line
## (`quantize` &"bar" / &"beat" / &"none"; &"" = config default), then crossfades over `fade` s.
## Re-requesting the playing track is a no-op. The special alias &"run_end" calls play_run_end().
func play(track: StringName, fade: float = -1.0, quantize: StringName = &"") -> void:
	if track == &"run_end":
		play_run_end(_run_won())
		return
	var id := resolve(track)
	if id == &"":
		return
	if fade < 0.0:
		fade = float(_config.get("crossfade", 2.5))
	if id == current_track:
		var live := _active >= 0 and _decks[_active].track == id and _decks[_active].target > 0.0
		if live or (not _pending.is_empty() and _pending.id == id):
			return
	current_track = id
	if _is_map_track(id):
		_map_track = id
	track_changed.emit(id)
	if quantize == &"":
		quantize = StringName(_config.get("quantize", "bar"))
	var wait := _time_to_boundary(quantize)
	if wait <= 0.03:
		_pending = {}
		_switch_now(id, fade)
	else:
		_pending = {"id": id, "fade": fade, "at": _clock + wait}


## Fades all music out (cancels a queued switch).
func stop(fade: float = 2.0) -> void:
	_pending = {}
	for d in _decks:
		d.target = 0.0
		d.fade_rate = 1.0 / maxf(fade, 0.05)
	if current_track != &"":
		current_track = &""
		track_changed.emit(&"")


## End of a run (the game over / victory screen): the looping "run won" theme or the defeat dirge.
func play_run_end(victory: bool) -> void:
	if victory:
		var won := StringName(_config.get("run_won_track", "run_won"))
		if _tracks.has(won):
			play(won, 2.0, &"beat")
		else:
			stop(2.5)
			stinger(&"boss_defeated")
	else:
		play(&"defeat", 3.0, &"none")


## True if `track` (or the track an alias points to) exists.
func has_track(track: StringName) -> bool:
	return track == &"run_end" or resolve(track) != &""


## Track id for a name or alias, or &"" if unknown.
func resolve(track: StringName) -> StringName:
	if _tracks.has(track):
		# The map loader asks for the map JSON's "music"; music.json map_tracks may override it.
		var def := _current_map_def(true)
		if not def.is_empty() and StringName(def.get("music", "")) == track:
			var over := StringName(_config.get("map_tracks", {}).get(String(def.get("id", "")), ""))
			if _tracks.has(over):
				return over
		return _story_variant(track)
	var aliases: Dictionary = _config.get("aliases", {})
	var a := String(aliases.get(String(track), ""))
	if a == "@menu":
		if _in_ending():
			return _ending_track()
		return _story_variant(&"basecamp") if _in_basecamp() and _tracks.has(&"basecamp") else &"title"
	if a == "@map":
		return _map_music()
	if a != "" and _tracks.has(StringName(a)):
		return StringName(a)
	# Unknown battle_* ids (a map nobody wrote a theme for yet) get the default map theme.
	if String(track).begins_with("battle_"):
		return _default_map_track()
	return &""


## Plays a named stinger event from music.json "stingers" (cooldown + priority aware), on the
## playing track's next beat. Returns true if it played or is queued for that beat.
func stinger(event: StringName) -> bool:
	var defs: Dictionary = _config.get("stingers", {})
	var def: Dictionary = defs.get(String(event), {})
	if def.is_empty() or resolve(StringName(def.get("track", ""))) == &"":
		return false
	var last := float(_stinger_last.get(event, -100.0))
	if _clock - last < float(def.get("cooldown", 0.5)):
		return false
	var prio := int(def.get("priority", 0))
	# A more important stinger still ringing (or queued) is not cut off.
	if _stinger.playing and _clock < _stinger_until and prio < _stinger_prio:
		return false
	if not _pending_stinger.is_empty() and prio < int(_pending_stinger.prio):
		return false
	_stinger_last[event] = _clock
	var s := {"event": event, "track": StringName(def.get("track", "")),
			"duck": float(def.get("duck", -6.0)), "prio": prio}
	var wait := _time_to_boundary(&"beat")
	if wait <= 0.03:
		_fire_stinger(s)
	else:
		s["at"] = _clock + wait
		_pending_stinger = s
	return true


func _fire_stinger(s: Dictionary) -> void:
	if play_stinger(s.track, s.duck):
		_stinger_prio = int(s.prio)
		stinger_played.emit(s.event)


## One-shot stinger (non-looping track, e.g. &"victory"); the music ducks under it.
func play_stinger(track: StringName, duck_db: float = -12.0) -> bool:
	var id := resolve(track)
	if id == &"":
		return false
	var stems: Array = _tracks[id].get("stems", [])
	if stems.is_empty():
		return false
	var stream := _get_stream(id, stems[0])
	if stream == null:
		return false
	_stinger.stream = stream
	_stinger.volume_db = BASE_DB
	_stinger.play()
	_stinger_until = _clock + stream.get_length()
	duck(duck_db, minf(stream.get_length() * 0.8, 6.0))
	return true


## Ducks the music by `duck_db` for `seconds` (Sfx calls this under big sounds: boss stinger,
## evolutions, legendary relics...). Overlapping ducks keep the deeper level and the later end.
func duck(duck_db: float, seconds: float) -> void:
	if _clock >= _duck_until or duck_db < _duck_db:
		_duck_db = duck_db
	_duck_until = maxf(_duck_until, _clock + seconds)


## Forces an intensity level (CALM/COMBAT/FRENZY); -1 returns to automatic.
func set_intensity_override(level: int) -> void:
	_override = level
	_poll_t = 0.0


## Keeps intensity at least `level` for `seconds` (objective waves, ambushes, scripted events).
func bump(level: int, seconds: float) -> void:
	if level >= _bump_level or _clock >= _bump_until:
		_bump_level = level
	_bump_until = maxf(_bump_until, _clock + seconds)
	_poll_t = 0.0


# ================================================================ loading

func _load_json() -> void:
	var m: Variant = _read_json(MANIFEST_PATH)
	if m is Dictionary:
		var tracks: Dictionary = m.get("tracks", {})
		for k: String in tracks:
			_tracks[StringName(k)] = tracks[k]
	else:
		push_warning("MusicManager: missing %s (run tools/music/gen_music.py)" % MANIFEST_PATH)
	var c: Variant = _read_json(CONFIG_PATH)
	_config = c if c is Dictionary else {}


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Starts threaded loads of every stem so later switches never hitch.
func _prefetch() -> void:
	for id: StringName in _tracks:
		for s: Dictionary in _tracks[id].get("stems", []):
			var path := String(s.get("file", ""))
			if ResourceLoader.exists(path):
				ResourceLoader.load_threaded_request(path, "AudioStreamWAV")


func _get_stream(id: StringName, stem: Dictionary) -> AudioStreamWAV:
	var path := String(stem.get("file", ""))
	if _streams.has(path):
		return _streams[path]
	if not ResourceLoader.exists(path):
		return null
	var res: Resource
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		res = ResourceLoader.load_threaded_get(path)  # blocks only if still loading
	if res == null:
		res = load(path)
	var wav := res as AudioStreamWAV
	if wav == null:
		return null
	var info: Dictionary = _tracks[id]
	if info.get("loop", true):
		# Enforce a sample-exact forward loop (the WAV 'smpl' chunk says the same; this guards
		# against importer settings). Stem lengths are whole bars dividing the track length, so
		# stems of one track stay locked.
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(stem.get("samples", info.get("samples", 0)))
	_streams[path] = wav
	return wav


# ================================================================ decks

## Seconds until the active deck's next bar (or beat) line; 0 if nothing rhythmic is playing.
func _time_to_boundary(quantize: StringName) -> float:
	if quantize == &"none" or _active < 0:
		return 0.0
	var d := _decks[_active]
	if d.track == &"" or d.target <= 0.0 or not d.player.playing:
		return 0.0
	var info: Dictionary = _tracks.get(d.track, {})
	if not info.get("loop", false) or float(info.get("bpm", 0.0)) <= 0.0:
		return 0.0
	var beat := 60.0 / float(info.bpm)
	var quantum := beat
	if quantize == &"bar":
		quantum = beat * float(info.get("beats_per_bar", 4))
		if quantum > float(_config.get("max_bar_wait", 2.8)):
			quantum *= 0.5  # slow tracks: half bars
	var pos := d.player.get_playback_position()
	if pos <= 0.0:  # some drivers report 0: fall back to our own clock since the deck started
		pos = _clock - d.started
	return quantum - fmod(pos, quantum)


func _switch_now(id: StringName, fade: float) -> void:
	var deck := _start_deck(id)
	if deck == null:
		return
	for d in _decks:
		if d != deck and d.track != &"":
			d.target = 0.0
			d.fade_rate = 1.0 / maxf(fade, 0.05)
	deck.target = 1.0
	deck.fade_rate = 1.0 / maxf(fade, 0.05)


func _start_deck(id: StringName) -> Deck:
	# Reuse a deck that is still fading this same track out (no restart, just fade back up).
	for i in _decks.size():
		if _decks[i].track == id and _decks[i].player.playing:
			_active = i
			return _decks[i]
	var idx := 0 if _active < 0 else 1 - _active
	# Prefer the quieter deck for the new track.
	if _active >= 0 and _decks[idx].gain > _decks[1 - idx].gain:
		idx = 1 - idx
	var deck := _decks[idx]
	var stems: Array = _tracks[id].get("stems", [])
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = stems.size()
	var roles := PackedStringArray()
	var gains := PackedFloat32Array()
	for i in stems.size():
		var s := _get_stream(id, stems[i])
		if s == null:
			push_warning("MusicManager: cannot load stem %s" % stems[i].get("file", "?"))
			return null
		sync.set_sync_stream(i, s)
		var role := String(stems[i].get("role", "base"))
		roles.append(role)
		var g := 1.0 if _stem_wanted(role) else 0.0
		gains.append(g)
		sync.set_sync_stream_volume(i, _gain_db(g))
	deck.sync = sync
	deck.roles = roles
	deck.stem_gain = gains
	deck.track = id
	deck.gain = 0.0
	deck.player.stop()
	deck.player.stream = sync
	deck.player.volume_db = -80.0
	deck.player.play()
	deck.started = _clock
	_active = idx
	return deck


func _update_decks(dt: float) -> void:
	var tune: Dictionary = _config.get("intensity", {})
	var fade_in := 1.0 / maxf(float(tune.get("stem_fade_in", 1.2)), 0.05)
	var fade_out := 1.0 / maxf(float(tune.get("stem_fade_out", 3.5)), 0.05)
	# Duck glides (DUCK_RATE dB/s) so sfx-triggered dips do not click in and out.
	_duck_now = move_toward(_duck_now, _duck_db if _clock < _duck_until else 0.0, DUCK_RATE * dt)
	var duck_db := _duck_now + PAUSED_DIP_DB * _muffle
	for d in _decks:
		if d.track == &"":
			continue
		d.gain = move_toward(d.gain, d.target, d.fade_rate * dt)
		if d.gain <= 0.0 and d.target <= 0.0:
			d.player.stop()
			d.track = &""
			continue
		# Equal-power-ish curve so crossfades do not dip in the middle.
		d.player.volume_db = linear_to_db(maxf(sin(d.gain * PI * 0.5), 0.0001)) + BASE_DB + duck_db
		for i in d.roles.size():
			var want := 1.0 if _stem_wanted(d.roles[i]) else 0.0
			var g := d.stem_gain[i]
			if g != want:
				g = move_toward(g, want, (fade_in if want > g else fade_out) * dt)
				d.stem_gain[i] = g
				d.sync.set_sync_stream_volume(i, _gain_db(g))


func _stem_wanted(role: String) -> bool:
	match role:
		"combat":
			return intensity >= COMBAT
		"frenzy":
			return intensity >= FRENZY
		"enrage":
			return _boss_enraged()
		"phase2":
			return _boss_phase() >= 1
		"phase3":
			return _boss_phase() >= 2
		"archons":
			return _ending_step >= 2
		"throne":
			return _ending_step >= 3
	return true


func _gain_db(g: float) -> float:
	# Perceptual fade: squared gain feels even, floored at SILENT_DB.
	return maxf(linear_to_db(maxf(g * g, 0.000001)), SILENT_DB) if g > 0.0 else SILENT_DB


# ================================================================ intensity

func _update_intensity() -> void:
	if _override >= 0:  # scripted: apply at once, no hold
		_set_intensity(_override)
		_lower_since = -1.0
		return
	var level := _wanted_intensity()
	if level > intensity:
		_set_intensity(level)
		_lower_since = -1.0
	elif level < intensity:
		# Drop one step at a time, only after the lower level has been wanted for `hold` s.
		var hold := float(_config.get("intensity", {}).get("hold", 8.0))
		if _lower_since < 0.0:
			_lower_since = _clock
		elif _clock - _lower_since >= hold:
			_set_intensity(intensity - 1)
			_lower_since = _clock
	else:
		_lower_since = -1.0


func _set_intensity(level: int) -> void:
	if level == intensity:
		return
	intensity = level
	intensity_changed.emit(level)


func _wanted_intensity() -> int:
	if _override >= 0:
		return _override
	var level := CALM
	if _clock < _bump_until:
		level = _bump_level
	var p := Game.player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return level
	var tune: Dictionary = _config.get("intensity", {})
	var near := _count_enemies_near(p.global_position, float(tune.get("radius", 24.0)))
	var now := _clock
	while not _kill_times.is_empty() and now - _kill_times[0] > 10.0:
		_kill_times.remove_at(0)
	var kills := _kill_times.size()
	var hp_ratio := 1.0
	var max_hp: Variant = p.get(&"max_hp")
	var hp: Variant = p.get(&"hp")
	if (max_hp is float or max_hp is int) and (hp is float or hp is int) and float(max_hp) > 0.0:
		hp_ratio = float(hp) / float(max_hp)
	if near >= int(tune.get("frenzy_enemies", 38)) or kills >= int(tune.get("kills_per_10s_frenzy", 40)):
		level = maxi(level, FRENZY)
	elif near >= int(tune.get("combat_enemies", 7)) or kills >= int(tune.get("kills_per_10s_combat", 6)) \
			or now - _last_hit < float(tune.get("hit_combat_seconds", 7.0)):
		level = maxi(level, COMBAT)
	if level >= COMBAT and hp_ratio < float(tune.get("low_hp_frenzy", 0.3)):
		level = FRENZY
	if _boss != null and is_instance_valid(_boss):
		level = maxi(level, COMBAT)
	return level


## Counts Enemy nodes under Game.world within `radius` (XZ) of `pos`.
func _count_enemies_near(pos: Vector3, radius: float) -> int:
	var world := Game.world
	if world == null or not is_instance_valid(world):
		return 0
	var r2 := radius * radius
	var n := 0
	# perf: the shared enemy list, not every child of the world (gems, FX, projectiles...).
	for c in Perf.enemies():
		if c is Enemy:
			var e := c as Node3D
			var dx := e.global_position.x - pos.x
			var dz := e.global_position.z - pos.z
			if dx * dx + dz * dz <= r2:
				n += 1
	return n


# ================================================================ boss

func _on_game_boss_spawned(boss: Node3D) -> void:
	_boss = boss
	var keep := _map_track
	play(_boss_track(boss), float(_config.get("boss_crossfade", 1.2)),
			StringName(_config.get("boss_quantize", "beat")))
	_map_track = keep


## Track for a boss: node property/meta `music_track`, else music.json boss_tracks[boss id]
## (id = the boss's EnemyData file name, e.g. "grand_inquisitor"), else boss_track.
func _boss_track(boss: Node) -> StringName:
	var custom: Variant = boss.get_meta(&"music_track") if boss.has_meta(&"music_track") else boss.get(&"music_track")
	if (custom is String or custom is StringName) and _tracks.has(StringName(custom)):
		return StringName(custom)
	var per_boss: Dictionary = _config.get("boss_tracks", {})
	for key in _boss_ids(boss):
		if per_boss.has(key) and _tracks.has(StringName(per_boss[key])):
			return StringName(per_boss[key])
	return resolve(StringName(_config.get("boss_track", "boss")))


func _boss_ids(boss: Node) -> PackedStringArray:
	var ids := PackedStringArray()
	var explicit: Variant = boss.get(&"boss_id")
	if explicit != null:
		ids.append(String(explicit))
	var data: Variant = boss.get(&"data")
	if data is Resource and (data as Resource).resource_path != "":
		ids.append((data as Resource).resource_path.get_file().get_basename())
	ids.append(String(boss.name).to_snake_case())
	return ids


func _on_game_boss_died(_position: Vector3) -> void:
	_boss = null
	stop(1.5)
	stinger(&"boss_defeated")
	# Bring the map theme back once the stinger has rung out (real time, ignores pause).
	await get_tree().create_timer(4.5, true, false, true).timeout
	if current_track == &"" and Game.player != null and is_instance_valid(Game.player) and not _run_over():
		play(_map_track if _map_track != &"" else _map_music(), 4.0, &"none")


func _boss_enraged() -> bool:
	if _boss == null or not is_instance_valid(_boss):
		return false
	var e: Variant = _boss.get(&"is_enraged")
	if e is bool:
		return e
	var hp: Variant = _boss.get(&"hp")
	var mx: Variant = _boss.get(&"max_hp")
	if (hp is float or hp is int) and (mx is float or mx is int) and float(mx) > 0.0:
		return float(hp) / float(mx) <= 0.5
	return false


## Boss phase (phase_index if the boss has one; else 0, or 2 once enraged).
func _boss_phase() -> int:
	if _boss == null or not is_instance_valid(_boss):
		return 0
	var p: Variant = _boss.get(&"phase_index")
	if p is int:
		return p
	return 2 if _boss_enraged() else 0


# ================================================================ gameplay hooks

## Hooks autoloads that may or may not exist (RunState, Progression, Meta), by name.
func _connect_autoloads() -> void:
	var rs := get_node_or_null(^"/root/RunState")
	_connect_optional(rs, &"wave_started", _on_run_state_wave_started)
	_connect_optional(rs, &"run_ended", _on_run_state_run_ended)
	var prog := get_node_or_null(^"/root/Progression")
	_connect_optional(prog, &"relic_gained", _on_progression_relic_gained)
	_connect_optional(prog, &"upgrade_bought", _on_upgrade_bought)
	_connect_optional(prog, &"unlocked", _on_unlocked)
	_connect_optional(get_node_or_null(^"/root/Meta"), &"upgrade_bought", _on_upgrade_bought)
	_connect_optional(get_node_or_null(^"/root/Dialogue"), &"event_triggered", _on_dialogue_event_triggered)


func _connect_optional(obj: Object, sig: StringName, callable: Callable) -> void:
	if obj != null and obj.has_signal(sig) and not obj.is_connected(sig, callable):
		obj.connect(sig, callable)


## Listens to the current player's level-ups (the player is recreated every run).
func _hook_player() -> void:
	var p := Game.player
	if p == null or not is_instance_valid(p) or p == _hooked_player:
		return
	_hooked_player = p
	_connect_optional(p, &"leveled_up", _on_player_leveled_up)


func _on_run_state_wave_started(_index: int, kind: StringName) -> void:
	if kind == &"surge":
		var tune: Dictionary = _config.get("intensity", {})
		bump(int(tune.get("surge_level", FRENZY)), float(tune.get("surge_seconds", 14.0)))


func _on_run_state_run_ended(result: Dictionary) -> void:
	if not bool(result.get("victory", false)):
		stop(2.0)  # death: the music drains away; the end screen starts the dirge


func _on_game_objective_started(_id: StringName) -> void:
	var tune: Dictionary = _config.get("intensity", {})
	bump(int(tune.get("objective_level", COMBAT)), float(tune.get("objective_seconds", 25.0)))


func _on_game_objective_completed(_id: StringName, _rewards: Dictionary) -> void:
	stinger(&"objective_complete")


func _on_progression_relic_gained(relic: Dictionary) -> void:
	var tier := clampi(int(relic.get("tier", 0)), 0, RARITY_IDS.size() - 1)
	stinger(StringName("relic_%s" % RARITY_IDS[tier]))


func _on_upgrade_bought(_id: StringName, _level: int) -> void:
	stinger(&"purchase")


func _on_unlocked(_id: StringName) -> void:
	stinger(&"purchase")


func _on_player_leveled_up() -> void:
	stinger(&"level_up")


## The staged ending (docs/team/story.md): stage_* events build the climb layers, and the choice
## lines (stage_sit / stage_break) cut to their resolution.
func _on_dialogue_event_triggered(event_name: String, _conv_id: String) -> void:
	var story: Dictionary = _config.get("story", {})
	var resolutions: Dictionary = story.get("resolutions", {})
	match event_name:
		"stage_climb":
			_ending_step = maxi(_ending_step, 1)
			play(_ending_track(), 2.0, &"none")
		"stage_archons":
			_ending_step = maxi(_ending_step, 2)
		"stage_throne":
			_ending_step = maxi(_ending_step, 3)
		_:
			if resolutions.has(event_name):
				_ending_step = 0
				stop(1.0)
				if play_stinger(StringName(resolutions[event_name]), 0.0):
					stinger_played.emit(StringName(event_name))


func _on_game_player_hit(_amount: float) -> void:
	_last_hit = _clock


func _on_game_enemy_died(_position: Vector3, _data: Resource) -> void:
	_kill_times.append(_clock)
	if _kill_times.size() > 200:
		_kill_times.remove_at(0)


func _run_won() -> bool:
	var rs := get_node_or_null(^"/root/RunState")
	return rs != null and rs.has_method(&"run_won") and bool(rs.call(&"run_won"))


func _run_over() -> bool:
	var rs := get_node_or_null(^"/root/RunState")
	return rs != null and rs.get(&"active") == false


# ================================================================ scene detection

func _on_tree_node_added(node: Node) -> void:
	if node.get_parent() == get_tree().root:
		_music_for_scene.call_deferred(node)


func _check_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene:
		_music_for_scene(scene)


func _music_for_scene(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node.scene_file_path == String(_config.get("story", {}).get("ending_scene", "")):
		_boss = null
		_ending_step = 1
		play(_ending_track(), 2.0, &"none")
		return
	_ending_step = 0
	var scene_tracks: Dictionary = _config.get("scene_tracks", {})
	var t := String(scene_tracks.get(node.scene_file_path, ""))
	if t == "":
		var group_tracks: Dictionary = _config.get("group_tracks", {})
		for g: String in group_tracks:
			if node.is_in_group(StringName(g)):
				t = String(group_tracks[g])
				break
	if t != "":
		_boss = null
		play(StringName(t), -1.0, &"none")
	elif node.name == &"Main":
		# A new run: reset run state, start calm on the map theme.
		_boss = null
		_kill_times.clear()
		_last_hit = -100.0
		_bump_until = 0.0
		_set_intensity(CALM)
		play(_map_music(), -1.0, &"none")


func _in_basecamp() -> bool:
	return get_tree().get_first_node_in_group(&"basecamp") != null


## The staged ending scene is loaded.
func _in_ending() -> bool:
	var scene := get_tree().current_scene
	var path := String(_config.get("story", {}).get("ending_scene", ""))
	return scene != null and path != "" and scene.scene_file_path == path


func _ending_track() -> StringName:
	return StringName(_config.get("story", {}).get("ending_track", "ending_climb"))


## The post-ending hub theme replaces "basecamp" once the story has ended.
func _story_variant(id: StringName) -> StringName:
	if id != &"basecamp":
		return id
	var story: Dictionary = _config.get("story", {})
	var variant := StringName(story.get("ended_basecamp", ""))
	var dlg := get_node_or_null(^"/root/Dialogue")
	if variant != &"" and _tracks.has(variant) and dlg != null and dlg.has_method(&"has_flag") \
			and bool(dlg.call(&"has_flag", String(story.get("ended_flag", "story.ended")))):
		return variant
	return id


func _default_map_track() -> StringName:
	var d := StringName(_config.get("default_map_track", "battle_sanctum"))
	return d if _tracks.has(d) else &""


func _is_map_track(id: StringName) -> bool:
	var info: Dictionary = _tracks.get(id, {})
	for s: Dictionary in info.get("stems", []):
		if s.get("role", "") == "combat":
			return true
	return false


## Music of the live map, else the selected map, else the default map theme. music.json
## "map_tracks" (map id -> track) overrides a map definition's "music".
func _map_music() -> StringName:
	var def := _current_map_def()
	if not def.is_empty():
		var over := StringName(_config.get("map_tracks", {}).get(String(def.get("id", "")), ""))
		if _tracks.has(over):
			return over
		for key: String in ["music", "music_fallback"]:
			var t := StringName(def.get(key, ""))
			if _tracks.has(t):
				return t
	return _default_map_track()


## Definition of the live map during a run, else (unless `live_only`) of the selected map.
## {} without Maps.
func _current_map_def(live_only: bool = false) -> Dictionary:
	var maps := get_node_or_null(^"/root/Maps")
	if maps == null:
		return {}
	var def: Variant = maps.get(&"current_def")
	if live_only:
		return def if def is Dictionary else {}
	if not (def is Dictionary) or (def as Dictionary).is_empty():
		def = maps.call(&"selected_def") if maps.has_method(&"selected_def") else {}
	return def if def is Dictionary else {}


# ================================================================ buses

func _setup_bus() -> void:
	_music_bus = _ensure_bus(BUS)
	for i in AudioServer.get_bus_effect_count(_music_bus):
		var fx := AudioServer.get_bus_effect(_music_bus, i)
		if fx is AudioEffectLowPassFilter:
			_lowpass = fx
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = OPEN_CUTOFF
		AudioServer.add_bus_effect(_music_bus, _lowpass, 0)
	# Most stems are mono (repo size). Their reverb is baked in; this light, fully spread room
	# only adds stereo width around them.
	var has_verb := false
	for i in AudioServer.get_bus_effect_count(_music_bus):
		has_verb = has_verb or AudioServer.get_bus_effect(_music_bus, i) is AudioEffectReverb
	if not has_verb:
		var verb := AudioEffectReverb.new()
		verb.room_size = 0.55
		verb.damping = 0.6
		verb.spread = 1.0
		verb.predelay_msec = 18.0
		verb.wet = 0.14
		verb.dry = 1.0
		verb.hipass = 0.2
		AudioServer.add_bus_effect(_music_bus, verb)
	_stinger_bus = _ensure_bus(STINGER_BUS)


func _ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	return idx


## The stinger bus follows the Music bus volume/mute (Sfx sets those from Settings).
func _mirror_stinger_bus() -> void:
	if _stinger_bus < 0 or _music_bus < 0:
		return
	AudioServer.set_bus_volume_db(_stinger_bus, AudioServer.get_bus_volume_db(_music_bus))
	AudioServer.set_bus_mute(_stinger_bus, AudioServer.is_bus_mute(_music_bus))


## Muffles the music while the game is paused (menus, level-up) and opens it back up.
func _update_muffle(dt: float) -> void:
	var want := 1.0 if get_tree().paused else 0.0
	if is_equal_approx(_muffle, want):
		return
	_muffle = move_toward(_muffle, want, dt * (2.5 if want > _muffle else 1.5))
	if _lowpass:
		# Exponential sweep sounds even across the spectrum.
		_lowpass.cutoff_hz = OPEN_CUTOFF * pow(PAUSED_CUTOFF / OPEN_CUTOFF, _muffle)
