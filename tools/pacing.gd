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

const TAPS_PER_SEC := 3.0  ## "Tapping" in PLAN §2
const TAPPING_MINUTES := 120.0
const IDLE_MINUTES := 10.0

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
		"expected_failure": "Only 13 items exist; gaps up to 16 min. Needs puzzles, methods and milestones (Phases 4–5).",
	},
	{
		"id": "new_every_10_min", "text": "Something new every ≤ 10 min after the first hour", "profile": "tapping",
		"type": "max_gap", "from": 3600.0, "to": 7200.0, "max": 600.0,
		"expected_failure": "All content is owned by ~52 min. Needs more helpers and prestige (Phases 5–6).",
	},
	{
		"id": "puzzle_3x3", "text": "3×3 unlocked at ~5 min (4–6 min)", "profile": "tapping",
		"type": "item_between", "kind": "puzzle", "item": "3x3", "min": 240.0, "max": 360.0,
		"expected_failure": "",
	},
	{
		"id": "robot", "text": "Solving Robot at ~10 min (8–12 min)", "profile": "tapping",
		"type": "item_between", "kind": "helper", "item": "robot", "min": 480.0, "max": 720.0,
		"expected_failure": "Robot comes at ~15 min. Phase 4 rebalance.",
	},
	{
		"id": "puzzle_4x4", "text": "4×4 unlocked at ~30 min (25–35 min)", "profile": "tapping",
		"type": "item_between", "kind": "puzzle", "item": "4x4", "min": 1500.0, "max": 2100.0,
		"expected_failure": "Puzzles don't exist yet (task 4.1–4.2).",
	},
	{
		"id": "puzzle_5x5", "text": "5×5 unlocked at ~60 min (50–70 min)", "profile": "tapping",
		"type": "item_between", "kind": "puzzle", "item": "5x5", "min": 3000.0, "max": 4200.0,
		"expected_failure": "Puzzles don't exist yet (task 4.1–4.2).",
	},
	{
		"id": "first_prestige", "text": "First World Championship at ~90 min (80–100 min, D6)", "profile": "tapping",
		"type": "item_between", "kind": "prestige", "item": "compete", "min": 4800.0, "max": 6000.0,
		"expected_failure": "Prestige doesn't exist yet (Phase 6); the bot must learn to Compete (6.4).",
	},
	{
		"id": "big_puzzles", "text": "7×7 in the 2nd–3rd run, Megaminx in the 4th–5th run", "profile": "tapping",
		"type": "unsupported", "reason": "the simulator only plays one run (multi-run sim comes with 6.4)",
		"expected_failure": "Needs prestige and multi-run simulation (6.2, 6.4).",
	},
	{
		"id": "second_run", "text": "Second run reaches the same point in ≤ 50 % of the time", "profile": "tapping",
		"type": "unsupported", "reason": "the simulator only plays one run (multi-run sim comes with 6.4)",
		"expected_failure": "Needs prestige and multi-run simulation (6.2, 6.4).",
	},
	{
		"id": "split_mix", "text": "The bot's best split at 30 min is a real mix (no puzzle above 70 %)", "profile": "tapping",
		"type": "split_mix", "minute": 30.0, "max_share": 0.7,
		"expected_failure": "",
	},
	{
		"id": "idle_progress", "text": "Never tapping still buys something within 5 min", "profile": "idle",
		"type": "first_by", "kind": "", "max": 300.0,
		"expected_failure": "With no taps there's no income at all. Phase 4 (free first Friend or a trickle).",
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
	var run_end := float(result["minutes"]) * 60.0
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
		"max_gap":
			var from := float(target["from"])
			var to := minf(float(target["to"]), run_end)
			if to <= from:
				return {"passed": false, "actual": "run too short (%s)" % clock(run_end)}
			var gap := longest_gap(events, from, to)
			return {"passed": gap["length"] <= float(target["max"]), "actual": "longest %s (%s)" % [clock(gap["length"]), gap["where"]]}
	push_error("Unknown pacing target type '%s'" % target["type"])
	return {"passed": false, "actual": "unknown target type"}


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
