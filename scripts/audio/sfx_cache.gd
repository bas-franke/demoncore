extends RefCounted
## Disk cache for the Sfx autoload's synthesized streams (owner: sfx role, docs/team/sfx.md).
## The first launch renders every sound (~25 s on a worker thread) and saves them all to one
## zstd-compressed file in user://; later launches load that file in well under a second.
## The file is keyed by a hash of the recipe sources, so editing any recipe script invalidates it
## automatically. Only plain Variants are stored (no Objects), and the payload is validated on load.
##
## Dev: `-- --sfx-nocache` ignores and rewrites the cache; delete user://sfx_cache/ to clear it.

const DIR := "user://sfx_cache"
const FILE := "user://sfx_cache/streams.bin"
## Bump when the on-disk layout changes.
const FORMAT := 2


## A key that changes whenever a recipe source, the cache format or the engine version changes.
## In exported builds the .gd sources may be missing; `fallback` (Sfx.RECIPE_VERSION) then decides.
static func version_key(sources: PackedStringArray, fallback: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(("%d|%s|%s" % [FORMAT, fallback, Engine.get_version_info().string]).to_utf8_buffer())
	for path in sources:
		if FileAccess.file_exists(path):
			ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


## name -> AudioStreamWAV, or {} when there is no valid cache for `key`.
static func load_streams(key: String) -> Dictionary:
	if not FileAccess.file_exists(FILE):
		return {}
	var f := FileAccess.open_compressed(FILE, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var payload: Variant = f.get_var(false)  # false: never decode Objects
	f.close()
	if not payload is Dictionary or payload.get("key") != key or not payload.get("streams") is Dictionary:
		return {}
	var out := {}
	var streams: Dictionary = payload["streams"]
	for n: Variant in streams:
		var e: Variant = streams[n]
		if not e is Array or (e as Array).size() != 6 or not e[5] is PackedByteArray:
			return {}  # corrupt: re-render everything
		var s := AudioStreamWAV.new()
		s.format = AudioStreamWAV.FORMAT_16_BITS
		s.mix_rate = int(e[0])
		s.stereo = bool(e[1])
		s.data = e[5]
		s.loop_mode = int(e[2]) as AudioStreamWAV.LoopMode
		s.loop_begin = int(e[3])
		s.loop_end = int(e[4])
		out[StringName(str(n))] = s
	return out


## Saves `streams` (name -> AudioStreamWAV) under `key`. 16-bit PCM only (what Sfx produces);
## anything else is skipped and simply re-rendered next launch.
static func save_streams(key: String, streams: Dictionary) -> bool:
	var packed := {}
	for n: Variant in streams:
		var s := streams[n] as AudioStreamWAV
		if s == null or s.format != AudioStreamWAV.FORMAT_16_BITS:
			continue
		packed[String(n)] = [s.mix_rate, s.stereo, int(s.loop_mode), s.loop_begin, s.loop_end, s.data]
	DirAccess.make_dir_recursive_absolute(DIR)
	var tmp := FILE + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("SfxCache: cannot write %s" % tmp)
		return false
	f.store_var({"key": key, "streams": packed}, false)
	f.close()
	# Write-then-rename, so a crash mid-save never leaves a half file that looks valid.
	DirAccess.remove_absolute(FILE)
	return DirAccess.rename_absolute(tmp, FILE) == OK
