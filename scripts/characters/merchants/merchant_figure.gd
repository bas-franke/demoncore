class_name MerchantFigure
extends Node3D
## Base for the Basecamp merchants' figures (characters-polish round 3): articulated, code-built
## (Art kit) demons with a craft-specific idle loop. HubShopkeeper owns the figure: it turns the
## whole body to watch the player, breathes it and calls animate() / greet() / react().
##
##   var fig := MerchantFigure.create(HubShopkeeper.Look.BLACKSMITH)   # null if unknown
##   body.add_child(fig)
##   fig.animate(delta, player_near)     # every frame
##   fig.greet()                         # the shop opened: pause the work, acknowledge
##   fig.react()                         # a sale: a pleased flourish
##
## Rig convention: forward is -Z, feet at y = 0. Limbs hang along -Y from their pivots; a
## shoulder's +X rotation swings the arm forward / up, an elbow's +X bends the forearm forward.

const LOOK_SCRIPTS := [
	"res://scripts/characters/merchants/grimmaul_figure.gd",
	"res://scripts/characters/merchants/vesper_figure.gd",
	"res://scripts/characters/merchants/clerk_figure.gd",
	"res://scripts/characters/merchants/ossek_figure.gd",
]

## Seconds since the figure was built (drives the idle loops).
var t := 0.0
## 1 -> 0 while greeting (the work pauses), 1 -> 0 after a sale.
var greet_w := 0.0
var joy_w := 0.0
## True while the player is near (figures may glance up from their work).
var near := false

var head: Node3D
var torso: Node3D
var _greet_t := 0.0
var _joy_t := 0.0


## The figure for a HubShopkeeper.Look (0 blacksmith, 1 occultist, 2 soul broker, 3 cartographer).
static func create(look: int) -> MerchantFigure:
	if look < 0 or look >= LOOK_SCRIPTS.size() or OS.get_cmdline_user_args().has("--old-merchants"):
		return null  # dev: --old-merchants compares with the hub's original primitive figures
	var script := load(LOOK_SCRIPTS[look]) as GDScript
	if script == null:
		return null
	var fig := script.new() as MerchantFigure
	fig.name = "Figure"
	fig.build()
	return fig


## Override: build the geometry.
func build() -> void:
	pass


## Override: pose the rig from `t`, greet_w, joy_w, near.
func pose(_delta: float) -> void:
	pass


func animate(delta: float, player_near: bool) -> void:
	t += delta
	near = player_near
	_greet_t = maxf(_greet_t - delta, 0.0)
	_joy_t = maxf(_joy_t - delta, 0.0)
	greet_w = EnemyModel.damp(greet_w, 1.0 if _greet_t > 0.0 else 0.0, 6.0, delta)
	joy_w = _bump(_joy_t, 1.1)
	pose(delta)


func greet() -> void:
	_greet_t = 1.6


func react() -> void:
	_joy_t = 1.1


# ---------------------------------------------------------------- rig helpers

## An arm: [shoulder, elbow, hand] pivots. `upper` / `fore` lengths, radii r1 / r2, the sleeve
## material for the arm, `hand_m` for the hand (a fist-ish sphere unless `hand_size` is 0).
func arm(parent: Node3D, shoulder: Vector3, upper: float, fore: float, r1: float, r2: float,
		sleeve_m: Material, hand_m: Material, hand_size: float = 0.1) -> Array[Node3D]:
	var sh := Art.pivot(parent, shoulder)
	EnemyModel.limb(sh, Vector3.ZERO, Vector3(0.0, -upper, 0.0), r1, sleeve_m)
	Art.part(sh, Art.sphere(), sleeve_m, Vector3.ZERO, Vector3.ONE * r1 * 2.3)
	var el := Art.pivot(sh, Vector3(0.0, -upper, 0.0))
	Art.part(el, Art.sphere(), sleeve_m, Vector3.ZERO, Vector3.ONE * r2 * 2.1)
	EnemyModel.limb(el, Vector3.ZERO, Vector3(0.0, -fore, 0.0), r2, sleeve_m)
	var hd := Art.pivot(el, Vector3(0.0, -fore, 0.0))
	if hand_size > 0.0:
		Art.part(hd, Art.sphere(), hand_m, Vector3(0.0, -hand_size * 0.5, 0.0),
			Vector3(hand_size * 1.1, hand_size * 1.3, hand_size * 0.8))
	var out: Array[Node3D] = [sh, el, hd]
	return out


## Poses an arm: shoulder Euler (x forward/up, y twist, z out to the side), elbow bend (x),
## optional hand rotation.
static func set_arm(a: Array[Node3D], shoulder: Vector3, elbow: float, hand := Vector3.ZERO) -> void:
	a[0].rotation = shoulder
	a[1].rotation = Vector3(elbow, 0.0, 0.0)
	a[2].rotation = hand


## Curved horn from `base` along `dirs` (segment offsets), tapering from r0 to r1.
static func horn(parent: Node3D, base: Vector3, dirs: Array, r0: float, r1: float, m: Material) -> void:
	var p := base
	for i in dirs.size():
		var q: Vector3 = p + (dirs[i] as Vector3)
		var r := lerpf(r0, r1, float(i) / float(maxi(dirs.size() - 1, 1)))
		EnemyModel.limb(parent, p, q, r, m)
		Art.part(parent, Art.sphere(), m, q, Vector3.ONE * r * 2.0)
		p = q
	Art.part(parent, Art.cone(0.5), m, p + (dirs[-1] as Vector3).normalized() * r1 * 2.0,
		Vector3(r1 * 2.0, r1 * 5.0, r1 * 2.0), _aim((dirs[-1] as Vector3).normalized()))


## Euler rotation that turns +Y toward `dir`.
static func _aim(dir: Vector3) -> Vector3:
	var b := Basis.IDENTITY
	var axis := Vector3.UP.cross(dir)
	if axis.length_squared() > 0.000001:
		b = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	elif dir.y < 0.0:
		b = Basis(Vector3.RIGHT, PI)
	return b.get_euler()


## 0 -> 1 -> 0 bump while a countdown `left` runs out of `length`.
static func _bump(left: float, length: float) -> float:
	if left <= 0.0:
		return 0.0
	var k := 1.0 - left / length
	return sin(clampf(k, 0.0, 1.0) * PI)


## Smoothstep from a to b.
static func ss(a: float, b: float, x: float) -> float:
	var u := clampf((x - a) / (b - a), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## One-shot burst of sparks at `parent` (local position `pos`).
func sparks(parent: Node3D, pos: Vector3, color: Color, amount: int, speed: float = 2.5) -> void:
	var p := InfernalFx.make_particles(color, amount, 0.45, 3.0)
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.spread = 70.0
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -7.0, 0.0)
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
