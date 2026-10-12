extends ProcBoss
## "Mother Verdance, Saint of the First Garden" (boss, outer gardens). See
## verdant_matriarch_model.gd for the look.
##   I   Blossom   (100-66%)  thorns that erupt under the demon, crossing roots, pollen orbs
##   II  Overgrowth(66-33%)   + bloom (fire disc around her), dryads and unicorns join
##   III Wildwood  (< 33%)    + seed rain, sweeping branches, lions and pegasi join, faster


func _configure() -> void:
	cfg.merge({
		"title": "MOTHER VERDANCE, SAINT OF THE FIRST GARDEN",
		"felled": "THE GARDEN WITHERS",
		"phase_lines": [0.66, 0.33],
		"phase_names": ["Blossom", "Overgrowth", "Wildwood"],
		"patterns": [
			[&"chase", &"cross", &"orbs", &"chase", &"cross"],
			[&"pyre", &"chase", &"orbs", &"cross", &"summon", &"chase"],
			[&"rain", &"sweep", &"chase", &"orbs", &"cross", &"pyre", &"summon"],
		],
		"minions": [[], ["dryad_priestess", "unicorn", "cherub", "cherub"], ["holy_lion", "pegasus", "dryad_priestess"]],
		"cooldown": [3.0, 2.6, 2.0],
		"tell_mult": [1.0, 0.92, 0.82],
		"speed_mult": [0.8, 0.9, 1.0],
		"hazard_tint": Color(0.7, 1.0, 0.4),
		"intro_color": Color(0.85, 1.0, 0.55),
	}, true)
