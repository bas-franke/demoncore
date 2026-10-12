class_name EnemyData
extends Resource
## Defines an enemy type. Create a new .tres in data/enemies/ and add it to a SpawnRule.

## CHASE: walks straight at the player. SHOOT: keeps its distance and fires `projectile`.
## CHARGE: winds up, then dashes in a locked direction for `charge_time`.
## HOP: crouches, then leaps onto where the player is (stomps on landing; landing circle shown).
## SLAM: closes in, raises its weapon over a telegraphed circle ahead of it, then strikes it.
## HEAL: hangs back behind its allies and channels a healing circle (heal_*) on wounded ones.
## SHIELD: walks with the host, wards nearby allies (ward_*: they take less damage, a halo shows)
##   and slams like SLAM when the demon is close.
## KITE: a skittish SHOOT: backs away whenever the demon closes in, fires while retreating.
## EXPLODE: sprints at the demon, lights a fuse within preferred_distance (circle telegraph for
##   windup_time) and detonates (explode_*). Killing it first defuses it.
## SUMMON: keeps its distance and calls `summon` minions (summon_*) beside itself.
## (New values are appended so existing .tres files keep their numbers.)
enum Behavior { CHASE, SHOOT, CHARGE, HOP, SLAM, HEAL, SHIELD, KITE, EXPLODE, SUMMON }

## Stable id (bestiary, saves), e.g. &"choir_wisp".
@export var id: StringName = &""
@export var display_name := "Enemy"
## One or two lines of lore for the bestiary.
@export_multiline var flavor_text := ""
## An EnemyModel scene (res://scenes/enemies/models/*.tscn).
@export var model: PackedScene
## Uniform scale for the model and the collision capsule.
@export var size := 1.0
## Extra height for flying enemies.
@export var hover := 0.0
@export var max_hp := 10.0
@export var speed := 3.0
## Damage per second dealt while touching the player.
@export var damage := 10.0
@export var xp_value := 1
## 0 = immune to knockback, 1 = normal.
@export var knockback_scale := 1.0

@export_group("Behavior")
@export var behavior := Behavior.CHASE
## SHOOT: distance kept from the player. CHARGE / SLAM: distance at which the attack starts.
@export var preferred_distance := 7.0
## Seconds between attacks (SHOOT, CHARGE, HOP and SLAM).
@export var attack_cooldown := 2.5
## SHOOT: projectile scene (needs `velocity: Vector3` and `damage: float` properties).
## Null = the holy orb.
@export var projectile: PackedScene
@export var projectile_damage := 8.0
@export var projectile_speed := 7.0
## SHOOT / KITE: draw the shot's lane on the ground during the wind-up; the aim locks at
## AIM_LOCK of the wind-up, so a side-step dodges it (siege weapons, snipers).
@export var aim_line := false
## SHOOT: height (before size scaling) the projectile leaves the model at.
@export var muzzle_height := 0.6
## SHOOT: seconds standing still after a shot (the model's "attack" clip is stretched over it,
## unless the model plays it at real speed).
@export var shot_recover_time := 0.3
## CHARGE: dash speed. HOP: max horizontal hop speed.
@export var charge_speed := 13.0
## CHARGE: dash duration. HOP: air time of one leap. SLAM: duration of the downswing.
@export var charge_time := 0.6
## Seconds spent winding up before shooting / charging / leaping / slamming.
@export var windup_time := 0.6
## SLAM: radius of the struck circle (world units).
@export var slam_radius := 2.6
## SLAM: distance from the enemy to the circle's center (world units).
@export var slam_reach := 1.6
## SLAM: damage dealt to the player inside the circle.
@export var slam_damage := 28.0

## Any behaviour: below this HP fraction the enemy frenzies once (speed x enrage_speed_mult,
## attack cooldowns x 0.6, red flash). 0 = never. (Flagellants, berserkers, wounded beasts.)
@export_range(0.0, 1.0) var enrage_hp := 0.0
@export var enrage_speed_mult := 1.5

@export_group("Support")
## HEAL: radius of the healing circle and the fraction of each ally's max HP restored.
@export var heal_radius := 5.0
@export var heal_fraction := 0.3
## SHIELD: allies within ward_radius take (1 - ward_reduction) damage; at most ward_max of them.
@export var ward_radius := 4.5
@export var ward_reduction := 0.5
@export var ward_max := 6
## EXPLODE: blast radius and damage.
@export var explode_radius := 2.2
@export var explode_damage := 24.0
## EXPLODE: damage to other angels in the blast, as a multiple of explode_damage (scaled with enemy
## HP growth). Luring a bomber into the crowd is a tactic; kills by the blast count as the demon's.
@export var explode_ally_mult := 2.5
## SUMMON: minion type (null = cherub), minions per cast, and the cap alive per summoner.
@export var summon: EnemyData
@export var summon_count := 3
@export var summon_max := 6
