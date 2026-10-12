class_name MapStatue
extends Enemy
## A destructible holy statue standing in a map: the demon's weapons target and break it like an
## angel (layer 3, group "enemies"). It never moves or attacks. Breaking one bursts into hellfire
## (damaging angels around it), spills soul shards and sometimes Ichor.
## Variant `ward` = a Gate Ward of the Seventh Gate (heavens_gate): sturdier, and its fall is
## reported through `destroyed`.
## Spawned by GameMap.statue(); scene res://scenes/maps/features/map_statue.tscn.

signal destroyed(statue: MapStatue)

const SCENE_PATH := "res://scenes/maps/features/map_statue.tscn"

var variant := &"saint"
var burst_damage := 40.0
var ichor := 2


## Builds an EnemyData for a statue of `variant` (&"saint", &"angel", &"ward").
static func make_data(p_variant: StringName) -> EnemyData:
	var d := EnemyData.new()
	d.id = &"map_statue" if p_variant != &"ward" else &"gate_ward"
	d.display_name = "Gate Ward" if p_variant == &"ward" else "Holy Statue"
	d.model = load("res://scenes/maps/features/map_statue_model.tscn")
	d.size = 1.0 if p_variant != &"ward" else 1.35
	d.hover = 0.0
	var minutes := Game.elapsed / 60.0
	d.max_hp = (160.0 + 40.0 * minutes) if p_variant != &"ward" else (900.0 + 120.0 * minutes)
	d.speed = 0.0
	d.damage = 0.0
	d.xp_value = 6 if p_variant != &"ward" else 25
	d.knockback_scale = 0.0
	d.behavior = EnemyData.Behavior.CHASE
	return d


func _ready() -> void:
	super()
	damage = 0.0
	# Group "map_features": spawner / objective caps subtract these from the "enemies" count.
	add_to_group(&"map_features")


func _physics_process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		model.set_flash(_flash_t / FLASH_TIME)
	if is_dying:
		return
	model.animate(delta, 0.0, EnemyModel.State.MOVING)


func die() -> void:
	if is_dying:
		return
	is_dying = true  # first: the burst below damages enemies around, never this statue again
	ObjectiveFX.corruption_burst(global_position, 0.8 if variant != &"ward" else 1.4)
	ObjectiveFX.damage_enemies(global_position, 5.0, burst_damage)
	if ichor > 0:
		RunState.drop_currency(global_position + Vector3(0, 0.5, 0), ichor, 2)
	Sfx.play(&"smite", 0.05, 0.0)
	destroyed.emit(self)
	# Not an angel: no Game.enemy_died / Game.kills (so "Angels slain", kill-count objectives, story
	# kill counters and RunState drops ignore it). Only Enemy.die()'s visual / XP parts run here.
	_drop_xp()
	_hide_telegraph()
	var s := data.size
	model.death_burst(global_position + Vector3(0.0, 0.45 * s + data.hover, 0.0), s, variant == &"ward")
	queue_free()
