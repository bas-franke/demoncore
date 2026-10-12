extends Weapon
## A lash of chained hellfire strikes the nearest enemy, then leaps from foe to foe.
## Visuals: a jagged bolt of fire threaded with red-hot forged chain links, fading fast, and a flare of
## embers on every target. The demon's head snaps toward the first victim.

const CORE := Color(1.0, 0.72, 0.4)
## Seconds between consecutive hops (visual only, damage is instant).
const HOP_DELAY := 0.05
const BEAM_TIME := 0.24
const IMPACT_TIME := 0.3
const STARE_TIME := 0.45
## Where the chain starts, relative to the player (about the demon's hand / chest).
const ORIGIN_OFFSET := Vector3(0.0, 1.3, 0.0)
const LINK_SPACING := 0.3
const LINK_SCALE := 1.35

@export var target_range := 13.0
## Max distance of each hop from one enemy to the next (scaled by Area).
@export var chain_range := 4.5
@export var knockback := 2.5

## Extra enemies the chain leaps to after the first one.
var chains := 1
var damage_mult := 1.0
var chain_range_mult := 1.0

var _stare: Node3D
var _stare_time := 0.0


func _on_level_changed() -> void:
	chains = 1 + int(level >= 2) + int(level >= 4) + int(level >= 6)
	damage_mult = 1.0 + 0.3 * int(level >= 3) + 0.4 * int(level >= 7)
	cooldown_mult = (0.8 if level >= 5 else 1.0) * (0.85 if level >= 7 else 1.0)
	chain_range_mult = 1.25 if level >= 6 else 1.0


func attack() -> bool:
	var origin := player.global_position + ORIGIN_OFFSET
	var first := Targeting.nearest_enemies(get_tree(), origin, 1, target_range)
	if first.is_empty():
		return false
	var hops := chains + player.bonus_projectiles
	var reach := chain_range * chain_range_mult * get_area()
	var targets: Array[Enemy] = [first[0]]
	var current: Enemy = first[0]
	for i in hops:
		var next := Targeting.nearest_enemy(get_tree(), current.global_position, reach, targets)
		if next == null:
			break
		targets.append(next)
		current = next

	var dmg := get_damage() * damage_mult
	var from := origin
	for i in targets.size():
		var e := targets[i]
		var to := _aim_point(e)
		var delay := HOP_DELAY * i
		_spawn_beam(from, to, delay)
		_spawn_impact(e, to, delay)
		Enemy.hit(e, dmg, Targeting.flat_dir(from, e.global_position) * knockback, self)
		from = to

	_stare = targets[0]
	_stare_time = STARE_TIME
	Sfx.play(&"chain")
	Sfx.play_element(&"lightning", &"hit", targets[0].global_position, -7.0)
	return true


func _physics_process(delta: float) -> void:
	super(delta)
	if _stare_time <= 0.0 or player == null or player.model == null:
		return
	_stare_time -= delta
	var valid := is_instance_valid(_stare) and _stare.is_inside_tree()
	if valid:
		# Turn the demon's head toward its victim (look_yaw + = toward the model's left, -X).
		var local := player.body.global_transform.basis.inverse() * (_stare.global_position - player.global_position)
		player.model.look_yaw = atan2(-local.x, -local.z)
	if _stare_time <= 0.0 or not valid:
		_stare_time = 0.0
		_stare = null
		player.model.look_yaw = 0.0


func _exit_tree() -> void:
	if _stare_time > 0.0 and is_instance_valid(player) and is_instance_valid(player.model):
		player.model.look_yaw = 0.0


func _aim_point(e: Enemy) -> Vector3:
	var s := 1.0
	var hover := 0.0
	if e.data:
		s = e.data.size
		hover = e.data.hover
	return e.global_position + Vector3(0.0, 0.5 * s + hover, 0.0)


# ---------------------------------------------------------------- visuals

## Jagged hellfire bolt from `a` to `b`, threaded with glowing chain links.
func _spawn_beam(a: Vector3, b: Vector3, delay: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.05:
		return
	var dir := d / length
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(dir).normalized()

	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Jagged path (local to `a`).
	var n := clampi(int(length / 0.55), 3, 12)
	var pts: Array[Vector3] = [Vector3.ZERO]
	for i in range(1, n):
		var u := float(i) / float(n)
		var env := sin(u * PI)
		var off := side * randf_range(-0.28, 0.28) * env + up * randf_range(-0.18, 0.18) * env
		pts.append(d * u + off)
	pts.append(d)
	var outer := Art.glow(Art.HELLFIRE, 1.6, true, 0.3)
	var core := Art.glow(CORE, 3.5, true, 0.9)
	for i in pts.size() - 1:
		InfernalFx.segment(root, pts[i], pts[i + 1], 0.1, outer)
		InfernalFx.segment(root, pts[i], pts[i + 1], 0.025, core)
	# Forged, red-hot chain links (Blender model, tools/blender/models/weapons/chain_link.py)
	# along the straight line, interlocking at alternating 90 degree turns.
	var links := maxi(int(length / LINK_SPACING), 1)
	var look := Basis.looking_at(dir, up)
	var twist := randf() * TAU
	for k in links:
		var lb := look * Basis(Vector3.BACK, twist + (PI * 0.5 if k % 2 == 1 else 0.0))
		var link := WeaponArt.build(WeaponArt.CHAIN_LINK, root)
		link.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		link.basis = lb.scaled_local(Vector3.ONE * LINK_SCALE)
		link.position = d * ((float(k) + 0.5) / float(links))
	root.visible = delay <= 0.0
	Game.spawn(root, a)
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	var tw := root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(root.show)
	var first := true
	for gi in WeaponArt.geometry(root):
		if first:
			tw.tween_property(gi, ^"transparency", 1.0, BEAM_TIME).set_ease(Tween.EASE_IN)
			first = false
		else:
			tw.parallel().tween_property(gi, ^"transparency", 1.0, BEAM_TIME).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)


## A searing flare that clings to the enemy, with a burst of embers.
func _spawn_impact(e: Enemy, at: Vector3, delay: float) -> void:
	var flare := Node3D.new()
	flare.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var core := Art.part(flare, Art.sphere(), Art.glow(CORE, 3.5), Vector3.ZERO, Vector3.ONE * 0.22)
	core.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var halo := Art.part(flare, Art.sphere(), Art.glow(Art.HELLFIRE, 1.6, true, 0.6), Vector3.ZERO, Vector3.ONE * 0.6)
	halo.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	flare.visible = delay <= 0.0
	Game.spawn(flare, at)
	if not is_instance_valid(flare) or not flare.is_inside_tree():
		return
	var offset := at - e.global_position
	# Capture the id, not the node: the enemy may be freed while the flare is still animating.
	var enemy_id := e.get_instance_id()
	var follow := func(t: float) -> void:
		var base := at
		var target := instance_from_id(enemy_id) as Node3D
		if target and target.is_inside_tree():
			base = target.global_position + offset
		flare.global_position = base
		flare.scale = Vector3.ONE * (1.0 + 0.3 * sin(t * 40.0)) * (1.0 - 0.6 * t)
	var tw := flare.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(flare.show)
	tw.tween_callback(func() -> void: InfernalFx.burst(flare.global_position, Art.HELLFIRE, 10, 2.8, 0.9))
	tw.tween_method(follow, 0.0, 1.0, IMPACT_TIME)
	tw.parallel().tween_property(halo, ^"transparency", 1.0, IMPACT_TIME).set_ease(Tween.EASE_IN)
	tw.tween_callback(flare.queue_free)
