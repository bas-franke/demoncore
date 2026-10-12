extends MerchantFigure
## Vesper, the Unsung (occultist): a fallen angel of the Hollow Choir. Tall and gaunt in layered
## violet-black robes with a tattered hem, a deep hood over a faceless void with two violet eyes,
## a cracked halo dimmed to violet, and torn black wings drooping to the floor. Idle: reads the
## floating grimoire and turns its pages (the page sweeps over the spine, the hand following it),
## violet wisps circling; greets by lifting its gaze and opening a hand; a sale makes the book
## flare and the wisps race.

const READ := 3.4
const TURN := 0.9
const VIOLET := Color(0.72, 0.3, 1.0)

var _arm_r: Array[Node3D] = []
var _arm_l: Array[Node3D] = []
var _book: Node3D
var _page: Node3D
var _halo: Node3D  # spins inside a fixed tilt pivot
var _wisps: Node3D
var _wings: Array[Node3D] = []
var _book_m: StandardMaterial3D
var _flip := 0


func build() -> void:
	var robe := Art.mat(Color(0.09, 0.05, 0.12), 0.92, 0.0, 0.35, true, 0.25, &"cloth")
	var robe_hi := Art.mat(Color(0.16, 0.09, 0.2), 0.88, 0.0, 0.3, true, 0.25, &"cloth")
	var void_m := Art.mat(Color(0.008, 0.004, 0.012), 1.0, 0.0, 0.0)
	var feather := Art.mat(Color(0.06, 0.05, 0.07), 0.8, 0.0, 0.2, true, 0.3, &"feather")
	var skin := Art.mat(Color(0.32, 0.27, 0.36), 0.6, 0.0, 0.2, true, 0.2, &"skin")
	var eye := Art.glow(VIOLET, 3.5)

	# Long robe: a narrow cone to the floor, tattered strips at the hem.
	Art.part(self, Art.cylinder(0.2, 0.46), robe, Vector3(0.0, 0.62, 0.0), Vector3(1.0, 1.24, 1.0))
	for k in 12:
		var a := TAU * float(k) / 12.0 + 0.13
		var ln := 0.22 + 0.12 * float((k * 7) % 3)
		Art.part(self, Art.box(), robe if k % 2 == 0 else robe_hi, Vector3(cos(a) * 0.43, 0.04 + ln * 0.1, sin(a) * 0.43),
			Vector3(0.12, ln, 0.02), Vector3(0.18 * sin(a), -a + PI * 0.5, 0.18 * cos(a)))
	torso = Art.pivot(self, Vector3(0.0, 1.2, 0.0))
	Art.part(torso, Art.sphere(), robe, Vector3(0.0, 0.22, 0.0), Vector3(0.5, 0.62, 0.36))
	# Mantle over the shoulders and a high collar.
	Art.part(torso, Art.sphere(), robe_hi, Vector3(0.0, 0.42, 0.0), Vector3(0.78, 0.3, 0.5))
	Art.part(torso, Art.cylinder(0.24, 0.16), robe_hi, Vector3(0.0, 0.58, 0.04), Vector3(1.0, 0.24, 1.0))
	Art.part(torso, Art.box(), Art.glow(VIOLET, 1.4), Vector3(0.0, 0.25, -0.19), Vector3(0.025, 0.42, 0.01))

	# Torn wings drooping from the back to the floor.
	for s: float in [-1.0, 1.0]:
		var w := Art.pivot(torso, Vector3(s * 0.16, 0.42, 0.18), Vector3(0.35, s * 0.35, s * 0.55))
		_wings.append(w)
		EnemyModel.limb(w, Vector3.ZERO, Vector3(s * 0.25, -0.15, 0.1), 0.035, feather)
		EnemyModel.limb(w, Vector3(s * 0.25, -0.15, 0.1), Vector3(s * 0.35, -0.95, 0.15), 0.03, feather)
		for i in 7:
			var f := float(i) / 6.0
			var root := Vector3(s * (0.1 + 0.25 * f), -0.1 - 0.75 * f, 0.1)
			var length := 0.55 + 0.35 * sin(f * PI) - (0.25 if i == 3 else 0.0)  # one torn short
			Art.part(w, Art.sphere(), feather, root + Vector3(s * 0.05, -length * 0.45, 0.05),
				Vector3(0.12, length, 0.03), Vector3(0.0, 0.0, s * (0.15 - 0.3 * f)))

	# Arms: long sleeves, pale gaunt hands.
	_arm_r = arm(torso, Vector3(0.3, 0.42, 0.0), 0.36, 0.34, 0.07, 0.075, robe, skin, 0.08)
	_arm_l = arm(torso, Vector3(-0.3, 0.42, 0.0), 0.36, 0.34, 0.07, 0.075, robe, skin, 0.08)
	for a: Array[Node3D] in [_arm_r, _arm_l]:
		Art.part(a[1], Art.cylinder(0.08, 0.17), robe_hi, Vector3(0.0, -0.28, 0.0), Vector3(1.0, 0.16, 1.0))  # bell cuff

	# Hood: deep, pointed, a void with two eyes.
	head = Art.pivot(torso, Vector3(0.0, 0.74, -0.02))
	Art.part(head, Art.sphere(), robe_hi, Vector3(0.0, 0.03, 0.04), Vector3(0.4, 0.46, 0.44))
	Art.part(head, Art.cone(0.5), robe_hi, Vector3(0.0, 0.3, 0.13), Vector3(0.28, 0.38, 0.28), Vector3(0.65, 0.0, 0.0))
	Art.part(head, Art.sphere(), void_m, Vector3(0.0, -0.01, -0.12), Vector3(0.26, 0.32, 0.14))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), eye, Vector3(s * 0.06, 0.02, -0.19), Vector3(0.045, 0.026, 0.02))
	# Cracked halo: a ring of shards with gaps, tilted behind the hood.
	var tilt := Art.pivot(head, Vector3(0.0, 0.32, 0.2), Vector3(0.5, 0.0, 0.0))
	_halo = Art.pivot(tilt)
	var halo_m := Art.glow(VIOLET.lerp(Color.WHITE, 0.25), 1.6)
	for k in 9:
		if k == 2 or k == 6:
			continue  # broken out
		var a := TAU * float(k) / 9.0
		Art.part(_halo, Art.box(), halo_m, Vector3(cos(a) * 0.27, 0.0, sin(a) * 0.27), Vector3(0.15, 0.02, 0.03),
			Vector3(0.0, -a + PI * 0.5, 0.0))

	# The grimoire floats before it: covers, page block, a turning page, glowing script.
	_book = Art.pivot(self, Vector3(0.0, 1.38, -0.55), Vector3(-0.55, 0.0, 0.0))
	var cover := Art.mat(Color(0.22, 0.04, 0.07), 0.7, 0.0, 0.4, true, 0.0, &"leather")
	var paper := Art.mat(Art.IVORY.darkened(0.1), 0.9, 0.0, 0.3, true, 0.0, &"parchment")
	for s: float in [-1.0, 1.0]:
		Art.part(_book, Art.box(), cover, Vector3(s * 0.17, 0.0, 0.0), Vector3(0.34, 0.02, 0.44), Vector3(0.0, 0.0, -s * 0.08))
		Art.part(_book, Art.box(), paper, Vector3(s * 0.16, 0.03, 0.0), Vector3(0.3, 0.035, 0.4), Vector3(0.0, 0.0, -s * 0.08))
	_book_m = StandardMaterial3D.new()
	_book_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_book_m.albedo_color = _bright(VIOLET, 1.6)
	_book_m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for s: float in [-1.0, 1.0]:
		for line in 4:
			Art.part(_book, Art.box(), _book_m, Vector3(s * 0.16, 0.05, -0.12 + 0.08 * line), Vector3(0.2, 0.003, 0.012))
	_page = Art.pivot(_book, Vector3(0.0, 0.05, 0.0))
	Art.part(_page, Art.box(), paper, Vector3(0.15, 0.0, 0.0), Vector3(0.3, 0.008, 0.39))
	Art.light(_book, VIOLET, 1.2, 4.0, Vector3(0.0, 0.25, 0.0))

	# Wisps circling.
	_wisps = Art.pivot(self, Vector3(0.0, 1.5, 0.0))
	for k in 3:
		var a := TAU * float(k) / 3.0
		Art.part(_wisps, Art.sphere(), Art.glow(VIOLET, 3.0), Vector3(cos(a) * 0.85, 0.15 * float(k), sin(a) * 0.85),
			Vector3.ONE * 0.09)


func pose(delta: float) -> void:
	var cycle := READ + TURN
	var c := fmod(t, cycle)
	var turn := 0.0
	if c >= READ:
		turn = (c - READ) / TURN
	var flip := int(t / cycle)
	if flip != _flip:
		_flip = flip
		if near:
			Sfx.play_at(&"whoosh", _book.global_position, 0.15, -22.0)
	var g := greet_w
	var j := joy_w
	# The page sweeps from the right over the spine to the left, lifting in an arc.
	var e := ss(0.0, 1.0, turn)
	_page.rotation = Vector3(0.0, 0.0, e * PI) if turn > 0.0 else Vector3.ZERO
	# Book bobs and tilts a little; flares on a sale.
	_book.position.y = 1.38 + sin(t * 1.3) * 0.03
	_book_m.albedo_color = _bright(VIOLET, 1.4 + 0.3 * sin(t * 3.0) + 3.0 * j)
	# Right hand turns the page (reaches over to the right edge, sweeps left); left palm under it.
	var reach := ss(0.0, 0.2, turn) * (1.0 - ss(0.85, 1.0, turn))
	var sweep := e
	var r_sh := Vector3(1.0 + 0.25 * reach, 0.0, lerpf(-0.05, 0.35, sweep * reach))
	var r_el := lerpf(0.9, 1.25, reach)
	r_sh = r_sh.lerp(Vector3(1.3, 0.0, -0.35), g)
	set_arm(_arm_r, r_sh, lerpf(r_el, 0.4, g), Vector3(0.0, 0.0, 0.0))
	set_arm(_arm_l, Vector3(0.95, 0.0, 0.18).lerp(Vector3(0.7, 0.0, 0.1), g), lerpf(1.05, 0.9, g))
	# Head reads along the lines (a slow sweep), lifts to the customer when greeted.
	var read_sweep := sin(fmod(c, READ) / READ * TAU * 2.0) * 0.12 * (1.0 - turn)
	head.rotation = Vector3(-0.5 * (1.0 - g) + 0.1 * g, read_sweep * (1.0 - g) + 0.35 * turn * (1.0 - g), 0.06 * sin(t * 0.6))
	torso.rotation = Vector3(-0.1 * (1.0 - g), 0.0, 0.03 * sin(t * 0.8))
	# Halo turns slowly; wisps orbit (racing on a sale); wings stir.
	_halo.rotation.y += delta * 0.3
	_wisps.rotation.y += delta * (0.7 + 4.0 * j)
	for i in _wings.size():
		var s := -1.0 if i == 0 else 1.0
		_wings[i].rotation = Vector3(0.35 + 0.05 * sin(t * 1.1), s * 0.35, s * (0.55 + 0.06 * sin(t * 0.9 + s) + 0.4 * j))


static func _bright(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)
