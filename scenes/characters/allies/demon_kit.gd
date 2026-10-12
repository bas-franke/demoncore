class_name DemonKit
extends ProcModel
## Shared look for the demonic characters (allies, Basecamp NPCs): ember death instead of holy
## light, and helpers for horns, bat wings, tails and glowing eyes. Demonic models extend this.

## Ember/ash colour for eyes and inner fire.
const EMBER_EYE := Color(1.0, 0.45, 0.1)

## Bat-wing pivots (animated by flap() in pose()).
var bat_wings: Array[Node3D] = []
var _tail_segments: Array[Node3D] = []


func _ready() -> void:
	# Demons die in embers, not in light and feathers.
	light_color = Art.EMBER
	feather_count = 0
	mote_count = 6
	debris = [&"mote"]
	debris_color = Art.EMBER
	super._ready()
	# Ember rim on the silhouette, like the player demon (docs/team/art-style.md).
	ArtStyle.apply_faction(self, ArtStyle.Faction.DEMON)


## A pair of curved horns on `head`: `n` stacked tapering segments curling back and out.
func horns(head: Node3D, pos: Vector3, length: float, thick: float, mat: Material, curl: float = 0.6,
		spread: float = 0.5) -> void:
	for s: float in [-1.0, 1.0]:
		var p := Art.pivot(head, Vector3(s * pos.x, pos.y, pos.z), Vector3(-0.2, 0.0, -s * spread))
		var segs := 3
		var cur := p
		for i in segs:
			var f := float(i) / float(segs)
			var seg_len := length / float(segs)
			var r := thick * (1.0 - f * 0.6)
			Art.part(cur, Art.cylinder(r * 0.8, r), mat, Vector3(0.0, seg_len * 0.5, 0.0), Vector3(1.0, seg_len, 1.0))
			cur = Art.pivot(cur, Vector3(0.0, seg_len * 0.95, 0.0), Vector3(curl / float(segs), 0.0, -s * 0.1))
		Art.part(cur, Art.cone(0.5), mat, Vector3(0.0, thick * 0.6, 0.0), Vector3(thick * 0.8, thick * 1.6, thick * 0.8))


## A leathery bat wing pair: a bone arm with finger struts and membrane panels between them.
## Registered as animated; flap them with flap().
func bat_wing_pair(parent: Node3D, pos: Vector3, span: float, bone: Material, membrane: Material,
		gap: float = 0.06) -> void:
	for s: float in [-1.0, 1.0]:
		var root := animated(Art.pivot(parent, pos + Vector3(s * gap, 0.0, 0.0)))
		limb(root, Vector3.ZERO, Vector3(s * span * 0.45, span * 0.18, 0.04), span * 0.025, bone)
		var tip := Vector3(s * span * 0.45, span * 0.18, 0.04)
		# Three finger struts fanning down and back, with membrane panels between.
		var prev := Vector3(s * span * 0.08, -span * 0.02, 0.05)
		for k in 3:
			var f := float(k + 1) / 3.0
			var end := tip + Vector3(s * span * lerpf(0.5, 0.15, f), -span * lerpf(0.05, 0.55, f), span * lerpf(0.1, 0.18, f))
			limb(root, tip, end, span * 0.012, bone)
			# Panel: a thin box spanning tip -> end -> previous edge (approximate with a flat sphere).
			var mid := (tip + end + prev) / 3.0
			var w := (end - prev).length()
			var panel := Art.part(root, Art.sphere(), membrane, mid, Vector3(w * 0.9, span * 0.01, (tip - mid).length() * 2.0))
			panel.basis = Basis.looking_at((tip - mid).normalized(), Vector3.UP if absf((tip - mid).normalized().y) < 0.95 else Vector3.BACK) \
					* Basis.from_scale(Vector3(w * 0.9, span * 0.01, (tip - mid).length() * 2.0))
			prev = end
		Art.part(root, Art.cone(0.5), bone, tip + Vector3(0.0, span * 0.04, 0.0), Vector3.ONE * span * 0.05)
		bat_wings.append(root)


## Beats the bat wings: `speed` beats/s-ish, `amp` radians, `fold` 0..1 folds them back.
func flap(speed: float, amp: float, fold: float = 0.0) -> void:
	for i in bat_wings.size():
		var s := -1.0 if i % 2 == 0 else 1.0
		var w := sin(t * speed)
		bat_wings[i].rotation = Vector3(0.0, s * (0.35 + fold * 0.9), s * (w * amp + 0.2 - fold * 0.4))


## A segmented tail with a spade tip, hanging back from `pos`. Sway it with sway_tail().
func tail(parent: Node3D, pos: Vector3, length: float, thick: float, mat: Material, tip_mat: Material = null) -> void:
	var cur := animated(Art.pivot(parent, pos, Vector3(1.2, 0.0, 0.0)))
	for i in 4:
		var f := float(i) / 4.0
		var seg := length / 4.0
		limb(cur, Vector3.ZERO, Vector3(0.0, seg, 0.0), thick * (1.0 - f * 0.5), mat)
		_tail_segments.append(cur)
		cur = animated(Art.pivot(cur, Vector3(0.0, seg, 0.0), Vector3(0.25, 0.0, 0.0)))
	Art.part(cur, Art.prism(), tip_mat if tip_mat else mat, Vector3(0.0, thick * 1.5, 0.0), Vector3(thick * 4.0, thick * 4.0, thick * 0.8))


func sway_tail(amount: float = 0.3, speed: float = 2.0) -> void:
	for i in _tail_segments.size():
		_tail_segments[i].rotation.z = sin(t * speed - float(i) * 0.6) * amount
		_tail_segments[i].rotation.x = (1.2 if i == 0 else 0.25) + sin(t * speed * 0.7 - float(i)) * amount * 0.3


## Two glowing slit eyes on `head`.
func ember_eyes(head: Node3D, pos: Vector3, size: float, color: Color = EMBER_EYE) -> void:
	for s: float in [-1.0, 1.0]:
		Art.part(head, Art.sphere(), Art.glow(color, 2.6), Vector3(s * pos.x, pos.y, pos.z), Vector3(size, size * 0.5, size * 0.4))
