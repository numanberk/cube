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


## A speedcubing time as csTimer and the WCA write it: 9.87, 1:02.34. INF (a DNF) gives "DNF".
static func solve_time(seconds: float) -> String:
	if is_inf(seconds) or is_nan(seconds):
		return "DNF"
	var hundredths := int(floorf(seconds * 100.0 + 0.0001))  # WCA truncates to hundredths
	var minutes := hundredths / 6000
	var rest := hundredths % 6000
	if minutes > 0:
		return "%d:%02d.%02d" % [minutes, rest / 100, rest % 100]
	return "%d.%02d" % [rest / 100, rest % 100]


## A helper's or the team's solve time, as a cuber reads it: "1:23.45", "9.87 s", then "5.20 ms", "38.0 µs", "12 ns"
## once it's far faster than a human. INF (no helpers) is "—".
static func cube_time(seconds: float) -> String:
	if is_inf(seconds) or is_nan(seconds) or seconds < 0.0:
		return "—"
	if seconds >= 60.0:
		return solve_time(seconds)
	if seconds >= 0.01:
		return solve_time(seconds) + " s"
	for unit: Array in [[1e-3, "ms"], [1e-6, "µs"], [1e-9, "ns"]]:
		var value := seconds / float(unit[0])
		if value >= 1.0 or unit[1] == "ns":
			if value < 1.0:
				return "<1 ns"
			var digits := 0 if value >= 100.0 else (1 if value >= 10.0 else 2)
			return ("%." + str(digits) + "f %s") % [value, unit[1]]
	return "—"
