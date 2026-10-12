extends ProcModel
## "Gilded Clockwork Cherub" (EXPLODE): a toy of the citadel's artificers, made to sing hymns on
## the hour, now made to do something else. A round gold-plated infant automaton with riveted
## seams, a porcelain face with painted cheeks and a fixed smile, a big wind-up key turning in its
## back, fan-of-gear wings that tick round, and a glass belly with a spinning escapement inside.
## EXPLODE: the key spins faster and faster, the belly glows white-hot (the fuse) and it bursts.

const CORE := Color(1.0, 0.85, 0.5)

var _key: Node3D
var _gears: Array[Node3D] = []
var _belly: MeshInstance3D
var _head: Node3D


func build() -> void:
	feather_count = 0
	mote_count = 6
	debris = [&"gold", &"gold", &"steel"]
	debris_color = Art.GOLD
	death_style = &"shrink"
	death_time = 0.2
	var gold := m_gold()
	var brass := Art.mat(Art.BRONZE, 0.3, 0.95, 0.25, true, 0.0, &"gold")
	var porcelain := Art.mat(Color(0.95, 0.93, 0.9), 0.25, 0.0, 0.05, true, 0.6, &"marble")
	body = animated(Art.pivot(self, Vector3(0.0, 0.45, 0.0)))
	Art.part(body, Art.sphere(), gold, Vector3.ZERO, Vector3(0.34, 0.34, 0.32))
	# Riveted seams and a glass belly with the escapement glowing inside.
	Art.part(body, Art.torus(0.9, 1.0), brass, Vector3.ZERO, Vector3(0.175, 0.2, 0.165), Vector3(PI * 0.5, 0.0, 0.0))
	Art.part(body, Art.torus(0.9, 1.0), brass, Vector3.ZERO, Vector3.ONE * 0.172)
	Art.part(body, Art.sphere(), Art.mat(Color(0.8, 0.9, 1.0), 0.05, 0.0, 0.0, true, 0.9, &"crystal"), Vector3(0.0, -0.02, -0.13), Vector3(0.16, 0.16, 0.08))
	_belly = keep(Art.part(body, Art.sphere(), Art.glow(CORE, 1.8), Vector3(0.0, -0.02, -0.12), Vector3.ONE * 0.08))
	_head = animated(Art.pivot(body, Vector3(0.0, 0.25, -0.01)))
	Art.part(_head, Art.sphere(), porcelain, Vector3.ZERO, Vector3(0.24, 0.22, 0.22))
	Art.part(_head, Art.sphere(), gold, Vector3(0.0, 0.06, 0.02), Vector3(0.24, 0.14, 0.22))  # gilt curls cap
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.mat(Color(0.9, 0.5, 0.5), 0.4), Vector3(s * 0.06, -0.04, -0.09), Vector3(0.05, 0.03, 0.02))
		Art.part(_head, Art.sphere(), Art.mat(Color(0.15, 0.2, 0.45), 0.2, 0.0, 0.0, true, 0.6), Vector3(s * 0.045, 0.0, -0.1), Vector3(0.035, 0.035, 0.015))
	Art.part(_head, Art.box(), Art.mat(Color(0.6, 0.15, 0.15), 0.4), Vector3(0.0, -0.06, -0.105), Vector3(0.05, 0.008, 0.01))
	halo(_head, Vector3(0.0, 0.17, 0.0), 0.1, 1.8, false, false, Art.GOLD)
	# Wind-up key in the back.
	_key = animated(Art.pivot(body, Vector3(0.0, 0.05, 0.17)))
	limb(_key, Vector3.ZERO, Vector3(0.0, 0.0, 0.1), 0.015, brass)
	for s: float in [-1.0, 1.0]:
		Art.part(_key, Art.torus(0.6, 1.0), brass, Vector3(s * 0.05, 0.0, 0.11), Vector3.ONE * 0.05, Vector3(0.0, 0.0, PI * 0.5))
	# Gear wings: a toothed disc on each side that ticks round.
	for s: float in [-1.0, 1.0]:
		var g := animated(Art.pivot(body, Vector3(s * 0.2, 0.1, 0.08), Vector3(0.0, 0.0, s * 0.4)))
		Art.part(g, Art.cylinder(0.5, 0.5), gold, Vector3(s * 0.12, 0.0, 0.0), Vector3(0.24, 0.02, 0.24))
		for k in 8:
			var a := TAU * float(k) / 8.0
			Art.part(g, Art.box(), gold, Vector3(s * 0.12 + cos(a) * 0.13, 0.0, sin(a) * 0.13), Vector3(0.04, 0.02, 0.04), Vector3(0.0, -a, 0.0))
		Art.part(g, Art.cylinder(0.5, 0.5), brass, Vector3(s * 0.12, 0.012, 0.0), Vector3(0.06, 0.02, 0.06))
		_gears.append(g)
	# Little jointed legs and arms (kick and wave in pose).
	for s: float in [-1.0, 1.0]:
		var hip := limb_pivot(body, Vector3(s * 0.08, -0.14, 0.0))
		limb(hip, Vector3.ZERO, Vector3(0.0, -0.14, 0.02), 0.035, gold)
		Art.part(hip, Art.sphere(), porcelain, Vector3(0.0, -0.16, 0.0), Vector3(0.06, 0.05, 0.08))
		add_leg(hip, 0.0 if s < 0.0 else PI, 0.6, 0.0)
		var sh := limb_pivot(body, Vector3(s * 0.16, 0.06, -0.02))
		limb(sh, Vector3.ZERO, Vector3(0.0, -0.13, 0.0), 0.03, gold)
		Art.part(sh, Art.sphere(), porcelain, Vector3(0.0, -0.14, 0.0), Vector3.ONE * 0.05)
		add_arm(sh, PI if s < 0.0 else 0.0, 0.6)
	finish()


func pose(delta: float) -> void:
	var fuse := windup_w
	# Jerky clockwork hop: quantised bob.
	body.position.y = 0.45 + snappedf(absf(sin(walk)) * 0.06 * move_w, 0.015) + sin(t * 40.0) * 0.01 * fuse
	body.rotation.z = snappedf(sin(walk) * 0.1 * move_w, 0.05) + sin(t * 50.0) * 0.05 * fuse
	_head.rotation.y = snappedf(sin(t * 1.2) * 0.5, 0.25)
	_key.rotation.z += delta * (2.0 + fuse * 25.0)
	for i in _gears.size():
		_gears[i].rotation.y += delta * (1.5 + fuse * 15.0) * (1.0 if i == 0 else -1.0)
	_belly.scale = Vector3.ONE * (0.08 + fuse * (0.1 + 0.1 * state_progress) + 0.01 * sin(t * 20.0))
