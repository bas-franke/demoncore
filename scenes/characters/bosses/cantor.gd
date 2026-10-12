extends ProcBoss
## "Cantor Seraphiel, the Broken Choir" (boss, ruined sanctum variant). See cantor_model.gd.
##   I   Introit   (100-66%)  sung rings (bells), baton cuts (lanes), notes that fall on the demon
##   II  Requiem   (66-33%)   + a burst of notes (orbs), crossing cuts, choir wraiths join
##   III Dies Irae (< 33%)    + note rain, arms brought down (fire disc), martyrs join


func _configure() -> void:
	cfg.merge({
		"title": "CANTOR SERAPHIEL, THE BROKEN CHOIR",
		"felled": "THE HYMN ENDS",
		"phase_names": ["Introit", "Requiem", "Dies Irae"],
		"patterns": [
			[&"bells", &"lanes", &"chase", &"bells", &"lanes"],
			[&"orbs", &"bells", &"cross", &"summon", &"chase", &"lanes"],
			[&"bells", &"rain", &"orbs", &"pyre", &"cross", &"bells", &"summon"],
		],
		"minions": [[], ["choir_wraith", "choir_wraith", "choir_wraith"],
			["choir_wraith", "choir_wraith", "martyr", "martyr"]],
		"cooldown": [2.8, 2.4, 2.0],
		"tell_mult": [1.0, 0.92, 0.82],
		"hazard_tint": Color(0.85, 0.78, 1.0),
		"intro_color": Color(0.88, 0.85, 1.0),
	}, true)
