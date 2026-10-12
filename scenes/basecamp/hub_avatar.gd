class_name HubAvatar
extends CharacterBody3D
## The chosen demon walking around Basecamp Hell. Movement only (no combat, no stats): WASD /
## arrows / left stick, using the same input actions as the run. `frozen` stops it while a shop is
## open. Group "hub_avatar" (shopkeepers watch it).

const DEFAULT_DEMON := "res://data/demons/vharok.tres"
const SURFACE_PROBE := preload("res://scripts/audio/surface_probe.gd")

@export var move_speed := 5.5

var frozen := false
var model: DemonModel
var _yaw := 0.0
var _step_t := 0.0


func _ready() -> void:
	add_to_group(&"hub_avatar")
	add_to_group(&"atmo_focus")  # Atmosphere weather follows the avatar (docs/team/visuals.md)
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)

	var demon := Game.selected_character as DemonData
	if demon == null:
		demon = load(DEFAULT_DEMON) as DemonData
	model = DemonModel.new()
	add_child(model)
	model.build(demon)
	_yaw = rotation.y
	rotation.y = 0.0
	model.rotation.y = _yaw


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if not frozen:
		input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	var dir := Vector3(input.x, 0.0, input.y)
	velocity = dir * move_speed
	move_and_slide()
	position.y = 0.0
	if dir.length_squared() > 0.01:
		_yaw = lerp_angle(_yaw, atan2(-dir.x, -dir.z), 1.0 - exp(-12.0 * delta))
		_step_t -= delta * velocity.length()
		if _step_t <= 0.0:
			_step_t = 1.6
			# Surface from the sfx probe (sfx_surface zones / terrain); the hub floor is flagstone.
			var surf: StringName = SURFACE_PROBE.surface_at(get_tree(), global_position)
			Sfx.play_at(StringName("step_" + (String(surf) if surf != &"" else "stone")), global_position,
					0.06, -10.0)
	model.rotation.y = _yaw
	model.ground_speed = velocity.length()
	model.animate(delta, velocity.length() / maxf(move_speed, 0.1))


## Turns the demon to face `pos` (used when talking to a merchant).
func face(pos: Vector3) -> void:
	var d := pos - global_position
	_yaw = atan2(-d.x, -d.z)


func cheer() -> void:
	model.play_cheer()
