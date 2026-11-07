extends RefCounted
## The pacing targets from PLAN §2 as data, checked against simulator results.
## Used by tests/test_runner.gd (test_pacing_targets) and by tools/simulate.gd (docs/BALANCE.md).
##
## Each target has:
##   id, text (shown in BALANCE.md), profile ("tapping" or "idle"), type + its fields,
##   expected_failure: why today's content can't meet it yet ("" = it must pass).
## An expected failure prints but doesn't fail the tests. When balance work makes one pass, the test
## fails on purpose ("now passes"), so the session that fixed it removes the mark and the target stays met.
##
## Types:
##   first_by      first purchase of `kind` ("" = anything) at or before `max` seconds
##   item_between  first purchase of `kind`/`item` between `min` and `max` seconds
##   max_gap       no wait longer than `max` seconds for a new item between `from` and `to` seconds
##   split_mix     at checkpoint `minute`, the bot's split uses 2+ puzzles and none above `max_share`
##   unsupported   the simulator can't measure it yet (`reason` says what's missing); always an expected failure
##   second_run    the second run (after the bot's first World Championship) earns the first run's Solves within
##                 `max_fraction` of the first run's time and at most `max_minutes` (6.4)
##   second_run_item  `kind`/`item` is bought in the second run
##   tap_share     at checkpoint `minute`, taps give at least `min` of the profile's income (S.7)
##   speedup       how many times sooner `profile` reaches the lifetime Solves `baseline` has at `minute`, between `min`
##                 and `max` (D13's "2–3×": the early economy compounds, so a raw Solves ratio would be far bigger)

const TAPS_PER_SEC := 3.0  ## "Tapping" in PLAN §2
const TAPPING_MINUTES := 120.0  ## the first run's cap; the bot competes before it (6.4)
const TAPPING_PRESTIGE := {"second_run_minutes": 60.0}  ## the tapping profile plays a second run after competing
const IDLE_MINUTES := 10.0
const ACTIVE_MINUTES := 30.0
const ACTIVE_HAND := {"tier": 2}  ## the "active" profile: Gold-pace hand solves back to back (S.3)

const TARGETS: Array[Dictionary] = [
	{
		"id": "first_helper", "text": "First helper ≤ 20 s", "profile": "tapping",
		"type": "first_by", "kind": "helper", "max": 20.0,
		"expected_failure": "",
	},
	{
		"id": "first_upgrade", "text": "First upgrade < 1 min", "profile": "tapping",
		"type": "first_by", "kind": "upgrade", "max": 59.9,
		"expected_failure": "",
	},
	{
		"id": "new_every_3_min", "text": "Something new every ≤ 3 min in the first hour", "profile": "tapping",
		"type": "max_gap", "from": 0.0, "to": 3600.0, "max": 180.0,
		"expected_failure": "",
	},
	{
		"id": "new_every_10_min", "text": "Something new every ≤ 10 min after the first hour", "profile": "tapping",
		"type": "max_gap", "from": 3600.0, "to": 7200.0, "max": 600.0,
		"expected_failure": "",
	},
	{
		"id": "puzzle_3x3", "text": "3×3 unlocked at ~5 min (4–6 min)", "profile": "tapping",
		"type": "item_between", "kind": "puzzle", "item": "3x3", "min": 240.0, "max": 360.0,
		"expected_failure": "",
	},
	{
		"id": "taps_matter", "text": "Taps give ≥ 10 % of income at 30 min (3 turns/s, S.7)", "profile": "tapping",
		"type": "tap_share", "minute": 30.0, "min": 0.1,
		"expected_failure": "",
	},
	{
		"id": "robot", "text": "Solving Robot at ~10 min (8–12 min)", "profile": "tapping",
		"type": "item_between", "kind": "helper", "item": "robot", "min": 480.0, "max": 720.0,
		"expected_failure": "",
	},
	{
		"id": "puzzle_4x4", "text": "4×4 unlocked at ~30 min (25–35 min)", "profile": "tapping",
		"type": "item_between", "kind": "puzzle", "item": "4x4", "min": 1500.0, "max": 2100.0,
		"expected_failure": "",
	},
	{
		"id": "puzzle_5x5", "text": "5×5 unlocked at ~60 min (50–70 min)", "profile": "tapping",
		"type": "item_between", "kind": "puzzle", "item": "5x5", "min": 3000.0, "max": 4200.0,
		"expected_failure": "",
	},
	{
		"id": "first_prestige", "text": "First World Championship at ~90 min (80–100 min, D6)", "profile": "tapping",
		"type": "item_between", "kind": "prestige", "item": "compete", "min": 4800.0, "max": 6000.0,
		"expected_failure": "",
	},
	{
		"id": "seven_by_seven", "text": "7×7 in the 2nd–3rd run (measured: in the 2nd run)", "profile": "tapping",
		"type": "second_run_item", "kind": "puzzle", "item": "7x7",
		"expected_failure": "",
	},
	{
		"id": "megaminx", "text": "Megaminx in the 4th–5th run", "profile": "tapping",
		"type": "unsupported", "reason": "the simulator plays two runs",
		"expected_failure": "Needs a simulator that plays 5 runs (too slow for the tests today; a later tuning task).",
	},
	{
		"id": "second_run", "text": "Second run reaches the same point in ≤ 50 % of the time and ≤ 45 min", "profile": "tapping",
		"type": "second_run", "max_fraction": 0.5, "max_minutes": 45.0,
		"expected_failure": "",
	},
	{
		"id": "split_mix", "text": "The bot's best split at 30 min is a real mix (no puzzle above 70 %)", "profile": "tapping",
		"type": "split_mix", "minute": 30.0, "max_share": 0.7,
		"expected_failure": "",
	},
	{
		"id": "active_speedup", "text": "An active player (Gold-pace hand solves) gets there 2–3× sooner than the tapping bot (D13)",
		"profile": "active", "type": "speedup", "baseline": "tapping", "minute": 30.0, "min": 2.0, "max": 3.0,
		"expected_failure": "",
	},
	{
		"id": "idle_progress", "text": "Never tapping still buys something within 5 min", "profile": "idle",
		"type": "first_by", "kind": "", "max": 300.0,
		"expected_failure": "",
	},
]


## Checks every target. `results` maps a profile ("tapping"/"idle") to a Simulator.run() result.
## Returns [{id, text, passed, actual, expected_failure, status}] where status is
## "pass", "expected failure", "FAIL" (missed a real target) or "NOW PASSES" (remove expected_failure).
static func evaluate(results: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for target: Dictionary in TARGETS:
		var outcome := {"passed": false, "actual": "profile '%s' not simulated" % target["profile"]}
		if target["type"] == "unsupported":
			outcome = {"passed": false, "actual": "not measured: %s" % target["reason"]}
		elif target["type"] == "speedup":
			outcome = _check_speedup(target, results)
		elif results.has(target["profile"]):
			outcome = check(target, results[target["profile"]])
		var expected: String = target.get("expected_failure", "")
		var status := ""
		if outcome["passed"]:
			status = "NOW PASSES" if expected != "" else "pass"
		else:
			status = "expected failure" if expected != "" else "FAIL"
		rows.append({
			"id": target["id"], "text": target["text"], "passed": outcome["passed"],
			"actual": outcome["actual"], "expected_failure": expected, "status": status,
		})
	return rows


## Checks one target against one simulator result. Returns {passed, actual}.
static func check(target: Dictionary, result: Dictionary) -> Dictionary:
	var events: Array = result["events"]
	var run_end := float(result.get("first_run_minutes", result["minutes"])) * 60.0
	match target["type"]:
		"first_by":
			for e: Dictionary in events:
				if target["kind"] == "" or e["kind"] == target["kind"]:
					return {"passed": float(e["t"]) <= float(target["max"]), "actual": "%s at %s" % [e["name"], clock(e["t"])]}
			return {"passed": false, "actual": "nothing bought in %s" % clock(run_end)}
		"item_between":
			for e: Dictionary in events:
				if e["kind"] == target["kind"] and e["id"] == target["item"]:
					var t := float(e["t"])
					return {"passed": t >= float(target["min"]) and t <= float(target["max"]), "actual": clock(t)}
			return {"passed": false, "actual": "never (in %s)" % clock(run_end)}
		"split_mix":
			for c: Dictionary in result.get("checkpoints", []):
				if is_equal_approx(float(c["minute"]), float(target["minute"])):
					var split: Dictionary = c.get("split", {})
					var top := 0.0
					for id: String in split:
						top = maxf(top, float(split[id]))
					var text := "%s" % ("one puzzle only" if split.size() < 2 else _split_text(split))
					return {"passed": split.size() >= 2 and top <= float(target["max_share"]) + 0.001, "actual": text}
			return {"passed": false, "actual": "no checkpoint at %s min" % target["minute"]}
		"tap_share":
			for c: Dictionary in result.get("checkpoints", []):
				if is_equal_approx(float(c["minute"]), float(target["minute"])):
					var share := float(c.get("tap_share", 0.0))
					return {"passed": share >= float(target["min"]), "actual": "%.1f %% of income" % (share * 100.0)}
			return {"passed": false, "actual": "no checkpoint at %s min" % target["minute"]}
		"second_run":
			var first := float(result.get("prestige_at", -1.0))
			var second: Dictionary = result.get("second_run", {})
			var reached := float(second.get("reached_at", -1.0))
			if first < 0.0:
				return {"passed": false, "actual": "never competed (in %s)" % clock(run_end)}
			if reached < 0.0:
				return {"passed": false, "actual": "not caught up in %s min" % second.get("minutes", 0)}
			var limit := minf(first * float(target["max_fraction"]), float(target["max_minutes"]) * 60.0)
			return {"passed": reached <= limit, "actual": "%s (%d %% of the first run's %s)" % [
					clock(reached), roundi(reached / first * 100.0), clock(first)]}
		"second_run_item":
			for e: Dictionary in result.get("second_run", {}).get("events", []):
				if e["kind"] == target["kind"] and e["id"] == target["item"]:
					return {"passed": true, "actual": "%s into the 2nd run" % clock(float(e["t"]) - float(result["prestige_at"]))}
			return {"passed": false, "actual": "not in the 2nd run"}
		"max_gap":
			var from := float(target["from"])
			var to := minf(float(target["to"]), run_end)
			if to <= from:
				return {"passed": false, "actual": "run too short (%s)" % clock(run_end)}
			var gap := longest_gap(events, from, to)
			return {"passed": gap["length"] <= float(target["max"]), "actual": "longest %s (%s)" % [clock(gap["length"]), gap["where"]]}
	push_error("Unknown pacing target type '%s'" % target["type"])
	return {"passed": false, "actual": "unknown target type"}


static func _check_speedup(target: Dictionary, results: Dictionary) -> Dictionary:
	if not results.has(target["profile"]) or not results.has(target["baseline"]):
		return {"passed": false, "actual": "profiles '%s'/'%s' not simulated" % [target["profile"], target["baseline"]]}
	var at := float(target["minute"]) * 60.0
	var goal := -1.0
	for sample: Array in results[target["baseline"]].get("samples", []):
		if float(sample[0]) <= at:
			goal = float(sample[1])
	var reached := -1.0
	for sample: Array in results[target["profile"]].get("samples", []):
		if float(sample[1]) >= goal:
			reached = float(sample[0])
			break
	if goal <= 0.0 or reached <= 0.0:
		return {"passed": false, "actual": "never reached the tapping bot's %s-min total" % target["minute"]}
	var speedup := at / reached
	return {"passed": speedup >= float(target["min"]) and speedup <= float(target["max"]),
			"actual": "×%.2f (the tapping bot's %s Solves at %s, the active one at %s)" % [speedup, Num.format(goal), clock(at), clock(reached)]}


static func _split_text(split: Dictionary) -> String:
	var parts := PackedStringArray()
	for id: String in split:
		parts.append("%s %d %%" % [Content.get_puzzle(id)["name"], roundi(float(split[id]) * 100.0)])
	return " · ".join(parts)


## Longest stretch inside [from, to] with no first purchase. Returns {length, where}.
static func longest_gap(events: Array, from: float, to: float) -> Dictionary:
	var times: Array[float] = [0.0]
	var names: Array[String] = ["the start"]
	for e: Dictionary in events:
		times.append(float(e["t"]))
		names.append(e["name"])
	times.append(INF)
	names.append("")
	var best := {"length": 0.0, "where": "none"}
	for i in times.size() - 1:
		var a := maxf(times[i], from)
		var b := minf(times[i + 1], to)
		if b - a > best["length"]:
			best["length"] = b - a
			var ending := "until %s" % clock(to) if times[i + 1] > to else "before %s" % names[i + 1]
			best["where"] = "after %s, %s" % [names[i], ending]
	return best


## Markdown section for BALANCE.md.
static func to_markdown(rows: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	lines.append("## Pacing targets (PLAN §2)")
	lines.append("")
	lines.append("Checked by `test_pacing_targets` in `tests/test_runner.gd`. \"Tapping\" = %s taps/s." % TAPS_PER_SEC)
	lines.append("")
	lines.append("| Target | Actual | Status |")
	lines.append("|---|---|---|")
	for row: Dictionary in rows:
		lines.append("| %s | %s | %s |" % [row["text"], row["actual"], row["status"]])
	lines.append("")
	lines.append("### Expected failures")
	lines.append("")
	lines.append("Targets today's content can't meet yet. They print in the tests but don't fail them.")
	lines.append("Remove a target's `expected_failure` in `tools/pacing.gd` once it passes.")
	lines.append("")
	var any := false
	for row: Dictionary in rows:
		if row["expected_failure"] != "":
			lines.append("- **%s** — %s" % [row["text"], row["expected_failure"]])
			any = true
	if not any:
		lines.append("None. Every target is met.")
	lines.append("")
	return "\n".join(lines)


## Seconds as m:ss (or h:mm:ss).
static func clock(seconds: float) -> String:
	var s := int(round(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
