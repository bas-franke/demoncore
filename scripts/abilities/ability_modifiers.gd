class_name AbilityModifiers
## How boons, synergies and the demon's affinity change an ability's numbers (static helpers; the
## Abilities autoload forwards damage_mult / cooldown_mult / count_bonus / summon_amp /
## hp_cost_mult / crit_chance / damage_amp_against here; `ab` is that autoload).


static func damage_mult(ab: Node, def: AbilityDef) -> float:
	var m: float = 1.0 + ab.mod("damage")
	for t in def.tags:
		m += ab.mod("tag:" + t)
	if ab.has_synergy(&"hellstorm_trinity"):
		m += float(ab.syn_param(&"hellstorm_trinity", "amp", 0.15))
	if ab.is_favoured(def):
		m += ab.affinity_damage()
	return m


static func cooldown_mult(ab: Node, def: AbilityDef) -> float:
	var cut: float = ab.mod("cooldown")
	for t in def.tags:
		cut += ab.mod("tagcd:" + t)
	if ab.has_synergy(&"hellstorm_trinity"):
		cut += float(ab.syn_param(&"hellstorm_trinity", "cooldown", 0.15))
	return maxf(1.0 - cut, 0.4)


## Extra projectiles / orbiting objects / summons / constructs for `def` from boons.
static func count_bonus(ab: Node, def: AbilityDef) -> int:
	var n := 0
	if def.kind in [&"bolt", &"orbit", &"summon", &"turret", &"mine", &"decoy"]:
		n += int(ab.mod("count"))
	if def.kind == &"summon":
		n += int(ab.mod("summon_count"))
	return n


static func summon_bonus(ab: Node) -> int:
	return int(ab.syn_param(&"lord_of_the_pit", "extra_count", 2)) if ab.has_synergy(&"lord_of_the_pit") else 0


## Damage multiplier applied to every summon strike (Sanguine Legion, Soul Cage).
static func summon_amp(ab: Node) -> float:
	var a := 1.0
	if ab.has_synergy(&"sanguine_legion"):
		a += float(ab.syn_param(&"sanguine_legion", "amp", 0.4))
	if ab.has_synergy(&"soul_cage"):
		a += ab.souls * float(ab.syn_param(&"soul_cage", "amp_per_soul", 0.003))
	return a


static func hp_cost_mult(ab: Node) -> float:
	var cut: float = ab.mod("hp_cost_cut")
	if ab.has_synergy(&"soul_transfusion"):
		cut += float(ab.syn_param(&"soul_transfusion", "cost_cut", 0.4))
	return maxf(1.0 - cut, 0.2)


static func crit_chance(ab: Node, tags: PackedStringArray, host: StatusHost) -> float:
	var c: float = ab.mod("crit")
	for t in tags:
		c += ab.mod("tagcrit:" + t)
	if host and host.has(&"curse") and ab.has_synergy(&"assassins_mark"):
		c += float(ab.syn_param(&"assassins_mark", "crit", 0.25))
	return c


## Bonus damage fraction for a hit on `enemy` (curses, shock, binds, gilding, synergies, execute).
static func damage_amp_against(ab: Node, enemy: Enemy, host: StatusHost, tags: PackedStringArray) -> float:
	var a: float = ab.syn.amp_against(enemy, host, tags)
	if host:
		a += host.curse_amp()
		if host.has(&"gilded"):
			a += float((ab.statuses[&"gilded"] as Dictionary).get("amp", 0.15))
		if tags.has("storm"):
			a += host.shock_amp()
		if host.has(&"root"):
			a += ab.mod("root_amp")
	if ab.mod("execute") > 0.0 and enemy.hp < enemy.max_hp * 0.3:
		a += ab.mod("execute")
	return a
