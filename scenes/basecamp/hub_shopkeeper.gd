class_name HubShopkeeper
extends HubInteractable
## A Basecamp Hell shopkeeper: a procedurally built demon merchant that breathes, sways, turns to
## watch the player when they come near, and opens its shop on interact (the hub listens to
## `interacted`). `shop_id` matches a key of "shops" in res://data/meta/upgrades.json; `look`
## picks the silhouette and hand props.

enum Look { BLACKSMITH, OCCULTIST, SOUL_BROKER, CARTOGRAPHER }

@export var shop_id := "blacksmith"
@export var look: Look = Look.BLACKSMITH
## Ground yaw the merchant faces when nobody is near (radians; 0 = facing -Z).
@export var rest_yaw := 0.0
## Distance at which it turns to watch the player.
@export var watch_range := 7.0
## Overall scale of the figure (merchants loom a little over the player).
@export var figure_scale := 1.25

var _body: Node3D
var _head: Node3D
var _float: Node3D  # props that hover / orbit (occultist book, soul broker coins)
var _yaw := 0.0
var _bounce := 0.0
var _phase := randf() * TAU
## characters-polish: articulated figure with a craft idle (scripts/characters/merchants/*).
var _fig: MerchantFigure


func _ready() -> void:
	verb = "Trade"
	super._ready()
	_yaw = rest_yaw
	_body = Art.pivot(self)
	_body.rotation.y = _yaw
	_fig = MerchantFigure.create(look)  # characters-polish (falls back to the primitives below)
	if _fig:
		_body.add_child(_fig)
	match look if _fig == null else -1:
		Look.BLACKSMITH:
			_build_blacksmith()
		Look.OCCULTIST:
			_build_occultist()
		Look.SOUL_BROKER:
			_build_broker()
		Look.CARTOGRAPHER:
			_build_cartographer()
	# Ember rim like every demon (art-style round 3; docs/team/art-style.md).
	ArtStyle.apply_faction(_body, ArtStyle.Faction.DEMON)
	# Solid so the avatar can't walk through the merchant.
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.55
	cyl.height = 2.0
	cs.shape = cyl
	cs.position.y = 1.0
	sb.add_child(cs)
	add_child(sb)


func _process(delta: float) -> void:
	super._process(delta)  # also advances _t
	var avatar := get_tree().get_first_node_in_group(&"hub_avatar") as Node3D
	var want := rest_yaw
	if avatar and flat_distance(avatar.global_position) < watch_range:
		var d := avatar.global_position - global_position
		want = atan2(-d.x, -d.z)
	_yaw = lerp_angle(_yaw, want, 1.0 - exp(-3.0 * delta))
	_body.rotation.y = _yaw
	# Breathing + idle sway; a quick hop after a sale or greeting.
	_bounce = maxf(0.0, _bounce - delta * 3.0)
	var breath := sin(_t * 1.6 + _phase)
	_body.scale = Vector3(1.0 - breath * 0.012, 1.0 + breath * 0.02, 1.0 - breath * 0.012) * figure_scale
	_body.position.y = sin(_bounce * PI) * 0.18
	if look == Look.OCCULTIST:
		_body.position.y += 0.18 + sin(_t * 1.1 + _phase) * 0.08  # it never quite touches the floor
	if _head:
		_head.rotation.z = sin(_t * 0.7 + _phase) * 0.06
		_head.rotation.x = sin(_t * 0.5 + _phase * 2.0) * 0.05
	if _float:
		_float.rotation.y += delta * 0.8
		_float.position.y = sin(_t * 1.3) * 0.08
	if _fig:  # characters-polish
		_fig.animate(delta, avatar != null and flat_distance(avatar.global_position) < watch_range)


func interact() -> void:
	_bounce = 1.0
	if _fig:  # characters-polish
		_fig.greet()
	super.interact()


## A little hop (call after a purchase).
func react() -> void:
	_bounce = 1.0
	if _fig:  # characters-polish
		_fig.react()


# ---------------------------------------------------------------- figures

## Shared robed demon body. Returns the head pivot. Forward is -Z.
func _figure(height: float, girth: float, robe: Color, skin: Color, eyes: Color,
		horns: bool, horn_color := Art.BONE) -> Node3D:
	var robe_m := Art.mat(robe, 0.9, 0.0, 0.4, true, 0.0, &"cloth")
	var skin_m := Art.mat(skin, 0.7, 0.0, 0.3, true, 0.1, &"skin")
	# Robe skirt and chest.
	Art.part(_body, Art.cylinder(0.3 * girth, 0.52 * girth), robe_m, Vector3(0.0, height * 0.3, 0.0),
			Vector3(1.0, height * 0.6, 1.0))
	Art.part(_body, Art.sphere(), robe_m, Vector3(0.0, height * 0.64, 0.0),
			Vector3(0.78 * girth, height * 0.34, 0.55 * girth))
	# Shoulders and arms.
	for s: float in [-1.0, 1.0]:
		Art.part(_body, Art.sphere(), robe_m, Vector3(s * 0.36 * girth, height * 0.74, 0.0),
				Vector3(0.34, 0.3, 0.34) * girth)
		Art.part(_body, Art.capsule(0.09 * girth, height * 0.38), robe_m,
				Vector3(s * 0.44 * girth, height * 0.56, -0.04), Vector3.ONE, Vector3(0.15, 0.0, s * 0.12))
		Art.part(_body, Art.sphere(), skin_m, Vector3(s * 0.47 * girth, height * 0.38, -0.08),
				Vector3(0.14, 0.16, 0.14) * girth)
	# Head.
	var head := Art.pivot(_body, Vector3(0.0, height * 0.86, 0.0))
	Art.part(head, Art.sphere(), skin_m, Vector3.ZERO, Vector3(0.32, 0.36, 0.32))
	Art.part(head, Art.sphere(), skin_m, Vector3(0.0, -0.1, -0.08), Vector3(0.2, 0.16, 0.18))  # jaw
	var eye_m := Art.glow(eyes, 3.0)
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), eye_m, Vector3(s * 0.075, 0.03, -0.145), Vector3(0.055, 0.035, 0.03))
	if horns:
		var horn_m := Art.mat(horn_color, 0.6, 0.0, 0.4, true, 0.0, &"bone")
		for s: float in [-1.0, 1.0]:
			Art.part(head, Art.cone(0.5), horn_m, Vector3(s * 0.13, 0.2, 0.02), Vector3(0.09, 0.32, 0.09),
					Vector3(-0.35, 0.0, -s * 0.55))
	_head = head
	return head


func _build_blacksmith() -> void:
	var g := 1.35
	var h := 2.0
	_figure(h, g, Color(0.16, 0.1, 0.07), Color(0.42, 0.12, 0.08), Art.EMBER, true)
	# Leather apron and a soot-black iron belt.
	var leather := Art.mat(Art.LEATHER, 0.85, 0.0, 0.5, true, 0.0, &"leather")
	Art.part(_body, Art.box(), leather, Vector3(0.0, h * 0.42, -0.36), Vector3(0.62, h * 0.6, 0.06), Vector3(-0.12, 0.0, 0.0))
	Art.part(_body, Art.cylinder(0.43 * g, 0.43 * g), Art.mat(Art.OBSIDIAN, 0.4, 0.9, 0.3, true, 0.0, &"metal"),
			Vector3(0.0, h * 0.52, 0.0), Vector3(1.0, 0.08, 1.0))
	# Great hammer in the right hand, resting head-down.
	var steel := Art.mat(Art.STEEL.darkened(0.3), 0.35, 0.9, 0.4, true, 0.0, &"metal")
	var hammer := Art.pivot(_body, Vector3(0.68, h * 0.4, -0.1), Vector3(0.0, 0.0, -0.25))
	Art.part(hammer, Art.cylinder(0.04, 0.04), Art.mat(Art.LEATHER.darkened(0.3), 0.8, 0.0, 0.4, true, 0.0, &"wood"),
			Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.1, 1.0))
	Art.part(hammer, Art.box(), steel, Vector3(0.0, -0.55, 0.0), Vector3(0.42, 0.24, 0.24))
	Art.part(hammer, Art.box(), Art.glow(Art.HELLFIRE, 1.6), Vector3(0.0, -0.55, 0.0), Vector3(0.44, 0.05, 0.26))


func _build_occultist() -> void:
	var h := 2.25
	var g := 0.95
	var robe := Color(0.1, 0.05, 0.13)
	var head := _figure(h, g, robe, Color(0.25, 0.2, 0.3), Color(0.75, 0.3, 1.0), false)
	# Deep pointed hood that swallows the face (only the eyes show).
	var hood_m := Art.mat(robe.darkened(0.2), 0.95, 0.0, 0.4, true, 0.0, &"cloth")
	Art.part(head, Art.sphere(), hood_m, Vector3(0.0, 0.04, 0.05), Vector3(0.42, 0.46, 0.44))
	Art.part(head, Art.cone(0.5), hood_m, Vector3(0.0, 0.33, 0.12), Vector3(0.3, 0.4, 0.3), Vector3(0.5, 0.0, 0.0))
	Art.part(head, Art.sphere(), Art.mat(Color(0.01, 0.0, 0.01), 1.0, 0.0, 0.0), Vector3(0.0, 0.0, -0.13),
			Vector3(0.26, 0.3, 0.12))
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(Color(0.75, 0.3, 1.0), 3.5), Vector3(s * 0.065, 0.02, -0.19),
				Vector3(0.05, 0.03, 0.03))
	# Grimoire and three violet wisps orbiting at chest height.
	_float = Art.pivot(_body, Vector3.ZERO)
	var book := Art.pivot(_float, Vector3(0.0, h * 0.62, -0.75), Vector3(-0.7, 0.0, 0.0))
	Art.part(book, Art.box(), Art.mat(Color(0.25, 0.04, 0.06), 0.7, 0.0, 0.4, true, 0.0, &"leather"),
			Vector3.ZERO, Vector3(0.46, 0.08, 0.34))
	Art.part(book, Art.box(), Art.mat(Art.IVORY, 0.9, 0.0, 0.3, true, 0.0, &"parchment"),
			Vector3(0.0, 0.05, 0.0), Vector3(0.42, 0.03, 0.3))
	Art.part(book, Art.box(), Art.glow(Color(0.7, 0.3, 1.0), 2.0), Vector3(0.0, 0.07, 0.0), Vector3(0.3, 0.005, 0.2))
	for k in 3:
		var a := TAU * k / 3.0
		Art.part(_float, Art.sphere(), Art.glow(Color(0.65, 0.25, 1.0), 3.0),
				Vector3(cos(a) * 0.9, h * 0.8, sin(a) * 0.9), Vector3.ONE * 0.12)
	Art.light(_float, Color(0.6, 0.25, 1.0), 1.4, 4.5, Vector3(0.0, h * 0.7, -0.5))


func _build_broker() -> void:
	var h := 1.7
	var g := 1.15
	var head := _figure(h, g, Color(0.22, 0.05, 0.06), Color(0.3, 0.25, 0.18), Color(0.4, 1.0, 0.8), true, Art.GOLD)
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.3, true, 0.0, &"gold")
	# Gold collar chain, a tall crown between the horns, a glinting monocle.
	Art.part(_body, Art.torus(0.36, 0.42), gold, Vector3(0.0, h * 0.74, -0.05), Vector3(1.0, 1.0, 1.0) * g,
			Vector3(0.35, 0.0, 0.0))
	for k in 5:
		var a := -0.8 + 0.4 * k
		Art.part(head, Art.cone(0.5), gold, Vector3(sin(a) * 0.14, 0.24, cos(a) * 0.14 * -1.0 + 0.04),
				Vector3(0.05, 0.16 + (0.06 if k == 2 else 0.0), 0.05))
	Art.part(head, Art.torus(0.4, 0.5), gold, Vector3(0.075, 0.03, -0.16), Vector3(0.09, 0.09, 0.09),
			Vector3(PI * 0.5, 0.0, 0.0))
	# Floating soul coins circling its hand.
	_float = Art.pivot(_body, Vector3(0.5, 0.0, -0.2))
	for k in 4:
		var a := TAU * k / 4.0
		Art.part(_float, Art.cylinder(0.5, 0.5), Art.glow(UIPalette.SOUL, 2.2), Vector3(cos(a) * 0.3, h * 0.55, sin(a) * 0.3),
				Vector3(0.12, 0.02, 0.12), Vector3(0.6, 0.0, 0.4))


func _build_cartographer() -> void:
	var h := 1.95
	var g := 1.0
	var head := _figure(h, g, Color(0.12, 0.13, 0.12), Color(0.35, 0.28, 0.22), Color(0.35, 0.95, 0.9), true)
	# Wide-brimmed traveller's hat, a long staff with a soul lantern and a scroll satchel.
	var hat := Art.mat(Art.LEATHER.darkened(0.2), 0.85, 0.0, 0.5, true, 0.0, &"leather")
	Art.part(head, Art.cylinder(0.5, 0.5), hat, Vector3(0.0, 0.17, 0.0), Vector3(0.75, 0.03, 0.75))
	Art.part(head, Art.cylinder(0.32, 0.4), hat, Vector3(0.0, 0.28, 0.0), Vector3(0.5, 0.22, 0.5))
	var staff := Art.pivot(_body, Vector3(-0.55, 0.0, -0.15))
	Art.part(staff, Art.cylinder(0.035, 0.045), Art.mat(Color(0.25, 0.18, 0.12), 0.85, 0.0, 0.4, true, 0.0, &"wood"),
			Vector3(0.0, h * 0.58, 0.0), Vector3(1.0, h * 1.16, 1.0))
	Art.part(staff, Art.box(), Art.mat(Art.OBSIDIAN, 0.4, 0.8), Vector3(0.0, h * 1.12, 0.0), Vector3(0.14, 0.2, 0.14))
	Art.part(staff, Art.sphere(), Art.glow(Color(0.35, 0.95, 0.9), 2.5), Vector3(0.0, h * 1.12, 0.0), Vector3.ONE * 0.11)
	Art.light(staff, Color(0.35, 0.95, 0.9), 1.0, 4.0, Vector3(0.0, h * 1.12, 0.0))
	var satchel := Art.pivot(_body, Vector3(0.42, h * 0.45, 0.15))
	Art.part(satchel, Art.box(), Art.mat(Art.LEATHER, 0.85, 0.0, 0.5, true, 0.0, &"leather"), Vector3.ZERO,
			Vector3(0.2, 0.32, 0.3))
	for k in 3:
		Art.part(satchel, Art.cylinder(0.5, 0.5), Art.mat(Art.IVORY.darkened(0.15), 0.9, 0.0, 0.3, true, 0.0, &"parchment"),
				Vector3(0.0, 0.2, -0.08 + k * 0.08), Vector3(0.07, 0.4, 0.07), Vector3(0.0, 0.0, 0.3))
