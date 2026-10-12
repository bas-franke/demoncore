extends EnemyModel
## "Seraph Sentinel": the rank and file of the Host. A tall knight in ivory plate with engraved
## gold trim, a pleated tabard, a smooth faceless porcelain mask traced with gold filigree and a
## crisp halo; wings folded tall behind the back, a winged spear and a kite shield with a sun.
## Blender model: idle / walk / windup / attack (spear thrust) / hit / death.
##
## The sentinel is a CHASE enemy (contact damage, no attack state), so the thrust is cosmetic:
## the base proximity attack plays it when the player comes within spear reach. The walk clip's
## playback rate follows the enemy's real ground speed (move_clip_speed) so the feet don't slide.

const MODEL := "res://assets/models/enemies/seraph_sentinel.glb"
## Ground speed (m/s at model scale 1) at which the "walk" clip's feet stay planted
## (Blender: stride_speed of the walk in tools/blender/models/enemies/seraph_sentinel.py).
const WALK_SPEED := 2.55


func build() -> void:
	feather_count = 5
	debris = [&"steel", &"gold"]
	debris_color = Art.GOLD
	move_clip_speed = WALK_SPEED
	# Spear thrust from 1.9 m (model scale 1); impact lands ~0.5 s later.
	proximity_range = 1.9
	proximity_cooldown = 2.4
	blend_attack = 0.08
	use_glb(MODEL)


func proximity_attack() -> void:
	if play_oneshot(proximity_anim, blend_attack) > 0.0:
		play_attack()
