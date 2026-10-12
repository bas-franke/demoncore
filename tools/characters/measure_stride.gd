extends SceneTree
## Measures a demon walk clip's planted-foot ground speed (the WALK_CLIP_SPEED to use):
##   godot --headless --path . --script res://tools/characters/measure_stride.gd -- iscariel lilaeth
## While a foot is the lowest point and on the ground it moves backwards at the clip's ground speed.

func _process(_d: float) -> bool:
	for id in OS.get_cmdline_user_args():
		var m := GlbModel.create("res://assets/models/demons/%s.glb" % id)
		root.add_child(m)
		var ap := m.anim_player
		var anim := ap.get_animation(&"walk")
		ap.play(&"walk")
		var feet: Array[Node3D] = [m.scene_root.find_child("foot_L", true, false), m.scene_root.find_child("foot_R", true, false)]
		var n := 120
		var dt := anim.length / float(n)
		var speeds: Array[float] = []
		var last := [Vector3.ZERO, Vector3.ZERO]
		var low := INF
		for i in n + 1:
			ap.seek(dt * float(i), true)
			for f in 2:
				var p := feet[f].global_position
				low = minf(low, p.y)
				if i > 0 and p.y < low + 0.03:
					var v := (p - (last[f] as Vector3)) / dt
					speeds.append(Vector2(v.x, v.z).length())
				last[f] = p
		speeds.sort()
		@warning_ignore("integer_division")
		var med := speeds[speeds.size() / 2] if not speeds.is_empty() else 0.0
		print("STRIDE %s planted-foot speed ~%.2f m/s (clip %.2f s)" % [id, med, anim.length])
		m.free()
	return true
