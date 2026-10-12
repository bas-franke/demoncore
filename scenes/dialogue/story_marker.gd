class_name StoryMarker
extends Label3D
## Story overlay for a Basecamp NPC (child of a HubInteractable):
##  - a floating "!" while Dialogue.has_new(who) is true (an unseen story beat is waiting);
##  - while the NPC is focused and takes offerings, a hint "[G] Offer gift  ✧ 40" and the G key
##    (gamepad Y) to give one (Dialogue.give_gift). Affinity hearts show next to the hint.
## Added automatically by StoryHooks to every shopkeeper and story NPC; add one yourself with
## StoryMarker.attach(node, who, height).

const POLL := 0.5
const GIFT_KEY := KEY_G

## Speaker id, shop id or pool name passed to Dialogue.has_new() / give_gift().
var who := ""
var base_height := 3.6

var _t := 0.0
var _poll := 0.0
var _hint: Label3D


## Adds a marker for `who_id` to `parent`, `height` above its origin.
static func attach(parent: Node3D, who_id: String, height: float) -> StoryMarker:
	var m := StoryMarker.new()
	m.name = "StoryMarker"
	m.who = who_id
	m.base_height = height
	parent.add_child(m)
	return m


func _ready() -> void:
	text = "!"
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.0016
	font_size = 44
	outline_size = 12
	outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	modulate = Color("ffb347")
	render_priority = 11
	outline_render_priority = 10
	position.y = base_height
	# Screen-space nudges (pixels): the "!" sits above the NPC's prompt, the hint just under it.
	offset = Vector2(0.0, 26.0)
	visible = false
	_poll = randf() * POLL
	# The hint hangs off the parent (not this node) so it shows even while the "!" is hidden.
	_hint = Label3D.new()
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.no_depth_test = true
	_hint.fixed_size = true
	_hint.pixel_size = 0.0011
	_hint.font_size = 22
	_hint.outline_size = 8
	_hint.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_hint.render_priority = 10
	_hint.outline_render_priority = 9
	_hint.visible = false
	_hint.offset = Vector2(0.0, -46.0)
	get_parent().add_child.call_deferred(_hint)


func _process(delta: float) -> void:
	_t += delta
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL
		visible = Dialogue.has_new(who)
		_refresh_hint()
	if visible:
		position.y = base_height + 0.08 * sin(_t * 3.2)
		modulate.a = 0.75 + 0.25 * sin(_t * 5.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _focused() or Dialogue.is_active() or get_tree().paused:
		return
	var pressed := false
	if event is InputEventKey:
		var k := event as InputEventKey
		pressed = k.pressed and not k.echo and k.physical_keycode == GIFT_KEY
	elif event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		pressed = b.pressed and b.button_index == JOY_BUTTON_Y
	if not pressed or Dialogue.gift_cost(who) < 0:
		return
	get_viewport().set_input_as_handled()
	if not Dialogue.give_gift(who):
		Sfx.play(&"ui_back", 0.02)
	_refresh_hint()


func _focused() -> bool:
	var p := get_parent()
	return p != null and p.has_method(&"is_focused") and bool(p.call(&"is_focused"))


func _refresh_hint() -> void:
	if _hint == null or not _hint.is_inside_tree():
		return
	var cost := Dialogue.gift_cost(who)
	_hint.visible = _focused() and cost >= 0 or (_focused() and Dialogue.affinity(who) >= Affinity.MAX_LEVEL)
	if not _hint.visible:
		return
	_hint.position.y = float(get_parent().get(&"prompt_height")) if get_parent().get(&"prompt_height") != null else base_height
	var lv := Dialogue.affinity(who)
	var hearts := "♥".repeat(lv) + "♡".repeat(Affinity.MAX_LEVEL - lv)
	if cost < 0:
		_hint.text = hearts + "   Bonded"
		_hint.modulate = Color("ff9a6a")
	elif Dialogue.can_gift(who):
		_hint.text = "%s   [G] Offer gift  ✧ %d" % [hearts, cost]
		_hint.modulate = Color("f0d9b0")
	else:
		_hint.text = "%s   [G] Offer gift  ✧ %d" % [hearts, cost]
		_hint.modulate = Color(0.6, 0.55, 0.5, 0.8)
