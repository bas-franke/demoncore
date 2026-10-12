class_name AtmoPresets
extends RefCounted
## Loads res://data/atmosphere/presets.json and resolves presets into flat state dictionaries
## ("section.key" -> value) for the Atmosphere autoload. Pure data: no nodes touched here.
##
## JSON rules (see the "_doc" entry in the file):
##   - every preset inherits from "extends" (default "_defaults"), section by section, key by key
##   - colors are "#rrggbb" or [r, g, b(, a)] (components may exceed 1 for tints); [x, y] = Vector2
##   - "cycle": [{"preset": name, "time": seconds}] = weather variants the map drifts through
##   - "overlays": {"boss": {...}} per preset replaces the global "_overlays" entry of that name
##   - overlay keys may end in an operator: "key*" multiply, "key+" add, "key~" [target, amount] mix

const PATH := "res://data/atmosphere/presets.json"
const SECTIONS: Array[String] = ["env", "sky", "sun", "moon", "grade", "weather", "scene", "fx"]
## Keys blended as angles (degrees) so the sun never swings the long way round.
const ANGLE_KEYS: Array[String] = ["sun.pitch", "sun.yaw", "moon.pitch", "moon.yaw"]

var _raw := {}  # String -> Dictionary (preset JSON as authored)
var _overlays := {}  # String -> Dictionary (ops, parsed)
var _cache := {}  # String -> Dictionary (resolved flat state)


## Loads (or reloads) the preset file. Returns false (with a warning) if it is missing or broken.
func load_file(path: String = PATH) -> bool:
	_raw.clear()
	_overlays.clear()
	_cache.clear()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("AtmoPresets: cannot open %s" % path)
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		push_warning("AtmoPresets: %s is not a JSON object" % path)
		return false
	for k: String in data:
		if k == "_overlays":
			var ovs: Dictionary = data[k]
			for o: String in ovs:
				_overlays[o] = parse_ops(ovs[o])
		elif data[k] is Dictionary:
			_raw[k] = data[k]
	if not _raw.has("_defaults"):
		push_warning("AtmoPresets: %s has no _defaults preset" % path)
	return true


func has(preset: String) -> bool:
	return _raw.has(preset) and not preset.begins_with("_")


## Public preset names (no "_" entries), in file order.
func names() -> PackedStringArray:
	var r := PackedStringArray()
	for k: String in _raw:
		if not k.begins_with("_"):
			r.append(k)
	return r


## Preset for a scene file from the "_scenes" table ("" if none).
func scene_preset(scene_path: String) -> String:
	var t: Dictionary = _raw.get("_scenes", {})
	var p := String(t.get(scene_path, ""))
	return p if has(p) else ""


func doc(preset: String) -> String:
	return String((_raw.get(preset, {}) as Dictionary).get("_doc", ""))


## The fully inherited flat state of `preset` (a fresh copy; safe to modify).
func resolve(preset: String) -> Dictionary:
	if not _cache.has(preset):
		var flat := {}
		for n in _chain(preset):
			var p: Dictionary = _raw[n]
			for section: String in SECTIONS:
				if p.has(section) and p[section] is Dictionary:
					var sec: Dictionary = p[section]
					for k: String in sec:
						if not k.begins_with("_"):
							flat[section + "." + k] = parse_value(sec[k])
		_cache[preset] = flat
	return (_cache[preset] as Dictionary).duplicate()


## The weather cycle of `preset` (nearest definition along the extends chain), as
## [{"preset": String, "time": float}], only entries naming known presets.
func cycle_of(preset: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chain := _chain(preset)
	chain.reverse()
	for n in chain:
		var p: Dictionary = _raw[n]
		if p.has("cycle") and p["cycle"] is Array:
			for e: Variant in p["cycle"]:
				if e is Dictionary and has(String(e.get("preset", ""))):
					out.append({"preset": String(e["preset"]), "time": maxf(float(e.get("time", 60.0)), 1.0)})
			break
	return out


## Overlay ops by name: the preset's own "overlays" entry (nearest along the chain), else the global
## "_overlays" one. Empty if neither exists.
func overlay(name: String, preset: String = "") -> Dictionary:
	if preset != "" and _raw.has(preset):
		var chain := _chain(preset)
		chain.reverse()
		for n in chain:
			var ovs: Variant = (_raw[n] as Dictionary).get("overlays", null)
			if ovs is Dictionary and (ovs as Dictionary).has(name):
				return parse_ops(ovs[name])
	return (_overlays.get(name, {}) as Dictionary).duplicate()


# ---------------------------------------------------------------- value helpers

## JSON value -> Godot value (Color / Vector2 / float / bool / String / Array).
static func parse_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_STRING:
			var s: String = v
			if s.begins_with("#"):
				return Color.html(s)
			return s
		TYPE_ARRAY:
			var a: Array = v
			var numeric := true
			for e: Variant in a:
				if typeof(e) != TYPE_INT and typeof(e) != TYPE_FLOAT:
					numeric = false
					break
			if numeric:
				if a.size() == 2:
					return Vector2(float(a[0]), float(a[1]))
				if a.size() == 3:
					return Color(float(a[0]), float(a[1]), float(a[2]))
				if a.size() == 4:
					return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
			return a
	return v


## Parses an overlay / override dictionary: flat "section.key[op]" keys, or nested sections.
static func parse_ops(d: Variant) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		return out
	for k: String in d:
		if k.begins_with("_"):
			continue
		var v: Variant = d[k]
		if v is Dictionary and k in SECTIONS:
			for sk: String in v:
				out[k + "." + sk] = _parse_op_value(sk, v[sk])
		else:
			out[k] = _parse_op_value(k, v)
	return out


static func _parse_op_value(key: String, v: Variant) -> Variant:
	if key.ends_with("~") and v is Array and (v as Array).size() == 2:
		return [parse_value(v[0]), float(v[1])]
	return parse_value(v)


## Applies overlay ops to `state` in place. `weight` 0..1 applies them partially (an overlay faded
## in by gameplay, e.g. run escalation): "*" multiplies by lerp(1, v, w), "+" adds v * w, "~" mixes
## amount * w, plain values blend toward v by w (toggles switch at w >= 0.5).
static func apply_ops(state: Dictionary, ops: Dictionary, weight: float = 1.0) -> void:
	var w := clampf(weight, 0.0, 1.0)
	if w <= 0.0:
		return
	for raw_key: String in ops:
		var v: Variant = ops[raw_key]
		var op := raw_key.right(1)
		var key := raw_key.left(-1) if op in ["*", "+", "~"] else raw_key
		if not state.has(key) and op in ["*", "+", "~"]:
			continue
		var cur: Variant = state.get(key)
		match op:
			"*":
				# Colors scale per channel, numbers scale as floats.
				var f: Variant
				if v is Color:
					f = Color(1, 1, 1).lerp(v, w)
				else:
					f = lerpf(1.0, float(v), w)
				state[key] = _mul(cur, f)
			"+":
				state[key] = _add(cur, _mul(v, w) if (v is Color or v is Vector2) else float(v) * w)
			"~":
				if v is Array and (v as Array).size() == 2:
					state[key] = _mix(cur, v[0], float(v[1]) * w)
			_:
				if w >= 0.999 or cur == null:
					state[key] = v
				elif v is bool or v is String or v is Array:
					if w >= 0.5:
						state[key] = v
				else:
					state[key] = _mix(cur, v, w)


static func _mul(a: Variant, b: Variant) -> Variant:
	if a is Color:
		var c: Color = a
		if b is Color:
			return Color(c.r * b.r, c.g * b.g, c.b * b.b, c.a)
		var f := float(b)
		return Color(c.r * f, c.g * f, c.b * f, c.a)
	if a is Vector2:
		return (a as Vector2) * float(b)
	if a is float:
		return float(a) * float(b)
	return a


static func _add(a: Variant, b: Variant) -> Variant:
	if a is Color:
		var c: Color = a
		if b is Color:
			return Color(c.r + b.r, c.g + b.g, c.b + b.b, c.a)
		var f := float(b)
		return Color(c.r + f, c.g + f, c.b + f, c.a)
	if a is Vector2 and b is Vector2:
		return (a as Vector2) + (b as Vector2)
	if a is float:
		return float(a) + float(b)
	return a


static func _mix(a: Variant, target: Variant, t: float) -> Variant:
	if a is Color and target is Color:
		return (a as Color).lerp(target, t)
	if a is Vector2 and target is Vector2:
		return (a as Vector2).lerp(target, t)
	if a is float:
		return lerpf(float(a), float(target), t)
	return a


## Blend of two flat states. Keys come from `b`; continuous values interpolate, discrete ones
## (bools, strings, arrays) take `b`'s value immediately so toggles happen at the start of a blend.
static func lerp_state(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var r := {}
	for k: String in b:
		var vb: Variant = b[k]
		var va: Variant = a.get(k, vb)
		if typeof(va) != typeof(vb):
			r[k] = vb
		elif vb is Color:
			r[k] = (va as Color).lerp(vb, t)
		elif vb is Vector2:
			r[k] = (va as Vector2).lerp(vb, t)
		elif vb is float:
			if k in ANGLE_KEYS:
				r[k] = rad_to_deg(lerp_angle(deg_to_rad(va), deg_to_rad(vb), t))
			else:
				r[k] = lerpf(va, vb, t)
		else:
			r[k] = vb
	return r


## Inheritance chain, root first ("_defaults", ..., preset). Guards against extends loops.
func _chain(preset: String) -> Array[String]:
	var chain: Array[String] = []
	var n := preset
	while n != "" and _raw.has(n) and not n in chain:
		chain.push_front(n)
		if n == "_defaults":
			break
		n = String((_raw[n] as Dictionary).get("extends", "_defaults"))
	if not chain.is_empty() and chain[0] != "_defaults" and _raw.has("_defaults"):
		chain.push_front("_defaults")
	return chain
