class_name TextFormat
## Small, shared text formatting helpers (Roman numerals, run clock). Static only.
##
## Several screens used to carry their own copy of these; call these instead so ranks, waves
## and timers read the same everywhere. Owned by code-quality (docs/team/code-quality.md).

const _ROMAN_VALUES: Array[int] = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
const _ROMAN_SYMBOLS: Array[String] = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]


## Roman numeral for `n` ("IV", "XII"). 0 gives "" (an unranked item shows no rank);
## negative numbers fall back to plain digits.
static func roman(n: int) -> String:
	if n < 0:
		return str(n)
	var out := ""
	for i in _ROMAN_VALUES.size():
		while n >= _ROMAN_VALUES[i]:
			out += _ROMAN_SYMBOLS[i]
			n -= _ROMAN_VALUES[i]
	return out


## Run-timer text: "mm:ss" (minutes keep counting past 59, e.g. "75:03").
static func clock(seconds: float) -> String:
	var t := maxi(int(seconds), 0)
	@warning_ignore("integer_division")  # whole minutes on purpose
	return "%02d:%02d" % [t / 60, t % 60]
