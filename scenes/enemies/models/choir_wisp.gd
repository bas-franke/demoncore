extends EnemyModel
## "Choir Wisp": a single note of the heavenly choir given form. A small sun with one slit eye
## between gold lids, crowned by a rayed halo, borne on three pairs of tiny seraph wings, trailing
## ribbons of light (Blender model: fly / windup / attack / hit / death). Swarms, so it skips the
## death copy. CHASE enemies never enter WINDUP/ATTACK, so close to the player it plays the
## "attack" dart itself (base proximity attack; purely visual, contact damage is unchanged).

const MODEL := "res://assets/models/enemies/choir_wisp.glb"


func build() -> void:
	feather_count = 2
	mote_count = 5
	corpse_on_death = false
	move_anim = &"fly"
	idle_anim = &"fly"
	move_speed_min = 0.85
	move_speed_max = 1.2
	# Dart at the player from ~1.4 m (2.0 model units x size 0.7), every ~1.6 s.
	proximity_range = 2.0
	proximity_cooldown = 1.6
	blend_attack = 0.06
	use_glb(MODEL)
	Art.no_shadows(self)


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	# Dip forward into the dive while chasing.
	rig.rotation.x = EnemyModel.damp(rig.rotation.x, -0.15 * move_ratio, 6.0, delta)
