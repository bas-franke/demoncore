class_name AbilitySynergies
extends RefCounted
## Active synergies and their effect on hits (owned by the Abilities autoload as
## `Abilities.syn`; the autoload forwards has_synergy / syn_param / synergy_statuses / ...).
## Bespoke synergies are checked by id here and in the kinds; data-driven ones come from the
## synergy's "hit_status" / "hit_amp" / "on_hit" / "on_kill" blocks, gated by "tags_any".

var ab: Node  # the Abilities autoload
var active := {}  # StringName -> Dictionary (its definition)
## Data-driven hooks, rebuilt when the active set changes: kind -> Array of [tags_any, payload].
var hooks := {"hit_status": [], "hit_amp": [], "on_hit": [], "on_kill": []}


func _init(p_ab: Node) -> void:
	ab = p_ab


func clear() -> void:
	active.clear()
	_rebuild_hooks()


func has(id: StringName) -> bool:
	return active.has(id)


func params(id: StringName) -> Dictionary:
	return (active.get(id, {}) as Dictionary).get("params", {})


func param(id: StringName, key: String, default: Variant) -> Variant:
	return params(id).get(key, default)


static func met(s: Dictionary, tags: Dictionary) -> bool:
	var req: Dictionary = s.get("requires", {})
	for t: String in req:
		if int(tags.get(t, 0)) < int(req[t]):
			return false
	return true


## Activates every synergy the owned tags now satisfy; announces each on the HUD.
func refresh(tags: Dictionary) -> void:
	var changed := false
	for s: Dictionary in ab.synergy_defs:
		var id := StringName(str(s["id"]))
		if active.has(id) or not met(s, tags):
			continue
		active[id] = s
		changed = true
		ab.synergy_activated.emit(id)
		var hud: Node = ab.get_tree().get_first_node_in_group(&"hud")
		var color := Color.from_string(str(s.get("color", "#ffffff")), Color.WHITE)
		if hud and hud.has_method(&"synergy_banner"):  # UI role: dedicated two-line banner
			hud.call(&"synergy_banner", str(s.get("name", id)), str(s.get("desc", "")), color)
		elif hud and hud.has_method(&"toast"):
			hud.call(&"toast", "Synergy: %s" % s.get("name", id), color)
	if changed:
		_rebuild_hooks()


## Names of synergies that owning `extra_tags` on top of `tags` would newly unlock.
func unlocked_by(tags: Dictionary, extra_tags: PackedStringArray) -> Array[String]:
	var t := tags.duplicate()
	for x in extra_tags:
		t[x] = int(t.get(x, 0)) + 1
	var out: Array[String] = []
	for s: Dictionary in ab.synergy_defs:
		if not active.has(StringName(str(s["id"]))) and met(s, t):
			out.append(str(s.get("name", "")))
	return out


## Statuses that synergies add to a hit with `tags`.
func statuses_for(tags: PackedStringArray) -> Array:
	var out: Array = []
	if active.is_empty():
		return out
	if tags.has("storm") and has(&"firestorm"):
		out.append({"id": "burn", "stacks": int(param(&"firestorm", "burn", 1))})
	if tags.has("storm") and tags.has("chain") and has(&"conductive_chains"):
		out.append({"id": "root", "stacks": 1})
	if tags.has("summon") and has(&"plague_bearers"):
		out.append({"id": "plague", "stacks": int(param(&"plague_bearers", "plague", 1))})
	for h: Array in hooks["hit_status"]:
		if _match(h[0], tags):
			out.append_array(h[1])
	return out


## Trigger effects synergies add to a hit (kill = true: to a killing blow).
func effects_for(tags: PackedStringArray, kill: bool) -> Array:
	var out: Array = []
	for h: Array in hooks["on_kill" if kill else "on_hit"]:
		if _match(h[0], tags):
			out.append_array(h[1])
	return out


## Bonus damage fraction synergies add to a hit on `enemy` (statuses in `host`).
func amp_against(enemy: Enemy, host: StatusHost, tags: PackedStringArray) -> float:
	var a := 0.0
	if host:
		var storm := tags.has("storm")
		if storm and host.has(&"burn") and has(&"firestorm"):
			a += float(param(&"firestorm", "amp", 0.3))
		if host.has(&"root"):
			if storm and has(&"conductive_chains"):
				a += float(param(&"conductive_chains", "amp", 0.25))
			if (tags.has("brute") or tags.has("melee")) and has(&"wrecking_ball"):
				a += float(param(&"wrecking_ball", "amp", 0.4))
	for h: Array in hooks["hit_amp"]:
		if not _match(h[0], tags):
			continue
		var amp: Dictionary = h[1]
		if amp.has("vs_status") and not (host and host.has(StringName(str(amp["vs_status"])))):
			continue
		if amp.get("vs_elite", false) and not (enemy.is_elite() or enemy.is_in_group(&"boss")):
			continue
		a += float(amp.get("amount", 0.0))
	return a


func _rebuild_hooks() -> void:
	for k: String in hooks:
		(hooks[k] as Array).clear()
	for id: StringName in active:
		var s: Dictionary = active[id]
		for k: String in hooks:
			if not s.has(k):
				continue
			var h: Dictionary = s[k]
			var tags := PackedStringArray()
			for t: Variant in h.get("tags_any", []):
				tags.append(str(t))
			var payload: Variant = h
			if k == "hit_status":
				payload = h.get("status", [])
			elif k != "hit_amp":
				payload = h.get("effects", [])
			(hooks[k] as Array).append([tags, payload])


static func _match(want: PackedStringArray, tags: PackedStringArray) -> bool:
	if want.is_empty():
		return true
	for t in want:
		if tags.has(t):
			return true
	return false
