extends AbilityKind
## "orbit": get_count() objects circling the demon; each enemy they touch is hit at most once per
## params.rehit seconds. Params: radius, spin, size, rehit, style (orb / flail / lantern / coin /
## mirror).

var _orbs: Array[Node3D] = []
var _hits := {}  # Enemy -> seconds until it can be hit again
var _angle := 0.0


func cast() -> bool:
	if _orbs.size() != count():
		rebuild()
	return true


func can_unleash() -> bool:
	return false


func rebuild() -> void:
	for o in _orbs:
		o.queue_free()
	_orbs.clear()
	var sz := p("size", 0.3)
	for i in count():
		var o := Node3D.new()
		caster.add_child(o)
		match style("orb"):
			"flail":
				Art.part(o, Art.sphere(), Art.mat(Art.STEEL, 0.4, 0.8), Vector3.ZERO, Vector3.ONE * sz * 1.6)
				for k in 6:
					Art.part(o, Art.cone(0.5), Art.mat(Art.STEEL, 0.4, 0.8), Vector3.ZERO,
						Vector3(sz * 0.4, sz * 2.4, sz * 0.4), Vector3(k * 1.05, k * 0.7, 0.0))
			"lantern":
				Art.part(o, Art.cylinder(0.35, 0.45), Art.mat(Art.BRONZE, 0.5, 0.7), Vector3.ZERO, Vector3(sz, sz * 1.6, sz))
				Art.part(o, Art.sphere(), Art.glow(def.color, 3.5, true, 0.9), Vector3.ZERO, Vector3.ONE * sz * 1.1)
			"coin":
				Art.part(o, Art.cylinder(), Art.mat(Art.GOLD, 0.25, 1.0), Vector3.ZERO, Vector3(sz * 2.2, sz * 0.25, sz * 2.2), Vector3(PI * 0.5, 0.0, 0.0))
				Art.part(o, Art.sphere(), Art.glow(def.color, 1.4, true, 0.4), Vector3.ZERO, Vector3.ONE * sz * 2.4)
			"mirror":
				# Smoked black mirror glass (cold silver-blue reads as heaven's; art-style palette).
				Art.part(o, Art.box(), Art.mat(Color(0.2, 0.17, 0.22), 0.05, 1.0), Vector3.ZERO, Vector3(sz * 2.0, sz * 3.0, 0.05))
				Art.part(o, Art.box(), Art.glow(def.color, 1.6, true, 0.35), Vector3.ZERO, Vector3(sz * 2.3, sz * 3.3, 0.02))
			_:
				Art.part(o, Art.sphere(), Art.glow(def.color, 2.6, true, 0.85), Vector3.ZERO, Vector3.ONE * sz * 2.0)
				# Hot core keeps the school's hue (a pure white core reads holy; art-style palette).
				Art.part(o, Art.sphere(), Art.glow(def.color.lerp(Color.WHITE, 0.55), 2.0, true, 1.0), Vector3.ZERO, Vector3.ONE * sz * 0.8)
		InfernalFx.embers(o, def.color, 6, 0.35, sz * 0.5)
		_orbs.append(o)


func cleanup() -> void:
	_orbs.clear()


func tick(delta: float) -> void:
	if _orbs.is_empty():
		return
	var r := p("radius", 2.5) * area()
	_angle += p("spin", 2.5) * delta
	var n := _orbs.size()
	var bob := style("") == "lantern"
	for i in n:
		var a := _angle + TAU * i / n
		_orbs[i].position = Vector3(cos(a) * r, 0.8 + (sin(a * 2.0 + i) * 0.15 if bob else 0.0), sin(a) * r)
		_orbs[i].rotation.y = -a
	for e: Variant in _hits.keys():
		_hits[e] = float(_hits[e]) - delta
		if float(_hits[e]) <= 0.0 or not is_instance_valid(e):
			_hits.erase(e)
	var reach := p("size", 0.3) + 0.45
	var src := source()
	for e in AbilityCombat.enemies_in_radius(player.global_position, r + reach + 0.5):
		if _hits.has(e):
			continue
		for o in _orbs:
			var d := o.global_position - e.global_position
			d.y = 0.0
			if d.length() <= reach + 0.3 * (e.data.size if e.data else 1.0):
				_hits[e] = p("rehit", 0.5)
				AbilityCombat.hit(e, damage(), src)
				break
