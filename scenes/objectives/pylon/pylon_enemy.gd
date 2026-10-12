class_name PylonEnemy
extends Enemy
## A Sanctified Pylon (the "Topple the Pylons" objective): a stationary holy obelisk the demon's
## weapons can target like any angel. Every `pulse_interval` s its crystal charges and releases a
## ring of light that heals angels within `pulse_radius` by `heal_ratio` of their max HP (never
## itself) and, while the demon stands inside, burns it for `pulse_damage`.
## Never moves, never relocates, no contact damage.

## Seconds the released pulse's sigil takes to fade.
const AFTERGLOW := 0.45

var pulse_interval := 4.0
var pulse_radius := 7.0
var heal_ratio := 0.2
var pulse_damage := 10.0

var _pulse_t := 0.0
var _after_t := 0.0
var _ring: BossTelegraph
var _pm: PylonModel


func _ready() -> void:
	super()
	damage = 0.0
	_pm = model as PylonModel
	_ring = BossTelegraph.new()
	add_child(_ring)
	_pulse_t = randf_range(1.0, pulse_interval)


func _physics_process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t = maxf(_flash_t - delta, 0.0)
		model.set_flash(_flash_t / FLASH_TIME)
	if is_dying:
		return
	_pulse_t -= delta
	var charge := clampf(1.0 - _pulse_t / 1.0, 0.0, 1.0)  # the last second before a pulse
	if _pm:
		_pm.charge = charge
	model.animate(delta, 0.0, EnemyModel.State.WINDUP if charge > 0.0 else EnemyModel.State.MOVING)
	_after_t = maxf(_after_t - delta, 0.0)
	if charge > 0.0:
		_ring.show_disc(global_position, pulse_radius, Art.HOLY, charge, 0.6 * charge, 1.2)
	elif _after_t > 0.0:
		# The released pulse: the full sigil fading out.
		_ring.show_disc(global_position, pulse_radius, Art.HOLY_WHITE, 1.0, _after_t / AFTERGLOW, 1.8)
	else:
		_ring.hide_now()
	if _pulse_t <= 0.0:
		_pulse_t = pulse_interval
		_pulse()


func _pulse() -> void:
	_after_t = AFTERGLOW
	HolyFX.motes(global_position + Vector3(0.0, 2.3, 0.0), 8, Art.HOLY, 0.5, 1.2, 0.8)
	Sfx.play_at(&"choir", global_position, 0.1, -8.0)
	var r2 := pulse_radius * pulse_radius
	# Perf.enemies(): the group list cached once per frame / physics step for every caller.
	for n in Perf.enemies():
		var e := n as Enemy
		if e == null or e == self or e.is_dying or e is PylonEnemy or e.is_in_group(&"boss"):
			continue
		if e.global_position.distance_squared_to(global_position) <= r2:
			e.hp = minf(e.hp + e.max_hp * heal_ratio, e.max_hp)
	var p := Game.player
	if p and not p.is_dead and p.global_position.distance_squared_to(global_position) <= r2:
		p.take_damage(pulse_damage)


func die() -> void:
	if is_dying:
		return
	_ring.hide_now()
	ObjectiveFX.corruption_burst(global_position, 0.7)
	Sfx.play(&"smite", 0.05, 0.0)
	super()
