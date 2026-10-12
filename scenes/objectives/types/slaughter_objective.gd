extends Objective
## "Carnage Totem": a totem of skulls and burning horns. Touch it to start the frenzy: slay `kills`
## angels anywhere within `time_limit` s. The totem calls fodder in waves around the demon
## (`fodder_count` of `fodder` every `fodder_interval` s) so there is always something to kill.
## params: kills, time_limit, fodder_interval, fodder_count, fodder (enemy ids), trigger_radius.

var _need := 40
var _count := 0
var _limit := 30.0
var _fodder_t := 0.0
var _zone: BossTelegraph
var _flame: MeshInstance3D
var _flame_mat: StandardMaterial3D


func _build() -> void:
	_need = maxi(int(param("kills", 40)), 1)
	_limit = float(param("time_limit", 30.0))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bone := Props.bone_mat()
	Art.part(self, Art.cylinder(0.25, 0.4), Art.mat(Art.OBSIDIAN, 0.6, 0.2, 0.4, false, 0.0, &"stone"),
			Vector3(0.0, 1.0, 0.0), Vector3(1.0, 2.0, 1.0))
	for i in 5:
		var a := TAU * float(i) / 5.0
		Art.part(self, Art.sphere(), bone, Vector3(cos(a) * 0.32, 0.6 + 0.3 * float(i % 2), sin(a) * 0.32), Vector3.ONE * 0.26)
	for sx: float in [-1.0, 1.0]:
		var horn := Art.part(self, Art.cone(0.5), bone, Vector3(sx * 0.35, 2.25, 0.0), Vector3(0.18, 0.7, 0.18))
		horn.rotation.z = -sx * 0.6
	_flame = HolyFX.glow_part(self, Art.cone(0.5), Art.HELLFIRE, 2.0, Vector3(0.0, 2.35, 0.0), Vector3(0.4, 0.8, 0.4))
	_flame_mat = _flame.material_override as StandardMaterial3D
	add_child(Props.bone_pile(rng))
	_zone = ObjectiveFX.zone(self)
	status_text = "Touch the totem"
	Game.enemy_died.connect(_on_enemy_died)


func _tick(delta: float) -> void:
	var flick := 0.8 + 0.2 * sin(age * 13.0)
	_flame.scale = Vector3(0.4, 0.8 * flick * (1.0 + progress), 0.4)
	_flame_mat.albedo_color = HolyFX.scaled(Art.HELLFIRE, 2.0 * flick)
	if state == State.DORMANT:
		_zone.show_disc(global_position, float(param("trigger_radius", 2.2)), Art.HELLFIRE, 0.0, 0.6, 1.2)
		if _player_distance() <= float(param("trigger_radius", 2.2)):
			activate()
		return
	_zone.hide_now()
	var left := _limit - active_time
	progress = float(_count) / float(_need)
	status_text = "%d / %d  %s" % [_count, _need, fmt_time(left)]
	_fodder_t -= delta
	if _fodder_t <= 0.0 and Game.player:
		_fodder_t = float(param("fodder_interval", 2.0))
		var ids: Array = param("fodder", ["choir_wisp"])
		for i in int(param("fodder_count", 6)):
			if not ids.is_empty():
				_spawn_enemy(str(ids.pick_random()), ObjectiveFX.ring_point(Game.player.global_position, randf_range(8.0, 11.0)), 0.6)
	if _count >= _need:
		complete()
	elif left <= 0.0:
		fail()


func _on_enemy_died(_at: Vector3, _data: Resource) -> void:
	if state == State.ACTIVE:
		_count += 1


func _on_activated() -> void:
	_toast("CARNAGE: %d in %d seconds" % [_need, roundi(_limit)], Art.HELLFIRE)
	Sfx.play(&"boss_roar", 0.0, -2.0)
	ObjectiveFX.corruption_burst(global_position, 0.6)


func _on_finished(completed: bool) -> void:
	_zone.hide_now()
	if Game.enemy_died.is_connected(_on_enemy_died):
		Game.enemy_died.disconnect(_on_enemy_died)
	if completed:
		# The frenzy can end far from the totem: the spoils come to the demon.
		if Game.player:
			var p := Game.player.global_position
			global_position = Vector3(p.x, 0.0, p.z)
			reset_physics_interpolation()
		ObjectiveFX.corruption_burst(global_position, 1.0)
