extends ProcBoss
## "Baraqiel, Archon of the Tempest" (boss, storm spire). See storm_archon_model.gd.
##   I   Gathering        (100-66%)  lightning that hunts the demon, crossing bolts, ball lightning
##   II  The Squall       (66-33%)   + thunderclaps (rings), a storm of strikes (pillar rain), light
##                                   elementals and ophanim join
##   III Eye of the Storm (< 33%)    + streaking charges, double orb bursts, seraphs join


func _configure() -> void:
	cfg.merge({
		"title": "BARAQIEL, ARCHON OF THE TEMPEST",
		"felled": "THE STORM BREAKS",
		"phase_names": ["Gathering", "The Squall", "Eye of the Storm"],
		"patterns": [
			[&"chase", &"cross", &"orbs", &"chase", &"lanes"],
			[&"bells", &"rain", &"chase", &"orbs", &"summon", &"cross"],
			[&"charge", &"rain", &"bells", &"orbs", &"chase", &"cross", &"pyre"],
		],
		"minions": [[], ["light_elemental", "light_elemental", "ophan", "ophan", "ophan"],
			["seraph", "light_elemental", "light_elemental"]],
		"cooldown": [2.6, 2.2, 1.8],
		"tell_mult": [1.0, 0.9, 0.8],
		"keep_distance": 6.0,
		"hazard_tint": Color(0.62, 0.62, 1.0),
		"intro_color": Color(0.7, 0.75, 1.0),
	}, true)
