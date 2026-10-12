extends ProcModel
## "Power" (CHASE, hunts your allies): the Host's enforcer, made to police demons and their thralls.
## A heavy angel in blackened-silver plate with a closed sallet helm, a chain-wrapped gauntlet, an
## iron cage-lantern holding a bound soul at its hip, a long chain with a hook, and short hard
## wings. Every HUNT_EVERY s it looks for the demon's summoned allies (group "allies": AllyMinion,
## freed DamnedSouls, ...) within HUNT_RANGE and lashes its chain at the nearest one, dragging it
## into the cage (the ally is dismissed). Otherwise it simply walks you down.

const HUNT_RANGE := 9.0
const HUNT_EVERY := 2.6
const CHAIN := Color(0.85, 0.9, 1.0)

var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _lantern: MeshInstance3D
var _hunt_t := 1.5
var _lash := 0.0


func build() -> void:
	feather_count = 3
	debris = [&"steel"]
	stride = 1.4
	wing_speed = 3.0
	wing_amp = 0.15
	wing_lift = 0.05
	wing_sweep = 0.6
	var plate := m_metal(Color(0.62, 0.64, 0.7), 0.3)
	var dark := m_metal(Color(0.3, 0.31, 0.34), 0.45)
	_torso = biped(0.66, 0.075, plate, dark, 0.13, 0.4)
	Art.part(body, Art.cylinder(0.2, 0.25), dark, Vector3(0.0, -0.12, 0.0), Vector3(1.0, 0.3, 0.85))
	Art.part(_torso, Art.cylinder(0.26, 0.2), plate, Vector3(0.0, 0.24, 0.0), Vector3(1.0, 0.48, 0.8))
	for s: float in [-1.0, 1.0]:
		Art.part(_torso, Art.sphere(), plate, Vector3(s * 0.28, 0.44, 0.0), Vector3(0.24, 0.18, 0.24))
		Art.part(_torso, Art.cone(0.5), dark, Vector3(s * 0.3, 0.55, 0.0), Vector3(0.06, 0.16, 0.06), Vector3(0.0, 0.0, -s * 0.5))
	var head := Art.pivot(_torso, Vector3(0.0, 0.6, 0.0))
	Art.part(head, Art.sphere(), plate, Vector3(0.0, 0.03, 0.02), Vector3(0.23, 0.25, 0.27))
	Art.part(head, Art.box(), Art.glow(CHAIN, 2.2), Vector3(0.0, 0.04, -0.12), Vector3(0.13, 0.016, 0.01))
	solid_wing_pair(_torso, Vector3(0.0, 0.4, 0.14), 0.6, m_metal(Color(0.6, 0.62, 0.66), 0.4), dark, null, 0.12)
	var a := arm(_torso, Vector3(-0.32, 0.44, 0.0), 0.5, 0.065, plate, dark, 0.0, 0.0)
	_arm_l = a[0]
	# Cage-lantern with a bound soul, at the left hand.
	var cage := Art.pivot(a[1], Vector3(0.0, -0.14, 0.0))
	for k in 6:
		var ang := TAU * float(k) / 6.0
		limb(cage, Vector3(cos(ang), 0.0, sin(ang)) * 0.08 + Vector3(0.0, 0.1, 0.0), Vector3(cos(ang), 0.0, sin(ang)) * 0.08 - Vector3(0.0, 0.1, 0.0), 0.006, dark)
	_lantern = keep(Art.part(cage, Art.sphere(), Art.glow(Art.SOUL, 1.8), Vector3.ZERO, Vector3.ONE * 0.1))
	var b := arm(_torso, Vector3(0.32, 0.44, 0.0), 0.5, 0.065, plate, dark, 0.0, 0.0)
	_arm_r = b[0]
	# Coiled chain and hook in the right fist.
	for k in 5:
		Art.part(b[1], Art.torus(0.6, 1.0), Art.mat(Color(0.7, 0.72, 0.75), 0.3, 0.9), Vector3(0.0, -0.05 - k * 0.04, 0.0), Vector3.ONE * 0.045, Vector3(0.0, 0.0, PI * 0.5 * float(k % 2)))
	Art.part(b[1], Art.cone(0.5), dark, Vector3(0.0, -0.28, -0.03), Vector3(0.03, 0.1, 0.03), Vector3(PI + 0.5, 0.0, 0.0))
	finish()


func pose(delta: float) -> void:
	biped_bob(0.66, 0.05)
	_lash = maxf(_lash - delta * 2.5, 0.0)
	_torso.rotation.x = -0.1 * move_w - _lash * 0.2
	_torso.rotation.y = sin(walk) * 0.1 * move_w + _lash * 0.4
	_arm_r.rotation = mixv(Vector3(0.4 - sin(walk) * 0.3 * move_w, 0.0, 0.12), Vector3(1.6, -0.3, 0.2), _lash)
	_arm_l.rotation = Vector3(0.3 + sin(walk) * 0.2 * move_w, 0.0, -0.15)
	_lantern.scale = Vector3.ONE * 0.1 * (1.0 + 0.15 * sin(t * 5.0) + _lash * 0.6)
	_hunt(delta)


## Lashes the chain at the nearest demonic ally in range and dismisses it.
func _hunt(delta: float) -> void:
	_hunt_t -= delta
	if _hunt_t > 0.0:
		return
	_hunt_t = HUNT_EVERY
	var e := host()
	if e == null or not is_inside_tree():
		return
	var best: Node3D = null
	var best_d := HUNT_RANGE * HUNT_RANGE
	for n in get_tree().get_nodes_in_group(&"allies"):
		var al := n as Node3D
		if al == null or not is_instance_valid(al):
			continue
		var d := al.global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = al
	if best == null:
		return
	_lash = 1.0
	var from := e.global_position + Vector3(0.0, 1.0 * body_scale, 0.0)
	var to := best.global_position + Vector3(0.0, 0.5, 0.0)
	_chain_fx(from, to)
	# Dismiss through whichever API the ally has (AllyMinion.dismiss, AbilityMinion.expire, ...).
	for m: StringName in [&"dismiss", &"expire", &"_vanish"]:
		if best.has_method(m):
			best.call(m)
			break
	EnemyModel.light_flash(to, 0.6, CHAIN, false)


## A brief bright chain-line from the Power to its prey.
static func _chain_fx(from: Vector3, to: Vector3) -> void:
	if Game.world == null:
		return
	var root := Art.pivot(Game.world)
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	EnemyModel.limb(root, from, to, 0.03, Art.glow(CHAIN, 2.4))
	var tw := root.create_tween()
	tw.tween_interval(0.2)
	tw.tween_property(root, "scale", Vector3(0.02, 1.0, 0.02), 0.15)
	tw.tween_callback(root.queue_free)
