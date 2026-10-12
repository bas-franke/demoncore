extends Objective
## "Free the Damned": `cages` gilded cages scattered within `spread` of the marker, each holding a
## damned soul. Stand beside a cage for `break_time` s to tear it open; the freed soul joins the
## demon as a DamnedSoul ally (`ally_*` params) and grants the `per_soul` rewards at once. Wardens
## (`wardens` enemy ids) answer when the demon arrives. Free them all within `time_limit` s of
## arriving for the full reward; when time runs out the remaining souls are purified (failed).
## params: cages, spread, break_time, time_limit, wardens, ally_duration, ally_damage,
##         ally_interval, ally_range.

const BREAK_RADIUS := 1.7
const BARS := 9

## One cage: its nodes and break progress.
class Cage:
	var root: Node3D
	var bars: Node3D
	var soul: Node3D
	var soul_mat: StandardMaterial3D
	var zone: BossTelegraph
	var progress := 0.0
	var freed := false


var _cages: Array[Cage] = []
var _freed := 0
var _time_limit := 70.0


func _build() -> void:
	var n := maxi(int(param("cages", 4)), 1)
	var spread := float(param("spread", 6.5))
	_time_limit = float(param("time_limit", 70.0))
	for i in n:
		var a := TAU * float(i) / float(n) + randf_range(-0.4, 0.4)
		var r := spread * randf_range(0.55, 1.0) if n > 1 else 0.0
		_cages.append(_make_cage(Vector3(cos(a) * r, 0.0, sin(a) * r)))
	status_text = "0 / %d" % n


func _make_cage(local: Vector3) -> Cage:
	var root := Art.pivot(self, local)
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.25, false, 0.0, &"gold")
	Art.part(root, Art.cylinder(), Art.mat(Art.STONE, 0.9, 0.0, 0.5, false, 0.0, &"stone"),
			Vector3(0.0, 0.08, 0.0), Vector3(1.3, 0.16, 1.3))
	var bars := Art.pivot(root)
	for b in BARS:
		var a := TAU * float(b) / float(BARS)
		Art.part(bars, Art.cylinder(), gold, Vector3(cos(a) * 0.55, 1.0, sin(a) * 0.55), Vector3(0.05, 1.7, 0.05))
	Art.part(bars, Art.torus(0.88, 1.0), gold, Vector3(0.0, 1.85, 0.0), Vector3.ONE * 0.6)
	Art.part(bars, Art.cone(0.5), gold, Vector3(0.0, 2.15, 0.0), Vector3(1.2, 0.6, 1.2))
	var soul_root := Art.pivot(root, Vector3(0.0, 1.0, 0.0))
	var soul := HolyFX.glow_part(soul_root, Art.sphere(), Art.SOUL, 1.8, Vector3.ZERO, Vector3(0.38, 0.55, 0.38))
	HolyFX.glow_part(soul_root, Art.sphere(), Art.HOLY_WHITE, 0.6, Vector3(0.0, 0.12, 0.0), Vector3.ONE * 0.14)
	var c := Cage.new()
	c.root = root
	c.bars = bars
	c.soul = soul_root
	c.soul_mat = soul.material_override as StandardMaterial3D
	c.zone = ObjectiveFX.zone(self)
	return c


func marker_position() -> Vector3:
	# Point at the nearest cage still locked once the demon is here.
	if state == State.ACTIVE:
		var best := global_position
		var best_d := INF
		for c in _cages:
			if c.freed:
				continue
			var at := c.root.global_position
			var d := _player_distance(at)
			if d < best_d:
				best_d = d
				best = at
		return best
	return global_position


func _tick(delta: float) -> void:
	if state == State.DORMANT and _player_distance() <= float(param("spread", 6.5)) + 4.0:
		activate()
	var break_time := maxf(float(param("break_time", 1.2)), 0.1)
	for c in _cages:
		var root := c.root
		var soul := c.soul
		var zone := c.zone
		if c.freed:
			continue
		soul.position.y = 1.0 + sin(age * 2.0 + root.position.x) * 0.1
		var mat := c.soul_mat
		mat.albedo_color = HolyFX.scaled(Art.SOUL, 1.5 + 0.5 * sin(age * 5.0 + root.position.z))
		var near := _player_distance(root.global_position) <= BREAK_RADIUS
		if state == State.ACTIVE and near:
			c.progress = minf(c.progress + delta / break_time, 1.0)
			c.bars.position = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.03 * c.progress
			if c.progress >= 1.0:
				_free_soul(c)
				continue
		else:
			c.progress = maxf(c.progress - delta / break_time, 0.0)
		zone.show_disc(root.global_position, BREAK_RADIUS, Art.SOUL, c.progress, 0.5 if not near else 0.9, 1.0)
	if state != State.ACTIVE:
		return
	var left := _time_limit - active_time
	progress = float(_freed) / float(_cages.size())
	status_text = "%d / %d  %s" % [_freed, _cages.size(), fmt_time(left)]
	if _freed >= _cages.size():
		complete()
	elif left <= 0.0:
		fail()


func _on_activated() -> void:
	_toast("The damned cry out to you", Art.SOUL)
	var ids: Array = param("wardens", [])
	if ids.is_empty():
		return
	for i in mini(_cages.size(), 4):
		_spawn_enemy(str(ids.pick_random()), ObjectiveFX.ring_point(global_position, float(param("spread", 6.5)) + 2.5))


func _free_soul(c: Cage) -> void:
	c.freed = true
	_freed += 1
	var root := c.root
	c.zone.hide_now()
	var at := root.global_position
	# The bars burst outward and the soul flies to the demon's side.
	for bar in c.bars.get_children():
		var b := bar as Node3D
		var out := Vector3(b.position.x, 0.0, b.position.z).normalized()
		var tw := b.create_tween()
		tw.tween_property(b, "position", b.position + out * 1.6 + Vector3(0.0, -0.8, 0.0), 0.45).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(b, "rotation", Vector3(out.z, 0.0, -out.x) * 1.4, 0.45)
		tw.parallel().tween_property(b, "scale", Vector3.ONE * 0.01, 0.6).set_delay(0.3)
	c.soul.hide()
	ObjectiveFX.corruption_burst(at, 0.5)
	Sfx.play(&"harvest", 0.0, 0.0)  # not &"soul": that is the XP pickup pitch ladder
	Sfx.play(&"chain", 0.05, -4.0)
	DamnedSoul.summon(at, float(param("ally_duration", 80.0)), float(param("ally_damage", 9.0)),
			float(param("ally_interval", 0.75)), float(param("ally_range", 6.0)))
	var rewards: Dictionary = def.get("rewards", {})
	var per_soul: Dictionary = rewards.get("per_soul", {})
	var director := get_tree().get_first_node_in_group(&"objective_director")
	if director and not per_soul.is_empty():
		director.call(&"grant", per_soul, at)


func _on_finished(completed: bool) -> void:
	for c in _cages:
		c.zone.hide_now()
		if not c.freed and not completed:
			# Purified: the soul goes up in a column of light.
			var at := c.soul.global_position
			HolyFX.column(at, 0.4, 14.0, 0.8, Art.HOLY, 1.6)
			c.soul.hide()
	if not completed:
		Sfx.play(&"choir", 0.0, -2.0)
