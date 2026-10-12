extends Node
## Difficulty probe (maps role): plays one map with the autopilot bot (no godmode) and prints a line
## every 30 s of game time plus a summary, so maps can be compared on the same bot.
##   godot --headless --fixed-fps 30 --path . res://tools/maps/balance_run.tscn -- --map=<id> [--minutes=6]
## Lines: BALANCE <map> t=<s> hp=<hp>/<max> lvl=<n> kills=<n> alive=<n> taken=<dmg> tier=<n>

var _map := "outer_gardens"
var _limit := 360.0
var _next := 30.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			_map = a.substr(6)
		elif a.begins_with("--minutes="):
			_limit = a.substr(10).to_float() * 60.0
	Game.autopilot = true
	Game.godmode = false
	Maps.select(StringName(_map))
	add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	RunState.run_ended.connect(_on_end)


func _process(_delta: float) -> void:
	if Game.player == null or not is_instance_valid(Game.player):
		return
	if Game.elapsed >= _next:
		_next += 30.0
		_line("")
	if Game.elapsed >= _limit:
		_line("SURVIVED")
		get_tree().quit()


func _line(tag: String) -> void:
	var p := Game.player
	print("BALANCE %s t=%d hp=%d/%d lvl=%d kills=%d alive=%d taken=%d tier=%d %s" % [_map, roundi(Game.elapsed),
			roundi(p.hp) if p else 0, roundi(p.max_hp) if p else 0, p.level if p else 0, Game.kills,
			get_tree().get_node_count_in_group(&"enemies"), roundi(RunState.damage_taken), RunState.difficulty_tier(), tag])


func _on_end(result: Dictionary) -> void:
	print("BALANCE %s END cause=%s t=%d kills=%d lvl=%d taken=%d" % [_map, result.get("cause"),
			roundi(float(result.get("time", 0.0))), int(result.get("kills", 0)), int(result.get("level", 0)),
			roundi(float(result.get("damage_taken", 0.0)))])
	get_tree().quit()
