extends RefCounted
## Headless balance bot. Drives a real GameState (never a copy of its formulas),
## so the numbers can't drift from the game. Used by tools/simulate.gd and, later, by pacing tests.
##
##   var sim := preload("res://tools/simulator.gd").new()
##   var result := sim.run(3.0, 120.0)   # taps per second, minutes
##
## Strategy (greedy, "best payback"): every REPLAN_INTERVAL seconds and after each purchase, look at
## everything the player can see, and pick the item with the lowest
##     time to afford it + cost / income it adds
## then buy it as soon as it's affordable. Income counts helpers and taps.

const STEP := 0.1             ## simulated seconds per tick
const REPLAN_INTERVAL := 1.0  ## re-pick the target this often (and after every purchase)
const CHECKPOINT_MINUTES: Array[float] = [1.0, 5.0, 15.0, 30.0, 60.0, 120.0]


## Runs one game. Returns:
##   taps_per_sec, minutes,
##   events:      [{t, kind, id, name, cost}]  first purchase of each item, in order
##   purchases:   int                          total items bought
##   checkpoints: [{minute, solves_per_sec, moves_per_sec, solves, total_solves}]
##   all_bought_at: seconds when every helper and upgrade was owned at least once, or -1
func run(taps_per_sec: float, minutes: float) -> Dictionary:
	var g := GameState.new()
	g.persistence_enabled = false
	g.reset_state()

	var duration := minutes * 60.0
	var events: Array[Dictionary] = []
	var seen := {}
	var checkpoints: Array[Dictionary] = []
	var next_checkpoint := 0
	var purchases := 0
	var all_bought_at := -1.0
	var item_count := Content.BUILDINGS.size() + Content.UPGRADES.size()

	var t := 0.0
	var tap_credit := 0.0
	var replan_timer := 0.0
	var target := {}

	while t < duration:
		# Earn: taps, then helpers (same as GameState._process does each frame).
		tap_credit += taps_per_sec * STEP
		while tap_credit >= 1.0:
			tap_credit -= 1.0
			g.tap()
		g.add_moves(g.get_moves_per_second() * STEP)
		t += STEP

		# Spend.
		replan_timer -= STEP
		if target.is_empty() or replan_timer <= 0.0:
			target = _pick_target(g, taps_per_sec)
			replan_timer = REPLAN_INTERVAL
		while not target.is_empty() and g.solves >= _cost(g, target):
			var cost := _cost(g, target)
			if not _buy(g, target):
				break
			purchases += 1
			var key := "%s:%s" % [target["kind"], target["id"]]
			if not seen.has(key):
				seen[key] = true
				events.append({
					"t": t, "kind": target["kind"], "id": target["id"],
					"name": _item_name(target), "cost": cost,
				})
				if seen.size() == item_count and all_bought_at < 0.0:
					all_bought_at = t
			target = _pick_target(g, taps_per_sec)
			replan_timer = REPLAN_INTERVAL

		while next_checkpoint < CHECKPOINT_MINUTES.size() and t >= CHECKPOINT_MINUTES[next_checkpoint] * 60.0 - STEP * 0.5:
			if CHECKPOINT_MINUTES[next_checkpoint] <= minutes:
				checkpoints.append({
					"minute": CHECKPOINT_MINUTES[next_checkpoint],
					"solves_per_sec": income(g, taps_per_sec),
					"moves_per_sec": g.get_moves_per_second() + taps_per_sec * g.get_tap_moves(),
					"solves": g.solves,
					"total_solves": g.total_solves,
				})
			next_checkpoint += 1

	g.free()
	return {
		"taps_per_sec": taps_per_sec,
		"minutes": minutes,
		"events": events,
		"purchases": purchases,
		"checkpoints": checkpoints,
		"all_bought_at": all_bought_at,
	}


## Solves per second from helpers plus tapping at `taps_per_sec`.
func income(g: GameState, taps_per_sec: float) -> float:
	var tap_solves := taps_per_sec * g.get_tap_moves() / g.get_moves_per_solve() * g.get_solve_value()
	return g.get_solves_per_second() + tap_solves


# --- Choosing what to buy ----------------------------------------------------

func _pick_target(g: GameState, taps_per_sec: float) -> Dictionary:
	var base := income(g, taps_per_sec)
	var best := {}
	var best_score := INF
	for item: Dictionary in _candidates(g):
		var gain := _income_gain(g, item, taps_per_sec, base)
		if gain <= 0.0:
			continue
		var cost := _cost(g, item)
		var wait := 0.0
		if g.solves < cost:
			wait = INF if base <= 0.0 else (cost - g.solves) / base
		var score := wait + cost / gain
		if score < best_score:
			best_score = score
			best = item
	return best


## Everything the player can currently see in the shop.
func _candidates(g: GameState) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for def: Dictionary in Content.BUILDINGS:
		if g.is_building_unlocked(def["id"]):
			items.append({"kind": "helper", "id": def["id"]})
	for def: Dictionary in Content.UPGRADES:
		if g.is_upgrade_available(def["id"]):
			items.append({"kind": "upgrade", "id": def["id"]})
	return items


## Extra Solves/s the item would give, measured by briefly owning it in the real GameState.
func _income_gain(g: GameState, item: Dictionary, taps_per_sec: float, base: float) -> float:
	var id: String = item["id"]
	match item["kind"]:
		"helper":
			g.buildings[id] = int(g.buildings[id]) + 1
			var with_it := income(g, taps_per_sec)
			g.buildings[id] = int(g.buildings[id]) - 1
			return with_it - base
		"upgrade":
			g.upgrades[id] = true
			var with_it := income(g, taps_per_sec)
			g.upgrades.erase(id)
			return with_it - base
	return 0.0


func _cost(g: GameState, item: Dictionary) -> float:
	match item["kind"]:
		"helper":
			return g.get_building_cost(item["id"])
		"upgrade":
			return float(Content.get_upgrade(item["id"])["cost"])
	return INF


func _buy(g: GameState, item: Dictionary) -> bool:
	match item["kind"]:
		"helper":
			return g.buy_building(item["id"])
		"upgrade":
			return g.buy_upgrade(item["id"])
	return false


func _item_name(item: Dictionary) -> String:
	match item["kind"]:
		"helper":
			return Content.get_building(item["id"])["name"]
		"upgrade":
			return Content.get_upgrade(item["id"])["name"]
	return item["id"]


# --- Report ------------------------------------------------------------------

## Markdown section for one run.
static func to_markdown(result: Dictionary) -> String:
	var taps: float = result["taps_per_sec"]
	var lines: PackedStringArray = []
	lines.append("## %s (%s taps/s, %s min)" % [
		"Tapping" if taps > 0.0 else "Never tapping", _num(taps), _num(result["minutes"]),
	])
	lines.append("")
	var events: Array = result["events"]
	var all_at: float = result["all_bought_at"]
	lines.append("- Items bought: %d (%d different)" % [result["purchases"], events.size()])
	lines.append("- Every helper and upgrade owned at: %s" % ("never" if all_at < 0.0 else _clock(all_at)))
	lines.append("- Longest wait for something new: %s" % _longest_gap(events, float(result["minutes"]) * 60.0))
	lines.append("")
	lines.append("### First purchase of each item")
	lines.append("")
	if events.is_empty():
		lines.append("Nothing was bought.")
	else:
		lines.append("| Time | Kind | Item | Cost | Gap |")
		lines.append("|---|---|---|---|---|")
		var previous := 0.0
		for e: Dictionary in events:
			lines.append("| %s | %s | %s | %s | +%s |" % [
				_clock(e["t"]), e["kind"], e["name"], Num.format(e["cost"]), _clock(float(e["t"]) - previous),
			])
			previous = e["t"]
	lines.append("")
	lines.append("### Income over time")
	lines.append("")
	lines.append("| Minute | Solves/s | Moves/s | Solves on hand | Lifetime Solves |")
	lines.append("|---|---|---|---|---|")
	for c: Dictionary in result["checkpoints"]:
		lines.append("| %s | %s | %s | %s | %s |" % [
			_num(c["minute"]), Num.format(c["solves_per_sec"]), Num.format(c["moves_per_sec"]),
			Num.format(c["solves"]), Num.format(c["total_solves"]),
		])
	lines.append("")
	return "\n".join(lines)


static func _longest_gap(events: Array, duration: float) -> String:
	if events.is_empty():
		return "the whole run (%s)" % _clock(duration)
	var longest := 0.0
	var where := ""
	var previous := 0.0
	for e: Dictionary in events:
		var gap := float(e["t"]) - previous
		if gap > longest:
			longest = gap
			where = "before %s" % e["name"]
		previous = e["t"]
	var tail := duration - previous
	if tail > longest:
		longest = tail
		where = "after the last new item, until the end of the run"
	return "%s (%s)" % [_clock(longest), where]


## Seconds as m:ss (or h:mm:ss).
static func _clock(seconds: float) -> String:
	var s := int(round(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


static func _num(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)
