extends ProcBoss
## "Ysmir, the Frost Abbot" (boss, frozen monastery). See frost_abbot_model.gd for the look.
##   I   Vigil        (100-66%)  ice lances (lane fans), icicles that hunt the demon, the abbey bells
##   II  Hailstorm    (66-33%)   + frost nova around him, hail (pillars scattered), monks join
##   III White Silence(< 33%)    + crossing lances, a burst of frost orbs, hermits and wraiths join


func _configure() -> void:
	cfg.merge({
		"title": "YSMIR, THE FROST ABBOT",
		"felled": "THE ABBOT THAWS",
		"phase_lines": [0.66, 0.33],
		"phase_names": ["Vigil", "Hailstorm", "White Silence"],
		"patterns": [
			[&"lanes", &"chase", &"bells", &"lanes", &"chase"],
			[&"pyre", &"lanes", &"rain", &"chase", &"bells", &"summon"],
			[&"bells", &"cross", &"orbs", &"rain", &"pyre", &"lanes", &"chase"],
		],
		"minions": [[], ["monk", "monk", "frost_hermit"], ["frost_hermit", "frost_hermit", "choir_wraith", "choir_wraith"]],
		"cooldown": [3.0, 2.6, 2.1],
		"tell_mult": [1.0, 0.92, 0.82],
		"hazard_tint": Color(0.55, 0.85, 1.0),
		"intro_color": Color(0.7, 0.9, 1.0),
	}, true)
