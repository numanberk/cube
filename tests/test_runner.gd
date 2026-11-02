extends SceneTree
## Headless test suite. Run with: bash tools/run_tests.sh
## Add a new test by writing a `func test_something() -> void:` below; it runs automatically.



var _checks := 0
var _failures := 0
var _current := ""


func _initialize() -> void:
	for method: Dictionary in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			_current = method_name
			call(method_name)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL [%s] %s" % [_current, message])


func check_near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s (expected %s, got %s)" % [message, expected, actual])


func new_game() -> GameState:
	var game := GameState.new()
	game.persistence_enabled = false
	game.reset_state()
	return game


# --- Tests -------------------------------------------------------------------

func test_fresh_state() -> void:
	var g := new_game()
	check_near(g.solves, 0.0, "starts with no solves")
	check(g.is_building_unlocked("friend"), "first helper is visible from the start")
	check(not g.is_building_unlocked("club"), "later helpers start hidden")
	check_near(g.get_moves_per_second(), 0.0, "no passive moves at start")
	g.free()


func test_tapping_completes_a_solve() -> void:
	var g := new_game()
	for i in int(g.BASE_MOVES_PER_SOLVE):
		g.tap()
	check_near(g.solves, 1.0, "15 taps = 1 solve")
	check_near(g.move_progress, 0.0, "progress resets after a solve")
	g.free()


func test_buying_helpers() -> void:
	var g := new_game()
	check(not g.buy_building("friend"), "can't buy without Solves")
	g.cheat_add_solves(5.0)
	check(g.buy_building("friend"), "can buy with enough Solves")
	check_near(g.solves, 0.0, "cost was deducted")
	check(g.get_building_cost("friend") > 5.0, "cost grows after buying")
	check_near(g.get_moves_per_second(), 0.5, "one friend = 0.5 moves/s")
	g.add_moves(g.get_moves_per_second() * 30.0)
	check_near(g.solves, 1.0, "30s of one friend = 1 solve")
	g.free()


func test_upgrades() -> void:
	var g := new_game()
	g.cheat_add_solves(1000.0)
	check(g.buy_upgrade("lube"), "buy Cube Lube")
	check_near(g.get_tap_moves(), 2.0, "lube doubles tap moves")
	check(not g.buy_upgrade("lube"), "can't buy an upgrade twice")
	check(g.buy_upgrade("cfop"), "buy CFOP")
	check_near(g.get_moves_per_solve(), 10.5, "CFOP cuts moves per solve by 30%")
	check(not g.is_upgrade_available("stackmat"), "Stackmat needs a friend first")
	g.buy_building("friend")
	check(g.is_upgrade_available("stackmat"), "Stackmat available after owning a friend")
	g.free()


func test_save_roundtrip_and_offline_progress() -> void:
	var g := new_game()
	g.cheat_add_solves(100.0)
	g.buy_building("friend")
	g.buy_upgrade("lube")
	var data: Dictionary = g.get_save_data()
	var saved_at: float = data["saved_at"]

	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), saved_at)
	check_near(loaded.solves, g.solves, "solves survive save/load")
	check(int(loaded.buildings["friend"]) == 1, "helpers survive save/load")
	check(loaded.upgrades.has("lube"), "upgrades survive save/load")
	check(loaded.offline_report.is_empty(), "no offline report when no time passed")

	loaded.apply_save_data(data, saved_at + 3600.0)
	var expected := floorf(0.5 * 3600.0 / 15.0)
	check_near(loaded.offline_report.get("solves", 0.0), expected, "1h offline with one friend")

	loaded.apply_save_data(data, saved_at + 100.0 * 3600.0)
	check_near(loaded.offline_report.get("seconds", 0.0), g.MAX_OFFLINE_SECONDS, "offline time is capped")
	g.free()
	loaded.free()


func test_content_is_valid() -> void:
	var ids := {}
	for def: Dictionary in Content.BUILDINGS:
		for field: String in ["id", "name", "description", "base_cost", "mps"]:
			check(def.has(field), "building %s has '%s'" % [def.get("id", "?"), field])
		check(not ids.has(def["id"]), "id '%s' is unique" % def["id"])
		ids[def["id"]] = true
	for def: Dictionary in Content.UPGRADES:
		for field: String in ["id", "name", "description", "cost", "effect"]:
			check(def.has(field), "upgrade %s has '%s'" % [def.get("id", "?"), field])
		check(not ids.has(def["id"]), "id '%s' is unique" % def["id"])
		ids[def["id"]] = true
		var effect: Dictionary = def["effect"]
		check(Content.EFFECT_TYPES.has(effect["type"]), "upgrade %s has a known effect type" % def["id"])
		if effect["type"] == "building_mult":
			check(not Content.get_building(effect.get("target", "")).is_empty(), "upgrade %s targets a real helper" % def["id"])
		for building_id: String in def.get("requires", {}):
			check(not Content.get_building(building_id).is_empty(), "upgrade %s requires a real helper" % def["id"])


func test_number_formatting() -> void:
	check(Num.format(0) == "0", "0")
	check(Num.format(0.5) == "0.5", "0.5")
	check(Num.format(999) == "999", "999")
	check(Num.format(1500) == "1.50K", "1500 -> 1.50K")
	check(Num.format(2500000) == "2.50M", "2.5M")
	check(Num.format(123456789) == "123.5M", "123.5M")
	check(Num.format_duration(75) == "1m 15s", "75s -> 1m 15s")
	check(Num.format_duration(7300) == "2h 1m", "7300s -> 2h 1m")


func test_screenshot_presets_still_load() -> void:
	# tools/screenshot.sh relies on these; a save-format change must keep them loading.
	var presets: Dictionary = load("res://tools/screenshot_presets.gd").PRESETS
	for name: String in ["fresh", "mid", "late"]:
		check(presets.has(name), "screenshot preset '%s' exists" % name)
	for name: String in presets:
		var data: Dictionary = presets[name]
		var g := new_game()
		g.apply_save_data(data.duplicate(true), 1000.0)
		check_near(g.solves, float(data.get("solves", 0.0)), "preset '%s' loads its Solves" % name)
		var saved_buildings: Dictionary = data.get("buildings", {})
		for id: String in saved_buildings:
			check(int(g.buildings.get(id, -1)) == int(saved_buildings[id]), "preset '%s' keeps helper '%s'" % [name, id])
		for id: String in data.get("upgrades", []):
			check(g.upgrades.has(id), "preset '%s' keeps upgrade '%s'" % [name, id])
		check(g.offline_report.is_empty(), "preset '%s' grants no offline progress" % name)
		g.free()


func test_simulator_short_run() -> void:
	var sim: RefCounted = load("res://tools/simulator.gd").new()
	var tapping: Dictionary = sim.run(3.0, 2.0)
	var events: Array = tapping["events"]
	check(not events.is_empty(), "a tapping bot buys something in 2 minutes")
	check(not events.is_empty() and events[0]["id"] == "friend", "the first purchase is a Cubing Friend")
	check(tapping["checkpoints"].size() == 1, "a 2-minute run records only the 1-minute checkpoint")
	var idle: Dictionary = sim.run(0.0, 1.0)
	check(idle["events"].is_empty(), "with no taps and no helpers nothing is bought")


func test_simulator_leaves_state_unchanged_when_measuring() -> void:
	var sim: RefCounted = load("res://tools/simulator.gd").new()
	var g := new_game()
	g.cheat_add_solves(5000.0)
	g.buy_building("friend")
	g.buy_upgrade("lube")
	var buildings_before := g.buildings.duplicate()
	var upgrades_before := g.upgrades.duplicate()
	var base: float = sim.income(g, 3.0)
	for item: Dictionary in sim._candidates(g):
		var gain: float = sim._income_gain(g, item, 3.0, base)
		check(gain >= 0.0, "%s %s never lowers income" % [item["kind"], item["id"]])
	check(g.buildings == buildings_before, "measuring helpers restores the owned counts")
	check(g.upgrades == upgrades_before, "measuring upgrades restores the owned set")
	check_near(sim.income(g, 3.0), base, "income is the same after measuring")
	g.free()


func test_pacing_checks() -> void:
	# The pacing rules themselves, on a made-up simulator result.
	var Pacing: GDScript = load("res://tools/pacing.gd")
	var result := {"minutes": 10.0, "events": [
		{"t": 15.0, "kind": "helper", "id": "friend", "name": "Friend"},
		{"t": 50.0, "kind": "upgrade", "id": "lube", "name": "Lube"},
		{"t": 400.0, "kind": "helper", "id": "club", "name": "Club"},
	]}
	check(Pacing.check({"type": "first_by", "kind": "helper", "max": 20.0}, result)["passed"], "helper at 15 s meets <= 20 s")
	check(not Pacing.check({"type": "first_by", "kind": "upgrade", "max": 40.0}, result)["passed"], "upgrade at 50 s misses <= 40 s")
	check(not Pacing.check({"type": "first_by", "kind": "", "max": 5.0}, result)["passed"], "anything by 5 s fails")
	check(Pacing.check({"type": "item_between", "kind": "helper", "item": "club", "min": 300.0, "max": 500.0}, result)["passed"], "club inside its window")
	check(not Pacing.check({"type": "item_between", "kind": "puzzle", "item": "3x3", "min": 0.0, "max": 999.0}, result)["passed"], "a missing item fails")
	var gap: Dictionary = Pacing.longest_gap(result["events"], 0.0, 600.0)
	check_near(gap["length"], 350.0, "longest gap is Lube -> Club")
	check_near(Pacing.longest_gap(result["events"], 450.0, 600.0)["length"], 150.0, "a gap after the last item runs to the window end")
	check(not Pacing.check({"type": "max_gap", "from": 0.0, "to": 600.0, "max": 300.0}, result)["passed"], "350 s gap misses <= 300 s")
	check(Pacing.check({"type": "max_gap", "from": 0.0, "to": 300.0, "max": 300.0}, result)["passed"], "first 5 min has no gap over 300 s")
	var rows: Array = Pacing.evaluate({})
	check(rows.size() == Pacing.TARGETS.size(), "evaluate returns a row per target")
	for target: Dictionary in Pacing.TARGETS:
		check(target["profile"] in ["tapping", "idle"], "target %s has a known profile" % target["id"])
		if target["type"] == "unsupported":
			check(target.get("expected_failure", "") != "", "unsupported target %s is an expected failure" % target["id"])


func test_pacing_targets() -> void:
	# PLAN §2 pacing, measured by the simulator on today's content. See tools/pacing.gd.
	var Pacing: GDScript = load("res://tools/pacing.gd")
	var sim: RefCounted = load("res://tools/simulator.gd").new()
	var results := {
		"tapping": sim.run(Pacing.TAPS_PER_SEC, Pacing.TAPPING_MINUTES),
		"idle": sim.run(0.0, Pacing.IDLE_MINUTES),
	}
	var expected: PackedStringArray = []
	for row: Dictionary in Pacing.evaluate(results):
		match row["status"]:
			"FAIL":
				check(false, "pacing target missed: %s (actual: %s)" % [row["text"], row["actual"]])
			"NOW PASSES":
				check(false, "pacing target '%s' now passes (%s): remove its expected_failure in tools/pacing.gd" % [row["id"], row["actual"]])
			_:
				check(true, row["id"])
				if row["status"] == "expected failure":
					expected.append(row["id"])
	if not expected.is_empty():
		print("  pacing: %d expected failures (see docs/BALANCE.md): %s" % [expected.size(), ", ".join(expected)])


# --- Safe saves (task 0.4) ---------------------------------------------------

const TEST_SAVE_DIR := "user://test_saves"


func save_game_at(path: String) -> GameState:
	var g := new_game()
	g.save_path = path
	return g


func clean_test_saves() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_SAVE_DIR))
	for file_name in DirAccess.get_files_at(TEST_SAVE_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_DIR.path_join(file_name)))


func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_save_writes_atomically_and_keeps_backup() -> void:
	clean_test_saves()
	var path := TEST_SAVE_DIR.path_join("save.json")
	var g := save_game_at(path)
	g.cheat_add_solves(10.0)
	check(g.save_game(), "first save succeeds")
	check(FileAccess.file_exists(path), "save.json exists")
	check(not FileAccess.file_exists(path + ".tmp"), "no temp file left behind")
	check(not FileAccess.file_exists(g.get_backup_path()), "no backup before the second save")
	check(g.get_backup_path().get_file() == "save.bak", "backup is called save.bak")
	g.cheat_add_solves(5.0)
	check(g.save_game(), "second save succeeds")
	var backup: Variant = JSON.parse_string(FileAccess.get_file_as_string(g.get_backup_path()))
	check(typeof(backup) == TYPE_DICTIONARY and is_equal_approx(float(backup["solves"]), 10.0), "backup holds the previous save")
	var loaded := save_game_at(path)
	loaded.load_game()
	check_near(loaded.solves, 15.0, "the newest save loads")
	check(loaded.load_notice == "", "no notice for a healthy save")
	g.free()
	loaded.free()


func test_corrupt_save_loads_backup() -> void:
	clean_test_saves()
	var path := TEST_SAVE_DIR.path_join("save.json")
	var g := save_game_at(path)
	g.cheat_add_solves(42.0)
	g.save_game()
	g.save_game()  # now save.bak = 42 Solves too
	write_text(path, "{\"solves\": 9")  # cut off mid-write
	var loaded := save_game_at(path)
	loaded.load_game()
	check_near(loaded.solves, 42.0, "a corrupt save falls back to the backup")
	check(loaded.load_notice != "", "the player is told the backup was loaded")
	check(FileAccess.file_exists(loaded.get_corrupt_path()), "the damaged save is kept for recovery")
	g.free()
	loaded.free()


func test_missing_save_starts_fresh() -> void:
	clean_test_saves()
	var path := TEST_SAVE_DIR.path_join("save.json")
	var g := save_game_at(path)
	g.load_game()
	check_near(g.solves, 0.0, "no save = fresh start")
	check(g.load_notice == "", "no notice on a first launch")
	g.free()


func test_missing_save_with_backup_loads_backup() -> void:
	# A crash between "save.json -> save.bak" and "tmp -> save.json" leaves only the backup.
	clean_test_saves()
	var path := TEST_SAVE_DIR.path_join("save.json")
	var g := save_game_at(path)
	g.cheat_add_solves(7.0)
	g.save_game()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(g.get_backup_path()))
	var loaded := save_game_at(path)
	loaded.load_game()
	check_near(loaded.solves, 7.0, "the backup loads when save.json is missing")
	g.free()
	loaded.free()


func test_corrupt_save_and_backup_start_fresh() -> void:
	clean_test_saves()
	var path := TEST_SAVE_DIR.path_join("save.json")
	write_text(path, "not json")
	var g := save_game_at(path)
	write_text(g.get_backup_path(), "[1, 2, 3]")
	g.load_game()
	check_near(g.solves, 0.0, "both unreadable = fresh start")
	check(g.load_notice.contains("started fresh"), "the player is told the game started fresh")
	check(FileAccess.get_file_as_string(g.get_corrupt_path()) == "not json", "the damaged save is kept")
	g.free()


func test_wipe_removes_save_and_backup() -> void:
	clean_test_saves()
	var path := TEST_SAVE_DIR.path_join("save.json")
	var g := save_game_at(path)
	g.save_game()
	g.save_game()
	g.wipe_save()
	check(not FileAccess.file_exists(path), "wipe removes save.json")
	check(not FileAccess.file_exists(g.get_backup_path()), "wipe removes save.bak")
	g.free()
	clean_test_saves()
