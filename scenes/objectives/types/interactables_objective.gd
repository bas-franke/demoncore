extends Objective
## "Profane the Fonts" / "Wake the Bells" (written by the maps role, docs/team/maps.md): use `count`
## of the map's own interactables of kind `feature` ("font" = HolyFont: corrupt it, "bell" =
## SummoningBell: strike it; group "map_interactables"). The objective sits over the nearest unused
## one; the first use engages it, every use counts, `count` uses complete it. Once engaged there are
## `time_limit` s (0 = none) to finish. If the map has fewer than `count` usable features the objective
## quietly expires at once (maps without fonts / bells never show it for long; use "maps" to limit it).
## params: feature ("font" | "bell"), count, time_limit.

var _targets: Array[Node] = []
var _done := {}
var _count := 2
var _limit := 0.0
var _impossible := false


func _build() -> void:
	_count = maxi(int(param("count", 2)), 1)
	_limit = float(param("time_limit", 0.0))
	var want := str(param("feature", "font"))
	for n in get_tree().get_nodes_in_group(&"map_interactables"):
		var ok := (want == "font" and n is HolyFont and not (n as HolyFont).corrupted) \
				or (want == "bell" and n is SummoningBell)
		if ok:
			_targets.append(n)
			n.connect(&"activated", _on_feature_used)
	if _targets.size() < _count:
		_impossible = true
		status_text = ""
		return
	# stand the beacon over the nearest usable feature
	var near := _nearest()
	if near:
		global_position = near.global_position
	status_text = "0 / %d" % _count


func _tick(_delta: float) -> void:
	if _impossible:
		_finish(State.EXPIRED)
		return
	if state == State.ACTIVE:
		if _limit > 0.0 and active_time >= _limit:
			fail()
			return
		status_text = "%d / %d" % [_done.size(), _count]
		if _limit > 0.0:
			status_text += "  %ds" % ceili(_limit - active_time)


func marker_position() -> Vector3:
	var n := _nearest()
	return n.global_position if n else global_position


func _nearest() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var from := Game.player.global_position if Game.player else global_position
	for t in _targets:
		if not is_instance_valid(t) or _done.has(t) or not bool(t.call(&"is_ready")):
			continue
		var d := (t as Node3D).global_position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = t
	return best


func _on_feature_used(feature: Node) -> void:
	if is_finished() or _done.has(feature):
		return
	_done[feature] = true
	if state == State.DORMANT:
		activate()
	progress = float(_done.size()) / float(_count)
	status_text = "%d / %d" % [_done.size(), _count]
	if _done.size() >= _count:
		complete()
	else:
		var n := _nearest()
		if n:
			global_position = n.global_position


func _on_finished(_completed: bool) -> void:
	for t in _targets:
		if is_instance_valid(t) and t.is_connected(&"activated", _on_feature_used):
			t.disconnect(&"activated", _on_feature_used)
