extends Pickup
## A dropped relic: a small gilded reliquary on the ground under a tall column of light in its
## rarity color (Rarity.COLORS), so rare loot reads from across the screen. Built in code.
## The relic is rolled when dropped (Progression.drop_relic) and granted on contact.

var relic_id: StringName = &""

var _t := 0.0
var _pop := 0.0
var _tier := 0
var _model: Node3D
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D


func _init() -> void:
	homing_accel = 30.0
	homing_start_speed = 2.0
	collision_layer = 8  # pickups
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	add_child(shape)


func _ready() -> void:
	var r := Progression.get_relic(relic_id)
	_tier = int(r.get("tier", 0))
	_build(r)
	if _tier >= Rarity.EPIC:
		Sfx.play(&"choir", 0.0, -6.0)


func _physics_process(delta: float) -> void:
	_t += delta
	if _pop < 1.0:
		_pop = minf(_pop + delta * 2.5, 1.0)
	var e := _pop * (2.0 - _pop)
	_model.scale = Vector3.ONE * maxf(e, 0.01)
	_model.position.y = 0.35 + sin(_t * 1.8) * 0.06
	_model.rotation.y += 1.2 * delta
	_beam.scale = Vector3(0.5 + 0.06 * sin(_t * 4.0), 6.0 * e, 0.5 + 0.06 * sin(_t * 4.0))
	_ring.rotation.y -= 0.8 * delta
	_light.light_energy = 1.4 + 0.5 * sin(_t * 2.6)
	_home(delta)


func _collect(_player: Player) -> void:
	Sfx.play_relic(_tier)  # relic_common .. relic_legendary (sfx)
	Progression.grant_relic(relic_id)


func _build(r: Dictionary) -> void:
	var col := Rarity.color(_tier)
	_model = Art.pivot(self)
	# Reliquary: gilded casket with a little roof and a glowing gem on top.
	var gold := Art.mat(Art.GOLD, 0.35, 0.8, 0.2)
	Art.part(_model, Art.box(), gold, Vector3.ZERO, Vector3(0.42, 0.28, 0.3))
	Art.part(_model, Art.prism(), gold, Vector3(0.0, 0.22, 0.0), Vector3(0.46, 0.16, 0.34))
	Art.part(_model, Art.box(), Art.mat(Art.OBSIDIAN, 0.6), Vector3(0.0, 0.0, 0.151), Vector3(0.3, 0.16, 0.01))
	Art.part(_model, Art.sphere(), Art.glow(col, 2.4), Vector3(0.0, 0.36, 0.0), Vector3.ONE * 0.1)
	Art.part(_model, Art.sphere(), Art.glow(col, 0.9, true, 0.4), Vector3(0.0, 0.05, 0.0), Vector3.ONE * 0.75)
	# Column of light (unit cylinder, scaled up as it pops in) and a ground ring.
	_beam = Art.part(self, Art.cylinder(0.35, 0.5), Art.glow(col, 0.9, true, 0.22), Vector3(0.0, 3.0, 0.0),
			Vector3(0.5, 0.01, 0.5))
	_ring = Art.part(self, Art.torus(0.82, 1.0), Art.glow(col, 1.6, true, 0.6), Vector3(0.0, 0.03, 0.0),
			Vector3(0.7, 0.3, 0.7))
	_light = Art.light(self, col, 1.4, 3.5, Vector3(0.0, 0.8, 0.0))
	Art.no_shadows(self)
	# Floating name in the rarity color.
	var label := Label3D.new()
	label.text = "%s %s" % [r.get("icon", ""), r.get("name", "Relic")]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 19
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.modulate = col
	label.position = Vector3(0.0, 1.3, 0.0)
	add_child(label)
