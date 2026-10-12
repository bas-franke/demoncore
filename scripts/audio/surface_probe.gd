extends RefCounted
## What the ground under a world position sounds like (owner: sfx role, docs/team/sfx.md).
## Used by the run's footsteps (scenes/world/ambience.gd). Returns one of SURFACES, or &"" when
## nothing claims the spot (the caller then uses its own fallback, e.g. the decor biome).
##
## Resolution order:
##   1. Explicit zones: any Node3D in group &"sfx_surface" with meta "surface" (e.g. "wood") and
##      meta "radius" (circle) or "size" (Vector2, axis-aligned rect, local x/z) around its origin.
##      Maps can drop these on bridges, carpets, puddles...
##   2. The active TerrainPatch (docs/team/terrain.md): bridges -> wood, rivers / pools -> water,
##      paths -> stone when paved, else the theme's ground; the theme's ground by its name
##      (hell -> ash, heaven -> grass, sanctum -> stone) or meta "footstep_surface" on the theme.
##   3. The current map's definition: "footsteps" key if present, else by "biome"
##      (city / citadel -> stone, snow -> snow, eden -> grass; ruins -> caller's decor biome).

const SURFACES := [&"stone", &"grass", &"snow", &"wood", &"water", &"ash"]
const BIOME_SURFACE := {
	"city": &"stone", "citadel": &"stone", "snow": &"snow", "eden": &"grass", "hell": &"ash",
	"heaven": &"grass", "sanctum": &"stone",
}


## Footstep surface under `pos`, most specific source first: an authored surface zone, then the
## terrain patch's splat material, then the current map's default surface ("" if none).
static func surface_at(tree: SceneTree, pos: Vector3) -> StringName:
	var s := _zone_surface(tree, pos)
	if s != &"":
		return s
	s = _terrain_surface(tree, pos)
	if s != &"":
		return s
	return _map_surface(tree)


## The smallest zone containing `pos` wins, so a puddle inside a courtyard zone still splashes.
static func _zone_surface(tree: SceneTree, pos: Vector3) -> StringName:
	var best := &""
	var best_area := INF
	for n in tree.get_nodes_in_group(&"sfx_surface"):
		var z := n as Node3D
		if z == null or not z.has_meta(&"surface"):
			continue
		var local := z.to_local(pos)
		var inside := false
		var area := INF
		if z.has_meta(&"radius"):
			var r := float(z.get_meta(&"radius"))
			inside = Vector2(local.x, local.z).length() <= r
			area = PI * r * r
		elif z.has_meta(&"size"):
			var size: Vector2 = z.get_meta(&"size")
			inside = absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.y * 0.5
			area = size.x * size.y
		if inside and area < best_area:
			var s := _valid(StringName(str(z.get_meta(&"surface"))))
			if s != &"":
				best = s
				best_area = area
	return best


static func _terrain_surface(tree: SceneTree, pos: Vector3) -> StringName:
	var t := tree.get_first_node_in_group(&"terrain") as Node3D
	# Only a TerrainPatch (other nodes may share the group): it answers height_at().
	if t == null or not t.is_inside_tree() or not t.has_method(&"height_at"):
		return &""
	var l3 := t.to_local(pos)
	var p := Vector2(l3.x, l3.z)
	# TerrainPatch keeps its authored features in these arrays (local x/z); read them duck-typed so
	# a refactor there degrades to "theme ground" instead of breaking footsteps.
	for b: Variant in _arr(t, &"_bridges"):
		if b is Array and (b as Array).size() >= 3 and _seg_dist(p, b[0], b[1]) <= float(b[2]) * 0.5 + 0.3:
			return &"wood"
	for r: Variant in _arr(t, &"_rivers"):
		if r is Array and (r as Array).size() >= 2 and _poly_dist(p, r[0]) <= float(r[1]) * 0.5:
			return &"water"
	for pl: Variant in _arr(t, &"_pools"):
		if pl is Array and (pl as Array).size() >= 2 and p.distance_to(pl[0]) <= float(pl[1]):
			return &"water"
	var theme: Variant = t.get(&"theme")
	for pa: Variant in _arr(t, &"_paths"):
		if pa is Array and (pa as Array).size() >= 2 and _poly_dist(p, pa[0]) <= float(pa[1]) * 0.5:
			if theme is Object and float((theme as Object).get(&"path_paved")) > 0.5:
				return &"stone"
			break
	if theme is Resource:
		var res := theme as Resource
		if res.has_meta(&"footstep_surface"):
			return _valid(StringName(str(res.get_meta(&"footstep_surface"))))
		var key := (res.resource_path.get_file().get_basename() + " " + str(res.get(&"display_name"))).to_lower()
		for k: String in BIOME_SURFACE:
			if key.contains(k):
				return BIOME_SURFACE[k]
	return &"stone"


static func _map_surface(tree: SceneTree) -> StringName:
	var maps := tree.root.get_node_or_null(^"Maps")
	if maps == null:
		return &""
	var m: Variant = maps.get(&"current_map")
	if not m is Object or not is_instance_valid(m):
		return &""
	var def: Variant = (m as Object).get(&"def")
	if not def is Dictionary:
		return &""
	if (def as Dictionary).has("footsteps"):
		return _valid(StringName(str(def["footsteps"])))
	return BIOME_SURFACE.get(str(def.get("biome", "")), &"")


static func _valid(s: StringName) -> StringName:
	return s if SURFACES.has(s) else &""


static func _arr(o: Object, prop: StringName) -> Array:
	var v: Variant = o.get(prop)
	return v if v is Array else []


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _poly_dist(p: Vector2, pts: Variant) -> float:
	if not pts is PackedVector2Array or (pts as PackedVector2Array).size() < 2:
		return INF
	var best := INF
	var arr := pts as PackedVector2Array
	for i in arr.size() - 1:
		best = minf(best, _seg_dist(p, arr[i], arr[i + 1]))
	return best
