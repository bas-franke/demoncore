class_name AbilityEvents
## Reactions to game events for the ability system (static helpers; `ab` is the Abilities
## autoload, which forwards its public event methods here): deaths of status-carrying enemies,
## expiring summons, blood spent, blinks, weapon hits, and the small spawners several synergies
## share (decoys, risen thralls, static discharge).


## Any enemy that dies while carrying statuses (reported by its StatusHost).
static func on_status_enemy_died(ab: Node, pos: Vector3, st: Dictionary) -> void:
	if not is_instance_valid(ab.player):
		return
	if st.has(&"plague"):
		var def: Dictionary = ab.statuses[&"plague"]
		var n := int(def.get("spread", 2)) + int(ab.mod("spread:plague"))
		if ab.has_synergy(&"contagion"):
			n += int(ab.syn_param(&"contagion", "spread", 2))
		AbilityCombat.spread(pos, &"plague", n, float(def.get("spread_range", 3.0)),
			maxi(1, int(float(st[&"plague"]) * 0.5)), null)
	if st.has(&"plague") and st.has(&"burn") and ab.has_synergy(&"explosive_miasma"):
		var sp: Dictionary = ab.synergy_params(&"explosive_miasma")
		var src := {"tags": PackedStringArray(["fire", "plague"]), "depth": 1,
			"status": [{"id": "burn", "stacks": int(sp.get("burn", 2))}, {"id": "plague", "stacks": int(sp.get("plague", 2))}]}
		AbilityCombat.explode(pos, float(sp.get("radius", 2.6)) * ab.area_mult(),
			float(sp.get("damage", 14)) * ab.player_might(), src, Color("c0e040"))
	if st.has(&"soul_mark"):
		ab.add_souls(1)
	if st.has(&"gilded"):
		ab.drop_ichor(pos, int((ab.statuses[&"gilded"] as Dictionary).get("ichor", 1)))
	if st.has(&"bleed") and ab.has_synergy(&"crimson_pact"):
		ab.heal_player(float(ab.syn_param(&"crimson_pact", "heal", 0.2)))
	if st.has(&"shock") and ab.has_synergy(&"static_step"):
		static_discharge(ab, pos)


static func on_minion_expired(ab: Node, m: AbilityMinion) -> void:
	if not is_instance_valid(ab.player) or not ab.has_synergy(&"plague_bearers"):
		return
	var sp: Dictionary = ab.synergy_params(&"plague_bearers")
	AbilityZone.spawn(m.global_position, float(sp.get("radius", 2.0)) * ab.area_mult(),
		float(sp.get("duration", 3.0)) * ab.duration_mult(), 0.5, 2.0 * ab.player_might(),
		{"tags": PackedStringArray(["plague"]), "status": [{"id": "plague", "stacks": 1}], "depth": 1},
		ab.status_color(&"plague"), &"cloud")


## Blood magic paid `cost` life (Boiling Blood, Blood Fury).
static func on_life_spent(ab: Node, cost: float) -> void:
	if not is_instance_valid(ab.player):
		return
	if ab.has_synergy(&"blood_fury"):
		ab.add_wrath(cost / AbilityResources.WRATH_PER_HP * float(ab.syn_param(&"blood_fury", "wrath_mult", 2.0)))
	if not ab.has_synergy(&"boiling_blood"):
		return
	var sp: Dictionary = ab.synergy_params(&"boiling_blood")
	AbilityCombat.explode(ab.player.global_position, float(sp.get("radius", 3.0)) * ab.area_mult(),
		cost * float(sp.get("damage_per_hp", 2.5)) * ab.player_might(),
		{"tags": PackedStringArray(["fire", "blood"]), "status": [{"id": "burn", "stacks": int(sp.get("burn", 2))}], "depth": 1},
		Art.HELLFIRE)


static func on_blink(ab: Node, from: Vector3, dest: Vector3) -> void:
	if ab.has_synergy(&"static_step"):
		static_discharge(ab, dest)
	if ab.has_synergy(&"smoke_and_mirrors"):
		spawn_decoy(ab, from)


## Weapon hits (not ability hits) apply statuses from the hitting weapon's tags, so weapons feed
## the synergies too. The weapon is exact when the hit came through Enemy.hit(e, dmg, kb, source)
## (Enemy.last_hit_source; a projectile source may name its weapon in a `weapon` property / meta)
## or `source` is passed; otherwise one owned weapon is picked at random.
static func on_enemy_struck(ab: Node, enemy: Node3D, source: Variant) -> void:
	var player: Player = ab.player
	if AbilityCombat.in_hit > 0 or not is_instance_valid(player) or player.weapons.is_empty():
		return
	var e := enemy as Enemy
	if e == null or e.is_dying:
		return
	var w := _weapon_of(source)
	if w == null:
		w = _weapon_of(e.last_hit_source)  # set by Enemy.hit(e, dmg, kb, weapon) (gameplay)
	if w == null:
		w = player.weapons.pick_random()
	if not is_instance_valid(w):
		return
	var tags := PackedStringArray()
	for t: Variant in ab.weapon_tags.get(w.scene_file_path.get_file().get_basename(), []):
		tags.append(str(t))
	for t in tags:
		var ws: Dictionary = ab.weapon_status.get(t, {})
		if not ws.is_empty() and randf() < float(ws.get("chance", 1.0)):
			AbilityCombat.apply_status(e, StringName(str(ws["id"])), int(ws.get("stacks", 1)))
	for s: Dictionary in ab.synergy_statuses(tags):
		AbilityCombat.apply_status(e, StringName(str(s["id"])), int(s.get("stacks", 1)))


## The Weapon behind a hit source: the weapon itself, or a projectile / effect that names it in
## a `weapon` property or meta.
static func _weapon_of(source: Variant) -> Weapon:
	if not source is Object or not is_instance_valid(source):
		return null
	if source is Weapon:
		return source
	var o := source as Object
	# QA: get_meta(key, null) still errors when the key is missing (a null default counts as "no default").
	var w: Variant = o.get(&"weapon") if &"weapon" in o else (o.get_meta(&"weapon") if o.has_meta(&"weapon") else null)
	return w as Weapon if w is Weapon and is_instance_valid(w) else null


static func static_discharge(ab: Node, at: Vector3) -> void:
	var sp: Dictionary = ab.synergy_params(&"static_step")
	AbilityCombat.chain(at, null, int(sp.get("jumps", 3)), 5.0, float(sp.get("damage", 10)) * ab.player_might(),
		{"tags": PackedStringArray(["storm", "shadow"]), "status": [{"id": "shock", "stacks": 1}], "depth": 1},
		Color("a080ff"))


## A mirror decoy at `at` (Smoke and Mirrors, the "decoy" effect). Uses Mirror Image's numbers
## when owned.
static func spawn_decoy(ab: Node, at: Vector3) -> void:
	var c: AbilityCaster = ab.get_caster(&"mirror_image")
	var dmg: float = c.get_damage() if c else 10.0 * ab.player_might()
	AbilityConstruct.spawn(at, &"_decoy", &"decoy", dmg, 0.9, 2.4 * ab.area_mult(), 4.0 * ab.duration_mult(),
		{"tags": PackedStringArray(["illusion"]), "color": Color("c8a8e8"), "depth": 1}, Color("c8a8e8"))


## A skeletal thrall rises at `pos` (Lord of the Pit, Bone Banquet, the "raise" effect).
static func raise_thrall(ab: Node, pos: Vector3) -> void:
	if ab.get_tree().get_node_count_in_group(AbilityMinion.GROUP) >= ab.MAX_MINIONS:
		return
	var def: AbilityDef = ab.defs.get(&"raise_thralls")
	var dmg: float = (def.damage if def else 7.0) * ab.player_might() * ab.summon_amp()
	AbilityMinion.spawn(pos, &"_risen", &"thrall", dmg, 5.0, 8.0 * ab.duration_mult(), 0.6,
		{"tags": PackedStringArray(["necro", "summon"]), "color": Color("c86a78")}, Color("c86a78"))


## A kill made by an ability hit (`had` = the victim's statuses just before the blow).
static func notify_ability_kill(ab: Node, _pos: Vector3, tags: PackedStringArray, _had: Dictionary) -> void:
	if tags.has("summon") and ab.has_synergy(&"sanguine_legion"):
		ab.heal_player(float(ab.syn_param(&"sanguine_legion", "heal", 1.0)))


static func minions_of(ab: Node, id: StringName) -> Array[AbilityMinion]:
	var out: Array[AbilityMinion] = []
	for n in ab.get_tree().get_nodes_in_group(AbilityMinion.GROUP):
		var m := n as AbilityMinion
		if m and m.get_meta(&"ability", &"") == id:
			out.append(m)
	return out
