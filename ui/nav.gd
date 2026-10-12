class_name UINav
## Keyboard / gamepad navigation helpers shared by every menu (UI role).
##
##   var d := UINav.page_dir(event)      # -1 / +1 for Q / E, PageUp / PageDown, pad LB / RB; else 0
##   UINav.recover_focus(event, button)  # a direction / accept with nothing focused -> focus `button`
## Focus outlines themselves come from the theme (every button, slider, toggle and field has a
## hellfire "focus" style), so anything focusable shows where the cursor is.


static func page_dir(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_Q, KEY_PAGEUP:
				return -1
			KEY_E, KEY_PAGEDOWN:
				return 1
	elif event is InputEventJoypadButton and event.pressed:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				return -1
			JOY_BUTTON_RIGHT_SHOULDER:
				return 1
	return 0


## When the mouse left nothing focused (clicked empty space), the first directional or accept
## press puts focus back on `fallback` instead of doing nothing. Returns true if it did.
static func recover_focus(event: InputEvent, fallback: Control) -> bool:
	if fallback == null or not fallback.is_visible_in_tree():
		return false
	if fallback.get_viewport().gui_get_focus_owner() != null:
		return false
	for a: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_focus_next"]:
		if event.is_action_pressed(a):
			fallback.grab_focus()
			fallback.get_viewport().set_input_as_handled()
			return true
	return false
