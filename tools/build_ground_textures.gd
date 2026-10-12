extends SceneTree
## Bakes the seamless ground textures used by res://scenes/world/ground.gdshader:
##   godot --headless --path . --script res://tools/build_ground_textures.gd
## then run --import (the .import files ask for mipmaps; keep them lossless, no VRAM compression).
##
##   ground_noise.png  512Â²  RGBA = four independent smooth fbm fields (macro variation / layout masks)
##   ground_stone.png  512Â²  RG = detail normal (world x, z), B = height, A = lichen mask
##                            (weathered flagstone: undulation, granite grain, pits, hairline cracks)
##   ground_soil.png   512Â²  RG = detail normal, B = height (soil grit 0..0.3, grass blades 0.35..1),
##                            A = per-blade tint (0.5 on bare soil)
## Everything is float-precision and exactly periodic (no 8-bit noise images), so the normals are smooth.
## Recipes are deterministic (fixed seeds).

const S := 512
const OUT_DIR := "res://assets/textures"
## World size of one texture tile (metres) -- used to scale the baked normals. Keep in sync with
## the shader constants STONE_TILE / SOIL_TILE.
const STONE_TILE := 1.6
const SOIL_TILE := 2.4
const STONE_RELIEF := 0.012	# metres of relief for height 0..1
const SOIL_RELIEF := 0.03


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var t0 := Time.get_ticks_msec()
	_save(_build_noise(), "ground_noise.png")
	_save(_build_stone(), "ground_stone.png")
	_save(_build_soil(), "ground_soil.png")
	print("ground textures built in %d ms" % (Time.get_ticks_msec() - t0))
	quit()


func _save(img: Image, file: String) -> void:
	var path := OUT_DIR.path_join(file)
	img.save_png(ProjectSettings.globalize_path(path))
	print("GROUND ", path)


# ---------------------------------------------------------------- helpers

## Periodic fbm: FastNoiseLite blended over the four tile-shifted copies with variance-preserving
## weights, so the result tiles exactly and keeps the same contrast everywhere. Returns ~N(0, 1).
func _fbm(cycles: float, octaves: int, seed_: int, fractal := FastNoiseLite.FRACTAL_FBM) -> PackedFloat32Array:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = cycles / float(S)
	n.fractal_type = fractal
	n.fractal_octaves = octaves
	var out := PackedFloat32Array()
	out.resize(S * S)
	var fs := float(S)
	for y in S:
		var v := (y + 0.5) / fs
		for x in S:
			var u := (x + 0.5) / fs
			var w00 := (1.0 - u) * (1.0 - v)
			var w10 := u * (1.0 - v)
			var w01 := (1.0 - u) * v
			var w11 := u * v
			var s := n.get_noise_2d(x, y) * w00 + n.get_noise_2d(x - fs, y) * w10 \
					+ n.get_noise_2d(x, y - fs) * w01 + n.get_noise_2d(x - fs, y - fs) * w11
			out[y * S + x] = s / sqrt(w00 * w00 + w10 * w10 + w01 * w01 + w11 * w11)
	return _standardize(out)


func _standardize(a: PackedFloat32Array) -> PackedFloat32Array:
	var mean := 0.0
	for v in a:
		mean += v
	mean /= a.size()
	var vs := 0.0
	for v in a:
		vs += (v - mean) * (v - mean)
	var sd := sqrt(vs / a.size())
	for i in a.size():
		a[i] = (a[i] - mean) / sd
	return a


## Periodic Voronoi with nÃ—n jittered cells. Returns [F1, F2, cell index] per pixel (distances in cell units).
func _voronoi(n: int, seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var pts := PackedVector2Array()
	pts.resize(n * n)
	for j in n:
		for i in n:
			pts[j * n + i] = Vector2(i + rng.randf_range(0.1, 0.9), j + rng.randf_range(0.1, 0.9))
	var f1 := PackedFloat32Array()
	var f2 := PackedFloat32Array()
	var ids := PackedInt32Array()
	f1.resize(S * S)
	f2.resize(S * S)
	ids.resize(S * S)
	var sc := float(n) / S
	for y in S:
		var py := (y + 0.5) * sc
		var cj := int(py)
		for x in S:
			var px := (x + 0.5) * sc
			var ci := int(px)
			var d1 := 99.0
			var d2 := 99.0
			var best := 0
			for dj in range(-1, 2):
				var jj := cj + dj
				var wj := posmod(jj, n)
				for di in range(-1, 2):
					var ii := ci + di
					var wi := posmod(ii, n)
					var q := pts[wj * n + wi]
					var dx := px - (q.x + (ii - wi))
					var dy := py - (q.y + (jj - wj))
					var d := sqrt(dx * dx + dy * dy)
					if d < d1:
						d2 = d1
						d1 = d
						best = wj * n + wi
					elif d < d2:
						d2 = d
			var k := y * S + x
			f1[k] = d1
			f2[k] = d2
			ids[k] = best
	return [f1, f2, ids]


static func _hash(i: int) -> float:
	var h := (i * 374761393 + 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _blur(a: PackedFloat32Array) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(S * S)
	for y in S:
		var ym := posmod(y - 1, S) * S
		var y0 := y * S
		var yp := posmod(y + 1, S) * S
		for x in S:
			var xm := posmod(x - 1, S)
			var xp := posmod(x + 1, S)
			o[y0 + x] = (a[y0 + x] * 4.0 + (a[ym + x] + a[yp + x] + a[y0 + xm] + a[y0 + xp]) * 2.0 \
					+ a[ym + xm] + a[ym + xp] + a[yp + xm] + a[yp + xp]) / 16.0
	return o


func _normalize01(a: PackedFloat32Array) -> PackedFloat32Array:
	var lo := INF
	var hi := -INF
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for i in a.size():
		a[i] = (a[i] - lo) / (hi - lo)
	return a


## Packs height (0..1) + extra channel into RGBA: RG = normal x/z (world), B = height, A = extra.
func _pack(h: PackedFloat32Array, extra: PackedFloat32Array, tile_m: float, relief_m: float, smooth_n := false) -> Image:
	var hn := _blur(h) if smooth_n else h
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	var px_m := tile_m / S
	var k := relief_m / (2.0 * px_m)
	for y in S:
		var ym := posmod(y - 1, S) * S
		var yp := posmod(y + 1, S) * S
		for x in S:
			var dx := (hn[y * S + posmod(x + 1, S)] - hn[y * S + posmod(x - 1, S)]) * k
			var dz := (hn[yp + x] - hn[ym + x]) * k
			var nv := Vector3(-dx, 1.0, -dz).normalized()
			img.set_pixel(x, y, Color(nv.x * 0.5 + 0.5, nv.z * 0.5 + 0.5, h[y * S + x], extra[y * S + x]))
	return img


# ---------------------------------------------------------------- textures

func _build_noise() -> Image:
	var a := _fbm(5.0, 5, 101)
	var b := _fbm(8.0, 4, 202)
	var c := _fbm(4.0, 5, 303)
	var d := _fbm(13.0, 3, 404)
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var k := y * S + x
			# ~N(0,1) -> 0..1 (mean 0.5, Â±2.5 sd)
			img.set_pixel(x, y, Color(clampf(0.5 + a[k] * 0.2, 0.0, 1.0), clampf(0.5 + b[k] * 0.2, 0.0, 1.0),
					clampf(0.5 + c[k] * 0.2, 0.0, 1.0), clampf(0.5 + d[k] * 0.2, 0.0, 1.0)))
	return img


func _build_stone() -> Image:
	var und := _fbm(3.0, 4, 11)	# broad undulation / worn hollows
	var grain := _fbm(38.0, 3, 23)	# granite grain
	var speck := _fbm(150.0, 2, 37)	# fine speckle
	var lich := _fbm(7.0, 4, 41)	# lichen patch field
	var pits := _voronoi(26, 5)
	var crk := _voronoi(4, 9)
	var crk_mask := _fbm(5.0, 3, 53)
	var h := PackedFloat32Array()
	var a := PackedFloat32Array()
	h.resize(S * S)
	a.resize(S * S)
	var pf1: PackedFloat32Array = pits[0]
	var pid: PackedInt32Array = pits[2]
	var cf1: PackedFloat32Array = crk[0]
	var cf2: PackedFloat32Array = crk[1]
	for k in S * S:
		var v := und[k] * 0.3 + grain[k] * 0.14 + speck[k] * 0.06
		# pits: a quarter of the small cells hold a rounded weathering pit
		var ph := _hash(pid[k] + 17)
		if ph < 0.28:
			var r := 0.12 + 0.2 * _hash(pid[k] + 3)
			v -= (1.0 - _sstep(r * 0.4, r, pf1[k])) * 0.45
		# hairline cracks along big-cell borders, only where the mask allows (open-ended cracks)
		var edge := cf2[k] - cf1[k]
		var cm := _sstep(0.2, 0.9, crk_mask[k])
		v -= (1.0 - _sstep(0.0, 0.035, edge)) * 0.6 * cm
		v -= (1.0 - _sstep(0.0, 0.12, edge)) * 0.12 * cm
		h[k] = v
		# lichen rosettes in some small cells, clustered by the patch field
		var lc := 0.0
		var lh := _hash(pid[k] + 91)
		if lh < 0.5 * _sstep(-0.2, 1.2, lich[k]):
			var lr := 0.35 + 0.3 * _hash(pid[k] + 7)
			lc = 1.0 - _sstep(lr * 0.6, lr, pf1[k])
		a[k] = clampf(maxf(lc, _sstep(0.9, 1.8, lich[k]) * 0.6), 0.0, 1.0)
	h = _normalize01(h)
	return _pack(h, a, STONE_TILE, STONE_RELIEF)


func _build_soil() -> Image:
	var grit := _fbm(45.0, 3, 61)
	var clod := _fbm(9.0, 4, 67)
	var clump := _fbm(7.0, 4, 71)	# grass density field
	var stones := _voronoi(36, 73)
	var sf1: PackedFloat32Array = stones[0]
	var sid: PackedInt32Array = stones[2]
	var h := PackedFloat32Array()
	var tint := PackedFloat32Array()
	h.resize(S * S)
	tint.resize(S * S)
	for k in S * S:
		var v := 0.1 + grit[k] * 0.025 + clod[k] * 0.04
		# grit & small pebbles
		if _hash(sid[k] + 5) < 0.3:
			var r := 0.15 + 0.15 * _hash(sid[k] + 9)
			var d := sf1[k] / r
			if d < 1.0:
				v = maxf(v, 0.12 + 0.12 * sqrt(1.0 - d * d))
		h[k] = clampf(v, 0.0, 0.3)
		tint[k] = 0.5
	# grass blades: short strokes, combed by a prevailing wind, denser in clumps
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var blades := 52000
	var wind := 0.5
	for i in blades:
		var x0 := rng.randf() * S
		var y0 := rng.randf() * S
		var dens := _sstep(-2.2, 0.7, clump[int(y0) * S + int(x0)])
		if rng.randf() > dens:
			continue
		var ang := wind + rng.randfn(0.0, 0.9)
		var dir := Vector2(cos(ang), sin(ang))
		var length := rng.randf_range(5.0, 15.0) * (0.6 + 0.5 * dens)
		var top := rng.randf_range(0.55, 1.0) * (0.75 + 0.25 * dens)
		var t_val := rng.randf_range(0.0, 1.0)
		var wide := rng.randf() < 0.35
		var steps := int(length * 1.5) + 1
		var side := Vector2(-dir.y, dir.x)
		for s in steps:
			var t := float(s) / steps
			var hv := 0.33 + (top - 0.33) * (1.0 - (1.0 - t) * (1.0 - t))
			var pp := Vector2(x0, y0) + dir * (t * length)
			_plot(h, tint, int(floor(pp.x)), int(floor(pp.y)), hv, t_val)
			if wide and t < 0.7:
				var p2 := pp + side * 0.9
				_plot(h, tint, int(floor(p2.x)), int(floor(p2.y)), hv * 0.97, t_val)
	return _pack(h, tint, SOIL_TILE, SOIL_RELIEF, true)


func _plot(h: PackedFloat32Array, tint: PackedFloat32Array, x: int, y: int, v: float, t: float) -> void:
	var k := posmod(y, S) * S + posmod(x, S)
	if v > h[k]:
		h[k] = v
		tint[k] = t
