extends ProcModel
## "Lightning-Rod Acolyte" (KITE -> called lightning, storm spire only): a novice of the storm-cult
## in a soaked slate-grey robe with copper wire wound round the arms, a tall copper lightning rod
## strapped to the back and a copper staff with a forked tip. It keeps its distance and calls the
## storm down: the staff is raised (sparks gather on the rod) and a telegraphed lightning strike
## (lightning_call spell, a pillar with storm tint) lands on the demon's position.

const BOLT := Color(0.65, 0.7, 1.0)
const HIP := 0.48

var _torso: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _spark: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 5
	light_color = BOLT
	stride = 1.0
	var robe := m_cloth(Color(0.3, 0.33, 0.38))
	var copper := Art.mat(Color(0.75, 0.42, 0.25), 0.35, 0.6, 0.2, true, 0.1, &"gold")
	var skin := m_skin(Color(0.78, 0.7, 0.66))
	_torso = biped(HIP, 0.04, robe, m_leather(), 0.07, 0.5)
	Art.part(body, Art.cylinder(0.15, 0.24), robe, Vector3(0.0, -0.2, 0.0), Vector3(1.0, 0.44, 0.9))
	Art.part(_torso, Art.cylinder(0.16, 0.14), robe, Vector3(0.0, 0.18, 0.0), Vector3(1.0, 0.38, 0.8))
	var head := Art.pivot(_torso, Vector3(0.0, 0.46, 0.0))
	Art.part(head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.18, 0.16))
	Art.part(head, Art.sphere(), robe, Vector3(0.0, 0.04, 0.03), Vector3(0.2, 0.2, 0.2))
	Art.part(head, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.6), Vector3(0.0, 0.0, -0.06), Vector3(0.12, 0.13, 0.06))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(BOLT, 2.0), Vector3(s * 0.03, 0.01, -0.095), Vector3(0.02, 0.012, 0.01))
	# Rod on the back.
	limb(_torso, Vector3(0.05, -0.1, 0.13), Vector3(0.05, 1.1, 0.15), 0.014, copper)
	Art.part(_torso, Art.sphere(), copper, Vector3(0.05, 1.12, 0.15), Vector3.ONE * 0.05)
	_spark = keep(Art.part(_torso, Art.sphere(), Art.glow(BOLT, 2.6), Vector3(0.05, 1.14, 0.15), Vector3.ONE * 0.03))
	var a := arm(_torso, Vector3(-0.18, 0.34, 0.0), 0.36, 0.035, robe, skin, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.18, 0.34, 0.0), 0.36, 0.035, robe, skin, 0.0, 0.0)
	_arm_r = b[0]
	# Copper wire wound round the forearms.
	for arm_n: Node3D in [_arm_l, _arm_r]:
		for k in 3:
			Art.part(arm_n, Art.torus(0.75, 1.0), copper, Vector3(0.0, -0.22 - k * 0.04, -0.01), Vector3.ONE * 0.045)
	# Forked copper staff out of the right fist (upward).
	var st := Art.pivot(b[1], Vector3.ZERO, Vector3(PI, 0.0, 0.0))
	limb(st, Vector3(0.0, -0.3, 0.0), Vector3(0.0, 0.6, 0.0), 0.012, copper)
	for s: float in [-1.0, 1.0]:
		limb(st, Vector3(0.0, 0.6, 0.0), Vector3(s * 0.07, 0.75, 0.0), 0.008, copper)
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.03)
	var call_w := windup_w
	_torso.rotation.x = -0.06 * move_w + call_w * 0.15
	_arm_r.rotation = mixv(Vector3(0.45 + sin(walk) * 0.2 * move_w, 0.0, 0.12), Vector3(2.9, 0.0, 0.1), call_w)
	_arm_r.rotation.x -= attack_kick * 0.8
	_arm_l.rotation = mixv(Vector3(0.3, 0.2, -0.15), Vector3(2.2, 0.0, -0.5), call_w)
	_spark.visible = fmod(t * 9.0, 1.0) < 0.5 + call_w * 0.5
	_spark.scale = Vector3.ONE * (0.03 + call_w * 0.12)
