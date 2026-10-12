extends EnemyModel
## "Dawn Lancer": a winged knight of the first light. Glides leaning far forward on great swept
## wings, legs trailing, a very long ornate lance couched under its arm (pennant streaming from
## below the burning point), crested great helm crowned with gold sun-rays, cape and tabard in the wind.
## Blender model: fly (glide loop) / windup (rears back, lance lowers and kindles, wings gather -
## the charge telegraph) / attack (the dash: flattened behind the lance, wings swept back; held
## for the whole charge) / hit / death (wings fail, it falls out of the air and the wings crumple).
## The corpse lives as long as the death clip (impact at 0.8 s, crumple until ~1.8 s).

const MODEL := "res://assets/models/enemies/dawn_lancer.glb"


func build() -> void:
	feather_count = 6
	debris = [&"steel", &"gold"]
	debris_color = Art.GOLD
	move_anim = &"fly"
	idle_anim = &"fly"
	move_speed_min = 0.8
	move_speed_max = 1.2
	# The windup's last pose and the attack's first pose meet exactly: near-hard cut into the
	# dash. After the charge, ease slowly back into the glide.
	blend_attack = 0.05
	blend_from_action = 0.28
	use_glb(MODEL)


func _on_state_enter(state: int) -> void:
	if state == State.WINDUP:
		Sfx.play(&"beam", 0.1, -8.0)


func play_attack() -> void:
	super.play_attack()
	Sfx.play(&"wingbeat", 0.1, -3.0)
