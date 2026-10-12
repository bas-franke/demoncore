extends SceneTree
## QA probe: runs a scene and periodically prints run state, then quits.
##   godot --headless --fixed-fps 60 --path . --script res://tools/qa/probe.gd -- \
##         --qa-scene=res://scenes/main.tscn --qa-seconds=360 --qa-interval=30 --autopilot --demon=skarn
## Game args (--autopilot, --demon=, --boss) are read by the game itself as usual.
## Output: "QA_PROBE t=.. elapsed=.. kills=.. hp=../.. lvl=.. dead=.. enemies=.. boss=.. nodes=.. orphans=.. fps=.. paused=.."
## and a final "QA_PROBE_END ..." line.

var scene := "res://scenes/main.tscn"
var seconds := 30.0
var interval := 10.0
var t := 0.0
var next_report := 0.0
var started := false
var max_enemies := 0
var max_nodes := 0
var death_time := -1.0
## --qa-immortal: refill the player's hp every frame so a long run exercises the full spawn curve.
var immortal := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-scene="):
			scene = a.substr(11)
		elif a.begins_with("--qa-seconds="):
			seconds = a.substr(13).to_float()
		elif a == "--qa-immortal":
			immortal = true
		elif a.begins_with("--qa-interval="):
			interval = a.substr(14).to_float()
	next_report = interval
	print("QA_PROBE_START scene=%s seconds=%s" % [scene, seconds])
	var err := change_scene_to_file(scene)
	if err != OK:
		print("QA_PROBE_FAIL change_scene_to_file(%s) = %s" % [scene, error_string(err)])
		quit(3)
		return
	started = true


func _process(delta: float) -> bool:
	if not started:
		return false
	t += delta
	if immortal:
		_heal()
	var st := _state()
	max_enemies = maxi(max_enemies, st.enemies)
	max_nodes = maxi(max_nodes, st.nodes)
	if st.dead and death_time < 0.0:
		death_time = t
		print("QA_PROBE_DIED t=%.1f %s" % [t, _fmt(st)])
	if t >= next_report:
		next_report += interval
		print("QA_PROBE t=%.1f %s" % [t, _fmt(st)])
	if t >= seconds:
		print("QA_PROBE_END t=%.1f %s max_enemies=%d max_nodes=%d died_at=%.1f" % [
			t, _fmt(st), max_enemies, max_nodes, death_time])
		quit(0)
		return true
	return false


func _state() -> Dictionary:
	var d := {
		"elapsed": 0.0, "kills": 0, "hp": -1.0, "max_hp": -1.0, "lvl": 0, "dead": false,
		"enemies": 0, "boss": 0, "weapons": 0, "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"fps": Performance.get_monitor(Performance.TIME_FPS), "paused": paused,
	}
	var game := root.get_node_or_null(^"Game")
	if game == null:
		return d
	d.elapsed = game.get(&"elapsed")
	d.kills = game.get(&"kills")
	var p: Variant = game.get(&"player")
	if p != null and is_instance_valid(p):
		d.hp = p.get(&"hp")
		d.max_hp = p.get(&"max_hp")
		d.lvl = p.get(&"level")
		d.dead = p.get(&"is_dead")
		var w: Variant = p.get(&"weapons")
		if w is Array:
			d.weapons = (w as Array).size()
	var world: Variant = game.get(&"world")
	if world != null and is_instance_valid(world):
		for c in (world as Node).get_children():
			if c.get_script() != null and c.is_class("CharacterBody3D") and c.has_method(&"take_damage"):
				d.enemies += 1
	d.boss = get_nodes_in_group(&"boss").size()
	return d


func _fmt(s: Dictionary) -> String:
	return "elapsed=%.1f kills=%d hp=%.0f/%.0f lvl=%d weapons=%d dead=%s enemies=%d boss=%d nodes=%d orphans=%d fps=%.0f paused=%s" % [
		s.elapsed, s.kills, s.hp, s.max_hp, s.lvl, s.weapons, s.dead, s.enemies, s.boss, s.nodes,
		s.orphans, s.fps, s.paused]


func _heal() -> void:
	var game := root.get_node_or_null(^"Game")
	if game == null:
		return
	var p: Variant = game.get(&"player")
	if p != null and is_instance_valid(p) and not p.get(&"is_dead"):
		p.set(&"hp", p.get(&"max_hp"))