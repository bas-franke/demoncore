extends SceneTree
## Compiles the shared style shaders and every shader that includes the corruption library by
## drawing a mesh with each for a few frames (shader errors only show up in a real renderer, so
## run it WINDOWED, not --headless):
##   godot --path . --script res://tools/style_shader_check.gd
## Prints "style_shader_check: N shaders drawn" and quits; look for SHADER ERROR lines above it.

const SHADERS := [
	"res://shaders/style/hellfire.gdshader",
	"res://shaders/style/holy_glow.gdshader",
	"res://shaders/style/outline.gdshader",
	"res://shaders/style/outline_mask.gdshader",
	"res://shaders/lit.gdshader",
	"res://shaders/lit_static.gdshader",
	"res://shaders/foliage.gdshader",
	"res://scenes/world/ground.gdshader",
	"res://shaders/terrain/terrain.gdshader",
]

var _frames := 0


func _initialize() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	var cam := Camera3D.new()
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 3.0, 8.0), Vector3.ZERO)
	var x := -float(SHADERS.size()) * 0.5
	var n := 0
	for path in SHADERS:
		if not ResourceLoader.exists(path):
			push_warning("style_shader_check: missing " + path)
			continue
		var m := ShaderMaterial.new()
		m.shader = load(path)
		var mi := MeshInstance3D.new()
		mi.mesh = SphereMesh.new()
		mi.material_override = m
		mi.position = Vector3(x, 0.0, 0.0)
		root3d.add_child(mi)
		x += 1.2
		n += 1
	print("style_shader_check: %d shaders drawn" % n)


func _process(_delta: float) -> bool:
	_frames += 1
	return _frames > 10
