class_name Crowd
## Cheap enemy-vs-enemy separation (perf role, docs/team/performance.md).
##
## Physics collisions between hundreds of packed CharacterBody3Ds were the single biggest CPU cost
## of a big wave (~10 ms per physics tick for 300 enemies in a ball around the player). Enemies now
## only collide with the world (collision_mask without the enemies layer) and this spreads them
## apart instead: once per physics tick every live enemy is put in a uniform grid (linked-list
## buckets, no allocations) and overlapping pairs push each other apart, the smaller one more.
##
##   velocity = move + knockback + Crowd.push(self)      # Enemy._physics_process
##
## Crowd.enabled = false restores the old behaviour for new enemies (physics collisions).

## Master switch, read by Enemy._ready (collision mask) and push().
static var enabled := true

## Grid cell size in metres. Must be >= the largest pair distance that matters (2 x MAX_RADIUS).
const CELL := 2.0
## Grid half-extent in cells around the player (enemies further away are relocated anyway).
const HALF := 24
## Separation radius = capsule radius x this (a hair under 1 lets crowds pack a little tighter).
const RADIUS_SCALE := 0.95
## Radii are clamped so a boss-sized body doesn't need a bigger grid.
const MAX_RADIUS := 1.0
## Push speed (m/s) per metre of overlap, and the cap on the summed push.
const STIFFNESS := 9.0
const MAX_PUSH := 6.0
## Above this many enemies the separation is re-solved every other physics tick.
const HALF_RATE_ABOVE := 120

static var _tick := -1
static var _ids := {}  # instance id -> index into _push (this tick)
static var _push := PackedVector3Array()
static var _px := PackedFloat32Array()
static var _pz := PackedFloat32Array()
static var _r := PackedFloat32Array()
static var _head := PackedInt32Array()
static var _next := PackedInt32Array()
static var _cell := PackedInt32Array()
static var _ens: Array[Enemy] = []
static var _count := 0
static var _built := -100  # physics frame of the last _update()
static var _built_epoch := -1
## query(): extra search radius covering movement since the grid was built.
const QUERY_MARGIN := 1.5
static var _ox := 0.0
static var _oz := 0.0


## Forgets every enemy reference (Perf calls this at quit).
static func clear() -> void:
	_ens.clear()
	_ids.clear()
	_count = 0
	_built = -100


## Live enemies within `radius` of `pos` (XZ), appended to `out`; uses the separation grid
## (at most a couple of physics ticks old), so it is far cheaper than scanning group "enemies".
## Radii are clamped to the grid: for radius > CELL * HALF use a group scan instead.
static func query(pos: Vector3, radius: float, out: Array[Enemy]) -> void:
	# Rebuild when stale or when enemies came / went since the build (fresh spawns must be found).
	# (Epoch-driven rebuilds at most once per physics step: AoE deaths change it many times.)
	var f := Engine.get_physics_frames()
	if f - _built > 2 or (Perf.enemy_epoch() != _built_epoch and f != _built):
		_update()
	var side := HALF * 2
	var r2 := radius * radius
	# Search the grid with a margin (positions are up to a couple of ticks old), then test the
	# live position.
	var rs := radius + QUERY_MARGIN
	var c0x := maxi(int(floorf((pos.x - rs) / CELL) - _ox), 0)
	var c1x := mini(int(floorf((pos.x + rs) / CELL) - _ox), side - 1)
	var c0z := maxi(int(floorf((pos.z - rs) / CELL) - _oz), 0)
	var c1z := mini(int(floorf((pos.z + rs) / CELL) - _oz), side - 1)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			var i := _head[cz * side + cx]
			while i != -1:
				var e := _ens[i]
				if is_instance_valid(e) and not e.is_dying:
					var d := e.global_position - pos
					if d.x * d.x + d.z * d.z <= r2:
						out.append(e)
				i = _next[i]


## Separation velocity for `e` this physics tick (zero when disabled or not found).
static func push(e: Node3D) -> Vector3:
	if not enabled:
		return Vector3.ZERO
	var f := Engine.get_physics_frames()
	if f != _tick:
		_tick = f
		# Big crowds re-solve every other tick (the push is a soft, slowly changing force).
		if _push.size() < HALF_RATE_ABOVE or f % 2 == 0:
			_update()
	var i: int = _ids.get(e.get_instance_id(), -1)
	return _push[i] if i >= 0 else Vector3.ZERO


static func _update() -> void:
	var list := Perf.enemies()
	var n := list.size()
	_ids.clear()
	_push.resize(n)
	_px.resize(n)
	_pz.resize(n)
	_r.resize(n)
	_next.resize(n)
	_cell.resize(n)
	var side := HALF * 2
	_head.resize(side * side)
	_head.fill(-1)
	var center := Vector3.ZERO
	if is_instance_valid(Game.player):
		center = Game.player.global_position
	var ox := floorf(center.x / CELL) - HALF
	var oz := floorf(center.z / CELL) - HALF
	_ox = ox
	_oz = oz
	_built = Engine.get_physics_frames()
	_built_epoch = Perf.enemy_epoch()
	_ens.resize(n)
	var count := 0
	for node in list:
		var e := node as Enemy
		if e == null or e.is_dying or e.data == null:
			continue
		var p := e.global_position
		var cx := int(floorf(p.x / CELL) - ox)
		var cz := int(floorf(p.z / CELL) - oz)
		if cx < 0 or cz < 0 or cx >= side or cz >= side:
			continue
		_ids[e.get_instance_id()] = count
		_ens[count] = e
		_px[count] = p.x
		_pz[count] = p.z
		_r[count] = minf(0.45 * e.data.size * RADIUS_SCALE, MAX_RADIUS)
		_push[count] = Vector3.ZERO
		var c := cz * side + cx
		_cell[count] = c
		_next[count] = _head[c]
		_head[c] = count
		count += 1
	# Each pair once: the rest of a body's own bucket plus its 4 "forward" neighbour cells.
	# (Hot loop: everything inlined, the pushes on `a` accumulate in locals.)
	var heads := PackedInt32Array([0, 0, 0, 0, 0])
	for a in count:
		var c := _cell[a]
		var cx := c % side
		heads[0] = _next[a]
		heads[1] = _head[c + 1] if cx + 1 < side else -1
		var below := c + side
		var has_below := below < side * side
		heads[2] = _head[below] if has_below else -1
		heads[3] = _head[below + 1] if has_below and cx + 1 < side else -1
		heads[4] = _head[below - 1] if has_below and cx > 0 else -1
		var ax := _px[a]
		var az := _pz[a]
		var ar := _r[a]
		var acc_x := 0.0
		var acc_z := 0.0
		for h in 5:
			var b := heads[h]
			while b != -1:
				var dx := ax - _px[b]
				var dz := az - _pz[b]
				var br := _r[b]
				var rs := ar + br
				var d2 := dx * dx + dz * dz
				if d2 < rs * rs:
					var d := sqrt(d2)
					var overlap := rs - d
					if d < 0.0001:
						# Exactly stacked (fresh spawns): split along an arbitrary, index-based axis.
						var ang := float(a * 7 + b * 13)
						dx = cos(ang)
						dz = sin(ang)
						d = 1.0
						overlap = rs
					# (dx, dz) / d is the unit axis; overlap x stiffness, split so the smaller body
					# gives way more (a takes br / rs of it, b takes ar / rs).
					var mag := overlap * STIFFNESS / (d * rs)
					acc_x += dx * mag * br
					acc_z += dz * mag * br
					_push[b] -= Vector3(dx * mag * ar, 0.0, dz * mag * ar)
				b = _next[b]
		_push[a] += Vector3(acc_x, 0.0, acc_z)
	_count = count
	for i in count:
		var v := _push[i]
		if v.length_squared() > MAX_PUSH * MAX_PUSH:
			_push[i] = v.normalized() * MAX_PUSH
