extends SceneTree
## Headless smoke test for MusicManager (music role).
##   godot --headless --path . -s res://tools/music/music_check.gd
## Checks buses, every stem (length, tiling, loop), aliases, bar-quantized switching, intensity
## overrides, boss-track mapping + phase layers, stinger events and the run-end path.
## Prints "MUSIC CHECK OK" or the failures.

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		printerr("FAIL: ", msg)


## `-- --run`: a real run on main.tscn: map theme starts, the player dies, the end screen
## starts the defeat dirge.
func _check_real_run(mm: Node) -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await create_timer(4.0).timeout
	_check(String(mm.get(&"current_track")).begins_with("battle_"), "run did not start a map theme (%s)" % mm.get(&"current_track"))
	var game: Node = root.get_node(^"Game")
	for i in 60:
		var p: Node = game.get(&"player")
		if p == null or not is_instance_valid(p) or float(p.get(&"hp")) <= 0.0:
			break
		p.call(&"take_damage", 9999.0)
		await create_timer(0.25).timeout
	await create_timer(5.0).timeout  # end screen opens ~2 s after death
	_check(mm.get(&"current_track") == &"defeat", "game over did not start the dirge (%s)" % mm.get(&"current_track"))


## A stand-in boss: MusicManager duck-types data / phase_index / is_enraged.
class FakeBoss extends Node3D:
	var data: Resource
	var phase_index := 0
	var is_enraged := false


func _run() -> void:
	var mm: Node = root.get_node_or_null(^"MusicManager")
	_check(mm != null, "MusicManager autoload missing")
	if mm == null:
		quit(1)
		return
	for bus: StringName in [&"Master", &"Music", &"SFX", &"UI", &"Ambience", &"MusicStingers"]:
		_check(AudioServer.get_bus_index(bus) != -1, "bus missing: %s" % bus)
	var tracks: Dictionary = mm.get(&"_tracks")
	_check(tracks.size() >= 30, "expected >= 30 tracks, got %d" % tracks.size())
	var total_bytes := 0
	var counted := {}
	for id: StringName in tracks:
		var info: Dictionary = tracks[id]
		for s: Dictionary in info["stems"]:
			var wav: AudioStreamWAV = mm.call(&"_get_stream", id, s)
			_check(wav != null, "stem failed to load: %s" % s["file"])
			if wav == null:
				continue
			if not counted.has(s["file"]):  # layered variants reference other tracks' stems
				counted[s["file"]] = true
				total_bytes += FileAccess.get_file_as_bytes(String(s["file"])).size()
			var frames := int(round(wav.get_length() * wav.mix_rate))
			_check(absi(frames - int(s["samples"])) <= 1, "%s length %d != manifest %d" % [s["file"], frames, int(s["samples"])])
			if info["loop"]:
				# Stems written at a lower rate (single-stem tracks only) have nothing to tile against.
				if int(s.get("mix_rate", info["mix_rate"])) == int(info["mix_rate"]):
					_check(int(info["samples"]) % int(s["samples"]) == 0, "%s does not tile the track" % s["file"])
				else:  # lower-rate stem: its loop must still divide the track's length in time
					var secs := float(s["samples"]) / float(s["mix_rate"])
					var track_secs := float(info["samples"]) / float(info["mix_rate"])
					var reps := roundf(track_secs / secs)
					_check(info["stems"].size() == 1 or absf(reps * secs - track_secs) < 0.002,
							"%s does not tile the track in time" % s["file"])
				_check(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s not looping" % s["file"])
	_check(total_bytes < 25000000, "music WAVs are %.2f MB (budget 25 MB)" % (total_bytes / 1e6))
	print("music source size: %.2f MB" % (total_bytes / 1e6))
	for alias: StringName in [&"menu", &"backyard", &"battle_city", &"battle_unknown_map", &"boss",
			&"defeat", &"run_end", &"game_over"]:
		_check(mm.call(&"has_track", alias), "alias not resolved: %s" % alias)
	_check(not mm.call(&"has_track", &"nonsense"), "nonsense track should not resolve")

	# Every loop track plays (unquantized).
	for id: StringName in tracks:
		if tracks[id]["loop"]:
			mm.call(&"play", id, 0.2, &"none")
			await create_timer(0.25).timeout
			_check(mm.get(&"current_track") == id, "play(%s) did not switch" % id)
	# Bar-quantized switch: queued now, swapped within one (half) bar.
	mm.call(&"play", &"battle_city", 0.1, &"none")
	await create_timer(0.5).timeout
	mm.call(&"play", &"battle_gardens", 0.3, &"bar")
	_check(mm.get(&"current_track") == &"battle_gardens", "quantized play did not set current_track")
	await create_timer(3.2).timeout
	var decks: Array = mm.get(&"_decks")
	var active: int = mm.get(&"_active")
	_check(active >= 0 and decks[active].track == &"battle_gardens", "quantized switch never happened")

	for lvl in [1, 2, 0]:
		mm.call(&"set_intensity_override", lvl)
		await create_timer(0.6).timeout
		_check(mm.get(&"intensity") == lvl, "intensity override %d not applied" % lvl)
	mm.call(&"set_intensity_override", -1)

	# Boss mapping by EnemyData file name, and phase layers.
	var boss := FakeBoss.new()
	boss.data = load("res://data/bosses/grand_inquisitor.tres")
	_check(mm.call(&"_boss_track", boss) == &"boss_inquisitor", "grand_inquisitor -> boss_inquisitor")
	boss.data = load("res://data/bosses/sariel.tres")
	_check(mm.call(&"_boss_track", boss) == &"boss_sariel", "sariel -> boss_sariel")
	for pair in [["war_chariot", &"boss_chariot"], ["storm_archon", &"boss_tempest"],
			["gilded_seraph", &"boss_aurum"], ["cantor", &"boss_cantor"], ["gate_archon", &"boss_archon"], ["frost_abbot", &"boss_abbot"], ["dawn_wyrm", &"boss_wyrm"],
			["verdant_matriarch", &"boss_verdance"]]:
		boss.data = load("res://data/bosses/%s.tres" % pair[0])
		_check(mm.call(&"_boss_track", boss) == pair[1], "%s -> %s" % pair)
	for key: StringName in [&"battle_breach", &"boss_chariot", &"boss_tempest", &"boss_aurum", &"boss_cantor", &"battle_isles", &"battle_spire", &"battle_gate", &"battle_wastes", &"run_won",
			&"ending_climb", &"ending_sit", &"ending_break", &"basecamp_ended"]:
		_check(tracks.has(key), "track missing: %s" % key)
	mm.set(&"_boss", boss)
	_check(not mm.call(&"_stem_wanted", "phase2"), "phase2 on in phase 0")
	boss.phase_index = 2
	_check(mm.call(&"_stem_wanted", "phase3"), "phase3 off in phase 2")
	mm.set(&"_boss", null)
	boss.free()

	# Stinger events: priority and cooldown.
	# (beat-quantized: with a track playing they queue for the next beat, which still counts)
	_check(mm.call(&"stinger", &"objective_complete"), "objective stinger did not play")
	_check(not mm.call(&"stinger", &"purchase"), "a purchase must not cut an objective stinger")
	_check(not mm.call(&"stinger", &"objective_complete"), "stinger cooldown ignored")
	_check(not mm.call(&"stinger", &"relic_common"), "relic stingers should be off by default")
	await create_timer(1.0).timeout
	_check(mm.get(&"_pending_stinger").is_empty(), "queued stinger never fired")
	for ev: StringName in [&"objective_complete", &"purchase", &"boss_defeated"]:
		var defs: Dictionary = mm.get(&"_config")["stingers"]
		_check(mm.call(&"resolve", StringName(defs[String(ev)]["track"])) != &"", "stinger track missing: %s" % ev)

	# Staged ending: climb, layers, resolution.
	mm.call(&"_on_dialogue_event_triggered", "stage_climb", "ending")
	await create_timer(0.3).timeout
	_check(mm.get(&"current_track") == &"ending_climb", "stage_climb did not start the climb")
	mm.call(&"_on_dialogue_event_triggered", "stage_archons", "ending")
	_check(mm.call(&"_stem_wanted", "archons") and not mm.call(&"_stem_wanted", "throne"), "archons layer")
	mm.call(&"_on_dialogue_event_triggered", "stage_sit", "ending")
	await create_timer(0.3).timeout
	_check(mm.get(&"current_track") == &"" and mm.get(&"_stinger").playing, "stage_sit did not cut to its resolution")
	# Run end: run won theme, then the defeat dirge.
	mm.call(&"play_run_end", true)
	await create_timer(0.3).timeout
	_check(mm.get(&"current_track") == &"run_won", "run end (victory) did not start run_won")
	mm.call(&"play_run_end", false)
	await create_timer(0.3).timeout
	_check(mm.get(&"current_track") == &"defeat", "run end (defeat) did not start the dirge")
	mm.call(&"stop", 0.2)
	await create_timer(0.5).timeout
	_check(mm.get(&"current_track") == &"", "stop() left a track")
	if "--run" in OS.get_cmdline_user_args():
		await _check_real_run(mm)
	print("MUSIC CHECK OK" if _fails == 0 else "MUSIC CHECK FAILED (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
