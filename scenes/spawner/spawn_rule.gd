class_name SpawnRule
extends Resource
## "Spawn this enemy between these times, with this relative weight."

@export var enemy: EnemyData
## Seconds into the run when this rule starts.
@export var start_time := 0.0
## Seconds into the run when this rule stops. -1 = never.
@export var end_time := -1.0
@export var weight := 1.0


func is_active(t: float) -> bool:
	return t >= start_time and (end_time < 0.0 or t < end_time)
