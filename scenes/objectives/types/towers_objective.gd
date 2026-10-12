extends Objective
## "Hold the Bell Towers": three bell towers in a triangle (`spread` m from the marker). Stand at a
## tower (`capture_radius`) to corrupt it (`capture_time` s); a corrupted tower stays yours for
## `hold_time` s, then the angels start to reclaim it (it drains at `reclaim_rate` x). Hold all
## three at once to win. Angels keep coming to ring them back (`raiders`). Fails after
## `time_limit` s.
## params: count, spread, capture_radius, capture_time, hold_time, reclaim_rate, time_limit,
##         raid_interval, raid_size, raiders (enemy ids).

## One tower: its nodes and state.
class Tower:
	var root: Node3D
	var bell: Node3D
	var bell_mat: StandardMaterial3D
	var zone: BossTelegraph
	var corruption := 0.0  # 0 holy .. 1 held
	var held_t := 0.0  # seconds since it was fully taken (reclaiming starts after hold_time)


var _towers: Array[Tower] = []
var _raid_t := 0.0


func _build() -> void:
	var n := maxi(int(param("count", 3)), 2)
	var spread := float(param("spread", 9.0))
	var base := randf() * TAU
	for i in n:
		var a := base + TAU * float(i) / float(n)
		_towers.append(_make_tower(Vector3(cos(a), 0.0, sin(a)) * spread))
	status_text = "0 / %d" % n


func _make_tower(local: Vector3) -> Tower:
	var t := Tower.new()
	var stone := Art.mat(Art.STONE, 0.9, 0.0, 0.5, false, 0.0, &"stone")
	var bronze := Art.mat(Art.BRONZE, 0.35, 1.0, 0.35, false, 0.0, &"gold")
	t.root = Art.pivot(self, ObjectiveFX.walkable(global_position + local) - global_position)
	Art.part(t.root, Art.box(), stone, Vector3(0.0, 0.2, 0.0), Vector3(1.8, 0.4, 1.8))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			Art.part(t.root, Art.box(), stone, Vector3(sx * 0.6, 2.2, sz * 0.6), Vector3(0.3, 4.0, 0.3))
	Art.part(t.root, Art.box(), stone, Vector3(0.0, 4.3, 0.0), Vector3(1.7, 0.3, 1.7))
	Art.part(t.root, Art.cone(0.5), stone, Vector3(0.0, 5.1, 0.0), Vector3(1.9, 1.4, 1.9))
	t.bell = Art.pivot(t.root, Vector3(0.0, 4.1, 0.0))
	Art.part(t.bell, Art.cylinder(0.22, 0.5), bronze, Vector3(0.0, -0.45, 0.0), Vector3(1.0, 0.8, 1.0))
	var glow := HolyFX.glow_part(t.bell, Art.sphere(), Art.HOLY, 1.2, Vector3(0.0, -0.8, 0.0), Vector3.ONE * 0.3)
	t.bell_mat = glow.material_override as StandardMaterial3D
	t.zone = ObjectiveFX.zone(self)
	return t


func marker_position() -> Vector3:
	# Once the fight is on, point at the nearest tower that is not (or no longer) held.
	if state == State.ACTIVE:
		var best: Tower = null
		var best_d := INF
		for t in _towers:
			if t.corruption >= 1.0:
				continue
			var d := _player_distance(t.root.global_position)
			if d < best_d:
				best_d = d
				best = t
		if best:
			return best.root.global_position
	return global_position


func _tick(delta: float) -> void:
	var r := float(param("capture_radius", 3.0))
	var cap := maxf(float(param("capture_time", 4.0)), 0.5)
	var hold := float(param("hold_time", 9.0))
	var reclaim := float(param("reclaim_rate", 0.12))
	var held := 0
	# Arriving among the towers starts it (the demon need not pick one first).
	if state == State.DORMANT and _player_distance() <= float(param("spread", 9.0)) + 3.0:
		activate()
	for t in _towers:
		var at := t.root.global_position
		var on := _player_distance(at) <= r
		if state == State.DORMANT and on:
			activate()
		if state == State.ACTIVE:
			if on:
				t.corruption = minf(t.corruption + delta / cap, 1.0)
				if t.corruption >= 1.0:
					t.held_t = 0.0
			elif t.corruption >= 1.0 and t.held_t < hold:
				t.held_t += delta
			else:
				t.corruption = maxf(t.corruption - delta * reclaim, 0.0)
				if t.corruption < 1.0:
					t.held_t = hold  # once slipping it keeps slipping until retaken
		if t.corruption >= 1.0:
			held += 1
		var col := Art.HOLY.lerp(Art.HELLFIRE, t.corruption)
		t.bell_mat.albedo_color = HolyFX.scaled(col, 1.2 + t.corruption * 1.5)
		t.bell.rotation.z = sin(age * 6.0) * 0.25 * (1.0 - t.corruption) if state == State.ACTIVE else 0.0
		var slipping := t.corruption >= 1.0 and t.held_t > hold * 0.6
		t.zone.show_disc(at, r, col, t.corruption, (0.9 if on else 0.55) * (0.6 + 0.4 * sin(age * 10.0) if slipping else 1.0), 1.2)
	if state != State.ACTIVE:
		return
	var sum := 0.0
	for t in _towers:
		sum += t.corruption
	progress = sum / float(_towers.size())
	var left := float(param("time_limit", 100.0)) - active_time
	status_text = "%d / %d held  %s" % [held, _towers.size(), fmt_time(left)]
	_raid_t -= delta
	if _raid_t <= 0.0:
		_raid_t = float(param("raid_interval", 5.0))
		_raid()
	if held >= _towers.size():
		complete()
	elif left <= 0.0:
		fail()


## Angels come for the tower the demon holds best.
func _raid() -> void:
	var ids: Array = param("raiders", ["choir_wisp"])
	if ids.is_empty():
		return
	var best: Tower = _towers[0]
	for t in _towers:
		if t.corruption > best.corruption:
			best = t
	for i in int(param("raid_size", 4)):
		_spawn_enemy(str(ids.pick_random()), ObjectiveFX.ring_point(best.root.global_position, randf_range(6.0, 9.0)))


func _on_activated() -> void:
	_toast("Silence the bells. All of them, at once.", Color("e6b35a"))
	_raid_t = 3.0


func _on_finished(completed: bool) -> void:
	for t in _towers:
		t.zone.hide_now()
	if completed:
		for t in _towers:
			ObjectiveFX.corruption_burst(t.root.global_position, 0.7)
		Sfx.play(&"toll", 0.0, 4.0)
