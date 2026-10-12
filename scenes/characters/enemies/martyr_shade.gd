extends ProcModel
## "Martyr's Shade" (CHASE, fast, hovers): what rises from a slain Martyr. A pale, translucent
## figure of light trailing off into wisps instead of legs, arms reaching forward, the arrows
## still in it, its halo now cracked and burning. Spawned by martyr.gd on death (not in the map
## pools). It does not leave a corpse; it simply goes out.

const GHOST := Color(0.75, 0.85, 1.0)

var _arm_l: Node3D
var _arm_r: Node3D
var _tail: Array[Node3D] = []


func build() -> void:
	feather_count = 0
	mote_count = 10
	light_color = GHOST
	death_style = &"shrink"
	death_time = 0.3
	var veil := Art.glow(GHOST, 0.9, true, 0.7)
	var core := Art.glow(Art.HOLY_WHITE, 1.4)
	body = animated(Art.pivot(self, Vector3(0.0, 0.55, 0.0)))
	Art.part(body, Art.sphere(), veil, Vector3(0.0, 0.2, 0.0), Vector3(0.3, 0.42, 0.24))
	Art.part(body, Art.sphere(), core, Vector3(0.0, 0.22, 0.0), Vector3(0.14, 0.24, 0.12))
	var head := Art.pivot(body, Vector3(0.0, 0.5, 0.0))
	Art.part(head, Art.sphere(), veil, Vector3.ZERO, Vector3(0.18, 0.2, 0.18))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(Art.OBSIDIAN, 1.0, false), Vector3(s * 0.04, 0.0, -0.08), Vector3(0.04, 0.05, 0.02))
	Art.part(head, Art.sphere(), Art.glow(Art.OBSIDIAN, 1.0, false), Vector3(0.0, -0.06, -0.08), Vector3(0.04, 0.06, 0.02))
	# Cracked halo: a broken ring tilted askew.
	var h := Art.pivot(head, Vector3(0.0, 0.15, 0.03), Vector3(0.3, 0.0, 0.25))
	for k in 5:
		var a := TAU * float(k) / 6.0
		Art.part(h, Art.box(), Art.glow(Art.EMBER, 2.4), Vector3(cos(a), 0.0, sin(a)) * 0.12, Vector3(0.07, 0.015, 0.015), Vector3(0.0, -a, 0.0))
	# Wispy tail of three fading puffs (sway).
	for i in 3:
		var w := animated(Art.pivot(body, Vector3(0.0, -0.05 - i * 0.15, 0.04 + i * 0.05)))
		Art.part(w, Art.sphere(), veil, Vector3.ZERO, Vector3.ONE * (0.24 - i * 0.06))
		_tail.append(w)
	_arm_l = limb_pivot(body, Vector3(-0.14, 0.34, 0.0))
	limb(_arm_l, Vector3.ZERO, Vector3(0.0, -0.32, 0.0), 0.035, veil)
	_arm_r = limb_pivot(body, Vector3(0.14, 0.34, 0.0))
	limb(_arm_r, Vector3.ZERO, Vector3(0.0, -0.32, 0.0), 0.035, veil)
	finish()


func pose(_delta: float) -> void:
	body.position.y = 0.55 + sin(t * 2.6) * 0.07
	body.rotation.x = -0.35 * move_w
	var reach := 1.3 + 0.2 * sin(t * 5.0)
	_arm_l.rotation = Vector3(reach, 0.0, -0.15)
	_arm_r.rotation = Vector3(reach + 0.15 * sin(t * 5.0 + 1.0), 0.0, 0.15)
	for i in _tail.size():
		_tail[i].position.x = sin(t * 3.0 - float(i)) * 0.05 * float(i + 1)
