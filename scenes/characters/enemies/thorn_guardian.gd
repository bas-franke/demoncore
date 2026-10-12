extends ProcModel
## "Thorn-Hedge Guardian" (SLAM centred on itself, outer gardens only): a topiary warden of the
## First Garden - a walking hedge of dark leaves clipped into the shape of a broad-shouldered
## knight, with a helm of white roses, bramble arms bristling with thorns and a gate of woven
## branches for a chest. Slow and tough. Its "slam" plants its roots and erupts a ring of thorns
## all around it (slam_reach 0, a wide radius): step back when it hunches.

var _torso: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _roses: MeshInstance3D
var _thorns: Node3D


func build() -> void:
	feather_count = 0
	mote_count = 6
	light_color = Color(0.8, 1.0, 0.6)
	debris = [&"mote"]
	debris_color = Color(0.4, 0.7, 0.3)
	death_style = &"sink"
	stride = 1.1
	var hedge := Art.mat(Color(0.16, 0.3, 0.12), 0.85, 0.0, 0.3, true, 0.3, &"cloth")
	var hedge2 := Art.mat(Color(0.22, 0.38, 0.16), 0.85, 0.0, 0.3, true, 0.3, &"cloth")
	var bark := Art.mat(Color(0.3, 0.22, 0.14), 0.9, 0.0, 0.4, true, 0.0, &"wood")
	var rose := Art.mat(Color(0.96, 0.94, 0.9), 0.6, 0.0, 0.05, true, 0.4)
	_torso = biped(0.55, 0.08, bark, bark, 0.14, 0.35)
	# Body: clipped hedge masses (leaf spheres), a woven-branch gate on the chest.
	for c: Array in [[Vector3(0.0, 0.3, 0.0), Vector3(0.7, 0.62, 0.5)], [Vector3(0.0, 0.6, 0.02), Vector3(0.78, 0.36, 0.5)],
			[Vector3(-0.32, 0.6, 0.0), Vector3(0.3, 0.3, 0.32)], [Vector3(0.32, 0.6, 0.0), Vector3(0.3, 0.3, 0.32)]]:
		Art.part(_torso, Art.sphere(), hedge if c[0].x == 0.0 else hedge2, c[0], c[1])
	for k in 4:
		limb(_torso, Vector3(-0.18 + k * 0.12, 0.08, -0.25), Vector3(-0.18 + k * 0.12, 0.55, -0.24), 0.018, bark)
	limb(_torso, Vector3(-0.22, 0.32, -0.26), Vector3(0.22, 0.32, -0.26), 0.018, bark)
	# Helm of white roses.
	var head := Art.pivot(_torso, Vector3(0.0, 0.86, 0.0))
	Art.part(head, Art.sphere(), hedge, Vector3.ZERO, Vector3(0.3, 0.3, 0.3))
	_roses = keep(Art.part(head, Art.sphere(), Art.glow(Color(0.9, 1.0, 0.7), 1.6), Vector3(0.0, 0.0, -0.14), Vector3(0.14, 0.04, 0.02)))
	for k in 6:
		var theta := TAU * float(k) / 6.0
		Art.part(head, Art.sphere(), rose, Vector3(cos(theta) * 0.13, 0.12, sin(theta) * 0.13), Vector3.ONE * 0.08)
	# Bramble arms with thorns.
	var a := arm(_torso, Vector3(-0.42, 0.62, 0.0), 0.56, 0.06, bark, hedge2, 0.0, 0.0)
	_arm_l = a[0]
	var b := arm(_torso, Vector3(0.42, 0.62, 0.0), 0.56, 0.06, bark, hedge2, 0.0, 0.0)
	_arm_r = b[0]
	for arm_n: Node3D in [_arm_l, _arm_r]:
		for k in 5:
			var y := -0.08 - k * 0.1
			Art.part(arm_n, Art.cone(0.5), Art.mat(Color(0.75, 0.7, 0.6), 0.5), Vector3(0.06 * (1.0 if k % 2 == 0 else -1.0), y, -0.03),
					Vector3(0.025, 0.09, 0.025), Vector3(-0.6, 0.0, (1.0 if k % 2 == 0 else -1.0) * 1.2))
	# Thorn crown that erupts from the ground around it during the slam (scaled in pose()).
	_thorns = animated(Art.pivot(self))
	for k in 10:
		var ang := TAU * float(k) / 10.0
		Art.part(_thorns, Art.cone(0.5), bark, Vector3(cos(ang), 0.2, sin(ang)) * 1.1, Vector3(0.1, 0.5, 0.1), Vector3(sin(ang) * 0.4, 0.0, -cos(ang) * 0.4))
	finish()


func pose(_delta: float) -> void:
	biped_bob(0.55, 0.05)
	var hunch := windup_w
	var erupt := maxf(strike_w, recover_w)
	_torso.rotation.x = -0.05 * move_w + hunch * 0.3 - erupt * 0.2
	_arm_l.rotation = mixv(Vector3(0.3 + sin(walk) * 0.25 * move_w, 0.0, -0.2), Vector3(0.9, 0.0, -1.1), maxf(hunch, erupt))
	_arm_r.rotation = mixv(Vector3(0.3 - sin(walk) * 0.25 * move_w, 0.0, 0.2), Vector3(0.9, 0.0, 1.1), maxf(hunch, erupt))
	_thorns.scale = Vector3(1.0, maxf(erupt, 0.001), 1.0)
	_thorns.visible = erupt > 0.02
	_roses.scale = Vector3(0.14, 0.04, 0.02) * (1.0 + hunch * 1.5)


func ragdoll_limbs() -> Array:
	return limbs_with([])
