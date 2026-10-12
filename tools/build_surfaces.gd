extends SceneTree
## Generates the seamless surface-detail textures used by the lit shader (detail_tex):
##   godot --headless --path . --script res://tools/build_surfaces.gd [-- --only=stone,metal]
##         [--out=<abs dir>] [--preview=<abs dir>]
## Writes res://assets/textures/surf_<type>.png with R = height (0..1), G = roughness variation
## (0.5 = none), B = height. Run --import afterwards (the .import files enable mipmaps).
## Everything is built from strictly periodic primitives (lattice value-noise upsampled with a
## wrapped cubic, periodic Worley, wrapped line/shape stamps), so every tile is exactly seamless.
## Recipes are deterministic (fixed seeds). --preview writes a lit 2x2-tiled sheet per type.

const OUT_DIR := "res://assets/textures"
## Type -> texture size. Hero types (large/close surfaces) are 1024.
const SIZES := {
	&"stone": 1024, &"metal": 1024, &"gold": 512, &"cloth": 1024, &"leather": 1024, &"skin": 1024,
	&"bone": 1024, &"feather": 1024, &"wood": 1024, &"crystal": 512, &"marble": 1024,
	&"chainmail": 1024, &"scales": 1024, &"rust": 512, &"moss_rock": 1024, &"parchment": 512,
	&"rope": 512,
}

var N := 512
var NN := N * N
var S := 0.5 ## pixel-size factor relative to 1024 (feature widths are authored for 1024)


func _init() -> void:
	var only: PackedStringArray = []
	var out_dir := ProjectSettings.globalize_path(OUT_DIR)
	var preview := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--preview="):
			preview = a.substr(10)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for t: StringName in SIZES:
		if not only.is_empty() and not only.has(String(t)):
			continue
		N = SIZES[t]
		NN = N * N
		S = N / 1024.0
		var t0 := Time.get_ticks_msec()
		var hr: Array = call("_" + String(t))
		var img := _pack(hr[0], hr[1])
		img.save_png(out_dir.path_join("surf_%s.png" % t))
		if preview != "":
			var sheets := _preview(hr[0], hr[1])
			sheets[0].save_png(preview.path_join("prev_%s.png" % t))
			sheets[1].save_png(preview.path_join("prev_%s_crop.png" % t))
		print("SURFACE %s %dpx %d ms" % [t, N, Time.get_ticks_msec() - t0])
	quit()


# ---------------------------------------------------------------- primitives

## Periodic value noise: px*py random lattice upsampled to N*N with a wrapped bicubic.
## px != py gives anisotropic streaks (px small = long features along x).
func _vnoise(px: int, py: int, seed_: int) -> PackedFloat32Array:
	px = mini(px, N)
	py = mini(py, N)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var v := PackedFloat32Array()
	v.resize(px * py)
	for i in px * py:
		v[i] = rng.randf()
	if px == N and py == N:
		return v
	# Pad with wrapped lattice values; when the period doesn't divide N, pad a whole tile so the
	# resized image is exactly 3 periods (keeps the result exactly N-periodic).
	var padx := 2 if N % px == 0 else px
	var pady := 2 if N % py == 0 else py
	var w := px + 2 * padx
	var h := py + 2 * pady
	var src := PackedFloat32Array()
	src.resize(w * h)
	for y in h:
		var row := posmod(y - pady, py) * px
		for x in w:
			src[y * w + x] = v[row + posmod(x - padx, px)]
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, src.to_byte_array())
	@warning_ignore("integer_division")
	img.resize(w * N / px, h * N / py, Image.INTERPOLATE_CUBIC)
	@warning_ignore("integer_division")
	img = img.get_region(Rect2i(padx * N / px, pady * N / py, N, N))
	return img.get_data().to_float32_array()


## Fractal sum of periodic value noise, standardized to mean 0.5 / std 0.17.
func _fbm(period: int, octaves: int, seed_: int, gain := 0.5, ax := 1, ay := 1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(NN)
	var amp := 1.0
	for o in octaves:
		var layer := _vnoise(period * ax << o, period * ay << o, seed_ + o * 1013)
		for i in NN:
			out[i] += layer[i] * amp
		amp *= gain
	return _fit(out, 0.5, 0.17)


## Remaps to the given mean/std (no clamping).
func _fit(a: PackedFloat32Array, mean: float, std: float) -> PackedFloat32Array:
	var m := 0.0
	for i in NN:
		m += a[i]
	m /= NN
	var v := 0.0
	for i in NN:
		v += (a[i] - m) * (a[i] - m)
	var k := std / maxf(sqrt(v / NN), 1e-6)
	for i in NN:
		a[i] = mean + (a[i] - m) * k
	return a


## Periodic Worley. Returns f1 (px), edge (px distance to the nearest cell border), k (cell index),
## dx/dy (offset from the nearest feature point, px), and per-cell rnd/rnd2/rnd3 in 0..1.
func _worley(cells: int, seed_: int, jitter := 1.0, wx := PackedFloat32Array(),
		wy := PackedFloat32Array(), wamt := 0.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var cs := float(N) / cells
	var nc := cells * cells
	var ptx := _arr(nc)
	var pty := _arr(nc)
	var rnd := _arr(nc)
	var rnd2 := _arr(nc)
	var rnd3 := _arr(nc)
	for j in cells:
		for i in cells:
			var k := j * cells + i
			ptx[k] = (i + 0.5 + (rng.randf() - 0.5) * jitter) * cs
			pty[k] = (j + 0.5 + (rng.randf() - 0.5) * jitter) * cs
			rnd[k] = rng.randf()
			rnd2[k] = rng.randf()
			rnd3[k] = rng.randf()
	var f1 := _new()
	var edge := _new()
	var ox := _new()
	var oy := _new()
	var kk := PackedInt32Array()
	kk.resize(NN)
	var warped := wamt > 0.0
	for y in N:
		for x in N:
			var i := y * N + x
			var fx := x + 0.5
			var fy := y + 0.5
			if warped:
				fx += (wx[i] - 0.5) * wamt
				fy += (wy[i] - 0.5) * wamt
			var ci := floori(fx / cs)
			var cj := floori(fy / cs)
			var d1 := INF
			var d2 := INF
			var b1x := 0.0
			var b1y := 0.0
			var b2x := 0.0
			var b2y := 0.0
			var k1 := 0
			for dj in 3:
				var jj := cj + dj - 1
				var wj := posmod(jj, cells)
				var offy := (jj - wj) * cs
				for di in 3:
					var ii := ci + di - 1
					var wi := posmod(ii, cells)
					var k := wj * cells + wi
					var qx := ptx[k] + (ii - wi) * cs
					var qy := pty[k] + offy
					var d := (qx - fx) * (qx - fx) + (qy - fy) * (qy - fy)
					if d < d1:
						d2 = d1
						b2x = b1x
						b2y = b1y
						d1 = d
						b1x = qx
						b1y = qy
						k1 = k
					elif d < d2:
						d2 = d
						b2x = qx
						b2y = qy
			f1[i] = sqrt(d1)
			var sep := sqrt((b2x - b1x) * (b2x - b1x) + (b2y - b1y) * (b2y - b1y))
			edge[i] = (d2 - d1) / maxf(2.0 * sep, 1e-4)
			ox[i] = fx - b1x
			oy[i] = fy - b1y
			kk[i] = k1
	return {"f1": f1, "edge": edge, "k": kk, "dx": ox, "dy": oy, "rnd": rnd, "rnd2": rnd2,
		"rnd3": rnd3, "cs": cs}


## Separable wrapped box blur (2 passes ~ gaussian).
func _blur(a: PackedFloat32Array, r: int) -> PackedFloat32Array:
	if r < 1:
		return a
	var tmp := PackedFloat32Array()
	tmp.resize(NN)
	var inv := 1.0 / (2 * r + 1)
	for _pass in 2:
		for y in N:
			var row := y * N
			var s := 0.0
			for k in range(-r, r + 1):
				s += a[row + posmod(k, N)]
			for x in N:
				tmp[row + x] = s * inv
				s += a[row + posmod(x + r + 1, N)] - a[row + posmod(x - r, N)]
		for x in N:
			var s := 0.0
			for k in range(-r, r + 1):
				s += tmp[posmod(k, N) * N + x]
			for y in N:
				a[y * N + x] = s * inv
				s += tmp[posmod(y + r + 1, N) * N + x] - tmp[posmod(y - r, N) * N + x]
	return a


## Wrapped bilinear sample.
func _samp(a: PackedFloat32Array, fx: float, fy: float) -> float:
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - x0
	var ty := fy - y0
	var xa := posmod(x0, N)
	var xb := posmod(x0 + 1, N)
	var ya := posmod(y0, N) * N
	var yb := posmod(y0 + 1, N) * N
	return lerpf(lerpf(a[ya + xa], a[ya + xb], tx), lerpf(a[yb + xa], a[yb + xb], tx), ty)


## Stamps a wrapped, tapered line segment into `m` (max-blend). Profile 1 at the centre -> 0 at w.
func _line(m: PackedFloat32Array, x0: float, y0: float, x1: float, y1: float, w: float,
		strength: float, taper := true) -> void:
	var lx := x1 - x0
	var ly := y1 - y0
	var l2 := maxf(lx * lx + ly * ly, 1e-4)
	var bx0 := floori(minf(x0, x1) - w - 1.0)
	var bx1 := ceili(maxf(x0, x1) + w + 1.0)
	var by0 := floori(minf(y0, y1) - w - 1.0)
	var by1 := ceili(maxf(y0, y1) + w + 1.0)
	for y in range(by0, by1 + 1):
		for x in range(bx0, bx1 + 1):
			var t := clampf(((x - x0) * lx + (y - y0) * ly) / l2, 0.0, 1.0)
			var dx := x - (x0 + lx * t)
			var dy := y - (y0 + ly * t)
			var d := sqrt(dx * dx + dy * dy)
			if d >= w:
				continue
			var p := 1.0 - smoothstep(0.0, w, d)
			if taper:
				p *= sqrt(sin(PI * t))
			var i := posmod(y, N) * N + posmod(x, N)
			m[i] = maxf(m[i], p * strength)


## Random scratches (angle spread around `angle`, `cross` = fraction at any angle).
func _scratches(count: int, seed_: int, angle: float, spread: float, cross: float, len_min: float,
		len_max: float, w_min: float, w_max: float) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(NN)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for _i in count:
		var a := angle + rng.randfn(0.0, spread)
		if rng.randf() < cross:
			a = rng.randf() * TAU
		var l := rng.randf_range(len_min, len_max) * S
		var x := rng.randf() * N
		var y := rng.randf() * N
		_line(m, x, y, x + cos(a) * l, y + sin(a) * l, rng.randf_range(w_min, w_max) * maxf(S, 0.6),
			rng.randf_range(0.35, 1.0))
	return m


## Wrapped signed distance helper.
func _wrapd(d: float) -> float:
	return d - roundf(d / N) * N


func _new() -> PackedFloat32Array:
	return _arr(NN)


func _arr(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	return a


func _pack(h: PackedFloat32Array, r: PackedFloat32Array) -> Image:
	var data := PackedByteArray()
	data.resize(NN * 4)
	for i in NN:
		var hv := int(clampf(h[i], 0.0, 1.0) * 255.0 + 0.5)
		data[i * 4] = hv
		data[i * 4 + 1] = int(clampf(r[i], 0.0, 1.0) * 255.0 + 0.5)
		data[i * 4 + 2] = hv
		data[i * 4 + 3] = 255
	return Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, data)


## Lit 2x2-tiled preview (albedo modulation like lit_common + lambert from the height gradient).
func _preview(h: PackedFloat32Array, r: PackedFloat32Array) -> Array:
	var data := PackedByteArray()
	data.resize(NN * 3)
	var k := 6.0 * S
	var ld := Vector3(-0.55, -0.6, 0.58).normalized()
	for y in N:
		for x in N:
			var i := y * N + x
			var gx := (h[y * N + posmod(x + 1, N)] - h[y * N + posmod(x - 1, N)]) * 255.0 / 40.0 / k
			var gy := (h[posmod(y + 1, N) * N + x] - h[posmod(y - 1, N) * N + x]) * 255.0 / 40.0 / k
			var n := Vector3(-gx, -gy, 1.0).normalized()
			var alb := lerpf(0.55, 1.12, clampf(h[i], 0.0, 1.0)) * 0.62
			var spec := pow(maxf(n.dot((ld + Vector3(0, 0, 1)).normalized()), 0.0), 40.0) * (1.0 - clampf(r[i], 0.0, 1.0)) * 0.6
			var c := clampf(alb * (0.25 + 0.85 * maxf(n.dot(ld), 0.0)) + spec, 0.0, 1.0)
			var b := int(c * 255.0)
			data[i * 3] = b
			data[i * 3 + 1] = b
			data[i * 3 + 2] = int(clampf(c * 0.92 + 0.02, 0.0, 1.0) * 255.0)
	var one := Image.create_from_data(N, N, false, Image.FORMAT_RGB8, data)
	var sheet := Image.create_empty(N * 2, N * 2, false, Image.FORMAT_RGB8)
	for j in 2:
		for i in 2:
			sheet.blit_rect(one, Rect2i(0, 0, N, N), Vector2i(i * N, j * N))
	var crop := sheet.get_region(Rect2i(N - 256, N - 256, 512, 512))
	if N > 512:
		sheet.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	return [sheet, crop]


# ---------------------------------------------------------------- recipes (return [height, rough])

## Weathered stone: tilted slabs split by a warped crack network at three scales (masked so the
## finer ones only appear in places), rounded/eroded crack lips, pitting and grain.
func _stone_layers(seed_: int) -> Array:
	var base := _fbm(3, 7, seed_ + 1, 0.55)
	var med := _fbm(12, 4, seed_ + 2, 0.5)
	var grit := _fbm(160, 2, seed_ + 3, 0.6)
	var wx := _fbm(4, 7, seed_ + 4, 0.6)
	var wy := _fbm(4, 7, seed_ + 5, 0.6)
	var big := _worley(4, seed_ + 21, 1.0, wx, wy, N * 0.09)
	var mid := _worley(10, seed_ + 22, 1.0, wx, wy, N * 0.05)
	var hair := _worley(24, seed_ + 23, 1.0, wx, wy, N * 0.025)
	var mmid := _fbm(4, 3, seed_ + 31)
	var mhair := _fbm(5, 3, seed_ + 32)
	var pits := _worley(56, seed_ + 41)
	var pmask := _fbm(6, 3, seed_ + 42)
	var cw := _fbm(8, 3, seed_ + 43)
	var mbig := _fbm(3, 4, seed_ + 45)
	var pock := _worley(9, seed_ + 46)
	var pkf: PackedFloat32Array = pock.f1
	var pkk: PackedInt32Array = pock.k
	var pkr: PackedFloat32Array = pock.rnd
	var pkcs: float = pock.cs
	var chis := _vnoise(40, 40, seed_ + 44)
	var be: PackedFloat32Array = big.edge
	var me: PackedFloat32Array = mid.edge
	var he: PackedFloat32Array = hair.edge
	var bk: PackedInt32Array = big.k
	var br: PackedFloat32Array = big.rnd
	var mk: PackedInt32Array = mid.k
	var mr: PackedFloat32Array = mid.rnd
	var pf: PackedFloat32Array = pits.f1
	var pk: PackedInt32Array = pits.k
	var pr: PackedFloat32Array = pits.rnd
	var pcs: float = pits.cs
	var h := _new()
	var r := _new()
	var crack := _new()
	var lips := _new()
	for i in NN:
		var wv := 0.35 + cw[i] * 1.5 # crack width varies along its length
		var ab := smoothstep(0.3, 0.46, mbig[i])
		var cb := (1.0 - smoothstep(0.0, 3.4 * S * wv + 0.3, be[i])) * ab
		var lb := (1.0 - smoothstep(0.0, 22.0 * S * wv, be[i])) * ab
		var am := smoothstep(0.5, 0.64, mmid[i])
		var cm := (1.0 - smoothstep(0.0, 1.8 * S * wv + 0.3, me[i])) * am
		var lm := (1.0 - smoothstep(0.0, 10.0 * S, me[i])) * am
		var ch := (1.0 - smoothstep(0.0, 1.1 * S + 0.4, he[i])) * smoothstep(0.62, 0.74, mhair[i])
		var pit := 0.0
		var pid := pr[pk[i]]
		if pid < 0.45 * smoothstep(0.3, 0.7, pmask[i]) + 0.08:
			var rad := (0.12 + pid * 0.35) * pcs
			pit = pow(maxf(1.0 - pf[i] / rad, 0.0), 0.6)
		var pocket := 0.0
		if pkr[pkk[i]] < 0.3:
			var tq := maxf(1.0 - pkf[i] / ((0.2 + pkr[pkk[i]] * 0.5) * pkcs), 0.0)
			pocket = tq * tq * (3.0 - 2.0 * tq)
		var slab := -pocket * 0.22 + (br[bk[i]] - 0.5) * 0.16 * ab + (mr[mk[i]] - 0.5) * 0.06 * am
		var chisel := 1.0 - absf(chis[i] * 2.0 - 1.0)
		var v := 0.5 + (base[i] - 0.5) * 0.75 + (med[i] - 0.5) * 0.42 + (grit[i] - 0.5) * 0.2 + slab 			+ chisel * 0.08
		v -= lb * lb * 0.28 + lm * lm * 0.14 # eroded, rounded lips
		v -= cb * 0.55 + cm * 0.35 + ch * 0.16 + pit * 0.3
		h[i] = v
		crack[i] = maxf(maxf(cb, cm), ch)
		lips[i] = lb
		r[i] = 0.5 + (grit[i] - 0.5) * 0.45 - (base[i] - 0.5) * 0.35 + crack[i] * 0.35 + pit * 0.3 + lb * 0.1
	return [h, r, crack, lips]


func _stone() -> Array:
	var l := _stone_layers(100)
	return [_fit(l[0], 0.6, 0.15), l[1]]


## Brushed steel: streaks along X, scratches mostly following the brushing, dents, patchy wear and
## clustered rust pitting.
func _metal() -> Array:
	var b1 := _vnoise(6, 512, 201)
	var b2 := _vnoise(24, 1024, 202)
	var b3 := _vnoise(2, 128, 203)
	var wear := _fbm(4, 5, 204)
	var fine := _fbm(64, 3, 205)
	var scr := _scratches(320, 206, 0.0, 0.08, 0.22, 20.0, 260.0, 0.8, 1.6)
	var nick := _scratches(90, 207, 0.0, 0.5, 1.0, 4.0, 22.0, 1.0, 2.2)
	var dents := _worley(7, 208)
	var pits := _worley(110, 209)
	var pmask := _fbm(5, 5, 210)
	var df: PackedFloat32Array = dents.f1
	var dk: PackedInt32Array = dents.k
	var dr: PackedFloat32Array = dents.rnd
	var dcs: float = dents.cs
	var pf: PackedFloat32Array = pits.f1
	var pk: PackedInt32Array = pits.k
	var pr: PackedFloat32Array = pits.rnd
	var pcs: float = pits.cs
	var h := _new()
	var r := _new()
	for i in NN:
		var brush := (b1[i] - 0.5) * 0.6 + (b2[i] - 0.5) * 0.5 + (b3[i] - 0.5) * 0.4
		var dent := 0.0
		if dr[dk[i]] < 0.45:
			var rad := (0.25 + dr[dk[i]] * 0.6) * dcs
			var t := maxf(1.0 - df[i] / rad, 0.0)
			dent = t * t * (3.0 - 2.0 * t)
		var rm := smoothstep(0.56, 0.74, pmask[i])
		var pit := 0.0
		if pr[pk[i]] < 0.25 + rm * 0.6:
			pit = pow(maxf(1.0 - pf[i] / ((0.15 + pr[pk[i]] * 0.3) * pcs), 0.0), 0.7) * (0.25 + rm)
		var s := maxf(scr[i], nick[i] * 1.3)
		h[i] = 0.62 + brush * 0.1 + (wear[i] - 0.5) * 0.16 + (fine[i] - 0.5) * 0.04 - s * 0.3 \
			- dent * 0.1 - pit * 0.32 - rm * 0.05
		r[i] = 0.5 + brush * 0.45 + (wear[i] - 0.5) * 0.5 - scr[i] * 0.3 + nick[i] * 0.1 + rm * 0.28 + pit * 0.2
	return [h, r]


## Aged gold: softly hammered facets, tarnish collecting in broad patches, fine polish scratches,
## a few dings.
func _gold() -> Array:
	var ham := _worley(18, 301, 0.9)
	var tarn := _fbm(3, 6, 302, 0.55)
	var tarn2 := _fbm(14, 3, 303)
	var fine := _fbm(48, 3, 304)
	var scr := _scratches(140, 305, 0.3, 1.2, 0.5, 10.0, 90.0, 0.6, 1.1)
	var dings := _worley(9, 306)
	var hf: PackedFloat32Array = ham.f1
	var hcs: float = ham.cs
	var df: PackedFloat32Array = dings.f1
	var dk: PackedInt32Array = dings.k
	var dr: PackedFloat32Array = dings.rnd
	var dcs: float = dings.cs
	var h := _new()
	var r := _new()
	for i in NN:
		var dimple := hf[i] / hcs # 0 at centre (dimpled) .. ~0.7 at ridges
		var t := smoothstep(0.45, 0.72, tarn[i] + (tarn2[i] - 0.5) * 0.35)
		var ding := 0.0
		if dr[dk[i]] < 0.3:
			ding = pow(maxf(1.0 - df[i] / ((0.08 + dr[dk[i]] * 0.25) * dcs), 0.0), 1.5)
		h[i] = 0.64 + dimple * 0.14 - t * 0.24 + (fine[i] - 0.5) * 0.05 - scr[i] * 0.12 - ding * 0.2
		r[i] = 0.42 + t * 0.45 + (fine[i] - 0.5) * 0.18 - scr[i] * 0.15 + (tarn2[i] - 0.5) * 0.15
	return [h, r]


## Plain weave with round threads, per-thread thickness wobble, slubs (thick lumps), fibre fuzz,
## frayed/worn patches and broad folds.
func _cloth() -> Array:
	var T := 112.0 # threads per tile
	var sw := _vnoise(112, 10, 401) # warp thickness wobble (per thread, along y)
	var sf := _vnoise(10, 112, 402) # weft
	var slw := _vnoise(112, 40, 403)
	var slf := _vnoise(40, 112, 404)
	var fibw := _vnoise(512, 48, 405) # fibre streaks along y
	var fibf := _vnoise(48, 512, 406)
	var worn := _fbm(4, 5, 407)
	var fold := _fbm(2, 4, 408, 0.45)
	var fuzz := _fbm(256, 2, 409)
	var h := _new()
	var r := _new()
	for y in N:
		var v := (y + 0.5) * T / N
		var tj := floori(v)
		var fv := v - tj
		for x in N:
			var i := y * N + x
			var u := (x + 0.5) * T / N
			var ti := floori(u)
			var fu := u - ti
			var slub_w := smoothstep(0.72, 0.9, slw[i])
			var slub_f := smoothstep(0.72, 0.9, slf[i])
			var tw := 0.78 + (sw[i] - 0.5) * 0.3 + slub_w * 0.3
			var tf := 0.78 + (sf[i] - 0.5) * 0.3 + slub_f * 0.3
			var aw := (fu - 0.5) * 2.0 / tw
			var af := (fv - 0.5) * 2.0 / tf
			var pw := sqrt(maxf(1.0 - aw * aw, 0.0))
			var pf := sqrt(maxf(1.0 - af * af, 0.0))
			var ow := 0.5 + 0.5 * sin(PI * (v + ti))
			var of := 0.5 - 0.5 * sin(PI * (u + tj))
			var hw := pw * (0.3 + 0.7 * ow) * (0.9 + (fibw[i] - 0.5) * 0.5) + slub_w * 0.12 * pw
			var hf := pf * (0.3 + 0.7 * of) * (0.9 + (fibf[i] - 0.5) * 0.5) + slub_f * 0.12 * pf
			var wv := maxf(hw, hf)
			var wm := smoothstep(0.6, 0.8, worn[i]) # worn/frayed: weave flattens into fuzz
			wv = lerpf(wv, 0.45 + (fuzz[i] - 0.5) * 0.5, wm * 0.7)
			h[i] = 0.18 + wv * 0.62 + (fold[i] - 0.5) * 0.35 + (fuzz[i] - 0.5) * 0.08
			r[i] = 0.5 + (0.5 - wv) * 0.35 + wm * 0.2 + (fuzz[i] - 0.5) * 0.2
	return [_fit(h, 0.58, 0.16), r]


## Leather: pebbled grain cells split by fine creases, larger warped wrinkles, pores and glossy
## worn scuffs.
func _leather() -> Array:
	var wx := _fbm(6, 4, 501)
	var wy := _fbm(6, 4, 502)
	var grain := _worley(72, 503, 1.0, wx, wy, N * 0.02)
	var wr := _worley(11, 504, 1.0, wx, wy, N * 0.12)
	var wmask := _fbm(3, 4, 505)
	var pores := _worley(150, 506)
	var scuff := _fbm(5, 5, 507)
	var base := _fbm(4, 5, 508)
	var gf: PackedFloat32Array = grain.f1
	var ge: PackedFloat32Array = grain.edge
	var gcs: float = grain.cs
	var we: PackedFloat32Array = wr.edge
	var pf: PackedFloat32Array = pores.f1
	var pk: PackedInt32Array = pores.k
	var pr: PackedFloat32Array = pores.rnd
	var pcs: float = pores.cs
	var h := _new()
	var r := _new()
	for i in NN:
		var dome := sqrt(maxf(1.0 - gf[i] / (gcs * 0.85), 0.0))
		var c1 := 1.0 - smoothstep(0.0, 1.8 * S + 0.4, ge[i])
		var wm := smoothstep(0.3, 0.6, wmask[i])
		var c2 := (1.0 - smoothstep(0.0, 6.0 * S, we[i])) * wm
		var c2w := (1.0 - smoothstep(0.0, 18.0 * S, we[i])) * wm
		var pore := 0.0
		if pr[pk[i]] < 0.35:
			pore = 1.0 - smoothstep(0.0, 0.25 * pcs, pf[i])
		var sc := smoothstep(0.6, 0.8, scuff[i])
		h[i] = 0.5 + dome * 0.16 * (1.0 - sc * 0.6) - c1 * 0.22 - c2 * 0.2 - c2w * 0.16 \
			- pore * 0.12 + (base[i] - 0.5) * 0.22
		r[i] = 0.5 + c1 * 0.2 + c2 * 0.25 - sc * 0.4 + (base[i] - 0.5) * 0.2 + pore * 0.1
	return [_fit(h, 0.6, 0.13), r]


## Skin: dense pores, a fine wrinkle mesh, directional creases (mostly horizontal, with
## variation) and soft subdermal bumps.
func _skin() -> Array:
	var wx := _fbm(8, 4, 601)
	var wy := _fbm(8, 4, 602)
	var pores := _worley(120, 603)
	var net := _worley(34, 604, 1.0, wx, wy, N * 0.03)
	var cw1 := _fbm(2, 4, 605)
	var cw2 := _fbm(3, 4, 606)
	var cmask := _fbm(3, 4, 607)
	var bumps := _fbm(6, 5, 608)
	var fine := _fbm(96, 2, 609)
	var pf: PackedFloat32Array = pores.f1
	var pk: PackedInt32Array = pores.k
	var pr: PackedFloat32Array = pores.rnd
	var pcs: float = pores.cs
	var ne: PackedFloat32Array = net.edge
	var h := _new()
	var r := _new()
	for i in NN:
		@warning_ignore("integer_division")
		var y := i / N
		var x := i % N
		var pore := 0.0
		if pr[pk[i]] < 0.75:
			pore = pow(maxf(1.0 - pf[i] / ((0.14 + pr[pk[i]] * 0.16) * pcs), 0.0), 0.7)
		var mesh := 1.0 - smoothstep(0.0, 1.5 * S + 0.3, ne[i])
		var b1 := float(y) / N * 26.0 + (cw1[i] - 0.5) * 5.0
		var b2 := float(x) / N * 18.0 + (cw2[i] - 0.5) * 5.0
		var m := smoothstep(0.42, 0.62, cmask[i])
		var crease := pow(1.0 - absf(sin(PI * b1)), 14.0) * m + pow(1.0 - absf(sin(PI * b2)), 20.0) * (1.0 - m) * 0.5
		h[i] = 0.6 + (bumps[i] - 0.5) * 0.3 + (fine[i] - 0.5) * 0.05 - pore * 0.2 - mesh * 0.09 \
			- crease * 0.28
		r[i] = 0.5 + pore * 0.22 + mesh * 0.1 + crease * 0.15 + (bumps[i] - 0.5) * 0.3
	return [_fit(h, 0.6, 0.11), r]


## Bone / ivory: wavy growth lines, longitudinal fibres, hairline cracks with weathered lips and
## porous pitting.
func _bone() -> Array:
	var warp := _fbm(2, 4, 701)
	var warp2 := _fbm(6, 3, 702)
	var fib := _vnoise(6, 256, 703)
	var fib2 := _vnoise(3, 96, 704)
	var wx := _fbm(5, 4, 705)
	var wy := _fbm(5, 4, 706)
	var cr := _worley(5, 707, 1.0, wx, wy, N * 0.12)
	var cr2 := _worley(13, 708, 1.0, wx, wy, N * 0.05)
	var cmask := _fbm(3, 3, 709)
	var pits := _worley(80, 710)
	var pmask := _fbm(4, 4, 711)
	var base := _fbm(3, 6, 712)
	var ce: PackedFloat32Array = cr.edge
	var ce2: PackedFloat32Array = cr2.edge
	var pf: PackedFloat32Array = pits.f1
	var pk: PackedInt32Array = pits.k
	var pr: PackedFloat32Array = pits.rnd
	var pcs: float = pits.cs
	var h := _new()
	var r := _new()
	for y in N:
		for x in N:
			var i := y * N + x
			var ph := float(y) / N * 18.0 + (warp[i] - 0.5) * 4.0 + (warp2[i] - 0.5) * 0.7
			var g1 := 0.5 + 0.5 * sin(ph * TAU)
			var g2 := 0.5 + 0.5 * sin(ph * TAU * 4.0 + warp2[i] * 3.0)
			var growth := pow(g1, 3.0) * 0.6 + g2 * 0.25
			var m := smoothstep(0.55, 0.7, cmask[i])
			var c := (1.0 - smoothstep(0.0, 1.6 * S + 0.4, ce[i])) * smoothstep(0.35, 0.5, cmask[i])
			var c2 := (1.0 - smoothstep(0.0, 1.1 * S + 0.3, ce2[i])) * m
			var lip := (1.0 - smoothstep(0.0, 9.0 * S, ce[i])) * smoothstep(0.35, 0.5, cmask[i])
			var pit := 0.0
			if pr[pk[i]] < 0.5 * smoothstep(0.45, 0.75, pmask[i]):
				pit = pow(maxf(1.0 - pf[i] / ((0.12 + pr[pk[i]] * 0.3) * pcs), 0.0), 0.8)
			h[i] = 0.5 + growth * 0.16 + (fib[i] - 0.5) * 0.1 + (fib2[i] - 0.5) * 0.08 \
				+ (base[i] - 0.5) * 0.25 - c * 0.36 - c2 * 0.2 - lip * lip * 0.12 - pit * 0.28
			r[i] = 0.5 + (base[i] - 0.5) * 0.3 + c * 0.3 + c2 * 0.2 + pit * 0.25 - growth * 0.12 \
				+ (fib[i] - 0.5) * 0.15
	return [_fit(h, 0.6, 0.13), r]


## Shingled feathers (tip toward +Y), each with a rachis, angled barbs, vane splits and an edge
## falloff; earlier rows overlap later ones.
func _feather() -> Array:
	var C := 8
	var R := 8
	var W := float(N) / C
	var HR := float(N) / R
	var rng := RandomNumberGenerator.new()
	rng.seed = 801
	var fa := _arr(C * R) # angle
	var fl := _arr(C * R) # length
	var fw := _arr(C * R) # width
	var fo := _arr(C * R) # height offset
	var fp := _arr(C * R) # barb phase
	for k in C * R:
		fa[k] = rng.randfn(0.0, 0.06)
		fl[k] = HR * rng.randf_range(2.5, 2.9)
		fw[k] = W * rng.randf_range(0.56, 0.66)
		fo[k] = rng.randf_range(-0.05, 0.05)
		fp[k] = rng.randf()
	var split := _vnoise(256, 24, 802)
	var fuzz := _fbm(128, 2, 803)
	var tone := _fbm(4, 4, 804)
	var barb_f := 1.0 / (4.2 * S)
	var h := _new()
	var r := _new()
	for y in N:
		var ry := floori(y / HR)
		for x in N:
			var i := y * N + x
			var best := -1.0
			var bh := 0.0
			var br := 0.5
			# earliest (topmost) row whose feather covers the pixel wins
			for back in range(3, -1, -1):
				var row := ry - back
				var wr := posmod(row, R)
				var off := 0.5 * W if posmod(row, 2) == 1 else 0.0
				var cx0 := floori((x - off) / W)
				for dc in range(-1, 2):
					var c := posmod(cx0 + dc, C)
					var k := wr * C + c
					var dx := _wrapd(x - (c * W + off + W * 0.5))
					var dy := _wrapd(y - row * HR + HR * 0.15)
					if dy < -N * 0.5 + 1.0:
						dy += N
					var ca := cos(fa[k])
					var sa := sin(fa[k])
					var lx := dx * ca - dy * sa
					var ly := dx * sa + dy * ca
					var u := ly / fl[k]
					if u <= 0.0 or u >= 1.0:
						continue
					var wu := fw[k] * pow(sin(PI * pow(u, 0.8)), 0.6)
					var a := absf(lx) / maxf(wu, 0.01)
					if a >= 1.0:
						continue
					var shaft := 1.0 - smoothstep(0.0, (2.6 - u * 1.6) * S + 0.5, absf(lx))
					var ph := (ly - absf(lx) * 0.85) * barb_f + fp[k] * 7.0
					var barb := 0.5 + 0.5 * cos(ph * TAU)
					var bi := floori(ph)
					var sp := split[posmod(bi * 7 + k * 13, N) * N + (c * 16 + (8 if lx > 0.0 else 0)) % N]
					var gap := smoothstep(0.78, 0.84, sp) * smoothstep(0.2, 0.5, a) 						* (1.0 - smoothstep(0.0, 0.18, absf(ph - bi - 0.5) - 0.32))
					var vane := (0.55 + 0.45 * barb) * (1.0 - gap * 0.75) * (1.0 - smoothstep(0.82, 1.0, a) * 0.7)
					var hh := 0.25 + u * 0.42 + fo[k] + vane * 0.2 + shaft * 0.16 - a * a * 0.06
					best = 1.0
					bh = hh
					br = 0.5 + (1.0 - barb) * 0.15 - shaft * 0.3 + gap * 0.25
					break
				if best > 0.0:
					break
			if best < 0.0:
				bh = 0.12
				br = 0.7
			h[i] = bh + (fuzz[i] - 0.5) * 0.05 + (tone[i] - 0.5) * 0.08
			r[i] = br + (fuzz[i] - 0.5) * 0.15
	return [_fit(h, 0.58, 0.14), r]


## Wood: growth rings along Y bending around knots (gaussian bumps in the ring phase), pores,
## drying checks along the grain and weathered latewood.
func _wood() -> Array:
	var G := 21.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 901
	var kx := PackedFloat32Array()
	var ky := PackedFloat32Array()
	var ks := PackedFloat32Array()
	var ka := PackedFloat32Array()
	for k in 3:
		kx.append((k / 3.0 + rng.randf_range(0.05, 0.25)) * N)
		ky.append((k * 0.37 + rng.randf_range(0.0, 0.2)) * N)
		ks.append(rng.randf_range(18.0, 34.0) * S)
		ka.append(rng.randf_range(2.2, 3.5) * (1.0 if rng.randf() < 0.5 else -1.0))
	var wv := _vnoise(4, 3, 902)
	var wv2 := _vnoise(16, 4, 903)
	var pores := _vnoise(256, 10, 904)
	var pores2 := _vnoise(512, 24, 905)
	var weather := _fbm(4, 4, 906)
	var checks := _new()
	for _c in 14:
		var x := rng.randf() * N
		var y := rng.randf() * N
		var l := rng.randf_range(60.0, 260.0) * S
		var a := PI * 0.5 + rng.randfn(0.0, 0.03)
		_line(checks, x, y, x + cos(a) * l, y + sin(a) * l, rng.randf_range(1.2, 2.4) * S + 0.4,
			rng.randf_range(0.5, 1.0))
	var h := _new()
	var r := _new()
	for y in N:
		for x in N:
			var i := y * N + x
			var ph := float(x) / N * G + (wv[i] - 0.5) * 1.6 + (wv2[i] - 0.5) * 0.35
			var knot := 0.0
			for k in kx.size():
				var dx := _wrapd(x - kx[k])
				var dy := _wrapd(y - ky[k]) * 0.45
				var g := exp(-(dx * dx + dy * dy) / (2.0 * ks[k] * ks[k]))
				ph += ka[k] * g
				knot = maxf(knot, exp(-(dx * dx + dy * dy) / (0.18 * ks[k] * ks[k])))
			var t := ph - floorf(ph)
			var late := smoothstep(0.55, 0.8, t) * (1.0 - smoothstep(0.9, 1.0, t))
			var wm := smoothstep(0.4, 0.7, weather[i])
			var pore := smoothstep(0.62, 0.85, pores[i]) * (1.0 - late)
			var p2 := (pores2[i] - 0.5)
			h[i] = 0.45 + late * (0.16 + wm * 0.14) + p2 * 0.08 - pore * 0.14 - checks[i] * 0.4 \
				- knot * 0.2 + (weather[i] - 0.5) * 0.12
			r[i] = 0.5 - late * 0.15 + pore * 0.2 + checks[i] * 0.3 + wm * 0.15 + knot * 0.1
	return [_fit(h, 0.58, 0.14), r]


## Crystal: planar facets (each Voronoi cell gets its own sloped plane) at two scales, sharp
## grooves on facet borders and faint internal fracture planes.
func _crystal() -> Array:
	var big := _worley(6, 1001, 1.0)
	var small := _worley(17, 1002, 1.0)
	var fr := _scratches(26, 1003, 0.0, 3.0, 1.0, 60.0, 260.0, 0.8, 1.4)
	var fine := _fbm(32, 2, 1004)
	var bdx: PackedFloat32Array = big.dx
	var bdy: PackedFloat32Array = big.dy
	var bk: PackedInt32Array = big.k
	var br: PackedFloat32Array = big.rnd
	var br2: PackedFloat32Array = big.rnd2
	var br3: PackedFloat32Array = big.rnd3
	var be: PackedFloat32Array = big.edge
	var bcs: float = big.cs
	var sdx: PackedFloat32Array = small.dx
	var sdy: PackedFloat32Array = small.dy
	var sk: PackedInt32Array = small.k
	var sr: PackedFloat32Array = small.rnd
	var sr2: PackedFloat32Array = small.rnd2
	var se: PackedFloat32Array = small.edge
	var scs: float = small.cs
	var h := _new()
	var r := _new()
	for i in NN:
		var k := bk[i]
		var p1 := 0.5 + br3[k] * 0.2 + ((br[k] - 0.5) * bdx[i] + (br2[k] - 0.5) * bdy[i]) / bcs * 0.55
		var k2 := sk[i]
		var p2 := ((sr[k2] - 0.5) * sdx[i] + (sr2[k2] - 0.5) * sdy[i]) / scs * 0.22
		var e1 := 1.0 - smoothstep(0.0, 2.2 * S + 0.4, be[i])
		var e2 := (1.0 - smoothstep(0.0, 1.0 * S + 0.3, se[i])) * 0.22
		h[i] = p1 + p2 - e1 * 0.35 - e2 * 0.2 - fr[i] * 0.08 + (fine[i] - 0.5) * 0.02
		r[i] = 0.32 + e1 * 0.45 + e2 * 0.3 + fr[i] * 0.2 + (fine[i] - 0.5) * 0.1
	return [_fit(h, 0.58, 0.16), r]


## Polished marble: turbulent veins at two scales (recessed + rough where weathered), hairline
## cracks and sugary pitting in weathered patches.
func _marble() -> Array:
	var t1 := _fbm(2, 7, 1101, 0.55)
	var t2 := _fbm(3, 7, 1102, 0.55)
	var t3 := _fbm(6, 5, 1103)
	var wx := _fbm(5, 4, 1104)
	var wy := _fbm(5, 4, 1105)
	var hair := _worley(4, 1106, 1.0, wx, wy, N * 0.1)
	var hm := _fbm(3, 3, 1107)
	var weather := _fbm(4, 5, 1108)
	var sugar := _fbm(200, 2, 1109)
	var cloud := _fbm(3, 5, 1110)
	var he: PackedFloat32Array = hair.edge
	var h := _new()
	var r := _new()
	for y in N:
		for x in N:
			var i := y * N + x
			var a := (2.0 * x + 1.0 * y) / N + (t1[i] - 0.5) * 1.5 + (t3[i] - 0.5) * 0.25
			var b := (1.0 * x - 3.0 * y) / N + (t2[i] - 0.5) * 2.2
			var sharp := lerpf(5.0, 36.0, cloud[i])
			var v1 := pow(1.0 - absf(sin(PI * a)), sharp)
			var v1w := pow(1.0 - absf(sin(PI * a)), 2.5)
			var v2 := pow(1.0 - absf(sin(PI * b)), 40.0) * smoothstep(0.4, 0.6, t3[i])
			var c := (1.0 - smoothstep(0.0, 1.2 * S + 0.3, he[i])) * smoothstep(0.62, 0.75, hm[i])
			var wm := smoothstep(0.55, 0.75, weather[i])
			h[i] = 0.72 + (cloud[i] - 0.5) * 0.1 - v1 * 0.42 - v1w * 0.14 - v2 * 0.25 - c * 0.3 \
				- wm * (0.04 + (sugar[i] - 0.5) * 0.2)
			r[i] = 0.36 + v1 * 0.25 + v2 * 0.2 + c * 0.3 + wm * 0.38 + (cloud[i] - 0.5) * 0.08
	return [h, r]


## European 4-in-1 riveted mail: tilted rings, alternating row tilt, interlocked by max-blend.
func _chainmail() -> Array:
	var C := 16
	var R := 20 # rows (even: alternating offset + lean)
	var SX := float(N) / C
	var SY := float(N) / R
	var rx := SX * 0.74
	var ry := SY * 0.95
	var wire := SX * 0.12
	var rng := RandomNumberGenerator.new()
	rng.seed = 1201
	var jit := PackedFloat32Array()
	jit.resize(C * R)
	for k in C * R:
		jit[k] = rng.randf()
	var rust := _fbm(4, 5, 1202)
	var grit := _fbm(128, 2, 1203)
	var h := _new()
	var r := _new()
	for y in N:
		var row0 := floori(y / SY)
		for x in N:
			var i := y * N + x
			var best := 0.0
			var top := 0.0
			for dr in range(-1, 2):
				var row := row0 + dr
				var wr := posmod(row, R)
				var off := 0.5 * SX if posmod(row, 2) == 1 else 0.0
				var tilt := 1.0 if posmod(row, 2) == 0 else -1.0
				var cx0 := floori((x - off) / SX)
				for dc in range(-1, 2):
					var c := posmod(cx0 + dc, C)
					var dx := _wrapd(x - (c * SX + off + SX * 0.5))
					var dy := _wrapd(y - (row * SY + SY * 0.5))
					var e := (sqrt((dx / rx) * (dx / rx) + (dy / ry) * (dy / ry)) - 1.0) * minf(rx, ry)
					if absf(e) >= wire:
						continue
					var tube := sqrt(1.0 - (e / wire) * (e / wire))
					var lift := 0.45 + 0.3 * tilt * dx / rx - 0.1 * dy / ry + (jit[wr * C + c] - 0.5) * 0.08
					var v := lift + tube * 0.3
					if v > best:
						best = v
						top = tube
			var rm := smoothstep(0.55, 0.75, rust[i])
			h[i] = best + (grit[i] - 0.5) * (0.04 + rm * 0.1)
			r[i] = (0.75 if best <= 0.0 else 0.5 - top * 0.25) + rm * 0.3 + (grit[i] - 0.5) * 0.1
	return [h, r]


## Overlapping keeled scales (free edge toward +Y), each with growth striations and a raised rim.
func _scales() -> Array:
	var C := 10
	var R := 20
	var W := float(N) / C
	var HR := float(N) / R
	var rs := W * 0.66
	var rng := RandomNumberGenerator.new()
	rng.seed = 1301
	var so := PackedFloat32Array()
	var sk := PackedFloat32Array()
	so.resize(C * R)
	sk.resize(C * R)
	for k in C * R:
		so[k] = rng.randf_range(-0.05, 0.05)
		sk[k] = rng.randf_range(0.7, 1.0)
	var fine := _fbm(96, 2, 1302)
	var tone := _fbm(4, 4, 1303)
	var pits := _worley(140, 1304)
	var pf: PackedFloat32Array = pits.f1
	var pk: PackedInt32Array = pits.k
	var pr: PackedFloat32Array = pits.rnd
	var pcs: float = pits.cs
	var h := _new()
	var r := _new()
	for y in N:
		var ry := floori(y / HR)
		for x in N:
			var i := y * N + x
			var hh := 0.1
			var rr := 0.7
			var done := false
			for back in range(4, -1, -1):
				var row := ry - back
				var wr := posmod(row, R)
				var off := 0.5 * W if posmod(row, 2) == 1 else 0.0
				var cx0 := floori((x - off) / W)
				for dc in range(-1, 2):
					var c := posmod(cx0 + dc, C)
					var k := wr * C + c
					var dx := _wrapd(x - (c * W + off + W * 0.5))
					var dy := _wrapd(y - (row * HR))
					var d := sqrt(dx * dx + dy * dy * 0.8) / rs
					if d >= 1.0 or dy < -rs * 0.25:
						continue
					var down := clampf(dy / rs, 0.0, 1.0)
					var keel := (1.0 - smoothstep(0.0, W * 0.09, absf(dx))) * sk[k] * (0.3 + down)
					var rim := smoothstep(0.8, 0.93, d) * (1.0 - smoothstep(0.93, 1.0, d))
					var stri := 0.5 + 0.5 * sin(d * 34.0)
					hh = 0.25 + down * 0.32 + (1.0 - d * d) * 0.12 + keel * 0.12 + rim * 0.06 \
						+ stri * 0.03 + so[k] - smoothstep(0.93, 1.0, d) * 0.12
					rr = 0.45 - keel * 0.15 + (1.0 - down) * 0.1 + stri * 0.05
					done = true
					break
				if done:
					break
			var pit := 0.0
			if pr[pk[i]] < 0.3:
				pit = 1.0 - smoothstep(0.0, 0.25 * pcs, pf[i])
			h[i] = hh + (fine[i] - 0.5) * 0.04 + (tone[i] - 0.5) * 0.06 - pit * 0.06
			r[i] = rr + (fine[i] - 0.5) * 0.15 + pit * 0.1
	return [_fit(h, 0.58, 0.14), r]


## Rust: flaking layered crust (terraced noise with curled lips), dense pitting, coarse grit.
func _rust() -> Array:
	var n1 := _fbm(4, 7, 1401, 0.55)
	var n2 := _fbm(10, 5, 1402)
	var grit := _fbm(128, 2, 1403)
	var pits := _worley(64, 1404)
	var pf: PackedFloat32Array = pits.f1
	var pk: PackedInt32Array = pits.k
	var pr: PackedFloat32Array = pits.rnd
	var pcs: float = pits.cs
	var h := _new()
	var r := _new()
	for i in NN:
		var n := n1[i] + (n2[i] - 0.5) * 0.25
		var layers := 0.0
		var lip := 0.0
		for th in [0.38, 0.48, 0.58, 0.68]:
			layers += smoothstep(th - 0.006, th + 0.006, n)
			var q: float = (n - th - 0.012) / 0.01
			lip += exp(-q * q)
		var pit := 0.0
		if pr[pk[i]] < 0.6:
			pit = pow(maxf(1.0 - pf[i] / ((0.15 + pr[pk[i]] * 0.35) * pcs), 0.0), 0.6)
		h[i] = 0.3 + layers * 0.1 + lip * 0.06 + (grit[i] - 0.5) * 0.2 - pit * 0.22
		r[i] = 0.55 + (grit[i] - 0.5) * 0.5 + pit * 0.15 - lip * 0.1 + (n2[i] - 0.5) * 0.3
	return [_fit(h, 0.56, 0.15), r]


## Mossy rock: the stone recipe with moss cushions settling in the cracks and hollows.
func _moss_rock() -> Array:
	var l := _stone_layers(1500)
	var sh: PackedFloat32Array = _fit(l[0], 0.55, 0.15)
	var sr: PackedFloat32Array = l[1]
	var crack: PackedFloat32Array = _blur(l[3].duplicate(), int(10 * S) + 1)
	var mm := _fbm(4, 6, 1501, 0.55)
	var clumps := _worley(70, 1502, 1.0)
	var cf: PackedFloat32Array = clumps.f1
	var ccs: float = clumps.cs
	var fuzz := _fbm(256, 2, 1503)
	var fuzz2 := _fbm(64, 3, 1504)
	var h := _new()
	var r := _new()
	for i in NN:
		var hollow := (0.55 - sh[i]) * 0.8 + crack[i] * 0.5
		var m := smoothstep(0.5, 0.62, mm[i] + hollow * 0.4)
		var cushion := sqrt(maxf(1.0 - cf[i] / (ccs * 0.8), 0.0))
		var moss := 0.56 + cushion * 0.16 + (fuzz[i] - 0.5) * 0.3 + (fuzz2[i] - 0.5) * 0.1
		h[i] = lerpf(sh[i], maxf(moss, sh[i] + 0.04), m)
		r[i] = lerpf(sr[i], 0.85 + (fuzz[i] - 0.5) * 0.2, m)
	return [h, r]


## Parchment: crumpled facets, a couple of straight folds, fibres, tide-marked stains and foxing.
func _parchment() -> Array:
	var wx := _fbm(4, 4, 1601)
	var wy := _fbm(4, 4, 1602)
	var cr := _worley(8, 1603, 1.0, wx, wy, N * 0.08)
	var cr2 := _worley(21, 1604, 1.0, wx, wy, N * 0.03)
	var fib := _vnoise(512, 20, 1605)
	var fib2 := _vnoise(20, 512, 1606)
	var stain := _fbm(3, 6, 1607, 0.55)
	var fox := _worley(26, 1608)
	var fine := _fbm(128, 2, 1609)
	var cdx: PackedFloat32Array = cr.dx
	var cdy: PackedFloat32Array = cr.dy
	var ck: PackedInt32Array = cr.k
	var crn: PackedFloat32Array = cr.rnd
	var crn2: PackedFloat32Array = cr.rnd2
	var crn3: PackedFloat32Array = cr.rnd3
	var ce: PackedFloat32Array = cr.edge
	var ccs: float = cr.cs
	var ce2: PackedFloat32Array = cr2.edge
	var ff: PackedFloat32Array = fox.f1
	var fk: PackedInt32Array = fox.k
	var fr: PackedFloat32Array = fox.rnd
	var fcs: float = fox.cs
	var fold_y := N * 0.37
	var fold_x := N * 0.71
	var h := _new()
	var r := _new()
	for y in N:
		for x in N:
			var i := y * N + x
			var k := ck[i]
			var facet := ((crn[k] - 0.5) * cdx[i] + (crn2[k] - 0.5) * cdy[i]) / ccs * 0.18
			var sgn := 1.0 if crn3[k] < 0.5 else -1.0
			var crease := (1.0 - smoothstep(0.0, 2.5 * S + 0.5, ce[i])) * sgn * 0.06 \
				- (1.0 - smoothstep(0.0, 1.2 * S + 0.3, ce2[i])) * 0.03
			var fy := _wrapd(y - fold_y)
			var fx := _wrapd(x - fold_x)
			var fold := -exp(-fy * fy / (6.0 * S * S + 1.0)) * 0.16 + exp(-(fy - 4.0 * S) * (fy - 4.0 * S) / (20.0 * S * S + 1.0)) * 0.05
			fold += -exp(-fx * fx / (5.0 * S * S + 1.0)) * 0.12
			var s := stain[i]
			var tide := exp(-pow((s - 0.66) / 0.012, 2.0))
			var st := smoothstep(0.62, 0.68, s)
			var foxing := 0.0
			if fr[fk[i]] < 0.12:
				foxing = 1.0 - smoothstep(0.0, (0.06 + fr[fk[i]]) * fcs, ff[i])
			h[i] = 0.64 + facet + crease + fold + (fib[i] - 0.5) * 0.05 + (fib2[i] - 0.5) * 0.05 \
				+ (fine[i] - 0.5) * 0.03 - st * 0.06 - tide * 0.05 - foxing * 0.12
			r[i] = 0.5 + (fib[i] - 0.5) * 0.2 - st * 0.15 + tide * 0.1 + foxing * 0.1 + crease * 0.5
	return [h, r]


## Twisted three-strand rope (ropes run along Y): helical strands, fibre twist inside each strand,
## fuzz and stray fibres across the gaps.
func _rope() -> Array:
	var K := 4 # ropes across the tile
	var P := 5.0 # strand bands along the tile
	var W := float(N) / K
	var rng := RandomNumberGenerator.new()
	rng.seed = 1701
	var ro := PackedFloat32Array()
	for _k in K:
		ro.append(rng.randf())
	var fuzz := _fbm(128, 2, 1702)
	var wob := _vnoise(K * 4, 6, 1703)
	var tone := _fbm(4, 4, 1704)
	var stray := _scratches(60, 1705, PI * 0.5, 0.6, 0.3, 8.0, 40.0, 0.6, 1.0)
	var h := _new()
	var r := _new()
	for y in N:
		for x in N:
			var i := y * N + x
			var rk := floori(x / W)
			var a := (x - rk * W) / W # 0..1 across this rope
			var ac := (a - 0.5) * 2.0 / 0.94
			var prof := sqrt(maxf(1.0 - ac * ac, 0.0))
			var s := float(y) / N * P + asin(clampf(ac, -1.0, 1.0)) / PI * 0.9 + ro[rk] * 3.0 				+ (wob[i] - 0.5) * 0.12
			var fs := s - floorf(s)
			var strand := pow(sin(PI * fs), 0.55)
			var fib := 0.5 + 0.5 * sin(TAU * (fs * 9.0 + ac * 2.5))
			var body := prof * (0.35 + strand * 0.5) + prof * strand * fib * 0.08
			var gap := 1.0 - smoothstep(0.0, 0.15, prof)
			h[i] = 0.1 + body * 0.75 + (fuzz[i] - 0.5) * 0.08 + stray[i] * 0.25 * gap \
				+ (tone[i] - 0.5) * 0.06
			r[i] = 0.55 + (1.0 - strand) * 0.15 + (fuzz[i] - 0.5) * 0.25 + gap * 0.2
	return [_fit(h, 0.56, 0.17), r]
