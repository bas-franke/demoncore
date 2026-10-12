class_name PylonModel
extends EnemyModel
## A Sanctified Pylon: a tapering white-marble obelisk banded in gold, a crystal of light turning
## above its tip. `charge` (0..1, set by PylonEnemy) brightens the crystal before each pulse.
## ~2.2 units tall at size 1. Code-built (Art kit).

var charge := 0.0

var _crystal: Node3D
var _crystal_mat: StandardMaterial3D
var _light: OmniLight3D


func build() -> void:
	light_color = Art.HOLY
	feather_count = 0
	mote_count = 12
	debris = [&"shard", &"gold"]
	var marble := Art.mat(Art.IVORY, 0.5, 0.0, 0.3, true, 0.0, &"marble")
	var gold := Art.mat(Art.GOLD, 0.3, 1.0, 0.2, true, 0.0, &"gold")
	Art.part(self, Art.box(), marble, Vector3(0.0, 0.12, 0.0), Vector3(0.9, 0.24, 0.9))
	Art.part(self, Art.cylinder(0.16, 0.3), marble, Vector3(0.0, 1.0, 0.0), Vector3(1.0, 1.6, 1.0)).rotation.y = PI * 0.25
	for y: float in [0.35, 1.0, 1.65]:
		Art.part(self, Art.torus(0.85, 1.0), gold, Vector3(0.0, y, 0.0), Vector3.ONE * lerpf(0.33, 0.2, (y - 0.35) / 1.3))
	Art.part(self, Art.cone(0.5), gold, Vector3(0.0, 1.9, 0.0), Vector3(0.3, 0.24, 0.3))
	_crystal = Art.pivot(self, Vector3(0.0, 2.35, 0.0))
	var c := HolyFX.glow_part(_crystal, Art.prism(), Art.HOLY_WHITE, 2.0, Vector3(0.0, 0.12, 0.0), Vector3(0.22, 0.25, 0.22))
	var c2 := HolyFX.glow_part(_crystal, Art.prism(), Art.HOLY_WHITE, 2.0, Vector3(0.0, -0.12, 0.0), Vector3(0.22, 0.25, 0.22))
	c2.rotation.x = PI
	_crystal_mat = c.material_override as StandardMaterial3D
	c2.material_override = _crystal_mat
	_light = Art.light(self, Art.HOLY, 1.2, 6.0, Vector3(0.0, 2.3, 0.0))


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	_crystal.rotate_y(delta * (1.0 + charge * 4.0))
	_crystal.position.y = 2.35 + sin(t * 1.8) * 0.06
	var k := 1.6 + charge * 2.0 + eye_flare
	_crystal_mat.albedo_color = HolyFX.scaled(Art.HOLY_WHITE, k)
	_light.light_energy = 1.0 + charge * 2.5
