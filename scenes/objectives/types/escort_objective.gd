extends Objective
## "Escort the Corrupted Reliquary": a cart bearing a stolen, blood-black reliquary waits by the
## road. It only rolls while the demon walks beside it (`follow_radius`), toward a hellish sigil
## `distance` m away; angels converge on it and gnaw at its `cart_hp` while they touch it
## (`gnaw_dps` each). Get it to the sigil for the reward; if they break it, the run's sin is lost.
## params: distance, speed, follow_radius, cart_hp, gnaw_dps, ambush_interval, ambush_size,
##         ambushers (enemy ids).

const CART_RADIUS := 1.4

var _cart: Node3D
var _wheels: Array[Node3D] = []
var _relic_mat: StandardMaterial3D
var _dest := Vector3.ZERO
var _cart_hp := 100.0
var _cart_max := 100.0
var _ambush_t := 0.0
var _dest_zone: BossTelegraph
var _ring: BossTelegraph
var _hurt_flash := 0.0
var _total_dist := 1.0


func _build() -> void:
	_cart_max = float(param("cart_hp", 260.0))
	_cart_hp = _cart_max
	var wood := Art.mat(Art.LEATHER.darkened(0.3), 0.9, 0.0, 0.5, false, 0.0, &"wood")
	var iron := Art.mat(Art.OBSIDIAN.lightened(0.1), 0.5, 0.8, 0.4, false, 0.0, &"metal")
	_cart = Art.pivot(self)
	Art.part(_cart, Art.box(), wood, Vector3(0.0, 0.7, 0.0), Vector3(1.4, 0.3, 2.2))
	for sx: float in [-1.0, 1.0]:
		Art.part(_cart, Art.box(), wood, Vector3(sx * 0.68, 0.95, 0.0), Vector3(0.08, 0.4, 2.2))
		for sz: float in [-0.75, 0.75]:
			var w := Art.pivot(_cart, Vector3(sx * 0.78, 0.42, sz))
			Art.part(w, Art.cylinder(), iron, Vector3.ZERO, Vector3(0.84, 0.1, 0.84), Vector3(0.0, 0.0, PI * 0.5))
			_wheels.append(w)
	# The reliquary: black iron, chained, bleeding red light.
	Art.part(_cart, Art.box(), iron, Vector3(0.0, 1.25, 0.0), Vector3(0.8, 0.7, 1.1))
	var core := HolyFX.glow_part(_cart, Art.sphere(), Art.SOUL, 2.0, Vector3(0.0, 1.3, -0.56), Vector3(0.3, 0.3, 0.06))
	_relic_mat = core.material_override as StandardMaterial3D
	Art.light(_cart, Art.SOUL, 1.2, 4.0, Vector3(0.0, 1.8, 0.0))
	_ring = ObjectiveFX.zone(self)
	_dest_zone = ObjectiveFX.zone(self)
	status_text = "Walk beside the cart"


func _ready() -> void:
	super()
	# Destination: a walkable spot `distance` m away, preferring the direction away from the demon.
	var away := global_position - (Game.player.global_position if Game.player else global_position)
	away.y = 0.0
	var dir := away.normalized() if away.length() > 0.1 else Vector3.FORWARD
	var dist := float(param("distance", 30.0))
	_dest = ObjectiveFX.walkable(global_position + dir.rotated(Vector3.UP, randf_range(-0.8, 0.8)) * dist)
	_total_dist = maxf(Vector2(_dest.x - global_position.x, _dest.z - global_position.z).length(), 1.0)


func marker_position() -> Vector3:
	return _cart.global_position


func _tick(delta: float) -> void:
	var cart_pos := _cart.global_position
	var near := _player_distance(cart_pos) <= float(param("follow_radius", 7.0))
	_ring.show_disc(cart_pos, float(param("follow_radius", 7.0)), Art.SOUL, 0.0, 0.5 if near else 0.3, 0.9)
	_dest_zone.show_disc(_dest, 3.0, Art.HELLFIRE, progress, 0.7, 1.4)
	_hurt_flash = maxf(_hurt_flash - delta * 3.0, 0.0)
	_relic_mat.albedo_color = HolyFX.scaled(Art.SOUL.lerp(Art.HOLY_WHITE, _hurt_flash), 1.6 + 0.6 * sin(age * 4.0))
	if state == State.DORMANT:
		if near:
			activate()
		return
	# Roll toward the sigil while escorted.
	var to := _dest - cart_pos
	to.y = 0.0
	var left := to.length()
	if near and left > 0.3:
		var step := to / left * float(param("speed", 2.2)) * delta
		_cart.global_position += step
		_cart.rotation.y = lerp_angle(_cart.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-4.0 * delta))
		for w in _wheels:
			w.rotate_x(-step.length() / 0.42)
	progress = clampf(1.0 - left / _total_dist, 0.0, 1.0)
	# Angels touching the cart gnaw at it.
	var gnaw := 0
	for n in get_tree().get_nodes_in_group(&"enemies"):
		var e := n as Enemy
		if e and not e.is_dying and e.global_position.distance_to(cart_pos) < CART_RADIUS + 0.4 * e.data.size:
			gnaw += 1
	if gnaw > 0:
		_cart_hp -= float(gnaw) * float(param("gnaw_dps", 9.0)) * delta
		_hurt_flash = 1.0
	status_text = "%dm  cart %d%%%s" % [roundi(left), roundi(100.0 * _cart_hp / _cart_max), "" if near else "  stay close!"]
	_ambush_t -= delta
	if _ambush_t <= 0.0:
		_ambush_t = float(param("ambush_interval", 5.0))
		_ambush(cart_pos, to / maxf(left, 0.01))
	if _cart_hp <= 0.0:
		fail()
	elif left <= 0.6:
		complete()


## Angels drop in ahead of the cart and to its sides.
func _ambush(cart_pos: Vector3, heading: Vector3) -> void:
	var ids: Array = param("ambushers", ["choir_wisp"])
	if ids.is_empty():
		return
	for i in int(param("ambush_size", 4)):
		var side := heading.rotated(Vector3.UP, randf_range(-1.3, 1.3))
		_spawn_enemy(str(ids.pick_random()), cart_pos + side * randf_range(7.0, 10.0))


func _on_activated() -> void:
	_toast("The reliquary moves. Keep it whole.", Art.SOUL)
	_ambush_t = 2.0


func _on_finished(completed: bool) -> void:
	_ring.hide_now()
	_dest_zone.hide_now()
	if completed:
		global_position = Vector3(_dest.x, 0.0, _dest.z)
		_cart.position = Vector3.ZERO
		reset_physics_interpolation()
		ObjectiveFX.corruption_burst(_dest, 1.3)
		_toast("The reliquary is home", Art.HELLFIRE)
	else:
		HolyFX.flash(_cart.global_position + Vector3(0.0, 1.0, 0.0), 3.0, 0.5, Art.HOLY_WHITE, 3.0)
		HolyFX.column(_cart.global_position, 0.8, 18.0, 0.8, Art.HOLY, 1.8)
		_cart.hide()
