extends HolyHorse
## "Unicorn" (CHARGE): a pure white horse with a silver-gold mane and a long spiralled horn that
## burns white at the tip. CHARGE: rears up and paws the air while the horn kindles (wind-up),
## then gallops through you head down, horn levelled.

var _horn_tip: MeshInstance3D


func build() -> void:
	mote_count = 8
	build_horse(Color(0.94, 0.93, 0.9), Color(0.92, 0.84, 0.62))
	# Spiral horn: stacked cones twisting along the forehead's forward-up axis.
	var horn := animated(Art.pivot(head, Vector3(0.0, 0.08, -0.08), Vector3(-PI * 0.5 + 0.55, 0.0, 0.0)))
	var gold := m_gold()
	for i in 4:
		var f := float(i) / 4.0
		Art.part(horn, Art.cone(0.5), Art.mat(Art.IVORY, 0.3, 0.2, 0.05), Vector3(0.0, 0.06 + f * 0.24, 0.0),
				Vector3.ONE * (0.07 - f * 0.012) * Vector3(1.0, 2.6, 1.0), Vector3(0.0, f * 1.2, 0.0))
		Art.part(horn, Art.torus(0.7, 1.0), gold, Vector3(0.0, 0.02 + f * 0.24, 0.0), Vector3.ONE * (0.035 - f * 0.006))
	_horn_tip = keep(Art.part(horn, Art.sphere(), Art.glow(Art.HOLY_WHITE, 2.5), Vector3(0.0, 0.4, 0.0), Vector3.ONE * 0.05))
	finish()


func pose(_delta: float) -> void:
	horse_pose(windup_w, strike_w)
	_horn_tip.scale = Vector3.ONE * 0.05 * (1.0 + windup_w * 2.0 + strike_w * 1.5 + 0.15 * sin(t * 8.0))
