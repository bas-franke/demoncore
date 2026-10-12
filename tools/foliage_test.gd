extends Node3D
## Test harness for res://scenes/world/foliage.gd (not part of the game): instances main.tscn and
## adds a Foliage node next to Decor. Dev args (after "--"):
##   --fol-pos=x,z      teleport the player there after start
##   --fol-cam=dist,pitch   camera rig distance / pitch (close-ups)
##   --fol-off          don't add foliage (A/B screenshots)
##   --fol-stats        print timing / instance stats

const FOLIAGE := preload("res://scenes/world/foliage.gd")

var _main: Node
var _fol: Node3D
var _t := 0.0
var _frames := 0
var _stats := false
var _pos := Vector2.INF


func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	var args := OS.get_cmdline_user_args()
	_stats = "--fol-stats" in args
	if not "--fol-off" in args:
		_fol = FOLIAGE.new()
		_fol.name = "Foliage"
		_main.add_child(_fol)
		_main.move_child(_fol, _main.get_node("Decor").get_index() + 1)
	add_child(_main)
	for a in args:
		if a.begins_with("--fol-pos="):
			var p := a.substr(10).split(",")
			_pos = Vector2(p[0].to_float(), p[1].to_float())
		elif a.begins_with("--fol-cam="):
			var c := a.substr(10).split(",")
			var rig := _main.get_node("CameraRig")
			rig.distance = c[0].to_float()
			rig.pitch_deg = c[1].to_float()
	if _pos != Vector2.INF:
		await get_tree().process_frame
		Game.player.global_position = Vector3(_pos.x, 0.0, _pos.y)
		Game.player.reset_physics_interpolation()


func _process(delta: float) -> void:
	_t += delta
	_frames += 1
	if _stats and _frames % 60 == 0:
		var inst := 0
		var mmis := 0
		if _fol:
			for c in _fol.get_children():
				for m in c.get_children():
					mmis += 1
					inst += (m as MultiMeshInstance3D).multimesh.instance_count
		print("FOL_STATS t=%.1f fps=%d chunks=%d mmis=%d instances=%d draw=%d prims=%d" % [_t,
				Engine.get_frames_per_second(), _fol.get_child_count() if _fol else 0, mmis, inst,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
