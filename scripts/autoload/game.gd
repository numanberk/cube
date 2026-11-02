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

var solves := 0.0          ## Spendable currency.
var total_solves := 0.0    ## Lifetime Solves earned; never goes down.
var total_moves := 0.0     ## Lifetime moves made.
var move_progress := 0.0   ## Moves made toward the current solve.
var buildings: Dictionary = {}  ## building id -> owned count
var upgrades: Dictionary = {}   ## upgrade id -> true (owned)
var offline_report: Dictionary = {}  ## {"seconds", "solves"} after loading, if anything was earned

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


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(get_save_data(), "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Save file is unreadable; starting fresh.")
		return
	apply_save_data(data, Time.get_unix_time_from_system())


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
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	state_reset.emit()


## Debug helper (F9 in debug builds).
func cheat_add_solves(amount: float) -> void:
	solves += amount
	total_solves += amount
