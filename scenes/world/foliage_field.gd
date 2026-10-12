class_name FoliageField
extends RefCounted
## CPU port of the ground shader's layout noise (res://scenes/world/ground.gdshader): flagstone
## roads, plazas, dry grass drift, dirt, mud, ash fields and moss hollows. Used by foliage.gd so the
## plants grow where the ground looks like it would grow them (and stay off the stones).
##
## The shader's hash is chaotic, so the GPU's float32 math is emulated (PackedFloat32Array rounding).
## GPU compilers still fuse / reassociate some operations, so a few lattice cells differ from the GPU:
## treat the result as a very close approximation and keep a safety margin around stone.
## Not thread-safe per instance: give each worker thread its own FoliageField.

const ROAD_SCALE := 0.017
const ROAD_WIDTH := 0.03
const PLAZA_CELL := 40.0
const PLAZA_CHANCE := 0.45
const ORIGIN_PLAZA_RADIUS := 7.0

var _b := PackedFloat32Array([0.0])
var _c1: float
var _c2: float
var _c3: float
var _cache := {}


func _init() -> void:
	_c1 = _f(123.34)
	_c2 = _f(456.21)
	_c3 = _f(45.32)


func _f(x: float) -> float:
	_b[0] = x
	return _b[0]


func hash21(x: float, y: float) -> float:
	var px := _f(x * _c1)
	px -= floorf(px)
	var py := _f(y * _c2)
	py -= floorf(py)
	var d := _f(_f(px * _f(px + _c3)) + _f(py * _f(py + _c3)))
	px = _f(px + d)
	py = _f(py + d)
	var r := _f(px * py)
	return r - floorf(r)


## hash21 of an integer lattice point, cached.
func _lh(ix: int, iy: int) -> float:
	var key := (ix << 32) ^ (iy & 0xFFFFFFFF)
	var v: Variant = _cache.get(key)
	if v != null:
		return v
	var h := hash21(float(ix), float(iy))
	if _cache.size() > 400000:
		_cache.clear()
	_cache[key] = h
	return h


func vnoise(x: float, y: float) -> float:
	var fx := floorf(x)
	var fy := floorf(y)
	var ix := int(fx)
	var iy := int(fy)
	var tx := x - fx
	var ty := y - fy
	var ux := tx * tx * (3.0 - 2.0 * tx)
	var uy := ty * ty * (3.0 - 2.0 * ty)
	var a := _lh(ix, iy)
	var b := _lh(ix + 1, iy)
	var c := _lh(ix, iy + 1)
	var d := _lh(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)


func fbm(x: float, y: float) -> float:
	var s := 0.0
	var a := 0.5
	for i in 4:
		s += a * vnoise(x, y)
		var nx := 1.6 * x - 1.2 * y + 3.1
		var ny := 1.2 * x + 1.6 * y + 7.7
		x = nx
		y = ny
		a *= 0.5
	return s / 0.9375


static func _ss(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Road mask (1 on the flagstones). `wide` variant returns the dirt verge halo instead.
func road(x: float, z: float, wide: bool = false) -> float:
	var qx := x * ROAD_SCALE
	var qz := z * ROAD_SCALE
	var wx := fbm(qx * 1.7 + 11.0, qz * 1.7 + 11.0)
	var wz := fbm(qx * 1.7 - 7.0, qz * 1.7 - 7.0)
	var n := fbm(qx + (wx - 0.5) * 0.7, qz + (wz - 0.5) * 0.7)
	var d := absf(n - 0.5)
	if wide:
		return 1.0 - _ss(ROAD_WIDTH, ROAD_WIDTH * 2.4, d)
	return 1.0 - _ss(ROAD_WIDTH * 0.45, ROAD_WIDTH, d)


## Plaza: Vector3(mask, distance from plaza centre, plaza radius).
func plaza(x: float, z: float) -> Vector3:
	var best := 0.0
	var dist := 1000.0
	var radius := 1.0
	var r0 := Vector2(x, z).length()
	if r0 < ORIGIN_PLAZA_RADIUS + 0.5:
		dist = r0
		radius = ORIGIN_PLAZA_RADIUS
		best = 1.0 - _ss(radius - 1.8, radius + 0.2, r0)
	var cx := floorf(x / PLAZA_CELL)
	var cz := floorf(z / PLAZA_CELL)
	var near_origin := absf(cx + 0.5) < 1.0 and absf(cz + 0.5) < 1.0
	if not near_origin and hash21(_f(cx + 0.37), _f(cz + 0.37)) < PLAZA_CHANCE:
		var sx := _f(cx + 5.1)
		var sz := _f(cz + 5.1)
		var hx := hash21(sx, sz)
		var hz := hash21(_f(sx + 17.17), _f(sz + 3.71))
		var px := (cx + 0.3 + 0.4 * hx) * PLAZA_CELL
		var pz := (cz + 0.3 + 0.4 * hz) * PLAZA_CELL
		var rad := lerpf(4.5, 8.0, hash21(_f(cx + 2.9), _f(cz + 2.9)))
		var r := Vector2(x - px, z - pz).length()
		var m := 1.0 - _ss(rad - 2.0, rad + 0.2, r)
		if m > best:
			best = m
			dist = r
			radius = rad
	return Vector3(best, dist, radius)


## Macro noise texture the ground shader samples for its soil zones (see ground.gdshader "macro fields").
const NOISE_TEX_PATH := "res://assets/textures/ground_noise.png"
var _noise: Image
var _nw := 1
var _nh := 1


func _load_noise() -> void:
	if _noise != null:
		return
	var noise_tex := load(NOISE_TEX_PATH) as Texture2D
	if noise_tex:
		_noise = noise_tex.get_image()
		if _noise and _noise.is_compressed():
			_noise.decompress()
	if _noise == null:
		_noise = Image.create(4, 4, false, Image.FORMAT_RGBA8)
		_noise.fill(Color(0.5, 0.5, 0.5, 0.5))
	_nw = _noise.get_width()
	_nh = _noise.get_height()


## Bilinear, repeating texture lookup at uv (like texture() with repeat_enable at mip 0).
func tex(u: float, v: float) -> Color:
	var x := u * _nw - 0.5
	var y := v * _nh - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var xa := posmod(x0, _nw)
	var xb := posmod(x0 + 1, _nw)
	var ya := posmod(y0, _nh)
	var yb := posmod(y0 + 1, _nh)
	var c0 := _noise.get_pixel(xa, ya).lerp(_noise.get_pixel(xb, ya), fx)
	var c1 := _noise.get_pixel(xa, yb).lerp(_noise.get_pixel(xb, yb), fx)
	return c0.lerp(c1, fy)


## Soil zones at world (x, z), mirroring ground.gdshader:
##   dry (sun-dried grass), lush, dirt, ash, moss (cushions), relief (macro height: water and mud
##   gather below ~0.4, puddles below ~0.16-0.34 depending on wetness), mud.
func zones(x: float, z: float) -> Dictionary:
	_load_noise()
	var nA := tex(x / 113.0, z / 113.0)
	var nB := tex(x / 31.0 + 0.37, z / 31.0 + 0.61)
	var c := cos(0.7)
	var s := sin(0.7)
	var nC := tex((c * x - s * z) / 7.3 + 0.13, (s * x + c * z) / 7.3 + 0.71)
	var relief := nA.b * 0.65 + nB.r * 0.35
	var mud_lvl := _ss(0.42, 0.28, relief) * 1.25 - 0.1 + (nC.a - 0.5) * 0.3
	return {
		"dry": _ss(0.56, 0.76, nA.r),
		"lush": _ss(0.3, 0.7, nB.g * 0.7 + nC.g * 0.3),
		"dirt": _ss(0.6, 0.76, nB.a * 0.55 + nA.r * 0.25 + nC.b * 0.2),
		"ash": _ss(0.6, 0.72, nA.a * 0.8 + nB.b * 0.2),
		"moss": _ss(0.6, 0.74, nA.g * 0.75 + nC.a * 0.25),
		"relief": relief,
		"mud": _ss(0.2, 0.6, mud_lvl),
		"leaf": _ss(0.42, 0.72, nB.r * 0.6 + nC.g * 0.4),
	}


## Flagstone coverage (road or plaza, 0..1) and the dirt verge around it (0..1), as Vector2.
func stone(x: float, z: float) -> Vector2:
	var pl := plaza(x, z)
	var qx := x * ROAD_SCALE
	var qz := z * ROAD_SCALE
	var wx := fbm(qx * 1.7 + 11.0, qz * 1.7 + 11.0)
	var wz := fbm(qx * 1.7 - 7.0, qz * 1.7 - 7.0)
	var n := fbm(qx + (wx - 0.5) * 0.7, qz + (wz - 0.5) * 0.7)
	var d := absf(n - 0.5)
	var road_m := 1.0 - _ss(ROAD_WIDTH * 0.45, ROAD_WIDTH, d)
	var wide := 1.0 - _ss(ROAD_WIDTH, ROAD_WIDTH * 2.4, d)
	return Vector2(maxf(road_m, pl.x), maxf(wide, _ss(pl.z + 2.5, pl.z - 0.5, pl.y)))
