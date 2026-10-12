class_name Targeting
## Helpers for weapons and abilities that need to find enemies. (The `_tree` parameter is kept
## for API compatibility; the scans use the Perf autoload.) All scans go through
## Perf.enemies() (the "enemies" group, cached per frame) and measure on the XZ plane.


## Returns up to `count` enemies closest to `from` (XZ plane), nearest first.
static func nearest_enemies(_tree: SceneTree, from: Vector3, count: int, max_range: float) -> Array[Enemy]:
	var candidates: Array = []
	var max_sq := max_range * max_range
	for node in Perf.enemies():
		var e := node as Enemy
		if e == null or e.is_dying:
			continue
		var d := e.global_position - from
		d.y = 0.0
		var dsq := d.length_squared()
		if dsq <= max_sq:
			candidates.append([dsq, e])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result: Array[Enemy] = []
	for i in mini(count, candidates.size()):
		result.append(candidates[i][1])
	return result


## The single closest live enemy within `max_range` (XZ plane), or null. Linear scan, no sort.
## `exclude`: optional Array or Dictionary of enemies to skip (e.g. targets already chained).
static func nearest_enemy(_tree: SceneTree, from: Vector3, max_range: float, exclude: Variant = null) -> Enemy:
	var best: Enemy = null
	var best_sq := max_range * max_range
	for node in Perf.enemies():
		var e := node as Enemy
		if e == null or e.is_dying or (exclude != null and exclude.has(e)):
			continue
		var d := e.global_position - from
		d.y = 0.0
		var dsq := d.length_squared()
		if dsq < best_sq:
			best_sq = dsq
			best = e
	return best


## Direction from `from` to `to` flattened onto the ground plane.
static func flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d := to - from
	d.y = 0.0
	return d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
