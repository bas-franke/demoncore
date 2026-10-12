extends ProcModel
## Training dummy for the Proving Pit in Basecamp Hell: a straw-stuffed angel effigy lashed to a
## wooden post, with a tin halo, sackcloth wings and a painted target on its chest. Used as the
## model of the pit's (unkillable, harmless) dummy Enemy. Wobbles on its post when struck.

var _effigy: Node3D
var _halo_pivot: Node3D
var _wobble := 0.0
var _wobble_dir := 1.0


func build() -> void:
	idle_gesture_every = 0.0
	var wood := m_wood()
	var sack := m_cloth(Color(0.55, 0.47, 0.32))
	var straw := Art.mat(Color(0.7, 0.6, 0.3), 0.95, 0.0, 0.4, true, 0.0, &"rope")
	var tin := Art.mat(Color(0.75, 0.66, 0.4), 0.35, 0.9, 0.3, true, 0.0, &"gold")
	# Post and base (static).
	Art.part(self, Art.cylinder(0.06, 0.08), wood, Vector3(0.0, 0.7, 0.0), Vector3(1.0, 1.4, 1.0))
	Art.part(self, Art.box(), wood, Vector3(0.0, 0.05, 0.0), Vector3(0.7, 0.1, 0.12))
	Art.part(self, Art.box(), wood, Vector3(0.0, 0.05, 0.0), Vector3(0.12, 0.1, 0.7))
	# The effigy pivots at the post's foot so hits rock it.
	_effigy = animated(Art.pivot(self, Vector3(0.0, 0.1, 0.0)))
	Art.part(_effigy, Art.box(), wood, Vector3(0.0, 1.15, 0.0), Vector3(1.0, 0.07, 0.07))  # crossbar
	Art.part(_effigy, Art.capsule(0.22, 0.75), sack, Vector3(0.0, 0.95, 0.0), Vector3(1.0, 1.0, 0.75))
	for s: float in [-1.0, 1.0]:
		# Arms tied along the crossbar, straw poking out of the cuffs.
		Art.part(_effigy, Art.capsule(0.07, 0.4), sack, Vector3(s * 0.32, 1.15, 0.0), Vector3.ONE,
				Vector3(0.0, 0.0, PI * 0.5))
		Art.part(_effigy, Art.cone(0.5), straw, Vector3(s * 0.55, 1.15, 0.0), Vector3(0.1, 0.14, 0.1),
				Vector3(0.0, 0.0, -s * PI * 0.5))
		# Sackcloth wings nailed on behind.
		Art.part(_effigy, Art.box(), sack, Vector3(s * 0.32, 1.05, 0.14), Vector3(0.5, 0.42, 0.03),
				Vector3(0.0, s * -0.4, s * 0.35))
	# Head: a stuffed sack with a stitched face, a tin halo on a wire.
	Art.part(_effigy, Art.sphere(), sack, Vector3(0.0, 1.42, 0.0), Vector3(0.28, 0.3, 0.26))
	Art.part(_effigy, Art.box(), Art.mat(Color(0.1, 0.06, 0.05), 0.9), Vector3(0.0, 1.42, -0.13),
			Vector3(0.12, 0.012, 0.01))
	_halo_pivot = animated(Art.pivot(_effigy, Vector3(0.0, 1.66, 0.02)))
	Art.part(_halo_pivot, Art.torus(0.8, 1.0), tin, Vector3.ZERO, Vector3(0.18, 0.18, 0.18), Vector3(0.3, 0.0, 0.0))
	# Painted target: red rings on the chest.
	for k in 3:
		var r := 0.16 - k * 0.05
		Art.part(_effigy, Art.cylinder(0.5, 0.5), Art.mat(Art.CRIMSON if k % 2 == 0 else Art.IVORY, 0.8),
				Vector3(0.0, 0.98, -0.16 - k * 0.004), Vector3(r * 2.0, 0.01, r * 2.0), Vector3(PI * 0.5, 0.0, 0.0))
	finish()


func jiggle_eyes(strength: float = 1.0, from_dir: Vector3 = Vector3.ZERO) -> void:
	super.jiggle_eyes(strength, from_dir)
	_wobble = 1.0
	_wobble_dir = -_wobble_dir


func pose(delta: float) -> void:
	_wobble = maxf(0.0, _wobble - delta * 1.6)
	# Damped rock on the post, plus the halo swinging on its wire.
	var rock := sin(t * 18.0) * _wobble * 0.18 * _wobble_dir
	_effigy.rotation = Vector3(rock * 0.6, 0.0, rock)
	_halo_pivot.rotation.z = sin(t * 3.0) * 0.15 + rock * 2.0
