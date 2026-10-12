class_name AtmoStack
extends RefCounted
## What sits on top of the active preset, in order: weighted overlays (boss lighting, run
## escalation, surges, gameplay tweaks) and plain value overrides (set_weather / set_value).
## compose() turns preset + stack into the target state. Owned by the Atmosphere autoload.

## [{id: StringName, name: String ("" = ad hoc), ops: Dictionary, weight: float}] in push order.
var overlays: Array[Dictionary] = []
## Flat key -> value.
var overrides := {}


func clear() -> void:
	overlays.clear()
	overrides.clear()


## Adds or updates overlay `id`. `ops` are parsed overlay ops; `name` is the presets.json overlay
## they came from ("" for ad-hoc dictionaries), so they can be re-resolved for a new preset.
func push(id: StringName, name: String, ops: Dictionary, weight: float) -> void:
	var entry := {"id": id, "name": name, "ops": ops, "weight": clampf(weight, 0.0, 1.0)}
	for i in overlays.size():
		if overlays[i]["id"] == id:
			overlays[i] = entry
			return
	overlays.append(entry)


## Removes overlay `id`; false if it was not there.
func pop(id: StringName) -> bool:
	for i in overlays.size():
		if overlays[i]["id"] == id:
			overlays.remove_at(i)
			return true
	return false


func has(id: StringName) -> bool:
	return overlays.any(func(o: Dictionary) -> bool: return o["id"] == id)


## Re-reads every named overlay for `preset` (its local "overlays" may differ from the global ones).
func reresolve(presets: AtmoPresets, preset: String) -> void:
	for o in overlays:
		if o["name"] != "":
			o["ops"] = presets.overlay(o["name"], preset)


## Sets (or with null, removes) a flat override.
func set_value(key: String, value: Variant) -> void:
	if value == null:
		overrides.erase(key)
	else:
		overrides[key] = AtmoPresets.parse_value(value)


## Removes every override whose key starts with `prefix` ("" = all).
func clear_values(prefix: String = "") -> void:
	for k: String in overrides.keys():
		if k.begins_with(prefix):
			overrides.erase(k)


## The target state: `base` preset, then overlays in push order, then overrides.
func compose(presets: AtmoPresets, base: String) -> Dictionary:
	var s := presets.resolve(base)
	for o in overlays:
		AtmoPresets.apply_ops(s, o["ops"], o["weight"])
	for k: String in overrides:
		s[k] = overrides[k]
	return s
