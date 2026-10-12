class_name PropBuilder
extends RefCounted
## Procedural mesh accumulator for the terrain prop kit (PropKit) and terrain features.
## Every primitive is appended (in prop-local space, through a Transform3D) to one SurfaceTool per
## (material, shadow) pair, so a whole prop ends up as a handful of MeshInstance3Ds that
## decor.gd / TerrainPatch can merge further. Collision shapes are collected alongside and become
## one StaticBody3D on physics layer 1 ("world"), which blocks both the player and enemies.
##
##   var b := PropBuilder.new()
##   b.lathe(marble, PackedVector2Array([Vector2(0.5, 0), Vector2(0.45, 3)]), 12, Transform3D.IDENTITY)
##   b.box(gold, Vector3(1, 0.2, 1), Transform3D(Basis(), Vector3(0, 3.1, 0)))
##   b.collide_cylinder(0.5, 3.2)
##   var node := b.finish()     # Node3D (+ StaticBody3D child when shapes were added)
##
## Winding is fixed up automatically from the intended outward normal (Godot front faces are
## clockwise), so primitives can be written without worrying about vertex order.

const WORLD_LAYER := 1

var _groups := {}  # "matid|shadow" -> {st, mat, shadow}
var _shapes: Array = []  # [[Shape3D, Transform3D], ...]


# ================================================================ low level

func surface(mat: Material, shadow: bool = true) -> SurfaceTool:
	var key := "%d|%d" % [mat.get_instance_id(), int(shadow)]
	if not _groups.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_groups[key] = {"st": st, "mat": mat, "shadow": shadow}
	return _groups[key]["st"]


## One triangle with per-vertex normals (already in output space). Winding is chosen so the face
## points along the average normal.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		uva := Vector2.ZERO, uvb := Vector2.ZERO, uvc := Vector2.ZERO) -> void:
	var face := (b - a).cross(c - a)
	if face.dot(na + nb + nc) > 0.0:
		# counter-clockwise as seen from the normal side: swap to clockwise (Godot front face)
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
		var tu := uvb; uvb = uvc; uvc = tu
	st.set_normal(na); st.set_uv(uva); st.add_vertex(a)
	st.set_normal(nb); st.set_uv(uvb); st.add_vertex(b)
	st.set_normal(nc); st.set_uv(uvc); st.add_vertex(c)


static var _xn_basis := Basis()
static var _xn_normal := Basis()


## Normal transform (inverse transpose), memoised for the last basis: primitives call this per
## vertex with the same transform, and the inverse is the expensive part.
static func _xn(xf: Transform3D, n: Vector3) -> Vector3:
	if xf.basis != _xn_basis:
		_xn_basis = xf.basis
		_xn_normal = xf.basis.inverse().transposed()
	return (_xn_normal * n).normalized()


func _flat_tri(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var wa := xf * a
	var wb := xf * b
	var wc := xf * c
	var n := (wb - wa).cross(wc - wa)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var o := _xn(xf, outward)
	if n.dot(o) < 0.0:
		n = -n
	tri(st, wa, wb, wc, n, n, n, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))


# ================================================================ primitives

## Axis-aligned box centred on xf.origin.
func box(mat: Material, size: Vector3, xf := Transform3D.IDENTITY, shadow: bool = true) -> void:
	var st := surface(mat, shadow)
	var h := size * 0.5
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for n: Vector3 in dirs:
		# two tangent axes spanning the face
		var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var v := n.cross(u)
		u = v.cross(n)
		var c := n * h
		var corners: Array[Vector3] = []
		for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(c + (u * s.x + v * s.y) * h)
		_flat_tri(st, xf, corners[0], corners[1], corners[2], n)
		_flat_tri(st, xf, corners[0], corners[2], corners[3], n)


## Polygon in the local XY plane extruded along Z from -depth/2 to +depth/2 (gates, slabs, arches,
## window frames). Concave polygons are fine (triangulated). `bevel` = 0 keeps hard edges.
func slab(mat: Material, poly: PackedVector2Array, depth: float, xf := Transform3D.IDENTITY, shadow: bool = true) -> void:
	_extrude(mat, poly, -depth * 0.5, depth * 0.5, xf, shadow, false)


## Polygon in the local XZ plane (x, z) extruded up from y0 to y1 (plinths, basalt columns, slabs).
func prism(mat: Material, poly: PackedVector2Array, y0: float, y1: float, xf := Transform3D.IDENTITY,
		shadow: bool = true) -> void:
	_extrude(mat, poly, y0, y1, xf, shadow, true)


func _extrude(mat: Material, poly: PackedVector2Array, a0: float, a1: float, xf: Transform3D, shadow: bool,
		vertical: bool) -> void:
	if poly.size() < 3:
		return
	var st := surface(mat, shadow)
	# map (poly.x, poly.y, axis) -> local space
	var P := func(p: Vector2, a: float) -> Vector3:
		return Vector3(p.x, a, p.y) if vertical else Vector3(p.x, p.y, a)
	var axis := Vector3.UP if vertical else Vector3.BACK
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var p0 := poly[idx[i]]
		var p1 := poly[idx[i + 1]]
		var p2 := poly[idx[i + 2]]
		_flat_tri(st, xf, P.call(p0, a1), P.call(p1, a1), P.call(p2, a1), axis)
		_flat_tri(st, xf, P.call(p0, a0), P.call(p1, a0), P.call(p2, a0), -axis)
	# side walls; outward = perpendicular to the edge, away from the polygon centroid side
	var clockwise := Geometry2D.is_polygon_clockwise(poly)
	for i in poly.size():
		var p0 := poly[i]
		var p1 := poly[(i + 1) % poly.size()]
		var e := (p1 - p0)
		if e.length_squared() < 1e-10:
			continue
		var o2 := Vector2(e.y, -e.x).normalized()
		if clockwise:
			o2 = -o2
		var o := P.call(o2, 0.0) as Vector3
		_flat_tri(st, xf, P.call(p0, a0), P.call(p1, a0), P.call(p1, a1), o)
		_flat_tri(st, xf, P.call(p0, a0), P.call(p1, a1), P.call(p0, a1), o)


## Surface of revolution around local +Y. `profile` = (radius, y) from bottom to top. `radial`
## (optional Callable(angle: float, t: float) -> float) multiplies the radius, e.g. column flutes.
## Smooth normals are computed from the generated grid. Ends with radius > 0 get flat caps.
func lathe(mat: Material, profile: PackedVector2Array, segs: int, xf := Transform3D.IDENTITY,
		shadow: bool = true, radial := Callable(), flat: bool = false, caps: bool = true, angle0: float = 0.0) -> void:
	var st := surface(mat, shadow)
	var rows := profile.size()
	if rows < 2:
		return
	var grid: Array[PackedVector3Array] = []
	for i in rows:
		var row := PackedVector3Array()
		var t := float(i) / float(rows - 1)
		for j in segs:
			var ang := angle0 + TAU * float(j) / float(segs)
			var r := profile[i].x
			if radial.is_valid():
				r *= float(radial.call(ang, t))
			row.append(Vector3(cos(ang) * r, profile[i].y, sin(ang) * r))
		grid.append(row)
	# Orientation convention: the visible side is (profile direction) x (direction of increasing
	# angle). Walls are listed bottom -> top, top surfaces (discs, rims, bowl insides) outside -> inside.
	for i in rows - 1:
		for j in segs:
			var j1 := (j + 1) % segs
			var a := grid[i][j]
			var b := grid[i][j1]
			var c := grid[i + 1][j1]
			var d := grid[i + 1][j]
			var out := ((d + c) - (a + b)).cross((b + c) - (a + d))
			if out.length_squared() < 1e-12:
				out = _profile_normal(profile, i, (TAU * (float(j) + 0.5) / float(segs)) + angle0)
			if flat:
				_flat_tri(st, xf, a, b, c, out)
				_flat_tri(st, xf, a, c, d, out)
			else:
				var na := _grid_normal(grid, profile, i, j, segs, angle0)
				var nb := _grid_normal(grid, profile, i, j1, segs, angle0)
				var nc := _grid_normal(grid, profile, i + 1, j1, segs, angle0)
				var nd := _grid_normal(grid, profile, i + 1, j, segs, angle0)
				var A := xf * a; var B := xf * b; var C := xf * c; var D := xf * d
				tri(st, A, B, C, _xn(xf, na), _xn(xf, nb), _xn(xf, nc))
				tri(st, A, C, D, _xn(xf, na), _xn(xf, nc), _xn(xf, nd))
	if caps:
		for end: int in [0, rows - 1]:
			if profile[end].x <= 0.001:
				continue
			var cy := profile[end].y
			var n := Vector3.DOWN if end == 0 else Vector3.UP
			for j in segs:
				_flat_tri(st, xf, Vector3(0, cy, 0), grid[end][j], grid[end][(j + 1) % segs], n)


func _grid_normal(grid: Array[PackedVector3Array], profile: PackedVector2Array, i: int, j: int, segs: int,
		angle0: float) -> Vector3:
	var rows := grid.size()
	var tj := grid[i][(j + 1) % segs] - grid[i][(j - 1 + segs) % segs]
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, rows - 1)
	var ti := grid[i1][j] - grid[i0][j]
	var n := ti.cross(tj)
	if n.length_squared() < 1e-10:
		# apex (radius 0) or degenerate profile step: fall back to the 2D profile normal
		return _profile_normal(profile, mini(i, rows - 2), angle0 + TAU * float(j) / float(segs))
	return n.normalized()


## Outward normal of profile segment i (radius, y) rotated to `angle`.
static func _profile_normal(profile: PackedVector2Array, i: int, angle: float) -> Vector3:
	var d := profile[i + 1] - profile[i]
	var n2 := Vector2(d.y, -d.x).normalized()  # (radial, vertical)
	return Vector3(cos(angle) * n2.x, n2.y, sin(angle) * n2.x).normalized()


func cylinder(mat: Material, r_bottom: float, r_top: float, height: float, segs: int,
		xf := Transform3D.IDENTITY, shadow: bool = true, flat: bool = false) -> void:
	lathe(mat, PackedVector2Array([Vector2(r_bottom, 0.0), Vector2(r_top, height)]), segs, xf, shadow,
			Callable(), flat)


## Faceted crystal / spike pointing up +Y (obsidian spires, brimstone crystals, gate finials).
func spike(mat: Material, radius: float, height: float, sides: int, xf := Transform3D.IDENTITY,
		shadow: bool = true, waist: float = 0.75) -> void:
	lathe(mat, PackedVector2Array([Vector2(radius, 0.0), Vector2(radius * waist, height * 0.55),
			Vector2(0.0, height)]), sides, xf, shadow, Callable(), true)


## Torus in the local XZ plane (ring around +Y). `arc` < TAU makes an open arc starting at +X.
func torus(mat: Material, major: float, minor: float, segs: int, rsegs: int, xf := Transform3D.IDENTITY,
		shadow: bool = true, arc: float = TAU) -> void:
	var st := surface(mat, shadow)
	var closed := arc >= TAU - 0.001
	var cols := segs if closed else segs + 1
	# ring of vertices / normals per column, computed once
	var pos: Array[PackedVector3Array] = []
	var nrm: Array[PackedVector3Array] = []
	for i in cols:
		var u := arc * float(i) / float(segs)
		var ring := Vector3(cos(u), 0.0, sin(u))
		var pr := PackedVector3Array()
		var nr := PackedVector3Array()
		for k in rsegs:
			var v := TAU * float(k) / float(rsegs)
			var n := ring * cos(v) + Vector3.UP * sin(v)
			pr.append(xf * (ring * major + n * minor))
			nr.append(_xn(xf, n))
		pos.append(pr)
		nrm.append(nr)
	for i in segs:
		var i1 := (i + 1) % cols
		for k in rsegs:
			var k1 := (k + 1) % rsegs
			tri(st, pos[i][k], pos[i1][k], pos[i1][k1], nrm[i][k], nrm[i1][k], nrm[i1][k1])
			tri(st, pos[i][k], pos[i1][k1], pos[i][k1], nrm[i][k], nrm[i1][k1], nrm[i][k1])


## Tube swept along a polyline (bones, bars, curls, roots, chains). `radii` optional per point.
func tube(mat: Material, points: PackedVector3Array, radius: float, sides: int, xf := Transform3D.IDENTITY,
		shadow: bool = true, radii := PackedFloat32Array(), caps: bool = true) -> void:
	var n := points.size()
	if n < 2:
		return
	var st := surface(mat, shadow)
	var rings: Array[PackedVector3Array] = []
	var norms: Array[PackedVector3Array] = []
	var prev_side := Vector3.ZERO
	for i in n:
		var t := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		# parallel-transport-ish frame: keep the previous side vector if possible
		var side := prev_side
		if side == Vector3.ZERO or absf(side.dot(t)) > 0.95:
			side = Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
		side = (side - t * side.dot(t)).normalized()
		prev_side = side
		var up := t.cross(side)
		var r := radii[i] if i < radii.size() else radius
		var ring := PackedVector3Array()
		var nr := PackedVector3Array()
		for k in sides:
			var a := TAU * float(k) / float(sides)
			var d := side * cos(a) + up * sin(a)
			ring.append(points[i] + d * r)
			nr.append(d)
		rings.append(ring)
		norms.append(nr)
	for i in n - 1:
		for k in sides:
			var k1 := (k + 1) % sides
			tri(st, xf * rings[i][k], xf * rings[i + 1][k], xf * rings[i + 1][k1],
					_xn(xf, norms[i][k]), _xn(xf, norms[i + 1][k]), _xn(xf, norms[i + 1][k1]))
			tri(st, xf * rings[i][k], xf * rings[i + 1][k1], xf * rings[i][k1],
					_xn(xf, norms[i][k]), _xn(xf, norms[i + 1][k1]), _xn(xf, norms[i][k1]))
	if caps:
		for e: int in [0, n - 1]:
			var dir := (points[e] - points[1 if e == 0 else n - 2]).normalized()
			for k in sides:
				_flat_tri(st, xf, points[e], rings[e][k], rings[e][(k + 1) % sides], dir)


## Noisy blob (rocks: flat=true; clouds: flat=false). Icosphere with `subdiv` subdivisions, each
## vertex pushed by hash noise of amplitude `noise` (fraction of the radius). `squash` scales Y.
func blob(mat: Material, radius: float, rng: RandomNumberGenerator, xf := Transform3D.IDENTITY,
		noise: float = 0.25, subdiv: int = 1, flat: bool = true, shadow: bool = true, squash: float = 1.0,
		flat_bottom: bool = false) -> void:
	var st := surface(mat, shadow)
	var mesh := _icosphere(subdiv)
	var verts: PackedVector3Array = mesh[0]
	var faces: PackedInt32Array = mesh[1]
	var seed_off := Vector3(rng.randf() * 100.0, rng.randf() * 100.0, rng.randf() * 100.0)
	var pos := PackedVector3Array()
	pos.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		var k := 1.0 + noise * (_vnoise(v * 1.7 + seed_off) * 2.0 - 1.0) + noise * 0.5 * (_vnoise(v * 4.1 + seed_off) - 0.5)
		var p := v * radius * k
		p.y *= squash
		if flat_bottom and p.y < 0.0:
			p.y *= 0.15
		pos[i] = p
	# smooth normals: area-weighted face normals accumulated per vertex
	var vn := PackedVector3Array()
	vn.resize(verts.size())
	if not flat:
		for f in range(0, faces.size(), 3):
			var a := pos[faces[f]]; var b := pos[faces[f + 1]]; var c := pos[faces[f + 2]]
			var fnm := (b - a).cross(c - a)
			if fnm.dot(a + b + c) < 0.0:
				fnm = -fnm
			for q in 3:
				vn[faces[f + q]] += fnm
	for f in range(0, faces.size(), 3):
		var a := pos[faces[f]]; var b := pos[faces[f + 1]]; var c := pos[faces[f + 2]]
		if flat:
			_flat_tri(st, xf, a, b, c, (a + b + c))
		else:
			tri(st, xf * a, xf * b, xf * c, _xn(xf, vn[faces[f]]), _xn(xf, vn[faces[f + 1]]), _xn(xf, vn[faces[f + 2]]))


## Flat quad in the local XY plane facing +Z, with 0..1 UVs (stained glass, banners).
func quad(mat: Material, size: Vector2, xf := Transform3D.IDENTITY, shadow: bool = false) -> void:
	var st := surface(mat, shadow)
	var h := size * 0.5
	var a := Vector3(-h.x, -h.y, 0); var b := Vector3(h.x, -h.y, 0)
	var c := Vector3(h.x, h.y, 0); var d := Vector3(-h.x, h.y, 0)
	var n := _xn(xf, Vector3.BACK)
	tri(st, xf * a, xf * b, xf * c, n, n, n, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	tri(st, xf * a, xf * c, xf * d, n, n, n, Vector2(0, 1), Vector2(1, 0), Vector2(0, 0))


## Raw triangle list in prop space (for terrain-like custom geometry).
func triangles(mat: Material, pts: PackedVector3Array, nrm: PackedVector3Array, xf := Transform3D.IDENTITY,
		shadow: bool = true, uvs := PackedVector2Array()) -> void:
	var st := surface(mat, shadow)
	for i in range(0, pts.size() - 2, 3):
		var u0 := uvs[i] if i < uvs.size() else Vector2.ZERO
		var u1 := uvs[i + 1] if i + 1 < uvs.size() else Vector2.ZERO
		var u2 := uvs[i + 2] if i + 2 < uvs.size() else Vector2.ZERO
		tri(st, xf * pts[i], xf * pts[i + 1], xf * pts[i + 2], _xn(xf, nrm[i]), _xn(xf, nrm[i + 1]),
				_xn(xf, nrm[i + 2]), u0, u1, u2)


# ================================================================ collision

func collide_box(size: Vector3, xf := Transform3D.IDENTITY) -> void:
	var s := BoxShape3D.new()
	s.size = size
	_shapes.append([s, xf])


## Upright cylinder standing on xf.origin (not centred).
func collide_cylinder(radius: float, height: float, xf := Transform3D.IDENTITY) -> void:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	_shapes.append([s, xf * Transform3D(Basis(), Vector3(0, height * 0.5, 0))])


func collide_sphere(radius: float, xf := Transform3D.IDENTITY) -> void:
	var s := SphereShape3D.new()
	s.radius = radius
	_shapes.append([s, xf])


func has_collision() -> bool:
	return not _shapes.is_empty()


# ================================================================ output

## Commits everything into `root` (a new Node3D if null): one MeshInstance3D per (material, shadow)
## and one StaticBody3D "Collision" (layer 1) holding the collected shapes. Resets the builder.
func finish(root: Node3D = null) -> Node3D:
	if root == null:
		root = Node3D.new()
	for key: String in _groups:
		var g: Dictionary = _groups[key]
		var mi := MeshInstance3D.new()
		mi.mesh = (g["st"] as SurfaceTool).commit()
		mi.material_override = g["mat"]
		if not g["shadow"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mi)
	if not _shapes.is_empty():
		var body := StaticBody3D.new()
		body.name = "Collision"
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		for s: Array in _shapes:
			var cs := CollisionShape3D.new()
			cs.shape = s[0]
			cs.transform = s[1]
			body.add_child(cs)
		root.add_child(body)
	_groups.clear()
	_shapes.clear()
	return root


## Commits only the meshes into a single ArrayMesh with one surface per material (for MultiMesh
## scatter or caching). Collision shapes are discarded.
func commit_mesh() -> ArrayMesh:
	var am := ArrayMesh.new()
	for key: String in _groups:
		var g: Dictionary = _groups[key]
		(g["st"] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, g["mat"])
	_groups.clear()
	_shapes.clear()
	return am


# ================================================================ helpers

static var _ico_cache := {}

## [vertices (unit sphere), triangle indices] of an icosphere, cached per subdivision level.
static func _icosphere(subdiv: int) -> Array:
	if _ico_cache.has(subdiv):
		return _ico_cache[subdiv]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in v.size():
		v[i] = v[i].normalized()
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
		10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10,
		8, 6, 7, 9, 8, 1])
	for _s in subdiv:
		var mids := {}
		var nf := PackedInt32Array()
		for i in range(0, f.size(), 3):
			var tri_idx := [f[i], f[i + 1], f[i + 2]]
			var m := [0, 0, 0]
			for e in 3:
				# midpoint of edge (e, e+1), shared between the two faces using it
				var a: int = tri_idx[e]
				var b: int = tri_idx[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mids.has(key):
					v.append(((v[a] + v[b]) * 0.5).normalized())
					mids[key] = v.size() - 1
				m[e] = mids[key]
			nf.append_array([tri_idx[0], m[0], m[2], tri_idx[1], m[1], m[0], tri_idx[2], m[2], m[1], m[0], m[1], m[2]])
		f = nf
	_ico_cache[subdiv] = [v, f]
	return _ico_cache[subdiv]


## Integer hash of a lattice point -> 0..1 (cheap, no allocations).
static func _hash3(x: int, y: int, z: int) -> float:
	var h := (x * 374761393 + y * 668265263 + z * 1274126177) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## Smooth value noise in 0..1.
static func _vnoise(p: Vector3) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var iz := floori(p.z)
	var fx := p.x - float(ix)
	var fy := p.y - float(iy)
	var fz := p.z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var x00 := lerpf(_hash3(ix, iy, iz), _hash3(ix + 1, iy, iz), fx)
	var x10 := lerpf(_hash3(ix, iy + 1, iz), _hash3(ix + 1, iy + 1, iz), fx)
	var x01 := lerpf(_hash3(ix, iy, iz + 1), _hash3(ix + 1, iy, iz + 1), fx)
	var x11 := lerpf(_hash3(ix, iy + 1, iz + 1), _hash3(ix + 1, iy + 1, iz + 1), fx)
	return lerpf(lerpf(x00, x10, fy), lerpf(x01, x11, fy), fz)
