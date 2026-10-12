class_name HubLife
extends Node3D
## The living, growing part of Basecamp Hell: who toils and wanders in the camp, and what has been
## built so far. The camp's development level (0..3) comes from meta progress (camp_level()); each
## level adds set pieces and inhabitants on top of the previous ones:
##   0  ruined camp: damned souls hauling and quarrying stone by the lava edge, an imp porter
##   1  the Bloodwine Bar opens (Velka the succubus pours), tents, more imp porters
##   2  a spiked palisade on the south edge, a hellhound kennel with a brute keeper, more souls
##   3  a stone monument to the chosen demon, ringed by braziers and war banners
## New levels are announced once in the hub (Meta.camp_level_seen). Models come from the
## characters role (CharacterRoster: imp, hellhound, succubus, hell_brute) plus the hub's own
## DamnedSoul. NPCs placed by data/npcs/npcs.json "basecamp" are added by Basecamp separately.

## Development points needed for each camp level (index = level).
const LEVEL_POINTS: Array[int] = [0, 4, 15, 32]
## Announcement shown the first time each level is reached.
const LEVEL_NEWS: Array[String] = [
	"",
	"The Bloodwine Bar opens its doors. The camp is beginning to feel like home.",
	"The camp fortifies: a palisade, a kennel of hellhounds, more hands at the quarry.",
	"A monument rises to your infamy. All of Hell knows who walks out of that gate.",
	"The Reconquest: Heaven's banners hang upside down in your camp, and an archangel kneels in chains.",
]
## Display names per level (ledger).
const LEVEL_NAMES: Array[String] = ["Ruin", "Outpost", "Stronghold", "Citadel", "Seat of the Reconquest"]
## Level 4 is not bought with points: it comes with the ending (Dialogue flag "story.ended").
const ENDING_LEVEL := 4
const CAPTIVE := Vector3(2.9, 0.0, -3.4)
const THRONE := Vector3(-7.6, 0.0, 2.4)
const SOUL_SCENE := preload("res://scenes/basecamp/models/damned_soul.tscn")
## Damned souls are drawn this much larger than life so they read from the hub camera.
const SOUL_SCALE := 1.4
const BAR := Vector3(-12.2, 0.0, 2.6)
const QUARRY := Vector3(-9.5, 0.0, -11.2)
const KENNEL := Vector3(4.6, 0.0, 9.4)
const MONUMENT := Vector3(8.7, 0.0, -6.6)
## Lines Velka pours with a drink when the story role has no "velka" pool yet.
const BAR_LINES: Array[String] = [
	"Bloodwine, neat. You look like Heaven chewed on you a while.",
	"They say the Choir sings louder every time you fall. I say let them sing.",
	"{runs} descents and still standing. Well, mostly standing.",
	"Grimmaul burnt his eyebrows off again. Don't mention it.",
	"{kills} angels in the ledger. The Clerk smiles when he counts them. It's horrible.",
	"Drink up. The gate doesn't care if you're sober.",
]

var level := 0
var bartender: ProcModel
var _scenery: HubScenery
var _rng := RandomNumberGenerator.new()


## Development points from meta progress: every bought rank, unlock, run (up to 20), win and trophy.
static func camp_points() -> int:
	var pts := 0
	for k: String in Meta.upgrades:
		pts += int(Meta.upgrades[k])
	var tree := Engine.get_main_loop() as SceneTree
	var prog := tree.root.get_node_or_null(^"Progression") if tree else null
	if prog:
		var lv: Variant = prog.get(&"levels")
		if lv is Dictionary:
			for k: Variant in lv:
				pts += int(lv[k])
		var un: Variant = prog.get(&"unlocks")
		if un is Array:
			pts += (un as Array).size() * 2
	@warning_ignore("integer_division")
	pts += mini(int(Meta.stats.get("runs", 0)), 20) / 2
	pts += int(Meta.stats.get("victories", 0)) * 4
	pts += Meta.trophies.size() * 4
	return pts


## Camp level from camp_points() against LEVEL_POINTS; ENDING_LEVEL once the story has ended.
static func camp_level() -> int:
	var pts := camp_points()
	var lv := 0
	for i in LEVEL_POINTS.size():
		if pts >= LEVEL_POINTS[i]:
			lv = i
	if story_ended():
		lv = ENDING_LEVEL
	# Dev override: --camp=<0..4>.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camp="):
			lv = clampi(arg.substr(7).to_int(), 0, ENDING_LEVEL)
	return lv


## True once the story's ending has played (story role: Dialogue flag "story.ended").
static func story_ended() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var dlg := tree.root.get_node_or_null(^"Dialogue") if tree else null
	return dlg != null and bool(dlg.call(&"has_flag", "story.ended"))


## Builds everything up to the current camp level. Returns the news line for a level reached
## since the last visit ("" if none).
func build(scenery: HubScenery) -> String:
	_scenery = scenery
	_rng.seed = 1666
	level = camp_level()
	_build_quarry()
	_add_porter([Vector3(-7.0, 0.0, 0.5), Vector3(-3.2, 0.0, -2.0), Vector3(-6.0, 0.0, 4.0)])
	if level >= 1:
		_build_bar()
		_build_tents()
		_add_porter([Vector3(3.0, 0.0, -4.5), Vector3(6.2, 0.0, -3.2), Vector3(5.0, 0.0, 4.0)])
		_add_porter([Vector3(-9.0, 0.0, 8.8), Vector3(-2.0, 0.0, 6.5), Vector3(-10.5, 0.0, 4.5)])
	if level >= 2:
		_build_palisade()
		_build_kennel()
		for k in 3:
			_add_soul(1 if k == 0 else 0, [QUARRY + Vector3(2.5 - k, 0.0, 0.5), Vector3(-6.2 + k * 0.6, 0.0, -7.5)])
	if level >= 3:
		_build_monument()
	if level >= ENDING_LEVEL:
		_build_reconquest()
	var news := ""
	if level > Meta.camp_level_seen:
		news = LEVEL_NEWS[level]
		Meta.camp_level_seen = level
		Meta.save_game()
	return news


# ---------------------------------------------------------------- level 0: the quarry

## Rubble heap at the lava edge where the damned cut stone, and the souls who haul it.
func _build_quarry() -> void:
	var stone := Art.mat(Color(0.2, 0.16, 0.15), 0.9, 0.0, 0.55, false, 0.0, &"stone")
	for k in 9:
		var p := QUARRY + Vector3(_rng.randf_range(-1.6, 1.6), 0.0, _rng.randf_range(-0.8, 0.8))
		var s := _rng.randf_range(0.35, 0.9)
		Art.part(self, Art.box(), stone, p + Vector3(0.0, s * 0.35, 0.0), Vector3(s, s * 0.7, s * 0.8),
				Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3)))
	# Finished blocks stacked by the gate path.
	for k in 4:
		@warning_ignore("integer_division")
		Art.part(self, Art.box(), stone, Vector3(-6.0 + (k % 2) * 0.62, 0.22 + (k / 2) * 0.44, -7.0),
				Vector3(0.58, 0.42, 0.42))
	_scenery.add_post(QUARRY, 1.6)
	_scenery.add_flicker(Art.light(self, Color(1.0, 0.6, 0.3), 2.6, 6.0, QUARRY + Vector3(1.0, 2.4, 1.6)))
	_scenery.add_post(Vector3(-5.7, 0.0, -7.0), 0.7)
	# A pick-swinger at the face, two haulers on the loop to the stack.
	_add_soul(1, [QUARRY + Vector3(0.0, 0.0, 1.3), QUARRY + Vector3(1.2, 0.0, 1.1)])
	_add_soul(0, [QUARRY + Vector3(1.8, 0.0, 1.0), Vector3(-6.6, 0.0, -6.3), Vector3(-7.5, 0.0, -8.6)])
	_add_soul(2, [Vector3(-7.8, 0.0, -9.6), QUARRY + Vector3(-1.4, 0.0, 1.2)])


func _add_soul(task: int, path: Array) -> void:
	var m := SOUL_SCENE.instantiate() as ProcModel
	m.set(&"task", task)
	# Readable from the camera height: a bit larger than life and a cold soul-light rim.
	m.scale = Vector3.ONE * SOUL_SCALE
	m.body_scale = SOUL_SCALE
	var w := HubWanderer.create(m, path, 0.9)
	if task == 1:
		w.stop_gesture = 0
		w.gestures_per_stop = 3
	add_child(w)
	ArtStyle.set_rim(m, Color(0.55, 0.95, 0.9, 0.85))


func _add_porter(path: Array) -> void:
	var m := CharacterRoster.make_ally(&"imp")
	if m == null:
		return
	m.set(&"outfit", 1)
	var w := HubWanderer.create(m, path, 2.2)
	w.pause_range = Vector2(0.8, 2.5)
	add_child(w)


# ---------------------------------------------------------------- level 1: the Bloodwine Bar

func _build_bar() -> void:
	var root := Art.pivot(self, BAR, Vector3(0.0, -PI * 0.5, 0.0))  # counter faces east (+X)
	var wood := Art.mat(Color(0.2, 0.08, 0.06), 0.55, 0.0, 0.4, false, 0.2, &"wood")
	var top := Art.mat(Art.OBSIDIAN, 0.25, 0.3, 0.2, false, 0.3, &"stone")
	var bone := Art.mat(Art.BONE, 0.7, 0.0, 0.5, false, 0.0, &"bone")
	# Counter, back shelf of glowing bottles, a skull-lamp, an awning on bone posts.
	Art.part(root, Art.box(), wood, Vector3(0.0, 0.55, -0.6), Vector3(3.0, 1.1, 0.6))
	Art.part(root, Art.box(), top, Vector3(0.0, 1.13, -0.6), Vector3(3.2, 0.08, 0.75))
	Art.part(root, Art.box(), wood, Vector3(0.0, 1.0, 0.9), Vector3(3.0, 2.0, 0.3))
	var colors: Array[Color] = [Art.CRIMSON, Color(0.6, 0.2, 0.9), UIPalette.SOUL, Art.EMBER]
	for row in 2:
		Art.part(root, Art.box(), wood, Vector3(0.0, 1.0 + row * 0.55, 0.7), Vector3(2.8, 0.05, 0.25))
		for k in 7:
			var h := _rng.randf_range(0.2, 0.32)
			Art.part(root, Art.cylinder(0.5, 0.5), Art.glow(colors[(k + row) % colors.size()], 1.4, true, 0.8),
					Vector3(-1.2 + k * 0.4, 1.03 + row * 0.55 + h * 0.5, 0.68), Vector3(0.1, h, 0.1))
	for s: float in [-1.0, 1.0]:
		Art.part(root, Art.cylinder(0.05, 0.07), bone, Vector3(s * 1.6, 1.3, -1.1), Vector3(1.0, 2.6, 1.0))
	# Goblets on the counter and three stools of stacked skulls.
	for k in 3:
		Art.part(root, Art.cylinder(0.5, 0.3), Art.mat(Art.GOLD, 0.3, 1.0, 0.3, false, 0.0, &"gold"),
				Vector3(-0.9 + k * 0.8, 1.23, -0.7), Vector3(0.09, 0.12, 0.09))
		Art.part(root, Art.cylinder(0.5, 0.5), bone, Vector3(-1.0 + k * 1.0, 0.35, -1.5), Vector3(0.4, 0.7, 0.4))
	var lamp := Art.light(root, Color(1.0, 0.45, 0.25), 3.2, 6.5, Vector3(0.0, 2.2, -0.6))
	lamp.light_specular = 0.5
	_scenery.add_flicker(lamp)
	_scenery.add_post(BAR + Vector3(0.6, 0.0, 0.0), 1.2)
	_scenery.add_post(BAR + Vector3(0.6, 0.0, 1.2), 0.6)
	_scenery.add_post(BAR + Vector3(0.6, 0.0, -1.2), 0.6)
	# Velka behind the counter.
	bartender = CharacterRoster.make_ally(&"succubus")
	if bartender:
		# Barkeep pose (characters-new): goblet + rag, polishing; talk() slides a drink across.
		bartender.set(&"barkeep", true)
		bartender.idle_gesture_every = 7.0
		bartender.position = BAR + Vector3(-0.4, 0.0, 0.0)
		bartender.rotation.y = -PI * 0.5
		add_child(bartender)
	var it := HubInteractable.new()
	it.verb = "Have a drink"
	it.label = "The Bloodwine Bar"
	it.radius = 2.4
	it.prompt_height = 3.2
	it.position = BAR + Vector3(1.4, 0.0, 0.0)
	it.highlight = bartender
	add_child(it)
	it.interacted.connect(_on_drink)


func _on_drink() -> void:
	if bartender:
		bartender.talk()
	Sfx.play(&"chalice", 0.1, -4.0)
	var dlg := get_node_or_null(^"/root/Dialogue")
	if dlg == null:
		return
	if dlg.call(&"bark", "velka") != "":
		return  # the story role wrote lines for her
	var line := BAR_LINES[_rng.randi() % BAR_LINES.size()]
	line = line.replace("{runs}", str(int(Meta.stats.get("runs", 0)))).replace(
			"{kills}", str(int(Meta.stats.get("total_kills", 0))))
	dlg.call(&"say", "velka", line)


func _build_tents() -> void:
	var hide_mat := Art.mat(Color(0.3, 0.16, 0.12), 0.9, 0.0, 0.5, false, 0.0, &"leather")
	var bone := Art.mat(Art.BONE.darkened(0.15), 0.7, 0.0, 0.5, false, 0.0, &"bone")
	for spot: Vector3 in [Vector3(-13.2, 0.0, -1.6), Vector3(13.4, 0.0, -1.8)]:
		var root := Art.pivot(self, spot, Vector3(0.0, _rng.randf_range(-0.4, 0.4), 0.0))
		# A hide_mat stretched over a ridge of bones.
		Art.part(root, Art.prism(), hide_mat, Vector3(0.0, 0.8, 0.0), Vector3(2.0, 1.6, 2.2))
		Art.part(root, Art.cylinder(0.04, 0.05), bone, Vector3(0.0, 0.9, 0.0), Vector3(1.0, 1.8, 1.0),
				Vector3(PI * 0.5, 0.0, 0.0))
		Art.part(root, Art.box(), Art.mat(Color(0.05, 0.02, 0.02), 1.0), Vector3(0.0, 0.45, -1.11),
				Vector3(0.6, 0.85, 0.02))
		_scenery.add_post(spot, 1.1)


# ---------------------------------------------------------------- level 2: palisade and kennel

func _build_palisade() -> void:
	var wood := Art.mat(Color(0.14, 0.09, 0.07), 0.85, 0.0, 0.5, false, 0.0, &"wood")
	var iron := Art.mat(Art.OBSIDIAN, 0.4, 0.8, 0.4, false, 0.0, &"metal")
	var x := HubScenery.X0 + 0.5
	while x < HubScenery.X1 - 0.3:
		if absf(x) > 1.6:  # leave the middle open
			var h := _rng.randf_range(1.3, 1.9)
			var stake := Art.part(self, Art.cylinder(0.04, 0.12), wood,
					Vector3(x, h * 0.5, HubScenery.Z1 + 0.3), Vector3(1.0, h, 1.0),
					Vector3(_rng.randf_range(-0.25, -0.1), 0.0, _rng.randf_range(-0.1, 0.1)))
			stake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if _rng.randf() < 0.2:
				Art.part(self, Art.sphere(), Art.mat(Art.BONE, 0.7, 0.0, 0.5, false), Vector3(x, h + 0.05, HubScenery.Z1 + 0.15),
						Vector3(0.2, 0.18, 0.22))
		x += 0.55
	Art.part(self, Art.box(), iron, Vector3(0.0, 0.5, HubScenery.Z1 + 0.35), Vector3(HubScenery.X1 * 2.0 - 1.0, 0.06, 0.06))
	for s: float in [-1.0, 1.0]:
		var b := Props.banner(_rng)
		b.position = Vector3(s * 2.4, 0.0, HubScenery.Z1 - 0.2)
		add_child(b)


func _build_kennel() -> void:
	var root := Art.pivot(self, KENNEL)
	var stone := Art.mat(Color(0.18, 0.13, 0.12), 0.9, 0.0, 0.6, false, 0.0, &"stone")
	var iron := Art.mat(Art.OBSIDIAN, 0.4, 0.8, 0.4, false, 0.0, &"metal")
	# Low stone pen with iron bars and a gnawed-bone floor.
	Art.part(root, Art.box(), stone, Vector3(0.0, 0.3, 1.0), Vector3(3.6, 0.6, 0.3))
	for s: float in [-1.0, 1.0]:
		Art.part(root, Art.box(), stone, Vector3(s * 1.8, 0.3, 0.0), Vector3(0.3, 0.6, 2.3))
	for k in 9:
		Art.part(root, Art.cylinder(0.03, 0.03), iron, Vector3(-1.6 + k * 0.4, 0.95, 1.0), Vector3(1.0, 0.7, 1.0))
	_scenery.add_post(KENNEL + Vector3(-1.2, 0.0, 0.4), 0.9)
	_scenery.add_post(KENNEL + Vector3(1.2, 0.0, 0.4), 0.9)
	for k in 2:
		var hound := CharacterRoster.spawn_npc(root, &"hellhound_resting", Vector3(-0.8 + k * 1.5, 0.0, 0.2),
				PI + _rng.randf_range(-0.6, 0.6))
		if hound:
			hound.idle_gesture_every = 6.0
	# One hound loose on patrol around the plaza, and the brute who keeps them.
	var loose := CharacterRoster.make_ally(&"hellhound")
	if loose:
		var w := HubWanderer.create(loose, [Vector3(2.5, 0.0, 6.5), Vector3(6.0, 0.0, 2.0),
				Vector3(4.0, 0.0, -3.5), Vector3(-1.5, 0.0, -5.0), Vector3(-5.5, 0.0, 1.5)], 2.6)
		w.pause_range = Vector2(1.0, 3.0)
		add_child(w)
	var keeper := CharacterRoster.spawn_npc(self, &"hell_brute", KENNEL + Vector3(2.4, 0.0, -0.6), PI + 0.5)
	if keeper:
		keeper.idle_gesture_every = 9.0
	var l := Art.light(root, Color(1.0, 0.5, 0.2), 1.6, 5.0, Vector3(0.0, 1.8, -0.4))
	_scenery.add_flicker(l)


# ---------------------------------------------------------------- level 3: the monument

## The chosen demon, carved in black stone three times life size, on a plinth between braziers.
func _build_monument() -> void:
	var root := Art.pivot(self, MONUMENT)
	var stone := Art.mat(Color(0.16, 0.13, 0.13), 0.75, 0.0, 0.5, false, 0.15, &"stone")
	Art.part(root, Art.box(), stone, Vector3(0.0, 0.4, 0.0), Vector3(2.0, 0.8, 2.0))
	Art.part(root, Art.box(), stone, Vector3(0.0, 0.95, 0.0), Vector3(1.5, 0.3, 1.5))
	Art.part(root, Art.box(), Art.glow(Art.HELLFIRE, 1.8, false), Vector3(0.0, 0.8, -1.01), Vector3(1.2, 0.08, 0.02))
	var demon := Game.selected_character as DemonData
	if demon == null:
		demon = load(HubAvatar.DEFAULT_DEMON) as DemonData
	var statue := GlbModel.create(demon.get_model_path(), false)
	# Faces the plaza (south-west), towering over the camp.
	statue.rotation.y = -0.6  # the raw model faces +Z; turn it toward the plaza (south-west)
	statue.scale = Vector3.ONE * 1.9
	statue.position = Vector3(0.0, 1.1, 0.0)
	root.add_child(statue)
	# Frozen mid-roar and turned to stone.
	if statue.anim_player:
		statue.play(&"idle", 0.0)
		statue.anim_player.seek(0.4, true)
		statue.anim_player.pause()
	_stone_over(statue, Art.mat(Color(0.36, 0.31, 0.3), 0.7, 0.0, 0.6, false, 0.1, &"stone"))
	for s: float in [-1.0, 1.0]:
		var br := Props.brazier(_rng)
		br.position = MONUMENT + Vector3(s * 1.7, 0.0, 1.0)
		add_child(br)
	var up := Art.light(root, Color(1.0, 0.5, 0.2), 4.5, 8.0, Vector3(-0.8, 0.8, 2.2))
	_scenery.add_flicker(up)
	_scenery.add_post(MONUMENT, 1.3)


func _stone_over(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_stone_over(c, m)


# ---------------------------------------------------------------- level 4: the Reconquest

## After the ending: Heaven's captured banners hang upside down around the gate, an archangel
## kneels in chains by the processional path, and the empty chair from the ending stands as a
## throne ("sit") or lies in pieces ("break", Dialogue var ending.choice). The camp's light turns
## a warmer, triumphant gold (Atmosphere overlay, pushed by Basecamp).
func _build_reconquest() -> void:
	var holy_cloth := Art.mat(Color(0.88, 0.84, 0.72), 0.85, 0.0, 0.5, false, 0.0, &"cloth")
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.3, false, 0.0, &"gold")
	var iron := Art.mat(Art.OBSIDIAN, 0.4, 0.8, 0.4, false, 0.0, &"metal")
	# Upside-down holy banners on iron poles, slashed with a burning cross-stroke.
	for x: float in [-6.4, -2.6, 2.6, 6.4]:
		var root := Art.pivot(self, Vector3(x, 0.0, -7.9 if absf(x) < 4.0 else -9.4))
		Art.part(root, Art.cylinder(0.04, 0.05), iron, Vector3(0.0, 1.6, 0.0), Vector3(1.0, 3.2, 1.0))
		Art.part(root, Art.box(), iron, Vector3(0.0, 3.15, 0.0), Vector3(1.0, 0.05, 0.05))
		Art.part(root, Art.box(), holy_cloth, Vector3(0.0, 2.3, 0.05), Vector3(0.9, 1.6, 0.03))
		Art.part(root, Art.prism(), holy_cloth, Vector3(0.0, 1.3, 0.05), Vector3(0.9, 0.4, 0.03), Vector3(0.0, 0.0, PI))
		Art.part(root, Art.torus(0.8, 1.0), gold, Vector3(0.0, 2.0, 0.08), Vector3(0.3, 0.3, 0.3), Vector3(PI * 0.5, 0.0, 0.0))
		var slash := Art.part(root, Art.box(), Art.glow(Art.HELLFIRE, 2.0), Vector3(0.0, 2.3, 0.075),
				Vector3(1.1, 0.06, 0.01), Vector3(0.0, 0.0, 0.9))
		slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_scenery.add_post(root.position, 0.2)
	_build_captive(iron)
	_build_chair()


## An archangel (characters role model) kneeling between two iron posts, chained at the wrists.
func _build_captive(iron: Material) -> void:
	var root := Art.pivot(self, CAPTIVE, Vector3(0.0, PI - 0.3, 0.0))
	for s: float in [-1.0, 1.0]:
		Art.part(root, Art.cylinder(0.06, 0.08), iron, Vector3(s * 1.1, 1.0, 0.0), Vector3(1.0, 2.0, 1.0))
		for k in 5:
			Art.part(root, Art.torus(0.7, 1.0), iron, Vector3(s * (1.0 - k * 0.16), 1.55 - k * 0.07, 0.0),
					Vector3(0.07, 0.07, 0.07), Vector3(PI * 0.5 * (k % 2), 0.0, PI * 0.5))
	var path := "res://scenes/characters/enemies/archangel.tscn"
	if ResourceLoader.exists(path):
		var angel := (load(path) as PackedScene).instantiate() as Node3D
		angel.set(&"autoplay", true)
		angel.position = Vector3(0.0, -0.35, 0.0)  # sunk to its knees
		angel.scale = Vector3.ONE * 0.95
		root.add_child(angel)
		# Its holy light is dimmed: a captive, not a threat.
		ArtStyle.set_rim(angel, Color(1.0, 0.85, 0.5, 0.25))
	_scenery.add_flicker(Art.light(root, Color(1.0, 0.85, 0.55), 1.4, 4.0, Vector3(0.0, 2.4, 0.8)))
	_scenery.add_post(CAPTIVE, 1.2)


## The empty chair from the ending: raised as a throne of fused halos, or left broken.
func _build_chair() -> void:
	var choice := ""
	var tree := get_tree()
	var dlg := tree.root.get_node_or_null(^"Dialogue") if tree else null
	if dlg:
		choice = String(dlg.call(&"get_var", "ending.choice", ""))
	var root := Art.pivot(self, THRONE, Vector3(0.0, PI * 0.5 + 0.4, 0.0))
	var stone := Art.mat(Art.OBSIDIAN.lightened(0.05), 0.4, 0.2, 0.3, false, 0.2, &"stone")
	var gold := Art.mat(Art.GOLD.darkened(0.2), 0.35, 1.0, 0.3, false, 0.0, &"gold")
	if choice == "break":
		# Shattered: seat, legs and back strewn across a scorched slab.
		Art.part(root, Art.cylinder(0.5, 0.5), Art.mat(Color(0.08, 0.06, 0.05), 0.95), Vector3(0.0, 0.02, 0.0),
				Vector3(2.4, 0.04, 2.4))
		Art.part(root, Art.box(), stone, Vector3(0.3, 0.15, 0.2), Vector3(0.9, 0.18, 0.8), Vector3(0.2, 0.6, 0.15))
		Art.part(root, Art.box(), stone, Vector3(-0.6, 0.2, -0.4), Vector3(0.9, 1.3, 0.16), Vector3(PI * 0.45, 0.3, 0.0))
		for k in 3:
			Art.part(root, Art.box(), stone, Vector3(-0.2 + k * 0.4, 0.08, 0.7 - k * 0.3), Vector3(0.12, 0.6, 0.12),
					Vector3(PI * 0.5, k * 0.9, 0.0))
		Art.part(root, Art.torus(0.8, 1.0), gold, Vector3(0.8, 0.05, -0.5), Vector3(0.35, 0.35, 0.35), Vector3(0.0, 0.0, 0.1))
	else:
		# Raised: a high-backed black throne crowned with fused, blackened halos.
		Art.part(root, Art.box(), stone, Vector3(0.0, 0.25, 0.0), Vector3(1.6, 0.5, 1.4))
		Art.part(root, Art.box(), stone, Vector3(0.0, 0.75, 0.0), Vector3(1.0, 0.5, 0.9))
		Art.part(root, Art.box(), stone, Vector3(0.0, 1.9, 0.38), Vector3(1.0, 2.0, 0.18))
		for s: float in [-1.0, 1.0]:
			Art.part(root, Art.box(), stone, Vector3(s * 0.5, 1.15, 0.0), Vector3(0.14, 0.35, 0.9))
			Art.part(root, Art.cone(0.5), stone, Vector3(s * 0.45, 3.1, 0.38), Vector3(0.18, 0.6, 0.18), Vector3(0.0, 0.0, -s * 0.3))
		for k in 3:
			Art.part(root, Art.torus(0.82, 1.0), gold, Vector3(0.0, 2.6 + k * 0.12, 0.38), Vector3(0.45, 0.45, 0.45) * (1.0 - k * 0.15),
					Vector3(PI * 0.5, 0.0, 0.0))
		var ember := Art.part(root, Art.sphere(), Art.glow(Art.HELLFIRE, 2.6), Vector3(0.0, 2.65, 0.3), Vector3.ONE * 0.12)
		ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scenery.add_flicker(Art.light(root, Color(1.0, 0.6, 0.3), 2.0, 5.0, Vector3(0.0, 2.8, -1.4)))
	_scenery.add_post(THRONE, 0.9)
