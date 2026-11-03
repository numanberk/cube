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

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2  ## v2 (task 4.2): parallel puzzles
const AUTOSAVE_INTERVAL := 10.0
const MAX_OFFLINE_SECONDS := 8.0 * 3600.0
const MIN_OFFLINE_SECONDS := 10.0
const BASE_TAP_MOVES := 1.0
const COST_GROWTH := 1.15
const BUY_MAX := -1              ## pass as `count` to buy as many as you can afford
const BULK_LIMIT := 10000        ## safety cap for bulk cost loops

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
var buildings: Dictionary = {}  ## building id -> owned count
var upgrades: Dictionary = {}   ## upgrade id -> true (owned)
var offline_report: Dictionary = {}  ## {"seconds", "solves"} after loading, if anything was earned
var load_notice := ""  ## Set when the save was damaged and a backup (or nothing) was loaded; the UI shows it once.

var _autosave_timer := 0.0


func _ready() -> void:
	reset_state()
	if persistence_enabled:
		load_game()


func _process(delta: float) -> void:
	add_moves(get_moves_per_second() * delta)
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


## Helper moves (or offline moves): divided across the unlocked puzzles by the split.
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
	total_moves += amount
	var progress := float(puzzle_progress[puzzle_id]) + amount
	var needed := get_moves_per_solve(puzzle_id)
	if progress >= needed:
		var count := floorf(progress / needed)
		progress -= count * needed
		var reward := count * get_solve_value(puzzle_id)
		solves += reward
		total_solves += reward
		puzzle_progress[puzzle_id] = progress
		solved.emit(int(count), puzzle_id)
	else:
		puzzle_progress[puzzle_id] = progress


## Moves needed for one solve on a puzzle (the focused one by default), after method upgrades.
func get_moves_per_solve(puzzle_id: String = "") -> float:
	var def := Content.get_puzzle(_or_focused(puzzle_id))
	return maxf(1.0, float(def.get("moves_per_solve", 1.0)) * _upgrade_mult("solve_moves_mult"))


## Solves earned per solve on a puzzle (the focused one by default).
func get_solve_value(puzzle_id: String = "") -> float:
	var def := Content.get_puzzle(_or_focused(puzzle_id))
	return float(def.get("solve_value", 1.0)) * _upgrade_mult("solve_value_mult")


## Moves made toward the next solve on a puzzle (the focused one by default).
func get_move_progress(puzzle_id: String = "") -> float:
	return float(puzzle_progress.get(_or_focused(puzzle_id), 0.0))


func get_tap_moves() -> float:
	return BASE_TAP_MOVES * _upgrade_mult("tap_mult") * _upgrade_mult("global_mult")


## Moves per second produced by ONE unit of a building.
func get_building_mps(id: String) -> float:
	var def := Content.get_building(id)
	return float(def["mps"]) * _upgrade_mult("building_mult", id) * _upgrade_mult("global_mult")


func get_moves_per_second() -> float:
	var total := 0.0
	for def: Dictionary in Content.BUILDINGS:
		var owned: int = buildings.get(def["id"], 0)
		if owned > 0:
			total += owned * get_building_mps(def["id"])
	return total


## Helper moves per second going to one puzzle.
func get_puzzle_moves_per_second(puzzle_id: String) -> float:
	return get_moves_per_second() * get_puzzle_share(puzzle_id)


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
	return ceilf(float(def["base_cost"]) * pow(COST_GROWTH, owned))


## Cost of the next `count` copies of a helper: the exact sum of each copy's ceil(base × 1.15^owned), so bulk
## buying costs the same as buying one at a time.
func get_building_cost_for(id: String, count: int) -> float:
	var def := Content.get_building(id)
	var owned: int = buildings.get(id, 0)
	var total := 0.0
	for i in mini(count, BULK_LIMIT):
		total += ceilf(float(def["base_cost"]) * pow(COST_GROWTH, owned + i))
	return total


## How many copies of a helper the current Solves can buy (0 if not even one).
func get_max_affordable(id: String) -> int:
	var def := Content.get_building(id)
	var owned: int = buildings.get(id, 0)
	var left := solves
	var count := 0
	while count < BULK_LIMIT:
		var cost := ceilf(float(def["base_cost"]) * pow(COST_GROWTH, owned + count))
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
	if total_solves < float(def["cost"]) * 0.5:
		return false
	var requires: Dictionary = def.get("requires", {})
	for building_id: String in requires:
		if int(buildings.get(building_id, 0)) < int(requires[building_id]):
			return false
	return true


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
## helper rate; INF without helpers), more}. The next puzzle (kind "puzzle") is one of the candidates.
func get_next_goal() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for def: Dictionary in Content.BUILDINGS:
		if int(buildings.get(def["id"], 0)) == 0:
			candidates.append({"kind": "helper", "id": def["id"], "name": def["name"], "cost": get_building_cost(def["id"]), "more": false})
	for def: Dictionary in Content.UPGRADES:
		if upgrades.has(def["id"]) or not _upgrade_requirements_met(def):
			continue
		candidates.append({"kind": "upgrade", "id": def["id"], "name": def["name"], "cost": float(def["cost"]), "more": false})
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


func _upgrade_requirements_met(def: Dictionary) -> bool:
	var requires: Dictionary = def.get("requires", {})
	for building_id: String in requires:
		if int(buildings.get(building_id, 0)) < int(requires[building_id]):
			return false
	return true


func _upgrade_mult(effect_type: String, target: String = "") -> float:
	var mult := 1.0
	for def: Dictionary in Content.UPGRADES:
		if not upgrades.has(def["id"]):
			continue
		var effect: Dictionary = def["effect"]
		if effect["type"] != effect_type:
			continue
		if target != "" and effect.get("target", "") != target:
			continue
		mult *= float(effect["value"])
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
	buildings.clear()
	for def: Dictionary in Content.BUILDINGS:
		buildings[def["id"]] = 0
	upgrades.clear()
	offline_report = {}


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
		"buildings": buildings.duplicate(),
		"upgrades": upgrades.keys(),
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
		if not Content.get_upgrade(id).is_empty():
			upgrades[id] = true

	var saved_at := float(data.get("saved_at", now))
	var elapsed := clampf(now - saved_at, 0.0, MAX_OFFLINE_SECONDS)
	if elapsed >= MIN_OFFLINE_SECONDS:
		var before := total_solves
		add_moves(get_moves_per_second() * elapsed)
		if total_solves > before:
			offline_report = {"seconds": elapsed, "solves": total_solves - before}


## Upgrades old save formats. Bump SAVE_VERSION and add a step here whenever
## the shape of get_save_data() changes, so existing players keep their progress.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
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
