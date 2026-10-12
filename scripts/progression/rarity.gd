class_name Rarity
## Item rarity tiers shared by level-up boons, relics and drops.
## Rolling is weighted; luck (0 = none, 1 = +100%) shifts weight from Common toward the rarer tiers.

enum { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const IDS: Array[StringName] = [&"common", &"uncommon", &"rare", &"epic", &"legendary"]
const NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
## Base roll weights (sum 100).
const WEIGHTS := [62.0, 24.0, 10.0, 3.3, 0.7]
## How strongly luck multiplies each tier's weight (common shrinks, rarer tiers grow).
const LUCK_SCALE := [-0.5, 0.6, 1.2, 2.0, 3.0]
## Level-up boons: multiplier on the passive's amount_per_level at each tier.
const BOON_POWER := [1.0, 1.3, 1.6, 2.0, 2.5]


static func id_of(tier: int) -> StringName:
	return IDS[clampi(tier, 0, IDS.size() - 1)]


static func from_id(id: Variant) -> int:
	var i := IDS.find(StringName(str(id)))
	return maxi(i, 0)


## Colors come from UIPalette.RARITY_COLORS so boons, relics and shop cards all match.
static func color(tier: int) -> Color:
	return UIPalette.rarity_color(id_of(tier))


static func display_name(tier: int) -> String:
	return NAMES[clampi(tier, 0, NAMES.size() - 1)]


## Weighted roll. `min_tier` floors the result (e.g. bosses never drop commons).
static func roll(luck: float = 0.0, min_tier: int = COMMON, max_tier: int = LEGENDARY) -> int:
	var weights: Array[float] = []
	var total := 0.0
	for i in WEIGHTS.size():
		var w := 0.0
		if i >= min_tier and i <= max_tier:
			w = maxf(WEIGHTS[i] * (1.0 + LUCK_SCALE[i] * luck), 0.05)
		weights.append(w)
		total += w
	var r := randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0 and weights[i] > 0.0:
			return i
	return clampi(max_tier, min_tier, LEGENDARY)
