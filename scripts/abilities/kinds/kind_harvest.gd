extends AbilityKind
## "harvest": pulls every XP gem on the map to the demon. (Its passive, might per Soul, is applied
## by Abilities._update_passives from params.might_per_soul.)


func cast() -> bool:
	for g in tree().get_nodes_in_group(&"gems"):
		if g.has_method(&"attract"):
			g.call(&"attract", player)
	AbilityFx.ring(player.global_position, 6.0, def.color, 0.6)
	sfx(&"harvest", -4.0)  # inward soul rush (sfx); not &"soul", the XP pickup pitch ladder
	return true
