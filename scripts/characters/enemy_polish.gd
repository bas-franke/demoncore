class_name EnemyPolish
## Per-model presentation tuning for enemy models, applied by EnemyModel after build()
## (characters-polish). Kept here so the model scripts (characters-new, Blender angels) stay
## untouched: readability scale for models that are too small to read from the game camera, and
## the faction death style (DeathFx) of each code-built enemy.

## Extra visual scale (the collision / EnemyData.size is unchanged): tiny models that vanish at the
## game camera's distance. Applied to EnemyModel.pose_pivot.
const VISUAL_SCALE := {
	&"ophan": 1.9,
	&"clockwork_cherub": 1.45,
	&"cherub": 1.15,
	&"choir_wraith": 1.25,
	&"martyr_shade": 1.25,
	&"bell_gargoyle": 1.25,
	# Siege pieces: from the high camera they read as small carts next to the knights; scaled up
	# so they look like the heavy engines they are (round 3 lineup).
	&"templar_ballista": 1.3,
	&"mobile_reliquary": 1.2,
	# Round 4 map-signature enemies (lineup at the game camera).
	&"hummingbird_cherub": 2.2,
	&"bell_ringer_monk": 1.15,
	&"rod_acolyte": 1.15,
	&"sun_priest": 1.1,
	&"crusader_revenant": 1.15,
	&"exorcist": 1.1,
	&"frost_hermit": 1.1,
	&"plague_doctor": 1.1,
	&"inquisitor": 1.08,
}
## Death style overrides by model id (default: by CharacterRoster faction, see DeathFx).
const DEATH_STYLE := {
	&"martyr_shade": &"shatter",   # a ghost: comes apart in light rather than falling over
	&"light_wyrm": &"shatter",
	# Round 4 signatures: the revenant falls to the ashes it rises from, the penitent's ice tomb
	# and the topiary guardian break apart rather than topple.
	&"crusader_revenant": &"crumble",
	&"icebound_penitent": &"crumble",
	&"thorn_guardian": &"crumble",
}


## Model id: the model scene's file name (res://scenes/characters/enemies/paladin.tscn -> paladin).
static func model_id(model: Node) -> StringName:
	var path := model.scene_file_path
	return StringName(path.get_file().get_basename()) if path != "" else &""


static func apply(model: EnemyModel) -> void:
	var id := model_id(model)
	if id == &"":
		return
	model.visual_scale = float(VISUAL_SCALE.get(id, 1.0))
	model.death_variant = death_style(id)


static func death_style(id: StringName) -> StringName:
	if DEATH_STYLE.has(id):
		return DEATH_STYLE[id]
	var info: Dictionary = CharacterRoster.ENEMIES.get(id, {})
	if info.is_empty():
		return &""
	return DeathFx.style_for_faction(StringName(info.get("faction", &"")))
