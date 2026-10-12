extends Pickup
## In-run meta-loot pickup: a Sin Shard (violet octahedral crystal) or a lump of Hellstone (molten
## orange rock). Built entirely in code. Sits still until the player's PickupArea touches it, then
## flies in; on contact it is credited with Progression.collect_run_loot (banked when the run ends).
## Spawn with Progression.drop_loot(position, &"sin_shards" | &"hellstone", amount).

## &"sin_shards" or &"hellstone"
var currency: StringName = &"sin_shards"
var value := 1

var _t := 0.0
var _pop := 0.0
var _model: Node3D
var _light: OmniLight3D


func _init() -> void:
	homing_accel = 40.0
	homing_start_speed = -3.0
	collision_layer = 8  # pickups
	collision_mask = 0
	monitoring = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	shape.shape = sphere
	add_child(shape)


func _ready() -> void:
	_t = randf() * TAU
	_build()
	_animate(0.0)


func _physics_process(delta: float) -> void:
	_t += delta
	_animate(delta)
	_home(delta)


func _collect(_player: Player) -> void:
	Sfx.play(&"gold", 0.06, -2.0)
	Progression.collect_run_loot(currency, value)
	var def := Progression.get_currency_def(currency)
	var hud := get_tree().get_first_node_in_group(&"hud")
	if hud and hud.has_method(&"toast") and currency == &"hellstone":
		hud.call(&"toast", "+%d %s" % [value, def.name], def.color)


func _animate(delta: float) -> void:
	if _model == null:
		return
	if _pop < 1.0:
		_pop = minf(_pop + delta * 3.0, 1.0)
	_model.scale = Vector3.ONE * maxf(_pop * (2.0 - _pop), 0.01)
	_model.position.y = 0.45 + sin(_t * 2.2) * 0.08
	_model.rotation.y += (5.0 if is_attracted() else 1.3) * delta
	_light.light_energy = 0.8 + 0.4 * sin(_t * 3.0)


func _build() -> void:
	var hell := currency == &"hellstone"
	var col: Color = Progression.get_currency_def(currency).color
	_model = Art.pivot(self)
	if hell:
		# A cracked black rock with magma glowing through: dark core + additive shell.
		var rock := SphereMesh.new()
		rock.radial_segments = 6
		rock.rings = 3
		Art.part(_model, rock, Art.mat(Art.OBSIDIAN, 0.9), Vector3.ZERO, Vector3(0.42, 0.34, 0.38), Vector3(0.3, 0.0, 0.2))
		Art.part(_model, rock, Art.glow(col, 2.6, true, 0.55), Vector3.ZERO, Vector3(0.48, 0.4, 0.44), Vector3(-0.2, 0.7, 0.1))
	else:
		# Octahedron: a 4-sided sphere with 2 rings is exactly that.
		var crystal := SphereMesh.new()
		crystal.radial_segments = 4
		crystal.rings = 1
		Art.part(_model, crystal, Art.emissive(col.darkened(0.4), col, 2.2, 0.2), Vector3.ZERO, Vector3(0.26, 0.5, 0.26))
		Art.part(_model, crystal, Art.glow(col, 1.2, true, 0.35), Vector3.ZERO, Vector3(0.36, 0.62, 0.36))
	_light = Art.light(self, col, 0.8, 2.4, Vector3(0.0, 0.6, 0.0))
	Art.no_shadows(_model)
