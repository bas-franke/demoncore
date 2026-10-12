extends BossModel
## "Mother Verdance, Saint of the First Garden" (boss model, outer gardens): a tree that was a
## saint, or a saint that became a tree. Her lower body is a gnarled trunk splitting into crawling
## roots; the bark rises into a woman's torso and serene face, her arms are long branches heavy
## with leaves and white blossoms, a canopy crown spreads behind her head with a ring of golden
## flowers for a halo, and glowing fruit hangs among the leaves.
## Poses per attack: chase / cross = a branch arm thrust down (roots erupt); orbs = she shakes her
## canopy (pollen); pyre = both arms spread low (bloom); rain / sweep = branches swept wide;
## summon = arms raised, the canopy blazes; lanes = a pointing branch.

const BLOOM := Color(1.0, 0.92, 0.55)

var _trunk: Node3D
var _torso: Node3D
var _head: Node3D
var _canopy: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _fruit: Array[MeshInstance3D] = []
var _roots: Array[Node3D] = []


func build() -> void:
	light_color = BLOOM
	stride = 1.2
	var bark := Art.mat(Color(0.36, 0.28, 0.2), 0.85, 0.0, 0.4, true, 0.0, &"wood")
	var pale := Art.mat(Color(0.82, 0.78, 0.68), 0.7, 0.0, 0.2, true, 0.1, &"wood")
	var leaf := Art.mat(Color(0.32, 0.5, 0.2), 0.7, 0.0, 0.2, true, 0.35, &"cloth")
	var leaf2 := Art.mat(Color(0.5, 0.6, 0.25), 0.7, 0.0, 0.2, true, 0.35, &"cloth")
	var blossom := Art.mat(Color(0.98, 0.95, 0.9), 0.5, 0.0, 0.0, true, 0.5)
	body = animated(Art.pivot(self))
	# Roots (crawl in pose) and a gnarled trunk.
	for k in 6:
		var a := TAU * float(k) / 6.0 + 0.3
		var r := animated(Art.pivot(body, Vector3(cos(a) * 0.2, 0.12, sin(a) * 0.2), Vector3(0.0, -a, 0.0)))
		limb(r, Vector3.ZERO, Vector3(0.45, -0.1, 0.0), 0.06, bark)
		limb(r, Vector3(0.45, -0.1, 0.0), Vector3(0.75, -0.12, 0.08), 0.035, bark)
		_roots.append(r)
	_trunk = animated(Art.pivot(body, Vector3(0.0, 0.0, 0.0)))
	Art.part(_trunk, Art.cylinder(0.2, 0.32), bark, Vector3(0.0, 0.45, 0.0), Vector3(1.0, 0.9, 1.0))
	for k in 4:
		Art.part(_trunk, Art.box(), Art.mat(Color(0.22, 0.17, 0.12), 0.9), Vector3(0.0, 0.45, 0.0), Vector3(0.05, 0.85, 0.5), Vector3(0.0, float(k) * 0.8, 0.1))
	_torso = animated(Art.pivot(_trunk, Vector3(0.0, 0.88, 0.0)))
	# The saint is larger than the trunk suggests: scale the whole upper body up.
	_torso.scale = Vector3.ONE * 1.35
	Art.part(_torso, Art.cylinder(0.19, 0.2), pale, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.4, 0.8))
	Art.part(_torso, Art.sphere(), pale, Vector3(0.0, 0.33, -0.03), Vector3(0.38, 0.22, 0.26))
	# A cloak of leaves over the shoulders.
	for k in 8:
		var a := -1.2 + float(k) * 0.34
		Art.part(_torso, Art.sphere(), leaf if k % 2 == 0 else leaf2, Vector3(sin(a) * 0.22, 0.32 - absf(a) * 0.08, cos(a) * 0.12 + 0.05), Vector3(0.16, 0.2, 0.06), Vector3(0.0, a, 0.0))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.52, 0.0)))
	Art.part(_head, Art.sphere(), pale, Vector3.ZERO, Vector3(0.2, 0.25, 0.21))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.box(), Art.glow(Color(0.7, 1.0, 0.5), 1.8), Vector3(s * 0.045, 0.02, -0.1), Vector3(0.045, 0.008, 0.01))
	# Canopy crown behind the head: layered leaf masses, blossoms and a halo of gold flowers.
	_canopy = animated(Art.pivot(_head, Vector3(0.0, 0.2, 0.12)))
	for k in 9:
		var a := TAU * float(k) / 9.0
		Art.part(_canopy, Art.sphere(), leaf if k % 2 == 0 else leaf2, Vector3(cos(a) * 0.32, 0.12 + sin(a) * 0.26, 0.05), Vector3(0.32, 0.28, 0.2))
		Art.part(_canopy, Art.sphere(), blossom, Vector3(cos(a) * 0.38, 0.12 + sin(a) * 0.3, -0.06), Vector3.ONE * 0.07)
	for k in 10:
		var a := TAU * float(k) / 10.0
		Art.part(_canopy, Art.sphere(), Art.glow(Art.GOLD, 1.8), Vector3(cos(a) * 0.2, 0.12 + sin(a) * 0.2, -0.12), Vector3.ONE * 0.05)
	# Branch arms with leaves, blossoms and glowing fruit.
	for side: float in [-1.0, 1.0]:
		var p := limb_pivot(_torso, Vector3(side * 0.24, 0.36, 0.0))
		limb(p, Vector3.ZERO, Vector3(side * 0.05, -0.38, -0.02), 0.05, bark)
		limb(p, Vector3(side * 0.05, -0.38, -0.02), Vector3(side * 0.02, -0.72, -0.08), 0.035, bark)
		limb(p, Vector3(side * 0.04, -0.5, -0.04), Vector3(side * 0.2, -0.66, 0.02), 0.02, bark)
		for k in 4:
			Art.part(p, Art.sphere(), leaf, Vector3(side * (0.06 + 0.04 * float(k % 2)), -0.3 - k * 0.12, -0.05), Vector3(0.14, 0.1, 0.12))
		var f := keep(Art.part(p, Art.sphere(), Art.glow(BLOOM, 2.0), Vector3(side * 0.16, -0.62, 0.0), Vector3.ONE * 0.07))
		_fruit.append(f)
		if side < 0.0:
			_arm_l = p
		else:
			_arm_r = p
	finish()


func pose(_delta: float) -> void:
	var thrust := act([&"chase", &"cross", &"lanes"])
	var shake := act([&"orbs"])
	var spread := act([&"pyre", &"rain", &"sweep"])
	var summon_w := act([&"summon"]) + rise_w
	body.position.y = rise_w * 0.4 - kneel_w * 0.5
	_trunk.rotation.z = sin(t * 0.6) * 0.03 + shake * sin(t * 20.0) * 0.05
	_torso.rotation.x = 0.05 - thrust * 0.3 * strike_w + summon_w * 0.15 - kneel_w * 0.4
	_torso.rotation.y = sin(t * 0.4) * 0.1
	_head.rotation.x = sin(t * 0.5) * 0.05 + kneel_w * 0.4
	_canopy.scale = Vector3.ONE * (1.0 + summon_w * 0.15 + float(boss_phase) * 0.1 + shake * 0.08 * sin(t * 24.0))
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var arm_n := _arm_l if i == 0 else _arm_r
		var r := Vector3(0.2 + sin(t * 0.8 + float(i)) * 0.08, 0.0, s * 0.25)
		r = mixv(r, Vector3(lerpf(2.4, 0.9, strike_w), 0.0, s * 0.1), thrust * (1.0 if i == 1 else 0.3))
		r = mixv(r, Vector3(0.6, 0.0, s * 1.3), spread)
		r = mixv(r, Vector3(2.8, 0.0, s * 0.5), minf(summon_w, 1.0))
		r = mixv(r, Vector3(1.6 + sin(t * 18.0) * 0.2, 0.0, s * 0.6), shake)
		arm_n.rotation = r
	for f in _fruit:
		f.scale = Vector3.ONE * 0.07 * (1.0 + windup_w * 0.8 + 0.1 * sin(t * 3.0))
	for i in _roots.size():
		_roots[i].rotation.z = sin(t * 1.5 + float(i)) * 0.06 + thrust * strike_w * 0.2
