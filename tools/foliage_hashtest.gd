extends SceneTree
## Temporary: compares FoliageField (CPU) with the ground shader functions on the GPU.

func _initialize() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/world/ground.gdshader")
	var funcs := ""
	for fn in ["float hash21(", "vec2 hash22(", "float vnoise(", "float fbm(", "float road_mask(", "float plaza_mask("]:
		var a := src.find(fn)
		var b := src.find("\n}\n", a)
		funcs += src.substr(a, b - a + 3) + "\n"
	var code := """shader_type canvas_item;
uniform float road_scale = 0.017;
uniform float road_width = 0.03;
uniform float plaza_cell = 40.0;
uniform float plaza_chance = 0.45;
uniform float origin_plaza_radius = 7.0;
uniform vec2 origin = vec2(-128.0);
""" + funcs + """
void fragment() {
	vec2 p = origin + floor(FRAGCOORD.xy) + 0.5;
	float wide;
	float road = road_mask(p, wide);
	vec2 rel; float rad;
	float plaza = plaza_mask(p, rel, rad);
	COLOR = vec4(road, plaza, wide, 1.0);
}
"""
	for org: Vector2 in [Vector2(-128, -128), Vector2(400, -900)]:
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 256)
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cr := ColorRect.new()
		cr.size = Vector2(256, 256)
		var m := ShaderMaterial.new()
		var s := Shader.new()
		s.code = code
		m.shader = s
		m.set_shader_parameter("origin", org)
		cr.material = m
		vp.add_child(cr)
		root.add_child(vp)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBAF)
		var ff := FoliageField.new()
		var t0 := Time.get_ticks_usec()
		var bad := [0, 0, 0]
		var on := [0, 0, 0]
		var maxerr: Array[float] = [0.0, 0.0, 0.0]
		var vis := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				var c := img.get_pixel(x, y)
				var px := org.x + x + 0.5
				var pz := org.y + y + 0.5
				var r := ff.road(px, pz)
				var pl := ff.plaza(px, pz).x
				var ash := ff.road(px, pz, true)
				var cpu: Array[float] = [r, pl, ash]
				var gpu: Array[float] = [c.r, c.g, c.b]
				for k in 3:
					var e := absf(cpu[k] - gpu[k])
					maxerr[k] = maxf(maxerr[k], e)
					if gpu[k] > 0.5:
						on[k] += 1
					if e > 0.25:
						bad[k] += 1
				vis.set_pixel(x, y, Color(c.r, r, 0.0))
		@warning_ignore("integer_division")
		print("FIELDTEST org=%s ms=%d on=%s bad=%s maxerr=%s" % [org, (Time.get_ticks_usec() - t0) / 1000, on, bad, maxerr])
		vis.save_png("C:/Users/buunn/AppData/Local/Temp/claude/sin20/foliage/fieldtest_%d.png" % int(org.x))
		vp.queue_free()
	quit()
