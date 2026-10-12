class_name Danger
extends RefCounted
## One query for "is this spot about to be hit?" across every telegraph convention in the game
## (core-gameplay role, docs/team/gameplay.md). Used by the Autopilot; AI, allies or abilities may
## use it too.
##
##   Danger.threat_at(tree, pos, margin) -> Vector3   flat push-away direction (ZERO = safe)
##   Danger.is_threatened(tree, pos, margin) -> bool
##
## Recognised, in groups:
##   "danger_zones"  HolyTelegraph (enemy wind-ups): contains(p, margin) + danger_center()
##   "boss_hazards"  duck-typed by their exported fields:
##       lane   (dir, length, width)            InquisitorLane
##       sector (radius, dir, half_angle)       PyreBurst
##       disc   (radius)                        JudgementPillar
##       ring   (max_radius, width, _r)         BellRing (only its current front)
##       orb    (velocity)                      SarielOrb: a short lane ahead of it
##   "enemy_shots"   every projectile an Enemy fires (Enemy._fire adds it): treated as an orb
## Any node in either group may instead implement `danger_contains(p: Vector3, margin: float) -> bool`
## (and optionally `danger_center() -> Vector3`); that wins over the duck typing.


static func is_threatened(tree: SceneTree, pos: Vector3, margin: float = 0.0) -> bool:
	return threat_at(tree, pos, margin) != Vector3.ZERO


static func threat_at(tree: SceneTree, pos: Vector3, margin: float = 0.0) -> Vector3:
	var push := Vector3.ZERO
	for n in tree.get_nodes_in_group(&"danger_zones"):
		push += _push(n as Node3D, pos, margin)
	for n in tree.get_nodes_in_group(&"boss_hazards"):
		push += _push(n as Node3D, pos, margin)
	for n in tree.get_nodes_in_group(&"enemy_shots"):
		push += _push(n as Node3D, pos, margin)
	push.y = 0.0
	return push.normalized() if push.length_squared() > 0.0001 else Vector3.ZERO


## Push-away vector from one hazard (ZERO when `pos` is outside it).
static func _push(h: Node3D, pos: Vector3, margin: float) -> Vector3:
	if h == null or not h.is_inside_tree() or not h.is_visible_in_tree():
		return Vector3.ZERO
	var center := h.global_position
	var inside := false
	if h.has_method(&"danger_contains"):
		inside = bool(h.call(&"danger_contains", pos, margin))
		if h.has_method(&"danger_center"):
			center = h.call(&"danger_center")
	elif h is HolyTelegraph:
		var t := h as HolyTelegraph
		inside = t.contains(pos, margin)
		center = t.danger_center()
	elif &"length" in h and &"width" in h and &"dir" in h:
		var d: Vector3 = h.get(&"dir")
		d.y = 0.0
		d = d.normalized()
		var rel := pos - center
		rel.y = 0.0
		var along := rel.dot(d)
		inside = along > -margin and along < float(h.get(&"length")) + margin \
				and (rel - d * along).length() < float(h.get(&"width")) * 0.5 + margin
		center = center + d * clampf(along, 0.0, float(h.get(&"length")))
	elif &"max_radius" in h and &"_r" in h:
		var r: float = h.get(&"_r")
		var w: float = float(h.get(&"width")) if &"width" in h else 0.8
		var dist := Vector2(pos.x - center.x, pos.z - center.z).length()
		inside = absf(dist - r) < w * 0.5 + margin + 0.6  # the front is about to sweep over us
	elif &"radius" in h:
		var r: float = h.get(&"radius")
		var rel := pos - center
		rel.y = 0.0
		inside = rel.length() < r + margin
		if inside and &"half_angle" in h and &"dir" in h and float(h.get(&"half_angle")) < PI:
			var d: Vector3 = h.get(&"dir")
			d.y = 0.0
			inside = rel.length() < 0.5 or rel.normalized().angle_to(d.normalized()) < float(h.get(&"half_angle"))
	elif &"velocity" in h:
		var v: Vector3 = h.get(&"velocity")
		v.y = 0.0
		if v.length_squared() > 0.01:
			var d := v.normalized()
			var rel := pos - center
			rel.y = 0.0
			var along := rel.dot(d)
			inside = along > -0.5 and along < v.length() * 0.8 and (rel - d * along).length() < 0.9 + margin
			if inside:
				# Sidestep perpendicular to the shot, not away from it.
				var side := Vector3(-d.z, 0.0, d.x)
				return side if side.dot(rel) >= 0.0 else -side
	if not inside:
		return Vector3.ZERO
	var away := pos - center
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	return away.normalized()
