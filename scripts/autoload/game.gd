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
signal career_moment(moment_id: String)  ## a Content.CAREER story beat happened, once per player (7.0a)
signal achievement_earned(achievement_id: String)  ## a Content achievement was earned, once per player (7.1a)
signal collection_drop(item_id: String, stars: int, source: String)  ## a Cube Collection item dropped (7.3a); stars after it
signal competition_started(tier: String, puzzle_id: String)  ## 8.3a
signal competition_finished(result: Dictionary)  ## a competition ended: get_competition_result()'s dictionary
signal kit_changed  ## the Comp Kit changed (7.4a): an equip, a slot back on auto, or an auto slot that found a better item
signal championship_won(trophies_won: int)  ## a World Championship reset the run (6.2); the UI rebuilds after it
## Buying a trophy perk (6.3) emits purchased("perk", id).
signal golden_spawned
signal golden_expired
signal golden_finished(success: bool, buff: Dictionary)  ## a hand solve was recorded, edited or deleted (Solve Station)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 19  ## v2 (4.2): parallel puzzles; v3 (4.6): mastery; v4 (5.1): methods; v5 (S.2): solve records;
                          ## v6 (S.6): Golden Scramble timer + active buff; v7 (S.4): algorithm drill records;
                          ## v8 (S.5): daily scramble results + reward; v9 (5.6): Algorithm Lab research;
                          ## v10 (6.2): World Championships (trophies, run Solves, puzzles reached); v11 (6.3): trophy perks;
                          ## v12 (6.3b): auto-buyer toggles; v13 (7.0a): career moments seen; v14 (7.1a): achievements;
                          ## v15 (7.2a): stats; v16 (7.3a): Cube Collection;
                          ## v17 (7.4a): Comp Kit; v18 (7.6/7.8): Legendary pity counter, new career moments seen;
                          ## v19 (8.3a): competitions (the running one, medals, records)
const AUTOSAVE_INTERVAL := 10.0
const MAX_OFFLINE_SECONDS := 8.0 * 3600.0  ## the base offline cap; "offline_hours" perks add to it (get_offline_cap_seconds)
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
var run_solves := 0.0      ## Solves earned in this run (since the last World Championship, 6.2): trophies and "shows at
                           ## half its cost" read this, so a new run reveals the shop step by step again.
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
## Unspent trophies from World Championships (Phase 6): each gives Content.CHAMPIONSHIP["bonus_per_trophy"] more moves on
## every puzzle. Won by compete() (6.2), saved (v10), spent by the perk tree later (6.3).
var trophies := 0
var perks: Dictionary = {}      ## trophy perks bought (6.3): perk id -> true; kept through every championship
var automation: Dictionary = {}  ## auto-buyers (6.3b, saved): kind -> on (bool) for Content.AUTOMATION kinds, + "compete_at"
var automation_running := false  ## true while run_automation() buys: the UI keeps quiet about those purchases
var automation_paused := false   ## set by the UI while "Welcome back" is open: no auto-buyer runs (6.3b)
var auto_compete_held := false   ## set by the UI while a hand solve or the Compete screen is open: no auto-Compete
var _automation_timer := 0.0
var career_seen: Dictionary = {}  ## Content.CAREER ids that already fired (7.0a, saved; kept through championships)
var _career_timer := 0.0  ## also times the once-a-second achievement check
var achievements: Dictionary = {}  ## achievement ids earned (7.1a, saved; kept through championships): id -> true
var collection: Dictionary = {}       ## Cube Collection (7.3a, saved; kept through championships): item id -> stars (1..max)
var _collection_stars := 0           ## the stars in `collection`, kept up to date (the upgrade cache checks it constantly)
var collection_pity: Dictionary = {}  ## misses in a row per drop source, and "rarity": drops in a row below the pity rarity
var collection_rng := RandomNumberGenerator.new()  ## drops (seeded by tests and the balance bot)
var kit: Dictionary = {}         ## Comp Kit (7.4a, saved; kept through championships): slot id -> item id (empty slots absent)
## Competitions (8.3a, saved; kept through championships). competition: the one running ({} if none): {tier, puzzle,
## started_at (unix), seed, rating (the team's on the event when it registered), hand: {round index as text: seconds}}.
var competition: Dictionary = {}
var competition_medals: Dictionary = {}   ## "tier:puzzle" -> medal points (1 bronze, 2 silver, 3 gold), the best so far
var competition_records: Dictionary = {}  ## puzzle id -> {"single", "average"}: the team's official bests
var competition_result: Dictionary = {}   ## the last finished one, until the screen dismisses it (clear_competition_result)
var competitions_entered := 0
var competition_now := -1.0               ## tests: the unix time "now" for competitions (-1 = the real clock)
var _competition_timer := 0.0
var kit_manual: Dictionary = {}  ## slots the player filled (or emptied) by hand: auto-fill leaves them alone
var stats: Dictionary = {}  ## the Stats screen's counters (7.2a, saved; see _new_stats() for each one and what a championship keeps)
var _applying_save := false  ## true inside apply_save_data: no career moment is signalled (no UI listens yet)
var championships := 0          ## World Championships won (6.2); the first one opens the 7×7, the Megaminx and "Finals"
var puzzles_reached: Dictionary = {}  ## puzzle id -> true for every puzzle ever unlocked (kept through prestige: its music stays)
var method := "beginner"        ## id of the newest method learned (Content.METHODS); every earlier one is learned too
var offline_report: Dictionary = {}  ## {"seconds", "solves"} after loading, if anything was earned; plus "research" (a topic),
                                     ## "mastery" (puzzle -> [before, now]) and "achievements" (ids reached) when they happened
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
## The Golden Scramble being solved now (7.13; not saved, like the attempt's clock): {kind: "scramble", moves} or
## {kind: "oll"|"pll", case_id, alg, name, known}. {} when none.
var golden_case: Dictionary = {}
var flow: Dictionary = {}                  ## Flow from hand solves (S.3): {mult, left, tier}; not saved (ends on quit)
var streak := 0.0                          ## the TPS streak meter (S.7), 0..1 (Content.TAPS); not saved
var _tap_clock := 0.0                      ## seconds counted by update_streak (for the shown TPS)
var _tap_times: Array[float] = []          ## _tap_clock of the taps in the last Content.TAPS["tps_window"] seconds
var drills: Dictionary = {}                ## algorithm id -> {best, clean, count} (S.4, saved)
var research: Dictionary = {}              ## the Lab project being researched: {id, left} (5.6, saved), or {}
var research_done: Dictionary = {}         ## finished non-method Lab projects (methods are tracked by `method`)
var daily: Dictionary = {}                 ## S.5 (saved): {date, rewarded, times {puzzle: s}, fmc {puzzle: moves}, fmc_ever {puzzle: moves}}
var daily_now := -1.0                      ## tests: the unix time "now" for the daily (-1 = the real clock)
var _mult_cache: Dictionary = {}           ## _upgrade_mult results for the current set of owned upgrades
var _mult_cache_owned := -1                ## _mult_cache_key() the cache was built for (-1 = stale)
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
	purchased.connect(func(_kind: String, _id: String) -> void: check_career())  # a new helper, puzzle, method...
	championship_won.connect(func(_won: int) -> void: check_career())


func _ready() -> void:
	reset_state()
	if persistence_enabled:
		load_game()


func _process(delta: float) -> void:
	add_helper_moves(delta)
	update_play_time(delta)
	update_golden(delta)
	update_flow(delta)
	update_streak(delta)
	update_research(delta)
	_career_timer += delta
	if _career_timer >= 1.0:  # lifetime Solves grow without a purchase, so the career is also checked once a second
		_career_timer = 0.0
		check_career()
		stats["best_solves_per_second"] = maxf(float(stats["best_solves_per_second"]), get_solves_per_second())
		check_achievements()  # achievements only here (7.1a): a toast a second late is fine, and nothing else waits on them
	_competition_timer += delta
	if _competition_timer >= 1.0:
		_competition_timer = 0.0
		update_competition()
	_automation_timer += delta
	if _automation_timer >= float(Content.AUTOMATION["interval"]):
		_automation_timer = 0.0
		run_automation()
	if persistence_enabled:
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_INTERVAL:
			_autosave_timer = 0.0
			save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and persistence_enabled:
		save_game()


# --- Moves and solves --------------------------------------------------------

## One tap (a click, Space/Enter, or a turn of the main cube with the keys, S.7): moves on the focused puzzle, after
## which the TPS streak grows. Returns the tap's moves (as get_tap_moves() gave them before it).
func tap() -> float:
	var amount := get_tap_moves()
	add_moves_to(focused_puzzle, amount)
	stats["taps"] = float(stats["taps"]) + 1.0
	var data: Dictionary = Content.TAPS
	streak = minf(1.0, streak + float(data["fill_per_tap"]))
	_tap_times.append(_tap_clock)
	return amount


## Time passing for the TPS streak (S.7): the meter drains, old taps leave the TPS window. Not run offline.
func update_streak(delta: float) -> void:
	if delta <= 0.0:
		return
	var data: Dictionary = Content.TAPS
	_tap_clock += delta
	streak = maxf(0.0, streak - float(data["drain_per_second"]) * delta)
	var window := float(data["tps_window"])
	while not _tap_times.is_empty() and _tap_clock - _tap_times[0] > window:
		_tap_times.pop_front()


## The TPS streak's multiplier on taps: 1 with an empty meter, Content.TAPS["streak_max_mult"] with a full one.
func get_streak_mult() -> float:
	return 1.0 + (float(Content.TAPS["streak_max_mult"]) - 1.0) * clampf(streak, 0.0, 1.0)


## Taps a second over the last Content.TAPS["tps_window"] seconds (shown next to the streak).
func get_recent_tps() -> float:
	return _tap_times.size() / float(Content.TAPS["tps_window"])


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
		run_solves += reward
		if total_solves >= _next_solves_milestone:
			var passed := _next_solves_milestone
			while total_solves >= passed * 10.0:
				passed *= 10.0
			_next_solves_milestone = passed * 10.0
			solves_milestone.emit(passed)
		puzzle_progress[puzzle_id] = progress
		var per_puzzle: Dictionary = stats["puzzle_solves"]
		per_puzzle[puzzle_id] = float(per_puzzle.get(puzzle_id, 0.0)) + count
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


## Moves one tap makes on the focused puzzle (before that puzzle's own multipliers, like helper moves): the flat
## part (tap upgrades) plus Content.TAPS["helper_share"] of the helper moves/s it gets, × the TPS streak (S.7).
## The streak multiplies only the helpers' share, so it matters once there's a team and leaves the first minutes'
## pacing (where the flat part is everything) as it was.
func get_tap_moves() -> float:
	return get_tap_moves_flat() + get_tap_moves_from_helpers() * get_streak_mult()


func get_tap_moves_flat() -> float:
	return BASE_TAP_MOVES * _upgrade_mult("tap_mult") * _upgrade_mult("global_mult")


## The part of a tap that grows with the team: a share of the focused puzzle's helper moves per second (S.7).
func get_tap_moves_from_helpers() -> float:
	return get_tap_share() * _helper_rate(focused_puzzle)


## The share of the focused puzzle's helper moves/s every tap adds: Content.TAPS["helper_share"] + "tap_share" effects.
func get_tap_share() -> float:
	return float(Content.TAPS["helper_share"]) + _upgrade_sum("tap_share")


## Moves per second produced by ONE unit of a building.
func get_building_mps(id: String) -> float:
	var def := Content.get_building(id)
	return float(def["mps"]) * _upgrade_mult("building_mult", id) * _upgrade_mult("global_mult") * _synergy_mult(id) \
			* _upgrade_mult("helper_mult")


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


## Solves this run (6.2) at which a helper appears in the shop (its "unlock_at", or half its base cost).
func get_building_unlock_at(id: String) -> float:
	var def := Content.get_building(id)
	return float(def.get("unlock_at", float(def["base_cost"]) * 0.5))


func is_building_unlocked(id: String) -> bool:
	return int(buildings.get(id, 0)) > 0 or run_solves >= get_building_unlock_at(id)


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
	if def.is_empty() or run_solves < float(def["cost"]) * 0.5 or is_upgrade_locked_out(id):
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
	invalidate_upgrade_cache()
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


## Only the next method in the chain can be learned, and it shows up (like an upgrade) at half its cost in Solves this run.
func is_method_available(id: String) -> bool:
	var next := get_next_method()
	return not next.is_empty() and next["id"] == id and run_solves >= float(next["cost"]) * 0.5 \
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


## The 7×7 and Megaminx (requires_prestige) and the "Finals" track open with the first World Championship (6.2).
func has_won_championship() -> bool:
	return championships > 0


# --- World Championship (Phase 6) ------------------------------------------------

## Trophies a championship gives for this many Solves earned in the run: floor(sqrt(solves / divisor) × gain_mult)
## (gain_mult: "trophy_gain_mult" perks, 6.3). Checked against solves_for_trophies, so rounding never loses a trophy
## right at its threshold.
static func trophies_for(run_solves: float, gain_mult: float = 1.0) -> int:
	var count := floori(sqrt(maxf(0.0, run_solves) / float(Content.CHAMPIONSHIP["divisor"])) * gain_mult)
	if run_solves >= solves_for_trophies(count + 1, gain_mult):
		count += 1
	elif count > 0 and run_solves < solves_for_trophies(count, gain_mult):
		count -= 1
	return count


## Run Solves needed for a championship to give `count` trophies (the inverse of trophies_for).
static func solves_for_trophies(count: int, gain_mult: float = 1.0) -> float:
	var root := float(count) / gain_mult
	return root * root * float(Content.CHAMPIONSHIP["divisor"])


## How many times more trophies a championship gives: "trophy_gain_mult" perks (6.3) × achievements (7.1a).
func get_trophy_gain_mult() -> float:
	return _perk_product("trophy_gain_mult") * get_achievement_mult()


## The moves bonus each unspent trophy gives: Content.CHAMPIONSHIP's 2 % plus "trophy_bonus" perks (6.3).
func get_bonus_per_trophy() -> float:
	return float(Content.CHAMPIONSHIP["bonus_per_trophy"]) + _perk_sum("trophy_bonus")


## Solves earned in this run (since the last championship).
func get_run_solves() -> float:
	return run_solves


## Trophies competing now would give.
func get_pending_trophies() -> int:
	return trophies_for(get_run_solves(), get_trophy_gain_mult())


## Competing needs at least one trophy to win.
func can_compete() -> bool:
	return get_pending_trophies() >= 1


## The Compete button shows up at half the first trophy's Solves (like an upgrade at half its cost), or once trophies exist.
func is_compete_visible() -> bool:
	return trophies > 0 or has_won_championship() or get_run_solves() >= solves_for_trophies(1) * 0.5


## Enters the World Championship (6.2): wins get_pending_trophies() trophies and starts a new run. Keeps what
## Content.CHAMPIONSHIP["keeps"] promises (trophies and perks, mastery, hand-solve records and their tier bonuses, drills, dailies,
## music, lifetime stats; drill sets learned keep their Lab projects done) and resets the rest (Solves, run Solves,
## helpers, upgrades so choices reopen, puzzles back to the 2×2, methods, Lab research, Golden/Flow buffs).
## Returns the trophies won (0 = can't compete yet, nothing changes).
func compete() -> int:
	if not can_compete():
		return 0
	var gain := get_pending_trophies()
	trophies += gain
	championships += 1
	stats["trophies_won"] = float(stats["trophies_won"]) + gain
	var run_time := float(stats["run_time"])
	if run_time > 0.0 and float(stats["run_untimed"]) == 0.0:  # a run that started before v15 has no real time
		var fastest := float(stats["fastest_championship"])
		stats["fastest_championship"] = run_time if fastest <= 0.0 else minf(fastest, run_time)
	stats["run_time"] = 0.0
	stats["run_untimed"] = 0.0
	solves = 0.0
	run_solves = 0.0
	unlocked_puzzles.clear()
	puzzle_progress.clear()
	_add_puzzle(Content.PUZZLES[0]["id"])
	focused_puzzle = Content.PUZZLES[0]["id"]
	split = {focused_puzzle: 1.0}
	for def: Dictionary in Content.BUILDINGS:
		buildings[def["id"]] = 0
	upgrades.clear()
	method = Content.METHODS[0]["id"]
	research = {}
	research_done.clear()
	for def: Dictionary in Content.get_lab_projects():  # a drill set learned by hand stays learned (S.4)
		if _is_drilled(def):
			research_done[def["id"]] = true
	invalidate_upgrade_cache()
	_apply_run_start_perks(false)  # perks (6.3): start with the 3×3, 10 Friends, ...
	buff = {}  # a glowing golden sticker isn't a buff: it stays and can still be clicked in the new run
	flow = {}
	offline_report = {}
	_tier_reached.clear()
	check_time_tiers(false)  # the new run's slow team doesn't pop "Sub-30" again... until it's really faster
	_helper_best.clear()
	check_helper_times(false)
	roll_collection_drop("championship")  # before the signal, so the screen rebuilt after it shows the new item
	championship_won.emit(gain)
	if persistence_enabled:
		save_game()
	return gain


## The moves multiplier from `count` unspent trophies (-1 = the ones owned now).
func get_trophy_mult(count: int = -1) -> float:
	return 1.0 + get_bonus_per_trophy() * float(trophies if count < 0 else count)


## Everything the Compete screen shows: trophies now / won / after, the bonus before and after, and the next trophy.
##   {run_solves, trophies, gain, after, mult_now, mult_after, next_at (run Solves for one more trophy), next_progress (0..1),
##    bonus_per_trophy, gain_mult (perks 6.3 × achievements 7.1a)}
func get_championship_preview() -> Dictionary:
	var run := get_run_solves()
	var gain_mult := get_trophy_gain_mult()
	var gain := trophies_for(run, gain_mult)
	var floor_at := solves_for_trophies(gain, gain_mult)
	var next_at := solves_for_trophies(gain + 1, gain_mult)
	return {
		"run_solves": run,
		"trophies": trophies,
		"gain": gain,
		"after": trophies + gain,
		"mult_now": get_trophy_mult(),
		"mult_after": get_trophy_mult(trophies + gain),
		"next_at": next_at,
		"next_progress": clampf((run - floor_at) / (next_at - floor_at), 0.0, 1.0),
		"bonus_per_trophy": get_bonus_per_trophy(),
		"gain_mult": gain_mult,
	}


# --- Trophy perks (task 6.3) -------------------------------------------------------

func has_perk(id: String) -> bool:
	return perks.has(id)


## A perk can be bought at all now (Content.PERKS `buyable`, default true; false while its system doesn't exist yet).
func is_perk_buyable_yet(id: String) -> bool:
	var def := Content.get_perk(id)
	return not def.is_empty() and bool(def.get("buyable", true))


## Every perk it needs is owned. A needed perk that can't be bought yet doesn't block it (owner, 2026-11-06: the
## Competition branch works before Competitions exist).
func are_perk_requirements_met(id: String) -> bool:
	for need: Variant in Content.get_perk(id).get("requires", []):
		if not perks.has(str(need)) and is_perk_buyable_yet(str(need)):
			return false
	return true


## "owned", "soon" (can't be bought yet), "locked" (a parent is missing), "available" (buyable; see can_buy_perk).
func get_perk_status(id: String) -> String:
	if perks.has(id):
		return "owned"
	if not is_perk_buyable_yet(id):
		return "soon"
	if not are_perk_requirements_met(id):
		return "locked"
	return "available"


func can_buy_perk(id: String) -> bool:
	return get_perk_status(id) == "available" and trophies >= int(Content.get_perk(id)["cost"])


## Spends trophies on a perk. Its effect counts at once; a run-start perk (the 3×3, 10 Friends) also applies to this run.
func buy_perk(id: String) -> bool:
	if not can_buy_perk(id):
		return false
	trophies -= int(Content.get_perk(id)["cost"])
	perks[id] = true
	invalidate_upgrade_cache()
	_apply_run_start_perks(true)
	var system := String(Content.get_perk(id).get("effect", {}).get("system", ""))
	if system.begins_with("auto_"):
		# a new auto-buyer starts switched on, except auto-Compete: it could end the run a second later, before the
		# player has set its target
		automation[system.trim_prefix("auto_")] = system != "auto_compete"
	purchased.emit("perk", id)
	return true


## Has an "unlock" perk opened this system ("automation", "competitions")?
func is_system_unlocked(system: String) -> bool:
	for id: String in perks:
		var effect: Dictionary = Content.get_perk(id).get("effect", {})
		if effect.get("type", "") == "unlock" and effect.get("system", "") == system:
			return true
	return false


# --- Auto-buyers (task 6.3b) --------------------------------------------------------

## Is this auto-buyer (Content.AUTOMATION kinds: helpers, upgrades, puzzles, compete) bought?
func is_auto_unlocked(kind: String) -> bool:
	return is_system_unlocked("auto_" + kind)


## Bought and switched on.
func is_auto_on(kind: String) -> bool:
	return is_auto_unlocked(kind) and bool(automation.get(kind, false))


## Switches an auto-buyer on or off (nothing happens for one that isn't bought).
func set_auto(kind: String, on: bool) -> void:
	if is_auto_unlocked(kind):
		automation[kind] = on


## The trophy gain auto-Compete waits for.
func get_auto_compete_at() -> int:
	return maxi(1, int(automation.get("compete_at", Content.AUTOMATION["compete_at_default"])))


func set_auto_compete_at(trophies_wanted: int) -> void:
	automation["compete_at"] = clampi(trophies_wanted, 1, 1000000000)


## One tick of the auto-buyers (from _process once a second; tests call it directly). Compete first (a new run makes
## buying now pointless), then the next puzzle, then upgrades (cheapest first, never a choice pair: picking a side
## stays the player's, 5.7b), then helpers (the cheapest one, again and again). Returns how many things it bought
## (a championship counts as one).
func run_automation() -> int:
	var bought := 0
	if automation_paused:
		return 0
	automation_running = true
	if is_auto_on("compete") and not auto_compete_held and get_pending_trophies() >= get_auto_compete_at() and compete() > 0:
		automation_running = false
		return 1
	if is_auto_on("puzzles"):
		var next := get_next_locked_puzzle()
		if can_unlock_puzzle(next) and unlock_puzzle(next):
			bought += 1
	if is_auto_on("upgrades"):
		var wanted: Array[Dictionary] = []
		for def: Dictionary in Content.get_upgrades():
			if String(def.get("choice_group", "")) == "" and is_upgrade_available(def["id"]):
				wanted.append(def)
		wanted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["cost"]) < float(b["cost"]))
		for def in wanted:
			if solves < float(def["cost"]):
				break
			if buy_upgrade(def["id"]):
				bought += 1
	if is_auto_on("helpers"):
		var reserve := get_auto_reserve()
		for i in int(Content.AUTOMATION["helper_buys_per_tick"]):
			var cheapest := _cheapest_helper()
			if cheapest == "" or solves - get_building_cost(cheapest) < reserve or not buy_building(cheapest):
				break
			bought += 1
	automation_running = false
	return bought


## Solves Team Manager leaves alone: the cost of the next puzzle (Puzzle Scout on) or the cheapest upgrade Shopping
## List would buy, if it's at most Content.AUTOMATION["save_seconds"] of helper income away; else 0.
func get_auto_reserve() -> float:
	var reserve := 0.0
	var reach := get_solves_per_second() * float(Content.AUTOMATION["save_seconds"])
	if is_auto_on("puzzles"):
		var next := get_next_locked_puzzle()
		if next != "" and get_puzzle_unlock_cost(next) - solves <= reach:
			reserve = maxf(reserve, get_puzzle_unlock_cost(next))
	if is_auto_on("upgrades"):
		var cheapest := INF
		for def: Dictionary in Content.get_upgrades():
			if String(def.get("choice_group", "")) == "" and is_upgrade_available(def["id"]):
				cheapest = minf(cheapest, float(def["cost"]))
		if cheapest < INF and cheapest - solves <= reach:
			reserve = maxf(reserve, cheapest)
	return reserve


## The shown helper with the lowest next-copy cost ("" if none is shown).
func _cheapest_helper() -> String:
	var best := ""
	var best_cost := INF
	for def: Dictionary in Content.BUILDINGS:
		if is_building_unlocked(def["id"]):
			var cost := get_building_cost(def["id"])
			if cost < best_cost:
				best = def["id"]
				best_cost = cost
	return best


# --- Career moments (task 7.0a) ---------------------------------------------------------

## Fires every Content.CAREER moment whose trigger is now true and that hasn't fired before, in data order. `emit` false
## marks them seen silently (an old save loading). While a save is being applied it does nothing (the UI isn't
## listening yet: e.g. research that finished while away fires at the first check after loading). Returns the ids fired.
func check_career(emit: bool = true) -> Array[String]:
	var fired: Array[String] = []
	if emit and _applying_save:
		return fired  # loading: nobody listens yet, so it stays unseen until the next check
	for def: Dictionary in Content.CAREER:
		var id: String = def["id"]
		if career_seen.has(id) or not is_career_trigger_met(def):
			continue
		career_seen[id] = true
		fired.append(id)
		if emit:
			career_moment.emit(id)
	return fired


## Is a career moment's trigger true right now (see Content.CAREER)?
func is_career_trigger_met(def: Dictionary) -> bool:
	var trigger: Dictionary = def.get("trigger", {})
	var id := String(trigger.get("id", ""))
	match String(trigger.get("type", "")):
		"lifetime_solves":
			return total_solves >= float(trigger.get("value", INF))
		"helper":
			return int(buildings.get(id, 0)) > 0
		"upgrade":
			return upgrades.has(id)
		"puzzle":
			return puzzles_reached.has(id)
		"method":
			return Content.get_method_index(method) >= Content.get_method_index(id) and Content.get_method_index(id) >= 0
		"championships":
			return championships >= int(trigger.get("value", 1))
		"hand_tier":
			return get_achievement_value({"type": "hand_tier"}) >= float(trigger.get("value", INF))
		"item_rarity":
			for item_id: String in collection:
				if String(Content.get_collection_item(item_id).get("rarity", "")) == id:
					return true
			return false
	return false


# --- Achievements (task 7.1a) ---------------------------------------------------------

## Earns every achievement (Content.get_achievements()) whose condition is now true and that isn't earned yet, in data
## order, and signals each. `emit` false earns them silently (an old save loading). Like check_career, it does nothing
## while a save is being applied (nobody listens yet): what was reached then is earned at the first check afterwards.
## Returns the ids earned.
func check_achievements(emit: bool = true) -> Array[String]:
	var earned: Array[String] = []
	if emit and _applying_save:
		return earned
	for def: Dictionary in Content.get_achievements():
		var id: String = def["id"]
		if achievements.has(id) or get_achievement_value(def) < float(def["value"]):
			continue
		achievements[id] = true
		earned.append(id)
	if emit:
		for id in earned:
			achievement_earned.emit(id)
			roll_collection_drop("achievement")  # an old save's backfill (emit false) drops nothing
	return earned


## Where an achievement's condition stands now, in the units of its `value` (a progress bar is value / def["value"]).
func get_achievement_value(def: Dictionary) -> float:
	var target := String(def.get("target", ""))
	match String(def.get("type", "")):
		"lifetime_solves":
			return total_solves
		"lifetime_moves":
			return total_moves
		"solves_per_second":
			return get_solves_per_second()
		"helper":
			return float(buildings.get(target, 0))
		"upgrades":
			return float(upgrades.size())
		"puzzle":
			return 1.0 if puzzles_reached.has(target) else 0.0
		"method":
			return 1.0 if Content.get_method_index(target) > 0 and is_method_learned(target) else 0.0
		"mastery":
			var best := 0
			for id: String in _mastery_levels:
				best = maxi(best, int(_mastery_levels[id]))
			return float(best)
		"championships":
			return float(championships)
		"perks":
			return float(perks.size())
		"hand_solves":
			var count := 0
			for id: String in solve_records:
				count += get_hand_solve_count(id)
			return float(count)
		"hand_tier":
			var tier := -1
			for id: String in solve_records:
				tier = maxi(tier, get_best_hand_tier(id))
			return float(tier)
		"drill_cases":
			var learned := 0
			for id: String in drills:
				if is_case_learned(id):
					learned += 1
			return float(learned)
		"drill_set":
			return 1.0 if is_drill_set_learned(target) else 0.0
		"research":
			return float(research_done.size())
		"tracks":
			return float(get_unlocked_track_ids().size())
		"taps", "golden_solved", "dailies", "time_played":
			return float(stats.get(String(def["type"]), 0.0))
	return -INF  # an unknown type is never earned


func is_achievement_earned(id: String) -> bool:
	return achievements.has(id)


## {earned, total}: the x/y of the achievements screen.
func get_achievement_progress() -> Dictionary:
	return {"earned": achievements.size(), "total": Content.get_achievements().size()}


## Trophy multiplier from achievements: +Content.ACHIEVEMENTS["bonus"] (1 %) more trophies per championship for each
## one earned, from the second championship on (owner, 2026-11-12: trophies, not moves, so the first run's pacing stays;
## counting it in the first championship too made competing worth it ~10 min sooner). Part of get_trophy_gain_mult.
func get_achievement_mult() -> float:
	if not has_won_championship():
		return 1.0
	return 1.0 + float(Content.ACHIEVEMENTS["bonus"]) * achievements.size()


# --- Stats (task 7.2a) ----------------------------------------------------------------

## Every counter starts here. All are lifetime (kept through championships) except `run_time`.
##   time_played: seconds with the game open · run_time: seconds this run took (open + time away as offline progress
##   counts it: capped like it, so a long break counts as the cap; a championship resets it) · run_untimed: 1 while the
##   run started before stats existed (v14 saves): its time isn't known, so it can't be the fastest ·
##   fastest_championship: the shortest run_time a championship ended (0 = none yet) · taps ·
##   best_solves_per_second (helpers', checked once a second) · puzzle_solves: puzzle id -> solves completed there ·
##   trophies_won (spent or not) · golden_solved (Golden Scrambles solved in time) · dailies (daily rewards earned)
static func _new_stats() -> Dictionary:
	return {"time_played": 0.0, "run_time": 0.0, "run_untimed": 0.0, "fastest_championship": 0.0, "taps": 0.0,
			"best_solves_per_second": 0.0,
			"puzzle_solves": {}, "trophies_won": 0.0, "golden_solved": 0.0, "dailies": 0.0}


## Time with the game open (from _process; never offline).
func update_play_time(delta: float) -> void:
	if delta <= 0.0:
		return
	stats["time_played"] = float(stats["time_played"]) + delta
	stats["run_time"] = float(stats["run_time"]) + delta


## Everything the Stats screen shows, read from the counters and the rest of the state:
##   the _new_stats() counters (puzzle_solves copied), plus lifetime_solves, lifetime_moves, run_solves, championships,
##   trophies (unspent), hand_solves, achievements_earned, achievements_total
func get_stats() -> Dictionary:
	var out: Dictionary = stats.duplicate(true)
	var progress := get_achievement_progress()
	out.merge({"lifetime_solves": total_solves, "lifetime_moves": total_moves, "run_solves": run_solves,
			"championships": championships, "trophies": trophies, "hand_solves": get_achievement_value({"type": "hand_solves"}),
			"achievements_earned": progress["earned"], "achievements_total": progress["total"]}, true)
	return out


## The saved counters; anything missing, unknown or damaged keeps its starting value.
func _load_stats(saved: Variant) -> void:
	stats = _new_stats()
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for key: String in stats:
		var value: Variant = (saved as Dictionary).get(key)
		if key == "puzzle_solves":
			if typeof(value) == TYPE_DICTIONARY:
				for id: Variant in value:
					if not Content.get_puzzle(str(id)).is_empty() and typeof(value[id]) in [TYPE_INT, TYPE_FLOAT]:
						stats["puzzle_solves"][str(id)] = maxf(0.0, float(value[id]))
		elif typeof(value) in [TYPE_INT, TYPE_FLOAT]:
			stats[key] = maxf(0.0, float(value))


# --- Cube Collection (task 7.3a) -------------------------------------------------------

## One try at a drop from `source` (Content.COLLECTION["sources"]): it drops with the source's chance, or surely once
## its pity is reached (the Nth try in a row). The item: a rarity by weight (or the pity rarity or better after a dry
## streak), then any item of it that can still grow; it gains a star (new: 1). Returns the item id, "" if nothing dropped.
func roll_collection_drop(source: String) -> String:
	var def: Dictionary = (Content.COLLECTION["sources"] as Dictionary).get(source, {})
	if def.is_empty() or (def.get("after_first_championship", false) and not has_won_championship()) \
			or (def.has("system") and not is_system_unlocked(String(def["system"]))):
		return ""  # no try: the pity doesn't move either
	var misses := int(collection_pity.get(source, 0))
	if misses + 1 < int(def["pity"]) and collection_rng.randf() >= float(def["chance"]):
		collection_pity[source] = misses + 1
		return ""
	var id := _pick_collection_item()
	if id == "":
		return ""  # everything is maxed: nothing to give
	collection_pity[source] = 0
	var got := Content.get_rarity_index(Content.get_collection_item(id)["rarity"])
	for pity: Dictionary in Content.COLLECTION["rarity_pity"]:
		var key := String(pity["key"])
		var floor_index := Content.get_rarity_index(String(pity["rarity"]))
		if got >= floor_index or not _can_grow_from(floor_index):  # nothing left up there: the pity has nothing to give
			collection_pity[key] = 0
		else:
			collection_pity[key] = int(collection_pity.get(key, 0)) + 1
	collection[id] = get_collection_stars(id) + 1
	_collection_stars += 1
	invalidate_upgrade_cache()
	auto_fill_kit()  # a better (or first) item of its kind goes into an auto slot
	collection_drop.emit(id, collection[id], source)
	return id


## Can an item of this rarity index or a rarer one still gain a star?
func _can_grow_from(rarity_index: int) -> bool:
	for item: Dictionary in Content.COLLECTION["items"]:
		if Content.get_rarity_index(String(item["rarity"])) >= rarity_index \
				and get_collection_stars(String(item["id"])) < int(Content.COLLECTION["max_stars"]):
			return true
	return false


## The item a drop gives: a rarity by weight (after a dry streak only the pity rarity or better can come), then a random
## item of it below max stars; if none of that rarity can grow, the nearest rarity that can (rarer first). "" if none.
func _pick_collection_item() -> String:
	var rarities: Array = Content.COLLECTION["rarities"]
	var floor_index := 0
	for pity: Dictionary in Content.COLLECTION["rarity_pity"]:  # the rarest pity that is due sets the floor
		if int(collection_pity.get(String(pity["key"]), 0)) >= int(pity["after"]):
			floor_index = maxi(floor_index, Content.get_rarity_index(String(pity["rarity"])))
	var total := 0.0
	for i in range(floor_index, rarities.size()):
		total += float(rarities[i]["weight"])
	var roll := collection_rng.randf() * total
	var chosen := rarities.size() - 1
	for i in range(floor_index, rarities.size()):
		roll -= float(rarities[i]["weight"])
		if roll < 0.0:
			chosen = i
			break
	var order: Array[int] = [chosen]
	for step in range(1, rarities.size()):
		for i: int in [chosen + step, chosen - step]:
			if i >= floor_index and i < rarities.size():
				order.append(i)
	for i in range(floor_index - 1, -1, -1):
		order.append(i)  # every rarer item is maxed: a lower one is still better than nothing
	for i in order:
		var candidates: Array[String] = []
		for item: Dictionary in Content.COLLECTION["items"]:
			if item["rarity"] == rarities[i]["id"] and get_collection_stars(item["id"]) < int(Content.COLLECTION["max_stars"]):
				candidates.append(item["id"])
		if not candidates.is_empty():
			return candidates[collection_rng.randi_range(0, candidates.size() - 1)]
	return ""


func get_collection_stars(id: String) -> int:
	return int(collection.get(id, 0))


func get_collection_stars_total() -> int:
	return _collection_stars


## An item's passive multiplier now: 1 + per_star × stars in the Comp Kit, 1 + owned_share of that out of it (7.4a),
## 1 if not owned.
func get_item_mult(id: String) -> float:
	var share := 1.0 if is_equipped(id) else float(Content.COMP_KIT["owned_share"])
	return 1.0 + Content.get_item_per_star(Content.get_collection_item(id)) * get_collection_stars(id) * share


# --- Competitions (task 8.3a, D19) -------------------------------------------------------

func _competition_clock() -> float:
	return competition_now if competition_now >= 0.0 else Time.get_unix_time_from_system()


## The team's rating on an event now: log10(1 + the puzzle's moves/s) (helpers' share, kit, mastery, trophies).
func get_competition_rating(puzzle_id: String) -> float:
	return log(1.0 + maxf(0.0, get_puzzle_moves_per_second(puzzle_id))) / log(10.0)


## "Your 3×3 average" if you registered now (seconds).
func get_competition_average(puzzle_id: String) -> float:
	return Content.competition_average(puzzle_id, get_competition_rating(puzzle_id))


## A tier is open once the one before it gave any medal (the first is open with the system).
func is_competition_tier_open(tier: String) -> bool:
	var index := Content.get_competition_tier_index(tier)
	if index < 0 or not is_system_unlocked("competitions"):
		return false
	if index == 0:
		return true
	var before := String(Content.COMPETITIONS["tiers"][index - 1]["id"])
	for key: String in competition_medals:
		if key.get_slice(":", 0) == before and int(competition_medals[key]) > 0:
			return true
	return false


func can_enter_competition(tier: String, puzzle_id: String) -> bool:
	return competition.is_empty() and is_competition_tier_open(tier) and is_puzzle_unlocked(puzzle_id) \
			and (Content.COMPETITIONS["events"] as Dictionary).has(puzzle_id)


## Registers: the competition starts now and runs for the tier's `seconds` of real time. `seed` -1 = a random one.
func enter_competition(tier: String, puzzle_id: String, seed_value: int = -1) -> bool:
	if not can_enter_competition(tier, puzzle_id):
		return false
	competition = {"tier": tier, "puzzle": puzzle_id, "started_at": _competition_clock(),
			"seed": seed_value if seed_value >= 0 else int(randi() % 1000000000),
			"rating": get_competition_rating(puzzle_id), "hand": {}}
	competition_result = {}
	competitions_entered += 1
	competition_started.emit(tier, puzzle_id)
	return true


## The round being played now (0-based), or the number of rounds once the time is up; -1 with no competition.
func get_competition_round() -> int:
	if competition.is_empty():
		return -1
	var tier := Content.get_competition_tier(String(competition["tier"]))
	var rounds := (tier["rounds"] as Array).size()
	var elapsed := _competition_clock() - float(competition["started_at"])
	return clampi(floori(elapsed / (float(tier["seconds"]) / rounds)), 0, rounds)


## Your own Solve Station solve as one attempt of the round being played (once a round; D19: it replaces the team's
## worst time if it's better, so it can only help). False if there's no round to take it (none running, you're out,
## or this round already has one).
func submit_competition_attempt(seconds: float) -> bool:
	if not can_submit_competition_attempt() or seconds <= 0.0 or is_inf(seconds) or is_nan(seconds):
		return false
	(competition["hand"] as Dictionary)[str(get_competition_round())] = seconds
	return true


func can_submit_competition_attempt() -> bool:
	if competition.is_empty():
		return false
	var index := get_competition_round()
	var tier := Content.get_competition_tier(String(competition["tier"]))
	if index >= (tier["rounds"] as Array).size() or (competition["hand"] as Dictionary).has(str(index)):
		return false
	var played := _competition_rounds(competition, index)  # the rounds before this one: still in?
	return played.is_empty() or bool(played.back()["you_advance"])


## A WCA average: the mean without the best and the worst attempt.
static func competition_mean(times: Array) -> float:
	var sorted := times.duplicate()
	sorted.sort()
	if sorted.size() <= 2:
		return float(sorted[0]) if not sorted.is_empty() else INF
	var total := 0.0
	for i in range(1, sorted.size() - 1):
		total += float(sorted[i])
	return total / (sorted.size() - 2)


## The entrants of a competition, from its seed: [{name, rating, you}], you first. Rival names are unique.
static func competition_entrants(comp: Dictionary) -> Array[Dictionary]:
	var tier := Content.get_competition_tier(String(comp["tier"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(comp["seed"])
	var people: Array = Content.NEWS["people"]
	var out: Array[Dictionary] = [{"name": "You", "rating": float(comp["rating"]), "you": true}]
	var used := {}
	while out.size() < int(tier["field"]):
		var name := "%s %s." % [people[rng.randi_range(0, people.size() - 1)], char(65 + rng.randi_range(0, 25))]
		if used.has(name):
			continue
		used[name] = true
		out.append({"name": name, "you": false,
				"rating": maxf(0.0, float(tier["rating"]) + rng.randfn(0.0, float(Content.COMPETITIONS["rival_spread"])))})
	return out


## (Results read Content's tiers, events and name pool live: editing those changes a competition already running.)
## The first `count` rounds of a competition, worked out from its seed (the same every time): each
## {name, advance (0 = the final), results: [{name, you, times, average, single, place, hand}] best first, you_in,
## you_place, you_advance}. Only entrants still in play a round; a round you're out of has you_in false.
func _competition_rounds(comp: Dictionary, count: int) -> Array[Dictionary]:
	var tier := Content.get_competition_tier(String(comp["tier"]))
	var cuts: Array = tier["rounds"]
	var entrants := competition_entrants(comp)
	var alive: Array[int] = []
	for i in entrants.size():
		alive.append(i)
	var names: Array = Content.COMPETITIONS["round_names"]
	var out: Array[Dictionary] = []
	for r in mini(count, cuts.size()):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(comp["seed"]) * 31 + r + 1
		var all_times: Array = []  # every entrant draws, in or out, so a round's times never depend on who advanced
		for i in entrants.size():
			var average := Content.competition_average(String(comp["puzzle"]), float(entrants[i]["rating"]))
			var times: Array[float] = []
			for a in int(Content.COMPETITIONS["attempts"]):
				times.append(average * exp(rng.randfn(0.0, float(Content.COMPETITIONS["attempt_noise"]))))
			all_times.append(times)
		var results: Array[Dictionary] = []
		for i in alive:
			var times: Array = (all_times[i] as Array).duplicate()
			var hand := false
			if entrants[i]["you"] and (comp.get("hand", {}) as Dictionary).has(str(r)):
				var worst := 0
				for a in times.size():
					if float(times[a]) > float(times[worst]):
						worst = a
				if float(comp["hand"][str(r)]) < float(times[worst]):
					times[worst] = float(comp["hand"][str(r)])
					hand = true
			results.append({"index": i, "name": entrants[i]["name"], "you": entrants[i]["you"], "times": times,
					"average": competition_mean(times), "single": float(times.min()), "hand": hand})
		results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["average"] != b["average"]:
				return float(a["average"]) < float(b["average"])
			if a["single"] != b["single"]:
				return float(a["single"]) < float(b["single"])
			return int(a["index"]) < int(b["index"]))
		var advance := int(cuts[r])
		var you_place := 0
		alive = []
		for place in results.size():
			results[place]["place"] = place + 1
			if results[place]["you"]:
				you_place = place + 1
			if place < advance:
				alive.append(int(results[place]["index"]))
		# "Final" last; with three rounds or more the one before it is the "Semi-final"; else "First round", "Second round"
		var name := String(names[r]) if r < 2 else "Round %d" % (r + 1)
		if r == cuts.size() - 1:
			name = String(names[3])
		elif r == cuts.size() - 2 and cuts.size() >= 3:
			name = String(names[2])
		out.append({"name": name, "advance": advance, "results": results, "you_in": you_place > 0, "you_place": you_place,
				"you_advance": you_place > 0 and you_place <= advance})
	return out


## Everything the Competitions screen shows about the one running ({} if none): {tier, puzzle, seconds, left,
## round (being played; = rounds.size() of the tier once over), round_left, rounds (the finished ones, see
## _competition_rounds), out (you were cut), can_attempt, average (your expected average), field}.
func get_competition_view() -> Dictionary:
	if competition.is_empty():
		return {}
	var tier := Content.get_competition_tier(String(competition["tier"]))
	var total := (tier["rounds"] as Array).size()
	var elapsed := _competition_clock() - float(competition["started_at"])
	var index := get_competition_round()
	var done := _competition_rounds(competition, index)
	var per_round := float(tier["seconds"]) / total
	return {"tier": competition["tier"], "puzzle": competition["puzzle"], "seconds": float(tier["seconds"]),
			"left": maxf(0.0, float(tier["seconds"]) - elapsed), "round": index,
			"round_left": maxf(0.0, per_round * (index + 1) - elapsed) if index < total else 0.0, "rounds": done,
			"out": not done.is_empty() and not bool(done.back()["you_in"] and (done.back()["you_advance"] or done.size() == total)),
			"can_attempt": can_submit_competition_attempt(), "field": int(tier["field"]),
			"average": Content.competition_average(String(competition["puzzle"]), float(competition["rating"]))}


## Ends the running competition once its time is up, or once the round that cut you is over (so you can come back
## sooner). From _process once a second (the real clock: time away counts in full); tests call it.
func update_competition() -> void:
	if competition.is_empty():
		return
	var tier := Content.get_competition_tier(String(competition["tier"]))
	if tier.is_empty():
		competition = {}
		return
	if float(competition["started_at"]) > _competition_clock():
		competition["started_at"] = _competition_clock()  # the PC's clock went back: it never waits longer than its length
	var total := (tier["rounds"] as Array).size()
	var rounds_over := get_competition_round()
	if rounds_over == 0:
		return  # no round over yet: nothing to work out
	var done := _competition_rounds(competition, rounds_over)
	var last: Dictionary = done.back()
	var cut := false
	for played: Dictionary in done:
		if played["you_in"] and not played["you_advance"] and int(played["advance"]) > 0:
			last = played
			cut = true
			break
	if cut or done.size() == total:
		_finish_competition(last, done.find(last) + 1)


## Medal, bonus, records, a drop; stores the result and signals it.
func _finish_competition(last: Dictionary, rounds_played: int) -> void:
	var puzzle := String(competition["puzzle"])
	var tier := String(competition["tier"])
	var mine: Dictionary = {}
	for row: Dictionary in last["results"]:
		if row["you"]:
			mine = row
	var is_final := int(last["advance"]) == 0
	var place := int(last["you_place"])
	var medals: Array = Content.COMPETITIONS["medals"]
	var points := maxi(0, medals.size() + 1 - place) if is_final else 0  # 1st 3, 2nd 2, 3rd 1
	var key := "%s:%s" % [tier, puzzle]
	var improved := points > int(competition_medals.get(key, 0))
	if improved:
		competition_medals[key] = points
		invalidate_upgrade_cache()
	# Official records: the best single and average of every round played.
	var record: Dictionary = competition_records.get(puzzle, {})
	var best_single := INF
	var best_average := INF
	for played: Dictionary in _competition_rounds(competition, rounds_played):
		for row: Dictionary in played["results"]:
			if row["you"]:
				best_single = minf(best_single, float(row["single"]))
				best_average = minf(best_average, float(row["average"]))
	var pb_single := best_single < float(record.get("single", INF))
	var pb_average := best_average < float(record.get("average", INF))
	competition_records[puzzle] = {"single": minf(best_single, float(record.get("single", INF))),
			"average": minf(best_average, float(record.get("average", INF)))}
	competition_result = {"tier": tier, "puzzle": puzzle, "place": place, "field": int(Content.get_competition_tier(tier)["field"]),
			"final": is_final, "round": String(last["name"]), "medal": String(medals[points - 1]) if points > 0 else "",
			"points": points, "improved": improved, "average": float(mine.get("average", INF)),
			"single": float(mine.get("single", INF)), "pb_single": pb_single, "pb_average": pb_average, "drop": ""}
	competition = {}
	if points > 0:
		competition_result["drop"] = roll_collection_drop("competition")
	competition_finished.emit(competition_result)


## The last finished competition ({} if none, or once dismissed).
func get_competition_result() -> Dictionary:
	return competition_result


func clear_competition_result() -> void:
	competition_result = {}


## Medal points: every tier-and-event's best medal (bronze 1, silver 2, gold 3) × its tier's weight.
func get_medal_points() -> int:
	var points := 0
	for key: String in competition_medals:
		points += int(competition_medals[key]) * int(Content.get_competition_tier(key.get_slice(":", 0)).get("weight", 0))
	return points


## All moves × this, for good: 1 + bonus_per_point × medal points.
func get_medal_mult() -> float:
	return 1.0 + float(Content.COMPETITIONS["bonus_per_point"]) * get_medal_points()


## The best medal at a tier and event: "" | "bronze" | "silver" | "gold".
func get_competition_medal(tier: String, puzzle_id: String) -> String:
	var points := int(competition_medals.get("%s:%s" % [tier, puzzle_id], 0))
	return String(Content.COMPETITIONS["medals"][points - 1]) if points > 0 else ""


func _load_competitions(saved: Variant) -> void:
	competition = {}
	competition_medals.clear()
	competition_records.clear()
	competition_result = {}
	competitions_entered = 0
	if typeof(saved) != TYPE_DICTIONARY:
		return
	var data: Dictionary = saved
	var events: Dictionary = Content.COMPETITIONS["events"]
	var medals: Variant = data.get("medals", {})
	if typeof(medals) == TYPE_DICTIONARY:
		for key: Variant in medals:
			var parts := str(key).split(":")
			if parts.size() == 2 and not Content.get_competition_tier(parts[0]).is_empty() and events.has(parts[1]) \
					and typeof(medals[key]) in [TYPE_INT, TYPE_FLOAT]:
				var points := clampi(int(medals[key]), 0, (Content.COMPETITIONS["medals"] as Array).size())
				if points > 0:
					competition_medals[str(key)] = points
	var records: Variant = data.get("records", {})
	if typeof(records) == TYPE_DICTIONARY:
		for id: Variant in records:
			var entry: Variant = records[id]
			if events.has(str(id)) and typeof(entry) == TYPE_DICTIONARY:
				var single: Variant = (entry as Dictionary).get("single")
				var average: Variant = (entry as Dictionary).get("average")
				if typeof(single) in [TYPE_INT, TYPE_FLOAT] and typeof(average) in [TYPE_INT, TYPE_FLOAT] \
						and float(single) > 0.0 and float(average) > 0.0:
					competition_records[str(id)] = {"single": float(single), "average": float(average)}
	if typeof(data.get("entered")) in [TYPE_INT, TYPE_FLOAT]:
		competitions_entered = maxi(0, int(data["entered"]))
	var active: Variant = data.get("active", {})
	if typeof(active) == TYPE_DICTIONARY and not Content.get_competition_tier(str((active as Dictionary).get("tier", ""))).is_empty() \
			and events.has(str((active as Dictionary).get("puzzle", ""))) \
			and typeof((active as Dictionary).get("started_at")) in [TYPE_INT, TYPE_FLOAT] \
			and typeof((active as Dictionary).get("seed")) in [TYPE_INT, TYPE_FLOAT] \
			and typeof((active as Dictionary).get("rating")) in [TYPE_INT, TYPE_FLOAT]:
		var hand := {}
		var saved_hand: Variant = (active as Dictionary).get("hand", {})
		if typeof(saved_hand) == TYPE_DICTIONARY:
			for r: Variant in saved_hand:
				if str(r).is_valid_int() and typeof(saved_hand[r]) in [TYPE_INT, TYPE_FLOAT] and float(saved_hand[r]) > 0.0:
					hand[str(r)] = float(saved_hand[r])
		competition = {"tier": str(active["tier"]), "puzzle": str(active["puzzle"]), "started_at": float(active["started_at"]),
				"seed": int(active["seed"]), "rating": maxf(0.0, float(active["rating"])), "hand": hand}
	competition_result = _clean_competition_result(data.get("last", {}))


## A saved result, rebuilt key by key with the right types; {} unless every key is there and makes sense.
func _clean_competition_result(saved: Variant) -> Dictionary:
	if typeof(saved) != TYPE_DICTIONARY:
		return {}
	var last: Dictionary = saved
	var numbers := [TYPE_INT, TYPE_FLOAT]
	for key: String in ["place", "field", "points", "average", "single"]:
		if not typeof(last.get(key)) in numbers:
			return {}
	for key: String in ["final", "improved", "pb_single", "pb_average"]:
		if typeof(last.get(key)) != TYPE_BOOL:
			return {}
	for key: String in ["tier", "puzzle", "round", "medal", "drop"]:
		if typeof(last.get(key)) != TYPE_STRING:
			return {}
	var medals: Array = Content.COMPETITIONS["medals"]
	var points := clampi(int(last["points"]), 0, medals.size())
	if Content.get_competition_tier(String(last["tier"])).is_empty() \
			or not (Content.COMPETITIONS["events"] as Dictionary).has(String(last["puzzle"])) or int(last["place"]) < 1:
		return {}
	var drop := String(last["drop"])
	return {"tier": String(last["tier"]), "puzzle": String(last["puzzle"]), "place": int(last["place"]),
			"field": maxi(1, int(last["field"])), "final": bool(last["final"]), "round": String(last["round"]),
			"medal": String(medals[points - 1]) if points > 0 else "", "points": points, "improved": bool(last["improved"]),
			"average": float(last["average"]), "single": float(last["single"]), "pb_single": bool(last["pb_single"]),
			"pb_average": bool(last["pb_average"]), "drop": drop if not Content.get_collection_item(drop).is_empty() else ""}


# --- Comp Kit (task 7.4a) --------------------------------------------------------------

func is_equipped(id: String) -> bool:
	return kit.values().has(id)


## slot id -> item id (a copy; empty slots are absent).
func get_kit() -> Dictionary:
	return kit.duplicate()


func is_slot_manual(slot: String) -> bool:
	return kit_manual.has(slot)


## Puts an owned item of the slot's kind in a slot ("" empties it); the slot stops filling itself. An item already in
## another slot (a cube in Main and Backup) swaps places with what was here. Returns false (no change) if it can't.
func equip(slot: String, item_id: String) -> bool:
	var slot_def := Content.get_kit_slot(slot)
	if slot_def.is_empty():
		return false
	if item_id != "":
		var item := Content.get_collection_item(item_id)
		if item.is_empty() or item["kind"] != slot_def["kind"] or get_collection_stars(item_id) <= 0:
			return false
		for other: String in kit.keys():
			if other != slot and kit[other] == item_id:
				if kit.has(slot):  # a real swap: both slots are the player's choice now
					kit[other] = kit[slot]
					kit_manual[other] = true
				else:  # a move into an empty slot: the old one keeps its mode (an auto slot refills below)
					kit.erase(other)
		kit[slot] = item_id
	else:
		kit.erase(slot)
	kit_manual[slot] = true
	auto_fill_kit(false)
	invalidate_upgrade_cache()
	kit_changed.emit()
	return true


## Lets a slot fill itself again (with the best item of its kind).
func set_slot_auto(slot: String) -> void:
	if Content.get_kit_slot(slot).is_empty():
		return
	kit_manual.erase(slot)
	auto_fill_kit(false)
	kit_changed.emit()


## Fills every slot the player hasn't chosen with the best owned item of its kind not in another slot: the highest
## per_star × stars, then the rarer, then data order. Signals kit_changed (if `emit`) when something moved.
func auto_fill_kit(emit: bool = true) -> void:
	var used := {}
	for slot: String in kit_manual:
		if kit.has(slot):
			used[kit[slot]] = true
	var changed := false
	for slot_def: Dictionary in Content.COMP_KIT["slots"]:
		var slot: String = slot_def["id"]
		if kit_manual.has(slot):
			continue
		var best := ""
		var best_value := 0.0
		var best_rarity := -1
		for item: Dictionary in Content.COLLECTION["items"]:
			var id: String = item["id"]
			if item["kind"] != slot_def["kind"] or get_collection_stars(id) <= 0 or used.has(id):
				continue
			var value := Content.get_item_per_star(item) * get_collection_stars(id)
			var rarity := Content.get_rarity_index(item["rarity"])
			if value > best_value + 1e-9 or (absf(value - best_value) <= 1e-9 and rarity > best_rarity):
				best = id
				best_value = value
				best_rarity = rarity
		if String(kit.get(slot, "")) != best:
			changed = true
			if best == "":
				kit.erase(slot)
			else:
				kit[slot] = best
		if best != "":
			used[best] = true
	if changed:
		invalidate_upgrade_cache()
		if emit:
			kit_changed.emit()


## brand -> items of that brand in the kit.
func get_kit_brand_counts() -> Dictionary:
	var counts := {}
	for slot: String in kit:
		var brand := String(Content.get_collection_item(kit[slot]).get("brand", ""))
		counts[brand] = int(counts.get(brand, 0)) + 1
	return counts


## The Content.COMP_KIT sets active now: for each brand only its biggest tier reached.
func get_active_kit_sets() -> Array[Dictionary]:
	var counts := get_kit_brand_counts()
	var best := {}
	for def: Dictionary in Content.COMP_KIT["sets"]:
		var brand: String = def["brand"]
		if int(counts.get(brand, 0)) >= int(def["pieces"]) and int(def["pieces"]) > int(best.get(brand, {}).get("pieces", 0)):
			best[brand] = def
	var out: Array[Dictionary] = []
	for def: Dictionary in Content.COMP_KIT["sets"]:
		if best.values().has(def):
			out.append(def)
	return out


func _load_kit(saved: Variant) -> void:
	kit.clear()
	kit_manual.clear()
	if typeof(saved) == TYPE_DICTIONARY:
		var slots: Variant = (saved as Dictionary).get("slots", {})
		var used := {}
		if typeof(slots) == TYPE_DICTIONARY:
			for slot_def: Dictionary in Content.COMP_KIT["slots"]:
				var id := str((slots as Dictionary).get(slot_def["id"], ""))
				var item := Content.get_collection_item(id)
				if not item.is_empty() and item["kind"] == slot_def["kind"] and get_collection_stars(id) > 0 and not used.has(id):
					kit[slot_def["id"]] = id
					used[id] = true
		var manual: Variant = (saved as Dictionary).get("manual", [])
		if typeof(manual) == TYPE_ARRAY:
			for slot: Variant in manual:
				if not Content.get_kit_slot(str(slot)).is_empty():
					kit_manual[str(slot)] = true
	auto_fill_kit(false)  # slots on auto take the best now (also a v16 save's first kit)
	invalidate_upgrade_cache()


## Where the bonuses from the Goals systems come from (7.12), one row per source, each {id, effects: {key: mult}}:
## "kit" (items in the Comp Kit, full), "collection" (the rest, their share), "sets" (brand sets active), "trophies"
## (unspent trophies: all moves), "achievements" (trophies per championship). An effect key is the effect type, or
## "puzzle_mult:<puzzle>" for a cube. A row's mult for a key is the product of its parts, as GameState applies them.
func get_bonus_breakdown() -> Array[Dictionary]:
	var kit_effects := {}
	var rest_effects := {}
	for id: String in collection:
		var item := Content.get_collection_item(id)
		var effect: Dictionary = item.get("effect", {})
		var keys: Array[String] = []
		if effect.get("type", "") == "puzzle_mult":
			for puzzle: Variant in effect.get("puzzles", []):
				keys.append("puzzle_mult:%s" % puzzle)
		else:
			keys.append(String(effect.get("type", "")))
		var target: Dictionary = kit_effects if is_equipped(id) else rest_effects
		for key in keys:
			target[key] = float(target.get(key, 1.0)) * get_item_mult(id)
	var set_effects := {}
	for def: Dictionary in get_active_kit_sets():
		var key := String(def["effect"]["type"])
		set_effects[key] = float(set_effects.get(key, 1.0)) * float(def["effect"]["value"])
	return [
		{"id": "kit", "effects": kit_effects},
		{"id": "collection", "effects": rest_effects},
		{"id": "sets", "effects": set_effects},
		{"id": "trophies", "effects": {"global_mult": get_trophy_mult()} if trophies > 0 else {}},
		{"id": "achievements", "effects": {"trophy_gain_mult": get_achievement_mult()} if get_achievement_mult() > 1.0 else {}},
		{"id": "perks", "effects": _perk_mult_effects()},
		{"id": "medals", "effects": {"global_mult": get_medal_mult()} if get_medal_points() > 0 else {}},
	]


## The trophy perks' multiplying effects (types ending in "_mult"), each the product of the perks owned.
func _perk_mult_effects() -> Dictionary:
	var out := {}
	for id: String in perks:
		var effect: Dictionary = Content.get_perk(id).get("effect", {})
		var type := String(effect.get("type", ""))
		if type.ends_with("_mult"):
			var key := type if type != "building_mult" else "building_mult:%s" % effect.get("target", "")
			out[key] = float(out.get(key, 1.0)) * float(effect.get("value", 1.0))
	return out


## {owned, total, stars, max_stars}: the Collection screen's counts.
func get_collection_progress() -> Dictionary:
	var items: Array = Content.COLLECTION["items"]
	return {"owned": collection.size(), "total": items.size(), "stars": get_collection_stars_total(),
			"max_stars": items.size() * int(Content.COLLECTION["max_stars"])}


## The pity counters' keys for rarities (Content.COLLECTION["rarity_pity"]): "rarity" (Epic), "legendary".
static func rarity_pity_keys() -> Array[String]:
	var keys: Array[String] = []
	for pity: Dictionary in Content.COLLECTION["rarity_pity"]:
		keys.append(String(pity["key"]))
	return keys


## Drop odds for the screen (7.5): per source {chance, pity, misses, after_first_championship, open}, and per rarity
## pity {rarity, after, count}: everything the Collection tab says about how drops work.
func get_drop_odds() -> Dictionary:
	var sources := {}
	for source: String in Content.COLLECTION["sources"]:
		var def: Dictionary = Content.COLLECTION["sources"][source]
		if def.has("system") and not is_system_unlocked(String(def["system"])):
			continue  # a source of a system the player doesn't have yet isn't listed
		sources[source] = {"chance": float(def["chance"]), "pity": int(def["pity"]),
				"misses": int(collection_pity.get(source, 0)),
				"after_first_championship": bool(def.get("after_first_championship", false)),
				"open": not def.get("after_first_championship", false) or has_won_championship()}
	var rarities: Array[Dictionary] = []
	for pity: Dictionary in Content.COLLECTION["rarity_pity"]:
		rarities.append({"rarity": String(pity["rarity"]), "after": int(pity["after"]),
				"count": int(collection_pity.get(String(pity["key"]), 0))})
	return {"sources": sources, "rarities": rarities}


func _load_collection(saved: Variant) -> void:
	collection.clear()
	collection_pity.clear()
	_collection_stars = 0
	if typeof(saved) != TYPE_DICTIONARY:
		_prune_kit()
		return
	var items: Variant = (saved as Dictionary).get("items", {})
	if typeof(items) == TYPE_DICTIONARY:
		for id: Variant in items:
			if not Content.get_collection_item(str(id)).is_empty() and typeof(items[id]) in [TYPE_INT, TYPE_FLOAT]:
				var stars := clampi(int(items[id]), 0, int(Content.COLLECTION["max_stars"]))
				if stars > 0:
					collection[str(id)] = stars
					_collection_stars += stars
	var pity: Variant = (saved as Dictionary).get("pity", {})
	if typeof(pity) == TYPE_DICTIONARY:
		for key: Variant in pity:
			if (rarity_pity_keys().has(str(key)) or (Content.COLLECTION["sources"] as Dictionary).has(str(key))) \
					and typeof(pity[key]) in [TYPE_INT, TYPE_FLOAT]:
				collection_pity[str(key)] = maxi(0, int(pity[key]))
	_prune_kit()


## The kit holds only owned items (7.4a): drops the others, then lets auto slots refill.
func _prune_kit() -> void:
	for slot: String in kit.keys():
		if get_collection_stars(kit[slot]) <= 0:
			kit.erase(slot)
	auto_fill_kit(false)
	invalidate_upgrade_cache()


## How long offline progress (and the Lab's time away) can run: 8 h plus "offline_hours" perks.
func get_offline_cap_seconds() -> float:
	return MAX_OFFLINE_SECONDS + _perk_sum("offline_hours") * 3600.0


## The run-start perks, for a run that's starting (compete) or already running (a perk just bought): owned "start_puzzle"
## puzzles get unlocked for free (in ladder order; the newest gets the focus and the whole split, like unlock_puzzle),
## and "start_helpers" tops a helper up to its count. `emit`: tell the UI about new puzzles (not during compete, which
## rebuilds the whole screen).
func _apply_run_start_perks(emit: bool) -> void:
	var added: Array[String] = []
	for def: Dictionary in Content.PUZZLES:
		var id: String = def["id"]
		if _perk_starts_with_puzzle(id) and not unlocked_puzzles.has(id) and get_next_locked_puzzle() == id:
			_add_puzzle(id)
			added.append(id)
	if not added.is_empty():
		set_split_preset("newest")
		focused_puzzle = unlocked_puzzles.back()
	for perk_id: String in perks:
		var effect: Dictionary = Content.get_perk(perk_id).get("effect", {})
		if effect.get("type", "") == "start_helpers" and buildings.has(effect.get("target", "")):
			buildings[effect["target"]] = maxi(int(buildings[effect["target"]]), int(effect.get("value", 0)))
	if emit and not added.is_empty():
		focus_changed.emit(focused_puzzle)
		for id in added:
			puzzle_unlocked.emit(id)


func _perk_starts_with_puzzle(puzzle_id: String) -> bool:
	for id: String in perks:
		var effect: Dictionary = Content.get_perk(id).get("effect", {})
		if effect.get("type", "") == "start_puzzle" and effect.get("puzzle", "") == puzzle_id:
			return true
	return false


## Sum of the owned perks' values for one effect type. Cached with the upgrade multipliers (it's read on every move).
func _perk_sum(effect_type: String) -> float:
	var key := "perk_sum|" + effect_type
	if _mult_cache_key() == _mult_cache_owned and _mult_cache.has(key):
		return _mult_cache[key]
	var total := 0.0
	for id: String in perks:
		var effect: Dictionary = Content.get_perk(id).get("effect", {})
		if effect.get("type", "") == effect_type:
			total += float(effect.get("value", 0.0))
	_store_cached(key, total)
	return total


func _perk_product(effect_type: String) -> float:
	var key := "perk_product|" + effect_type
	if _mult_cache_key() == _mult_cache_owned and _mult_cache.has(key):
		return _mult_cache[key]
	var total := 1.0
	for id: String in perks:
		var effect: Dictionary = Content.get_perk(id).get("effect", {})
		if effect.get("type", "") == effect_type:
			total *= float(effect.get("value", 1.0))
	_store_cached(key, total)
	return total


## Puts a value in the upgrade cache, first dropping the cache if it was built for another set of owned things.
func _store_cached(key: String, value: float) -> void:
	if _mult_cache_key() != _mult_cache_owned:
		_mult_cache.clear()
		_mult_cache_owned = _mult_cache_key()
	_mult_cache[key] = value


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
	puzzles_reached[puzzle_id] = true
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


## Moves on a puzzle are multiplied by its level bonus, its "moves" milestones, every "all_moves" milestone (from any
## puzzle with mastery, unlocked this run or not: mastery is kept through a championship, 6.2), its hand-solve tier,
## specialist upgrades ("puzzle_mult", 5.7b) and unspent trophies (Phase 6).
func get_puzzle_moves_mult(puzzle_id: String) -> float:
	var per_level := 1.0 + float(Content.MASTERY["per_level_moves"]) * (get_mastery_level(puzzle_id) - 1)
	var everywhere := 1.0
	for id: String in _mastery_levels:
		everywhere *= _milestone_mult(id, "all_moves")
	return per_level * _milestone_mult(puzzle_id, "moves") * everywhere * get_hand_tier_mult(puzzle_id) \
			* _upgrade_mult("puzzle_mult", puzzle_id) * get_trophy_mult() * get_medal_mult()


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
	var ids: Array[String] = []
	for def: Dictionary in Content.TRACKS:
		if def["file"] != "" and is_track_unlock_reached(def["unlock"]):
			ids.append(def["id"])
	return ids


## A track's `unlock` is a puzzle ever unlocked (music stays through a championship) or "championship" (the first win).
func is_track_unlock_reached(unlock: String) -> bool:
	return has_won_championship() if unlock == "championship" else puzzles_reached.has(unlock) or unlocked_puzzles.has(unlock)


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
		candidates.append({"kind": "upgrade", "id": def["id"], "name": _goal_name(def), "cost": float(def["cost"]), "more": false})
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
		run_solves += reward
		today["rewarded"] = true
		stats["dailies"] = float(stats["dailies"]) + 1.0
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
			golden_case = {}
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
	golden_case = roll_golden_case()
	golden_attempt_left = float(Content.GOLDEN["case_seconds"] if golden_case["kind"] != "scramble" else Content.GOLDEN["solve_seconds"])
	return true


## What the next golden sticker opens (Content.GOLDEN["kinds"], 7.13): a short scramble, or a real OLL/PLL case on the
## 3×3 (any case, D18), once the player has a 3×3. A case learned in the drills is `known` (it pays more).
func roll_golden_case() -> Dictionary:
	var kinds: Array = []
	var total := 0.0
	for def: Dictionary in Content.GOLDEN["kinds"]:
		if def["id"] != "scramble" and not is_puzzle_unlocked("3x3"):
			continue
		kinds.append(def)
		total += float(def["weight"])
	var pick := golden_rng.randf() * total
	var chosen: Dictionary = kinds.back()
	for def: Dictionary in kinds:
		pick -= float(def["weight"])
		if pick <= 0.0:
			chosen = def
			break
	if chosen["id"] == "scramble":
		return {"kind": "scramble", "moves": roll_golden_case_moves()}
	var cases := Content.get_drill_cases(String(chosen["set"]))
	var alg: Dictionary = cases[golden_rng.randi_range(0, cases.size() - 1)]
	return {"kind": String(chosen["id"]), "case_id": String(alg["id"]), "alg": String(alg["alg"]),
			"name": String(alg.get("name", alg["id"])), "known": is_case_learned(String(alg["id"]))}


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
	var known := bool(golden_case.get("known", false))
	golden_case = {}
	if not success:
		golden_finished.emit(false, {})
		return {}
	var result := _apply_golden_buff(_roll_golden_buff(), float(Content.GOLDEN["known_bonus"]) if known else 1.0)
	if known:
		result["known"] = true
		result["text"] = "You knew this one! " + String(result["text"])
	stats["golden_solved"] = float(stats["golden_solved"]) + 1.0
	golden_finished.emit(true, result)
	roll_collection_drop("golden")
	return result


## ×N on every move while a Frenzy runs (not during offline catch-up), else 1.
func get_buff_mult() -> float:
	if buff.is_empty() or _offline_catch_up:
		return 1.0
	return float(buff.get("mult", 1.0))


## Applies a buff from Content.GOLDEN["buffs"] (tests call it with a chosen one).
## `scale` (7.13: a known golden case) makes it longer (Frenzy) or bigger (Lucky).
func _apply_golden_buff(def: Dictionary, scale: float = 1.0) -> Dictionary:
	match String(def.get("id", "")):
		"frenzy":
			var seconds := float(def["seconds"]) * scale
			buff = {"id": "frenzy", "mult": float(def["mult"]), "left": seconds}
			return {"id": "frenzy", "name": def["name"], "mult": float(def["mult"]), "seconds": seconds,
					"text": "%s: ×%s moves for %ds" % [def["name"], Num.format(float(def["mult"])), int(seconds)]}
		"lucky":
			var minutes := float(def["minutes"]) * scale
			var amount := maxf(get_solves_per_second() * minutes * 60.0,
					float(def["min_solves_value"]) * get_solve_value(focused_puzzle) * scale)
			solves += amount
			total_solves += amount
			run_solves += amount
			return {"id": "lucky", "name": def["name"], "solves": amount,
					"text": "%s: +%s Solves (%s minutes' worth)" % [def["name"], Num.format(amount), str(snappedf(minutes, 0.1))]}
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
			add.call(cost_goal.call("upgrade", def["id"], _goal_name(def), float(def["cost"]), false))
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
	goals = goals.slice(0, limit)
	# 7.10: an achievement at ACHIEVEMENT_GOAL_AT or more joins: in its place by time when that can be told, else in the
	# last slot (from a 3-goal strip on), unless that slot holds something ready now (it gives way to that).
	var near := get_near_achievement_goal() if limit >= 3 else {}
	if not near.is_empty():
		if not is_inf(float(near["seconds"])):
			goals.append(near)
			goals.sort_custom(_goal_before)
			goals = goals.slice(0, limit)
		elif goals.size() < limit:
			goals.append(near)
		elif float(goals[limit - 1]["seconds"]) > 0.0:
			goals[limit - 1] = near
	return goals


const ACHIEVEMENT_GOAL_AT := 0.8  ## an achievement this far along can be a goal (7.10)

## The unearned achievement closest to done, as a goal ({} if none is at ACHIEVEMENT_GOAL_AT yet). Only ones with a
## count (not "unlock the 4×4"); unit "progress", `progress` 0..1; seconds from the rate where the game knows it.
func get_near_achievement_goal() -> Dictionary:
	var best: Dictionary = {}
	var best_fraction := ACHIEVEMENT_GOAL_AT
	for def: Dictionary in Content.get_achievements():
		var target := float(def["value"])
		if achievements.has(def["id"]) or target <= 1.0 or String(def["type"]) in ["hand_tier", "mastery"]:
			continue  # done-or-not ones (and tiers/levels: their bar would mislead) never show here
		var fraction := get_achievement_value(def) / target
		if fraction >= best_fraction and fraction < 1.0:
			best = def
			best_fraction = fraction
	if best.is_empty():
		return {}
	var missing := float(best["value"]) - get_achievement_value(best)
	var rate := INF
	match String(best["type"]):
		"lifetime_solves":
			rate = get_solves_per_second()
		"lifetime_moves":
			rate = get_moves_per_second()
		"time_played":
			rate = 1.0
	var seconds := missing / rate if rate > 0.0 and not is_inf(rate) else INF
	return {"kind": "achievement", "id": best["id"], "name": String(best["name"]), "more": false, "unit": "progress",
			"missing": missing, "seconds": seconds, "progress": best_fraction}


## An upgrade's name in the goal strip; an open choice (5.7b) names both sides, so the strip doesn't pick for you.
func _goal_name(def: Dictionary) -> String:
	var names: Array[String] = [String(def["name"])]
	for partner in get_choice_partners(def["id"]):
		names.append(String(Content.get_upgrade(partner)["name"]))
	return " or ".join(names)


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
	if _mult_cache_key() != _mult_cache_owned:
		_mult_cache.clear()
		_mult_cache_owned = _mult_cache_key()
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
## in Solves this run, like upgrades) and affordable.
func can_start_research(id: String) -> bool:
	return is_research_visible(id) and research.is_empty() and solves >= float(Content.get_lab_project(id)["cost"])


## Shown in the Lab: not done, requirements done, and half its cost earned this run, like an upgrade.
func is_research_visible(id: String) -> bool:
	var def := Content.get_lab_project(id)
	if def.is_empty() or is_research_done(id) or String(research.get("id", "")) == id:
		return false
	return _lab_requirements_done(def) and run_solves >= float(def["cost"]) * 0.5


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
		invalidate_upgrade_cache()
		research_finished.emit(id)
		check_helper_times()
		check_time_tiers()


## Learning a drill set in the Solve Station finishes its Lab project for free ("your own practice counts", S.4).
func _on_drill_set_learned_for_lab(set_id: String) -> void:
	for def in Content.get_lab_projects():
		if String(def.get("drill_set", "")) == set_id and not is_research_done(def["id"]):
			_complete_research(def["id"])


## Drops the cached upgrade/Lab multipliers. Everything in GameState that changes `upgrades` or `research_done` calls it;
## code that changes them directly (the balance bot trying an upgrade on, screenshot presets, tests) must call it too.
## (The cache also checks the owned count, but that alone misses swapping one upgrade for another of the same count:
## the bot tries upgrades on one at a time, so until 5.8 every trial after the first reused the first one's numbers.)
func invalidate_upgrade_cache() -> void:
	_mult_cache_owned = -1


## Product of every owned upgrade's (and finished Lab project's and trophy perk's) effect of this type (and target). Cached: with ~50 upgrades (5.2) this is called
## thousands of times a second by the balance bot. It's dropped by invalidate_upgrade_cache() (buying, finishing research,
## a reset, a load) and, as a safety net, whenever the number of owned upgrades, finished projects or perks changes.
func _upgrade_mult(effect_type: String, target: String = "") -> float:
	if _mult_cache_key() != _mult_cache_owned:
		_mult_cache.clear()
		_mult_cache_owned = _mult_cache_key()
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
		if not _effect_matches(effect, target):
			continue
		mult *= float(effect["value"])
	for id: String in research_done:  # finished Lab projects (5.6) count like owned upgrades
		var lab_effect: Dictionary = Content.get_lab_project(id).get("effect", {})
		if lab_effect.get("type", "") != effect_type or not _effect_matches(lab_effect, target):
			continue
		mult *= float(lab_effect["value"])
	for id: String in perks:  # trophy perks (6.3) with an upgrade effect count like owned upgrades too
		var perk_effect: Dictionary = Content.get_perk(id).get("effect", {})
		if perk_effect.get("type", "") != effect_type or not _effect_matches(perk_effect, target):
			continue
		mult *= float(perk_effect["value"])
	for id: String in collection:  # Cube Collection items (7.3a): get_item_mult (full in the Comp Kit, a share outside it)
		var item_effect: Dictionary = Content.get_collection_item(id).get("effect", {})
		if item_effect.get("type", "") != effect_type or not _effect_matches(item_effect, target):
			continue
		mult *= get_item_mult(id)
	for set_def: Dictionary in get_active_kit_sets():  # Comp Kit brand sets (7.4a)
		var set_effect: Dictionary = set_def["effect"]
		if set_effect["type"] == effect_type and _effect_matches(set_effect, target):
			mult *= float(set_effect["value"])
	_mult_cache[key] = mult
	return mult


## Like _upgrade_mult, but for effects that add up ("tap_share", S.7): the sum of every owned one's value.
func _upgrade_sum(effect_type: String) -> float:
	if _mult_cache_key() != _mult_cache_owned:
		_mult_cache.clear()
		_mult_cache_owned = _mult_cache_key()
	var key := "sum|" + effect_type
	if _mult_cache.has(key):
		return _mult_cache[key]
	var total := 0.0
	var effects: Array[Dictionary] = []
	for id: String in upgrades:
		effects.append(Content.get_upgrade(id).get("effect", {}))
	for id: String in research_done:
		effects.append(Content.get_lab_project(id).get("effect", {}))
	for id: String in perks:
		effects.append(Content.get_perk(id).get("effect", {}))
	for effect in effects:
		if effect.get("type", "") == effect_type:
			total += float(effect["value"])
	_mult_cache[key] = total
	return total


## What the upgrade cache's safety net compares: the counts of owned upgrades, finished projects, perks and collection
## stars (a drop also drops the cache itself).
func _mult_cache_key() -> int:
	return upgrades.size() + 1000 * research_done.size() + 1000000 * perks.size() + 1000000000 * get_collection_stars_total()


## Does an effect apply to this target ("" = any): its `target` (a helper) or one of its `puzzles` (5.7b specialists).
func _effect_matches(effect: Dictionary, target: String) -> bool:
	return target == "" or effect.get("target", "") == target or (effect.get("puzzles", []) as Array).has(target)


# --- Save / load -------------------------------------------------------------

func reset_state() -> void:
	solves = 0.0
	total_solves = 0.0
	run_solves = 0.0
	total_moves = 0.0
	unlocked_puzzles.clear()
	puzzle_progress.clear()
	puzzles_reached.clear()
	_add_puzzle(Content.PUZZLES[0]["id"])
	focused_puzzle = Content.PUZZLES[0]["id"]
	split = {focused_puzzle: 1.0}
	mastery_xp.clear()
	_mastery_levels.clear()
	buildings.clear()
	for def: Dictionary in Content.BUILDINGS:
		buildings[def["id"]] = 0
	upgrades.clear()
	trophies = 0
	perks.clear()
	career_seen.clear()
	_career_timer = 0.0
	achievements.clear()
	stats = _new_stats()
	collection.clear()
	_collection_stars = 0
	collection_pity.clear()
	collection_rng.randomize()
	kit.clear()
	kit_manual.clear()
	_load_competitions({})
	automation = {"compete_at": int(Content.AUTOMATION["compete_at_default"])}
	_automation_timer = 0.0
	championships = 0
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
	golden_case = {}
	golden_rng.randomize()
	golden_next = _roll_golden_wait()
	flow = {}
	streak = 0.0
	_tap_times.clear()
	drills.clear()
	daily = {}
	research = {}
	research_done.clear()
	invalidate_upgrade_cache()


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
		"championship": {"trophies": trophies, "count": championships, "run_solves": run_solves,
				"reached": puzzles_reached.keys(), "perks": perks.keys()},
		"automation": automation.duplicate(),
		"career": career_seen.keys(),
		"achievements": achievements.keys(),
		"stats": stats.duplicate(true),
		"collection": {"items": collection.duplicate(), "pity": collection_pity.duplicate()},
		"kit": {"slots": kit.duplicate(), "manual": kit_manual.keys()},
		"competitions": {"active": competition.duplicate(true), "medals": competition_medals.duplicate(),
				"records": competition_records.duplicate(true), "last": competition_result.duplicate(true),
				"entered": competitions_entered},
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
	_applying_save = true  # a moment reached here (e.g. research finished while away) fires at the first check after
	data = _migrate(data)
	solves = float(data.get("solves", 0.0))
	total_solves = maxf(0.0, float(data.get("total_solves", 0.0)))
	total_moves = float(data.get("total_moves", 0.0))
	var saved_champ: Dictionary = data.get("championship", {}) if typeof(data.get("championship", {})) == TYPE_DICTIONARY else {}
	trophies = maxi(0, int(saved_champ.get("trophies", 0)))
	championships = maxi(0, int(saved_champ.get("count", 0)))
	run_solves = clampf(float(saved_champ.get("run_solves", total_solves)), 0.0, total_solves)  # never more than lifetime
	_load_perks(saved_champ.get("perks", []))
	var saved_career: Variant = data.get("career", [])
	if typeof(saved_career) == TYPE_ARRAY:
		for id: Variant in saved_career:
			if not Content.get_career_moment(str(id)).is_empty():
				career_seen[str(id)] = true
	var saved_achievements: Variant = data.get("achievements", [])
	if typeof(saved_achievements) == TYPE_ARRAY:
		for id: Variant in saved_achievements:
			if not Content.get_achievement(str(id)).is_empty():
				achievements[str(id)] = true
	_load_stats(data.get("stats", {}))
	_load_collection(data.get("collection", {}))
	if typeof(data.get("collection")) == TYPE_STRING and String(data["collection"]) == "backfill":
		collection_rng.seed = 7700 + championships  # the same items every time this save loads (and screenshot presets)
		for i in mini(championships, (Content.COLLECTION["items"] as Array).size() * int(Content.COLLECTION["max_stars"])):
			roll_collection_drop("championship")  # nobody listens to the signal yet: the screen just shows them
		collection_rng.randomize()
	_load_kit(data.get("kit", {}))  # after the collection (and its backfill): only owned items fit
	_load_competitions(data.get("competitions", {}))  # a running one ends at the first update after loading (signalled)
	var saved_auto: Variant = data.get("automation", {})
	if typeof(saved_auto) == TYPE_DICTIONARY:
		for kind: String in Content.AUTOMATION["kinds"]:
			if typeof((saved_auto as Dictionary).get(kind)) == TYPE_BOOL:
				automation[kind] = bool(saved_auto[kind])
		if typeof((saved_auto as Dictionary).get("compete_at")) in [TYPE_INT, TYPE_FLOAT]:
			set_auto_compete_at(int(saved_auto["compete_at"]))
	var saved_reached: Variant = saved_champ.get("reached", [])
	if typeof(saved_reached) == TYPE_ARRAY:
		for id: Variant in saved_reached:
			if not Content.get_puzzle(str(id)).is_empty():
				puzzles_reached[str(id)] = true
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
	invalidate_upgrade_cache()
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
	if typeof(data.get("career")) == TYPE_STRING and String(data["career"]) == "backfill":
		check_career(false)  # a pre-v13 save: what already happened doesn't pop again (time away below still can)
	if typeof(data.get("career_backfill")) == TYPE_ARRAY:  # a v13-v17 save: v18's new moments it already lived (7.8)
		for id: Variant in data["career_backfill"]:
			var moment := Content.get_career_moment(str(id))
			if not moment.is_empty() and is_career_trigger_met(moment):
				career_seen[str(id)] = true
	if typeof(data.get("achievements")) == TYPE_STRING and String(data["achievements"]) == "backfill":
		check_achievements(false)  # a pre-v14 save: what it already reached is earned (with its bonus), silently
	_next_solves_milestone = _milestone_above(total_solves)
	var saved_at := float(data.get("saved_at", now))
	var elapsed := clampf(now - saved_at, 0.0, get_offline_cap_seconds())
	if elapsed >= MIN_OFFLINE_SECONDS:
		var before := total_solves
		var levels_before := _mastery_levels.duplicate()
		stats["run_time"] = float(stats["run_time"]) + elapsed  # the run went on (time played doesn't: nobody played)
		_offline_catch_up = true  # a buff pauses while the game is closed
		add_helper_moves(elapsed)
		_offline_catch_up = false
		var running := String(research.get("id", ""))
		update_research(elapsed)  # the Lab kept working too (capped like the rest)
		# 7.9: what else happened: mastery levels gained, achievements reached (earned, with their pops, at the first
		# check after loading)
		var mastery := {}
		for id: String in _mastery_levels:
			if int(_mastery_levels[id]) > int(levels_before.get(id, 1)):
				mastery[id] = [int(levels_before.get(id, 1)), int(_mastery_levels[id])]
		var reached: Array[String] = []
		for def: Dictionary in Content.get_achievements():
			if not achievements.has(def["id"]) and get_achievement_value(def) >= float(def["value"]):
				reached.append(String(def["id"]))
		if total_solves > before or (running != "" and research.is_empty()) or not mastery.is_empty() or not reached.is_empty():
			offline_report = {"seconds": elapsed, "solves": total_solves - before}
			if running != "" and research.is_empty():
				offline_report["research"] = Content.get_lab_project(running).get("topic", "")
			if not mastery.is_empty():
				offline_report["mastery"] = mastery  # puzzle id -> [level before, level now]
			if not reached.is_empty():
				offline_report["achievements"] = reached
	_applying_save = false


## The saved trophy perks (6.3): unknown ids and ones whose requirements aren't owned are dropped (in Content order, so a
## parent is decided before its children).
func _load_perks(saved: Variant) -> void:
	perks.clear()
	var wanted := {}
	if typeof(saved) == TYPE_ARRAY:
		for id: Variant in saved:
			wanted[str(id)] = true
	for def: Dictionary in Content.PERKS:
		if wanted.has(def["id"]) and is_perk_buyable_yet(def["id"]) and are_perk_requirements_met(def["id"]):
			perks[def["id"]] = true
	invalidate_upgrade_cache()


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
		if (done_set.has(def["id"]) and _lab_requirements_done(def)) or _is_drilled(def):
			research_done[def["id"]] = true
	invalidate_upgrade_cache()
	var current: Dictionary = lab.get("current", {}) if typeof(lab.get("current", {})) == TYPE_DICTIONARY else {}
	var id := str(current.get("id", ""))
	var def := Content.get_lab_project(id)
	if def.is_empty() or is_research_done(id) or not _lab_requirements_done(def):
		return
	if def["kind"] == "method" and get_next_method().get("id", "") != def["method"]:
		return
	var left := float(current.get("left", 0.0)) if typeof(current.get("left")) in [TYPE_FLOAT, TYPE_INT] else 0.0
	research = {"id": id, "left": clampf(left, 0.0, float(def["seconds"]))}


## A Lab project whose drill set (S.4) the player learned by hand: done for free, on load and after a championship.
func _is_drilled(def: Dictionary) -> bool:
	return def.get("kind", "") == "research" and String(def.get("drill_set", "")) != "" and is_drill_set_learned(def["drill_set"])


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
	if int(data["version"]) < 10:
		# v10 adds World Championships: none won yet, so this run's Solves are the lifetime ones and every puzzle
		# reached is one still unlocked.
		if not data.has("championship"):
			var reached: Array = (data.get("puzzles", {}) as Dictionary).get("unlocked", [])
			data["championship"] = {"trophies": 0, "count": 0, "run_solves": float(data.get("total_solves", 0.0)),
					"reached": reached.duplicate()}
		data["version"] = 10
	if int(data["version"]) < 11:
		# v11 adds trophy perks: none bought yet.
		var champ: Variant = data.get("championship", {})
		if typeof(champ) == TYPE_DICTIONARY and not (champ as Dictionary).has("perks"):
			(champ as Dictionary)["perks"] = []
		data["version"] = 11
	if int(data["version"]) < 12:
		# v12 adds the auto-buyer switches: nobody owned an auto-buyer, so all off.
		if not data.has("automation"):
			data["automation"] = {}
		data["version"] = 12
	if int(data["version"]) < 13:
		# v13 adds career moments (7.0a). An older save already lived through some of them: "backfill" marks every
		# moment that's already true as seen when the save is applied, so they don't all pop at once.
		if not data.has("career"):
			data["career"] = "backfill"
		data["version"] = 13
	if int(data["version"]) < 14:
		# v14 adds achievements (7.1a). "backfill" earns, silently, every one an older save has already reached (the
		# ones it can tell: what it owns and has done now), so its bonus counts at once and nothing floods the screen.
		if not data.has("achievements"):
			data["achievements"] = "backfill"
		data["version"] = 14
	if int(data["version"]) < 15:
		# v15 adds stats (7.2a). Most weren't counted before, so they start at 0 (best Solves/s fills in within a second).
		# Trophies won can be worked out: the ones held plus the ones spent on perks.
		# The run in progress started before its clock did, so it can't set the fastest championship.
		if not data.has("stats"):
			var champ: Variant = data.get("championship", {})
			var won := 0.0
			if typeof(champ) == TYPE_DICTIONARY:
				won = maxf(0.0, float((champ as Dictionary).get("trophies", 0)))
				var owned: Variant = (champ as Dictionary).get("perks", [])
				var counted := {}
				if typeof(owned) == TYPE_ARRAY:
					for id: Variant in owned:
						if not counted.has(str(id)):  # a perk dropped on load (a missing requirement) was still paid for
							counted[str(id)] = true
							won += float(Content.get_perk(str(id)).get("cost", 0))
			data["stats"] = {"trophies_won": won, "run_untimed": 1.0}
		data["version"] = 15
	if int(data["version"]) < 16:
		# v16 adds the Cube Collection (7.3a). A championship now always drops an item: "backfill" gives an older save
		# one per championship it already won, when it's applied (nothing else: achievement drops are luck).
		if not data.has("collection"):
			data["collection"] = "backfill"
		data["version"] = 16
	if int(data["version"]) < 17:
		# v17 adds the Comp Kit (7.4a): every slot on auto, so loading fills it with the best items owned.
		if not data.has("kit"):
			data["kit"] = {"slots": {}, "manual": []}
		data["version"] = 17
	if int(data["version"]) < 18:
		# v18: the Legendary pity counter (7.6) starts at 0 (missing = 0, nothing to add), and new career moments (7.8):
		# the ones an older save already lived through are marked seen when it's applied, silently.
		if typeof(data.get("career")) == TYPE_ARRAY:
			data["career_backfill"] = Content.CAREER_V18.duplicate()
		data["version"] = 18
	if int(data["version"]) < 19:
		# v19 adds competitions (8.3a): nobody has entered one yet.
		if not data.has("competitions"):
			data["competitions"] = {}
		data["version"] = 19
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
	run_solves += amount
