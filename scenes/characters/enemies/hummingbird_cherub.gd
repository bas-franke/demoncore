extends ProcModel
## "Hummingbird Cherub" (CHASE, swarms of four, outer gardens only): a tiny cherub-headed
## hummingbird - an iridescent green-and-violet body, a long golden beak, a baby's face with a
## pin of a halo, wings beating to a blur. It darts in sudden zig-zags and hovers in place between
## them. Each one that arrives brings three more (spawn_companions; the companions don't).

const IRIDESCENT := Color(0.2, 0.75, 0.55)

var _blur: Array[Node3D] = []
var _dart := Vector3.ZERO
var _dart_t := 0.0
var _flocked := false


func build() -> void:
	feather_count = 1
	mote_count = 2
	death_style = &"shrink"
	death_time = 0.2
	var body_mat := Art.mat(IRIDESCENT, 0.25, 0.4, 0.05, true, 0.8, &"feather")
	var throat := Art.mat(Color(0.65, 0.2, 0.7), 0.25, 0.4, 0.05, true, 0.8, &"feather")
	body = animated(Art.pivot(self, Vector3(0.0, 0.7, 0.0)))
	Art.part(body, Art.sphere(), body_mat, Vector3(0.0, 0.0, 0.03), Vector3(0.12, 0.12, 0.2))
	Art.part(body, Art.sphere(), throat, Vector3(0.0, -0.02, -0.06), Vector3(0.1, 0.09, 0.08))
	Art.part(body, Art.cone(0.5), body_mat, Vector3(0.0, 0.0, 0.16), Vector3(0.08, 0.14, 0.02), Vector3(PI * 0.5, 0.0, 0.0))
	# The cherub's face on the bird's head, golden beak, a pin of a halo.
	var head := Art.pivot(body, Vector3(0.0, 0.05, -0.1))
	Art.part(head, Art.sphere(), m_skin(Color(0.96, 0.85, 0.78)), Vector3.ZERO, Vector3(0.1, 0.1, 0.1))
	Art.part(head, Art.sphere(), m_gold(), Vector3(0.0, 0.04, 0.01), Vector3(0.1, 0.05, 0.09))
	Art.part(head, Art.cone(0.5), m_gold(), Vector3(0.0, -0.01, -0.1), Vector3(0.014, 0.14, 0.014), Vector3(-PI * 0.5, 0.0, 0.0))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(Art.HOLY_WHITE, 1.6), Vector3(s * 0.025, 0.01, -0.045), Vector3.ONE * 0.02)
	halo(head, Vector3(0.0, 0.08, 0.0), 0.04, 2.4)
	# Blur wings: thin glowing ovals that flicker.
	for s: float in [-1.0, 1.0]:
		var w := animated(Art.pivot(body, Vector3(s * 0.05, 0.04, 0.0)))
		Art.part(w, Art.sphere(), Art.glow(Color(0.8, 1.0, 0.9), 0.6, true, 0.5), Vector3(s * 0.12, 0.0, 0.02), Vector3(0.24, 0.01, 0.08))
		_blur.append(w)
	finish()


func pose(delta: float) -> void:
	if not _flocked:
		_flocked = true
		spawn_companions(3, &"hummingbird_flock", 1.2)
	# Darting: sudden small jumps of the body, then a hover.
	_dart_t -= delta
	if _dart_t <= 0.0:
		_dart_t = randf_range(0.25, 0.7)
		_dart = Vector3(randf_range(-0.4, 0.4), randf_range(-0.15, 0.2), randf_range(-0.3, 0.3))
	body.position = body.position.lerp(Vector3(0.0, 0.7, 0.0) + _dart, 1.0 - exp(-14.0 * delta))
	body.rotation.x = -0.4 * move_w + sin(t * 3.0) * 0.1
	for i in _blur.size():
		var s := -1.0 if i == 0 else 1.0
		_blur[i].rotation.z = s * sin(t * 70.0) * 0.8
