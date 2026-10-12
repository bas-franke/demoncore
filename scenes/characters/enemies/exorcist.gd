extends ProcModel
## "Exorcist" (SHOOT, ExorcismBolt): a grim priest whose rite tears at what a demon has gathered.
## Black cassock, a long violet stole embroidered with gold crosses, a silver aspergillum flicking
## holy water in one hand and an open Rituale in the other, a white collar, a sigil of binding
## burning on the open page. SHOOT: he reads the rite (book raised, the sigil flares, the
## aspergillum is shaken), then hurls a binding sigil: on hit it drains Ichor and reaped souls
## (see res://scenes/characters/projectiles/exorcism_bolt.gd).

const RITE := Color(0.75, 0.6, 1.0)
const HIP := 0.5

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _stole: Node3D
var _sigil: MeshInstance3D


func build() -> void:
	feather_count = 0
	mote_count = 6
	light_color = RITE
	stride = 1.1
	var cassock := m_cloth(Color(0.06, 0.06, 0.07))
	var violet := Art.mat(Color(0.35, 0.12, 0.45), 0.5, 0.0, 0.1, true, 0.6, &"cloth")
	var silver := m_metal(Color(0.85, 0.85, 0.9), 0.2)
	var skin := m_skin(Color(0.8, 0.7, 0.62))
	_torso = biped(HIP, 0.04, cassock, m_leather(Color(0.06, 0.05, 0.05)), 0.08, 0.5)
	Art.part(body, Art.cylinder(0.16, 0.25), cassock, Vector3(0.0, -0.22, 0.0), Vector3(1.0, 0.5, 0.9))
	Art.part(_torso, Art.cylinder(0.17, 0.15), cassock, Vector3(0.0, 0.2, 0.0), Vector3(1.0, 0.42, 0.78))
	Art.part(_torso, Art.cylinder(0.5, 0.5), Art.mat(Art.HOLY_WHITE, 0.6), Vector3(0.0, 0.42, 0.0), Vector3(0.2, 0.03, 0.18))
	# Stole: two violet bands hanging from the neck past the knees (sway), gold crosses at the ends.
	_stole = animated(Art.pivot(_torso, Vector3(0.0, 0.4, -0.08)))
	for s: float in [-1.0, 1.0]:
		Art.part(_stole, Art.box(), violet, Vector3(s * 0.06, -0.38, -0.02), Vector3(0.05, 0.78, 0.012))
		Art.part(_stole, Art.box(), m_gold(), Vector3(s * 0.06, -0.7, -0.03), Vector3(0.012, 0.06, 0.005))
		Art.part(_stole, Art.box(), m_gold(), Vector3(s * 0.06, -0.69, -0.03), Vector3(0.04, 0.012, 0.005))
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.53, 0.0)))
	Art.part(_head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.15, 0.19, 0.16))
	Art.part(_head, Art.sphere(), m_cloth(Color(0.55, 0.55, 0.55)), Vector3(0.0, 0.05, 0.02), Vector3(0.155, 0.1, 0.15))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(RITE, 1.6), Vector3(s * 0.035, 0.02, -0.074), Vector3(0.025, 0.012, 0.01))
	var a := arm(_torso, Vector3(-0.2, 0.37, 0.0), 0.4, 0.04, cassock, skin, 0.0, 0.0)
	_arm_l = a[0]
	# The Rituale: an open book with a burning binding sigil on the page.
	var bk := Art.pivot(a[1], Vector3(0.0, -0.04, -0.06), Vector3(-1.2, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		Art.part(bk, Art.box(), Art.mat(Color(0.1, 0.06, 0.08), 0.6), Vector3(s * 0.06, 0.0, 0.0), Vector3(0.12, 0.015, 0.16), Vector3(0.0, 0.0, -s * 0.15))
		Art.part(bk, Art.box(), Art.mat(Art.IVORY, 0.8, 0.0, 0.2, true, 0.0, &"parchment"), Vector3(s * 0.058, 0.012, 0.0), Vector3(0.11, 0.01, 0.15), Vector3(0.0, 0.0, -s * 0.15))
	_sigil = keep(Art.part(bk, Art.torus(0.75, 1.0), Art.glow(RITE, 2.4), Vector3(0.0, 0.03, 0.0), Vector3.ONE * 0.05))
	var b := arm(_torso, Vector3(0.2, 0.37, 0.0), 0.4, 0.04, cassock, skin, 0.0, 0.0)
	_arm_r = b[0]
	# Aspergillum: a short silver handle with a pierced ball.
	limb(b[1], Vector3.ZERO, Vector3(0.0, -0.16, -0.02), 0.012, silver)
	Art.part(b[1], Art.sphere(), silver, Vector3(0.0, -0.2, -0.02), Vector3.ONE * 0.06)
	finish()


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.03)
	var rite := windup_w
	_torso.rotation.x = -0.05 * move_w + rite * 0.08 - attack_kick * 0.2
	_head.rotation.x = 0.15 + rite * 0.15
	_stole.rotation.x = 0.2 * move_w + sin(walk * 2.0) * 0.04 + attack_kick * 0.3
	# Book held up to read; aspergillum shaken in the wind-up, flung forward on the cast.
	_arm_l.rotation = mixv(Vector3(0.9, 0.3, 0.0), Vector3(1.5, 0.2, 0.0), rite)
	var shake := sin(t * 18.0) * 0.4 * rite
	_arm_r.rotation = Vector3(0.3 + sin(walk) * 0.25 * move_w + rite * 0.9 + shake + attack_kick * 1.0, 0.0, 0.15)
	_sigil.scale = Vector3.ONE * 0.05 * (1.0 + rite * 1.5 + 0.1 * sin(t * 5.0))
	_sigil.rotation.y += 0.05 + rite * 0.2
