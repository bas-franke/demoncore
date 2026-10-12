extends DemonKit
## "Hellhound Kennel" (Basecamp prop + NPCs): a pen of black iron bars on a basalt floor with a
## doghouse built of ribs and a skull lintel, a trough of glowing meat, a gnawed-bone pile, and
## three hellhounds: one asleep in the doghouse, one lying by the trough, one pacing the pen. The
## pen is solid (StaticBody3D). talk() (the "Pet the hounds" interaction) wakes them all: the
## sleepers lift their heads, the pacer stops and stares.

const W := 2.6
const D := 2.0

var _hounds: Array[ProcModel] = []
var _pacer: ProcModel
var _pace_t := 0.0


func build() -> void:
	mote_count = 0
	var iron := m_metal(Color(0.15, 0.13, 0.13), 0.55)
	var basalt := m_stone(Color(0.15, 0.12, 0.12))
	var bone := Art.mat(Art.BONE, 0.6, 0.0, 0.4, true, 0.0, &"bone")
	Art.part(self, Art.box(), basalt, Vector3(0.0, 0.03, 0.0), Vector3(W + 0.2, 0.06, D + 0.2))
	# Iron bars on three sides (the back, +Z, and both ends); the front (-Z) is open.
	for i in 14:
		var x := -W * 0.5 + W * float(i) / 13.0
		limb(self, Vector3(x, 0.05, D * 0.5), Vector3(x, 1.0, D * 0.5), 0.02, iron)
	for s: float in [-1.0, 1.0]:
		for i in 10:
			var z := -D * 0.5 + D * float(i) / 9.0
			limb(self, Vector3(s * W * 0.5, 0.05, z), Vector3(s * W * 0.5, 1.0, z), 0.02, iron)
		limb(self, Vector3(s * W * 0.5, 1.0, -D * 0.5), Vector3(s * W * 0.5, 1.0, D * 0.5), 0.03, iron)
	limb(self, Vector3(-W * 0.5, 1.0, D * 0.5), Vector3(W * 0.5, 1.0, D * 0.5), 0.03, iron)
	# Spiked finials on the corners.
	for c: Vector3 in [Vector3(-W * 0.5, 1.0, D * 0.5), Vector3(W * 0.5, 1.0, D * 0.5), Vector3(-W * 0.5, 1.0, -D * 0.5), Vector3(W * 0.5, 1.0, -D * 0.5)]:
		Art.part(self, Art.cone(0.5), iron, c + Vector3(0.0, 0.1, 0.0), Vector3(0.06, 0.2, 0.06))
	# Doghouse of ribs with a skull over the door (back-left corner).
	var dh := Art.pivot(self, Vector3(-0.75, 0.0, 0.45))
	for i in 6:
		var x := -0.35 + 0.14 * float(i)
		for s: float in [-1.0, 1.0]:
			limb(dh, Vector3(x, 0.05, s * 0.32), Vector3(x, 0.62, s * 0.05), 0.025, bone)
	Art.part(dh, Art.box(), basalt, Vector3(-0.38, 0.32, 0.0), Vector3(0.05, 0.6, 0.62))
	Art.part(dh, Art.sphere(), bone, Vector3(0.4, 0.62, 0.0), Vector3(0.16, 0.15, 0.18))
	for s: float in [-1.0, 1.0]:
		Art.part(dh, Art.sphere(), Art.glow(Art.EMBER, 2.0), Vector3(0.47, 0.64, s * 0.04), Vector3(0.03, 0.03, 0.03))
	# Trough of glowing meat (front-right) and a pile of gnawed bones.
	Art.part(self, Art.box(), iron, Vector3(0.7, 0.12, -0.55), Vector3(0.7, 0.18, 0.26))
	Art.part(self, Art.box(), Art.glow(Art.HELLFIRE, 1.2), Vector3(0.7, 0.21, -0.55), Vector3(0.62, 0.02, 0.18))
	for k in 5:
		Art.part(self, Art.sphere(), m_skin(Color(0.45, 0.08, 0.06)), Vector3(0.48 + k * 0.1, 0.23, -0.55 + 0.03 * sin(float(k))), Vector3(0.09, 0.06, 0.08))
	for k in 6:
		var a := float(k) * 1.1
		limb(self, Vector3(-0.2 + cos(a) * 0.12, 0.08, -0.6 + sin(a) * 0.1), Vector3(-0.2 - cos(a) * 0.12, 0.1, -0.6 - sin(a) * 0.1), 0.02, bone)
	finish()
	_add_hound(Vector3(-0.75, 0.0, 0.45), PI * 0.5, true)
	_add_hound(Vector3(0.6, 0.0, -0.05), PI, true)
	_pacer = _add_hound(Vector3(0.0, 0.0, 0.2), -PI * 0.5, false)


func _add_hound(pos: Vector3, yaw: float, resting: bool) -> ProcModel:
	var h := (load("res://scenes/characters/allies/hellhound.tscn") as PackedScene).instantiate() as ProcModel
	h.set(&"resting", resting)
	h.autoplay = not resting  # the pacer is driven below; sleepers drive themselves
	h.position = pos
	h.rotation.y = yaw
	add_child(h)
	_hounds.append(h)
	return h


func _ready() -> void:
	super._ready()
	# Solid pen: one box for the whole kennel (the avatar walks around it).
	if bool(autoplay):
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(W + 0.2, 1.2, D + 0.2)
		cs.shape = box
		cs.position.y = 0.6
		sb.add_child(cs)
		add_child(sb)


func _process(delta: float) -> void:
	super._process(delta)
	if _pacer == null:
		return
	# The pacer walks a slow figure-of-eight along the front of the pen, unless startled.
	var startled := gesture_w > 0.05
	_pace_t += delta * (0.0 if startled else 0.45)
	var p := Vector3(sin(_pace_t) * 0.8, 0.0, sin(_pace_t * 2.0) * 0.25 - 0.1)
	var vel := (p - _pacer.position) / maxf(delta, 0.001)
	_pacer.position = p
	vel.y = 0.0
	if vel.length() > 0.05:
		_pacer.rotation.y = lerp_angle(_pacer.rotation.y, atan2(-vel.x, -vel.z), 1.0 - exp(-6.0 * delta))
	_pacer.ground_speed = vel.length() * 0.6
	_pacer.animate(delta, clampf(vel.length() / 1.0, 0.0, 1.0), State.MOVING)


## "Pet the hounds": everyone wakes up and looks.
func talk() -> void:
	gesture(0, 2.0)
	for h in _hounds:
		h.gesture(0, 2.0)
