class_name UIFit
## Responsive helper: uniformly scales a centred menu block down when the visible area (window
## size, or a large Settings.ui_scale) leaves too little room. Never scales up.
##
##   UIFit.scale_to_fit(%Box)            # call after opening and on viewport size_changed


static func scale_to_fit(box: Control, frac := Vector2(0.94, 0.92)) -> void:
	if box == null or not box.is_inside_tree():
		return
	var avail := box.get_viewport().get_visible_rect().size * frac
	var need := box.get_combined_minimum_size()
	var k := minf(1.0, minf(avail.x / maxf(need.x, 1.0), avail.y / maxf(need.y, 1.0)))
	box.pivot_offset = need * 0.5
	box.scale = Vector2(k, k)
