class_name HubPit
extends Node3D
## The Proving Pit: a training ring in Basecamp Hell. Interacting opens the rite list (HubShopUI
## open_rites); entering swaps the hub avatar for a real Player (same demon, weapons, meta upgrades,
## Progression bonuses) with the chosen abilities granted, facing three straw-angel training
## dummies. Dummies are ordinary Enemies (so every weapon, ability and status works on them) that
## never move, never hurt, get their HP topped up and show damage per second above their heads.
## Esc / E leaves the pit (`exited`). While active, Game.player / Game.world point into the pit.

signal entered
signal exited

const CENTER := Vector3(11.4, 0.0, 1.4)
const RADIUS := 2.9
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const DUMMY_SCRIPT := preload("res://scenes/basecamp/training_dummy_enemy.gd")
const DUMMY_MODEL := preload("res://scenes/basecamp/models/training_dummy.tscn")
## Dummy positions relative to CENTER.
const DUMMY_SPOTS: Array[Vector3] = [Vector3(-1.2, 0.0, -1.3), Vector3(1.3, 0.0, -1.0), Vector3(0.1, 0.0, -2.1)]
## Seconds of hits averaged for the DPS readout.
const DPS_WINDOW := 4.0

var active := false
var player: Player
var interactable: HubInteractable
var _scenery: HubScenery
var _arena: Node3D
var _dummies: Array[Enemy] = []
var _labels := {}  # Enemy -> Label3D
var _hits := {}  # Enemy -> Array of [time, amount]
var _dummy_data: EnemyData
var _t := 0.0
var _godmode_before := false


func build(scenery: HubScenery) -> void:
	_scenery = scenery
	_build_ring()
	interactable = HubInteractable.new()
	interactable.verb = "Choose rites"
	interactable.label = "The Proving Pit"
	interactable.radius = 2.0
	interactable.prompt_height = 2.6
	interactable.position = CENTER + Vector3(-RADIUS - 0.2, 0.0, 0.4)
	add_child(interactable)
	# Idle dummies stand in the ring even when nobody trains (pure decoration then).
	for spot in DUMMY_SPOTS:
		var d := DUMMY_MODEL.instantiate() as ProcModel
		d.position = CENTER + spot
		d.rotation.y = PI
		d.add_to_group(&"pit_idle_dummy")
		add_child(d)


## Starts a training session with ability ids `rites` (may be empty: weapons only).
func enter(rites: Array) -> void:
	if active:
		return
	active = true
	for n in get_tree().get_nodes_in_group(&"pit_idle_dummy"):
		(n as Node3D).visible = false
	_arena = Node3D.new()
	_arena.name = "PitArena"
	add_child(_arena)
	Game.reset()
	Game.world = _arena
	# Nothing in the pit may hurt the demon (touching a dummy still ticks 1 dps otherwise).
	_godmode_before = Game.godmode
	Game.godmode = true
	_dummy_data = _make_dummy_data()
	player = PLAYER_SCENE.instantiate() as Player
	player.position = CENTER + Vector3(0.0, 0.0, 1.4)
	_arena.add_child(player)
	Game.player = player
	for spot in DUMMY_SPOTS:
		var node := ENEMY_SCENE.instantiate()
		node.set_script(DUMMY_SCRIPT)  # same scene, immortal behaviour
		var e := node as Enemy
		e.setup(_dummy_data)
		Game.spawn(e, CENTER + spot)
		_dummies.append(e)
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 30
		l.pixel_size = 0.012
		l.outline_size = 8
		l.modulate = UIPalette.BRIMSTONE
		l.position = CENTER + spot + Vector3(0.0, 2.5, 0.0)
		_arena.add_child(l)
		_labels[e] = l
		_hits[e] = []
	if not Game.enemy_struck.is_connected(_on_struck):
		Game.enemy_struck.connect(_on_struck)
	# Abilities starts its run a frame after the Player is ready; grant once it has.
	await get_tree().process_frame
	await get_tree().process_frame
	var ab := get_node_or_null(^"/root/Abilities")
	if ab and active:
		for id: Variant in rites:
			ab.call(&"grant", StringName(id))
	entered.emit()


## Ends a training session: stops listening to Game.enemy_struck and clears the dummies' labels.
func leave() -> void:
	if not active:
		return
	active = false
	if Game.enemy_struck.is_connected(_on_struck):
		Game.enemy_struck.disconnect(_on_struck)
	_dummies.clear()
	_labels.clear()
	_hits.clear()
	player = null
	Game.reset()
	Game.godmode = _godmode_before
	if is_instance_valid(_arena):
		_arena.queue_free()
	# Progression drops its run HUD into the current scene when a Player appears.
	var hud := get_tree().current_scene.get_node_or_null(^"ProgressionHud") if get_tree().current_scene else null
	if hud:
		hud.queue_free()
	for n in get_tree().get_nodes_in_group(&"pit_idle_dummy"):
		(n as Node3D).visible = true
	exited.emit()


func _process(delta: float) -> void:
	_t += delta
	if not active:
		return
	_hide_run_huds()
	for e in _dummies:
		if not is_instance_valid(e):
			continue
		# Immortal: top the straw back up before anything can finish it.
		if e.hp < e.max_hp * 0.5:
			e.hp = e.max_hp
		var hits: Array = _hits.get(e, [])
		while not hits.is_empty() and _t - float(hits[0][0]) > DPS_WINDOW:
			hits.pop_front()
		var sum := 0.0
		for h: Array in hits:
			sum += float(h[1])
		var l: Label3D = _labels.get(e)
		if l:
			l.text = ("%d dps" % roundi(sum / DPS_WINDOW)) if sum > 0.0 else ""


## The run HUDs that Abilities (next to the Player) and Progression (in the current scene) add when
## a Player appears are run furniture; the pit keeps the hub's own UI clean.
func _hide_run_huds() -> void:
	var scene := get_tree().current_scene
	for n: Node in [_arena.get_node_or_null(^"AbilityHud") if is_instance_valid(_arena) else null,
			scene.get_node_or_null(^"ProgressionHud") if scene else null]:
		var layer := n as CanvasLayer
		if layer and layer.visible:
			layer.visible = false


func _on_struck(enemy: Node, amount: float) -> void:
	if _hits.has(enemy):
		(_hits[enemy] as Array).append([_t, amount])


## An immortal, harmless, unmovable dummy: huge HP, no speed, no damage, no knockback, no XP.
func _make_dummy_data() -> EnemyData:
	var d := EnemyData.new()
	d.id = &""  # not a bestiary entry
	d.display_name = "Training Dummy"
	d.model = DUMMY_MODEL
	d.max_hp = 1000000.0
	d.speed = 0.0
	d.damage = 0.0
	d.xp_value = 0
	d.knockback_scale = 0.0
	d.behavior = EnemyData.Behavior.CHASE
	d.attack_cooldown = 9999.0
	return d


# ---------------------------------------------------------------- the ring

func _build_ring() -> void:
	var root := Art.pivot(self, CENTER)
	var stone := Art.mat(Color(0.16, 0.12, 0.11), 0.85, 0.0, 0.55, false, 0.0, &"stone")
	var sand := Art.mat(Color(0.2, 0.15, 0.12), 0.95, 0.0, 0.6, false, 0.0, &"stone")
	var bone := Art.mat(Art.BONE.darkened(0.1), 0.7, 0.0, 0.5, false, 0.0, &"bone")
	# Packed ash floor and a low ring wall of stones with skull-capped stakes.
	Art.part(root, Art.cylinder(0.5, 0.5), sand, Vector3(0.0, 0.02, 0.0), Vector3(RADIUS * 2.0, 0.04, RADIUS * 2.0))
	for k in 18:
		var a := TAU * k / 18.0
		var p := Vector3(cos(a), 0.0, sin(a)) * (RADIUS + 0.15)
		# Gap facing west (toward the plaza) for the entrance.
		if absf(wrapf(a - PI, -PI, PI)) < 0.35:
			continue
		Art.part(root, Art.box(), stone, p + Vector3(0.0, 0.18, 0.0), Vector3(0.6, 0.36, 0.4), Vector3(0.0, -a, 0.0))
		if k % 3 == 0:
			Art.part(root, Art.cylinder(0.03, 0.06), Art.mat(Color(0.18, 0.12, 0.08), 0.85, 0.0, 0.5, false, 0.0, &"wood"),
					p + Vector3(0.0, 0.9, 0.0), Vector3(1.0, 1.4, 1.0))
			Art.part(root, Art.sphere(), bone, p + Vector3(0.0, 1.65, 0.0), Vector3(0.22, 0.2, 0.24))
	var l := Art.light(root, Color(1.0, 0.55, 0.25), 2.6, 6.5, Vector3(0.0, 3.0, 1.0))
	l.light_specular = 0.4
	_scenery.add_flicker(l)
