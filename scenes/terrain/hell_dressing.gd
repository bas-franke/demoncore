class_name HellDressing
extends Node3D
## Set dressing for a plateau floating on a lava sea (Basecamp Hell): obsidian spires and basalt
## organ-pipes rising out of the lava, brimstone islets and chain posts on the rim, all PropKit props.
## Purely visual (no collision): everything stands OUTSIDE the walkable rectangle, and the near
## (south, +z) side only gets low pieces so nothing tall hides the player from the camera.
##
##   add_child(HellDressing.around(Rect2(X0, Z0, X1 - X0, Z1 - Z0), -1.6))
##
## Everything is merged per 24 m tile after building (a few dozen draw calls).

## Distance band (m) beyond the plateau edge where dressing is placed.
const NEAR := 2.2
const FAR := 16.0


## A ready-built dressing node for the plateau `area` (x, z rect) over lava at height `lava_y`.
static func around(area: Rect2, lava_y: float = -1.6, seed_value: int = 666) -> HellDressing:
	var d := HellDressing.new()
	d.name = "HellDressing"
	d.build(area, lava_y, seed_value)
	return d


func build(area: Rect2, lava_y: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var outer := area.grow(FAR)
	var accept := func(p: Vector2) -> bool:
		var d := _dist_outside(area, p)
		if d < NEAR or d > FAR:
			return false
		# south (near the camera) only from a few metres past the edge
		return p.y < area.end.y or d > 3.0
	var pts := Scatter.poisson(outer, 4.2, rng, 90, accept)
	for p in pts:
		var south := p.y > area.end.y - 1.0
		var d := _dist_outside(area, p)
		var kind: StringName
		if south:
			kind = Props.pick({&"brimstone_rock": 3.0, &"chain_posts": 1.0, &"bone_heap": 1.0}, rng)
		elif d > 6.0:
			kind = Props.pick({&"obsidian_spire": 3.0, &"basalt_columns": 2.0}, rng)
		else:
			kind = Props.pick({&"obsidian_spire": 2.0, &"basalt_columns": 2.0, &"brimstone_rock": 2.0}, rng)
		var n := PropKit.build(kind, rng, false)
		# pieces out in the lava stand on a basalt islet; spires rise straight out of it
		var y := lava_y + (0.15 if kind in [&"obsidian_spire", &"basalt_columns"] else 0.0)
		if kind in [&"brimstone_rock", &"chain_posts", &"bone_heap"]:
			_islet(n, rng)
			y = lava_y + 0.25
		# further out = bigger, so the silhouette builds toward the horizon
		var s := lerpf(0.9, 1.7, clampf((d - NEAR) / (FAR - NEAR), 0.0, 1.0)) * rng.randf_range(0.9, 1.1)
		if south:
			s = minf(s, 1.0)
		n.scale = Vector3(s, s, s)
		n.position = Vector3(p.x, y, p.y)
		add_child(n)
	Scatter.merge(self, 24.0)


## A flat basalt slab under a prop that sits in the lava.
static func _islet(n: Node3D, rng: RandomNumberGenerator) -> void:
	var b := PropBuilder.new()
	var r := PropKit.footprint(StringName(n.get_meta(&"prop", &""))) * 0.9 + 0.6
	b.blob(PropKit.basalt(), r, rng, Transform3D(Basis(), Vector3(0, -0.35, 0)), 0.25, 1, true, true, 0.35, false)
	b.finish(n)


static func _dist_outside(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dz).length()
