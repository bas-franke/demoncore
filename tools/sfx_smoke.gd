extends SceneTree
## Sfx smoke test: plays every element / API path once, then runs the real game on autopilot and
## prints which sounds the gameplay hooks actually triggered. Owner: sfx (docs/team/sfx.md).
##   godot --headless --path . --script res://tools/sfx_smoke.gd -- --autopilot [--secs=30]
## Exits 1 if an API call fails or the run produced no hit / death sounds.

const ELEMENTS := [&"fire", &"blood", &"shadow", &"plague", &"lightning", &"necro"]

var _phase := 0
var _t := 0.0
var _run_secs := 30.0
var _loop: Node
var _fail := false


func _process(delta: float) -> bool:
	_t += delta
	var sfx: Node = root.get_node_or_null(^"Sfx")
	if sfx == null:
		return false
	match _phase:
		0:
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--secs="):
					_run_secs = float(a.get_slice("=", 1))
			if int(sfx.get(&"_gen_task")) != -1:
				return false  # wait for synthesis
			_api_checks(sfx)
			_phase = 1
			_t = 0.0
		1:
			if _t < 0.5:
				return false
			if _loop == null or not bool(_loop.get(&"playing")):
				_err("play_loop did not start")
			_ability_hook_check(sfx)
			change_scene_to_file("res://scenes/main.tscn")
			_phase = 2
			_t = 0.0
		2:
			if _t < _run_secs:
				return false
			var counts: Dictionary = sfx.call(&"get_play_counts")
			var keys := counts.keys()
			keys.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
			for k: StringName in keys:
				print("  %-20s %d" % [k, counts[k]])
			# Material hits and deaths depend on which enemies spawned: require any of each.
			for group: Array in [[&"hit_flesh", &"hit_stone", &"hit_glass", &"hit_metal", &"hit_holy"],
					[&"death_flesh", &"crumble", &"angel_shatter", &"armor_clatter", &"light_burst"]]:
				var total := 0
				for n: StringName in group:
					total += int(counts.get(n, 0))
				if total == 0:
					_err("gameplay never played any of %s" % [group])
			print("sfx_smoke: %s" % ("FAIL" if _fail else "ok"))
			quit(1 if _fail else 0)
			_phase = 3
	return false


func _api_checks(sfx: Node) -> void:
	for e: StringName in ELEMENTS:
		for kind: StringName in [&"cast", &"hit"]:
			if not sfx.call(&"play_element", e, kind, Vector3(1.0, 0.0, 2.0)):
				_err("play_element(%s, %s) failed" % [e, kind])
	if sfx.call(&"play_element", &"holy", &"cast"):
		_err("play_element accepted an unknown element")
	for s: StringName in [&"hit_flesh", &"angel_shatter", &"holy_chime", &"dash", &"pickup_item",
			&"coin", &"shop_buy", &"shop_deny", &"portal_open", &"portal_enter", &"unlock",
			&"ability_ready", &"amb_portal", &"amb_hellfire", &"amb_hell_choir",
			&"hit_stone", &"hit_glass", &"hit_metal", &"hit_holy", &"death_flesh", &"crumble",
			&"armor_clatter", &"light_burst", &"voice_roar", &"voice_grind", &"blip_mid",
			&"desecrate", &"seal_break", &"relic_corrupt", &"stinger_boss", &"thunder",
			&"amb_rain", &"amb_gust_wide", &"amb_hellfire_wide", &"amb_ritual", &"harvest",
			&"wrath_cast", &"greed_hit", &"envy_cast", &"pride_hit", &"gluttony_cast", &"decoy_cast",
			&"turret_hit", &"mine_hit", &"whip_cast", &"evolve", &"synergy", &"relic_common",
			&"relic_legendary", &"step_snow", &"step_wood", &"step_water", &"step_ash",
			&"summon_hellhound", &"summon_imps", &"summon_brute", &"summon_succubus", &"devour",
			&"reflect", &"gilded_drop", &"bell_ring", &"mirror_beam", &"mimic_snap", &"ichor_steal",
			&"revenant_rise", &"frost_shatter", &"djinn_blink", &"dash_swarm", &"hurt_swarm",
			&"death_swarm", &"dash_turncoat", &"hurt_turncoat", &"death_turncoat", &"amb_fly_buzz"]:
		if not sfx.call(&"has_sound", s):
			_err("missing sound %s" % s)
	# Registry: data/audio/enemy_audio.json + keyword fallback.
	var reg: Object = sfx.get(&"registry")
	var expect := {"penitent_statue": &"stone", "glass_golem": &"glass", "paladin": &"metal",
			"choir_wisp": &"holy", "zealot": &"flesh"}
	for id: String in expect:
		var data := load("res://data/enemies/%s.tres" % id)
		if data and reg.call(&"material_of", data) != expect[id]:
			_err("material_of(%s) = %s, want %s" % [id, reg.call(&"material_of", data), expect[id]])
	for m: StringName in [&"stone", &"glass", &"metal", &"holy"]:
		if not sfx.call(&"play_material_hit", m, Vector3.ZERO, -6.0):
			_err("play_material_hit(%s) failed" % m)
	sfx.call(&"play_blip", "grimmaul")
	if not sfx.call(&"play_element", &"avarice", &"cast"):
		_err("play_element(avarice -> greed) failed")
	sfx.call(&"play_relic", 4)
	# Demon identity: Nhazgul's hurt is the swarm version; "" restores the generic one.
	sfx.call(&"set_demon", "nhazgul")
	sfx.call(&"play", &"hurt")
	if int((sfx.call(&"get_play_counts") as Dictionary).get(&"hurt_swarm", 0)) == 0:
		_err("set_demon(nhazgul) did not swap hurt -> hurt_swarm")
	sfx.call(&"set_demon", "iscariel")
	sfx.call(&"play", &"faint")
	if int((sfx.call(&"get_play_counts") as Dictionary).get(&"death_turncoat", 0)) == 0:
		_err("set_demon(iscariel) did not swap faint -> death_turncoat")
	sfx.call(&"set_demon", "")
	print("sfx_smoke: streams from %s" % ("user:// cache" if sfx.get(&"loaded_from_cache") else "synthesis"))
	var holder := Node3D.new()
	root.add_child(holder)
	_loop = sfx.call(&"play_loop", &"amb_portal", holder, -6.0)
	var b := Button.new()
	root.add_child(b)
	sfx.call(&"wire_button", b)
	sfx.call(&"wire_button", b)  # second call must be a no-op
	b.pressed.emit()


## SfxHooks <- Abilities: an ability hit tagged "blood" must voice blood_hit, and a cast of the
## first defined ability must voice its element (when its tags name one).
func _ability_hook_check(sfx: Node) -> void:
	var ab := root.get_node_or_null(^"Abilities")
	if ab == null or not ab.has_signal(&"damage_dealt"):
		print("sfx_smoke: no Abilities autoload, skipping hook check")
		return
	var before: Dictionary = sfx.call(&"get_play_counts")
	ab.emit_signal(&"damage_dealt", 12.0, PackedStringArray(["blood", "projectile"]))
	var after: Dictionary = sfx.call(&"get_play_counts")
	if int(after.get(&"blood_hit", 0)) <= int(before.get(&"blood_hit", 0)):
		_err("Abilities.damage_dealt did not voice blood_hit")
	var defs: Variant = ab.get(&"defs")
	if defs is Dictionary and not (defs as Dictionary).is_empty():
		var id: Variant = (defs as Dictionary).keys()[0]
		ab.emit_signal(&"ability_cast", id)
		var after2: Dictionary = sfx.call(&"get_play_counts")
		var casts := 0
		for k: StringName in after2:
			if String(k).ends_with("_cast"):
				casts += int(after2[k]) - int(after.get(k, 0))
		print("sfx_smoke: ability_cast(%s) -> %d element cast(s)" % [id, casts])
	if ab.has_signal(&"ability_evolved"):
		var before_evo := int((sfx.call(&"get_play_counts") as Dictionary).get(&"evolve", 0))
		ab.emit_signal(&"ability_evolved", &"a", &"b")
		if int((sfx.call(&"get_play_counts") as Dictionary).get(&"evolve", 0)) <= before_evo:
			_err("Abilities.ability_evolved did not play evolve")
	var hooks := sfx.get_node_or_null(^"SfxHooks")
	var tag_cases := {["machine", "trap", "area"]: &"mine", ["illusion", "summon"]: &"decoy",
			["machine", "fire"]: &"turret", ["whip", "fire", "melee"]: &"whip", ["envy", "projectile"]: &"envy"}
	for tags: Array in tag_cases:
		var got: StringName = hooks.call(&"_element_from_tags", PackedStringArray(tags))
		if got != tag_cases[tags]:
			_err("tags %s -> %s, want %s" % [tags, got, tag_cases[tags]])


func _err(msg: String) -> void:
	_fail = true
	push_error("sfx_smoke: " + msg)
