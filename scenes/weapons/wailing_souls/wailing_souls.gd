extends Weapon
## Tormented souls circle the demon, howling through anything in their path.
## Each soul is a howling bone death-mask in a torn, streaming shroud of red-violet spirit-light
## (Blender model, tools/blender/models/weapons/soul_wisp.py), trailing a fading, writhing tail.

const SOUL_COLORS: Array[Color] = [
	Color(0.9, 0.12, 0.2),   # blood-red
	Color(0.62, 0.14, 0.95),  # violet
	Color(0.85, 0.1, 0.55),  # crimson-magenta
]
const CORE := Color(1.0, 0.78, 0.86)
const SOUL_HEIGHT := 0.95
## Glowing beads in each soul's trailing tail.
const TAIL_BEADS := 9
const TAIL_SPACING := 0.11
const MASK_SCALE := 1.45

@export var base_radius := 2.6
@export var spin_speed := 3.0
## Seconds before the same enemy can be hit again.
@export var hit_interval := 0.5

var count := 2
var radius_mult := 1.0
var damage_mult := 1.0
var spin_mult := 1.0

var _souls: Array[Area3D] = []
var _visuals: Array[Node3D] = []
var _bumps: PackedFloat32Array = PackedFloat32Array()
var _beads: Array[MeshInstance3D] = []  # soul i owns [i * TAIL_BEADS, (i + 1) * TAIL_BEADS)
var _last_hit := {}  # enemy instance id -> time
var _time := 0.0


func _on_level_changed() -> void:
	count = 2 + int(level >= 2) + int(level >= 4) + int(level >= 6)
	radius_mult = 1.25 if level >= 3 else 1.0
	damage_mult = 1.5 if level >= 5 else 1.0
	spin_mult = 1.3 if level >= 7 else 1.0
	_rebuild_souls()


func _rebuild_souls() -> void:
	for s in _souls:
		s.queue_free()
	for bead in _beads:
		bead.queue_free()
	_souls.clear()
	_visuals.clear()
	_beads.clear()
	_bumps.resize(count)
	_bumps.fill(0.0)
	for i in count:
		var c: Color = SOUL_COLORS[i % SOUL_COLORS.size()]
		_make_soul(c)
		_make_tail(c)
	if player:
		_place(0.0)
		for s in _souls:
			s.reset_physics_interpolation()
		for bead in _beads:
			bead.reset_physics_interpolation()


func _make_soul(c: Color) -> void:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 4
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.55
	cs.shape = sh
	a.add_child(cs)
	var vis := Node3D.new()
	a.add_child(vis)
	# Faint aura around the mask, then the mask + shroud themselves (tinted per soul).
	Art.part(vis, Art.sphere(), Art.glow(c, 0.9, true, 0.3), Vector3(0.0, 0.02, 0.1), Vector3(0.62, 0.7, 0.7))
	var mask := WeaponArt.build(WeaponArt.SOUL, vis, c)
	mask.scale = Vector3.ONE * MASK_SCALE
	mask.rotation.x = 0.6  # tipped up toward the high camera so the face reads
	var embers := InfernalFx.embers(a, c, 8, 0.5, 0.15, Vector3.ZERO, 2.6)
	embers.gravity = Vector3(0.0, 1.0, 0.0)
	embers.initial_velocity_max = 0.4
	add_child(a)
	_souls.append(a)
	_visuals.append(vis)


func _make_tail(c: Color) -> void:
	for k in TAIL_BEADS:
		var u := float(k) / float(TAIL_BEADS - 1)
		var s := lerpf(0.3, 0.07, u)
		var alpha := snappedf(lerpf(0.7, 0.15, u), 0.05)
		var bead := Art.part(self, Art.sphere(), Art.glow(c, lerpf(2.0, 1.0, u), true, alpha), Vector3.ZERO, Vector3.ONE * s)
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_beads.append(bead)


func _physics_process(delta: float) -> void:
	if player == null or player.is_dead:
		return
	_time += delta
	_place(delta)
	var dmg := get_damage() * damage_mult
	for i in _souls.size():
		for body in _souls[i].get_overlapping_bodies():
			var e := body as Enemy
			if e == null or e.is_dying:
				continue
			var id := e.get_instance_id()
			if _time - float(_last_hit.get(id, -INF)) >= hit_interval:
				_last_hit[id] = _time
				_bumps[i] = 1.0
				Enemy.hit(e, dmg, Targeting.flat_dir(player.global_position, e.global_position) * 6.0, self)
				InfernalFx.burst(_souls[i].global_position, SOUL_COLORS[i % SOUL_COLORS.size()], 6, 2.0, 0.8, 0.4)
				# necro_hit, not &"soul": that one drives the XP pickup pitch ladder.
				Sfx.play_element(&"necro", &"hit", _souls[i].global_position, -5.0, 0.12)
	if _last_hit.size() > 600:
		_last_hit.clear()


## Positions the souls along their orbit and their tails trailing behind.
func _place(delta: float) -> void:
	var n := _souls.size()
	if n == 0:
		return
	var r := base_radius * radius_mult * get_area()
	var ang_speed := spin_speed * spin_mult
	for i in n:
		var ang := _time * ang_speed + TAU * i / n
		var bob := sin(_time * 4.0 + i * 1.7) * 0.1
		_souls[i].position = Vector3(cos(ang) * r, SOUL_HEIGHT + bob, sin(ang) * r)
		# Face along the orbit so the "mouth" leads.
		var tangent := Vector3(-sin(ang), 0.0, cos(ang))
		_bumps[i] = move_toward(_bumps[i], 0.0, delta * 5.0)
		var b := _bumps[i]
		var flick := 1.0 + sin(_time * 21.0 + i * 3.0) * 0.06 + sin(_time * 13.0 + i) * 0.05
		var sc := Vector3(1.0 + 0.35 * b, 1.0 + 0.2 * b, 1.0 + 0.35 * b) * flick
		_visuals[i].basis = Basis.looking_at(tangent, Vector3.UP) * Basis.from_scale(sc)
		# Writhing tail: lags behind, rises and twists as it fades.
		var step_a := TAIL_SPACING / maxf(r, 0.5)
		var start := 0.2 / maxf(r, 0.5)
		for k in TAIL_BEADS:
			var bead := _beads[i * TAIL_BEADS + k]
			var a := ang - start - step_a * k
			var wig := sin(_time * 8.0 - k * 0.9 + i) * 0.045 * k
			var rr := r + wig
			var y := SOUL_HEIGHT + bob * 0.6 + 0.025 * k + cos(_time * 6.0 - k * 0.7) * 0.015 * k
			bead.position = Vector3(cos(a) * rr, y, sin(a) * rr)
