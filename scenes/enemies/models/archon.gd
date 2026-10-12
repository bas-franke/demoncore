extends EnemyModel
## "Archon of the Seventh Gate" (elite, SLAM): a towering knight in gold-filigreed ivory plate,
## a great helm under a crown of blades, two pairs of great wings, a heavy cape, a three-ring
## blazing halo and a greatsword whose fuller burns with runes.
## SLAM: "windup" hauls the blade high overhead while the wings flare and the halo swells
## (stretched over the wind-up), "attack" is the downswing that bites the ground on its last
## frames (stretched over `charge_time`); the Enemy strikes the lit circle when it ends. The
## model then plays "recover" (impact hold, heave the blade out, back to guard) through the
## Enemy's slam recovery (State.RECOVER, played by the base) instead of snapping back to idle.
## Blender model: tools/blender/models/enemies/archon.py
## (idle / walk / windup / attack / recover / hit / death).

const MODEL := "res://assets/models/enemies/archon.glb"
## Ground speed of the "walk" clip in model units (archon.py WALK_SPEED); the Enemy scales the
## model by EnemyData.size, so playback = speed / (size * WALK_SPEED) keeps the feet planted.
const WALK_SPEED := 0.868

var _halo_light: OmniLight3D
var _blade_light: OmniLight3D


func build() -> void:
	feather_count = 8
	mote_count = 10
	debris = [&"gold", &"steel", &"feather"]
	debris_color = Art.GOLD
	# Walk playback = real ground speed / (size * WALK_SPEED): 2 m/s at size 2 -> 1.15x.
	move_clip_speed = WALK_SPEED
	move_speed_min = 0.6
	move_speed_max = 1.15
	idle_below = 0.1
	# The death clip (reels, kneels on the planted sword, the halo shatters ~1 s, falls ~2 s) sets
	# the corpse's life; it burns white only at the end and sinks instead of shrinking.
	corpse_flash_delay = 0.55
	corpse_shrink = false
	use_glb(MODEL)
	var halo_node := glb_node("halo")
	if halo_node:
		_halo_light = Art.light(halo_node, Art.HOLY, 1.4, 2.6)
	var sword := glb_node("sword")
	if sword:
		_blade_light = Art.light(sword, Art.HOLY, 0.0, 1.8)
		# Blender's blade axis (+Z) is the node's +Y after the glTF Y-up conversion.
		_blade_light.position = Vector3(0.0, 0.8, 0.0)


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	var blaze := 1.4
	var blade := 0.0
	if state == State.WINDUP:
		blaze = 1.4 + 2.6 * state_progress
		blade = 2.5 * state_progress
	elif state == State.ATTACKING:
		blaze = 4.0
		blade = 3.0
	blaze += 2.0 * land_kick
	blade += 3.0 * land_kick
	if _halo_light:
		_halo_light.light_energy = EnemyModel.damp(_halo_light.light_energy, blaze, 10.0, delta)
	if _blade_light:
		_blade_light.light_energy = EnemyModel.damp(_blade_light.light_energy, blade, 12.0, delta)


func play_attack() -> void:
	super.play_attack()
	Sfx.play(&"wingbeat", 0.06, -1.0)
