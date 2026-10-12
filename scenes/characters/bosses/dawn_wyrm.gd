extends ProcBoss
## "Aurelion, the Dawn Wyrm" (boss, sunlit citadel). See dawn_wyrm_model.gd for the look.
##   I   First Light (100-66%)  breath (lane fans), a sweeping breath arc, sun-orb bursts
##   II  High Noon   (66-33%)   + diving charges, falling stars (pillar rain), wyrmlings join
##   III Eclipse     (< 33%)    + wingbeat shockwaves (rings), double orb bursts, faster tells


func _configure() -> void:
	cfg.merge({
		"title": "AURELION, THE DAWN WYRM",
		"felled": "THE DAWN IS EXTINGUISHED",
		"phase_lines": [0.66, 0.33],
		"phase_names": ["First Light", "High Noon", "Eclipse"],
		"patterns": [
			[&"lanes", &"orbs", &"sweep", &"lanes", &"orbs"],
			[&"charge", &"lanes", &"rain", &"orbs", &"charge", &"summon", &"sweep"],
			[&"bells", &"charge", &"orbs", &"lanes", &"rain", &"sweep", &"charge"],
		],
		"minions": [[], ["light_wyrm", "light_wyrm", "clockwork_cherub", "clockwork_cherub"], ["light_wyrm", "light_wyrm", "seraph"]],
		"cooldown": [2.8, 2.4, 1.9],
		"tell_mult": [1.0, 0.9, 0.8],
		"keep_distance": 6.0,
		"hazard_tint": Color(1.0, 0.72, 0.3),
		"intro_color": Color(1.0, 0.85, 0.45),
	}, true)
