extends Node3D
## VFX test harness (res://tools/vfx_test.tscn): main.tscn + a CombatVFX node, plus synthetic
## Game events timed against --shot-time so the screenshot lands mid-effect.
##   godot --path . res://tools/vfx_test.tscn -- --demon=lilaeth --vfx=hits --shot=out.png --shot-time=6
## --vfx= hits | death | blood | boss | dissolve | all

const MODELS := [
	"res://scenes/enemies/models/seraph_sentinel.tscn",
	"res://scenes/enemies/models/penitent_statue.tscn",
	"res://scenes/enemies/models/thurible_priest.tscn",
	"res://scenes/enemies/models/dawn_lancer.tscn",
]

var mode := "all"
var shot_time := 6.0
var _t := 0.0
var _acc := 0.0
var _did := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vfx="):
			mode = arg.substr(6)
		elif arg.begins_with("--shot-time="):
			shot_time = arg.substr(12).to_float()


func _process(delta: float) -> void:
	_t += delta
	var p := Game.player
	if p == null:
		return
	var c := p.global_position
	var to_shot := shot_time - _t
	if mode in ["hits", "all"] and to_shot < 1.5:
		_acc += delta
		while _acc > 0.05:
			_acc -= 0.05
			var a := randf() * TAU
			Game.enemy_hit.emit(c + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.0, 5.0), randf_range(6.0, 36.0))
	if mode in ["death", "all"] and to_shot < 0.5 and _once(&"death"):
		for i in 5:
			Game.enemy_died.emit(c + Vector3(-5.0 + i * 2.5, 0.0, 2.5), null)
	if mode in ["blood", "all"] and to_shot < 0.7:
		Game.player_hit.emit(30.0 * delta)
		if _once(&"blood"):
			Game.player_hit.emit(18.0)
	if mode == "boss" and to_shot < 0.45 and _once(&"boss"):
		Game.boss_died.emit(c + Vector3(0.0, 0.0, -2.0))
	if mode == "dissolve" and to_shot < 1.6 and _once(&"dissolve"):
		for i in MODELS.size():
			var m: Node3D = load(MODELS[i]).instantiate()
			m.scale = Vector3.ONE * 1.6
			Game.spawn(m, c + Vector3(-4.5 + i * 3.0, 0.0, 2.0))
			# Staggered so one screenshot shows several stages.
			var tw := m.create_tween()
			tw.tween_interval(0.25 * i)
			tw.tween_callback(func() -> void: Dissolve.play(m, 2.6, Art.HOLY if i % 2 == 0 else Art.HELLFIRE))


func _once(key: StringName) -> bool:
	if _did.has(key):
		return false
	_did[key] = true
	return true
