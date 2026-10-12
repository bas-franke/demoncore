class_name DialogueDB
extends RefCounted
## All dialogue content, loaded from every res://data/dialogue/*.json file (see the format in
## docs/team/story.md). Files are merged; a later id overrides an earlier one with a warning.
## Note for exports: add "*.json" to the export preset's non-resource include filter.

const DIR := "res://data/dialogue"

## speaker id -> {name, title, color (Color), glyph, portrait, shop / shops}
var speakers: Dictionary = {}
## conversation id -> conversation Dictionary (with "id", "pool", "lines", ... filled in)
var conversations: Dictionary = {}
## pool name -> Array of conversation ids, in file order
var pools: Dictionary = {}
## shop id -> speaker id (from each speaker's "shop" field)
var shops: Dictionary = {}
## Any other top-level key of the files (e.g. "ending_rule", "codex", "gifts"), merged by key.
var extra: Dictionary = {}


## (Re)loads every JSON file in DIR into speakers / conversations / pools / shops / extra.
func load_all() -> void:
	speakers.clear()
	conversations.clear()
	pools.clear()
	shops.clear()
	extra.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		push_warning("DialogueDB: %s not found" % DIR)
		return
	var files := Array(dir.get_files())
	files.sort()  # deterministic merge order
	for f: String in files:
		# Exported builds may list "x.json.remap"-style names; only plain JSON is supported.
		if f.get_extension() == "json":
			_load_file(DIR.path_join(f))


## The conversation with this id, or {} if unknown.
func get_conv(id: String) -> Dictionary:
	return conversations.get(id, {})


## Conversation ids in the named pool (random barks / NPC chatter), or [] if unknown.
func pool(name: String) -> Array:
	return pools.get(name, [])


## True when the pool exists and has at least one conversation.
func has_pool(name: String) -> bool:
	return pools.has(name) and not (pools[name] as Array).is_empty()


## The speaker definition (name, color, portrait, ...) for an id, or {} if unknown.
func speaker(id: String) -> Dictionary:
	return speakers.get(id, {})


## Who says a line that has no "who": the conversation's "who", else its pool when the pool is a
## speaker id (NPC pools), else the narrator.
func default_who(conv: Dictionary) -> String:
	if conv.has("who"):
		return str(conv["who"])
	return conv["pool"] if speakers.has(conv["pool"]) else "narrator"


func _load_file(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("DialogueDB: %s is not a valid JSON object" % path)
		return
	var data: Dictionary = parsed
	var sp: Variant = data.get("speakers", {})
	if sp is Dictionary:
		for id: Variant in sp:
			_add_speaker(str(id), sp[id])
	for k: Variant in data:
		if not str(k) in ["speakers", "conversations", "_doc"]:
			extra[str(k)] = data[k]
	var convs: Variant = data.get("conversations", [])
	if convs is Array:
		for c: Variant in convs:
			if c is Dictionary:
				_add_conversation(c, path)


func _add_speaker(id: String, raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var s: Dictionary = (raw as Dictionary).duplicate()
	s["id"] = id
	s["name"] = str(s.get("name", id.capitalize()))
	s["title"] = str(s.get("title", ""))
	s["color"] = Color.from_string(str(s.get("color", "#e8d6a6")), Color("e8d6a6"))
	s["glyph"] = str(s.get("glyph", s["name"].left(1)))
	s["portrait"] = str(s.get("portrait", ""))
	speakers[id] = s
	# "shop": "occultist" or "shops": ["occultist", "oracle"] (Meta and Progression shop ids).
	var shop_ids: Array = []
	if s.has("shop"):
		shop_ids.append(s["shop"])
	if s.get("shops") is Array:
		shop_ids.append_array(s["shops"])
	for shop: Variant in shop_ids:
		shops[str(shop)] = id


func _add_conversation(c: Dictionary, path: String) -> void:
	var id := str(c.get("id", ""))
	if id == "":
		push_warning("DialogueDB: conversation without id in %s" % path)
		return
	if conversations.has(id):
		push_warning("DialogueDB: duplicate conversation '%s' (%s overrides)" % [id, path])
		_remove_from_pool(id)
	if not c.get("lines", null) is Array:
		push_warning("DialogueDB: conversation '%s' has no lines" % id)
		c["lines"] = []
	c["id"] = id
	c["pool"] = str(c.get("pool", ""))
	c["priority"] = float(c.get("priority", 0))
	c["once"] = bool(c.get("once", false))
	c["labels"] = _index_labels(c["lines"])
	conversations[id] = c
	if c["pool"] != "":
		if not pools.has(c["pool"]):
			pools[c["pool"]] = []
		(pools[c["pool"]] as Array).append(id)


func _remove_from_pool(id: String) -> void:
	for p: String in pools:
		(pools[p] as Array).erase(id)


## label -> line index, so "goto" can jump.
func _index_labels(lines: Array) -> Dictionary:
	var labels := {}
	for i in lines.size():
		var line: Variant = lines[i]
		if line is Dictionary and line.has("label"):
			labels[str(line["label"])] = i
	return labels
