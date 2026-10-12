extends SceneTree
## Generates the ground-mark atlases used by res://scenes/world/ground_marks.gd:
##   godot --headless --path . --script res://tools/build_decals.gd
## then run --import. Deterministic (fixed seeds).
##
## Two 4x2 atlases of 256 px cells (1024x512):
##   decal_atlas_albedo.png  RGB = albedo, A = coverage
##   decal_atlas_data.png    R = emissive mask, G = dissolve noise, B = height, A = wetness
## Cells (row-major): 0 holy burn ring, 1 scorched sigil, 2 ichor splatter, 3 blood drops,
##                    4 cracked crater, 5 feather scatter, 6 small scorch, 7 directional smear

const CELL := 256
const COLS := 4
const ROWS := 2
const OUT_DIR := "res://assets/textures"

var _n_fbm := FastNoiseLite.new()
var _n_fine := FastNoiseLite.new()
var _n_cell := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()

# Per-pixel channel outputs set by each cell recipe.
var _alb := Color()
var _dat := Color()


func _init() -> void:
	_n_fbm.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_fbm.frequency = 2.2
	_n_fbm.fractal_octaves = 5
	_n_fbm.seed = 17
	_n_fine.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_fine.frequency = 9.0
	_n_fine.fractal_octaves = 3
	_n_fine.seed = 41
	_n_cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	_n_cell.frequency = 5.0
	_n_cell.fractal_type = FastNoiseLite.FRACTAL_NONE
	_n_cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	_n_cell.seed = 5

	var albedo := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGBA8)
	var data := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGBA8)
	for idx in COLS * ROWS:
		_rng.seed = 1000 + idx * 77
		var prep: Dictionary = _prepare(idx)
		var ox := (idx % COLS) * CELL
		@warning_ignore("integer_division")
		var oy := (idx / COLS) * CELL
		for py in CELL:
			for px in CELL:
				var p := Vector2((px + 0.5) / CELL * 2.0 - 1.0, (py + 0.5) / CELL * 2.0 - 1.0)
				_alb = Color(0, 0, 0, 0)
				_dat = Color(0, 0.5, 0.5, 0)
				_shade(idx, p, prep, idx * 13.7)
				# Keep a transparent border so mip levels don't bleed between cells.
				var edge := clampf((1.0 - maxf(absf(p.x), absf(p.y))) / 0.04, 0.0, 1.0)
				_alb.a *= edge
				_dat.r *= edge
				_dat.g = clampf(0.5 + 0.5 * _n_fbm.get_noise_2d(p.x * 1.3 + idx * 9.0, p.y * 1.3) * 1.4
					+ 0.25 * (1.0 - p.length()), 0.0, 1.0)
				albedo.set_pixel(ox + px, oy + py, _clamp(_alb))
				data.set_pixel(ox + px, oy + py, _clamp(_dat))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(albedo, "decal_atlas_albedo")
	_save(data, "decal_atlas_data")
	quit()


func _save(img: Image, name_: String) -> void:
	var path := OUT_DIR.path_join(name_ + ".png")
	img.save_png(ProjectSettings.globalize_path(path))
	# Lossless + mipmaps (the marks are seen at a grazing distance; no VRAM compression banding).
	var imp := ProjectSettings.globalize_path(path + ".import")
	if not FileAccess.file_exists(imp):
		var f := FileAccess.open(imp, FileAccess.WRITE)
		f.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
			+ "compress/mode=0\nmipmaps/generate=true\ndetect_3d/compress_to=0\n")
		f.close()
	print("DECAL ", path)


static func _clamp(c: Color) -> Color:
	return Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1), clampf(c.a, 0, 1))


static func _ss(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var pa := p - a
	var ba := b - a
	var h := clampf(pa.dot(ba) / ba.dot(ba), 0.0, 1.0)
	return (pa - ba * h).length()


## Random jagged polyline from `from` heading `ang` outwards; returns PackedVector2Array.
func _crack(from: Vector2, ang: float, length: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array([from])
	var p := from
	var step := length / segs
	for i in segs:
		ang += _rng.randf_range(-0.45, 0.45)
		p += Vector2(cos(ang), sin(ang)) * step * _rng.randf_range(0.7, 1.3)
		pts.append(p)
	return pts


static func _poly_dist(p: Vector2, pts: PackedVector2Array) -> Vector2:
	## x = distance, y = 0..1 along the polyline at the closest point.
	var best := 1e9
	var t := 0.0
	for i in pts.size() - 1:
		var d := _seg_dist(p, pts[i], pts[i + 1])
		if d < best:
			best = d
			t = (i + 0.5) / (pts.size() - 1)
	return Vector2(best, t)


func _prepare(idx: int) -> Dictionary:
	var d := {}
	match idx:
		2, 3, 7:
			var drops := []
			var n := 16 if idx == 2 else (9 if idx == 3 else 12)
			for i in n:
				var ang := _rng.randf() * TAU
				var rad := _rng.randf_range(0.35, 0.85) if idx == 2 else _rng.randf_range(0.0, 0.75)
				var c := Vector2(cos(ang), sin(ang)) * rad
				if idx == 7:
					c = Vector2(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.22, 0.22) * (1.0 - absf(c.x)))
					ang = 0.0
				drops.append([c, _rng.randf_range(0.025, 0.075) * (1.4 if idx == 3 else 1.0), ang,
					_rng.randf_range(1.0, 2.6)])
			d.drops = drops
		4:
			var cracks := []
			for i in 11:
				var ang := i * TAU / 11.0 + _rng.randf_range(-0.2, 0.2)
				var st := Vector2(cos(ang), sin(ang)) * 0.22
				cracks.append(_crack(st, ang, _rng.randf_range(0.45, 0.72), 7))
				if _rng.randf() < 0.6:  # branch
					var base: PackedVector2Array = cracks[-1]
					var bp := base[_rng.randi_range(2, 4)]
					cracks.append(_crack(bp, ang + _rng.randf_range(-0.9, 0.9), _rng.randf_range(0.15, 0.3), 4))
			d.cracks = cracks
		5:
			var feathers := []
			for i in 7:
				var c := Vector2(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.6, 0.6))
				feathers.append([c, _rng.randf() * TAU, _rng.randf_range(0.2, 0.36),
					_rng.randf_range(0.055, 0.085), _rng.randf()])
			d.feathers = feathers
		6:
			var specks := []
			for i in 14:
				var ang := _rng.randf() * TAU
				specks.append([Vector2(cos(ang), sin(ang)) * _rng.randf_range(0.0, 0.55), _rng.randf_range(0.012, 0.03)])
			d.specks = specks
	return d


func _shade(idx: int, p: Vector2, prep: Dictionary, off: float) -> void:
	var r := p.length()
	var a := atan2(p.y, p.x)
	var n := _n_fbm.get_noise_2d(p.x + off, p.y)
	var nf := _n_fine.get_noise_2d(p.x + off, p.y)
	var soot := Color(0.03, 0.026, 0.024)
	match idx:
		0:  # holy burn: charred disk, radiant gold ring, light rays scorched outward
			var scorch := _ss(0.8 + 0.3 * n, 0.25, r)
			var ring := exp(-pow((r - 0.5 - 0.06 * n) / 0.045, 2.0)) * _ss(-0.55, 0.1, nf + 0.4 * n)
			var rays := pow(absf(sin(a * 6.0 + n * 1.6)), 10.0) * _ss(0.95, 0.35, r) * _ss(0.12, 0.3, r)
			# Holy fire bleaches: pale ash inside the ring, a charcoal halo and soot rays outside.
			var inside := _ss(0.5, 0.36, r + 0.08 * n) * _ss(-0.6, 0.2, n + 0.5 * nf)
			var halo := scorch * (1.0 - inside)
			var cov := maxf(maxf(scorch * (0.7 + 0.25 * _ss(-0.4, 0.4, nf)), rays * 0.7), ring * 0.9)
			var ash := Color(0.2, 0.19, 0.17).lerp(Color(0.36, 0.34, 0.3), _ss(-0.2, 0.7, nf))
			var col := soot.lerp(ash, inside)
			col = col.lerp(soot, rays * (1.0 - inside) * 0.5 + halo * 0.3)
			col = col.lerp(Color(0.42, 0.37, 0.27), ring * 0.7)
			_alb = Color(col.r, col.g, col.b, cov)
			_dat.r = ring * 0.95 + rays * 0.45 + _ss(0.3, 0.0, r) * 0.5 * (0.6 + 0.4 * nf)
			_dat.b = 0.5 - scorch * 0.15 + ring * 0.12 + nf * 0.05
			_dat.a = 0.0
		1:  # scorched sigil: charred disk with an engraved, glowing angelic seal
			var scorch := _ss(0.88 + 0.1 * n, 0.55, r)
			var line := 0.0
			line = maxf(line, _ss(0.022, 0.008, absf(r - 0.74)))
			line = maxf(line, _ss(0.014, 0.004, absf(r - 0.62)))
			line = maxf(line, _ss(0.012, 0.003, absf(r - 0.2)))
			for i in 7:  # {7/3} star of the seven choirs
				var a0 := TAU * float(i * 3) / 7.0 - PI / 2.0
				var a1 := TAU * float(i * 3 + 3) / 7.0 - PI / 2.0
				var d := _seg_dist(p, Vector2(cos(a0), sin(a0)) * 0.6, Vector2(cos(a1), sin(a1)) * 0.6)
				line = maxf(line, _ss(0.014, 0.0035, d))
			for i in 7:  # spokes from the inner circle
				var a0 := TAU * (i + 0.5) / 7.0 - PI / 2.0
				var dir := Vector2(cos(a0), sin(a0))
				line = maxf(line, _ss(0.011, 0.003, _seg_dist(p, dir * 0.2, dir * 0.34)))
			# rune ticks between the outer circles
			var tick := absf(fposmod(a / TAU * 24.0, 1.0) - 0.5)
			line = maxf(line, _ss(0.08, 0.03, tick) * _ss(0.64, 0.66, r) * _ss(0.72, 0.70, r))
			line *= 0.75 + 0.25 * _ss(-0.4, 0.3, nf)  # worn, broken strokes
			var cov := maxf(scorch * (0.5 + 0.3 * _ss(-0.5, 0.5, n) + 0.15 * nf), line)
			var col := soot.lerp(Color(0.11, 0.095, 0.08), _ss(0.0, 0.7, nf) * 0.5)
			col = col.lerp(Color(0.5, 0.43, 0.3), line)  # seal lines burnt pale gold
			_alb = Color(col.r, col.g, col.b, cov)
			_dat.r = line + _ss(0.5, 0.0, r) * 0.15
			_dat.b = 0.5 - line * 0.25 - scorch * 0.05
		2, 3, 7:  # dark crimson splatter / drops / smear
			var m := 0.0
			if idx == 2:
				var rr := 0.3 + 0.07 * sin(a * 5.0 + n * 3.0) + 0.06 * n
				m = _ss(rr + 0.02, rr - 0.02, r)
			elif idx == 7:
				var w := 0.16 * (1.0 - _ss(-0.2, 0.85, p.x)) + 0.03 + 0.04 * n
				m = _ss(w + 0.02, w - 0.02, absf(p.y - 0.06 * sin(p.x * 3.0))) * _ss(0.9, 0.7, absf(p.x + 0.05))
			for dr in prep.drops:
				var c: Vector2 = dr[0]
				var rad: float = dr[1]
				var dir := c.normalized() if c.length() > 0.01 else Vector2.RIGHT
				var q := p - c
				# elongate along the splash direction
				var along: float = q.dot(dir) / float(dr[3])
				var across := q.dot(dir.orthogonal())
				var dd := Vector2(along, across).length() + nf * 0.012
				m = maxf(m, _ss(rad + 0.012, rad - 0.012, dd))
			var rim := _ss(0.25, 0.75, m) * (1.0 - _ss(0.8, 1.0, m))
			var col := Color(0.34, 0.02, 0.025).lerp(Color(0.12, 0.005, 0.008), rim * 0.8 + 0.3 * _ss(0.0, 0.6, nf))
			_alb = Color(col.r, col.g, col.b, m * 0.92)
			_dat.r = 0.0
			_dat.b = 0.5 + m * 0.06
			_dat.a = m * (0.8 - rim * 0.3)
		4:  # cracked impact crater
			var depress := _ss(0.42 + 0.05 * n, 0.05, r)
			var rim := exp(-pow((r - 0.45 - 0.04 * n) / 0.08, 2.0))
			var crack := 0.0
			for c in prep.cracks:
				var pd := _poly_dist(p, c)
				var w := lerpf(0.022, 0.004, pd.y)
				crack = maxf(crack, _ss(w, w * 0.25, pd.x))
			var plates := _n_cell.get_noise_2d(p.x * 3.0 + 3.0, p.y * 3.0)  # -1 at cell edges
			var fine_cr := _ss(-0.86, -0.97, plates) * _ss(0.55, 0.1, r)
			crack = maxf(crack, fine_cr * 0.8)
			var outer := _ss(0.98 + 0.08 * n, 0.45, r)
			var cov := maxf(maxf(outer * 0.75, depress), crack)
			var col := Color(0.3, 0.27, 0.23).lerp(soot, minf(depress * 1.3, 1.0))
			col = col.lerp(Color(0.46, 0.41, 0.34), rim * 0.75)
			col = col.lerp(Color(0.008, 0.006, 0.005), crack)
			_alb = Color(col.r, col.g, col.b, cov * (0.9 + 0.1 * nf))
			_dat.r = crack * (0.6 + 0.4 * _ss(0.8, 0.1, r)) + depress * 0.45
			_dat.b = 0.5 - depress * 0.35 + rim * 0.22 - crack * 0.25 + nf * 0.04
		5:  # feather scatter
			var cov := 0.0
			var col := Color(0, 0, 0)
			var glow := 0.0
			for f in prep.feathers:
				var c: Vector2 = f[0]
				var ang: float = f[1]
				var hl: float = f[2]
				var hw: float = f[3]
				var q := (p - c).rotated(-ang)
				var t := q.x / hl  # -1 quill .. 1 tip
				if absf(t) > 1.0:
					continue
				var vane := hw * sqrt(maxf(1.0 - t * t, 0.0)) * (0.75 + 0.25 * t)
				var curve := q.y - 0.12 * hw * t * t
				var barbs := 0.5 + 0.5 * sin((q.x * 1.6 - absf(curve)) * 160.0)
				var ragged := vane * (0.82 + 0.18 * barbs + 0.1 * nf)
				var m := _ss(ragged, ragged * 0.7, absf(curve)) * _ss(-0.98, -0.8, t)
				var rachis := _ss(0.006, 0.0015, absf(curve)) * _ss(-1.0, -0.9, t)
				m = maxf(m, rachis)
				if m <= 0.0:
					continue
				var singe: float = _ss(0.35, 1.0, t) if f[4] > 0.5 else 0.0
				var fc := Color(0.66, 0.63, 0.57).lerp(Color(0.42, 0.41, 0.39), _ss(0.2, 1.0, absf(curve) / hw))
				fc = fc.lerp(Color(0.78, 0.74, 0.64), rachis)
				fc = fc.lerp(Color(0.05, 0.04, 0.035), singe * 0.9)
				col = col.lerp(fc, m) if cov > 0.0 else fc
				cov = maxf(cov, m * (1.0 - singe * 0.3))
				glow = maxf(glow, singe * _ss(0.6, 1.0, t) * m)
			_alb = Color(col.r, col.g, col.b, cov)
			_dat.r = glow * 0.8
			_dat.b = 0.5 + cov * 0.1
		6:  # small scorch with embers
			var m := _ss(0.62 + 0.25 * n, 0.12, r) * (0.75 + 0.25 * nf)
			var ember := 0.0
			for s in prep.specks:
				var sr: float = s[1]
				ember = maxf(ember, _ss(sr, sr * 0.3, (p - (s[0] as Vector2)).length()))
			var sc := soot.lerp(Color(0.33, 0.31, 0.28), _ss(0.45, 0.1, r + 0.1 * n))
			_alb = Color(sc.r, sc.g, sc.b, maxf(m * 0.85, ember))
			_dat.r = ember + m * 0.25 * _ss(0.4, 0.0, r)
			_dat.b = 0.5 - m * 0.08
