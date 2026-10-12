class_name HubBoards
extends Node3D
## The Ledger of the Damned (a basalt obelisk with Meta.stats burned into it) and the trophy wall
## (one plaque per boss in data/bosses/bosses.json; a boss's trophy is mounted after its first
## kill, Meta.trophies). Both are HubInteractables that open a HubBoardUI. Emits `opened` /
## the hub freezes the avatar while the board is up.

signal board_opened
## The player accepted today's trial at the Board of Trials (DailyChallenge dictionary).
signal trial_accepted(trial: Dictionary)

const LEDGER := Vector3(-5.6, 0.0, -1.6)
const WALL := Vector3(9.6, 0.0, -11.7)
const WALL_WIDTH := 4.6
const TRIALS := Vector3(-4.8, 0.0, -5.4)
## Trophy colours per boss id (anything else gets holy gold).
const TROPHY_COLORS := {"sariel": Color(1.0, 0.86, 0.5), "grand_inquisitor": Color(0.85, 0.25, 0.2)}

var board: HubBoardUI
var _scenery: HubScenery
var _ledger_glow: MeshInstance3D


func build(scenery: HubScenery, ui: HubBoardUI) -> void:
	_scenery = scenery
	board = ui
	_build_ledger()
	_build_wall()
	_build_trials()


# ---------------------------------------------------------------- the ledger

func _build_ledger() -> void:
	var root := Art.pivot(self, LEDGER, Vector3(0.0, PI + 0.35, 0.0))  # carved face (local -Z) toward the plaza
	var basalt := Art.mat(Color(0.1, 0.08, 0.08), 0.6, 0.0, 0.4, false, 0.2, &"stone")
	Art.part(root, Art.box(), basalt, Vector3(0.0, 0.15, 0.0), Vector3(1.3, 0.3, 1.0))
	Art.part(root, Art.cylinder(0.32, 0.45), basalt, Vector3(0.0, 1.3, 0.0), Vector3(1.0, 2.2, 0.55))
	Art.part(root, Art.cone(0.5), basalt, Vector3(0.0, 2.65, 0.0), Vector3(0.62, 0.55, 0.35))
	# Glowing tally marks burned into its face (a row per hundred souls, roughly).
	@warning_ignore("integer_division")
	var marks := mini(6, 1 + int(Meta.stats.get("souls_earned", 0)) / 150)
	for row in marks:
		for k in 5:
			var x := -0.18 + k * 0.08
			var slash := Art.part(root, Art.box(), Art.glow(Art.EMBER, 1.6), Vector3(x if k < 4 else 0.0, 0.7 + row * 0.25, -0.26),
					Vector3(0.02 if k < 4 else 0.38, 0.17 if k < 4 else 0.02, 0.01), Vector3(0.0, 0.0, 0.0 if k < 4 else -0.5))
			slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ledger_glow = Art.part(root, Art.sphere(), Art.glow(Art.EMBER, 2.4), Vector3(0.0, 2.5, -0.15), Vector3.ONE * 0.14)
	_scenery.add_flicker(Art.light(root, Color(1.0, 0.5, 0.2), 1.3, 3.5, Vector3(0.0, 1.6, -0.9)))
	_scenery.add_post(LEDGER, 0.6)
	var it := _interactable("Read", "The Ledger of the Damned", LEDGER + Vector3(0.0, 0.0, 0.6), 1.8, 3.2)
	it.interacted.connect(open_ledger)


## Shows the Ledger board: lifetime stats, upgrade ranks and the camp level.
func open_ledger() -> void:
	var s := Meta.stats
	var ranks := 0
	for k: String in Meta.upgrades:
		ranks += int(Meta.upgrades[k])
	var t := int(float(s.get("best_time", 0.0)))
	var level := HubLife.camp_level()
	var pts := HubLife.camp_points()
	var next_note := "%d / %d toward the next stage of the camp." % [pts, HubLife.LEVEL_POINTS[level + 1]] \
		if level + 1 < HubLife.LEVEL_POINTS.size() else "The camp has grown as far as stone allows."
	if level == HubLife.LEVEL_POINTS.size() - 1 and not HubLife.story_ended():
		next_note = "Only the end of the story can raise it further."
	elif level >= HubLife.ENDING_LEVEL:
		next_note = "The Reconquest has begun. The camp is a capital now."
	var trophies := Meta.boss_trophies()
	var mounted := 0
	for boss_rec in trophies:
		if boss_rec.unlocked:
			mounted += 1
	var rows: Array = [
		{"label": "Descents", "value": str(int(s.get("runs", 0)))},
		{"label": "Triumphs", "value": str(int(s.get("victories", 0)))},
		{"label": "Angels slain", "value": str(int(s.get("total_kills", 0)))},
		{"label": "Longest survival", "value": TextFormat.clock(t)},
		{"label": "Souls earned, all told", "value": str(int(s.get("souls_earned", 0))), "color": UIPalette.SOUL},
		{"label": "Souls in hand", "value": str(Meta.souls), "color": UIPalette.SOUL},
		{"label": "Ranks bought from the merchants", "value": str(ranks)},
		{"label": "Trophies mounted", "value": "%d / %d" % [mounted, trophies.size()]},
		{"label": "The camp", "value": HubLife.LEVEL_NAMES[level], "note": next_note},
	]
	_open("The Ledger of the Damned", "Every soul, every death, every debt. Mammon's Clerk keeps it; the stone remembers it.", rows)


# ---------------------------------------------------------------- the trophy wall

func _build_wall() -> void:
	var root := Art.pivot(self, WALL)
	var stone := Art.mat(Color(0.15, 0.11, 0.1), 0.85, 0.0, 0.55, false, 0.0, &"stone")
	var iron := Art.mat(Art.OBSIDIAN, 0.4, 0.8, 0.4, false, 0.0, &"metal")
	Art.part(root, Art.box(), stone, Vector3(0.0, 1.5, 0.0), Vector3(WALL_WIDTH, 3.0, 0.5))
	Art.part(root, Art.box(), stone, Vector3(0.0, 3.1, 0.05), Vector3(WALL_WIDTH + 0.4, 0.25, 0.7))
	for s: float in [-1.0, 1.0]:
		Art.part(root, Art.cone(0.5), Art.mat(Art.BONE, 0.7, 0.0, 0.5, false, 0.0, &"bone"),
				Vector3(s * (WALL_WIDTH * 0.5 + 0.1), 3.6, 0.05), Vector3(0.25, 0.9, 0.25), Vector3(0.0, 0.0, -s * 0.4))
	var trophies := Meta.boss_trophies()
	var n := maxi(trophies.size(), 1)
	for i in trophies.size():
		var entry: Dictionary = trophies[i]
		var x := lerpf(-WALL_WIDTH * 0.5, WALL_WIDTH * 0.5, (i + 0.5) / n)
		var plaque := Art.pivot(root, Vector3(x, 1.75, 0.27))
		# Iron shield-plaque; a mounted trophy once the boss has fallen, a chained seal before.
		Art.part(plaque, Art.cylinder(0.5, 0.5), iron, Vector3.ZERO, Vector3(1.1, 0.06, 1.3), Vector3(PI * 0.5, 0.0, 0.0))
		if entry.unlocked:
			_trophy(plaque, TROPHY_COLORS.get(entry.id, Art.HOLY))
			var name_l := Label3D.new()
			name_l.text = String(entry.name)
			name_l.font_size = 22
			name_l.pixel_size = 0.006
			name_l.outline_size = 6
			name_l.modulate = UIPalette.BRIMSTONE
			name_l.position = Vector3(0.0, -0.85, 0.05)
			plaque.add_child(name_l)
		else:
			for k in 2:
				Art.part(plaque, Art.box(), iron, Vector3(0.0, 0.0, 0.06), Vector3(1.0, 0.06, 0.04),
						Vector3(0.0, 0.0, 0.7 if k == 0 else -0.7))
			Art.part(plaque, Art.box(), Art.mat(Color(0.25, 0.22, 0.2), 0.5, 0.8), Vector3(0.0, 0.0, 0.1),
					Vector3(0.18, 0.2, 0.06))
	_scenery.add_flicker(Art.light(root, Color(1.0, 0.75, 0.45), 2.4, 5.5, Vector3(0.0, 2.6, 1.8)))
	_scenery.add_post(WALL + Vector3(-WALL_WIDTH * 0.25, 0.0, 0.0), 1.2)
	_scenery.add_post(WALL + Vector3(WALL_WIDTH * 0.25, 0.0, 0.0), 1.2)
	var it := _interactable("Admire", "Wall of Fallen Heralds", WALL + Vector3(0.0, 0.0, 1.6), 2.6, 3.8)
	it.interacted.connect(open_trophies)


## A mounted holy trophy: a broken halo over crossed, torn wings and the boss's stolen heart-gem.
func _trophy(parent: Node3D, color: Color) -> void:
	var gold := Art.mat(color.lerp(Art.GOLD, 0.5), 0.3, 1.0, 0.2, false, 0.0, &"gold")
	var feather := Art.mat(Art.IVORY, 0.8, 0.0, 0.3, false, 0.0, &"feather")
	for s: float in [-1.0, 1.0]:
		Art.part(parent, Art.box(), feather, Vector3(s * 0.28, 0.0, 0.08), Vector3(0.62, 0.22, 0.04),
				Vector3(0.0, 0.0, s * 0.6))
	Art.part(parent, Art.torus(0.82, 1.0), gold, Vector3(0.0, 0.32, 0.1), Vector3(0.32, 0.32, 0.32), Vector3(PI * 0.5, 0.0, 0.0))
	var gem := Art.part(parent, Art.sphere(), Art.glow(color, 2.6), Vector3(0.0, -0.05, 0.14), Vector3.ONE * 0.16)
	gem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Shows the trophy wall: one row per boss slain (kills, first kill date, by which demon).
func open_trophies() -> void:
	var rows: Array = []
	for boss_rec in Meta.boss_trophies():
		if boss_rec.unlocked:
			var when := Time.get_date_string_from_unix_time(int(boss_rec.first_kill)) if int(boss_rec.first_kill) > 0 else ""
			var by := (" by %s" % boss_rec.demon) if String(boss_rec.demon) != "" else ""
			rows.append({"label": String(boss_rec.name), "value": "slain %d×" % int(boss_rec.kills),
					"note": "First cast down%s%s." % [by, (" on " + when) if when != "" else ""]})
		else:
			rows.append({"label": "An empty mount", "value": "—", "dim": true,
					"note": "Some herald of Heaven still flies. Bring back its halo."})
	_open("Wall of Fallen Heralds", "Every Herald of Heaven you cast down leaves something to hang here.", rows)


# ---------------------------------------------------------------- the board of trials

## A notice board of charred planks with today's trial nailed to it (DailyChallenge).
func _build_trials() -> void:
	var root := Art.pivot(self, TRIALS, Vector3(0.0, PI + 0.4, 0.0))  # notices (local -Z) face the plaza
	var wood := Art.mat(Color(0.16, 0.1, 0.07), 0.85, 0.0, 0.5, false, 0.0, &"wood")
	var parchment := Art.mat(Color(0.62, 0.52, 0.38), 0.9, 0.0, 0.4, false, 0.0, &"parchment")
	for s: float in [-1.0, 1.0]:
		Art.part(root, Art.cylinder(0.05, 0.06), wood, Vector3(s * 0.75, 1.0, 0.0), Vector3(1.0, 2.0, 1.0))
	Art.part(root, Art.box(), wood, Vector3(0.0, 1.45, 0.0), Vector3(1.7, 0.95, 0.08))
	Art.part(root, Art.box(), wood, Vector3(0.0, 2.0, 0.02), Vector3(1.9, 0.12, 0.18), Vector3(0.0, 0.0, 0.03))
	# Today's trial and older, curling notices; a wax seal glows on the fresh one.
	Art.part(root, Art.box(), parchment, Vector3(0.0, 1.45, -0.05), Vector3(0.6, 0.72, 0.01))
	var old_spots: Array[Vector3] = [Vector3(-0.58, 1.3, -0.045), Vector3(0.58, 1.52, -0.045), Vector3(0.6, 1.15, -0.045)]
	for k in old_spots.size():
		Art.part(root, Art.box(), parchment, old_spots[k], Vector3(0.36, 0.42, 0.01), Vector3(0.0, 0.0, -0.15 + k * 0.12))
	var seal := Art.part(root, Art.cylinder(0.5, 0.5), Art.glow(Art.HELLFIRE, 2.2), Vector3(0.0, 1.2, -0.06),
			Vector3(0.14, 0.02, 0.14), Vector3(PI * 0.5, 0.0, 0.0))
	seal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scenery.add_flicker(Art.light(root, Color(1.0, 0.6, 0.3), 1.6, 4.0, Vector3(0.0, 2.2, -0.8)))
	_scenery.add_post(TRIALS, 0.8)
	var it := _interactable("Read the trial", "Board of Trials", TRIALS + Vector3(0.0, 0.0, 0.9), 1.8, 2.8)
	it.interacted.connect(open_trials)


## Shows today's Daily Trial (DailyChallenge.today()): date, seed, road and modifiers.
func open_trials() -> void:
	var t := DailyChallenge.today()
	var rows: Array = [
		{"label": "Trial of " + String(t.date), "value": "seed %d" % int(t.seed), "color": UIPalette.ASH_TEXT},
		{"label": "Road", "value": String(t.map_name)},
	]
	for m: Dictionary in t.modifiers:
		rows.append({"label": "%s  %s" % [String(m.get("icon", "✦")), String(m.get("name", ""))], "value": "",
				"note": String(m.get("description", ""))})
	var best: Dictionary = Meta.trial_best.get(String(t.key), {})
	if best.is_empty():
		rows.append({"label": "Your best today", "value": "—", "note": "Your own demon and weapon, no keepsake. Score: kills, time, level, bosses, a win; modifiers raise it."})
	else:
		var tt := int(float(best.get("time", 0.0)))
		rows.append({"label": "Your best today", "value": str(int(best.score)), "color": UIPalette.SOUL,
				"note": "%s · %d slain · %s%s" % [best.get("demon", ""), int(best.get("kills", 0)), TextFormat.clock(tt),
					" · triumphant" if bool(best.get("victory", false)) else ""]})
	# The last few days' bests, so returning players see their streak.
	var past: Array = []
	for key: String in Meta.trial_best:
		if key != String(t.key):
			past.append(key)
	past.sort()
	past.reverse()
	for key: String in past.slice(0, 4):
		rows.append({"label": "Trial of " + key, "value": str(int(Meta.trial_best[key].score)), "dim": true})
	board_opened.emit()
	board.open_board("Board of Trials", "One seed, one road, the same for every damned soul today. Beat your own mark.",
			rows, "Accept the Trial", func() -> void: trial_accepted.emit(t))


# ---------------------------------------------------------------- helpers

func _open(title: String, sub: String, rows: Array) -> void:
	board_opened.emit()
	board.open_board(title, sub, rows)


func _interactable(verb: String, label: String, at: Vector3, radius: float, height: float) -> HubInteractable:
	var it := HubInteractable.new()
	it.verb = verb
	it.label = label
	it.radius = radius
	it.prompt_height = height
	it.position = at
	add_child(it)
	return it
