extends Node3D
## Dev-only: lays out every Blender weapon model under game-like light for a screenshot.
##   godot --path . res://scenes/weapons/_showcase.tscn -- --shot=<abs png> --shot-time=3 [--far]

var _spin: Node3D
var _t := 0.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.45)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.541, -2.142, 0.0)
	sun.light_color = Color(1, 0.83, 0.62)
	sun.light_energy = 2.3
	sun.shadow_enabled = true
	add_child(sun)
	Art.part(self, Art.box(), Art.mat(Art.STONE.darkened(0.5), 0.9, 0.0, 0.4, false), Vector3(0, -0.05, 0), Vector3(40, 0.1, 40))
	var cam := Camera3D.new()
	cam.fov = 35.0
	var far := "--far" in OS.get_cmdline_user_args()
	var k := 1.0 if far else 0.42
	cam.transform = Transform3D(Basis(Vector3.RIGHT, -0.959931), Vector3(0, 21.7 * k, 14.91 * k + 0.5))
	add_child(cam)
	cam.current = true

	_spin = Node3D.new()
	_spin.position = Vector3(-3.2, 0.8, -1.2)
	add_child(_spin)
	WeaponArt.build(WeaponArt.SCYTHE, _spin)
	var skull := Node3D.new()
	skull.position = Vector3(-0.8, 0.8, -1.2)
	add_child(skull)
	WeaponArt.build(WeaponArt.HELLFIRE_CORE, skull).scale = Vector3.ONE * 1.15
	skull.basis = Basis.looking_at(Vector3(1, 0, 0.3), Vector3.UP)
	var bolt := (load("res://scenes/weapons/hellfire_bolt/hellfire_projectile.tscn") as PackedScene).instantiate() as Projectile
	bolt.velocity = Vector3(0.001, 0.0, 0.0)
	bolt.lifetime = 1000.0
	bolt.position = Vector3(0.6, 0.8, -1.2)
	add_child(bolt)
	var sword := Node3D.new()
	sword.position = Vector3(1.6, 0.7, -0.2)
	sword.rotation = Vector3(0, -1.2, 0.35)
	add_child(sword)
	WeaponArt.build(WeaponArt.SWORD, sword).scale = Vector3.ONE * 2.6 * 0.92 / 1.06
	for i in 8:
		var l := WeaponArt.build(WeaponArt.CHAIN_LINK, self)
		l.basis = Basis.looking_at(Vector3.RIGHT, Vector3.UP) * Basis(Vector3.BACK, 0.4 + (PI * 0.5 if i % 2 else 0.0))
		l.basis = l.basis.scaled_local(Vector3.ONE * 1.1)
		l.position = Vector3(-3.5 + i * 0.25, 1.0, 1.0)
	var cols: Array[Color] = [Color(0.9, 0.12, 0.2), Color(0.62, 0.14, 0.95), Color(0.85, 0.1, 0.55)]
	for i in 3:
		var v := Node3D.new()
		v.position = Vector3(-0.8 + i * 0.9, 0.95, 1.2)
		add_child(v)
		v.basis = Basis.looking_at(Vector3(-1, 0, 0.3), Vector3.UP)
		var m := WeaponArt.build(WeaponArt.SOUL, v, cols[i])
		m.scale = Vector3.ONE * 1.45
		m.rotation.x = 0.6
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(3.2 + cos(a) * 1.2, 0.0, 1.2 + sin(a) * 1.2)
		var piv := Node3D.new()
		add_child(piv)
		piv.position = p
		piv.basis = Basis.looking_at(Vector3(-cos(a), 0, -sin(a)), Vector3.UP) * Basis(Vector3.RIGHT, 0.14)
		WeaponArt.build(WeaponArt.RUNE_STONES, piv, WeaponArt.NO_TINT, "stone%d" % (i % 3), true)


func _process(delta: float) -> void:
	_t += delta
	_spin.rotation.y = -_t * 6.0
