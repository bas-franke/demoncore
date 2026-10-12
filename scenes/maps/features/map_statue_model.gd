class_name MapStatueModel
extends EnemyModel
## Model for MapStatue: a robed marble saint on a plinth with a gilded halo, or (variant "ward",
## read from the parent MapStatue) a Gate Ward: a tall marble pillar bound in golden chains with a
## burning sun-sigil, ~3 m. Code-built with flashable Art materials so hits flash.

var _sigil: Node3D
var _light: OmniLight3D


func build() -> void:
	light_color = Art.HOLY
	feather_count = 2
	mote_count = 10
	debris = [&"shard", &"gold"]
	var ward := false
	var p := get_parent()
	if p and &"variant" in p:
		ward = p.get(&"variant") == &"ward"
	var marble := Art.mat(Art.IVORY, 0.5, 0.0, 0.35, true, 0.0, &"marble")
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.2, true, 0.0, &"gold")
	Art.part(self, Art.box(), marble, Vector3(0, 0.25, 0), Vector3(1.1, 0.5, 1.1))
	if ward:
		Art.part(self, Art.cylinder(0.35, 0.45), marble, Vector3(0, 1.6, 0), Vector3(1.0, 2.3, 1.0))
		for y: float in [0.9, 1.6, 2.3]:
			Art.part(self, Art.torus(0.85, 1.0), gold, Vector3(0, y, 0), Vector3.ONE * 0.5)
		_sigil = Art.pivot(self, Vector3(0, 3.1, 0))
		HolyFX.glow_part(_sigil, Art.torus(0.8, 1.0), Art.HOLY, 2.4, Vector3.ZERO, Vector3.ONE * 0.55)
		HolyFX.glow_part(_sigil, Art.sphere(), Art.HOLY_WHITE, 2.6, Vector3.ZERO, Vector3.ONE * 0.35)
		_light = Art.light(self, Art.HOLY, 1.6, 7.0, Vector3(0, 3.1, 0))
	else:
		# robed figure: tapering robe, shoulders, head, folded wings, halo
		Art.part(self, Art.cylinder(0.22, 0.42), marble, Vector3(0, 1.1, 0), Vector3(1.0, 1.2, 1.0))
		Art.part(self, Art.sphere(), marble, Vector3(0, 1.75, 0), Vector3(0.62, 0.32, 0.42))
		Art.part(self, Art.sphere(), marble, Vector3(0, 2.0, 0), Vector3(0.3, 0.34, 0.3))
		for s: float in [-1.0, 1.0]:
			Art.part(self, Art.box(), marble, Vector3(s * 0.32, 1.45, 0.25), Vector3(0.12, 1.0, 0.45),
					Vector3(0.3, s * 0.4, 0))
		_sigil = Art.pivot(self, Vector3(0, 2.3, -0.05))
		HolyFX.glow_part(_sigil, Art.torus(0.8, 1.0), Art.HOLY, 1.6, Vector3.ZERO, Vector3.ONE * 0.3)


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	if _sigil:
		_sigil.rotate_y(delta * 0.8)
	if _light:
		_light.light_energy = 1.4 + 0.4 * sin(t * 2.2) + eye_flare
