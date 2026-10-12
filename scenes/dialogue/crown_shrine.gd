class_name CrownShrine
extends HubInteractable
## The Sinbound Crown, shown in Basecamp Hell after the ending (story.ended): Grimmaul's crown on
## an obsidian pillar, slowly turning in a ring of hellfire light. Interacting plays the "crown"
## pool (narration that changes with the post-ending story). Spawned by StoryHooks.

var _crown: Node3D


func _ready() -> void:
	verb = "Behold"
	label = "The Sinbound Crown"
	radius = 2.2
	prompt_height = 2.6
	super._ready()
	var stone := Art.mat(Art.OBSIDIAN, 0.35, 0.2, 0.3, false, 0.0, &"stone")
	Art.part(self, Art.cylinder(0.32, 0.42), stone, Vector3(0.0, 0.6, 0.0), Vector3(1.0, 1.2, 1.0))
	Art.part(self, Art.cylinder(0.5, 0.55), stone, Vector3(0.0, 0.08, 0.0), Vector3(1.0, 0.16, 1.0))
	_crown = Art.pivot(self, Vector3(0.0, 1.45, 0.0))
	var gold := Art.mat(Art.GOLD.darkened(0.15), 0.3, 1.0, 0.3, false, 0.0, &"gold")
	var iron := Art.mat(Art.OBSIDIAN.lightened(0.1), 0.5, 0.9, 0.5, false, 0.0, &"metal")
	Art.part(_crown, Art.torus(0.26, 0.32), iron, Vector3.ZERO, Vector3(1.0, 1.6, 1.0))
	for k in 7:
		var a := TAU * k / 7.0
		var spike_h := 0.32 if k % 2 == 0 else 0.22
		Art.part(_crown, Art.cone(0.5), gold, Vector3(cos(a) * 0.29, 0.12 + spike_h * 0.5, sin(a) * 0.29),
				Vector3(0.07, spike_h, 0.07))
	Art.part(_crown, Art.sphere(), Art.glow(Art.HELLFIRE, 3.0), Vector3(0.0, 0.05, -0.3), Vector3.ONE * 0.07)
	Art.light(self, Art.EMBER, 1.2, 3.5, Vector3(0.0, 1.6, 0.0))


func _process(delta: float) -> void:
	super._process(delta)
	_crown.rotation.y += delta * 0.4
	_crown.position.y = 1.45 + 0.04 * sin(_t * 1.5)


func interact() -> void:
	super.interact()
	if not Dialogue.is_active():
		Dialogue.bark("crown", true)
