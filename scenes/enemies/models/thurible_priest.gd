extends EnemyModel
## "Censer Cleric": a tall hooded cleric of the Host hovering above the ground in layered
## vestments (ash under-robe, pale tunic, gold-trimmed scapular, long dark stole), its face a
## faint glow deep in a gothic cowl, small wings folded at its back, prayer beads in one hand.
## With the other it swings a filigree censer on a link chain; the embers inside are flung out
## as a scalding gust of holy smoke.
## Blender model: idle / fly (loops, the censer swings on a spring chain) / windup (pendulum
## backswing, embers flare) / attack (thrust swing, impact hold) / hit / death (the robes
## deflate, the censer drops). The smoke, the ember glow and the release puff hang on the
## model's "censer" / "ember" joints.

const MODEL := "res://assets/models/enemies/thurible_priest.glb"
const SMOKE := Color(0.82, 0.78, 0.68)
const EMBER := Color(1.0, 0.52, 0.18)
const SMOKE_PUFFS := 4

var _censer: Node3D
var _ember: Node3D
var _glow: MeshInstance3D
var _smoke: Array[MeshInstance3D] = []
var _smoke_t: Array[float] = []
var _smoke_base: Array[Vector3] = []


func build() -> void:
	feather_count = 3
	mote_count = 8
	debris = [&"gold"]
	debris_color = Art.GOLD
	move_anim = &"fly"
	idle_anim = &"idle"
	move_speed_min = 0.8
	move_speed_max = 1.1
	# The thrust + impact hold must read: play the attack at real speed (it finishes after the
	# short shot recovery, EnemyData.shot_recover_time) instead of squeezing it into it.
	attack_real_speed = true
	use_glb(MODEL)
	_censer = glb_node("censer")
	_ember = glb_node("ember")
	var smoke_mat := Art.glow(SMOKE, 0.55, false, 0.25)
	for i in SMOKE_PUFFS:
		_smoke.append(Art.part(self, Art.sphere(), smoke_mat, Vector3.ZERO, Vector3.ONE * 0.1))
		_smoke_t.append(float(i) / float(SMOKE_PUFFS))
		_smoke_base.append(Vector3(0.24, 0.3, -0.37))
	# Soft ember halo around the censer (cheaper than a light; swells in the windup).
	_glow = Art.part(self, Art.sphere(), Art.glow(EMBER, 1.6, true, 0.35), Vector3.ZERO, Vector3.ONE * 0.3)


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	if _censer == null or not is_inside_tree():
		return
	var windup := state_progress if state == State.WINDUP else 0.0
	var origin := to_local((_ember if _ember else _censer).global_position)
	# Ember glow: a slow flicker, swelling through the windup, flashing on release.
	var flick := 0.9 + 0.1 * sin(t * 11.0) * sin(t * 4.3)
	_glow.position = origin
	_glow.scale = Vector3.ONE * (0.26 + 0.22 * windup + 0.3 * attack_kick) * flick
	# Smoke: each puff rises from the censer, swells and thins, then starts over (faster and
	# thicker while the censer is being wound up).
	var rate := 0.8 + 1.2 * windup
	for i in _smoke.size():
		var k := fposmod(_smoke_t[i] + delta * rate, 1.0)
		if k < _smoke_t[i]:
			_smoke_base[i] = origin
		_smoke_t[i] = k
		_smoke[i].position = _smoke_base[i] + Vector3(sin(k * 4.0 + float(i)) * 0.05, 0.08 + k * 0.45, 0.0)
		_smoke[i].scale = Vector3.ONE * (0.08 + 0.2 * k + 0.08 * windup) * (1.0 - k * k)


func play_attack() -> void:
	super.play_attack()
	Sfx.play(&"wingbeat", 0.12, -7.0)
	if _censer and is_inside_tree():
		# The incense spills from the censer as it is flung.
		EnemyModel.poof(_censer.global_position, SMOKE, EMBER, 5, 0.22, 0.45)


func death_burst(at: Vector3, s: float, elite: bool) -> void:
	super.death_burst(at, s, elite)
	EnemyModel.poof(at, SMOKE, Art.BONE, 6, 0.35 * s, 0.6 * s)
