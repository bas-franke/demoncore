extends SceneTree
## Renders every SVG in res://assets/icons/abilities/ into one contact-sheet PNG (headless ok):
##   godot --headless --path . --script res://tools/icons/icon_sheet.gd -- --out=<abs png> [--size=96]

const DIR := "res://assets/icons/abilities/"


func _initialize() -> void:
	var out := "user://ability_icons.png"
	var size := 96
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--size="):
			size = a.substr(7).to_int()
	var files: Array[String] = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".svg"):
			files.append(f)
	files.sort()
	var cols := 10
	var rows := ceili(float(files.size()) / cols)
	var sheet := Image.create_empty(cols * size, rows * size, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.12, 0.1))
	for i in files.size():
		var img := Image.new()
		var svg := FileAccess.get_file_as_string(DIR + files[i])
		if img.load_svg_from_string(svg, float(size) / 256.0) != OK:
			push_error("icon_sheet: bad svg " + files[i])
			continue
		img.convert(Image.FORMAT_RGBA8)
		@warning_ignore("integer_division")
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % cols) * size, (i / cols) * size))
	sheet.save_png(out)
	print("icon_sheet: %d icons -> %s" % [files.size(), out])
	quit()
