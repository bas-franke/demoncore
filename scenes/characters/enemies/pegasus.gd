extends HolyHorse
## "Pegasus" (CHASE, flies): a dapple-white winged horse with a pale-blue mane, flying low with its
## legs folded under it and great swan wings beating. It never touches the ground; the beat
## quickens with its speed.

func build() -> void:
	mote_count = 6
	feather_count = 8
	feather_color = Art.HOLY_WHITE
	wing_speed = 4.5
	wing_amp = 0.55
	wing_lift = 0.2
	wing_sweep = 0.25
	build_horse(Color(0.9, 0.9, 0.92), Color(0.62, 0.74, 0.9))
	solid_wing_pair(body, Vector3(0.0, 0.16, -0.12), 0.8, null, Art.mat(Color(0.86, 0.9, 0.96), 0.7, 0.0, 0.1, true, 0.3, &"feather"), null, 0.08)
	finish()


func pose(_delta: float) -> void:
	# Flying gallop: legs fold (front tucked, hind trailing) instead of striding.
	horse_pose(0.0, 0.0)
	body.position.y = HolyHorse.SHOULDER + 0.35 + sin(t * wing_speed) * 0.05
	body.rotation.x = -0.1 * move_w + sin(t * wing_speed + 0.5) * 0.04
	for l in front_legs:
		l.rotation.x = 1.2 + sin(t * 3.0) * 0.15
	for l in back_legs:
		l.rotation.x = -0.9 + sin(t * 3.0 + 1.0) * 0.12
	wing_speed = 4.0 + move_w * 2.0
