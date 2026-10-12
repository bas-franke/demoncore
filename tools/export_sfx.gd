extends SceneTree
## Renders every procedural sound of the Sfx autoload to .wav files for auditioning, and prints
## a sanity report (length, peak, silent / clipped / NaN streams). Owner: sfx (docs/team/sfx.md).
##   godot --headless --path . --script res://tools/export_sfx.gd            # export + report
##   godot --headless --path . --script res://tools/export_sfx.gd -- --check  # report only
## Output: res://assets/audio/sfx/<name>.wav. That folder has a .gdignore: the game never loads
## these files (it synthesizes at runtime), they are only for listening in any audio player.
## Exits with code 1 if any stream looks broken.

const OUT_DIR := "res://assets/audio/sfx"
const TIMEOUT_S := 240.0

var _t := 0.0
var _started := false


func _process(delta: float) -> bool:
	_t += delta
	var sfx: Node = root.get_node_or_null(^"Sfx")
	if sfx == null:
		if _t > 5.0:
			push_error("export_sfx: no Sfx autoload")
			quit(1)
		return false
	# Sfx merges finished streams in its own _process; wait for the worker to finish.
	if int(sfx.get(&"_gen_task")) != -1 and _t < TIMEOUT_S:
		return false
	if _started:
		return false
	_started = true
	print("export_sfx: streams ready after %.2f s (%s)" % [_t,
			"user:// cache" if sfx.get(&"loaded_from_cache") else "synthesized"])
	_report(sfx)
	return true


func _report(sfx: Node) -> void:
	var check_only := OS.get_cmdline_user_args().has("--check")
	if not check_only:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		var ignore := FileAccess.open(OUT_DIR.path_join(".gdignore"), FileAccess.WRITE)
		if ignore:
			ignore.store_string("")
	var bad := 0
	var all := {}
	all.merge(sfx.get(&"_streams"))
	# Legacy synthesized music (null once MusicManager owns music: it is then skipped).
	var music: Dictionary = sfx.get(&"_music_streams")
	for k: StringName in music:
		if music[k] != null:
			all[StringName("music_%s" % k)] = music[k]
	var names := all.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for n: StringName in names:
		var s: AudioStreamWAV = all[n]
		var stats := _stats(s)
		var flag := ""
		if stats.nan:
			flag = "  << NaN"
		elif stats.peak < 0.01:
			flag = "  << SILENT"
		elif stats.peak > 0.999:
			flag = "  << CLIPPED"
		if flag != "":
			bad += 1
		print("%-22s %6.2fs  peak %.2f  rms %.3f%s%s" % [n, s.get_length(), stats.peak, stats.rms,
				"  loop" if s.loop_mode != AudioStreamWAV.LOOP_DISABLED else "", flag])
		if not check_only:
			s.save_to_wav(ProjectSettings.globalize_path(OUT_DIR.path_join("%s.wav" % n)))
	print("export_sfx: %d streams, %d broken%s" % [names.size(), bad,
			"" if check_only else ", written to " + OUT_DIR])
	quit(1 if bad > 0 else 0)


## Peak / RMS of a 16-bit or float-converted stream (Sfx streams are 16-bit PCM after import).
func _stats(s: AudioStreamWAV) -> Dictionary:
	var d := s.data
	var peak := 0.0
	var sum := 0.0
	var nan := false
	var count := 0
	if s.format == AudioStreamWAV.FORMAT_16_BITS:
		@warning_ignore("integer_division")
		count = d.size() / 2
		for i in range(0, count, 3):
			var v := absf(d.decode_s16(i * 2) / 32768.0)
			peak = maxf(peak, v)
			sum += v * v
	elif s.format == AudioStreamWAV.FORMAT_8_BITS:
		count = d.size()
		for i in range(0, count, 3):
			var v := absf(d.decode_s8(i) / 128.0)
			peak = maxf(peak, v)
			sum += v * v
	else:
		# Compressed formats: can't inspect cheaply; trust the length.
		return {"peak": 0.5, "rms": 0.0, "nan": false}
	if is_nan(sum):
		nan = true
	var rms := sqrt(sum / maxf(count / 3.0, 1.0))
	return {"peak": peak, "rms": rms, "nan": nan}
