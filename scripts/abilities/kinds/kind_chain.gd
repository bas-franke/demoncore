extends AbilityKind
## "chain": lightning from above the demon into get_count() enemies, each leaping params.jumps
## more times (boons: +jumps; Conductive Chains: +2).


func cast() -> bool:
	var targets := Targeting.nearest_enemies(tree(), player.global_position, count(), p("range", 8.0))
	if targets.is_empty():
		return false
	var jumps := int(p("jumps")) + int(Abilities.mod("jumps"))
	if jumps > 0 and Abilities.has_synergy(&"conductive_chains"):
		jumps += int(Abilities.syn_param(&"conductive_chains", "jumps", 2))
	var from := player.global_position + Vector3(0.0, 2.2, 0.0)
	var src := source()
	for t in targets:
		AbilityFx.lightning(from, t.global_position + Vector3(0.0, 0.9, 0.0), def.color)
		var pos := t.global_position
		AbilityCombat.hit(t, damage(), src)
		if jumps > 0:
			AbilityCombat.chain(pos, t, jumps - 1, p("jump_range", 4.5), damage() * 0.85, src, def.color)
	sfx(&"beam", -6.0)
	return true
