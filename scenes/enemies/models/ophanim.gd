extends EnemyModel
## "Ophanim": a wheel within a wheel within a wheel. Three gyroscopically nested golden rings,
## engraved with a burning inscription and set with lidded eyes, turn on their axle pins around
## a radiant core with a great burning eye. Small wings spring from the outer wheel's hubs and a
## crown of light hovers above. Hovers.
## Blender model: idle (the wheels turn at different speeds, eyes blink) / windup (the wheels
## spin up and lock into a bullseye facing the target, every eye opens wide, the core flares) /
## attack (pulse + recoil, the wheels spin back out) / hit (the wheels jolt, eyes squeeze shut) /
## death (the wheels stall, fall and settle flat on the ground, the light goes out).
## The base resume_loops picks the 8 s idle turn up where it left off after hit / attack instead
## of restarting it from the rest pose. The corpse lives as long as the death clip (~1.5 s).

const MODEL := "res://assets/models/enemies/ophanim.glb"


func build() -> void:
	feather_count = 2
	mote_count = 10
	debris = [&"gold", &"mote"]
	debris_color = Art.GOLD
	move_anim = &"idle"
	move_speed_min = 1.0
	move_speed_max = 1.35
	resume_loops = true
	# Heavy wheels: ease into the jolt and back out of the pulse.
	blend_hit = 0.12
	blend_from_action = 0.3
	use_glb(MODEL)


func _on_state_enter(state: int) -> void:
	if state == State.WINDUP:
		Sfx.play(&"choir", 0.15, -14.0)


func play_attack() -> void:
	super.play_attack()
	Sfx.play(&"beam", 0.12, -8.0)
