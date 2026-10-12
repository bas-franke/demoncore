class_name HolyFont
extends MapInteractable
## A font of holy water. While pure it is a hazard: every `pulse_interval` s it washes the angels
## within `heal_radius` (heals `heal_ratio` of their max HP). The demon corrupts it by standing in
## its circle: a hellfire burst scorches nearby angels, the demon drinks (heal) and the water turns
## to blood; a corrupted font then burns angels that wander into it.

@export var heal_radius := 7.0
@export var heal_ratio := 0.15
@export var pulse_interval := 6.0
@export var burst_damage := 60.0
@export var player_heal := 25.0

var corrupted := false
var _pulse_t := 3.0
var _water: MeshInstance3D
var _water_mat: StandardMaterial3D
var _light: OmniLight3D
var _burn_t := 0.0


func _build() -> void:
	display_name = "Holy Font"
	channel_time = 3.0
	radius = 2.8
	tint = Color(0.75, 0.9, 1.0)
	var stone := Art.mat(Color(0.86, 0.84, 0.79), 0.45, 0.0, 0.25, false, 0.0, &"marble")
	var gold := Art.mat(Art.GOLD, 0.3, 0.9, 0.2, false, 0.0, &"metal")
	Art.part(self, Art.cylinder(0.55, 0.75), stone, Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 1.0))
	Art.part(self, Art.cylinder(1.0, 0.7), stone, Vector3(0, 1.0, 0), Vector3(1.2, 0.3, 1.2))
	Art.part(self, Art.torus(0.95, 1.08), gold, Vector3(0, 1.16, 0), Vector3(1.2, 1.0, 1.2))
	_water_mat = StandardMaterial3D.new()
	_water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_water_mat.albedo_color = Color(0.6, 0.85, 1.0) * 1.6
	_water = Art.part(self, Art.cylinder(), _water_mat, Vector3(0, 1.13, 0), Vector3(2.1, 0.02, 2.1))
	_light = Art.light(self, Color(0.7, 0.88, 1.0), 1.4, 6.0, Vector3(0, 1.8, 0))
	# solid for the demon / angels (layer 1), small
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.85
	sh.height = 1.4
	cs.shape = sh
	cs.position.y = 0.7
	body.add_child(cs)
	add_child(body)


func can_activate() -> bool:
	return not corrupted


func _tick(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	if corrupted:
		_light.light_energy = 1.6 + 0.4 * sin(t * 6.0)
		_burn_t -= delta
		if _burn_t <= 0.0:
			_burn_t = 1.0
			ObjectiveFX.damage_enemies(global_position, radius, 12.0)
		return
	_light.light_energy = 1.2 + 0.3 * sin(t * 2.0)
	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = pulse_interval
		_wash()


func _wash() -> void:
	var r2 := heal_radius * heal_radius
	var any := false
	# Perf.enemies(): the group list cached once per frame / physics step for every caller.
	for n in Perf.enemies():
		var e := n as Enemy
		if e == null or e.is_dying or e is MapStatue:
			continue
		if e.global_position.distance_squared_to(global_position) <= r2:
			e.hp = minf(e.hp + e.max_hp * heal_ratio, e.max_hp)
			any = true
	if any:
		HolyFX.motes(global_position + Vector3(0, 1.3, 0), 10, Color(0.7, 0.9, 1.0), heal_radius * 0.3, 1.4, 0.9)
		_ring.show_disc(global_position, heal_radius, Color(0.7, 0.9, 1.0), 1.0, 0.5, 1.4)


func _activate() -> void:
	corrupted = true
	tint = Art.HELLFIRE  # minimap / overview marker turns red
	_water_mat.albedo_color = Color(0.9, 0.08, 0.06) * 1.8
	_light.light_color = Art.HELLFIRE
	ObjectiveFX.corruption_burst(global_position, 1.0)
	ObjectiveFX.damage_enemies(global_position, heal_radius, burst_damage)
	if Game.player:
		Game.player.heal(player_heal)
	Sfx.play(&"chalice", 0.05, 0.0)
	toast("The font runs red")
