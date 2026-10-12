extends Node3D
## Visual check for SkinBake / GlbSkin: each horde type twice, original (back row) vs skinned
## (front row), animating side by side. Windowed:
##   godot --path . res://tools/perf/skin_compare.tscn -- --shot=out.png [--types=cherub,ophan]
##   [--anim=walk]  (Blender models: clip to play; default walk)

const TYPES := ["cherub", "ophan", "holy_knight", "zealot", "villager_torch", "monk", "martyr", "light_elemental"]


func _ready() -> void:
	var types := PackedStringArray(TYPES)
	var shot := ""
	var anim := &"walk"
	var only_row := -1  # --row=0 / 1: just the original / just the skinned one, centred
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--row="):
			only_row = a.substr(6).to_int()
		if a.begins_with("--anim="):
			anim = StringName(a.substr(7))
		if a.begins_with("--types="):
			types = a.substr(8).split(",")
		elif a.begins_with("--shot="):
			shot = a.substr(7)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.12, 0.14)
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3((types.size() - 1) * 0.9, 1.4 + 0.25 * types.size(), 2.6 + 0.8 * types.size())
	cam.rotation.x = -0.3
	cam.fov = 62.0
	add_child(cam)
	cam.current = true
	for i in types.size():
		var data := load("res://data/enemies/%s.tres" % types[i]) as EnemyData
		if data == null or data.model == null:
			continue
		for row in 2:
			if only_row >= 0 and row != only_row:
				continue
			var m := data.model.instantiate()
			if m is ProcModel:
				(m as ProcModel).skin_bake = row == 1
				(m as ProcModel).autoplay = true
			# One type: side by side (left = original, right = skinned), or centred with --row.
			if types.size() == 1:
				m.position = Vector3(0.0, 0.0, 1.5) if only_row >= 0 else Vector3((row - 0.5) * 1.4, 0.0, 0.0)
			else:
				m.position = Vector3(i * 1.8, 0.0, -1.6 if row == 0 else 0.4)
			m.rotation.y = 0.5
			GlbSkin.enabled = row == 1
			add_child(m)
			GlbSkin.enabled = true
			var em := m as EnemyModel
			if em and em.glb:
				em.glb.play(anim, 0.0)
				em.glb.anim_player.seek(0.37, true)
	if shot != "":
		await get_tree().create_timer(2.5).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
