extends AbilityKind
## "summon": keeps get_count() (+ synergy bonus) AbilityMinions of this ability alive.
## Params: lifetime, speed, hit_rate, style (thrall / wraith / shade / locust, or an ally model id
## from data/allies/allies.json: imp / hellhound / succubus / hell_brute).


func cast() -> bool:
	var want := count() + Abilities.summon_bonus()
	var alive := Abilities.minions_of(def.id)
	if alive.size() >= want:
		return true
	if tree().get_node_count_in_group(AbilityMinion.GROUP) >= Abilities.MAX_MINIONS:
		return true
	for i in want - alive.size():
		var off := Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		AbilityMinion.spawn(player.global_position + off, def.id, StringName(style("thrall")), damage(),
			p("speed", 5.0), p("lifetime", 10.0) * Abilities.duration_mult(), p("hit_rate", 0.6), source(), def.color)
	# Demonic allies get their own call (sfx role: SINS.SUMMON_SOUNDS), the undead keep necro_cast.
	sfx(Sfx.SINS.SUMMON_SOUNDS.get(StringName(style("thrall")), &"necro_cast"), -6.0)
	return true
