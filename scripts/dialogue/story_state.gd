class_name StoryState
extends RefCounted
## Persistent story memory: named variables (flags and counters share one table) plus how often
## each conversation has been seen. Saved as JSON to user://story.json by the Dialogue autoload.
##
## Variables are plain JSON values keyed by dotted names, e.g. "runs", "boss_kills.sariel",
## "last.died", "met_vesper". A flag is any variable whose value is truthy.
##
## Condition blocks ("requires" in the dialogue JSON) are evaluated by check():
##   "min": {"runs": 3}            every variable >= value (missing = 0)
##   "max": {"deaths": 2}          every variable <= value
##   "eq":  {"last.result": "death"}
##   "flags": ["a", "b"]           all truthy        "not_flags": [...]  none truthy
##   "seen": ["conv_id"]           all seen before   "not_seen": [...]   none seen
##   "demon": "lilaeth" | [...]    current demon id  "not_demon": ...
##   "any": [{...}, {...}]         at least one nested block passes
##   "chance": 0.25                random roll (re-rolled each time it is checked)

const VERSION := 1

## name -> JSON value
var vars: Dictionary = {}
## conversation id -> times seen
var seen: Dictionary = {}


func to_dict() -> Dictionary:
	return {"version": VERSION, "vars": vars, "seen": seen}


func from_dict(d: Dictionary) -> void:
	var v: Variant = d.get("vars", {})
	var s: Variant = d.get("seen", {})
	vars = v if v is Dictionary else {}
	seen = s if s is Dictionary else {}


func save(path: String) -> void:
	# Atomic (temp file + rename) so a crash mid-save can't corrupt the story save.
	JsonIO.write_atomic(path, to_dict(), "StoryState")


func load_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		from_dict(parsed)
	else:
		push_warning("StoryState: %s is not valid JSON, starting fresh" % path)


# ---------------------------------------------------------------- variables

func get_var(key: String, default: Variant = null) -> Variant:
	return vars.get(key, default)


func get_num(key: String) -> float:
	var v: Variant = vars.get(key, 0)
	if v is bool:
		return 1.0 if v else 0.0
	if v is int or v is float:
		return float(v)
	return 0.0


func set_var(key: String, value: Variant) -> void:
	vars[key] = value


func add(key: String, amount: float = 1.0) -> void:
	var n := get_num(key) + amount
	# Keep whole numbers as ints so the save file stays readable.
	if is_equal_approx(n, roundf(n)):
		vars[key] = int(n)
	else:
		vars[key] = n


func is_flag(key: String) -> bool:
	var v: Variant = vars.get(key, false)
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	if v is String:
		return v != ""
	return v != null


func times_seen(conv_id: String) -> int:
	return int(seen.get(conv_id, 0))


func mark_seen(conv_id: String) -> void:
	seen[conv_id] = times_seen(conv_id) + 1


## Applies a "set" block ({"name": value}) and an "add" block ({"name": amount}).
func apply(set_block: Variant, add_block: Variant = null) -> void:
	if set_block is Dictionary:
		for k: Variant in set_block:
			set_var(str(k), set_block[k])
	if add_block is Dictionary:
		for k: Variant in add_block:
			add(str(k), float(add_block[k]))


# ---------------------------------------------------------------- conditions

## True when every rule in `req` passes. `demon_id` is the current demon's id ("" if none).
func check(req: Variant, demon_id: String) -> bool:
	if req == null:
		return true
	if not req is Dictionary:
		push_warning("StoryState: 'requires' must be an object, got %s" % str(req))
		return false
	var r: Dictionary = req
	for k: Variant in r.get("min", {}):
		if get_num(str(k)) < float(r["min"][k]):
			return false
	for k: Variant in r.get("max", {}):
		if get_num(str(k)) > float(r["max"][k]):
			return false
	for k: Variant in r.get("eq", {}):
		if not _equals(vars.get(str(k), null), r["eq"][k]):
			return false
	for f: Variant in r.get("flags", []):
		if not is_flag(str(f)):
			return false
	for f: Variant in r.get("not_flags", []):
		if is_flag(str(f)):
			return false
	for c: Variant in r.get("seen", []):
		if times_seen(str(c)) == 0:
			return false
	for c: Variant in r.get("not_seen", []):
		if times_seen(str(c)) > 0:
			return false
	if r.has("demon") and not _matches(r["demon"], demon_id):
		return false
	if r.has("not_demon") and _matches(r["not_demon"], demon_id):
		return false
	if r.has("any"):
		var ok := false
		for sub: Variant in r["any"]:
			if check(sub, demon_id):
				ok = true
				break
		if not ok:
			return false
	if r.has("chance") and randf() > float(r["chance"]):
		return false
	return true


## JSON numbers load as floats and counters are stored as ints, so numbers compare by value.
func _equals(have: Variant, want: Variant) -> bool:
	if (have is int or have is float or have == null) and (want is int or want is float):
		return is_equal_approx(float(have) if have != null else 0.0, float(want))
	if have is bool or want is bool:
		return is_flag_value(have) == is_flag_value(want)
	return str(have if have != null else "") == str(want)


static func is_flag_value(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return v != null and str(v) != ""


func _matches(want: Variant, demon_id: String) -> bool:
	if want is Array:
		return demon_id in want
	return str(want) == demon_id
