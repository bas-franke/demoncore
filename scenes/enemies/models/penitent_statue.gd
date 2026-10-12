extends EnemyModel
## "Penitent Statue": a weathered marble angel on a broken plinth, hooded, both hands pressed
## over its face. Light weeps from beneath its fingers and bleeds through a fissure down its robe;
## its right wing is snapped at the elbow. It does not walk: it rocks its plinth forward, crouches
## with a groan of stone, then leaps and falls on you.
## Blender model: idle / walk / windup (crouch) / attack (the leap: ends on the impact squash) /
## land (impact hold + grinding recovery) / hit / death (crumbles into chunks).
## The leap's height is added here from state_progress (the Enemy only moves it along the ground).

const MODEL := "res://assets/models/enemies/penitent_statue.glb"
const HOP_HEIGHT := 0.9
## Arc shape: < 1 peaks early and falls fast (a heavy drop rather than a floaty parabola).
const HOP_SKEW := 0.75


func build() -> void:
	feather_count = 0
	mote_count = 5
	debris = [&"shard", &"shard", &"shard", &"mote"]
	debris_color = Art.STONE
	move_speed_min = 0.7
	move_speed_max = 1.2
	# Landing (State.RECOVER): the base plays "land" (impact hold + grinding recovery) as a
	# one-shot, cut in hard so the impact frame isn't blended away.
	recover_anim = &"land"
	blend_recover = 0.0
	# The crumble needs a moment to read: the corpse lives for the death clip plus a beat, burns
	# white late and sinks into the floor instead of shrinking.
	corpse_linger = 0.25
	corpse_flash_delay = 0.45
	corpse_shrink = false
	use_glb(MODEL)


func animate(delta: float, move_ratio: float, state: int) -> void:
	super.animate(delta, move_ratio, state)
	var p := state_progress
	var y := 0.0
	rig.position.x = 0.0
	match state:
		State.WINDUP:
			# Stone grinding against stone as it gathers itself.
			rig.position.x = randf_range(-0.012, 0.012) * p
		State.ATTACKING:
			y = HOP_HEIGHT * sin(PI * pow(p, HOP_SKEW))
	rig.position.y = y
	# The clips squash on impact already; keep the code kick small so the two don't stack.
	var sy := 1.0 - land_kick * 0.06
	var sxz := 1.0 / sqrt(maxf(sy, 0.3))
	rig.scale = Vector3(sxz, sy, sxz)


func play_attack() -> void:
	super.play_attack()
	Sfx.play(&"wingbeat", 0.1, -6.0)


func death_burst(at: Vector3, s: float, elite: bool) -> void:
	super.death_burst(at, s, elite)
	EnemyModel.poof(at, Art.STONE, Art.BONE, 7, 0.35 * s, 0.6 * s)
