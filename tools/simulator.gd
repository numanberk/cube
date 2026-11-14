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
const HAND_OVERHEAD := 30.0   ## active profile: seconds between hand solves on top of the solve itself
const SAMPLE_INTERVAL := 5.0  ## lifetime Solves are sampled this often (see "samples")
## Prestige (6.4): the bot competes once a championship would at least double its trophy bonus (a common idle-game rule
## of thumb: "prestige when it doubles your multiplier"), then spends trophies with PERK_PLAN and plays a second run.
const COMPETE_FACTOR := 2.0
## The perks the bot buys after a championship, in this order, each only while it keeps at least PERK_KEEP of its
## trophies unspent (a perk is a trade: only unspent trophies give the +2 %, D14).
const PERK_PLAN: Array[String] = ["team_captain", "warm_up", "comp_circuit", "comp_prep", "team_spirit", "practice_away",
		"home_crowd", "club_founder", "appearance_fees", "big_cube_prep", "team_chemistry", "overnight"]
const PERK_KEEP := 0.5

var _now := 0.0
var _purchases := 0
var _forbid := {}  ## upgrade ids this run never buys (to play the other side of a choice pair, 5.8)
var _puzzle_gain_cache := {}  ## puzzle id -> {at, purchases, gain}
const CHECKPOINT_MINUTES: Array[float] = [1.0, 5.0, 15.0, 30.0, 60.0, 120.0]


## Runs one game. Returns:
##   taps_per_sec, minutes,
##   events:      [{t, kind, id, name, cost}]  first purchase of each item, in order
##   purchases:   int                          total items bought
##   checkpoints: [{minute, solves_per_sec, moves_per_sec, solves, total_solves}]
##   all_bought_at: seconds when every helper, upgrade, method and pre-prestige puzzle was owned at least once, or -1
##   hand_solves: how many Solve Station solves the bot did (the "active" profile, S.3)
## `hand` makes it an active player (task S.3): {"tier": 2} = a hand solve just inside that tier's target (Gold) on its
## biggest unlocked cube, back to back (the solve's time + HAND_OVERHEAD for scramble and inspection).
## `forbid` lists upgrade ids the bot never buys: forbidding one side of each choice pair (5.7b) plays the other build,
## which the greedy bot would never pick by itself (task 5.8: the balance mustn't be tuned to one build).
##
## `prestige` (6.4) makes it play past its first World Championship: {"second_run_minutes": m}. The first run ends when
## it competes (logged as an event of kind "prestige", id "compete", and capped at `minutes`); it buys perks
## (PERK_PLAN) and plays a second run for up to m minutes, stopping once it has earned the first run's Solves. Adds:
##   prestige_at (-1 = never competed), trophies_won, perks (ids bought), second_run: {events, reached_at (seconds into
##   the run when its run Solves matched the first run's, -1 = not in time), minutes}
## events, purchases, checkpoints, samples and all_bought_at stay first-run only (first_run_minutes: where it ended;
## second_run_purchases counts the second run's).
func run(taps_per_sec: float, minutes: float, hand: Dictionary = {}, forbid: Array = [], prestige: Dictionary = {}) -> Dictionary:
	_puzzle_gain_cache.clear()
	_forbid.clear()
	for id: Variant in forbid:
		_forbid[str(id)] = true
	_now = 0.0
	_purchases = 0
	var g := GameState.new()
	g.persistence_enabled = false
	g.reset_state()
	g.collection_rng.seed = 7  # Cube Collection drops (7.3a): the same run every time

	var duration := minutes * 60.0
	var events: Array[Dictionary] = []
	var seen := {}
	var checkpoints: Array[Dictionary] = []
	var next_checkpoint := 0
	var purchases := 0
	var all_bought_at := -1.0
	var item_count := Content.BUILDINGS.size() + Content.get_upgrades().size() + Content.METHODS.size() - 1  # Beginner is free
	for def: Dictionary in Content.PUZZLES:
		if float(def["unlock_cost"]) > 0.0 and not def["requires_prestige"]:
			item_count += 1  # puzzles you can buy before prestige
	for def: Dictionary in Content.get_lab_projects():
		if def["kind"] == "research":
			item_count += 1  # Lab projects (5.6); methods are counted above
	var choice_groups := {}
	for def: Dictionary in Content.get_upgrades():
		if def.has("choice_group"):
			if choice_groups.has(def["choice_group"]):
				item_count -= 1  # only one upgrade of each choice group (5.7b) can be bought
			choice_groups[def["choice_group"]] = true
	var learned_method := g.method

	var t := 0.0
	var tap_credit := 0.0
	var achievement_timer := 1.0
	var replan_timer := 0.0
	var split_timer := 0.0
	var target := {}
	var hand_wait := 0.0
	var hand_solves := 0
	var samples: Array = []  # [seconds, lifetime Solves] every SAMPLE_INTERVAL (how fast a run gets somewhere)
	var sample_timer := 0.0
	var first_events := events  # the first run's; a second run logs into its own list
	var prestige_at := -1.0
	var trophies_won := 0
	var first_run_solves := 0.0
	var run_start := 0.0
	var reached_at := -1.0
	var perks_bought: Array[String] = []
	var second_run := false
	var first_purchases := -1

	while t < duration:
		# Earn: taps, then helpers (same as GameState._process does each frame).
		tap_credit += taps_per_sec * STEP
		while tap_credit >= 1.0:
			tap_credit -= 1.0
			g.tap()
		g.add_helper_moves(STEP)
		g.update_flow(STEP)
		g.update_play_time(STEP)
		g.update_streak(STEP)
		g.update_research(STEP)
		achievement_timer -= STEP
		if achievement_timer <= 0.0:  # GameState._process checks achievements once a second (7.1a)
			g.check_achievements()
			achievement_timer = 1.0
		if g.method != learned_method:  # a method's Lab research finished: that's when it counts (and is logged)
			learned_method = g.method
			purchases += 1
			var method_key := "method:" + learned_method
			if not seen.has(method_key):
				seen[method_key] = true
				events.append({"t": t, "kind": "method", "id": learned_method,
						"name": _item_name({"kind": "method", "id": learned_method}),
						"cost": float(Content.get_method(learned_method)["cost"])})
				if seen.size() == item_count and all_bought_at < 0.0 and not second_run:
					all_bought_at = t
		if not hand.is_empty():
			hand_wait -= STEP
			if hand_wait <= 0.0:
				var puzzle := _hand_puzzle(g)
				var targets: Array = (Content.SOLVE_REWARDS["targets"] as Dictionary)[puzzle]
				var time := float(targets[int(hand.get("tier", 2))]) * 0.98
				g.record_hand_solve(puzzle, time, "", 50)
				hand_solves += 1
				hand_wait = time + HAND_OVERHEAD
		t += STEP
		_now = t
		if second_run and reached_at < 0.0 and g.run_solves >= first_run_solves:
			reached_at = t - run_start
			break  # the second run caught up: that's all it's measured for
		sample_timer -= STEP
		if not second_run and sample_timer <= 0.0:
			samples.append([t, g.total_solves])
			sample_timer = SAMPLE_INTERVAL
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
			if target["kind"] != "method" and not seen.has(key):  # a method is logged when its research finishes
				seen[key] = true
				events.append({
					"t": t, "kind": target["kind"], "id": target["id"],
					"name": _item_name(target), "cost": cost,
				})
				if seen.size() == item_count and all_bought_at < 0.0 and not second_run:
					all_bought_at = t
			target = _pick_target(g, taps_per_sec)
			replan_timer = REPLAN_INTERVAL

		while not second_run and next_checkpoint < CHECKPOINT_MINUTES.size() and t >= CHECKPOINT_MINUTES[next_checkpoint] * 60.0 - STEP * 0.5:
			if CHECKPOINT_MINUTES[next_checkpoint] <= minutes:
				checkpoints.append({
					"minute": CHECKPOINT_MINUTES[next_checkpoint],
					"solves_per_sec": income(g, taps_per_sec),
					"tap_share": tap_income(g, taps_per_sec) / maxf(1e-12, income(g, taps_per_sec)),
					"moves_per_sec": g.get_moves_per_second() + taps_per_sec * g.get_tap_moves(),
					"solves": g.solves,
					"total_solves": g.total_solves,
					"split": g.get_split(),
				})
			next_checkpoint += 1

		if not prestige.is_empty() and not second_run and should_compete(g):
			first_run_solves = g.run_solves
			first_purchases = purchases
			trophies_won = g.compete()
			prestige_at = t
			events.append({"t": t, "kind": "prestige", "id": "compete", "name": "World Championship (+%d trophies)" % trophies_won,
					"cost": 0.0})
			perks_bought = buy_perks(g)
			second_run = true
			run_start = t
			duration = t + float(prestige.get("second_run_minutes", 60.0)) * 60.0
			events = []  # the second run's first purchases
			seen.clear()
			_puzzle_gain_cache.clear()
			learned_method = g.method
			target = {}
			choose_split(g)
			continue


	g.free()
	return {
		"taps_per_sec": taps_per_sec,
		"minutes": minutes,
		"first_run_minutes": minutes if prestige_at < 0.0 else prestige_at / 60.0,  ## where the first run ended
		"events": first_events,
		"prestige_at": prestige_at,
		"trophies_won": trophies_won,
		"perks": perks_bought,
		"second_run": {"events": events if second_run else [], "reached_at": reached_at,
				"minutes": float(prestige.get("second_run_minutes", 60.0))},
		"purchases": purchases if first_purchases < 0 else first_purchases,  ## first run only
		"second_run_purchases": 0 if first_purchases < 0 else purchases - first_purchases,
		"checkpoints": checkpoints,
		"all_bought_at": all_bought_at,
		"hand_solves": hand_solves,
		"samples": samples,
		"hand": hand,
		"forbid": forbid,
	}


## Compete once the championship at least doubles the trophy bonus (COMPETE_FACTOR).
func should_compete(g: GameState) -> bool:
	var gain := g.get_pending_trophies()
	return gain >= 1 and g.get_trophy_mult(g.trophies + gain) >= g.get_trophy_mult() * COMPETE_FACTOR


## Buys perks in PERK_PLAN order while at least PERK_KEEP of the trophies stay unspent. Returns the ids bought.
func buy_perks(g: GameState) -> Array[String]:
	var bought: Array[String] = []
	var floor_left := int(ceil(g.trophies * PERK_KEEP))
	for id in PERK_PLAN:
		if g.can_buy_perk(id) and g.trophies - int(Content.get_perk(id)["cost"]) >= floor_left and g.buy_perk(id):
			bought.append(id)
	return bought


## The biggest cube the player has (what an active player would practise on).
func _hand_puzzle(g: GameState) -> String:
	var best := "2x2"
	for id in g.get_unlocked_puzzle_ids():
		var shape := PuzzleShapes.from_id(id)
		if shape != null and shape.size > PuzzleShapes.from_id(best).size:
			best = id
	return best


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
	choose_focus(g)


## Taps go to the focused puzzle, so the bot focuses the one where a tap earns the most (S.7: a tap makes a share of
## that puzzle's helper moves/s, so a big-share puzzle beats the newest one; a player would keep their focus there too).
## Sets it directly (no signals).
func choose_focus(g: GameState) -> void:
	var best := g.focused_puzzle
	var best_value := -1.0
	var keep := g.focused_puzzle
	for id in g.get_unlocked_puzzle_ids():
		g.focused_puzzle = id
		var value := g.get_tap_moves() * g.get_puzzle_moves_mult(id) / g.get_moves_per_solve(id) * g.get_solve_value(id)
		if value > best_value * 1.000001:
			best_value = value
			best = id
	g.focused_puzzle = best if best_value > 0.0 else keep


## Solves per second from helpers plus tapping at `taps_per_sec`.
func income(g: GameState, taps_per_sec: float) -> float:
	return g.get_solves_per_second() + tap_income(g, taps_per_sec)


## Solves per second from tapping alone (on the focused puzzle, after its multipliers like helper moves).
func tap_income(g: GameState, taps_per_sec: float) -> float:
	var focus := g.get_focused_puzzle_id()
	return taps_per_sec * g.get_tap_moves() * g.get_puzzle_moves_mult(focus) / g.get_moves_per_solve() * g.get_solve_value()


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
	for def: Dictionary in Content.get_upgrades():
		if g.is_upgrade_available(def["id"]) and not _forbid.has(def["id"]):
			items.append({"kind": "upgrade", "id": def["id"]})
	var next_method := g.get_next_method()
	if not next_method.is_empty() and g.is_method_available(next_method["id"]) and g.research.is_empty():
		items.append({"kind": "method", "id": next_method["id"]})
	if g.research.is_empty():  # the Lab (5.6): one project at a time
		for def: Dictionary in Content.get_lab_projects():
			if def["kind"] == "research" and g.is_research_visible(def["id"]):
				items.append({"kind": "research", "id": def["id"]})
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
			g.invalidate_upgrade_cache()
			var with_it := income(g, taps_per_sec)
			g.upgrades.erase(id)
			g.invalidate_upgrade_cache()
			return with_it - base
		"method":
			var current := g.method
			g.method = id
			var with_it := income(g, taps_per_sec)
			g.method = current
			return with_it - base
		"research":
			g.research_done[id] = true
			g.invalidate_upgrade_cache()
			var with_it := income(g, taps_per_sec)
			g.research_done.erase(id)
			g.invalidate_upgrade_cache()
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
		"method":
			return float(Content.get_method(item["id"])["cost"])
		"research":
			return float(Content.get_lab_project(item["id"])["cost"])
		"puzzle":
			return g.get_puzzle_unlock_cost(item["id"])
	return INF


func _buy(g: GameState, item: Dictionary) -> bool:
	match item["kind"]:
		"helper":
			return g.buy_building(item["id"])
		"upgrade":
			return g.buy_upgrade(item["id"])
		"method":
			return g.buy_method(item["id"])
		"research":
			return g.start_research(item["id"])
		"puzzle":
			return g.unlock_puzzle(item["id"])
	return false


func _item_name(item: Dictionary) -> String:
	match item["kind"]:
		"helper":
			return Content.get_building(item["id"])["name"]
		"upgrade":
			return Content.get_upgrade(item["id"])["name"]
		"method":
			return Content.get_method(item["id"])["name"]
		"research":
			return Content.get_lab_project(item["id"])["name"]
		"puzzle":
			return Content.get_puzzle(item["id"])["name"]
	return item["id"]


# --- Report ------------------------------------------------------------------

## Markdown section for one run.
static func to_markdown(result: Dictionary) -> String:
	var taps: float = result["taps_per_sec"]
	var lines: PackedStringArray = []
	var hand: Dictionary = result.get("hand", {})
	var title := "Tapping" if taps > 0.0 else "Never tapping"
	if not hand.is_empty():
		title = "Active: tapping + %s-pace hand solves" % GameState.hand_tier_name(int(hand.get("tier", 2)))
	var forbid: Array = result.get("forbid", [])
	if not forbid.is_empty():
		title += " (never buying some upgrades)"
	lines.append("## %s (%s taps/s, %s min)" % [title, _num(taps), _num(result["minutes"])])
	lines.append("")
	if not forbid.is_empty():
		var names := PackedStringArray()
		for id: Variant in forbid:
			names.append(Content.get_upgrade(str(id)).get("name", str(id)))
		lines.append("- Never buys: %s" % ", ".join(names))
	if not hand.is_empty():
		lines.append("- Hand solves in the Solve Station: %d (each just inside the tier's target on the biggest cube owned, back to back)" % result["hand_solves"])
	var events: Array = result["events"]
	var all_at: float = result["all_bought_at"]
	lines.append("- Items bought: %d (%d different)" % [result["purchases"], events.size()])
	lines.append("- Every helper, upgrade, method and puzzle owned at: %s" % ("never" if all_at < 0.0 else _clock(all_at)))
	var gap := Pacing.longest_gap(events, 0.0, float(result.get("first_run_minutes", result["minutes"])) * 60.0)
	lines.append("- Longest wait for something new: %s (%s)" % [_clock(gap["length"]), gap["where"]])
	var prestige_at := float(result.get("prestige_at", -1.0))
	if prestige_at >= 0.0:
		var second: Dictionary = result["second_run"]
		var reached := float(second["reached_at"])
		lines.append("- **First World Championship at %s: +%d trophies.** Perks bought: %s" % [_clock(prestige_at),
				result["trophies_won"], ", ".join(PackedStringArray((result["perks"] as Array).map(
				func(id: Variant) -> String: return Content.get_perk(str(id)).get("name", str(id)))))])
		var caught_up := "not within %s min" % _num(second["minutes"]) if reached < 0.0 \
				else "%s (%d %% of the first run)" % [_clock(reached), roundi(reached / prestige_at * 100.0)]
		lines.append("- **Second run** (%d items bought) earned the first run's Solves at: %s" % [
				result["second_run_purchases"], caught_up])
		var firsts := PackedStringArray()
		for e: Dictionary in second["events"]:
			if e["kind"] in ["puzzle", "method"]:
				firsts.append("%s %s" % [e["name"], _clock(float(e["t"]) - prestige_at)])
		lines.append("- Second run puzzles and methods: %s" % (", ".join(firsts) if not firsts.is_empty() else "none"))
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


## The choice-pair upgrades (5.7b) a run bought: the build it played.
static func chosen_sides(result: Dictionary) -> Array[String]:
	var picked: Array[String] = []
	for e: Dictionary in result["events"]:
		if e["kind"] == "upgrade" and Content.get_upgrade(e["id"]).has("choice_group"):
			picked.append(e["id"])
	return picked


## Markdown comparing the main build with runs that each play the other side of one choice pair (5.8). `others` is
## [[label, result], ...].
static func compare_markdown(main: Dictionary, others: Array, until: float) -> String:
	var lines: PackedStringArray = []
	lines.append("## Main build vs the other side of each choice (first %s min)" % _num(until / 60.0))
	lines.append("")
	lines.append("Each other column is the tapping bot again, never buying the side of ONE choice pair it picked, so it plays")
	lines.append("the other side of that pair (the greedy bot never would). A side that's far behind is a weak choice.")
	lines.append("")
	var header := "| Moment | Main build |"
	var rule := "|---|---|"
	for other: Array in others:
		header += " %s |" % other[0]
		rule += "---|"
	lines.append(header)
	lines.append(rule)
	for row: Array in [["3×3", "puzzle", "3x3"], ["Solving Robot", "helper", "robot"], ["4×4", "puzzle", "4x4"],
			["5×5", "puzzle", "5x5"]]:
		var line := "| %s | %s |" % [row[0], _first_time(main, row[1], row[2])]
		for other: Array in others:
			line += " %s |" % _first_time(other[1], row[1], row[2])
		lines.append(line)
	var gaps := "| Longest wait for something new | %s |" % _clock(_gap_until(main, until))
	var totals := "| Lifetime Solves at %s | %s |" % [_clock(until), Num.format(_total_at(main, until))]
	for other: Array in others:
		gaps += " %s |" % _clock(_gap_until(other[1], until))
		totals += " %s |" % Num.format(_total_at(other[1], until))
	lines.append(gaps)
	lines.append(totals)
	lines.append("")
	return "\n".join(lines)


static func _gap_until(result: Dictionary, until: float) -> float:
	return Pacing.longest_gap(result["events"], 0.0, minf(until, float(result["minutes"]) * 60.0))["length"]


static func _first_time(result: Dictionary, kind: String, id: String) -> String:
	for e: Dictionary in result["events"]:
		if e["kind"] == kind and e["id"] == id:
			return _clock(e["t"])
	return "never"


static func _total_at(result: Dictionary, at: float) -> float:
	var total := 0.0
	for sample: Array in result.get("samples", []):
		if float(sample[0]) <= at:
			total = float(sample[1])
	return total


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
