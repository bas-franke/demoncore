extends ProcModel
## "Warden of the Seventh Gate" (SHIELD: wards + slam, heaven's gate only): a colossal angelic
## doorkeeper - a towering figure in white-gold plate with a featureless gold mask, a mantle of
## heavy chains of light, a great ring of keys of light at its belt, and an enormous key-headed
## halberd. Kesh's mirror image on the other side of the Breach. It wards the Host around it and
## brings the halberd down on whatever comes too close.

const LIGHT := Color(1.0, 0.92, 0.7)
const HIP := 0.72

var _torso: Node3D
var _head: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _keys: Node3D
var _halberd_head: MeshInstance3D


func build() -> void:
	feather_count = 4
	debris = [&"gold", &"steel"]
	debris_color = Art.GOLD
	wing_speed = 1.8
	wing_amp = 0.1
	wing_lift = 0.15
	wing_sweep = 0.5
	stride = 1.5
	var plate := Art.mat(Color(0.92, 0.9, 0.84), 0.35, 0.5, 0.15, true, 0.2, &"metal")
	var gold := Art.mat(Art.GOLD, 0.3, 0.55, 0.15, true, 0.3, &"gold")
	var chain := Art.glow(LIGHT, 1.6)
	_torso = biped(HIP, 0.09, plate, gold, 0.15, 0.35)
	Art.part(body, Art.cylinder(0.24, 0.32), plate, Vector3(0.0, -0.16, 0.0), Vector3(1.0, 0.34, 0.9))
	Art.part(_torso, Art.cylinder(0.3, 0.24), plate, Vector3(0.0, 0.28, 0.0), Vector3(1.0, 0.56, 0.8))
	for s: float in [-1.0, 1.0]:
		Art.part(_torso, Art.sphere(), gold, Vector3(s * 0.34, 0.52, 0.0), Vector3(0.28, 0.2, 0.28))
	# Mantle of chains of light over the shoulders.
	for s: float in [-1.0, 1.0]:
		for k in 6:
			var f := float(k) / 5.0
			Art.part(_torso, Art.torus(0.6, 1.0), chain, Vector3(s * lerpf(0.34, 0.06, f), lerpf(0.62, 0.2, f), lerpf(-0.05, -0.28, f)),
					Vector3.ONE * 0.06, Vector3(0.0, s * 0.5, PI * 0.5 * float(k % 2)))
	Art.part(_torso, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.04, 0.0), Vector3(0.6, 0.07, 0.5))
	_keys = animated(Art.pivot(_torso, Vector3(-0.26, 0.02, -0.2)))
	Art.part(_keys, Art.torus(0.8, 1.0), gold, Vector3(0.0, -0.06, 0.0), Vector3.ONE * 0.07, Vector3(PI * 0.5, 0.0, 0.0))
	for k in 4:
		var kp := Art.pivot(_keys, Vector3(0.0, -0.1, 0.0), Vector3(0.0, 0.0, -0.5 + 0.33 * float(k)))
		Art.part(kp, Art.box(), chain, Vector3(0.0, -0.09, 0.0), Vector3(0.015, 0.16, 0.015))
		Art.part(kp, Art.box(), chain, Vector3(0.015, -0.16, 0.0), Vector3(0.035, 0.035, 0.012))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.72, 0.0)))
	Art.part(_head, Art.sphere(), gold, Vector3.ZERO, Vector3(0.24, 0.3, 0.26))
	Art.part(_head, Art.box(), Art.glow(LIGHT, 2.4), Vector3(0.0, 0.03, -0.13), Vector3(0.16, 0.012, 0.01))
	halo(_head, Vector3(0.0, 0.06, 0.2), 0.3, 3.0, true, false, LIGHT)
	solid_wing_pair(_torso, Vector3(0.0, 0.5, 0.16), 0.9, plate, gold, null, 0.14)
	var a := arm(_torso, Vector3(-0.38, 0.52, 0.0), 0.62, 0.075, plate, gold, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.38, 0.52, 0.0), 0.62, 0.075, plate, gold, 0.0, 0.0)
	_arm_r = b[0]
	# Key-halberd: a long gold haft, a key bit of light and a crescent blade.
	var hb := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(hb, Vector3(0.0, -0.8, 0.0), Vector3(0.0, 1.5, 0.0), 0.03, gold)
	Art.part(hb, Art.torus(0.7, 1.0), chain, Vector3(0.0, 1.62, 0.0), Vector3.ONE * 0.14, Vector3(PI * 0.5, 0.0, 0.0))
	Art.part(hb, Art.box(), chain, Vector3(0.0, 1.32, -0.09), Vector3(0.04, 0.08, 0.16))
	_halberd_head = keep(Art.part(hb, Art.prism(), Art.emissive(Color(0.9, 0.88, 0.8), LIGHT, 0.6, 0.3), Vector3(0.0, 1.38, 0.15), Vector3(0.04, 0.42, 0.22)))
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.05)
	var lift := windup_w
	var smite := maxf(strike_w, recover_w)
	_torso.rotation.x = -0.05 * move_w + lift * 0.2 - smite * 0.35
	_head.rotation.x = sin(t * 0.6) * 0.04 + smite * 0.15
	_keys.rotation.z = sin(t * 2.0) * 0.12 + sin(walk) * 0.2 * move_w
	# Halberd planted beside it, hoisted for the ward-slam, brought down on the struck circle.
	var rest := Vector3(0.4 + sin(walk) * 0.1 * move_w, 0.0, 0.18)
	var r := mixv(rest, Vector3(2.7, 0.0, 0.1), lift)
	_arm_r.rotation = mixv(r, Vector3(1.1, 0.0, 0.05), smite)
	_arm_l.rotation = mixv(Vector3(0.3, 0.2, -0.15), Vector3(2.4, 0.0, -0.3), maxf(lift, smite))
	EnemyModel.glow(_halberd_head, lift * 0.7 + smite * 0.5)


func ragdoll_limbs() -> Array:
	return limbs_with([_head, _keys])
