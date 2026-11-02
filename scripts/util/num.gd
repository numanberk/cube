class_name Num
extends RefCounted
## Number and time formatting for the UI.

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

## "short" (1.50K, 2.50M) or "scientific" (1.50e3). Set from Settings.
static var notation := "short"


## 999 -> "999", 1500 -> "1.50K", 2.5e6 -> "2.50M", huge -> "1.23e45". Scientific notation: 1500 -> "1.50e3".
static func format(n: float) -> String:
	if n < 0.0:
		return "-" + format(-n)
	if n < 1000.0:
		if n < 10.0 and not is_equal_approx(n, floorf(n)):
			return "%.1f" % n
		return str(int(floorf(n)))
	var tier := int(floorf(log(n) / log(1000.0)))
	if notation == "short" and tier < SUFFIXES.size():
		var scaled := n / pow(1000.0, tier)
		var digits := "%.2f" if scaled < 100.0 else "%.1f"
		return (digits % scaled) + SUFFIXES[tier]
	var exponent := int(floorf(log(n) / log(10.0)))
	return "%.2fe%d" % [n / pow(10.0, exponent), exponent]


## 75 -> "1m 15s", 7300 -> "2h 1m"
static func format_duration(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]
