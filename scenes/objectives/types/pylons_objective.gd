extends Objective
## "Topple the Sanctified Pylons": `count` marble obelisks (PylonEnemy) stand around the marker,
## mending every angel near them with pulses of light. They are targets like any angel: break them
## all. The pylons are raised when the demon first comes within `wake_radius`; their HP grows with
## the run. No time limit.
## params: count, spread, wake_radius, hp, hp_per_minute, pulse_interval, pulse_radius,
##         heal_ratio, pulse_damage.

const PYLON_SCENE := preload("res://scenes/objectives/pylon/pylon.tscn")
const PYLON_MODEL := preload("res://scenes/objectives/pylon/pylon_model.tscn")

var _pylons: Array[PylonEnemy] = []
var _total := 0
var _zone: BossTelegraph


func _build() -> void:
	_zone = ObjectiveFX.zone(self)
	status_text = "Approach"


func marker_position() -> Vector3:
	if state == State.ACTIVE:
		var best := global_position
		var best_d := INF
		for p in _pylons:
			if is_instance_valid(p) and not p.is_dying:
				var d := _player_distance(p.global_position)
				if d < best_d:
					best_d = d
					best = p.global_position
		return best
	return global_position


func _tick(_delta: float) -> void:
	if state == State.DORMANT:
		_zone.show_disc(global_position, float(param("spread", 6.0)), Art.HOLY, 0.0, 0.35 + 0.15 * sin(age * 2.0), 0.9)
		if _player_distance() <= float(param("wake_radius", 16.0)):
			activate()
		return
	var alive := 0
	for p in _pylons:
		if is_instance_valid(p) and not p.is_dying:
			alive += 1
	progress = 1.0 - float(alive) / float(maxi(_total, 1))
	status_text = "%d / %d" % [_total - alive, _total]
	if alive == 0:
		complete()


func _on_activated() -> void:
	_zone.hide_now()
	var base := ObjectiveFX.enemy_data("penitent_statue")
	var d := (base.duplicate() if base else EnemyData.new()) as EnemyData
	d.id = &""  # not a bestiary entry
	d.display_name = "Sanctified Pylon"
	d.flavor_text = "Marble and gold, humming with a hymn no demon can bear."
	d.model = PYLON_MODEL
	d.size = 1.15
	d.hover = 0.0
	d.max_hp = float(param("hp", 220.0)) + float(param("hp_per_minute", 70.0)) * Game.elapsed / 60.0
	d.speed = 0.0
	d.damage = 0.0
	d.xp_value = 12
	d.knockback_scale = 0.0
	d.behavior = EnemyData.Behavior.CHASE
	var n := maxi(int(param("count", 3)), 1)
	var spread := float(param("spread", 6.0))
	var base_a := randf() * TAU
	for i in n:
		var a := base_a + TAU * float(i) / float(n)
		var at := ObjectiveFX.walkable(global_position + Vector3(cos(a), 0.0, sin(a)) * spread)
		var p := PYLON_SCENE.instantiate() as PylonEnemy
		p.setup(d, 1.0)
		p.pulse_interval = float(param("pulse_interval", 4.0))
		p.pulse_radius = float(param("pulse_radius", 7.0))
		p.heal_ratio = float(param("heal_ratio", 0.2))
		p.pulse_damage = float(param("pulse_damage", 10.0))
		Game.spawn(p, at)
		_pylons.append(p)
		HolyFX.column(at, 0.8, 22.0, 0.9, Art.HOLY, 1.8)
	_total = _pylons.size()
	_toast("The pylons sing. Silence them.", Color("fff4cf"))
	Sfx.play(&"choir", 0.0, 0.0)


func _on_finished(completed: bool) -> void:
	_zone.hide_now()
	if completed:
		ObjectiveFX.corruption_burst(global_position, 1.0)
	else:
		for p in _pylons:
			if is_instance_valid(p) and not p.is_dying:
				p.queue_free()
