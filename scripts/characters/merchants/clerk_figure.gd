extends MerchantFigure
## Mammon's Clerk (soul broker): a squat, pot-bellied devil of the Ledger in a crimson waistcoat
## with gold buttons, a long tailcoat, a tall gold-banded top hat with a soul gem between curled
## gilt-tipped horns, a monocle and long, thin counting fingers. Idle: counts soul coins: flicks
## the top coin of the stack in its palm into the air, catches it and sets it back; every few
## coins it holds one to the monocle or bites it. Greets with a bow and a doff of the hat; a sale
## makes it rub its hands.

const FLIP := 1.25
const COINS := 6
const SOUL := Color(0.4, 1.0, 0.8)

var _arm_r: Array[Node3D] = []
var _arm_l: Array[Node3D] = []
var _stack: Node3D
var _coin: Node3D
var _hat: Node3D
var _monocle_glint: MeshInstance3D
var _last_k := 0.0


func build() -> void:
	var coat := Art.mat(Color(0.08, 0.05, 0.06), 0.8, 0.0, 0.35, true, 0.2, &"cloth")
	var vest := Art.mat(Color(0.3, 0.035, 0.05), 0.7, 0.0, 0.3, true, 0.25, &"cloth")
	var skin := Art.mat(Color(0.33, 0.26, 0.17), 0.6, 0.0, 0.3, true, 0.15, &"skin")
	var gold := Art.mat(Art.GOLD, 0.28, 1.0, 0.25, true, 0.0, &"gold")
	var black := Art.mat(Color(0.03, 0.025, 0.03), 0.55, 0.0, 0.2, true, 0.1, &"cloth")
	var coin_m := Art.emissive(SOUL.darkened(0.5), SOUL, 2.2)

	# Short legs, buckled shoes.
	for s: float in [-1.0, 1.0]:
		EnemyModel.limb(self, Vector3(s * 0.16, 0.62, 0.0), Vector3(s * 0.17, 0.1, 0.0), 0.09, black)
		Art.part(self, Art.box(), black, Vector3(s * 0.17, 0.05, -0.06), Vector3(0.16, 0.1, 0.3))
		Art.part(self, Art.box(), gold, Vector3(s * 0.17, 0.08, -0.2), Vector3(0.08, 0.05, 0.02))
	torso = Art.pivot(self, Vector3(0.0, 0.62, 0.0))
	# Belly in the waistcoat, gold buttons and a watch chain; tailcoat behind.
	Art.part(torso, Art.sphere(), vest, Vector3(0.0, 0.3, -0.02), Vector3(0.82, 0.8, 0.74))
	Art.part(torso, Art.sphere(), coat, Vector3(0.0, 0.32, 0.08), Vector3(0.86, 0.82, 0.74))
	Art.part(torso, Art.box(), coat, Vector3(0.0, -0.08, 0.32), Vector3(0.6, 0.62, 0.05), Vector3(0.25, 0.0, 0.0))
	for k in 4:
		Art.part(torso, Art.sphere(), gold, Vector3(0.0, 0.5 - 0.12 * float(k), -0.39 + 0.03 * absf(float(k) - 1.5)),
			Vector3.ONE * 0.045)
	EnemyModel.limb(torso, Vector3(-0.02, 0.36, -0.38), Vector3(0.2, 0.26, -0.33), 0.008, gold)
	Art.part(torso, Art.cylinder(0.5, 0.5), gold, Vector3(0.21, 0.25, -0.33), Vector3(0.07, 0.02, 0.07),
		Vector3(PI * 0.5, 0.0, 0.0))
	# Collar of gold chain.
	Art.part(torso, Art.torus(0.4, 0.46), gold, Vector3(0.0, 0.66, -0.04), Vector3(0.62, 0.6, 0.62), Vector3(0.3, 0.0, 0.0))

	_arm_r = arm(torso, Vector3(0.36, 0.6, 0.0), 0.3, 0.3, 0.075, 0.07, coat, skin, 0.0)
	_arm_l = arm(torso, Vector3(-0.36, 0.6, 0.0), 0.3, 0.3, 0.075, 0.07, coat, skin, 0.0)
	for a: Array[Node3D] in [_arm_r, _arm_l]:
		Art.part(a[1], Art.cylinder(0.5, 0.5), vest, Vector3(0.0, -0.27, 0.0), Vector3(0.16, 0.05, 0.16))  # cuff
		# Long counting fingers.
		Art.part(a[2], Art.sphere(), skin, Vector3(0.0, -0.04, 0.0), Vector3(0.09, 0.08, 0.06))
		for f in 3:
			EnemyModel.limb(a[2], Vector3((float(f) - 1.0) * 0.025, -0.06, 0.0),
				Vector3((float(f) - 1.0) * 0.035, -0.17, -0.02), 0.011, skin)
	# Coin stack in the left palm; the flicked coin rides the right hand.
	_stack = Art.pivot(_arm_l[2], Vector3(0.0, -0.1, -0.03))
	for k in COINS:
		Art.part(_stack, Art.cylinder(0.5, 0.5), coin_m, Vector3(0.0, 0.02 * float(k), 0.0), Vector3(0.1, 0.016, 0.1))
	_coin = Art.pivot(self)
	Art.part(_coin, Art.cylinder(0.5, 0.5), coin_m, Vector3.ZERO, Vector3(0.1, 0.016, 0.1))
	Art.light(_stack, SOUL, 0.7, 2.2, Vector3(0.0, 0.15, 0.0))

	# Head: broad, jowly, grinning; curled gilt-tipped horns; monocle; tall top hat with a soul gem.
	head = Art.pivot(torso, Vector3(0.0, 0.82, -0.04))
	Art.part(head, Art.sphere(), skin, Vector3.ZERO, Vector3(0.4, 0.34, 0.38))
	Art.part(head, Art.sphere(), skin, Vector3(0.0, -0.1, -0.06), Vector3(0.42, 0.18, 0.32))        # jowls
	Art.part(head, Art.box(), Art.mat(Color(0.05, 0.0, 0.0), 1.0), Vector3(0.0, -0.08, -0.2), Vector3(0.18, 0.02, 0.02))
	Art.part(head, Art.cone(0.5), skin, Vector3(0.0, -0.01, -0.21), Vector3(0.06, 0.1, 0.06), Vector3(-1.6, 0.0, 0.0))  # nose
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(SOUL, 3.0), Vector3(s * 0.08, 0.04, -0.17), Vector3(0.05, 0.03, 0.03))
		horn(head, Vector3(s * 0.15, 0.06, 0.0), [Vector3(s * 0.1, 0.06, 0.0), Vector3(s * 0.05, 0.08, 0.04)], 0.04, 0.018,
			gold)
	Art.part(head, Art.torus(0.4, 0.5), gold, Vector3(0.08, 0.04, -0.19), Vector3(0.1, 0.1, 0.1), Vector3(PI * 0.5, 0.0, 0.0))
	_monocle_glint = Art.part(head, Art.sphere(), Art.glow(Color.WHITE, 2.0), Vector3(0.1, 0.06, -0.2), Vector3.ONE * 0.02)
	EnemyModel.limb(head, Vector3(0.12, 0.0, -0.18), Vector3(0.18, -0.2, -0.12), 0.004, gold)
	_hat = Art.pivot(head, Vector3(0.0, 0.17, 0.0))
	Art.part(_hat, Art.cylinder(0.5, 0.5), black, Vector3(0.0, 0.0, 0.0), Vector3(0.5, 0.025, 0.46))
	Art.part(_hat, Art.cylinder(0.5, 0.5), black, Vector3(0.0, 0.2, 0.0), Vector3(0.3, 0.4, 0.3))
	Art.part(_hat, Art.cylinder(0.5, 0.5), gold, Vector3(0.0, 0.06, 0.0), Vector3(0.31, 0.06, 0.31))
	Art.part(_hat, Art.sphere(), Art.glow(SOUL, 2.5), Vector3(0.0, 0.07, -0.155), Vector3(0.06, 0.07, 0.03))


func pose(_delta: float) -> void:
	var g := greet_w
	var j := joy_w
	var k := fmod(t, FLIP) / FLIP
	var n := int(t / FLIP)
	var inspect := (n % 4) == 3  # every fourth coin: hold it to the monocle
	# Left palm holds the stack before the belly.
	set_arm(_arm_l, Vector3(0.9, 0.0, 0.25).lerp(Vector3(0.5, 0.0, 0.15), g), lerpf(1.35, 1.0, g),
		Vector3(0.0, 0.0, 0.0))
	# Right hand: pick (0-0.2), flick (0.2-0.3) -> coin in the air (0.3-0.7) -> catch -> place (0.8-1).
	var r_sh := Vector3(1.0, 0.0, -0.35)
	var r_el := 1.2
	var coin_air := 0.0
	if inspect:
		var lift := ss(0.1, 0.35, k) * (1.0 - ss(0.75, 0.95, k))
		r_sh = r_sh.lerp(Vector3(2.0, 0.0, -0.1), lift)
		r_el = lerpf(r_el, 1.9, lift)
	else:
		var flick := ss(0.18, 0.28, k) * (1.0 - ss(0.62, 0.72, k))
		r_sh = r_sh.lerp(Vector3(0.85, 0.0, -0.4), flick)
		r_el = lerpf(r_el, 0.9, flick)
		if k > 0.28 and k < 0.68:
			coin_air = (k - 0.28) / 0.4
	if _last_k < 0.68 and k >= 0.68 and not inspect and near:
		Sfx.play_at(&"gold", global_position, 0.2, -22.0)
	_last_k = k
	# Greeting: a little bow, right hand doffs the hat. Sale: rubs its hands.
	r_sh = r_sh.lerp(Vector3(2.6, 0.0, -0.25), g)
	r_el = lerpf(r_el, 1.6, g)
	var rub := sin(t * 18.0) * 0.12 * j
	r_sh = r_sh.lerp(Vector3(1.05, 0.0, 0.45 + rub), j)
	set_arm(_arm_r, r_sh, lerpf(r_el, 1.4, j))
	_hat.position = Vector3(0.0, 0.17 + 0.12 * g, -0.05 * g)
	_hat.rotation = Vector3(-0.4 * g, 0.0, 0.0)
	torso.rotation = Vector3(-0.35 * g + 0.04 * sin(t * 1.4), 0.0, 0.0)
	# Head watches the coin (up when it flies), leans to the monocle while inspecting.
	var lean_in := 0.0
	if inspect:
		lean_in = ss(0.25, 0.45, k) * (1.0 - ss(0.7, 0.9, k))
	head.rotation = Vector3(-0.25 + 0.5 * sin(coin_air * PI) - 0.1 * lean_in + 0.2 * g, 0.0, 0.18 * lean_in)
	_monocle_glint.visible = lean_in > 0.5 or fmod(t, 3.0) < 0.15
	# The flicked coin: rides the right hand, flies up spinning, lands back on the stack.
	var hand := _arm_r[2].global_position + _arm_r[2].global_basis.y * -0.15
	if coin_air > 0.0:
		var top := hand + Vector3(0.0, 0.55 * sin(coin_air * PI) * global_basis.y.length(), 0.0)
		_coin.global_position = top
		_coin.rotation = Vector3(coin_air * TAU * 3.0, 0.0, 0.3)
	else:
		_coin.global_position = hand
		_coin.rotation = Vector3(0.0, 0.0, 0.4)
	_coin.visible = not inspect or k < 0.95
