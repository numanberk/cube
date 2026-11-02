class_name GameState
extends Node
## Global game state and rules. Registered as the autoload "Game".
## All numbers live here; UI scripts only read them and call the public methods.

signal solved(count: int)
signal purchased(kind: String, id: String)
signal state_reset

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL := 10.0
const MAX_OFFLINE_SECONDS := 8.0 * 3600.0
const MIN_OFFLINE_SECONDS := 10.0
const BASE_MOVES_PER_SOLVE := 15.0
const BASE_TAP_MOVES := 1.0
const COST_GROWTH := 1.15

## Set to false before the node enters the tree to skip loading/saving (tests do this).
var persistence_enabled := true
## Where the save lives. Tests point this somewhere else. The backup is `save.bak` next to it,
## and a save that can't be read is copied to `save.corrupt.json` before anything overwrites it.
var save_path := SAVE_PATH

var solves := 0.0          ## Spendable currency.
var total_solves := 0.0    ## Lifetime Solves earned; never goes down.
var total_moves := 0.0     ## Lifetime moves made.
var move_progress := 0.0   ## Moves made toward the current solve.
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
	add_moves(get_tap_moves())


func add_moves(amount: float) -> void:
	if amount <= 0.0:
		return
	total_moves += amount
	move_progress += amount
	var needed := get_moves_per_solve()
	if move_progress >= needed:
		var count := floorf(move_progress / needed)
		move_progress -= count * needed
		var reward := count * get_solve_value()
		solves += reward
		total_solves += reward
		solved.emit(int(count))


func get_moves_per_solve() -> float:
	return maxf(1.0, BASE_MOVES_PER_SOLVE * _upgrade_mult("solve_moves_mult"))


func get_solve_value() -> float:
	return _upgrade_mult("solve_value_mult")


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


func get_solves_per_second() -> float:
	return get_moves_per_second() / get_moves_per_solve() * get_solve_value()


# --- Shop --------------------------------------------------------------------

func get_building_cost(id: String) -> float:
	var def := Content.get_building(id)
	var owned: int = buildings.get(id, 0)
	return ceilf(float(def["base_cost"]) * pow(COST_GROWTH, owned))


func is_building_unlocked(id: String) -> bool:
	var def := Content.get_building(id)
	var unlock_at := float(def.get("unlock_at", float(def["base_cost"]) * 0.5))
	return int(buildings.get(id, 0)) > 0 or total_solves >= unlock_at


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


## The next new thing to aim for (the "Next goal" strip): the cheapest helper not owned yet, or upgrade not bought
## yet whose requirements are met. If everything is owned, the cheapest next copy of a helper (`more` = true).
## Returns {kind, id, name, cost, missing (Solves still needed, 0 = can buy now), seconds (at the current
## helper rate; INF without helpers), more}. Puzzles join this list in task 4.3a.
func get_next_goal() -> Dictionary:
	var candidates: Array[Dictionary] = []
	for def: Dictionary in Content.BUILDINGS:
		if int(buildings.get(def["id"], 0)) == 0:
			candidates.append({"kind": "helper", "id": def["id"], "name": def["name"], "cost": get_building_cost(def["id"]), "more": false})
	for def: Dictionary in Content.UPGRADES:
		if upgrades.has(def["id"]) or not _upgrade_requirements_met(def):
			continue
		candidates.append({"kind": "upgrade", "id": def["id"], "name": def["name"], "cost": float(def["cost"]), "more": false})
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
	move_progress = 0.0
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
		"move_progress": move_progress,
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
	move_progress = float(data.get("move_progress", 0.0))
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
	var _version := int(data.get("version", 1))
	# Example for the future:
	# if _version < 2:
	#     data["trophies"] = 0
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
