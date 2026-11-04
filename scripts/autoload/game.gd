class_name GameState
extends Node
## Global game state and rules. Registered as the autoload "Game".
## All numbers live here; UI scripts only read them and call the public methods.

signal solved(count: int, puzzle_id: String)
signal purchased(kind: String, id: String)
signal state_reset
signal puzzle_unlocked(puzzle_id: String)
signal focus_changed(puzzle_id: String)
signal split_changed
signal mastery_level_up(puzzle_id: String, level: int)
signal time_tier_reached(puzzle_id: String, tier: String, seconds: float)  ## the team's best time crossed a tier (R.3)
signal solve_records_changed(puzzle_id: String)
## News feed events (task R.4); like the tiers they're derived, never saved, and never fire for what a load restores.
signal helper_best_time(building_id: String, puzzle_id: String, seconds: float, first: bool)  ## a helper kind got faster
signal solves_milestone(amount: float)  ## lifetime Solves passed a power of ten (100, 1K, 10K, ...)
signal hand_solve_pb(puzzle_id: String, single: bool, averages: Array, seconds: float)  ## a Solve Station PB
## Golden Scramble (task S.6): a sticker starts glowing, stops glowing unclaimed, an attempt ends (buff = {} on a miss).
signal hand_tier_reached(puzzle_id: String, tier: String)  ## a puzzle's PB single reached a new S.3 tier (permanent)
signal flow_started(mult: float, seconds: float)  ## a hand solve started (or refreshed) Flow
signal drill_case_learned(case_id: String)  ## a drill case reached its clean solves (S.4)
signal drill_set_learned(set_id: String)    ## every case of a drill set is learned
signal daily_rewarded(amount: float)  ## the first daily scramble finished today paid its reward (S.5)
signal research_started(project_id: String)   ## Algorithm Lab (5.6)
signal research_finished(project_id: String)  ## a project's effect counts from now (methods also emit purchased("method"))
signal golden_spawned
signal golden_expired
signal golden_finished(success: bool, buff: Dictionary)  ## a hand solve was recorded, edited or deleted (Solve Station)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 9  ## v2 (4.2): parallel puzzles; v3 (4.6): mastery; v4 (5.1): methods; v5 (S.2): solve records;
                         ## v6 (S.6): Golden Scramble timer + active buff; v7 (S.4): algorithm drill records;
                         ## v8 (S.5): daily scramble results + reward; v9 (5.6): Algorithm Lab research
const AUTOSAVE_INTERVAL := 10.0
const MAX_OFFLINE_SECONDS := 8.0 * 3600.0
const MIN_OFFLINE_SECONDS := 10.0
const BASE_TAP_MOVES := 1.0
const COST_GROWTH := 1.15
const BUY_MAX := -1              ## pass as `count` to buy as many as you can afford
const BULK_LIMIT := 10000        ## safety cap for bulk cost loops
const SOLVE_HISTORY_LIMIT := 1000  ## hand solves kept per puzzle (records and averages are over these)
const AVERAGE_SIZES: Array[int] = [5, 12, 50, 100]
const PENALTIES: Array[String] = ["", "+2", "DNF"]

## Set to false before the node enters the tree to skip loading/saving (tests do this).
var persistence_enabled := true
## Where the save lives. Tests point this somewhere else. The backup is `save.bak` next to it,
## and a save that can't be read is copied to `save.corrupt.json` before anything overwrites it.
var save_path := SAVE_PATH

var solves := 0.0          ## Spendable currency.
var total_solves := 0.0    ## Lifetime Solves earned; never goes down.
var total_moves := 0.0     ## Lifetime moves made.
## Puzzles (D9, task 4.2): every unlocked puzzle runs at once. Helper moves are split across them by `split`
## (a weight per puzzle, shown as shares that add up to 100 %); taps go to the focused puzzle.
var unlocked_puzzles: Array[String] = []  ## in ladder order
var puzzle_progress: Dictionary = {}       ## puzzle id -> moves made toward its current solve
var focused_puzzle := ""
var split: Dictionary = {}                 ## puzzle id -> weight (>= 0)
var mastery_xp: Dictionary = {}            ## puzzle id -> mastery XP (task 4.6); kept through prestige
var _mastery_levels: Dictionary = {}       ## puzzle id -> level, cached from mastery_xp
var buildings: Dictionary = {}  ## building id -> owned count
var upgrades: Dictionary = {}   ## upgrade id -> true (owned)
## Hand solves from the Solve Station (task S.2), kept through prestige:
## puzzle id -> {"history": [{"t": seconds, "p": penalty, "m": moves, "d": unix time}, ... oldest first], "count": all ever}
var solve_records: Dictionary = {}
var _solve_bests: Dictionary = {}  ## puzzle id -> {"single": s, 5: s, 12: s, ...}; INF = none/DNF. Cached, not saved.
var method := "beginner"        ## id of the newest method learned (Content.METHODS); every earlier one is learned too
var offline_report: Dictionary = {}  ## {"seconds", "solves"} after loading, if anything was earned
var load_notice := ""  ## Set when the save was damaged and a backup (or nothing) was loaded; the UI shows it once.

var _autosave_timer := 0.0
var _tier_reached: Dictionary = {}         ## puzzle id -> index of the best time tier reached (derived, not saved)
var _helper_best: Dictionary = {}          ## building id -> [puzzle id, best solve time reported] (news feed, not saved)
var _next_solves_milestone := 100.0        ## lifetime Solves at which solves_milestone fires next (derived)
var golden_next := 0.0                     ## seconds until the next golden sticker (saved)
var golden_glow_left := 0.0                ## > 0 while a golden sticker glows and can be clicked
var golden_attempt_left := 0.0             ## > 0 while a claimed Golden Scramble case is being solved
var buff: Dictionary = {}                  ## the active buff: {id, mult, left} (saved; paused while closed), or {}
var golden_rng := RandomNumberGenerator.new()
var flow: Dictionary = {}                  ## Flow from hand solves (S.3): {mult, left, tier}; not saved (ends on quit)
var drills: Dictionary = {}                ## algorithm id -> {best, clean, count} (S.4, saved)
var research: Dictionary = {}              ## the Lab project being researched: {id, left} (5.6, saved), or {}
var research_done: Dictionary = {}         ## finished non-method Lab projects (methods are tracked by `method`)
var daily: Dictionary = {}                 ## S.5 (saved): {date, rewarded, times {puzzle: s}, fmc {puzzle: moves}, fmc_ever {puzzle: moves}}
var daily_now := -1.0                      ## tests: the unix time "now" for the daily (-1 = the real clock)
var _mult_cache: Dictionary = {}           ## _upgrade_mult results for the current set of owned upgrades
var _mult_cache_owned := -1                ## upgrades.size() the cache was built for
var _offline_catch_up := false             ## true while offline progress is added: buffs don't count then


func _init() -> void:
	# Anything that can speed a helper up can cross a time tier.
	purchased.connect(func(_kind: String, _id: String) -> void:
		check_helper_times()  # "Robot Unit 7 joins the team" reads best before "3×3 team: WR pace!"
		check_time_tiers())
	mastery_level_up.connect(func(_id: String, _level: int) -> void:
		check_helper_times()
		check_time_tiers())
	focus_changed.connect(func(_id: String) -> void: check_helper_times(false))
	drill_set_learned.connect(_on_drill_set_learned_for_lab)


func _ready() -> void:
	reset_state()
	if persistence_enabled:
		load_game()


func _process(delta: float) -> void:
	add_helper_moves(delta)
	update_golden(delta)
	update_flow(delta)
	update_research(delta)
	if persistence_enabled:
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_INTERVAL:
			_autosave_timer = 0.0
			save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and persistence_enabled:
		save_game()


# --- Moves and solves --------------------------------------------------------

func tap() -> void:
	add_moves_to(focused_puzzle, get_tap_moves())


## `seconds` of helper work: each puzzle gets its share of helper moves/s, with the variety bonus (Content.VARIETY).
## Used every frame and for offline progress.
func add_helper_moves(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for id in unlocked_puzzles:
		var rate := _helper_rate(id)
		if rate > 0.0:
			add_moves_to(id, rate * seconds)


## Raw moves divided across the unlocked puzzles by the split, with no pace limit (tests and debugging).
func add_moves(amount: float) -> void:
	if amount <= 0.0:
		return
	for id in unlocked_puzzles:
		var share := get_puzzle_share(id)
		if share > 0.0:
			add_moves_to(id, amount * share)


## Moves made on one puzzle: each full `get_moves_per_solve(id)` completes a solve worth `get_solve_value(id)`.
func add_moves_to(puzzle_id: String, amount: float) -> void:
	if amount <= 0.0 or not puzzle_progress.has(puzzle_id):
		return
	amount *= get_puzzle_moves_mult(puzzle_id) * get_buff_mult() * get_flow_mult()
	total_moves += amount
	var progress := float(puzzle_progress[puzzle_id]) + amount
	var needed := get_moves_per_solve(puzzle_id)
	if progress >= needed:
		var count := floorf(progress / needed)
		progress -= count * needed
		var reward := count * get_solve_value(puzzle_id)
		solves += reward
		total_solves += reward
		if total_solves >= _next_solves_milestone:
			var passed := _next_solves_milestone
			while total_solves >= passed * 10.0:
				passed *= 10.0
			_next_solves_milestone = passed * 10.0
			solves_milestone.emit(passed)
		puzzle_progress[puzzle_id] = progress
		_add_mastery_xp(puzzle_id, count * get_mastery_xp_per_solve(puzzle_id))
		solved.emit(int(count), puzzle_id)
	else:
		puzzle_progress[puzzle_id] = progress


## Moves needed for one solve on a puzzle (the focused one by default), after methods, upgrades and mastery,
## but never below the puzzle's floor (get_moves_floor).
func get_moves_per_solve(puzzle_id: String = "") -> float:
	var id := _or_focused(puzzle_id)
	var def := Content.get_puzzle(id)
	var moves := float(def.get("moves_per_solve", 1.0)) * get_method_mult() * _upgrade_mult("solve_moves_mult") \
			* _mastery_mult(id, "solve_moves")
	return maxf(get_moves_floor(id), moves)


## The fewest moves a solve can ever take on a puzzle (the focused one by default), at least 1.
func get_moves_floor(puzzle_id: String = "") -> float:
	var def := Content.get_puzzle(_or_focused(puzzle_id))
	return maxf(1.0, float(def.get("min_moves_per_solve", 1.0)))


## Solves earned per solve on a puzzle (the focused one by default).
func get_solve_value(puzzle_id: String = "") -> float:
	var id := _or_focused(puzzle_id)
	var def := Content.get_puzzle(id)
	return float(def.get("solve_value", 1.0)) * _upgrade_mult("solve_value_mult") * _mastery_mult(id, "solve_value")


## Moves made toward the next solve on a puzzle (the focused one by default).
func get_move_progress(puzzle_id: String = "") -> float:
	return float(puzzle_progress.get(_or_focused(puzzle_id), 0.0))


func get_tap_moves() -> float:
	return BASE_TAP_MOVES * _upgrade_mult("tap_mult") * _upgrade_mult("global_mult")


## Moves per second produced by ONE unit of a building.
func get_building_mps(id: String) -> float:
	var def := Content.get_building(id)
	return float(def["mps"]) * _upgrade_mult("building_mult", id) * _upgrade_mult("global_mult") * _synergy_mult(id)


func get_moves_per_second() -> float:
	var total := 0.0
	for def: Dictionary in Content.BUILDINGS:
		var owned: int = buildings.get(def["id"], 0)
		if owned > 0:
			total += owned * get_building_mps(def["id"])
	return total


## Helper moves per second going to one puzzle, after the variety bonus and its mastery bonus.
func get_puzzle_moves_per_second(puzzle_id: String) -> float:
	return _helper_rate(puzzle_id) * get_puzzle_moves_mult(puzzle_id)


## The variety bonus on a puzzle's share of helper moves: ×1 with a single puzzle, more for smaller shares.
## (share^exponent / share; a 10 % share at exponent 0.6 does the work of 25 %, a ×2.5 bonus.)
func get_puzzle_variety_bonus(puzzle_id: String) -> float:
	var share := get_puzzle_share(puzzle_id)
	return 0.0 if share <= 0.0 else pow(share, float(Content.VARIETY["exponent"])) / share


## Helper moves/s a puzzle gets before its mastery bonus: all helpers' moves × share^exponent.
func _helper_rate(puzzle_id: String) -> float:
	var share := get_puzzle_share(puzzle_id)
	return 0.0 if share <= 0.0 else get_moves_per_second() * pow(share, float(Content.VARIETY["exponent"]))


func get_puzzle_solves_per_second(puzzle_id: String) -> float:
	return get_puzzle_moves_per_second(puzzle_id) / get_moves_per_solve(puzzle_id) * get_solve_value(puzzle_id)


## Total Solves per second from helpers, summed over every running puzzle.
func get_solves_per_second() -> float:
	var total := 0.0
	for id in unlocked_puzzles:
		total += get_puzzle_solves_per_second(id)
	return total


# --- Shop --------------------------------------------------------------------

func get_building_cost(id: String) -> float:
	var def := Content.get_building(id)
	var owned: int = buildings.get(id, 0)
	return _copy_cost(def, owned)


## What copy number `n` (0 = the first) of a helper costs: ceil(base × 1.15^n), and nothing for a helper's first copy
## when it's marked first_free (task 5.0).
func _copy_cost(def: Dictionary, n: int) -> float:
	if n == 0 and def.get("first_free", false):
		return 0.0
	return ceilf(float(def["base_cost"]) * pow(COST_GROWTH, n))


## Cost of the next `count` copies of a helper: the exact sum of each copy's ceil(base × 1.15^owned), so bulk
## buying costs the same as buying one at a time.
func get_building_cost_for(id: String, count: int) -> float:
	var def := Content.get_building(id)
	var owned: int = buildings.get(id, 0)
	var total := 0.0
	for i in mini(count, BULK_LIMIT):
		total += _copy_cost(def, owned + i)
	return total


## How many copies of a helper the current Solves can buy (0 if not even one).
func get_max_affordable(id: String) -> int:
	var def := Content.get_building(id)
	var owned: int = buildings.get(id, 0)
	var left := solves
	var count := 0
	while count < BULK_LIMIT:
		var cost := _copy_cost(def, owned + count)
		if cost > left:
			break
		left -= cost
		count += 1
	return count


## Buys `count` copies of a helper, all or nothing; `BUY_MAX` buys as many as affordable. Returns how many were bought.
func buy_buildings(id: String, count: int) -> int:
	if count == BUY_MAX:
		count = get_max_affordable(id)
	if count <= 0:
		return 0
	var cost := get_building_cost_for(id, count)
	if solves < cost:
		return 0
	solves -= cost
	buildings[id] = int(buildings.get(id, 0)) + count
	purchased.emit("building", id)
	return count


## Lifetime Solves at which a helper appears in the shop (its "unlock_at", or half its base cost).
func get_building_unlock_at(id: String) -> float:
	var def := Content.get_building(id)
	return float(def.get("unlock_at", float(def["base_cost"]) * 0.5))


func is_building_unlocked(id: String) -> bool:
	return int(buildings.get(id, 0)) > 0 or total_solves >= get_building_unlock_at(id)


func buy_building(id: String) -> bool:
	var cost := get_building_cost(id)
	if solves < cost:
		return false
	solves -= cost
	buildings[id] = int(buildings.get(id, 0)) + 1
	purchased.emit("building", id)
	return true


func is_upgrade_available(id: String) -> bool:
	if upgrades.has(id):
		return false
	var def := Content.get_upgrade(id)
	if def.is_empty() or total_solves < float(def["cost"]) * 0.5 or is_upgrade_locked_out(id):
		return false
	var requires: Dictionary = def.get("requires", {})
	for building_id: String in requires:
		if int(buildings.get(building_id, 0)) < int(requires[building_id]):
			return false
	return true


## Choices (5.7b): the other upgrades in this one's `choice_group` (empty if it isn't a choice).
func get_choice_partners(id: String) -> Array[String]:
	var partners: Array[String] = []
	var group := String(Content.get_upgrade(id).get("choice_group", ""))
	if group == "":
		return partners
	for def: Dictionary in Content.get_upgrades():
		if def["id"] != id and String(def.get("choice_group", "")) == group:
			partners.append(def["id"])
	return partners


## The upgrade picked in a choice group this run, or "".
func get_choice_pick(group: String) -> String:
	for def: Dictionary in Content.get_upgrades():
		if String(def.get("choice_group", "")) == group and upgrades.has(def["id"]):
			return def["id"]
	return ""


## True when another upgrade of this one's choice group was bought this run, so this one can't be.
func is_upgrade_locked_out(id: String) -> bool:
	var group := String(Content.get_upgrade(id).get("choice_group", ""))
	if group == "":
		return false
	var pick := get_choice_pick(group)
	return pick != "" and pick != id


func buy_upgrade(id: String) -> bool:
	if not is_upgrade_available(id):
		return false
	var cost := float(Content.get_upgrade(id)["cost"])
	if solves < cost:
		return false
	solves -= cost
	upgrades[id] = true
	purchased.emit("upgrade", id)
	return true


# --- Methods (task 5.1) -------------------------------------------------------------

## The newest method learned (Content.METHODS entry).
func get_method() -> Dictionary:
	return Content.get_method(method)


## The next method in the chain, or {} once God's Number is learned.
func get_next_method() -> Dictionary:
	var index := Content.get_method_index(method) + 1
	return Content.METHODS[index] if index < Content.METHODS.size() else {}


## True for the current method and every one before it.
func is_method_learned(id: String) -> bool:
	var index := Content.get_method_index(id)
	return index >= 0 and index <= Content.get_method_index(method)


## Only the next method in the chain can be learned, and it shows up (like an upgrade) at half its cost in lifetime Solves.
func is_method_available(id: String) -> bool:
	var next := get_next_method()
	return not next.is_empty() and next["id"] == id and total_solves >= float(next["cost"]) * 0.5 \
			and String(research.get("id", "")) != "method_" + id


## Learning a method is Lab research (5.6): this pays for it and starts it; the method counts once the research is done
## (then purchased("method", id) fires, as it always has).
func buy_method(id: String) -> bool:
	if not is_method_available(id):
		return false
	return start_research("method_" + id)


## Moves-per-solve multiplier from every learned method (before the puzzle floor).
func get_method_mult() -> float:
	var mult := 1.0
	for i in Content.get_method_index(method) + 1:
		mult *= float(Content.METHODS[i]["mult"])
	return mult


# --- Hand solves: records (task S.2) ---------------------------------------------------

## Records a finished Solve Station attempt. Returns {"final" (seconds with penalty, INF = DNF), "pb_single": bool,
## "pb_averages": [sizes that just set a new best]}.
func record_hand_solve(puzzle_id: String, seconds: float, penalty: String, moves: int) -> Dictionary:
	if Content.get_puzzle(puzzle_id).is_empty() or seconds <= 0.0 or not PENALTIES.has(penalty):
		return {}
	var record := _solve_record(puzzle_id)
	var bests := get_solve_bests(puzzle_id)  # before adding this solve
	var tier_before := get_best_hand_tier(puzzle_id)
	var history: Array = record["history"]
	history.append({"t": seconds, "p": penalty, "m": moves, "d": Time.get_unix_time_from_system()})
	while history.size() > SOLVE_HISTORY_LIMIT:
		history.pop_front()
	record["count"] = int(record["count"]) + 1
	var final := final_solve_time(history.back())
	var info := {"final": final, "pb_single": final < float(bests["single"]), "pb_averages": []}
	bests["single"] = minf(float(bests["single"]), final)
	for size: int in AVERAGE_SIZES:
		var current := get_current_average(puzzle_id, size)
		if current >= 0.0 and current < float(bests[size]):
			bests[size] = current
			(info["pb_averages"] as Array).append(size)
	_reward_hand_solve(puzzle_id, final, bool(info["pb_single"]), tier_before, info)
	solve_records_changed.emit(puzzle_id)
	if info["pb_single"] or not (info["pb_averages"] as Array).is_empty():
		hand_solve_pb.emit(puzzle_id, info["pb_single"], info["pb_averages"], final)
	return info


## Sets a recorded solve's penalty ("", "+2", "DNF"); index into get_solve_history(). Bests are recomputed.
func set_hand_solve_penalty(puzzle_id: String, index: int, penalty: String) -> bool:
	var history := get_solve_history(puzzle_id)
	if index < 0 or index >= history.size() or not PENALTIES.has(penalty):
		return false
	(history[index] as Dictionary)["p"] = penalty
	_recompute_solve_bests(puzzle_id)
	solve_records_changed.emit(puzzle_id)
	return true


func delete_hand_solve(puzzle_id: String, index: int) -> bool:
	var history := get_solve_history(puzzle_id)
	if index < 0 or index >= history.size():
		return false
	history.remove_at(index)
	_recompute_solve_bests(puzzle_id)
	solve_records_changed.emit(puzzle_id)
	return true


## Recorded hand solves on a puzzle, oldest first (the live array; change it only through the methods above).
func get_solve_history(puzzle_id: String) -> Array:
	return solve_records.get(puzzle_id, {}).get("history", [])


## Hand solves ever recorded on a puzzle (deleted ones included; the history only keeps the last 1000).
func get_hand_solve_count(puzzle_id: String) -> int:
	return int(solve_records.get(puzzle_id, {}).get("count", 0))


## {"single": seconds, 5: seconds, 12: ..., 50: ..., 100: ...}; INF = no record yet (or only DNFs).
func get_solve_bests(puzzle_id: String) -> Dictionary:
	if not _solve_bests.has(puzzle_id):
		_recompute_solve_bests(puzzle_id)
	return _solve_bests[puzzle_id]


## The average of the last `size` solves (WCA trimming), -1 if there aren't that many, INF if it's a DNF.
func get_current_average(puzzle_id: String, size: int) -> float:
	var history := get_solve_history(puzzle_id)
	if history.size() < size:
		return -1.0
	return _average_at(history, history.size() - size, size)


## A recorded solve's time with its penalty (+2 adds 2 s, DNF = INF).
static func final_solve_time(entry: Dictionary) -> float:
	return SolveSession.final_time({"time": float(entry.get("t", 0.0)), "penalty": String(entry.get("p", ""))})


func _average_at(history: Array, start: int, size: int) -> float:
	var times: Array[float] = []
	for i in range(start, start + size):
		times.append(final_solve_time(history[i]))
	return SolveSession.trimmed_average(times, SolveSession.trim_count(size))


func _solve_record(puzzle_id: String) -> Dictionary:
	if not solve_records.has(puzzle_id):
		solve_records[puzzle_id] = {"history": [], "count": 0}
	return solve_records[puzzle_id]


## Bests over the kept history (after an edit, a delete or a load).
func _recompute_solve_bests(puzzle_id: String) -> void:
	var history := get_solve_history(puzzle_id)
	var bests := {"single": INF}
	for entry: Dictionary in history:
		bests["single"] = minf(float(bests["single"]), final_solve_time(entry))
	for size: int in AVERAGE_SIZES:
		var best := INF
		for start in history.size() - size + 1:
			best = minf(best, _average_at(history, start, size))
		bests[size] = best
	_solve_bests[puzzle_id] = bests


# --- Puzzles (D9) -------------------------------------------------------------------

func get_unlocked_puzzle_ids() -> Array[String]:
	return unlocked_puzzles.duplicate()


func get_focused_puzzle_id() -> String:
	return focused_puzzle


func is_puzzle_unlocked(puzzle_id: String) -> bool:
	return unlocked_puzzles.has(puzzle_id)


## Prestige comes in Phase 6; until then the puzzles that require it stay out of reach.
func has_won_championship() -> bool:
	return false


## The next puzzle on the ladder that isn't unlocked yet and can be reached now ("" if none).
func get_next_locked_puzzle() -> String:
	for def: Dictionary in Content.PUZZLES:
		if unlocked_puzzles.has(def["id"]):
			continue
		if def["requires_prestige"] and not has_won_championship():
			return ""
		return def["id"]
	return ""


func get_puzzle_unlock_cost(puzzle_id: String) -> float:
	return float(Content.get_puzzle(puzzle_id).get("unlock_cost", INF))


func can_unlock_puzzle(puzzle_id: String) -> bool:
	return puzzle_id != "" and puzzle_id == get_next_locked_puzzle() and solves >= get_puzzle_unlock_cost(puzzle_id)


## Unlocks the next puzzle: spends its cost, focuses it and moves the whole split onto it (so a player who never
## touches the split plays a simple ladder). It then runs alongside the others.
func unlock_puzzle(puzzle_id: String) -> bool:
	if not can_unlock_puzzle(puzzle_id):
		return false
	solves -= get_puzzle_unlock_cost(puzzle_id)
	_add_puzzle(puzzle_id)
	set_split_preset("newest")
	set_focus(puzzle_id)
	puzzle_unlocked.emit(puzzle_id)
	purchased.emit("puzzle", puzzle_id)
	return true


func set_focus(puzzle_id: String) -> void:
	if not unlocked_puzzles.has(puzzle_id) or puzzle_id == focused_puzzle:
		return
	focused_puzzle = puzzle_id
	focus_changed.emit(puzzle_id)


## A puzzle's share of helper moves, 0..1 (all unlocked puzzles' shares add up to 1).
func get_puzzle_share(puzzle_id: String) -> float:
	if not unlocked_puzzles.has(puzzle_id):
		return 0.0
	var total := 0.0
	for id in unlocked_puzzles:
		total += float(split.get(id, 0.0))
	if total <= 0.0:
		return 1.0 / unlocked_puzzles.size()
	return float(split.get(puzzle_id, 0.0)) / total


## Every unlocked puzzle's share: {id: 0..1}, adding up to 1.
func get_split() -> Dictionary:
	var shares := {}
	for id in unlocked_puzzles:
		shares[id] = get_puzzle_share(id)
	return shares


## Sets the split from weights (any scale; negatives count as 0; unknown or locked puzzles are ignored).
## All zero puts everything on the newest puzzle.
func set_split(weights: Dictionary) -> void:
	var clean := {}
	var total := 0.0
	for id in unlocked_puzzles:
		var weight := maxf(0.0, float(weights.get(id, 0.0)))
		clean[id] = weight
		total += weight
	if total <= 0.0:
		clean[unlocked_puzzles.back()] = 1.0
		total = 1.0
	for id: String in clean:
		clean[id] = clean[id] / total
	split = clean
	split_changed.emit()


## Sets one puzzle's share (0..1) and rescales the others in proportion, so the shares still add up to 1.
## If the others were all 0, the rest is shared equally between them.
func set_share(puzzle_id: String, share: float) -> void:
	if not unlocked_puzzles.has(puzzle_id):
		return
	if unlocked_puzzles.size() == 1:
		set_split({puzzle_id: 1.0})
		return
	share = clampf(share, 0.0, 1.0)
	var others_total := 0.0
	for id in unlocked_puzzles:
		if id != puzzle_id:
			others_total += get_puzzle_share(id)
	var weights := {puzzle_id: share}
	for id in unlocked_puzzles:
		if id == puzzle_id:
			continue
		if others_total > 0.0:
			weights[id] = get_puzzle_share(id) / others_total * (1.0 - share)
		else:
			weights[id] = (1.0 - share) / (unlocked_puzzles.size() - 1)
	set_split(weights)


## Moves one puzzle's share up or down by `delta` (e.g. ±0.1), keeping the total at 100 %. Shares snap to whole percents.
func adjust_share(puzzle_id: String, delta: float) -> void:
	set_share(puzzle_id, snappedf(get_puzzle_share(puzzle_id) + delta, 0.01))


## "newest": everything on the newest puzzle; "even": the same share for each unlocked puzzle.
func set_split_preset(preset: String) -> void:
	var weights := {}
	for id in unlocked_puzzles:
		weights[id] = 1.0 if preset == "even" or id == unlocked_puzzles.back() else 0.0
	set_split(weights)


func _add_puzzle(puzzle_id: String) -> void:
	if unlocked_puzzles.has(puzzle_id) or Content.get_puzzle(puzzle_id).is_empty():
		return
	unlocked_puzzles.append(puzzle_id)
	# keep ladder order whatever order they were added in
	var order := {}
	for i in Content.PUZZLES.size():
		order[Content.PUZZLES[i]["id"]] = i
	unlocked_puzzles.sort_custom(func(x: String, y: String) -> bool: return order[x] < order[y])
	puzzle_progress[puzzle_id] = 0.0


# --- Puzzle Mastery (task 4.6) -----------------------------------------------------

func get_mastery_xp(puzzle_id: String) -> float:
	return float(mastery_xp.get(puzzle_id, 0.0))


func get_mastery_level(puzzle_id: String) -> int:
	return int(_mastery_levels.get(puzzle_id, 1))


## XP needed to go from `level` to the next one.
func get_mastery_xp_for_level(level: int) -> float:
	return ceilf(float(Content.MASTERY["xp_first_level"]) * pow(float(Content.MASTERY["xp_growth"]), level - 1))


## XP a solve on this puzzle gives (bigger puzzles give more, so XP per move is the same everywhere; "mastery_xp_mult"
## upgrades multiply it).
func get_mastery_xp_per_solve(puzzle_id: String) -> float:
	return float(Content.get_puzzle(puzzle_id).get("moves_per_solve", 8.0)) / float(Content.MASTERY["xp_per_solve_moves"]) \
			* _upgrade_mult("mastery_xp_mult")


## Progress through the current level, 0..1 (1 at the max level).
func get_mastery_progress(puzzle_id: String) -> float:
	var level := get_mastery_level(puzzle_id)
	if level >= int(Content.MASTERY["max_level"]):
		return 1.0
	return clampf((get_mastery_xp(puzzle_id) - _mastery_xp_at(level)) / get_mastery_xp_for_level(level), 0.0, 1.0)


## The next milestone a puzzle can reach: {level, text} or {} at the top.
func get_next_mastery_milestone(puzzle_id: String) -> Dictionary:
	var level := get_mastery_level(puzzle_id)
	for milestone: Dictionary in Content.MASTERY["milestones"]:
		if int(milestone["level"]) > level:
			return milestone
	return {}


## Moves on a puzzle are multiplied by its level bonus, its "moves" milestones, every "all_moves" milestone, its hand-solve
## tier and specialist upgrades ("puzzle_mult", 5.7b).
func get_puzzle_moves_mult(puzzle_id: String) -> float:
	var per_level := 1.0 + float(Content.MASTERY["per_level_moves"]) * (get_mastery_level(puzzle_id) - 1)
	var everywhere := 1.0
	for id in unlocked_puzzles:
		everywhere *= _milestone_mult(id, "all_moves")
	return per_level * _milestone_mult(puzzle_id, "moves") * everywhere * get_hand_tier_mult(puzzle_id) \
			* _upgrade_mult("puzzle_mult", puzzle_id)


func _mastery_mult(puzzle_id: String, effect_type: String) -> float:
	return _milestone_mult(puzzle_id, effect_type)


func _milestone_mult(puzzle_id: String, effect_type: String) -> float:
	var level := get_mastery_level(puzzle_id)
	var mult := 1.0
	for milestone: Dictionary in Content.MASTERY["milestones"]:
		if milestone["type"] == effect_type and level >= int(milestone["level"]):
			mult *= float(milestone["value"])
	return mult


## Total XP needed to reach `level` from level 1.
func _mastery_xp_at(level: int) -> float:
	var total := 0.0
	for l in range(1, level):
		total += get_mastery_xp_for_level(l)
	return total


func _add_mastery_xp(puzzle_id: String, xp: float) -> void:
	mastery_xp[puzzle_id] = get_mastery_xp(puzzle_id) + xp
	var old_level := get_mastery_level(puzzle_id)
	var level := _level_for_xp(mastery_xp[puzzle_id])
	_mastery_levels[puzzle_id] = level
	for l in range(old_level + 1, level + 1):
		mastery_level_up.emit(puzzle_id, l)


func _level_for_xp(xp: float) -> int:
	var level := 1
	var needed := get_mastery_xp_for_level(1)
	var max_level := int(Content.MASTERY["max_level"])
	while level < max_level and xp >= needed:
		xp -= needed
		level += 1
		needed = get_mastery_xp_for_level(level)
	return level


func _or_focused(puzzle_id: String) -> String:
	return focused_puzzle if puzzle_id == "" else puzzle_id


## Tracks the player can hear: their unlock puzzle is unlocked and the file exists.
func get_unlocked_track_ids() -> Array[String]:
	var unlocked := get_unlocked_puzzle_ids()
	var ids: Array[String] = []
	for def: Dictionary in Content.TRACKS:
		if def["file"] != "" and unlocked.has(def["unlock"]):
			ids.append(def["id"])
	return ids


## The track that belongs to a puzzle ("" if it has none or isn't available yet).
func get_track_for_puzzle(puzzle_id: String) -> String:
	for def: Dictionary in Content.TRACKS:
		if def["unlock"] == puzzle_id and def["file"] != "":
			return def["id"]
	return ""


## The next new thing to aim for (the "Next goal" strip): the cheapest helper not owned yet, or upgrade not bought
## yet whose requirements are met. If everything is owned, the cheapest next copy of a helper (`more` = true).
## Returns {kind, id, name, cost, missing (Solves still needed, 0 = can buy now), seconds (at the current
## helper rate; INF without helpers), more}. The next method (kind "method") and the next puzzle (kind "puzzle")
## are candidates too.
func get_next_goal() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for def: Dictionary in Content.BUILDINGS:
		if int(buildings.get(def["id"], 0)) == 0:
			candidates.append({"kind": "helper", "id": def["id"], "name": def["name"], "cost": get_building_cost(def["id"]), "more": false})
	for def: Dictionary in Content.get_upgrades():
		if upgrades.has(def["id"]) or not _upgrade_requirements_met(def) or is_upgrade_locked_out(def["id"]):
			continue
		candidates.append({"kind": "upgrade", "id": def["id"], "name": def["name"], "cost": float(def["cost"]), "more": false})
	var next_method := get_next_method()
	if not next_method.is_empty() and String(research.get("id", "")) != "method_" + String(next_method["id"]):
		candidates.append({"kind": "method", "id": next_method["id"], "name": next_method["name"],
				"cost": float(next_method["cost"]), "more": false})
	var next_puzzle := get_next_locked_puzzle()
	if next_puzzle != "":
		candidates.append({"kind": "puzzle", "id": next_puzzle, "name": Content.get_puzzle(next_puzzle)["name"],
				"cost": get_puzzle_unlock_cost(next_puzzle), "more": false})
	if candidates.is_empty():
		for def: Dictionary in Content.BUILDINGS:
			candidates.append({"kind": "helper", "id": def["id"], "name": def["name"], "cost": get_building_cost(def["id"]), "more": true})
	if candidates.is_empty():
		return {}
	var best: Dictionary = candidates[0]
	for candidate in candidates:
		if float(candidate["cost"]) < float(best["cost"]):
			best = candidate
	var missing := maxf(0.0, float(best["cost"]) - solves)
	var rate := get_solves_per_second()
	best["missing"] = missing
	best["seconds"] = 0.0 if missing <= 0.0 else (missing / rate if rate > 0.0 else INF)
	return best


# --- Cube times and goals (task R.3) --------------------------------------------------

## Seconds ONE helper of this kind takes for one solve on a puzzle: the puzzle's moves per solve ÷ the helper's moves/s
## there (its upgrades and the puzzle's mastery bonus count). INF if it makes no moves.
func get_helper_solve_time(building_id: String, puzzle_id: String = "") -> float:
	var id := _or_focused(puzzle_id)
	var mps := get_building_mps(building_id) * get_puzzle_moves_mult(id)
	return get_moves_per_solve(id) / mps if mps > 0.0 else INF


## The team's best time on a puzzle: the fastest helper kind the player owns. INF with no helpers.
func get_team_solve_time(puzzle_id: String = "") -> float:
	var best := INF
	for def: Dictionary in Content.BUILDINGS:
		if int(buildings.get(def["id"], 0)) > 0:
			best = minf(best, get_helper_solve_time(def["id"], puzzle_id))
	return best


## The best time tier the team has reached on a puzzle: {index, name, seconds}, or {} below the first.
func get_time_tier(puzzle_id: String = "") -> Dictionary:
	var id := _or_focused(puzzle_id)
	var tiers: Array = Content.TIME_TIERS.get(id, [])
	var time := get_team_solve_time(id)
	var reached := {}
	for i in tiers.size():
		if time < float(tiers[i][0]):
			reached = {"index": i, "name": tiers[i][1], "seconds": float(tiers[i][0])}
	return reached


## The next tier to reach on a puzzle: {index, name, seconds}, or {} past the last.
func get_next_time_tier(puzzle_id: String = "") -> Dictionary:
	var id := _or_focused(puzzle_id)
	var tiers: Array = Content.TIME_TIERS.get(id, [])
	var index := int(get_time_tier(id).get("index", -1)) + 1
	return {} if index >= tiers.size() else {"index": index, "name": tiers[index][1], "seconds": float(tiers[index][0])}


## Emits time_tier_reached for every unlocked puzzle whose team time just crossed a new tier (the best one only).
## A puzzle seen for the first time (or after a load, emit = false) is just noted, so old tiers never pop.
func check_time_tiers(emit: bool = true) -> void:
	for id in unlocked_puzzles:
		var tier := get_time_tier(id)
		var index := int(tier.get("index", -1))
		if not _tier_reached.has(id) or not emit:
			_tier_reached[id] = index
			continue
		if index > int(_tier_reached[id]):
			_tier_reached[id] = index
			time_tier_reached.emit(id, tier["name"], get_team_solve_time(id))


# --- Hand-solve rewards (task S.3) ------------------------------------------------------

## The tier a time reaches on a puzzle (0 = Bronze ... 5 = Master), or -1 below every target (or a DNF).
func get_hand_tier(puzzle_id: String, seconds: float) -> int:
	var targets: Array = (Content.SOLVE_REWARDS["targets"] as Dictionary).get(puzzle_id, [])
	var tier := -1
	for i in targets.size():
		if seconds <= float(targets[i]):
			tier = i
	return tier


## The best tier the puzzle's PB single has reached (-1 for none): the permanent bonus.
func get_best_hand_tier(puzzle_id: String) -> int:
	var single := float(get_solve_bests(puzzle_id)["single"])
	return -1 if is_inf(single) else get_hand_tier(puzzle_id, single)


static func hand_tier_name(tier: int) -> String:
	var names: Array = Content.SOLVE_REWARDS["tiers"]
	return names[tier] if tier >= 0 and tier < names.size() else ""


## Moves on a puzzle ×(1 + 5 % per tier its PB has reached).
func get_hand_tier_mult(puzzle_id: String) -> float:
	return 1.0 + float(Content.SOLVE_REWARDS["tier_moves_bonus"]) * (get_best_hand_tier(puzzle_id) + 1)


## Flow's multiplier on every move while it runs (not during offline catch-up), else 1.
func get_flow_mult() -> float:
	if flow.is_empty() or _offline_catch_up:
		return 1.0
	return float(flow["mult"])


func update_flow(delta: float) -> void:
	if flow.is_empty() or delta <= 0.0:
		return
	flow["left"] = float(flow["left"]) - delta
	if float(flow["left"]) <= 0.0:
		flow = {}


## A finished hand solve: Flow (by this solve's tier; a new solve replaces the old Flow), mastery XP, and a new tier if
## the PB single reached one. Fills info with {tier, flow_mult, flow_seconds, new_tier}.
func _reward_hand_solve(puzzle_id: String, final: float, pb_single: bool, tier_before: int, info: Dictionary) -> void:
	var data: Dictionary = Content.SOLVE_REWARDS
	info["tier"] = -1
	info["new_tier"] = -1
	if is_inf(final):  # a DNF earns nothing
		return
	var tier := get_hand_tier(puzzle_id, final)
	var mult := float((data["flow_by_tier"] as Array)[tier + 1])
	var seconds := maxf(float(data["flow_min_seconds"]), float(data["flow_time_factor"]) * final)
	flow = {"mult": mult, "left": seconds, "tier": tier}
	info["tier"] = tier
	info["flow_mult"] = mult
	info["flow_seconds"] = seconds
	flow_started.emit(mult, seconds)
	if unlocked_puzzles.has(puzzle_id):
		var xp := float(data["xp_solves"]) * get_mastery_xp_per_solve(puzzle_id)
		_add_mastery_xp(puzzle_id, xp * (float(data["xp_pb_factor"]) if pb_single else 1.0))
	var tier_now := get_best_hand_tier(puzzle_id)
	if tier_now > tier_before:
		info["new_tier"] = tier_now
		hand_tier_reached.emit(puzzle_id, hand_tier_name(tier_now))
		check_helper_times()
		check_time_tiers()


# --- Daily scramble (task S.5) ------------------------------------------------------

## Today's date in UTC ("2026-11-04"): the daily scramble is the same for everyone that day.
func get_daily_date() -> String:
	var now := daily_now if daily_now >= 0.0 else Time.get_unix_time_from_system()
	return Time.get_date_string_from_unix_time(int(now))


## The seed for a puzzle's daily scramble on a date: FNV-1a over "date:puzzle", so it never depends on the engine's hash.
static func daily_seed(date: String, puzzle_id: String) -> int:
	var h := 2166136261
	for byte in ("%s:%s" % [date, puzzle_id]).to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & 0xFFFFFFFF
	return h


## Today's results, rolled over to a fresh day when the date changed.
func get_daily() -> Dictionary:
	var today := get_daily_date()
	if String(daily.get("date", "")) != today:
		var ever: Dictionary = daily.get("fmc_ever", {})
		daily = {"date": today, "rewarded": false, "times": {}, "fmc": {}, "fmc_ever": ever}
	return daily


## A finished daily: mode "time" (seconds, final with penalties; INF = DNF) or "fmc" (moves). Keeps today's best (and
## the best FMC ever) and pays the day's reward the first time. Returns {best, pb_today, reward}.
func record_daily(puzzle_id: String, mode: String, value: float) -> Dictionary:
	var today := get_daily()
	if Content.get_puzzle(puzzle_id).is_empty() or not mode in ["time", "fmc"] or value <= 0.0:
		return {}
	var key := "times" if mode == "time" else "fmc"
	var bests: Dictionary = today[key]
	var pb := not is_inf(value) and value < float(bests.get(puzzle_id, INF))
	if pb:
		bests[puzzle_id] = value
	if mode == "fmc" and value < float((today["fmc_ever"] as Dictionary).get(puzzle_id, INF)):
		today["fmc_ever"][puzzle_id] = value
	var reward := 0.0
	if not bool(today["rewarded"]) and not is_inf(value):
		reward = maxf(get_solves_per_second() * float(Content.DAILY["reward_minutes"]) * 60.0,
				float(Content.DAILY["min_solves_value"]) * get_solve_value(focused_puzzle))
		solves += reward
		total_solves += reward
		today["rewarded"] = true
		daily_rewarded.emit(reward)
	return {"best": float(bests.get(puzzle_id, INF)), "pb_today": pb, "reward": reward}


func is_daily_reward_ready() -> bool:
	return not bool(get_daily()["rewarded"])


func _clean_daily(saved: Variant) -> Dictionary:
	if typeof(saved) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = saved
	var out := {"date": String(d.get("date", "")), "rewarded": bool(d.get("rewarded", false)), "times": {}, "fmc": {}, "fmc_ever": {}}
	for key: String in ["times", "fmc", "fmc_ever"]:
		var values: Variant = d.get(key, {})
		if typeof(values) != TYPE_DICTIONARY:
			continue
		for id: String in values:
			if not Content.get_puzzle(id).is_empty() and float(values[id]) > 0.0:
				out[key][id] = float(values[id])
	return out


# --- Algorithm drills (task S.4) ------------------------------------------------------

## A finished drill of one case (an algorithm id) in `set_id`: best time, clean solves (within the set's target), learned.
## Returns {pb, clean (this one), clean_count, learned (now), learned_now (just now), set_learned_now}.
func record_drill(set_id: String, case_id: String, seconds: float) -> Dictionary:
	var drill := Content.get_drill_set(set_id)
	if drill.is_empty() or Content.get_algorithm(case_id).is_empty() or seconds <= 0.0:
		return {}
	var was_learned := is_case_learned(case_id)
	var set_was_learned := is_drill_set_learned(set_id)
	var entry: Dictionary = drills.get(case_id, {"best": INF, "clean": 0, "count": 0})
	var pb := seconds < float(entry["best"])
	entry["best"] = minf(float(entry["best"]), seconds)
	entry["count"] = int(entry["count"]) + 1
	var clean := seconds <= float(drill["target"])
	if clean:
		entry["clean"] = int(entry["clean"]) + 1
	drills[case_id] = entry
	var learned_now := not was_learned and is_case_learned(case_id)
	if learned_now:
		drill_case_learned.emit(case_id)
	var set_learned_now := not set_was_learned and is_drill_set_learned(set_id)
	if set_learned_now:
		drill_set_learned.emit(set_id)
	return {"pb": pb, "clean": clean, "clean_count": int(entry["clean"]), "learned": is_case_learned(case_id),
			"learned_now": learned_now, "set_learned_now": set_learned_now}


func is_case_learned(case_id: String) -> bool:
	return int((drills.get(case_id, {}) as Dictionary).get("clean", 0)) >= int(Content.DRILLS["clean_needed"])


func get_drill_record(case_id: String) -> Dictionary:
	return drills.get(case_id, {"best": INF, "clean": 0, "count": 0})


## {learned, total} for a drill set.
func get_drill_set_progress(set_id: String) -> Dictionary:
	var cases := Content.get_drill_cases(set_id)
	var learned := 0
	for alg: Dictionary in cases:
		if is_case_learned(alg["id"]):
			learned += 1
	return {"learned": learned, "total": cases.size()}


func is_drill_set_learned(set_id: String) -> bool:
	var progress := get_drill_set_progress(set_id)
	return int(progress["total"]) > 0 and int(progress["learned"]) >= int(progress["total"])


# --- Golden Scramble (task S.6) ------------------------------------------------------

## Runs the golden sticker's clock, the attempt's clock and the buff's clock (from _process; tests call it).
func update_golden(delta: float) -> void:
	if delta <= 0.0:
		return
	if not buff.is_empty():
		buff["left"] = float(buff["left"]) - delta
		if float(buff["left"]) <= 0.0:
			buff = {}
	if golden_attempt_left > 0.0:
		golden_attempt_left -= delta
		if golden_attempt_left <= 0.0:
			golden_attempt_left = 0.0
			golden_finished.emit(false, {})
		return  # no new sticker while a case is being solved
	if golden_glow_left > 0.0:
		golden_glow_left -= delta
		if golden_glow_left <= 0.0:
			golden_glow_left = 0.0
			golden_next = _roll_golden_wait()
			golden_expired.emit()
		return
	golden_next -= delta
	if golden_next <= 0.0:
		golden_next = 0.0
		golden_glow_left = float(Content.GOLDEN["glow"])
		golden_spawned.emit()


## Clicking the glowing sticker: starts the timed case. Returns false if nothing glows.
func claim_golden() -> bool:
	if golden_glow_left <= 0.0 or golden_attempt_left > 0.0:
		return false
	golden_glow_left = 0.0
	golden_attempt_left = float(Content.GOLDEN["solve_seconds"])
	return true


## How many moves from solved the next golden case is (Content.GOLDEN case_moves_min..max).
func roll_golden_case_moves() -> int:
	return golden_rng.randi_range(int(Content.GOLDEN["case_moves_min"]), int(Content.GOLDEN["case_moves_max"]))


## The case is over: solved in time (success) or not. A success rolls a buff and applies it; returns
## {id, name, text, mult, seconds | solves} ({} on a miss or with no attempt running). Emits golden_finished.
func finish_golden(success: bool) -> Dictionary:
	if golden_attempt_left <= 0.0:
		return {}
	golden_attempt_left = 0.0
	golden_next = _roll_golden_wait()
	if not success:
		golden_finished.emit(false, {})
		return {}
	var result := _apply_golden_buff(_roll_golden_buff())
	golden_finished.emit(true, result)
	return result


## ×N on every move while a Frenzy runs (not during offline catch-up), else 1.
func get_buff_mult() -> float:
	if buff.is_empty() or _offline_catch_up:
		return 1.0
	return float(buff.get("mult", 1.0))


## Applies a buff from Content.GOLDEN["buffs"] (tests call it with a chosen one).
func _apply_golden_buff(def: Dictionary) -> Dictionary:
	match String(def.get("id", "")):
		"frenzy":
			buff = {"id": "frenzy", "mult": float(def["mult"]), "left": float(def["seconds"])}
			return {"id": "frenzy", "name": def["name"], "mult": float(def["mult"]), "seconds": float(def["seconds"]),
					"text": "%s: ×%s moves for %ds" % [def["name"], Num.format(float(def["mult"])), int(def["seconds"])]}
		"lucky":
			var amount := maxf(get_solves_per_second() * float(def["minutes"]) * 60.0,
					float(def["min_solves_value"]) * get_solve_value(focused_puzzle))
			solves += amount
			total_solves += amount
			return {"id": "lucky", "name": def["name"], "solves": amount,
					"text": "%s: +%s Solves (%d minutes' worth)" % [def["name"], Num.format(amount), int(def["minutes"])]}
	return {}


func _roll_golden_buff() -> Dictionary:
	var buffs: Array = Content.GOLDEN["buffs"]
	var total := 0.0
	for def: Dictionary in buffs:
		total += float(def["weight"])
	var pick := golden_rng.randf() * total
	for def: Dictionary in buffs:
		pick -= float(def["weight"])
		if pick <= 0.0:
			return def
	return buffs.back()


func _golden_buff_def(id: String) -> Dictionary:
	for def: Dictionary in Content.GOLDEN["buffs"]:
		if def["id"] == id:
			return def
	return {}


func _roll_golden_wait() -> float:
	return golden_rng.randf_range(float(Content.GOLDEN["spawn_min"]), float(Content.GOLDEN["spawn_max"]))


## Emits helper_best_time for each helper kind whose solve time on the focused puzzle is new (its first copy) or at least
## 5 % faster than the last one reported. emit = false just notes the current times (after a load or a focus change).
func check_helper_times(emit: bool = true) -> void:
	for def: Dictionary in Content.BUILDINGS:
		var id: String = def["id"]
		if int(buildings.get(id, 0)) <= 0:
			continue
		var time := get_helper_solve_time(id, focused_puzzle)
		var known: Array = _helper_best.get(id, [])
		var first := known.is_empty()
		if not emit or first or known[0] != focused_puzzle or time < float(known[1]) * 0.95:
			_helper_best[id] = [focused_puzzle, time]
			if emit and (first or known[0] == focused_puzzle):
				helper_best_time.emit(id, focused_puzzle, time, first)


## The first power of ten (from 100) above an amount of lifetime Solves.
func _milestone_above(amount: float) -> float:
	var next := 100.0
	while next <= amount:
		next *= 10.0
	return next


## Solves a puzzle completes each second (a count, not Solves earned).
func get_puzzle_solve_rate(puzzle_id: String = "") -> float:
	var id := _or_focused(puzzle_id)
	return get_puzzle_moves_per_second(id) / get_moves_per_solve(id)


## The next few things to aim for, soonest first, at most one of each kind (helper, upgrade, method, puzzle, mastery):
## [{kind, id, name, more, unit ("Solves"/"XP"), missing, seconds (ETA, INF if unknown), progress (0..1)}].
## Cost goals count the player's Solves; the mastery goal is the focused puzzle's next milestone level.
func get_goals(limit: int = 3) -> Array[Dictionary]:
	var by_kind := {}
	var add := func(goal: Dictionary) -> void:
		var kind: String = goal["kind"]
		if not by_kind.has(kind) or _goal_before(goal, by_kind[kind]):
			by_kind[kind] = goal
	var rate := get_solves_per_second()
	var cost_goal := func(kind: String, id: String, name: String, cost: float, more: bool) -> Dictionary:
		var missing := maxf(0.0, cost - solves)
		return {"kind": kind, "id": id, "name": name, "more": more, "unit": "Solves", "missing": missing,
				"seconds": 0.0 if missing <= 0.0 else (missing / rate if rate > 0.0 else INF),
				"progress": 1.0 if cost <= 0.0 else clampf(solves / cost, 0.0, 1.0)}
	var all_owned := true
	for def: Dictionary in Content.BUILDINGS:
		if int(buildings.get(def["id"], 0)) == 0:
			all_owned = false
			add.call(cost_goal.call("helper", def["id"], def["name"], get_building_cost(def["id"]), false))
	if all_owned:
		for def: Dictionary in Content.BUILDINGS:
			add.call(cost_goal.call("helper", def["id"], def["name"], get_building_cost(def["id"]), true))
	for def: Dictionary in Content.get_upgrades():
		if not upgrades.has(def["id"]) and _upgrade_requirements_met(def) and not is_upgrade_locked_out(def["id"]):
			add.call(cost_goal.call("upgrade", def["id"], def["name"], float(def["cost"]), false))
	var next_method := get_next_method()
	if not next_method.is_empty() and String(research.get("id", "")) != "method_" + String(next_method["id"]):
		add.call(cost_goal.call("method", next_method["id"], next_method["name"], float(next_method["cost"]), false))
	var running := get_research_progress()
	if not running.is_empty():  # the Lab project being researched (5.6): already paid, just time left
		add.call({"kind": "research", "id": running["id"], "name": "Research " + String(running["topic"]), "more": false, "unit": "time",
				"missing": running["left"], "seconds": running["left"], "progress": running["fraction"]})
	var next_puzzle := get_next_locked_puzzle()
	if next_puzzle != "":
		add.call(cost_goal.call("puzzle", next_puzzle, Content.get_puzzle(next_puzzle)["name"],
				get_puzzle_unlock_cost(next_puzzle), false))
	var milestone := get_next_mastery_milestone(focused_puzzle)
	if not milestone.is_empty():
		var level := int(milestone["level"])
		var target := _mastery_xp_at(level)
		var start := _mastery_xp_at(maxi(1, _previous_milestone_level(level)))
		var xp := get_mastery_xp(focused_puzzle)
		var xp_rate := get_puzzle_solve_rate(focused_puzzle) * get_mastery_xp_per_solve(focused_puzzle)
		var missing := maxf(0.0, target - xp)
		add.call({"kind": "mastery", "id": focused_puzzle, "more": false, "unit": "XP", "missing": missing,
				"name": "%s Mastery %d" % [Content.get_puzzle(focused_puzzle)["name"], level],
				"seconds": 0.0 if missing <= 0.0 else (missing / xp_rate if xp_rate > 0.0 else INF),
				"progress": clampf((xp - start) / maxf(1.0, target - start), 0.0, 1.0)})
	var goals: Array[Dictionary] = []
	for kind: String in by_kind:
		goals.append(by_kind[kind])
	goals.sort_custom(_goal_before)
	return goals.slice(0, limit)


## Soonest first; with the same (or no) estimate, Solves goals before mastery, then the cheapest.
func _goal_before(a: Dictionary, b: Dictionary) -> bool:
	if float(a["seconds"]) != float(b["seconds"]):
		return float(a["seconds"]) < float(b["seconds"])
	if (a["unit"] == "time") != (b["unit"] == "time"):
		return b["unit"] == "time"
	if (a["unit"] == "XP") != (b["unit"] == "XP"):
		return b["unit"] == "XP"
	return float(a["missing"]) < float(b["missing"])


func _previous_milestone_level(level: int) -> int:
	var previous := 1
	for milestone: Dictionary in Content.MASTERY["milestones"]:
		if int(milestone["level"]) < level:
			previous = int(milestone["level"])
	return previous


func _upgrade_requirements_met(def: Dictionary) -> bool:
	var requires: Dictionary = def.get("requires", {})
	for building_id: String in requires:
		if int(buildings.get(building_id, 0)) < int(requires[building_id]):
			return false
	return true


## Synergies on a helper (5.3): ×(1 + value × copies of the source) for each owned synergy upgrade that targets it.
func _synergy_mult(target: String) -> float:
	if upgrades.size() + 1000 * research_done.size() != _mult_cache_owned:
		_mult_cache.clear()
		_mult_cache_owned = upgrades.size() + 1000 * research_done.size()
	var key := "synergy_defs|" + target
	if not _mult_cache.has(key):  # which owned synergies target this helper (only changes with the owned set)
		var found: Array = []
		for id: String in upgrades:
			var effect: Dictionary = Content.get_upgrade(id).get("effect", {})
			if effect.get("type", "") == "synergy" and effect.get("target", "") == target:
				found.append(effect)
		_mult_cache[key] = found
	var mult := 1.0
	for effect: Dictionary in _mult_cache[key]:
		mult *= 1.0 + float(effect["value"]) * int(buildings.get(effect["source"], 0))
	return mult


# --- Algorithm Lab (task 5.6) ---------------------------------------------------------

## True for a finished project (a method project: that method is learned).
func is_research_done(id: String) -> bool:
	var def := Content.get_lab_project(id)
	if def.is_empty():
		return false
	if def["kind"] == "method":
		return is_method_learned(def["method"])
	return research_done.has(id)


## Can this project be started now: not done, not running, the slot free, its requirements done, in reach (half its cost
## in lifetime Solves, like upgrades) and affordable.
func can_start_research(id: String) -> bool:
	return is_research_visible(id) and research.is_empty() and solves >= float(Content.get_lab_project(id)["cost"])


## Shown in the Lab: not done, requirements done, and half its cost earned (lifetime), like an upgrade.
func is_research_visible(id: String) -> bool:
	var def := Content.get_lab_project(id)
	if def.is_empty() or is_research_done(id) or String(research.get("id", "")) == id:
		return false
	return _lab_requirements_done(def) and total_solves >= float(def["cost"]) * 0.5


## Pays for a project and starts it. False if it can't start (see can_start_research).
func start_research(id: String) -> bool:
	if not can_start_research(id):
		return false
	var def := Content.get_lab_project(id)
	solves -= float(def["cost"])
	research = {"id": id, "left": float(def["seconds"])}
	research_started.emit(id)
	if float(def["seconds"]) <= 0.0:
		update_research(0.0001)
	return true


## Runs the Lab's clock (from _process, and for time away: apply_save_data, capped like offline progress).
func update_research(delta: float) -> void:
	if research.is_empty() or delta <= 0.0:
		return
	research["left"] = float(research["left"]) - delta
	if float(research["left"]) <= 0.0:
		_complete_research(String(research["id"]))


## Finishes the running project at once (tests and debugging).
func finish_research() -> void:
	if not research.is_empty():
		_complete_research(String(research["id"]))


## {id, name, topic (the name without "Learn "), left, total, fraction} for the running project, or {}.
func get_research_progress() -> Dictionary:
	if research.is_empty():
		return {}
	var def := Content.get_lab_project(String(research["id"]))
	var total := maxf(0.001, float(def.get("seconds", 1.0)))
	return {"id": research["id"], "name": def.get("name", ""), "topic": def.get("topic", ""), "left": maxf(0.0, float(research["left"])), "total": total,
			"fraction": clampf(1.0 - float(research["left"]) / total, 0.0, 1.0)}


func _complete_research(id: String) -> void:
	var def := Content.get_lab_project(id)
	if String(research.get("id", "")) == id:
		research = {}
	if def.is_empty():
		return
	if def["kind"] == "method":
		if Content.get_method_index(def["method"]) > Content.get_method_index(method):
			method = def["method"]
		research_finished.emit(id)
		purchased.emit("method", def["method"])
	else:
		research_done[id] = true
		research_finished.emit(id)
		check_helper_times()
		check_time_tiers()


## Learning a drill set in the Solve Station finishes its Lab project for free ("your own practice counts", S.4).
func _on_drill_set_learned_for_lab(set_id: String) -> void:
	for def in Content.get_lab_projects():
		if String(def.get("drill_set", "")) == set_id and not is_research_done(def["id"]):
			_complete_research(def["id"])


## Product of every owned upgrade's effect of this type (and target). Cached: with ~50 upgrades (5.2) this is called
## thousands of times a second by the balance bot. The cache is dropped whenever the number of owned upgrades changes
## (buying, a reset, a load, or the bot trying one on), which is the only way the set changes.
func _upgrade_mult(effect_type: String, target: String = "") -> float:
	if upgrades.size() + 1000 * research_done.size() != _mult_cache_owned:
		_mult_cache.clear()
		_mult_cache_owned = upgrades.size() + 1000 * research_done.size()
	var key := effect_type + "|" + target
	if _mult_cache.has(key):
		return _mult_cache[key]
	var mult := 1.0
	for id: String in upgrades:
		var def := Content.get_upgrade(id)
		if def.is_empty():
			continue
		var effect: Dictionary = def["effect"]
		if effect["type"] != effect_type:
			continue
		if target != "" and effect.get("target", "") != target and not (effect.get("puzzles", []) as Array).has(target):
			continue
		mult *= float(effect["value"])
	for id: String in research_done:  # finished Lab projects (5.6) count like owned upgrades
		var lab_effect: Dictionary = Content.get_lab_project(id).get("effect", {})
		if lab_effect.get("type", "") != effect_type or (target != "" and lab_effect.get("target", "") != target):
			continue
		mult *= float(lab_effect["value"])
	_mult_cache[key] = mult
	return mult


# --- Save / load -------------------------------------------------------------

func reset_state() -> void:
	solves = 0.0
	total_solves = 0.0
	total_moves = 0.0
	unlocked_puzzles.clear()
	puzzle_progress.clear()
	_add_puzzle(Content.PUZZLES[0]["id"])
	focused_puzzle = Content.PUZZLES[0]["id"]
	split = {focused_puzzle: 1.0}
	mastery_xp.clear()
	_mastery_levels.clear()
	buildings.clear()
	for def: Dictionary in Content.BUILDINGS:
		buildings[def["id"]] = 0
	upgrades.clear()
	method = Content.METHODS[0]["id"]
	solve_records.clear()
	_solve_bests.clear()
	offline_report = {}
	_tier_reached.clear()
	check_time_tiers(false)
	_helper_best.clear()
	check_helper_times(false)
	_next_solves_milestone = _milestone_above(total_solves)
	buff = {}
	golden_glow_left = 0.0
	golden_attempt_left = 0.0
	golden_rng.randomize()
	golden_next = _roll_golden_wait()
	flow = {}
	drills.clear()
	daily = {}
	research = {}
	research_done.clear()


func get_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"solves": solves,
		"total_solves": total_solves,
		"total_moves": total_moves,
		"puzzles": {
			"unlocked": unlocked_puzzles.duplicate(),
			"progress": puzzle_progress.duplicate(),
			"focus": focused_puzzle,
			"split": split.duplicate(),
		},
		"mastery": mastery_xp.duplicate(),
		"buildings": buildings.duplicate(),
		"upgrades": upgrades.keys(),
		"method": method,
		"solve_records": solve_records.duplicate(true),
		"golden": {"next": golden_next, "buff": buff.duplicate()},
		"drills": drills.duplicate(true),
		"daily": daily.duplicate(true),
		"lab": {"current": research.duplicate(), "done": research_done.keys()},
	}


## Saves safely: write `save.json.tmp`, check it reads back, keep the old save as `save.bak`,
## then rename the temp file into place. A crash at any point leaves a readable save or backup.
func save_game() -> bool:
	var text := JSON.stringify(get_save_data(), "\t")
	var tmp := save_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	var written := file.store_string(text)
	file.close()
	if not written or _read_save_file(tmp).is_empty():
		push_warning("Save did not write correctly; keeping the previous save.")
		_remove(tmp)
		return false
	var backup := get_backup_path()
	if FileAccess.file_exists(save_path):
		_remove(backup)
		_rename(save_path, backup)
	if not _rename(tmp, save_path):
		push_warning("Could not move the new save into place.")
		return false
	return true


## Loads the save, or the backup if the save is missing or damaged. Sets `load_notice` when it had to
## fall back. With neither file present it's a fresh start.
func load_game() -> void:
	load_notice = ""
	var main_exists := FileAccess.file_exists(save_path)
	var backup_exists := FileAccess.file_exists(get_backup_path())
	if not main_exists and not backup_exists:
		return
	var data := _read_save_file(save_path) if main_exists else {}
	if not data.is_empty():
		apply_save_data(data, Time.get_unix_time_from_system())
		return
	if main_exists:
		_keep_corrupt_copy()
	data = _read_save_file(get_backup_path()) if backup_exists else {}
	if not data.is_empty():
		push_warning("Save file is %s; loaded the backup." % ("unreadable" if main_exists else "missing"))
		apply_save_data(data, Time.get_unix_time_from_system())
		load_notice = "Your save file was %s, so the backup from a few seconds earlier was loaded." \
				% ("damaged" if main_exists else "missing")
		return
	push_warning("Save file and backup are unreadable; starting fresh.")
	load_notice = "Your save file was damaged and no backup could be read, so the game started fresh."
	if main_exists:
		load_notice += "\nThe damaged file was kept as %s." % get_corrupt_path().get_file()


func get_backup_path() -> String:
	return save_path.get_basename() + ".bak"


func get_corrupt_path() -> String:
	return save_path.get_basename() + ".corrupt.json"


## Parsed save data, or {} if the file is missing or isn't a save.
func _read_save_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()  # parse() reports failure quietly; JSON.parse_string() would log an engine error
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("version"):
		return {}
	return data


func _keep_corrupt_copy() -> void:
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(get_corrupt_path()))
	if err != OK:
		push_warning("Could not keep a copy of the damaged save: %s" % error_string(err))


func _rename(from: String, to: String) -> bool:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to)) == OK


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Restores state from save data, then grants offline progress up to `now`.
func apply_save_data(data: Dictionary, now: float) -> void:
	reset_state()
	data = _migrate(data)
	solves = float(data.get("solves", 0.0))
	total_solves = float(data.get("total_solves", 0.0))
	total_moves = float(data.get("total_moves", 0.0))
	var saved_mastery: Dictionary = data.get("mastery", {})
	for id: String in saved_mastery:
		if not Content.get_puzzle(id).is_empty():
			mastery_xp[id] = maxf(0.0, float(saved_mastery[id]))
			_mastery_levels[id] = _level_for_xp(mastery_xp[id])
	var saved_puzzles: Dictionary = data.get("puzzles", {})
	for id in saved_puzzles.get("unlocked", []):
		_add_puzzle(str(id))  # unknown ids (removed from Content) are skipped
	var saved_progress: Dictionary = saved_puzzles.get("progress", {})
	for id: String in saved_progress:
		if puzzle_progress.has(id):
			puzzle_progress[id] = clampf(float(saved_progress[id]), 0.0, get_moves_per_solve(id))
	var saved_split: Dictionary = saved_puzzles.get("split", {})
	set_split(saved_split)
	var saved_focus := str(saved_puzzles.get("focus", ""))
	focused_puzzle = saved_focus if unlocked_puzzles.has(saved_focus) else unlocked_puzzles.back()
	var saved_buildings: Dictionary = data.get("buildings", {})
	for id: String in saved_buildings:
		if buildings.has(id):  # ignore helpers that were removed from Content
			buildings[id] = int(saved_buildings[id])
	for id: String in data.get("upgrades", []):
		if not Content.get_upgrade(id).is_empty() and not is_upgrade_locked_out(id):  # a damaged save: one per choice group
			upgrades[id] = true
	var saved_method := str(data.get("method", ""))
	if Content.get_method_index(saved_method) >= 0:  # an unknown id (removed from Content) keeps the Beginner Method
		method = saved_method
	var saved_records: Dictionary = data.get("solve_records", {})
	for id: String in saved_records:
		if Content.get_puzzle(id).is_empty():
			continue
		var history: Array = []
		for entry: Variant in (saved_records[id] as Dictionary).get("history", []):
			if typeof(entry) == TYPE_DICTIONARY and float((entry as Dictionary).get("t", 0.0)) > 0.0:
				var penalty := String((entry as Dictionary).get("p", ""))
				history.append({"t": float(entry["t"]), "p": penalty if PENALTIES.has(penalty) else "",
						"m": int((entry as Dictionary).get("m", 0)), "d": float((entry as Dictionary).get("d", 0.0))})
		history = history.slice(maxi(0, history.size() - SOLVE_HISTORY_LIMIT))
		solve_records[id] = {"history": history, "count": maxi(history.size(), int((saved_records[id] as Dictionary).get("count", 0)))}

	drills.clear()
	var saved_drills: Dictionary = data.get("drills", {})
	for id: String in saved_drills:
		var entry: Variant = saved_drills[id]
		if Content.get_algorithm(id).is_empty() or typeof(entry) != TYPE_DICTIONARY:
			continue
		var saved: Dictionary = entry
		var best := float(saved.get("best", 0.0))
		drills[id] = {"best": best if best > 0.0 else INF, "clean": maxi(0, int(saved.get("clean", 0))),
				"count": maxi(0, int(saved.get("count", 0)))}
	daily = _clean_daily(data.get("daily", {}))
	_load_lab(data.get("lab", {}))
	var saved_golden: Dictionary = data.get("golden", {})
	golden_next = clampf(float(saved_golden.get("next", golden_next)), 0.0, float(Content.GOLDEN["spawn_max"]))
	golden_glow_left = 0.0
	golden_attempt_left = 0.0
	buff = {}
	var saved_buff: Dictionary = saved_golden.get("buff", {})
	if _golden_buff_def(String(saved_buff.get("id", ""))).size() > 0 and float(saved_buff.get("left", 0.0)) > 0.0:
		buff = {"id": String(saved_buff["id"]), "mult": maxf(1.0, float(saved_buff.get("mult", 1.0))),
				"left": float(saved_buff["left"])}
	_tier_reached.clear()
	check_time_tiers(false)  # tiers reached before don't pop again
	_helper_best.clear()
	check_helper_times(false)
	_next_solves_milestone = _milestone_above(total_solves)
	var saved_at := float(data.get("saved_at", now))
	var elapsed := clampf(now - saved_at, 0.0, MAX_OFFLINE_SECONDS)
	if elapsed >= MIN_OFFLINE_SECONDS:
		var before := total_solves
		_offline_catch_up = true  # a buff pauses while the game is closed
		add_helper_moves(elapsed)
		_offline_catch_up = false
		var running := String(research.get("id", ""))
		update_research(elapsed)  # the Lab kept working too (capped like the rest)
		if total_solves > before or (running != "" and research.is_empty()):
			offline_report = {"seconds": elapsed, "solves": total_solves - before}
			if running != "" and research.is_empty():
				offline_report["research"] = Content.get_lab_project(running).get("topic", "")


## The saved Lab (5.6), checked like the rest of a save: unknown projects, ones whose requirements aren't done and a
## running project's impossible time left are dropped or clamped. A drill set learned in the Solve Station (S.4, maybe
## before the Lab existed) counts as its project done.
func _load_lab(saved: Variant) -> void:
	research = {}
	research_done.clear()
	var lab: Dictionary = saved if typeof(saved) == TYPE_DICTIONARY else {}
	var done_ids: Array = lab.get("done", []) if typeof(lab.get("done", [])) == TYPE_ARRAY else []
	var done_set := {}
	for id: Variant in done_ids:
		done_set[str(id)] = true
	for def: Dictionary in Content.get_lab_projects():  # in order, so a requirement is decided before what needs it
		if def["kind"] != "research":
			continue
		var drilled := String(def.get("drill_set", "")) != "" and is_drill_set_learned(def["drill_set"])
		if (done_set.has(def["id"]) and _lab_requirements_done(def)) or drilled:
			research_done[def["id"]] = true
	var current: Dictionary = lab.get("current", {}) if typeof(lab.get("current", {})) == TYPE_DICTIONARY else {}
	var id := str(current.get("id", ""))
	var def := Content.get_lab_project(id)
	if def.is_empty() or is_research_done(id) or not _lab_requirements_done(def):
		return
	if def["kind"] == "method" and get_next_method().get("id", "") != def["method"]:
		return
	var left := float(current.get("left", 0.0)) if typeof(current.get("left")) in [TYPE_FLOAT, TYPE_INT] else 0.0
	research = {"id": id, "left": clampf(left, 0.0, float(def["seconds"]))}


func _lab_requirements_done(def: Dictionary) -> bool:
	for need: Variant in def.get("requires", []):
		if not is_research_done(str(need)):
			return false
	return true


## Upgrades old save formats. Bump SAVE_VERSION and add a step here whenever
## the shape of get_save_data() changes, so existing players keep their progress.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	data["version"] = version
	if version < 2:
		# v1 had one 15-move solve and no puzzles. Old players start with the 2×2, plus the 3×3 if they had bought
		# any upgrade (they were past the start); the newest is focused and gets the whole split.
		# Their move progress goes to the starting puzzle (it's clamped to under one solve when applied).
		var unlocked: Array = ["2x2"]
		if not (data.get("upgrades", []) as Array).is_empty():
			unlocked.append("3x3")
		data["puzzles"] = {
			"unlocked": unlocked,
			"progress": {"2x2": float(data.get("move_progress", 0.0))},
			"focus": unlocked.back(),
			"split": {unlocked.back(): 1.0},
		}
		data.erase("move_progress")
		data["version"] = 2
	if int(data["version"]) < 3:
		# v3 added puzzle mastery: everyone starts at level 1.
		if not data.has("mastery"):
			data["mastery"] = {}
		data["version"] = 3
	if int(data["version"]) < 4:
		# v4 made methods a chain of their own. CFOP and Roux used to be ordinary upgrades ("cfop" ×0.7, "roux" ×0.8,
		# buyable in any order); they leave the upgrade list and become the method: Roux if it was owned (CFOP comes
		# with it, since the chain is learned in order), else CFOP, else the Beginner Method.
		var old_upgrades: Array = data.get("upgrades", [])
		var learned := "beginner"
		if old_upgrades.has("roux"):
			learned = "roux"
		elif old_upgrades.has("cfop"):
			learned = "cfop"
		data["upgrades"] = old_upgrades.filter(func(id: Variant) -> bool: return str(id) != "cfop" and str(id) != "roux")
		if not data.has("method"):
			data["method"] = learned
		data["version"] = 4
	if int(data["version"]) < 5:
		# v5 keeps hand solves from the Solve Station; nobody had any before.
		if not data.has("solve_records"):
			data["solve_records"] = {}
		data["version"] = 5
	if int(data["version"]) < 6:
		# v6 adds the Golden Scramble: the first one comes after the longest wait, and nobody has a buff yet.
		if not data.has("golden"):
			data["golden"] = {"next": float(Content.GOLDEN["spawn_max"]), "buff": {}}
		data["version"] = 6
	if int(data["version"]) < 7:
		# v7 keeps algorithm drill records; nobody had any.
		if not data.has("drills"):
			data["drills"] = {}
		data["version"] = 7
	if int(data["version"]) < 8:
		# v8 adds the daily scramble: nothing played yet.
		if not data.has("daily"):
			data["daily"] = {}
		data["version"] = 8
	if int(data["version"]) < 9:
		# v9 adds the Algorithm Lab: nothing researched yet (methods already learned stay learned).
		if not data.has("lab"):
			data["lab"] = {"current": {}, "done": []}
		data["version"] = 9
	return data


func wipe_save() -> void:
	reset_state()
	for path: String in [save_path, save_path + ".tmp", get_backup_path()]:
		_remove(path)
	state_reset.emit()


## Debug helper (F9 in debug builds).
func cheat_add_solves(amount: float) -> void:
	solves += amount
	total_solves += amount
