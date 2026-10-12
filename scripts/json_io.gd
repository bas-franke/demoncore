class_name JsonIO
## Shared JSON file helpers: reading data / save files and writing saves safely. Static only.
##
## Several systems (abilities, maps, objectives, atmosphere, audio, skins, roster, dialogue, the
## save files of Meta / Progression / StoryState) each carried their own "read text -> parse ->
## check it is an object -> warn" and "write a temp file -> rename" code. Use these instead so
## every loader reports problems the same way and every save is crash-safe.
## Owned by code-quality (docs/team/code-quality.md).


## Parses the JSON object in `path`. Returns {} (and reports why) when the file is missing,
## unreadable or not a JSON object. `context` prefixes the message ("Maps", "DemonSkins", ...).
## `missing_ok`: a missing file is normal (e.g. no save yet), so return {} silently.
## `as_error`: report with push_error instead of push_warning (for data the game can't run without).
static func read_dict(path: String, context: String, missing_ok: bool = false,
		as_error: bool = false) -> Dictionary:
	if not FileAccess.file_exists(path):
		if not missing_ok:
			_report("%s: cannot read %s (missing)" % [context, path], as_error)
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		_report("%s: cannot read %s (%s)" % [context, path, error_string(FileAccess.get_open_error())],
				as_error)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_report("%s: %s is not a JSON object" % [context, path], as_error)
		return {}
	return parsed


## Writes `data` as tab-indented JSON. The text goes to `<path>.tmp` first and is then renamed
## over `path`, so a crash or power loss mid-write never leaves a half-written save behind.
## Returns false (with a warning prefixed by `context`) if the file can't be written.
static func write_atomic(path: String, data: Variant, context: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("%s: cannot write %s (%s)" % [context, tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# rename_absolute replaces an existing file (MoveFileEx with REPLACE_EXISTING on Windows).
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("%s: cannot replace %s (%s)" % [context, path, error_string(err)])
		return false
	return true


static func _report(message: String, as_error: bool) -> void:
	if as_error:
		push_error(message)
	else:
		push_warning(message)
