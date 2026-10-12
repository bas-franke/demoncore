class_name SummoningBell
extends MapInteractable
## A great bronze bell on a frame. Strike it (stand under it for `channel_time` s) and it tolls:
## a ring of `count` angels from the map's pool answers the call around the demon, and the bell
## spills Ichor for the trouble. Rests for `cooldown` s, then can be struck again.

@export var count := 10
@export var ichor := 6
@export var summon_radius := 11.0

var _bell: Node3D
var _swing := 0.0


func _build() -> void:
	display_name = "Bell of Summoning"
	channel_time = 1.5
	cooldown = 75.0
	radius = 2.4
	tint = Color(1.0, 0.75, 0.35)
	var wood := Art.mat(Color(0.24, 0.15, 0.09), 0.85, 0.0, 0.4, false, 0.0, &"wood")
	var bronze := Art.mat(Color(0.62, 0.45, 0.22), 0.35, 0.85, 0.35, false, 0.0, &"metal")
	for s: float in [-1.0, 1.0]:
		Art.part(self, Art.box(), wood, Vector3(s * 1.2, 1.6, 0), Vector3(0.25, 3.2, 0.25))
	Art.part(self, Art.box(), wood, Vector3(0, 3.25, 0), Vector3(2.8, 0.25, 0.3))
	_bell = Art.pivot(self, Vector3(0, 3.1, 0))
	Art.part(_bell, Art.cylinder(0.45, 0.85), bronze, Vector3(0, -0.7, 0), Vector3(1.0, 1.2, 1.0))
	Art.part(_bell, Art.sphere(), bronze, Vector3(0, -0.12, 0), Vector3(0.9, 0.5, 0.9))
	for s: float in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.25
		sh.height = 3.0
		cs.shape = sh
		cs.position = Vector3(s * 1.2, 1.5, 0)
		body.add_child(cs)
		add_child(body)


func _tick(delta: float) -> void:
	_swing = maxf(_swing - delta * 0.35, 0.0)
	_bell.rotation.x = sin(Time.get_ticks_msec() * 0.006) * 0.45 * _swing


func _activate() -> void:
	_swing = 1.0
	Sfx.play(&"toll", 0.02, 2.0)
	get_tree().call_group(&"camera_rig", &"shake", 0.25)
	HolyFX.flash(global_position + Vector3(0, 2.6, 0), 3.0, 0.6, Color(1.0, 0.8, 0.45), 2.0)
	if Game.player:
		RunState.drop_currency(global_position + Vector3(0, 0.5, 0), ichor, 3)
	_summon()
	toast("The bell tolls. They come.", Color(1.0, 0.8, 0.5))


func _summon() -> void:
	var pool: Array[Resource] = Maps.enemy_pool(Maps.current_def.get("id", &""))
	if pool.is_empty() or Game.player == null:
		return
	var center := Game.player.global_position
	var start := randf() * TAU
	for i in count:
		var a := start + TAU * float(i) / float(count)
		var at := Maps.clamp_to_bounds(center + Vector3(cos(a), 0, sin(a)) * summon_radius)
		var data := pool[randi() % pool.size()] as EnemyData
		if data and data.behavior != EnemyData.Behavior.SUMMON:
			ObjectiveFX.spawn_enemy_data(data, at)
