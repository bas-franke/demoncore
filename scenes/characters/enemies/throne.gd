extends ProcModel
## "Throne": a wheel of judgement. A great upright bronze-and-gold wheel whose rim is set with
## unblinking eyes, a second wheel turning crosswise through it, burning at the hub, with a pair
## of wings at the axle. It does not walk: it rolls. CHARGE: it spins up in place throwing
## sparks (wind-up), then rolls through you; the rolling follows the real ground speed.

const RIM_EYES := 10
# Holy fire: gold-white, never hellfire orange (docs/team/art-style.md palette).
const FIRE := Color(1.0, 0.78, 0.42)

var _wheel: Node3D
var _cross: Node3D
var _hub: MeshInstance3D
var _spin := 0.0
var _cross_spin := 0.0


func build() -> void:
	light_color = FIRE
	feather_count = 3
	debris = [&"gold", &"mote"]
	debris_color = Art.GOLD
	death_style = &"sink"
	wing_speed = 3.0
	wing_amp = 0.25
	var gold := m_gold()
	var bronze := Art.mat(Art.BRONZE, 0.4, 0.9, 0.35, true, 0.0, &"gold")
	body = animated(Art.pivot(self, Vector3(0.0, 0.62, 0.0)))
	# Main wheel: rim, inner rim, eight spokes and eyes all round (rolls about the X axis).
	_wheel = animated(Art.pivot(body))
	var rim := Art.pivot(_wheel, Vector3.ZERO, Vector3(0.0, 0.0, PI * 0.5))
	Art.part(rim, Art.torus(0.8, 1.0), gold, Vector3.ZERO, Vector3.ONE * 0.64)
	# Teeth of fire around the rim.
	for i in 12:
		var a := TAU * float(i) / 12.0
		Art.part(_wheel, Art.cone(0.5), Art.glow(FIRE, 1.6), Vector3(0.0, cos(a), sin(a)) * 0.7, Vector3(0.05, 0.16, 0.08), Vector3(a, 0.0, 0.0))
	Art.part(rim, Art.torus(0.86, 1.0), bronze, Vector3.ZERO, Vector3.ONE * 0.46)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var d := Vector3(0.0, cos(a), sin(a))
		limb(_wheel, d * 0.08, d * 0.52, 0.022, bronze)
	for i in RIM_EYES:
		var a := TAU * (float(i) + 0.5) / float(RIM_EYES)
		var d := Vector3(0.0, cos(a), sin(a))
		# Eyes look out of both faces of the wheel, alternating sides.
		var side := 1.0 if i % 2 == 0 else -1.0
		eye(_wheel, d * 0.52 + Vector3(side * 0.05, 0.0, 0.0), 0.075, Vector3(side, 0.0, 0.0) + d * 0.4, true)
	# Crosswise wheel, smaller, turning on its own axle (about Z).
	_cross = animated(Art.pivot(body))
	Art.part(_cross, Art.torus(0.85, 1.0), gold, Vector3.ZERO, Vector3.ONE * 0.4, Vector3(PI * 0.5, 0.0, 0.0))
	for i in 4:
		var a := TAU * float(i) / 4.0
		var d := Vector3(cos(a), sin(a), 0.0)
		limb(_cross, d * 0.06, d * 0.36, 0.018, bronze)
	# Burning hub.
	_hub = keep(Art.part(body, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.8), Vector3.ZERO, Vector3.ONE * 0.16))
	Art.part(body, Art.sphere(), Art.glow(FIRE, 0.6), Vector3.ZERO, Vector3.ONE * 0.34)
	# Axle stubs with wings springing from them.
	for s: float in [-1.0, 1.0]:
		Art.part(body, Art.cylinder(0.5, 0.5), gold, Vector3(s * 0.12, 0.0, 0.0), Vector3(0.07, 0.2, 0.07), Vector3(0.0, 0.0, PI * 0.5))
	wing_pair(body, Vector3(0.0, 0.05, 0.0), 0.42, 4, null, null, 0.2)
	finish()


func pose(delta: float) -> void:
	# Roll: angular speed = ground speed / radius. Wind-up spins it in place (sparking).
	var roll := (ground_speed if ground_speed >= 0.0 else move_w * 2.0) / maxf(0.6 * body_scale, 0.1)
	roll += windup_w * 14.0 + strike_w * 6.0
	_spin -= roll * delta
	_wheel.rotation.x = _spin
	_cross_spin += delta * (1.5 + windup_w * 6.0)
	_cross.rotation = Vector3(0.0, _cross_spin * 0.4, _cross_spin)
	body.position.y = 0.62 + absf(sin(_spin * 2.0)) * 0.02 * move_w
	# Lean into the roll, rock back while winding up.
	body.rotation.x = -0.12 * move_w + windup_w * 0.18 * sin(t * 30.0) * 0.3
	body.rotation.z = sin(t * 1.4) * 0.05
	_hub.scale = Vector3.ONE * 0.16 * (1.0 + windup_w * 0.8 + 0.08 * sin(t * 17.0))
	eye_flare = maxf(eye_flare, windup_w)
