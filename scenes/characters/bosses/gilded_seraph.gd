extends ProcBoss
## "Aurum, the Gilded Seraph" (boss, gilded isles). See gilded_seraph_model.gd.
##   I   The Counting (100-66%)  coin bursts (orbs), golden beams (lanes), wing slashes
##   II  The Tithe    (66-33%)   + falling gold (pillar rain), the hoard slammed down (rings),
##                               clockwork cherubs join
##   III Avarice      (< 33%)    + gold that hunts the demon, dives, a reliquary joins


func _configure() -> void:
	cfg.merge({
		"title": "AURUM, THE GILDED SERAPH",
		"felled": "THE HOARD IS SPILLED",
		"phase_names": ["The Counting", "The Tithe", "Avarice"],
		"patterns": [
			[&"orbs", &"lanes", &"sweep", &"orbs", &"lanes"],
			[&"rain", &"orbs", &"bells", &"sweep", &"summon", &"lanes"],
			[&"chase", &"charge", &"orbs", &"rain", &"bells", &"sweep", &"cross"],
		],
		"minions": [[], ["clockwork_cherub", "clockwork_cherub", "clockwork_cherub", "cherub", "cherub"],
			["mobile_reliquary", "clockwork_cherub", "clockwork_cherub"]],
		"cooldown": [2.8, 2.4, 1.9],
		"tell_mult": [1.0, 0.9, 0.8],
		"keep_distance": 5.5,
		"hazard_tint": Color(1.0, 0.78, 0.25),
		"intro_color": Color(1.0, 0.85, 0.4),
	}, true)
