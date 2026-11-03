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

const Pacing := preload("res://tools/pacing.gd")

const STEP := 0.1             ## simulated seconds per tick
const REPLAN_INTERVAL := 1.0  ## re-pick the target this often (and after every purchase)
const SPLIT_INTERVAL := 30.0  ## re-choose the helper split this often (and after a puzzle unlock)
const SPLIT_CHUNKS := 20      ## the split is chosen in 5 % steps
const PUZZLE_GAIN_REFRESH := 15.0  ## re-estimate what unlocking the next puzzle is worth this often (it's slow)

var _now := 0.0
var _purchases := 0
var _puzzle_gain_cache := {}  ## puzzle id -> {at, purchases, gain}
const CHECKPOINT_MINUTES: Array[float] = [1.0, 5.0, 15.0, 30.0, 60.0, 120.0]


## Runs one game. Returns:
##   taps_per_sec, minutes,
##   events:      [{t, kind, id, name, cost}]  first purchase of each item, in order
##   purchases:   int                          total items bought
##   checkpoints: [{minute, solves_per_sec, moves_per_sec, solves, total_solves}]
##   all_bought_at: seconds when every helper and upgrade was owned at least once, or -1
func run(taps_per_sec: float, minutes: float) -> Dictionary:
	_puzzle_gain_cache.clear()
	_now = 0.0
	_purchases = 0
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
	for def: Dictionary in Content.PUZZLES:
		if float(def["unlock_cost"]) > 0.0 and not def["requires_prestige"]:
			item_count += 1  # puzzles you can buy before prestige

	var t := 0.0
	var tap_credit := 0.0
	var replan_timer := 0.0
	var split_timer := 0.0
	var target := {}

	while t < duration:
		# Earn: taps, then helpers (same as GameState._process does each frame).
		tap_credit += taps_per_sec * STEP
		while tap_credit >= 1.0:
			tap_credit -= 1.0
			g.tap()
		g.add_helper_moves(STEP)
		t += STEP
		_now = t
		_purchases = purchases
		split_timer -= STEP
		if split_timer <= 0.0:
			choose_split(g)
			split_timer = SPLIT_INTERVAL

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
			if target["kind"] == "puzzle":
				choose_split(g)
				split_timer = SPLIT_INTERVAL
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
					"split": g.get_split(),
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


## The bot's helper split: the best one for income. With the variety bonus (Content.VARIETY) each puzzle's income is
## v × mps × share^e (v = Solves per move incl. mastery), so the best shares are proportional to v^(1 / (1 - e)).
## Rounded to 5 % steps like the in-game controls. Sets it directly (no signals).
func choose_split(g: GameState) -> void:
	var ids := g.get_unlocked_puzzle_ids()
	if ids.size() <= 1:
		return
	var power := 1.0 / (1.0 - float(Content.VARIETY["exponent"]))
	var weights := {}
	var total := 0.0
	for id in ids:
		var value := g.get_puzzle_moves_mult(id) / g.get_moves_per_solve(id) * g.get_solve_value(id)
		weights[id] = pow(value, power)
		total += weights[id]
	for id: String in weights:
		weights[id] = snappedf(weights[id] / total, 1.0 / SPLIT_CHUNKS)
	g.split = weights
	g.set_split(weights)  # normalises after rounding (and signals, harmlessly)


## Solves per second from helpers plus tapping at `taps_per_sec`.
func income(g: GameState, taps_per_sec: float) -> float:
	var tap_solves := taps_per_sec * g.get_tap_moves() / g.get_moves_per_solve() * g.get_solve_value()  # focused puzzle
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
	var next_puzzle := g.get_next_locked_puzzle()
	if next_puzzle != "":
		items.append({"kind": "puzzle", "id": next_puzzle})
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
		"puzzle":
			var cached: Dictionary = _puzzle_gain_cache.get(id, {})
			if not cached.is_empty() and cached["purchases"] == _purchases and _now - float(cached["at"]) < PUZZLE_GAIN_REFRESH:
				return cached["gain"]
			# Unlocking focuses the new puzzle and moves the whole split onto it (the default, kept for now: task 4.7
			# teaches the bot to choose a split). Measure that, then put everything back.
			var unlocked := g.unlocked_puzzles.duplicate()
			var progress := g.puzzle_progress.duplicate()
			var split := g.split.duplicate()
			var focus := g.focused_puzzle
			g._add_puzzle(id)
			g.split = {id: 1.0}
			g.focused_puzzle = id
			choose_split(g)  # the bot will re-split after unlocking, so value it that way
			var with_it := income(g, taps_per_sec)
			g.unlocked_puzzles = unlocked
			g.puzzle_progress = progress
			g.split = split
			g.focused_puzzle = focus
			_puzzle_gain_cache[id] = {"at": _now, "purchases": _purchases, "gain": with_it - base}
			return with_it - base
	return 0.0


func _cost(g: GameState, item: Dictionary) -> float:
	match item["kind"]:
		"helper":
			return g.get_building_cost(item["id"])
		"upgrade":
			return float(Content.get_upgrade(item["id"])["cost"])
		"puzzle":
			return g.get_puzzle_unlock_cost(item["id"])
	return INF


func _buy(g: GameState, item: Dictionary) -> bool:
	match item["kind"]:
		"helper":
			return g.buy_building(item["id"])
		"upgrade":
			return g.buy_upgrade(item["id"])
		"puzzle":
			return g.unlock_puzzle(item["id"])
	return false


func _item_name(item: Dictionary) -> String:
	match item["kind"]:
		"helper":
			return Content.get_building(item["id"])["name"]
		"upgrade":
			return Content.get_upgrade(item["id"])["name"]
		"puzzle":
			return Content.get_puzzle(item["id"])["name"]
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
	var gap := Pacing.longest_gap(events, 0.0, float(result["minutes"]) * 60.0)
	lines.append("- Longest wait for something new: %s (%s)" % [_clock(gap["length"]), gap["where"]])
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
	lines.append("| Minute | Solves/s | Moves/s | Solves on hand | Lifetime Solves | Bot's split |")
	lines.append("|---|---|---|---|---|---|")
	for c: Dictionary in result["checkpoints"]:
		lines.append("| %s | %s | %s | %s | %s | %s |" % [
			_num(c["minute"]), Num.format(c["solves_per_sec"]), Num.format(c["moves_per_sec"]),
			Num.format(c["solves"]), Num.format(c["total_solves"]), split_text(c.get("split", {})),
		])
	lines.append("")
	return "\n".join(lines)


## "2×2 10 % · 3×3 25 % · 4×4 65 %"
static func split_text(split: Dictionary) -> String:
	var parts := PackedStringArray()
	for id: String in split:
		parts.append("%s %d %%" % [Content.get_puzzle(id)["name"], roundi(float(split[id]) * 100.0)])
	return " · ".join(parts)


## Seconds as m:ss (or h:mm:ss).
static func _clock(seconds: float) -> String:
	return Pacing.clock(seconds)


static func _num(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)
