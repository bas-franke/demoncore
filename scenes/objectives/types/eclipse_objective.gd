extends Objective
## Run event "Holy Eclipse" (data/objectives/events.json): for `duration` s a black sun hangs over
## the run. Every angel that arrives is empowered (x`hp_mult` HP, x`damage_mult` damage), but each
## one slain sheds extra sin (an extra soul shard worth `bonus_xp_mult` x its XP) and every kill
## banks `souls_per_kill` Souls, paid when the eclipse ends. Surviving it always completes it.

var _kills := 0
var _overlay: CanvasLayer
var _shade: ColorRect
var _sun: Control


func _build() -> void:
	status_text = "Endure"
	_overlay = CanvasLayer.new()
	_overlay.layer = 1
	add_child(_overlay)
	_shade = ColorRect.new()
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.08, 0.0, 0.12, 0.0)
	_overlay.add_child(_shade)
	# The black sun: a dark disc with a burning gold corona, top of the screen.
	_sun = Control.new()
	_sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sun.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sun.draw.connect(_draw_sun)
	_sun.modulate.a = 0.0
	_overlay.add_child(_sun)


func marker_position() -> Vector3:
	var p := Game.player
	return p.global_position if p else global_position


func _tick(_delta: float) -> void:
	if state != State.ACTIVE:
		return
	var duration := float(param("duration", 45.0))
	var left := duration - active_time
	progress = clampf(active_time / duration, 0.0, 1.0)
	status_text = "%d slain  %s" % [_kills, fmt_time(left)]
	var k := clampf(minf(active_time / 2.0, left / 2.0), 0.0, 1.0)
	_shade.color.a = 0.28 * k
	_sun.modulate.a = k
	_sun.queue_redraw()
	if left <= 0.0:
		var p := Game.player
		if p:
			global_position = Vector3(p.global_position.x, 0.0, p.global_position.z)
			reset_physics_interpolation()
		var souls := int(float(_kills) * float(param("souls_per_kill", 0.25)))
		def["rewards"] = {"souls": souls, "xp_levels": 0.5} if souls > 0 else {"xp_levels": 0.5}
		complete()


func _on_activated() -> void:
	def = def.duplicate(true)  # rewards are filled in at the end
	_toast(str(param("title", "A HOLY ECLIPSE")), Color("c46bff"))
	if param("subtitle", "") != "":
		_toast(str(param("subtitle", "")), Color("e8c8ff"))
	Sfx.play(&"toll", 0.0, 2.0)
	Sfx.play(&"choir", 0.0, 0.0)
	get_tree().node_added.connect(_on_node_added)
	Game.enemy_died.connect(_on_enemy_died)
	# Angels already on the field are empowered too.
	for n in get_tree().get_nodes_in_group(&"enemies"):
		_empower.call_deferred(n)


func _on_node_added(n: Node) -> void:
	if n is Enemy:
		# Deferred: after setup and any other system's scaling on entering the tree.
		_empower.call_deferred(n)


# QA: untyped so a node freed before the deferred call (e.g. a corpse or a culled spawn) is skipped;
# a typed `Node` parameter made the engine reject the call ("Cannot convert argument 1").
func _empower(n: Variant) -> void:
	if not is_instance_valid(n):
		return
	var e := n as Enemy
	if e == null or e.is_dying or e.is_in_group(&"boss") or e.has_meta(&"eclipsed"):
		return
	e.set_meta(&"eclipsed", true)
	var hm := float(param("hp_mult", 1.45))
	e.max_hp *= hm
	e.hp *= hm
	e.damage *= float(param("damage_mult", 1.3))
	if e.model:
		e.model.light_color = Color(0.8, 0.5, 1.0)


func _on_enemy_died(at: Vector3, data: Resource) -> void:
	if state != State.ACTIVE:
		return
	_kills += 1
	var d := data as EnemyData
	if d == null:
		return
	var gem: XPGem = ObjectiveDirector.GEM_SCENE.instantiate()
	gem.value = maxi(int(float(d.xp_value) * float(param("bonus_xp_mult", 1.0))), 1)
	Game.spawn.call_deferred(gem, at + Vector3(randf_range(-0.5, 0.5), 0.4, randf_range(-0.5, 0.5)))


func _on_finished(_completed: bool) -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if Game.enemy_died.is_connected(_on_enemy_died):
		Game.enemy_died.disconnect(_on_enemy_died)
	var tw := create_tween().set_parallel()
	tw.tween_property(_shade, "color:a", 0.0, 1.5)
	tw.tween_property(_sun, "modulate:a", 0.0, 1.5)
	_toast("The sun returns", Art.HOLY)


func _draw_sun() -> void:
	var size := _sun.size
	var c := Vector2(size.x * 0.33, size.y * 0.12)  # clear of the timer (top centre) and the list
	var r := minf(size.x, size.y) * 0.055
	var pulse := 1.0 + 0.06 * sin(age * 2.0)
	for i in 6:
		var rr := r * (1.25 + 0.18 * float(i)) * pulse
		_sun.draw_circle(c, rr, Color(1.0, 0.75, 0.3, 0.08))
	_sun.draw_arc(c, r * 1.08 * pulse, 0.0, TAU, 64, Color(1.0, 0.85, 0.45, 0.9), 3.0, true)
	_sun.draw_circle(c, r, Color(0.02, 0.0, 0.03, 0.95))
