extends DemonKit
## "Damned Laborer" (Basecamp ambient): a soul condemned to work the camp forever. A gaunt,
## grey-blue, half-translucent figure in a rag loincloth, iron collar and shackles with a dragging
## chain, hollow glowing eyes. `task` picks the job:
##   0 hauler  - drags a stone block on a chain back and forth along `patrol` (walks)
##   1 miner   - swings a pick at a rock, chips of ember flying
##   2 carrier - carries a bucket of lava on a yoke back and forth along `patrol`
## Patrols run between the spawn position and spawn + `patrol` (local XZ offset), turning at
## each end; the model drives itself (Basecamp: autoplay).

const HIP := 0.42
const SOUL := Color(0.55, 0.75, 0.9)

## 0 hauler, 1 miner, 2 carrier.
@export var task := 0
## Patrol offset (m, parent-local XZ) from the starting position; zero = stay put.
@export var patrol := Vector3(3.0, 0.0, 0.0)
@export var walk_speed := 0.7

var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _load: Node3D
var _home := Vector3.ZERO
var _to_b := true
var _pause := 0.0
var _move := 0.0


func build() -> void:
	light_color = SOUL
	debris = [&"mote"]
	debris_color = SOUL
	stride = 0.9
	idle_gesture_every = 0.0
	var flesh := Art.mat(Color(0.42, 0.5, 0.58), 0.7, 0.0, 0.1, true, 0.5, &"skin")
	var rag := m_cloth(Color(0.25, 0.22, 0.2))
	var iron := m_metal(Color(0.2, 0.2, 0.2), 0.6)
	_torso = biped(HIP, 0.03, flesh, flesh, 0.07, 0.5)
	Art.part(body, Art.cylinder(0.12, 0.15), rag, Vector3(0.0, -0.04, 0.0), Vector3(1.0, 0.14, 0.85))
	# Gaunt ribbed torso.
	Art.part(_torso, Art.cylinder(0.14, 0.11), flesh, Vector3(0.0, 0.17, 0.0), Vector3(1.0, 0.36, 0.7))
	for k in 3:
		Art.part(_torso, Art.box(), Art.mat(Color(0.3, 0.36, 0.42), 0.8), Vector3(0.0, 0.14 + k * 0.05, -0.085), Vector3(0.16, 0.008, 0.01))
	Art.part(_torso, Art.torus(0.7, 1.0), iron, Vector3(0.0, 0.36, 0.0), Vector3.ONE * 0.08)
	_head = animated(Art.pivot(_torso, Vector3(0.0, 0.44, -0.02)))
	Art.part(_head, Art.sphere(), flesh, Vector3.ZERO, Vector3(0.14, 0.17, 0.15))
	for s: float in [-1.0, 1.0]:
		Art.part(_head, Art.sphere(), Art.glow(SOUL, 2.2), Vector3(s * 0.035, 0.01, -0.07), Vector3(0.03, 0.03, 0.01))
	Art.part(_head, Art.sphere(), Art.mat(Art.OBSIDIAN, 0.5), Vector3(0.0, -0.05, -0.07), Vector3(0.03, 0.04, 0.01))
	# Faint soul-glow aura (half translucent).
	Art.part(_torso, Art.sphere(), Art.glow(SOUL, 0.25, true, 0.5), Vector3(0.0, 0.2, 0.0), Vector3(0.4, 0.7, 0.35))
	var a := arm(_torso, Vector3(-0.15, 0.32, 0.0), 0.32, 0.025, flesh, flesh, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.15, 0.32, 0.0), 0.32, 0.025, flesh, flesh, 0.0, 0.0)
	_arm_r = b[0]
	for h: Node3D in [a[1], b[1]]:
		Art.part(h, Art.cylinder(0.5, 0.5), iron, Vector3(0.0, 0.03, 0.0), Vector3(0.06, 0.03, 0.06))
	# Leg shackles joined by a short chain.
	for i in _legs.size():
		Art.part(_legs[i], Art.cylinder(0.5, 0.5), iron, Vector3(0.0, -HIP * 0.85, 0.0), Vector3(0.06, 0.03, 0.06))
	match task:
		0:
			# A chain over the shoulder to a stone block dragged behind.
			_load = animated(Art.pivot(self, Vector3(0.0, 0.0, 0.9)))
			Art.part(_load, Art.box(), m_stone(Color(0.32, 0.28, 0.27)), Vector3(0.0, 0.17, 0.0), Vector3(0.42, 0.34, 0.5))
			Art.part(_load, Art.box(), Art.glow(Art.EMBER, 1.4), Vector3(0.0, 0.345, 0.0), Vector3(0.1, 0.01, 0.4))
			for k in 6:
				var f := float(k) / 5.0
				Art.part(self, Art.torus(0.55, 1.0), iron, Vector3(0.08, lerpf(0.72, 0.3, f), lerpf(0.1, 0.68, f)),
						Vector3.ONE * 0.04, Vector3(0.0, 0.0, PI * 0.5 * float(k % 2)))
		1:
			# Pickaxe in both hands (on the right hand pivot).
			var pk := Art.pivot(b[1], Vector3.ZERO, Vector3(-PI * 0.5, 0.0, 0.0))
			limb(pk, Vector3(0.0, -0.1, 0.0), Vector3(0.0, 0.42, 0.0), 0.012, m_wood())
			Art.part(pk, Art.cone(0.5), iron, Vector3(0.09, 0.42, 0.0), Vector3(0.03, 0.2, 0.03), Vector3(0.0, 0.0, -PI * 0.5))
			Art.part(pk, Art.cone(0.5), iron, Vector3(-0.07, 0.42, 0.0), Vector3(0.03, 0.14, 0.03), Vector3(0.0, 0.0, PI * 0.5))
			_load = Art.pivot(self, Vector3(0.0, 0.0, -0.6))
			Art.part(_load, Art.sphere(), m_stone(Color(0.25, 0.2, 0.2)), Vector3(0.0, 0.15, 0.0), Vector3(0.55, 0.4, 0.5))
			Art.part(_load, Art.box(), Art.glow(Art.EMBER, 1.8), Vector3(0.0, 0.25, 0.1), Vector3(0.3, 0.012, 0.02), Vector3(0.0, 0.0, 0.4))
		2:
			# Yoke across the shoulders with two buckets of glowing lava.
			_load = animated(Art.pivot(_torso, Vector3(0.0, 0.36, 0.04)))
			limb(_load, Vector3(-0.38, 0.0, 0.0), Vector3(0.38, 0.0, 0.0), 0.018, m_wood())
			for s: float in [-1.0, 1.0]:
				limb(_load, Vector3(s * 0.36, 0.0, 0.0), Vector3(s * 0.36, -0.22, 0.0), 0.005, iron)
				Art.part(_load, Art.cylinder(0.5, 0.42), m_wood(), Vector3(s * 0.36, -0.28, 0.0), Vector3(0.15, 0.14, 0.15))
				Art.part(_load, Art.cylinder(0.5, 0.5), Art.glow(Art.HELLFIRE, 1.8), Vector3(s * 0.36, -0.215, 0.0), Vector3(0.13, 0.01, 0.13))
	finish()


func bake_variant() -> String:
	return str(task)


func _ready() -> void:
	super._ready()
	_home = position


func _process(delta: float) -> void:
	# Patrol between home and home + patrol (haulers and carriers); miners stay at the rock.
	var target_speed := 0.0
	if task != 1 and patrol.length_squared() > 0.01:
		if _pause > 0.0:
			_pause -= delta
		else:
			var goal := _home + (patrol if _to_b else Vector3.ZERO)
			var to := goal - position
			to.y = 0.0
			if to.length() < 0.1:
				_to_b = not _to_b
				_pause = randf_range(0.8, 2.0)
			else:
				var spd := walk_speed * (0.55 if task == 0 else 1.0)
				position += to.normalized() * minf(spd * delta, to.length())
				rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-5.0 * delta))
				target_speed = spd
	_move = damp(_move, target_speed, 6.0, delta)
	ground_speed = _move
	animate(delta, clampf(_move / maxf(walk_speed, 0.01), 0.0, 1.0), State.MOVING)


func pose(_delta: float) -> void:
	biped_bob(HIP, 0.04)
	match task:
		0:
			# Bent double, hauling; both hands on the chain over the shoulder.
			_torso.rotation.x = -0.45 - 0.1 * move_w
			_head.rotation.x = 0.3
			_arm_l.rotation = Vector3(2.6, 0.0, -0.2)
			_arm_r.rotation = Vector3(2.4, 0.0, 0.3)
			if _load:
				_load.position.y = absf(sin(walk * 0.5)) * 0.015 * move_w
		1:
			# Swinging the pick: a slow rhythm of raise and strike.
			var c := fmod(t * 0.8, 1.0)
			var swing := (sin(c * PI * 2.0 - PI * 0.5) + 1.0) * 0.5
			_torso.rotation.x = -0.15 - (1.0 - swing) * 0.35
			_arm_r.rotation = Vector3(lerpf(0.6, 2.9, swing), 0.0, 0.0)
			_arm_l.rotation = Vector3(lerpf(0.7, 2.8, swing), 0.0, 0.3)
			_head.rotation.x = 0.2
		2:
			_torso.rotation.x = -0.12
			_head.rotation.x = 0.1 + sin(t * 0.7) * 0.05
			_arm_l.rotation = Vector3(0.0, 0.0, -1.3)
			_arm_r.rotation = Vector3(0.0, 0.0, 1.3)
			if _load:
				_load.rotation.z = sin(walk * 0.5) * 0.08 * move_w
