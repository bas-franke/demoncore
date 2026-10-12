class_name TrainingDummyEnemy
extends Enemy
## The Proving Pit's straw angel: an ordinary Enemy (so every weapon, ability and status lands on
## it) that can never die. HP refills before each hit and die() is refused, so even executes,
## doom and one-shots leave it standing. Created by HubPit with harmless EnemyData.


func take_damage(amount: float, knockback := Vector3.ZERO) -> void:
	if hp < max_hp * 0.5:
		hp = max_hp
	super.take_damage(amount, knockback)


func die() -> void:
	# Straw doesn't die; it just gets restuffed.
	hp = max_hp
