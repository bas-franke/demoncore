extends ProcBoss
## "Lord-Marshal Caddoc, the Burning Crusade" (boss, ashen wastes). See war_chariot_model.gd.
##   I   The Muster  (100-66%)  chariot charges, sword sweeps, a fan of burning lances
##   II  The Advance (66-33%)   + fire-arrow volleys (pillar rain), a plunged sword (fire disc),
##                              zealots and knights join
##   III The Pyre    (< 33%)    + rings of fire, back-to-back charges, a ballista crew joins


func _configure() -> void:
	cfg.merge({
		"title": "LORD-MARSHAL CADDOC, THE BURNING CRUSADE",
		"felled": "THE CRUSADE BURNS OUT",
		"phase_names": ["The Muster", "The Advance", "The Pyre"],
		"patterns": [
			[&"charge", &"sweep", &"lanes", &"charge", &"sweep"],
			[&"charge", &"rain", &"pyre", &"lanes", &"summon", &"charge", &"sweep"],
			[&"charge", &"bells", &"charge", &"rain", &"pyre", &"lanes", &"sweep"],
		],
		"minions": [[], ["zealot", "zealot", "holy_knight", "holy_knight"],
			["templar_ballista", "zealot", "zealot", "witch_hunter_captain"]],
		"cooldown": [2.8, 2.4, 1.9],
		"tell_mult": [1.0, 0.9, 0.8],
		"speed_mult": [1.1, 1.25, 1.4],
		"keep_distance": 6.5,
		"hazard_tint": Color(1.0, 0.45, 0.15),
		"intro_color": Color(1.0, 0.55, 0.25),
	}, true)
