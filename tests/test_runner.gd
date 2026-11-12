extends SceneTree
## Headless test suite. Run with: bash tools/run_tests.sh
## Add a new test by writing a `func test_something() -> void:` below; it runs automatically.



var _checks := 0
var _failures := 0
var _current := ""


func _initialize() -> void:
	await process_frame  # the tree only runs _ready() on added nodes once the main loop has started
	for method: Dictionary in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			_current = method_name
			await call(method_name)  # tests may await frames
	print("\n%d checks, %d failed" % [_checks, _failures])
	var audio := root.get_node_or_null("Audio") as AudioManager
	if audio != null:
		audio.shut_down()  # sounds still playing at exit would be reported as leaked resources
		for i in 6:  # the audio thread releases stopped playbacks on its next mixes
			await create_timer(0.1).timeout
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
	game.collection_rng.seed = 1  # Cube Collection drops (7.3a): the same in every run of the tests
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
	check(g.get_focused_puzzle_id() == "2x2", "a new game starts on the 2x2")
	for i in int(g.get_moves_per_solve()):
		g.tap()
	check_near(g.solves, 1.0, "8 taps = one 2x2 solve = 1 Solve")
	check_near(g.get_move_progress(), 0.0, "progress resets after a solve")
	g.free()


func test_buying_helpers() -> void:
	var g := new_game()
	check_near(g.get_building_cost("friend"), 0.0, "the first Friend is free (5.0: never tapping still progresses)")
	check(g.buy_building("friend"), "so it can be bought with no Solves")
	check(not g.buy_building("friend"), "the second one costs Solves")
	check_near(g.get_building_cost("friend"), ceilf(5.0 * 1.15), "...ceil(5 × 1.15) = 6")
	check_near(g.get_building_cost_for("friend", 2), 6.0 + ceilf(5.0 * 1.15 * 1.15), "bulk cost sums each copy")
	check(not Content.get_building("club").get("first_free", false) and g.get_building_cost("club") > 0.0, "only the Friend is free")
	g.free()
	g = new_game()
	g.cheat_add_solves(5.0)
	check(g.buy_building("friend"), "can buy with enough Solves")
	check_near(g.solves, 5.0, "the free one costs nothing")
	check(g.get_building_cost("friend") > 5.0, "cost grows after buying")
	check_near(g.get_moves_per_second(), 0.5, "one friend = 0.5 moves/s")
	g.add_moves(g.get_moves_per_second() * 30.0)
	check_near(g.solves, 6.0, "30s of one friend = 1 solve (on top of the 5 the free Friend didn't cost)")
	g.free()


func test_upgrades() -> void:
	var g := new_game()
	g.cheat_add_solves(1000.0)
	check(g.buy_upgrade("lube"), "buy Cube Lube")
	check_near(g.get_tap_moves(), 2.0, "lube doubles tap moves")
	check(not g.buy_upgrade("lube"), "can't buy an upgrade twice")
	check(Content.get_upgrade("cfop").is_empty() and not g.buy_upgrade("cfop"), "CFOP is a method now, not an upgrade")
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
	var expected := floorf(0.5 * 3600.0 / loaded.get_moves_per_solve("2x2")) * loaded.get_solve_value("2x2")
	check_near(loaded.offline_report.get("solves", 0.0), expected, "1h offline with one friend (on the 2x2)")

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
		if effect["type"] == "puzzle_mult":
			for puzzle_id: String in effect.get("puzzles", []):
				check(not Content.get_puzzle(puzzle_id).is_empty(), "upgrade %s boosts a real puzzle" % def["id"])
		if def.has("choice_group"):
			var members := 0
			for other: Dictionary in Content.UPGRADES:
				if other.get("choice_group", "") == def["choice_group"]:
					members += 1
					check(float(other["cost"]) == float(def["cost"]), "choice %s: both sides cost the same" % def["choice_group"])
			check(members == 2, "choice group %s is a pair" % def["choice_group"])
	for i in Content.METHODS.size():
		var def: Dictionary = Content.METHODS[i]
		for field: String in ["id", "icon", "name", "description", "cost", "mult"]:
			check(def.has(field), "method %s has '%s'" % [def.get("id", "?"), field])
		check(not ids.has(def["id"]), "id '%s' is unique" % def["id"])
		ids[def["id"]] = true
		if i == 0:
			check(float(def["cost"]) == 0.0 and float(def["mult"]) == 1.0, "the first method is free and changes nothing")
		else:
			check(float(def["mult"]) > 0.0 and float(def["mult"]) < 1.0, "method %s cuts moves per solve" % def["id"])
			check(float(def["cost"]) > float(Content.METHODS[i - 1]["cost"]), "method %s costs more than the one before" % def["id"])
	for def: Dictionary in Content.PUZZLES:
		var floor_moves := float(def.get("min_moves_per_solve", 0.0))
		check(floor_moves >= 1.0 and floor_moves < float(def["moves_per_solve"]), "puzzle %s has a floor below its moves per solve" % def["id"])


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
			if not Content.get_method(id).is_empty():  # "cfop"/"roux" were upgrades before save v4
				check(g.is_method_learned(id), "preset '%s' keeps method '%s'" % [name, id])
			else:
				check(g.upgrades.has(id), "preset '%s' keeps upgrade '%s'" % [name, id])
		check(g.offline_report.is_empty(), "preset '%s' grants no offline progress" % name)
		var past_prestige := g.unlocked_puzzles.has("7x7") or g.unlocked_puzzles.has("megaminx")
		check(not past_prestige or g.has_won_championship(), "preset '%s': a 7×7 or Megaminx comes with a championship" % name)
		g.free()


func test_simulator_short_run() -> void:
	var sim: RefCounted = load("res://tools/simulator.gd").new()
	var tapping: Dictionary = sim.run(3.0, 2.0)
	var events: Array = tapping["events"]
	check(not events.is_empty(), "a tapping bot buys something in 2 minutes")
	check(not events.is_empty() and events[0]["id"] == "friend", "the first purchase is a Cubing Friend")
	check(tapping["checkpoints"].size() == 1, "a 2-minute run records only the 1-minute checkpoint")
	var idle: Dictionary = sim.run(0.0, 1.0)
	check(idle["events"].size() >= 1 and idle["events"][0]["id"] == "friend", "with no taps the free Friend is still taken (5.0)")


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
		check(target["profile"] in ["tapping", "idle", "active"], "target %s has a known profile" % target["id"])
		if target["type"] == "unsupported":
			check(target.get("expected_failure", "") != "", "unsupported target %s is an expected failure" % target["id"])


func test_pacing_targets() -> void:
	# PLAN §2 pacing, measured by the simulator on today's content. See tools/pacing.gd.
	var Pacing: GDScript = load("res://tools/pacing.gd")
	var sim: RefCounted = load("res://tools/simulator.gd").new()
	var results := {
		"tapping": sim.run(Pacing.TAPS_PER_SEC, Pacing.TAPPING_MINUTES, {}, [], Pacing.TAPPING_PRESTIGE),
		"idle": sim.run(0.0, Pacing.IDLE_MINUTES),
		"active": sim.run(Pacing.TAPS_PER_SEC, Pacing.ACTIVE_MINUTES, Pacing.ACTIVE_HAND),
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


# --- Twisty model (task 1.1) -------------------------------------------------

func seeded_rng(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


func test_cube_shapes() -> void:
	for n in range(PuzzleShapes.MIN_CUBE, PuzzleShapes.MAX_CUBE + 1):
		var cube := PuzzleShapes.cube(n)
		check(cube.piece_count() == n * n * n - (n - 2) * (n - 2) * (n - 2), "%dx%d has n³ − (n−2)³ pieces" % [n, n])
		check(cube.is_solved(), "%dx%d starts solved" % [n, n])
		var stickers := 0
		for normals in cube.sticker_normals:
			stickers += normals.size()
		check(stickers == 6 * n * n, "%dx%d has 6n² stickers" % [n, n])
		check(cube.scramble_widths == maxi(1, n / 2), "%dx%d scrambles with widths up to %d" % [n, n, maxi(1, n / 2)])


func test_cube_moves_return_to_solved() -> void:
	for n in range(PuzzleShapes.MIN_CUBE, PuzzleShapes.MAX_CUBE + 1):
		var cube := PuzzleShapes.cube(n)
		for face in cube.face_names.size():
			for width in range(1, n):
				var move := cube.make_move(face, 1, width)
				for i in 4:
					cube.apply(move)
					check(cube.is_solved() == (i == 3), "%dx%d %s applied %d× solved = %s" % [n, n, cube.notation(move), i + 1, i == 3])
		var sexy := cube.parse_sequence("R U R' U'")
		for i in 6:
			cube.apply_all(sexy)
		check(cube.is_solved(), "%dx%d (R U R' U')×6 = solved" % [n, n])


func test_cube_scramble_and_inverse() -> void:
	for n in range(PuzzleShapes.MIN_CUBE, PuzzleShapes.MAX_CUBE + 1):
		var cube := PuzzleShapes.cube(n)
		var moves := cube.scramble(50, seeded_rng(n))
		check(moves.size() == 50, "%dx%d scramble has 50 moves" % [n, n])
		check(not cube.is_solved(), "%dx%d is not solved after a 50-move scramble" % [n, n])
		var no_repeats := true
		for i in range(1, moves.size()):
			no_repeats = no_repeats and moves[i]["face"] != moves[i - 1]["face"]
		check(no_repeats, "%dx%d scramble never turns the same face twice in a row" % [n, n])
		cube.apply_all(cube.inverse_sequence(moves))
		check(cube.is_solved(), "%dx%d scramble + inverse = solved" % [n, n])


func test_cube_turn_direction() -> void:
	var cube := PuzzleShapes.cube(3)
	var f := cube.face_names.find("F")
	var u := cube.face_names.find("U")
	cube.apply(cube.parse("U"))
	check(cube.color_at(Vector3(0, 1, 1), f) == PuzzleShapes.COLOR_RED, "U moves the R face's stickers onto F")
	cube.reset()
	cube.apply(cube.parse("R"))
	check(cube.color_at(Vector3(1, 1, 0), u) == PuzzleShapes.COLOR_GREEN, "R moves the F face's stickers onto U")
	check(cube.color_at(Vector3(-1, 1, 0), u) == PuzzleShapes.COLOR_WHITE, "R leaves the L side of U alone")
	cube.reset()
	var big := PuzzleShapes.cube(5)
	var fu := big.face_names.find("U")
	big.apply(big.parse("Rw"))
	check(big.color_at(Vector3(1, 2, 0), fu) == PuzzleShapes.COLOR_GREEN, "Rw turns the second layer too")
	check(big.color_at(Vector3(0, 2, 0), fu) == PuzzleShapes.COLOR_WHITE, "Rw leaves the middle layer alone")


func test_cube_notation() -> void:
	var cube := PuzzleShapes.cube(7)
	var r := cube.face_names.find("R")
	var u := cube.face_names.find("U")
	check(cube.notation(cube.make_move(r, 1)) == "R", "R")
	check(cube.notation(cube.make_move(r, -1)) == "R'", "R'")
	check(cube.notation(cube.make_move(r, 3)) == "R'", "3 quarter turns = R'")
	check(cube.notation(cube.make_move(r, 2)) == "R2", "R2")
	check(cube.notation(cube.make_move(r, 1, 2)) == "Rw", "Rw")
	check(cube.notation(cube.make_move(u, -1, 2)) == "Uw'", "Uw'")
	check(cube.notation(cube.make_move(r, 1, 3)) == "3Rw", "3Rw")
	check(cube.notation(cube.make_move(u, 2, 3)) == "3Uw2", "3Uw2")
	check(cube.notation(cube.make_move(r, 1, 1, 1)) == "2R", "SiGN inner slice 2R")
	check(cube.notation_sequence(cube.parse_sequence("R U R' U'")) == "R U R' U'", "sequence round trip")
	check(cube.parse("X").is_empty(), "unknown face is rejected")
	check(PuzzleShapes.cube(3).parse("3Rw").is_empty(), "3Rw doesn't exist on a 3x3")
	for n in range(PuzzleShapes.MIN_CUBE, PuzzleShapes.MAX_CUBE + 1):
		var model := PuzzleShapes.cube(n)
		var rng := seeded_rng(100 + n)
		var all_round_trip := true
		for i in 40:
			var move := model.random_move(rng)
			all_round_trip = all_round_trip and model.parse(model.notation(move)) == move
		check(all_round_trip, "%dx%d notation -> parse round-trips random moves" % [n, n])


# --- 3D puzzle view (task 1.2) -----------------------------------------------

func mouse_button(pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	return event


func test_puzzle_ids() -> void:
	for n in range(PuzzleShapes.MIN_CUBE, PuzzleShapes.MAX_CUBE + 1):
		var model := PuzzleShapes.from_id("%dx%d" % [n, n])
		check(model != null and model.size == n, "'%dx%d' builds a %d-cube" % [n, n, n])
	check(PuzzleShapes.from_id("8x8") == null, "8x8 doesn't exist")
	check(PuzzleShapes.from_id("3x4") == null, "3x4 doesn't exist")
	check(PuzzleShapes.from_id("banana") == null, "nonsense id gives null")


func test_puzzle_view_click_and_drag() -> void:
	var view: PuzzleView3D = load("res://scenes/puzzle_view_3d.tscn").instantiate()
	root.add_child(view)
	check(view.puzzle_id == PuzzleView3D.DEFAULT_PUZZLE and view.model != null, "the view starts on the default puzzle")
	var taps := [0]
	view.tapped.connect(func(_at: Vector2) -> void: taps[0] += 1)
	view._gui_input(mouse_button(true, Vector2(100, 100)))
	view._gui_input(mouse_button(false, Vector2(103, 102)))
	check(taps[0] == 1, "a click (moving < 6 px) taps")
	view._gui_input(mouse_button(true, Vector2(100, 100)))
	view._gui_input(mouse_button(false, Vector2(130, 100)))
	check(taps[0] == 1, "a drag doesn't tap")
	view.set_puzzle("5x5")
	check(view.puzzle_id == "5x5" and view.model.size == 5, "set_puzzle switches puzzles")
	check(view._bodies.multimesh.instance_count == 98, "5x5 draws 98 pieces")
	check(view._stickers.multimesh.instance_count == 150, "5x5 draws 150 stickers")
	view.show_solved()
	view.finish_animations()
	check(view.model.is_solved(), "show_solved ends on a solved puzzle")
	view.free()


func test_clicking_the_puzzle_taps() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	var tap_moves := game.get_tap_moves()
	view._gui_input(mouse_button(true, Vector2(150, 150)))
	view._gui_input(mouse_button(false, Vector2(150, 150)))
	check_near(game.total_moves, tap_moves, "clicking the puzzle calls Game.tap()")
	main.free()
	game.reset_state()


# --- Animated turns (task 1.3) -----------------------------------------------

func new_view() -> PuzzleView3D:
	var view: PuzzleView3D = load("res://scenes/puzzle_view_3d.tscn").instantiate()
	root.add_child(view)
	return view


## Sticker instances whose drawn colour isn't what the model has at that spot.
func sticker_mismatches(view: PuzzleView3D, unturn: bool = false) -> int:
	var bad := 0
	for sticker: Dictionary in view.drawn_stickers(unturn):
		var face := view.model.face_index(sticker["normal"])
		var expected := view.model.color_at(sticker["position"], face)
		if expected < 0 or not (sticker["color"] as Color).is_equal_approx(PuzzleShapes.CUBE_COLORS[expected]):
			bad += 1
	return bad


func test_view_matches_model_after_1000_moves() -> void:
	for id: String in ["3x3", "4x4", "7x7"]:
		var view := new_view()
		view.set_puzzle(id)
		check(sticker_mismatches(view) == 0, "%s: drawn stickers match the model at the start" % id)
		view.set_speed(5.0)
		var reference := PuzzleShapes.from_id(id)
		reference.orientations = view.model.orientations.duplicate()
		view.record_moves = true
		var mid_turn_mismatches := 0
		for i in 1000:
			view.scramble_step()
			if i % 3 == 0:
				view._process(0.03)  # stop part-way through turns now and then
				mid_turn_mismatches += sticker_mismatches(view, true)
		view._process(5.0)  # let the queue run out the normal way
		view._process(0.0)
		check(mid_turn_mismatches == 0, "%s: mid-turn, the drawing is the model plus the half-done turn" % id)
		check(view.is_idle(), "%s: nothing left to animate" % id)
		check(sticker_mismatches(view) == 0, "%s: after 1,000 moves every drawn sticker matches the model" % id)
		reference.apply_all(view.recorded_moves)
		check(reference.orientations == view.model.orientations, "%s: no move was lost or reordered" % id)
		check(view.recorded_moves.size() == 1000, "%s: all 1,000 moves were applied (got %d)" % [id, view.recorded_moves.size()])
		view.free()


func test_view_queue_stays_bounded() -> void:
	var view := new_view()
	view.set_speed(5.0)
	var longest := 0
	for i in 1000:
		view.scramble_step()
		longest = maxi(longest, view.queued_moves())
	check(longest <= PuzzleView3D.MAX_QUEUE, "1,000 moves in one frame never queue more than MAX_QUEUE")
	view.finish_animations()
	view.set_speed(1000.0)
	check(view.speed_mode, "1,000 moves/s switches to speed mode")
	for i in 1000:
		view.scramble_step()
	check(view.queued_moves() == 0, "speed mode doesn't queue at all")
	view._process(0.016)
	check(sticker_mismatches(view) == 0, "speed mode drawing matches the model after a frame")
	view.show_solved()
	check(view.model.is_solved() and view.is_idle(), "a solve in speed mode snaps to solved without a replay")
	view.scramble_step()
	view._process(0.016)
	check(not view.model.is_solved(), "speed mode keeps turning right after a solve (no hold)")
	view.show_solved()
	check(not view.model.is_solved(), "back-to-back solves in speed mode don't reset it every frame")
	view.set_speed(10.0)
	check(view.speed_mode, "speed mode stays on between the two thresholds")
	view.set_speed(5.0)
	check(not view.speed_mode, "speed mode turns off below SPEED_MODE_OFF")
	view.free()


func test_view_solve_replays_backwards() -> void:
	var view := new_view()
	view.set_speed(5.0)
	for i in 12:
		view.scramble_step()
	view._process(0.05)
	check(not view.model.is_solved(), "scrambled before the solve")
	view.show_solved()
	check(not view.is_idle(), "the solve queues a backwards replay")
	var elapsed := 0.0
	while not view.is_idle() and elapsed < 3.0:
		view._process(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	check(view.model.is_solved(), "the replay ends solved")
	check(elapsed <= PuzzleView3D.REWIND_TIME + 0.05, "the replay takes at most REWIND_TIME (took %.2f s)" % elapsed)
	check(sticker_mismatches(view) == 0, "drawing matches the solved model")
	view.scramble_step()
	check(view.queued_moves() == 0, "moves are held off while the solved puzzle is shown")
	view.free()


# --- Stage and camera (task 1.4) ---------------------------------------------

func mouse_motion(position: Vector2, relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	return event


func test_view_drag_rotates_and_never_taps() -> void:
	var view := new_view()
	var taps := [0]
	view.tapped.connect(func(_at: Vector2) -> void: taps[0] += 1)
	view._gui_input(mouse_button(true, Vector2(100, 100)))
	view._gui_input(mouse_motion(Vector2(110, 103), Vector2(10, 3)))
	view._gui_input(mouse_motion(Vector2(130, 110), Vector2(20, 7)))
	check(view.drag_offset().x > 0.2, "dragging right turns the view")
	check(view.drag_offset().y > 0.05, "dragging down tilts the view")
	view._gui_input(mouse_button(false, Vector2(130, 110)))
	check(taps[0] == 0, "a drag of more than 6 px doesn't tap")
	# Out and back to the start is still a drag.
	view._gui_input(mouse_button(true, Vector2(100, 100)))
	view._gui_input(mouse_motion(Vector2(120, 100), Vector2(20, 0)))
	view._gui_input(mouse_motion(Vector2(100, 100), Vector2(-20, 0)))
	view._gui_input(mouse_button(false, Vector2(100, 100)))
	check(taps[0] == 0, "dragging away and back doesn't tap")
	# A wiggle within 6 px is still a click.
	view._gui_input(mouse_button(true, Vector2(100, 100)))
	view._gui_input(mouse_motion(Vector2(104, 101), Vector2(4, 1)))
	view._gui_input(mouse_button(false, Vector2(104, 101)))
	check(taps[0] == 1, "moving less than 6 px still taps")
	var before := view.drag_offset().length()
	for i in 180:
		view._process(1.0 / 60.0)
	check(view.drag_offset().length() < before * 0.05, "a released drag springs back")
	view.free()


func test_view_ticker() -> void:
	var view := new_view()
	check(view.ticker_text().split(" ", false).size() <= PuzzleView3D.TICKER_LENGTH, "ticker starts with at most 8 moves")
	view.set_speed(5.0)
	for i in 20:
		view.scramble_step()
	view.finish_animations()
	var tokens := view.ticker_text().split(" ", false)
	check(tokens.size() == PuzzleView3D.TICKER_LENGTH, "ticker shows the last 8 moves")
	var all_valid := true
	for token in tokens:
		all_valid = all_valid and not view.model.parse(token).is_empty()
	check(all_valid, "every ticker entry is valid notation")
	view.show_solved()
	view.finish_animations()
	check(view.ticker_text() == "", "the ticker clears on a solve")
	view.free()


# --- Graphics settings (task 1.5) --------------------------------------------

func test_settings_store() -> void:
	clean_test_saves()
	var path := TEST_SAVE_DIR.path_join("settings.cfg")
	var settings := GameSettings.new()
	settings.path = path
	settings.reset_to_defaults()
	check(settings.get_value("quality") == "high" and is_equal_approx(settings.get_value("music_volume"), 0.5), "defaults")
	check(settings.set_value("quality", "low"), "a valid value is accepted")
	check(not settings.set_value("quality", "ultra"), "an invalid choice is rejected")
	check(settings.set_value("sfx_volume", 3.0) and is_equal_approx(settings.get_value("sfx_volume"), 1.0), "volumes are clamped")
	settings.set_value("reduce_motion", true)
	settings.set_value("notation", "scientific")
	settings.set_value("music_mode", "shuffle")
	var reloaded := GameSettings.new()
	reloaded.path = path
	reloaded.reset_to_defaults()
	reloaded.load_settings()
	check(reloaded.get_value("quality") == "low" and reloaded.get_value("reduce_motion") == true
			and reloaded.get_value("notation") == "scientific" and reloaded.get_value("music_mode") == "shuffle"
			and is_equal_approx(reloaded.get_value("sfx_volume"), 1.0), "settings survive a restart")
	# A save reset never touches settings.
	var g := save_game_at(TEST_SAVE_DIR.path_join("save.json"))
	g.save_game()
	g.wipe_save()
	check(FileAccess.file_exists(path), "wiping the save keeps settings.cfg")
	g.free()
	# Files from task 1.5 (GraphicsConfig) and hand-edited junk.
	write_text(path, "[graphics]\nquality=\"low\"\n[other]\nkeep=1\n")
	var legacy := GameSettings.new()
	legacy.path = path
	legacy.reset_to_defaults()
	legacy.load_settings()
	check(legacy.get_value("quality") == "low", "a 1.5-era graphics setting still loads")
	legacy.set_value("notation", "short")
	var config := ConfigFile.new()
	config.load(path)
	check(config.get_value("other", "keep", 0) == 1, "saving keeps unknown sections")
	write_text(path, "[graphics]\nquality=\"ultra\"\n")
	var junk := GameSettings.new()
	junk.path = path
	junk.reset_to_defaults()
	junk.load_settings()
	check(junk.get_value("quality") == "high", "an invalid stored value falls back to the default")
	for node: GameSettings in [settings, reloaded, legacy, junk]:
		node.free()
	clean_test_saves()


func test_view_graphics_quality() -> void:
	var view := new_view()
	view.set_puzzle("7x7")
	var high_triangles := view.body_triangles()
	view.set_speed(5.0)
	for i in 10:
		view.scramble_step()
	view._process(0.05)
	view.set_graphics("low")
	check(view._viewport.msaa_3d == Viewport.MSAA_DISABLED, "Low turns MSAA off")
	check(not view._backdrop.visible and not view._shadow.visible, "Low hides the stage glow and shadow")
	check(view.body_triangles() * 4 < high_triangles, "Low pieces use far fewer triangles")
	check(view._bodies.multimesh.mesh == view._body_mesh, "the pieces switch to the Low mesh")
	view.finish_animations()
	check(sticker_mismatches(view) == 0, "switching quality keeps the puzzle's state")
	view.set_graphics("high")
	check(view._viewport.msaa_3d == Viewport.MSAA_4X and view._backdrop.visible, "High turns them back on")
	check(view.body_triangles() == high_triangles, "High restores rounded pieces")
	view.free()


func test_stage_and_background() -> void:
	# Task V.3: the puzzle sits on a cubing mat, a rim light makes its outline pop, and a desk background (High only).
	var slab := PuzzleMeshes.rounded_slab(Vector3(2.0, 0.1, 1.5), 0.05)
	check(slab.get_aabb().size.is_equal_approx(Vector3(4.0, 0.2, 3.0)) and slab.get_aabb().get_center().is_zero_approx(),
			"a rounded slab is as big as asked, centred: %s" % slab.get_aabb())
	var arrays := slab.surface_get_arrays(0)
	var flat_top := 0
	var tilted := 0
	for i in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		var v: Vector3 = arrays[Mesh.ARRAY_VERTEX][i]
		if is_equal_approx(v.y, 0.1) and absf(v.x) <= 1.95 + 0.0001 and absf(v.z) <= 1.45 + 0.0001:
			flat_top += 1
			if (arrays[Mesh.ARRAY_NORMAL][i] as Vector3).dot(Vector3.UP) < 0.999:  # normals are stored compressed
				tilted += 1
	check(flat_top > 0 and tilted == 0, "the slab's flat top is lit evenly: every normal there points up (%d of %d tilted)" % [tilted, flat_top])
	var view := new_view()
	for id: String in ["2x2", "3x3", "7x7", "megaminx"]:
		view.set_puzzle(id)
		var extent: float = view._extent()
		var lowest := INF
		for i in view.model.home_positions.size():
			var home: Vector3 = view.model.home_positions[i]
			if view.model.piece_geometry.is_empty():
				lowest = minf(lowest, home.y - PuzzleView3D.CUBIE_HALF)
			else:
				for polygon: PackedVector3Array in view.model.piece_geometry[i]["body"]:
					for v in polygon:
						lowest = minf(lowest, home.y + v.y)
		var gap: float = lowest - view.mat_top()  # both in the puzzle's tilted frame (Floor has its basis)
		check(view._floor.visible and gap > 0.0 and gap < extent * 0.05,
				"%s sits just above its mat (gap %.3f of width %.2f)" % [id, gap, extent])
		check(view._floor.basis.is_equal_approx(view._base_puzzle), "%s: the mat has the puzzle's resting tilt" % id)
		var mat_size: Vector3 = (view._mat.mesh as ArrayMesh).get_aabb().size
		check(mat_size.x > extent and mat_size.z > extent, "%s: the mat is wider and deeper than the puzzle" % id)
		var outside := 0
		for corner: Vector3 in view._mat_corners():
			if not view._camera.is_position_in_frustum(corner):
				outside += 1
		check(view._mat_corners().size() == 8 and outside == 0, "%s: the camera sees the whole mat (%d corners outside)" % [id, outside])
	view.squash()
	view._process(0.02)
	check(view._floor.scale.is_equal_approx(Vector3.ONE) and not view._puzzle.scale.is_equal_approx(Vector3.ONE),
			"a squash squashes the puzzle, not the mat")
	view._drag_pitch = 0.4
	view._pressing = true
	view._process(0.02)
	check(view._floor.basis.is_equal_approx(view._puzzle.basis.orthonormalized()) and view._floor.scale.is_equal_approx(Vector3.ONE)
			and not view._floor.basis.is_equal_approx(view._base_puzzle),
			"a look-around drag tilts the mat with the puzzle, so the puzzle never dips into it")
	view._pressing = false
	check(view._rim_light.visible, "High has the rim light")
	view.set_graphics("low")
	check(not view._rim_light.visible and view._floor.visible, "Low drops the rim light, keeps the mat (a few triangles)")
	view.floor_enabled = false
	check(not view._floor.visible, "floor_enabled = false hides the mat")
	view.free()
	var chip: PuzzleChip = load("res://scenes/puzzle_chip.tscn").instantiate()
	root.add_child(chip)
	check(not chip.view.floor_enabled, "the small puzzle chips have no mat")
	chip.free()
	# The background: the shader on High, a flat bg colour on Low, still with Reduce motion.
	var settings: GameSettings = root.get_node("Settings")
	settings.persistence_enabled = false
	settings.reset_to_defaults()
	settings.apply_all()
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var background: ColorRect = main.get_node("%Background")
	var material := background.material as ShaderMaterial
	check(material != null and material.shader.resource_path.ends_with("ui_background.gdshader"), "High draws the desk background")
	settings.set_value("reduce_motion", true)
	check(is_zero_approx(float(main._background_material.get_shader_parameter("drift"))), "Reduce motion stops the bokeh drifting")
	settings.set_value("quality", "low")
	check(background.material == null and _colour_distance(background.color, background.get_theme_color(&"bg", &"Palette")) < 0.003,
			"Low: the flat bg colour, no shader")
	settings.set_value("quality", "high")
	check(background.material == main._background_material, "High brings it back")
	main._refresh()  # places the lamp (every refresh, so it follows any layout change)
	var lamp: Vector2 = main._background_material.get_shader_parameter("lamp_center")
	var expected: Vector2 = (main.get_node("%PuzzleView") as Control).get_global_rect().get_center() / main.get_viewport_rect().size
	check(lamp.is_equal_approx(expected), "the lamp glow sits behind the puzzle: %s" % lamp)
	main.free()
	settings.reset_to_defaults()
	settings.apply_all()
	settings.persistence_enabled = true
	game.reset_state()


func test_settings_panel() -> void:
	var settings: GameSettings = root.get_node("Settings")
	settings.persistence_enabled = false  # never write the real settings.cfg from tests
	settings.reset_to_defaults()
	settings.apply_all()
	clean_test_saves()
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.save_path = TEST_SAVE_DIR.path_join("save.json")
	game.reset_state()
	game.cheat_add_solves(1500.0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var panel: Control = main.get_node("%SettingsPanel")  # untyped: SettingsPanel uses autoload names, which the runner compiles before they exist
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	var fx: FxLayer = main.get_node("%FxLayer")
	(main.get_node("%SettingsButton") as Button).pressed.emit()
	check(panel.visible, "the Settings button opens the panel")
	main._unhandled_input(key_event(KEY_SPACE, true, false))
	check_near(game.total_moves, 0.0, "Space doesn't tap while the panel is open")
	# Graphics
	var graphics: OptionButton = panel._options["quality"]
	for i in graphics.item_count:
		if graphics.get_item_metadata(i) == "low":
			graphics.select(i)
			graphics.item_selected.emit(i)
	check(settings.get_value("quality") == "low" and view.graphics_quality == "low", "choosing Graphics: Low applies it")
	# Reduce motion
	panel._reduce_motion.button_pressed = true
	check(settings.get_value("reduce_motion") == true, "the Reduce motion switch sets the setting")
	check(view.reduce_motion and not view.sway_enabled and not fx.particles_enabled, "Reduce motion turns off sway and particles")
	view.squash()
	view._process(1.0 / 60.0)
	check(is_equal_approx(view._puzzle.scale.y, view._puzzle.scale.x), "Reduce motion: no squash")
	view.set_speed(1000.0)
	for i in 30:
		view._process(0.05)
	check(view._wobble == 0.0, "Reduce motion: no speed-mode wobble")
	# Numbers
	settings.set_value("notation", "scientific")
	check(Num.format(1500.0) == "1.50e3", "scientific notation")
	check(Num.format(1e15) == "1.00e15" and Num.format(1e3) == "1.00e3" and Num.format(999999.0) == "1.00e6"
			and Num.format(9.9951e14) == "1.00e15", "the mantissa never reads 10.00 (%s, %s)" % [Num.format(1e15), Num.format(999999.0)])
	main._animate_counter(1.0)
	check((main.get_node("%SolvesLabel") as Label).text == "1.50e3", "the UI uses the chosen notation")
	settings.set_value("notation", "short")
	check(Num.format(1500.0) == "1.50K", "back to short notation")
	check(Num.format(999999.0) == "1.00M" and Num.format(99995.0) == "100.0K" and Num.format(9.9999e35) == "1.00e36"
			and Num.format(1e6) == "1.00M", "rounding moves up a unit, never 1000.0K (%s, %s)" % [Num.format(999999.0), Num.format(99995.0)])
	# Volumes and music
	(panel._sliders["sfx_volume"] as HSlider).value = 0.4
	check(absf(root.get_node("Audio").get_bus_volume(AudioManager.SFX_BUS) - 0.4) < 0.01, "the SFX slider sets the bus volume")
	check(panel._jukebox.get_child_count() == Content.TRACKS.size(), "the Jukebox lists every track")
	panel.play_track("practice_room")
	check(settings.get_value("music_mode") == "loop" and settings.get_value("loop_track") == "practice_room", "Jukebox play loops that track")
	# Reset save
	panel._ask_reset()
	check(panel._reset_dialog.dialog_text.contains("1.50K Solves") and panel._reset_dialog.dialog_text.contains("settings are kept"),
			"the reset dialog names what is lost and what is kept")
	panel._reset_save()
	check_near(game.solves, 0.0, "confirming the reset wipes the save")
	check(settings.get_value("reduce_motion") == true, "...and keeps the settings")
	check(not panel.visible, "the panel closes after the reset")
	panel.open()
	panel._unhandled_input(key_event(KEY_ESCAPE, true, false))
	main.free()
	settings.reset_to_defaults()
	settings.apply_all()
	settings.persistence_enabled = true
	game.save_path = GameState.SAVE_PATH
	game.reset_state()
	clean_test_saves()

func test_theme_is_used_everywhere() -> void:
	check(ProjectSettings.get_setting("gui/theme/custom") == "res://ui/theme.tres", "ui/theme.tres is the project theme")
	var theme: Theme = load("res://ui/theme.tres")
	check(theme != null and theme.default_font != null, "the theme loads with its font (Inter)")
	check(FileAccess.file_exists("res://assets/CREDITS.md") and FileAccess.get_file_as_string("res://assets/CREDITS.md").contains("InterVariable.ttf"),
			"the font is credited in assets/CREDITS.md")
	var variation_regex := RegEx.create_from_string("theme_type_variation = &\"(\\w+)\"")
	for scene_name in DirAccess.get_files_at("res://scenes"):
		if not scene_name.ends_with(".tscn"):
			continue
		var text := FileAccess.get_file_as_string("res://scenes".path_join(scene_name))
		# Style belongs in the theme. A deliberate exception must be listed here with a reason.
		check(not text.contains("theme_override_"), "%s has no per-node theme overrides" % scene_name)
		for found in variation_regex.search_all(text):
			var variation := found.get_string(1)
			check(theme.get_type_variation_base(variation) != &"", "%s uses theme variation %s, which the theme defines" % [scene_name, variation])


func test_theme_materials() -> void:
	# Task V.2: one palette of tokens (Palette/colors/*), three depth levels, buttons that press down, category stickers.
	var theme: Theme = load("res://ui/theme.tres")
	var tokens := ["bg", "inset", "surface_1", "surface_2", "surface_3", "text", "text_dim", "text_faint", "buy",
			"buy_dim", "gold"]
	for category: StringName in IconSticker.CATEGORIES:
		tokens.append("cat_%s" % category)
	for token: String in tokens:
		check(theme.has_color(StringName(token), &"Palette"), "the palette has %s" % token)
	var pal := func(token: String) -> Color: return theme.get_color(StringName(token), &"Palette")
	check(_colour_distance(pal.call("buy"), Color("#3ccf8e")) < 0.003, "buy is the one green, #3ccf8e (CLAUDE.md rule 9)")
	var levels := ["bg", "surface_1", "surface_2", "surface_3"]
	for i in levels.size() - 1:
		check(pal.call(levels[i + 1]).get_luminance() - pal.call(levels[i]).get_luminance() > 0.025,
				"%s is clearly lighter than %s" % [levels[i + 1], levels[i]])
	# Category colours: told apart from each other and from the buy green at a glance (D15b).
	var cats: Array[Color] = []
	for category: StringName in IconSticker.CATEGORIES:
		if category != &"locked":
			cats.append(pal.call("cat_%s" % category))
	for i in cats.size():
		check(_colour_distance(cats[i], pal.call("buy")) > 0.35, "category colour %d is far from the buy green" % i)
		for j in range(i + 1, cats.size()):
			check(_colour_distance(cats[i], cats[j]) > 0.3, "category colours %d and %d differ" % [i, j])
	# The styles use the tokens: background < panels < cards.
	var main_scene := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var bg: Color = pal.call("bg")
	var bg_line := "color = Color(%s, %s, %s, 1)" % [snappedf(bg.r, 0.0001), snappedf(bg.g, 0.0001), snappedf(bg.b, 0.0001)]
	check(main_scene.contains(bg_line), "the main screen's background is the bg token")
	check(FileAccess.get_file_as_string("res://scenes/solve_station.tscn").contains(bg_line), "...and the Solve Station's")
	for panel: Array in [[&"TopBar", &"panel"], [&"SidePanel", &"panel"], [&"PanelContainer", &"panel"],
			[&"TabContainer", &"panel"], [&"NewsPanel", &"panel"]]:
		var box := theme.get_stylebox(panel[1], panel[0]) as StyleBoxFlat
		check(box.bg_color.is_equal_approx(pal.call("surface_1")), "%s is a level-1 panel (surface_1)" % panel[0])
		check(box.shadow_size >= 6 and box.shadow_color.a > 0.2, "%s floats on a soft shadow" % panel[0])
	# V.4: a shelf puzzle has no card of its own; its little stand is the level-2 slab.
	for card: StringName in [&"ShopCard", &"PuzzleStand"]:
		var box := theme.get_stylebox(&"panel" if card == &"PuzzleStand" else &"normal", card) as StyleBoxFlat
		check(box.bg_color.is_equal_approx(pal.call("surface_2")), "%s is a level-2 card (surface_2)" % card)
		check(box.shadow_offset.y >= 2.0 and box.border_width_top >= 1, "%s has a slab under it and a lit top edge" % card)
	# Pressing sinks the face (and its text) into the slab without changing the button's size.
	for type_name: StringName in [&"Button", &"PrimaryButton", &"GoldenButton", &"IconButton", &"ShopCard", &"ToggleChip"]:
		var normal := theme.get_stylebox(&"normal", type_name) as StyleBoxFlat
		var pressed := theme.get_stylebox(&"pressed", type_name) as StyleBoxFlat
		var down := -pressed.expand_margin_top
		check(down >= 1.0 and is_equal_approx(pressed.expand_margin_bottom, down), "%s presses down %d px" % [type_name, down])
		check(is_equal_approx(pressed.shadow_offset.y, normal.shadow_offset.y - down), "%s: the slab shrinks as much" % type_name)
		check(is_equal_approx(pressed.get_minimum_size().y, normal.get_minimum_size().y), "%s: pressing doesn't change its size" % type_name)
		# Cards lay their content out by anchors (no content margins), so shop_card.gd etc. sink it themselves.
		if type_name != &"ShopCard":
			check(is_equal_approx(pressed.content_margin_top, normal.content_margin_top + down), "%s: the text moves down with it" % type_name)
	# Icon stickers: the category's colour, white glyph (dark on the light ones).
	var sticker: IconSticker = load("res://scenes/icon_sticker.tscn").instantiate()
	root.add_child(sticker)
	sticker.texture = Content.icon("friend")
	for category: StringName in IconSticker.CATEGORIES:
		sticker.category = category
		check(sticker.self_modulate.is_equal_approx(pal.call("cat_%s" % category)), "a %s sticker is its colour" % category)
	sticker.category = &"station"
	check((sticker.get_node("%Glyph") as TextureRect).modulate.get_luminance() < 0.3, "a white sticker gets a dark glyph")
	sticker.category = &"trophies"
	sticker.muted = true
	check((sticker.get_node("%Glyph") as TextureRect).modulate == Color.WHITE
			and sticker.self_modulate.get_luminance() < pal.call("cat_trophies").get_luminance() - 0.2,
			"a muted (can't buy) sticker is darker and keeps a white glyph, so it stays readable when dimmed")
	sticker.muted = false
	sticker.category = &"helpers"
	check((sticker.get_node("%Glyph") as TextureRect).modulate == Color.WHITE and (sticker.get_node("%Glyph") as TextureRect).texture != null,
			"a blue sticker gets the white glyph")
	sticker.free()
	# Pressed cards sink their content with the face, and it comes back up when the card is disabled mid-press.
	for scene: String in ["res://scenes/shop_card.tscn", "res://scenes/upgrade_tile.tscn", "res://scenes/perk_node.tscn"]:
		var card: Button = load(scene).instantiate()
		root.add_child(card)
		card.set_view({"icon": Content.icon("friend"), "affordable": true, "status": "available", "cost": "1"})
		var content: Control = card.get_node("%Content")
		var rest := content.position.y
		card.sync_press(BaseButton.DRAW_PRESSED)
		check(is_equal_approx(content.position.y, rest + 2.0), "%s: held, the content sinks 2 px" % scene.get_file())
		card.set_view({"icon": Content.icon("friend"), "affordable": false, "status": "available", "cost": "1"})
		card.sync_press()  # disabled now: Godot never sends button_up, the draw mode is DRAW_DISABLED
		check(is_equal_approx(content.position.y, rest), "%s: disabled mid-press, it comes back up" % scene.get_file())
		card.free()
	check(FileAccess.get_file_as_string("res://assets/CREDITS.md").contains("assets/images/ui/sticker.svg"), "the sticker texture is credited")
	# On the main screen: helpers blue, Lab projects and methods purple, upgrades orange, a locked helper grey.
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._refresh()
	var sticker_of := func(card: Node, path: String) -> StringName: return (card.get_node(path) as IconSticker).category
	var first_visible := func(cards: Dictionary, locked: bool) -> Node:
		for card: Node in cards.values():
			if (card as Control).visible and (not locked or card.get("locked")):
				return card
		return null
	var friend_card: Node = main._helper_cards[Content.BUILDINGS[0]["id"]]
	check(sticker_of.call(friend_card, "%IconTile") == &"helpers", "a helper's sticker is blue (helpers)")
	var locked_card: Node = first_visible.call(main._helper_cards, true)
	check(locked_card != null and sticker_of.call(locked_card, "%IconTile") == &"locked", "the next locked helper's sticker is grey")
	game.cheat_add_solves(1e15)  # every Lab project and the next method show up
	main._refresh()
	var lab_card: Node = first_visible.call(main._lab_cards, false)
	check(lab_card != null and sticker_of.call(lab_card, "%IconTile") == &"lab", "a Lab project's sticker is purple")
	var method_tile: Node = first_visible.call(main._method_tiles, false)
	check(method_tile != null and sticker_of.call(method_tile, "%Icon") == &"lab", "a method (Lab research) tile is purple")
	check(sticker_of.call(main._upgrade_tiles.values()[0], "%Icon") == &"upgrades", "an upgrade tile is orange")
	main.free()
	game.reset_state()


## How far apart two colours look, roughly (RGB distance, 0..√3).
func _colour_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func test_top_bar_stats() -> void:
	# Task V.1: the top bar shows numbers as an icon + value (+ unit) chips, never "·"-joined sentences.
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.cheat_add_solves(1e30)
	game.trophies = 12
	game.flow = {"mult": 2.0, "left": 30.0}
	var buff_def: Dictionary = Content.GOLDEN["buffs"][0]
	game.buff = {"id": buff_def["id"], "mult": 7.0, "left": 20.0}
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._shown_solves = game.solves
	main._animate_counter(0.0)
	main._refresh()
	main._refresh_golden()
	check((main.get_node("%SolvesLabel") as Label).text == Num.format(1e30), "the counter shows just the number (the caption says Solves)")
	var top_bar: Control = main.get_node("Margin/Rows/TopBar")
	var texts: Array[String] = []
	_collect_texts(top_bar, texts)
	for text in texts:
		check(not text.contains("·"), "no '·'-joined stat in the top bar: '%s'" % text)
	for chip_name in ["SolvesRate", "MovesRate", "StreakChip", "FlowChip", "BuffChip"]:
		var chip: StatChip = main.get_node("%" + chip_name)
		check(chip.icon != null, "%s has an icon" % chip_name)
	var flow_chip: StatChip = main.get_node("%FlowChip")
	check(flow_chip.visible and flow_chip.get_text().begins_with("×2"), "the Flow chip shows its multiplier: %s" % flow_chip.get_text())
	var buff_chip: StatChip = main.get_node("%BuffChip")
	check(buff_chip.visible and buff_chip.get_text() == "×7 20s" and String(buff_def["name"]) in buff_chip.tooltip_text,
			"the Golden buff chip: %s (%s)" % [buff_chip.get_text(), buff_chip.tooltip_text])
	var stats: Node = main.get_node("%Stats")
	check(stats.get_child(0).name == "SolvesRate" and stats.get_child(1).name == "BuffChip",
			"the timed Golden buff comes right after solves/s, so it's the last chip to be left out")
	var theme: Theme = load("res://ui/theme.tres")
	var display: FontVariation = theme.get_font(&"font", &"CounterLabel")
	check(not display.fallbacks.is_empty(), "the display font falls back to Inter for glyphs it lacks (✓, →)")
	check(FileAccess.get_file_as_string("res://assets/CREDITS.md").contains("FredokaVariable.ttf"), "Fredoka is credited")
	check((main.get_node("%SettingsButton") as Button).icon != null and (main.get_node("%SettingsButton") as Button).text == "",
			"Settings is an icon button")
	# FitRow: children that don't fit whole are left out (not cut), and the row never widens the bar.
	var row := FitRow.new()
	root.add_child(row)
	check(row.get_combined_minimum_size().x == 0.0, "a FitRow asks for no width")
	for i in 3:
		var block := Control.new()
		block.custom_minimum_size = Vector2(100, 20)
		row.add_child(block)
	row.size = Vector2(230, 30)
	check(row.fitting_children().size() == 2, "230 px holds two 100 px children with a 12 px gap, not three")
	row.size = Vector2(330, 30)
	check(row.fitting_children().size() == 3, "...and all three at 330 px")
	row.free()
	var chip: StatChip = load("res://scenes/stat_chip.tscn").instantiate()
	root.add_child(chip)
	chip.set_stat("+73", "/s")
	check(chip.get_text() == "+73 /s", "a chip reads value + unit")
	chip.set_stat("42")
	check(chip.get_text() == "42" and not (chip.get_node("%Unit") as Label).visible, "an empty unit is hidden")
	chip.tone = "gold"
	check((chip.get_node("%Value") as Label).theme_type_variation == &"StatValueGold", "tone picks the value's style")
	chip.free()
	main.free()
	game.buff = {}
	game.flow = {}
	game.reset_state()


func _collect_texts(node: Node, texts: Array[String]) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		texts.append((node as Label).text)
	elif node is Button and (node as Button).is_visible_in_tree():
		texts.append((node as Button).text)
	for child in node.get_children():
		_collect_texts(child, texts)


func test_style_gallery_covers_theme() -> void:
	# Task V.0: the style gallery shows every type variation of ui/theme.tres, so a new style is never left unseen.
	var theme: Theme = load("res://ui/theme.tres")
	var gallery_scene := FileAccess.get_file_as_string("res://scenes/dev/style_gallery.tscn")
	check(gallery_scene != "" and not gallery_scene.contains("theme_override_"), "the gallery scene exists and has no overrides")
	var gallery: StyleGallery = load("res://scenes/dev/style_gallery.tscn").instantiate()
	root.add_child(gallery)
	var used := {}
	for page: String in StyleGallery.PAGES:
		gallery.build(page)
		used.merge(gallery.used_variations())
	# (That each one is also on screen is checked when the gallery is shot: an off-screen node is an ERROR there.)
	for type_name: StringName in theme.get_type_list():
		if theme.get_type_variation_base(type_name) != &"":
			check(used.has(type_name), "the style gallery has theme variation %s" % type_name)
	for type_name: StringName in used:
		check(type_name == &"Button" or theme.get_type_variation_base(type_name) != &"",
				"the gallery's variation %s is defined in the theme" % type_name)
	gallery.free()
	# Not part of the game: no autoloads by name, and nothing in the game points at it.
	var source := FileAccess.get_file_as_string("res://scripts/dev/style_gallery.gd")
	check(RegEx.create_from_string("\\b(Game|Settings|Audio)\\.").search(source) == null,
			"the gallery never uses the Game/Settings/Audio autoloads by name")
	check(not FileAccess.get_file_as_string("res://project.godot").contains("style_gallery"), "project.godot doesn't use it")
	for dir: String in ["res://scenes", "res://scripts/ui", "res://scripts/autoload", "res://scripts/data",
			"res://scripts/cube", "res://scripts/util"]:
		for file_name in DirAccess.get_files_at(dir):
			if file_name.ends_with(".gd") or file_name.ends_with(".tscn"):
				check(not FileAccess.get_file_as_string(dir.path_join(file_name)).contains("style_gallery"),
						"%s doesn't reference the style gallery" % file_name)


# --- Layout (task 2.2) -----------------------------------------------------------

func test_next_goal() -> void:
	var g := new_game()
	var goal := g.get_next_goal()
	check(goal["id"] == "friend" and goal["kind"] == "helper", "a new game aims at the first Friend")
	check_near(goal["missing"], 0.0, "it's free, so it's ready to buy at once (5.0)")
	g.buy_building("friend")
	g.cheat_add_solves(2.0)
	goal = g.get_next_goal()
	check(float(goal["missing"]) > 0.0 and float(goal["seconds"]) > 0.0, "the next goal has Solves missing and a time")
	goal = g.get_next_goal()
	check(goal["id"] == "ms_friend_1", "next is the cheapest new thing (Practice Partners I, 5)")
	check(float(goal["seconds"]) > 0.0 and not is_inf(float(goal["seconds"])), "with a helper there's a time estimate")
	g.cheat_add_solves(1e33)
	for def: Dictionary in Content.BUILDINGS:
		g.buy_buildings(def["id"], 200)  # enough for every milestone
	for def: Dictionary in Content.get_upgrades():
		g.buy_upgrade(def["id"])
	goal = g.get_next_goal()
	check(goal["kind"] == "method" and goal["id"] == "cfop", "with every helper and upgrade owned it aims at the next method (CFOP, 200)")
	while not g.get_next_method().is_empty():
		g.buy_method(g.get_next_method()["id"])
		g.finish_research()  # methods are Lab research (5.6)
	goal = g.get_next_goal()
	check(goal["kind"] == "puzzle" and goal["id"] == "3x3", "then at the next puzzle (the 3x3, 300)")
	while g.get_next_locked_puzzle() != "":
		g.unlock_puzzle(g.get_next_locked_puzzle())
	goal = g.get_next_goal()
	check(goal["more"] and goal["kind"] == "helper", "with everything owned it aims at another helper")
	g.free()


func key_event(physical: Key, pressed: bool, echo: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	event.pressed = pressed
	event.echo = echo
	return event


func test_layout_and_keyboard_tap() -> void:
	check(InputMap.has_action("tap"), "there's a tap input action")
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(main.get_node_or_null("%TapButton") == null, "the old Turn button is gone")
	check(main.get_node_or_null("%GoalCard") != null and main.get_node_or_null("%SettingsButton") != null,
			"the goal card and the settings button exist")
	var first_tap := game.get_tap_moves()
	main._unhandled_input(key_event(KEY_SPACE, true, false))
	check_near(game.total_moves, first_tap, "Space taps")
	var second_tap := game.get_tap_moves()  # a little more: the TPS streak (S.7) grew
	main._unhandled_input(key_event(KEY_SPACE, true, true))
	main._unhandled_input(key_event(KEY_SPACE, true, true))
	check_near(game.total_moves, first_tap, "holding Space doesn't repeat (echo events are ignored)")
	main._unhandled_input(key_event(KEY_SPACE, false, false))
	main._unhandled_input(key_event(KEY_ENTER, true, false))
	check_near(game.total_moves, first_tap + second_tap, "Enter taps too")
	main._refresh()
	check((main.get_node("%Goal1Label") as Label).text.begins_with("Cubing Friend"),
			"next to the moves bar, the goal card shows the next goal first")
	main.free()
	game.reset_state()


# --- Shop cards (task 2.3) ---------------------------------------------------------

func test_content_icons_exist() -> void:
	for def: Dictionary in Content.BUILDINGS + Content.UPGRADES + Content.METHODS:
		check(def.has("icon") and ResourceLoader.exists(Content.ICON_DIR + def["icon"] + ".svg"), "%s has an icon file" % def["id"])
	check(ResourceLoader.exists(Content.ICON_DIR + Content.LOCKED_ICON + ".svg"), "there's a locked icon")
	var credits := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	for file_name in DirAccess.get_files_at(Content.ICON_DIR):
		if file_name.ends_with(".svg"):
			check(credits.contains("assets/icons/" + file_name), "%s is credited in assets/CREDITS.md" % file_name)


func test_shop_cards() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var cards: Dictionary = main._helper_cards
	var friend: ShopCard = cards["friend"]
	var club: ShopCard = cards["club"]
	check(friend.visible and friend.affordable and not friend.disabled, "fresh: the free first Friend is ready to take (5.0)")
	game.buy_building("friend")
	main._refresh()
	check(friend.visible and not friend.affordable and friend.disabled, "the second one isn't affordable yet")
	check(club.visible and club.locked and club._title.text == "???", "fresh: the next helper shows as a locked ??? card")
	var visible_locked := 0
	for id: String in cards:
		if (cards[id] as ShopCard).visible and (cards[id] as ShopCard).locked:
			visible_locked += 1
	check(visible_locked == 1, "exactly one locked card is shown")
	game.cheat_add_solves(40.0)
	main._refresh()
	check(friend.affordable and not friend.disabled and friend._cost.theme_type_variation == &"CostAffordable",
			"with enough Solves the card is affordable with a green cost")
	check(not club.locked and club.visible, "40 lifetime Solves reveals the Club (unlocks at 30)")
	check(cards["robot"].locked and cards["robot"].visible, "...and the Robot becomes the locked next card")
	var tabs: TabContainer = main.get_node("%Tabs")
	check(tabs.get_tab_title(main.UPGRADES_TAB) == "Upgrades" and main.get_tab_count(main.UPGRADES_TAB) == 2,
			"the Upgrades tab's bubble counts the affordable Lube and Practice Partners I (V.5)")
	# V.5: bars towards the cost, milestone pips, the next helper's silhouette, the count bubbles.
	check(friend._bar.visible and is_equal_approx(friend._bar.value, 1.0) and friend._bar.theme_type_variation == &"CostBar"
			and friend.is_processing(), "an affordable card's bar is full, green and breathing")
	check(club._bar.visible and club._bar.value < 1.0 and club._bar.theme_type_variation == &"CostBarDim"
			and not club.is_processing(), "a card you can't afford yet: a grey bar part-way (%s)" % club._bar.value)
	var robot: ShopCard = cards["robot"]
	check(robot._sticker.silhouette and robot._bar.visible
			and is_equal_approx(robot._bar.value, game.get_run_solves() / game.get_building_unlock_at("robot")),
			"the next helper: a silhouette and a bar towards its unlock")
	check(friend._pips.visible and friend._pips.get_child_count() == Content.HELPER_MILESTONES.size()
			and (friend._pips.get_child(0) as Control).theme_type_variation == &"PipReady",
			"one Friend owned: its first milestone is ready to buy, not yet gold")
	game.upgrades["ms_friend_1"] = true
	main._refresh()
	check((friend._pips.get_child(0) as Control).theme_type_variation == &"PipOn", "...gold once its upgrade is bought")
	game.upgrades.erase("ms_friend_1")
	check(main.get_tab_count(main.HELPERS_TAB) == 1, "the Helpers bubble counts the affordable Friend")
	main.set_buy_amount(10)
	check(main.get_tab_count(main.HELPERS_TAB) == 1, "...also on ×10 (it counts single buys)")
	main.set_buy_amount(1)
	ShopCard.reduce_motion = true
	friend._process(0.3)
	check(is_equal_approx(friend._bar.modulate.a, 1.0), "Reduce motion: the bar doesn't breathe")
	ShopCard.reduce_motion = false
	friend.pressed.emit()
	check(game.buildings["friend"] == 2, "clicking an affordable card buys the helper (a second Friend)")
	main.free()
	game.reset_state()


## V.6: every motion-kit helper ends at once (no tween) with Reduce motion on, and animates with it off.
func test_ui_fx() -> void:
	var holder := Control.new()
	root.add_child(holder)
	var node := Control.new()
	node.size = Vector2(100, 40)
	holder.add_child(node)
	var label := Label.new()
	holder.add_child(label)
	var dim := ColorRect.new()
	holder.add_child(dim)
	var fmt := func(value: float) -> String: return str(roundi(value))
	var was := UiFx.reduce_motion
	UiFx.reduce_motion = true
	var instant: Array = [UiFx.pop_in(node), UiFx.pop(node), UiFx.squash(node), UiFx.slide_in(node, Vector2(30, 0)),
			UiFx.shake(node), UiFx.roll_number(label, 1.0, 9.0, fmt), UiFx.sheen(node), UiFx.breathe(node),
			UiFx.fly_text(holder, "+1", Vector2.ZERO, Vector2(50, 50))]
	check(instant.all(func(tween: Variant) -> bool: return tween == null), "Reduce motion: no helper starts a tween")
	check(node.scale == Vector2.ONE and is_equal_approx(node.modulate.a, 1.0) and label.text == "9"
			and node.self_modulate == Color.WHITE, "...everything is already in its end state")
	check(holder.get_child_count() == 3, "...and nothing flies")
	holder.visible = false
	check(UiFx.open_panel(holder, dim, node) == null and holder.visible and is_equal_approx(dim.modulate.a, 1.0), "panels open at once")
	var closed := [0]
	check(UiFx.close_panel(holder, dim, node, func() -> void: closed[0] += 1) == null and not holder.visible and closed[0] == 1,
			"...and close at once, calling back")
	UiFx.reduce_motion = false
	holder.visible = true
	label.text = "x"
	var probe := UiFx.roll_number(label, 1.0, 9.0, fmt)
	probe.custom_step(UiFx.ROLL_TIME / 3.0)
	check(label.text != "x" and label.text != "1" and label.text != "9", "a number rolls through the values between (%s)" % label.text)
	probe.custom_step(5.0)
	var moving: Array = [UiFx.pop(node), UiFx.squash(node), UiFx.shake(node), UiFx.roll_number(label, 1.0, 9.0, fmt),
			UiFx.sheen(node), UiFx.fly_text(holder, "+1", Vector2.ZERO, Vector2(50, 50))]
	check(moving.all(func(tween: Variant) -> bool: return tween is Tween), "with motion: each helper animates")
	for tween: Tween in moving:
		tween.custom_step(5.0)
	check(node.scale.is_equal_approx(Vector2.ONE) and label.text == "9" and node.self_modulate.is_equal_approx(Color.WHITE),
			"...and ends where it should")
	var opening := UiFx.open_panel(holder, dim, node)
	check(opening != null and is_zero_approx(dim.modulate.a), "a panel fades in from a clear backdrop")
	opening.custom_step(UiFx.OPEN_TIME / 2.0)
	check(dim.modulate.a > 0.1 and dim.modulate.a < 0.95 and node.modulate.a < 1.0, "...half-way: half dim, still fading in")
	opening.custom_step(1.0)
	check(is_equal_approx(dim.modulate.a, 1.0) and node.scale.is_equal_approx(Vector2.ONE), "...then fully open")
	check((dim.material != null) == UiFx.backdrop_blur, "the backdrop blurs on High only")
	var blur_was := UiFx.backdrop_blur
	UiFx.backdrop_blur = not blur_was
	check((dim.material != null) == UiFx.backdrop_blur, "switching Graphics re-dresses an open panel's backdrop")
	UiFx.backdrop_blur = blur_was
	var closing := UiFx.close_panel(holder, dim, node, func() -> void: closed[0] += 1)
	check(holder.visible and UiFx.is_closing(holder), "closing: still visible while it fades, marked closing")
	closing.custom_step(1.0)
	check(not holder.visible and not UiFx.is_closing(holder) and closed[0] == 2 and is_equal_approx(dim.modulate.a, 1.0)
			and node.scale.is_equal_approx(Vector2.ONE), "...then hidden, called back, and reset for next time")
	# In a CenterContainer (as the dialogs are), which resets its child's scale when it lays it out on showing.
	var centre := CenterContainer.new()
	centre.size = Vector2(400, 300)
	holder.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 100)
	centre.add_child(panel)
	holder.visible = false
	var growing := UiFx.open_panel(holder, dim, panel)
	growing.pause()  # only the container's layout runs in this frame
	await process_frame  # the container sorts its child here (scale back to 1)
	growing.custom_step(0.001)  # just started: from OPEN_SCALE, not from the 1 the container set
	check(panel.scale.x < 0.99, "a panel in a CenterContainer really grows in (scale %s)" % panel.scale.x)
	growing.custom_step(1.0)
	check(panel.scale.is_equal_approx(Vector2.ONE), "...to full size")
	UiFx.reduce_motion = was
	holder.free()


## V.6: the shop's motion: buying squashes the card and flies "+N" to its count; a card that becomes affordable pops.
func test_shop_motion() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	UiFx.reduce_motion = false
	game.buy_building("friend")
	main._refresh()
	var friend: ShopCard = main._helper_cards["friend"]
	check(not friend.affordable, "test setup: the second Friend isn't affordable")
	game.cheat_add_solves(1000.0)
	main._refresh()
	check(friend.affordable and friend._pop != null and friend._pop.is_running(), "a card that becomes affordable pops")
	friend._pop.custom_step(UiFx.POP_TIME * 0.4)
	check(friend.scale.x > 1.01, "...it swells (%s)" % friend.scale)
	friend._pop.custom_step(1.0)
	check(friend.scale.is_equal_approx(Vector2.ONE), "...and settles")
	var layer_before: int = main.fx.get_child_count()
	friend.pressed.emit()
	check(game.buildings["friend"] == 2 and main.fx.get_child_count() == layer_before + 1, "buying flies a \"+1\"")
	main._refresh()
	check(friend._owned_roll != null and friend._owned_roll.is_running(), "...and the owned count rolls up")
	friend._owned_roll.custom_step(1.0)
	main._refresh()
	check(friend._owned.text == "2", "...to the new count (%s)" % friend._owned.text)
	UiFx.reduce_motion = false
	main.free()
	UiFx.reduce_motion = bool(root.get_node("Settings").get_value("reduce_motion"))
	game.reset_state()


## V.6: the motion kit at speed: ~1,000 moves/s with buys every few frames for 120 frames leaves no flying labels or
## running pops behind (an error anywhere fails run_tests.sh's log check).
func test_motion_at_speed() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	UiFx.reduce_motion = false
	game.buildings["robot"] = 30  # ~1,000 helper moves/s
	game.cheat_add_solves(1e7)
	check(game.get_moves_per_second() >= 900.0, "test setup: about 1,000 moves/s (%s)" % game.get_moves_per_second())
	for frame in 120:
		if frame % 5 == 0:
			main._on_helper_card_pressed("friend")
		if frame == 30:
			main.settings_panel.open()
		if frame == 40:
			main.settings_panel.close()
		await process_frame
	check(int(game.buildings["friend"]) >= 20, "it kept buying (%d Friends)" % game.buildings["friend"])
	await create_timer(UiFx.FLY_TIME + 0.2).timeout
	var flying := 0
	for child in main.fx.get_children():
		if child is Label and not (main.fx._labels as Array).has(child):  # FxLayer's own pooled labels stay
			flying += 1
	check(flying == 0, "every \"+N\" that flew is gone (%d left)" % flying)
	check(not main.settings_panel.visible, "the panel finished closing")
	main.free()
	UiFx.reduce_motion = bool(root.get_node("Settings").get_value("reduce_motion"))
	game.reset_state()


func test_upgrade_tiles_show_owned() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.cheat_add_solves(100.0)
	game.buy_upgrade("lube")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var lube: UpgradeTile = main._upgrade_tiles["lube"]
	check(lube.visible and lube.owned and lube.disabled and lube._cost.text == "Owned", "a bought upgrade stays as an Owned tile")
	check(not main._upgrade_tiles["firmware"].visible, "upgrades far out of reach stay hidden")
	check(not main._method_tiles["roux"].visible, "methods after the next one stay hidden")
	main.free()
	game.reset_state()


func test_upgrade_tiles_buyable_first() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.cheat_add_solves(5000.0)
	game.buy_building("friend")
	game.buy_upgrade("lube")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var first_visible: UpgradeTile = null
	for child in (main.get_node("%UpgradeList") as GridContainer).get_children():
		if (child as UpgradeTile).visible:
			first_visible = child
			break
	check(first_visible != null and not first_visible.owned, "the first tile in the grid is a buyable upgrade, not an owned one")
	main.free()
	game.reset_state()


# --- Juice (task 2.4) --------------------------------------------------------------

func test_juice_pool_and_counter() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var fx: FxLayer = main.get_node("%FxLayer")
	for i in 1000:
		main._on_tap_pressed(Vector2(200, 200))
	check(fx.active_count() <= FxLayer.POOL_SIZE, "1,000 taps in one frame never show more than 20 floating texts")
	check(fx.active_count() > 0, "taps do show floating texts")
	for i in 120:
		fx._process(1.0 / 60.0)
	check(fx.active_count() == 0, "floating texts fade out")
	# Counter eases up, snaps down.
	main._animate_counter(1.0)
	game.cheat_add_solves(10000.0)
	main._animate_counter(1.0 / 60.0)
	var label: Label = main.get_node("%SolvesLabel")
	check(main._shown_solves > 0.0 and main._shown_solves < game.solves, "the counter counts up instead of jumping")
	for i in 120:
		main._animate_counter(1.0 / 60.0)
	check_near(main._shown_solves, game.solves, "the counter reaches the real value")
	check(label.text == Num.format(game.solves), "the label shows the real value at the end")
	game.solves = 10.0
	main._animate_counter(1.0 / 60.0)
	check_near(main._shown_solves, 10.0, "spending snaps the counter down at once")
	main.free()
	game.reset_state()
	# Squash on tap (a fresh view, so no solve bounce from the taps above is still running).
	var view := new_view()
	view.squash()
	view._process(1.0 / 60.0)
	check(view._puzzle.scale.y < 0.99 and view._puzzle.scale.x > view._puzzle.scale.y, "a tap squashes the puzzle")
	for i in 60:
		view._process(1.0 / 60.0)
	check(absf(view._puzzle.scale.y - 1.0) < 0.01, "the squash springs back")
	view.free()


func test_juice_at_high_speed() -> void:
	# A real run of the main scene at late-game speed (~369K moves/s, solves every frame): stays within the pool,
	# pops solves at a limited rate, and logs no errors (run_tests.sh fails on any ERROR line).
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	var presets: Dictionary = load("res://tools/screenshot_presets.gd").PRESETS
	game.apply_save_data(presets["late"].duplicate(true), Time.get_unix_time_from_system())
	check(game.get_moves_per_second() > 1000.0, "the late preset runs at over 1,000 moves/s")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var fx: FxLayer = main.get_node("%FxLayer")
	var most := 0
	var solves_before := game.total_solves
	for i in 120:
		await process_frame
		most = maxi(most, fx.active_count())
	check(game.total_solves > solves_before, "the game kept solving during the run")
	check(most <= FxLayer.POOL_SIZE, "never more than 20 floating texts at high speed")
	check(most >= 1, "solves show a floating +X Solves")
	var view := main.get_node("%PuzzleView") as PuzzleView3D
	if ShowcaseSolve.supports(game.get_focused_puzzle_id()):  # R.2: a staged showcase solve, never speed mode
		check(not view.speed_mode and main._showcase != null, "the big puzzle plays a showcase solve, not speed mode")
	else:
		check(view.speed_mode, "the puzzle is in speed mode")
	main.free()
	game.reset_state()


# --- Audio (task 3.1) ----------------------------------------------------------------

func test_audio_buses_and_rate_limits() -> void:
	var audio: AudioManager = root.get_node("Audio")
	for bus: String in ["Master", "Music", "SFX"]:
		check(AudioServer.get_bus_index(bus) >= 0, "audio bus %s exists" % bus)
	check(absf(audio.get_bus_volume(AudioManager.SFX_BUS) - AudioManager.DEFAULT_SFX_VOLUME) < 0.01, "SFX starts at 70 %")
	check(absf(audio.get_bus_volume(AudioManager.MUSIC_BUS) - AudioManager.DEFAULT_MUSIC_VOLUME) < 0.01, "Music starts at 50 %")
	await create_timer(0.6).timeout  # let any earlier test's sounds age past their rate limits
	var before: Dictionary = audio.played.duplicate()
	var chimes := 0
	for i in 100:
		if audio.play_solve():
			chimes += 1
	check(chimes == 1 and int(audio.played["chime"]) == int(before["chime"]) + 1, "100 solves in one frame play one chime, not 100")
	check(audio.play_buy(), "buying plays a sound")
	check(audio.play_unlock(), "an unlock plays a sound")
	check(audio.play_click(7), "a turn plays a click")
	check(not audio.play_click(7), "a second click in the same instant is skipped")
	await create_timer(0.3).timeout
	check(audio.play_solve(), "after 0.25 s a solve chimes again")
	audio.set_bus_volume(AudioManager.SFX_BUS, 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioManager.SFX_BUS)), "volume 0 mutes the bus")
	audio.set_bus_volume(AudioManager.SFX_BUS, AudioManager.DEFAULT_SFX_VOLUME)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioManager.SFX_BUS)), "volume back up unmutes it")


func test_game_events_play_sounds() -> void:
	var audio: AudioManager = root.get_node("Audio")
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.6).timeout
	var before: Dictionary = audio.played.duplicate()
	audio._last_played.clear()
	main._on_tap_pressed()
	check(int(audio.played["click"]) == int(before["click"]) + 1, "a tap clicks")
	game.cheat_add_solves(40.0)  # reveals the Club (unlocks at 30 lifetime Solves)
	audio._last_played.clear()
	main._refresh()
	check(int(audio.played["unlock"]) == int(before["unlock"]) + 1, "a newly revealed helper plays the unlock sound")
	audio._last_played.clear()
	game.buy_building("friend")
	check(int(audio.played["buy"]) == int(before["buy"]) + 1, "buying plays the buy sound")
	audio._last_played.clear()
	for i in 20:
		game.tap()  # completes a solve
	check(int(audio.played["chime"]) == int(before["chime"]) + 1, "a solve chimes")
	main.free()
	game.reset_state()


# --- Music (task 3.2) ----------------------------------------------------------------

func test_tracks_data() -> void:
	var ids := {}
	for def: Dictionary in Content.TRACKS:
		for field: String in ["id", "title", "artist", "license", "file", "unlock"]:
			check(def.has(field), "track %s has '%s'" % [def.get("id", "?"), field])
		check(not ids.has(def["id"]), "track id %s is unique" % def["id"])
		ids[def["id"]] = true
		if def["file"] != "":
			check(ResourceLoader.exists(def["file"]), "track %s's file exists" % def["id"])
			check(def["license"] in ["CC0", "CC-BY", "CC-BY 4.0", "CC-BY 3.0"], "track %s is CC0 or CC-BY" % def["id"])
			check(FileAccess.get_file_as_string("res://assets/CREDITS.md").contains(String(def["file"]).get_file()), "track %s is credited" % def["id"])
			var stream: AudioStreamWAV = load(def["file"])
			check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "track %s loops" % def["id"])
	var with_files := 0
	for def: Dictionary in Content.TRACKS:
		if def["file"] != "":
			with_files += 1
	check(with_files >= 2, "at least 2 tracks have music")
	var g := new_game()
	check(g.get_unlocked_track_ids() == (["practice_room"] as Array[String]), "a new game hears the 2x2's track")
	g.cheat_add_solves(float(Content.get_puzzle("3x3")["unlock_cost"]))
	g.unlock_puzzle("3x3")
	check(g.get_unlocked_track_ids() == (["practice_room", "first_sub_20"] as Array[String]), "unlocking the 3x3 unlocks its track")
	check(g.get_track_for_puzzle("3x3") == "first_sub_20", "3x3's track is First Sub-20")
	check(g.get_track_for_puzzle("4x4") == "parity", "the 4x4's track is Parity")
	for def: Dictionary in Content.TRACKS:
		check(def["file"] != "", "track %s has a file (placeholder until D8)" % def["id"])
	g.free()


## V.9: every button gets a soft hover tick and a press tap (disabled ones stay quiet on hover); cards that buy keep
## their own "buy" sound instead of the tap.
func test_button_sounds() -> void:
	var audio: AudioManager = root.get_node("Audio")
	var button := Button.new()
	root.add_child(button)
	audio._last_played.clear()
	var hovers: int = audio.played["hover"]
	var presses: int = audio.played["press"]
	button.mouse_entered.emit()
	check(audio.played["hover"] == hovers + 1, "hovering a button ticks")
	button.pressed.emit()
	check(audio.played["press"] == presses + 1, "pressing it taps")
	audio._last_played.clear()
	button.disabled = true
	button.mouse_entered.emit()
	check(audio.played["hover"] == hovers + 1, "a disabled button stays quiet")
	var card: ShopCard = load("res://scenes/shop_card.tscn").instantiate()
	root.add_child(card)
	audio._last_played.clear()
	card.pressed.emit()
	check(audio.played["press"] == presses + 1, "a shop card doesn't tap (buying plays its own sound)")
	button.free()
	card.free()


func test_music_crossfade_never_two_at_full_volume() -> void:
	var audio: AudioManager = root.get_node("Audio")
	audio.music_clock = 0.0
	audio.stop_all()
	audio.set_window_focused(true)
	audio.set_music_mode("follow")
	var tracks: Array[String] = ["practice_room", "first_sub_20"]
	audio.set_music_context(tracks, "practice_room")
	check(audio.current_track_id == "", "no music in the first seconds after launch")
	audio.advance_music(AudioManager.MUSIC_START_DELAY)
	check(audio.current_track_id == "practice_room", "after the delay, follow mode plays the focused puzzle's track")
	audio.advance_music(0.1)
	check(audio.music_volumes().max() < 0.2, "the first track fades in rather than starting loud")
	for i in 30:
		audio.advance_music(0.1)
	var both_loud := false
	audio.set_music_context(tracks, "first_sub_20")  # focus moved to another puzzle
	check(audio.current_track_id == "first_sub_20", "follow mode switches when the focused puzzle changes")
	var saw_overlap := false
	for i in 30:
		audio.advance_music(0.1)
		var v := audio.music_volumes()
		both_loud = both_loud or (v[0] > 0.99 and v[1] > 0.99)
		saw_overlap = saw_overlap or (v[0] > 0.05 and v[1] > 0.05)
	check(saw_overlap, "the two tracks overlap during the crossfade")
	check(not both_loud, "two tracks are never both at full volume")
	var v_end := audio.music_volumes()
	check((v_end[0] > 0.99) != (v_end[1] > 0.99) and minf(v_end[0], v_end[1]) == 0.0, "after the crossfade only one track plays")
	# Ducking when the window loses focus.
	audio.set_window_focused(false)
	for i in 20:
		audio.advance_music(0.1)
	check(absf(maxf(audio.music_volumes()[0], audio.music_volumes()[1]) - AudioManager.DUCK_VOLUME) < 0.02, "music ducks to 30 % when unfocused")
	audio.set_window_focused(true)
	for i in 20:
		audio.advance_music(0.1)
	check(maxf(audio.music_volumes()[0], audio.music_volumes()[1]) > 0.99, "music comes back when focused again")
	# Loop and shuffle modes.
	audio.set_music_mode("loop", "practice_room")
	check(audio.current_track_id == "practice_room", "loop mode plays the chosen track")
	for i in 10:
		audio.on_music_looped()
	check(audio.current_track_id == "practice_room", "loop mode never changes track")
	audio.set_music_mode("shuffle")
	for i in AudioManager.SHUFFLE_LOOPS:
		audio.on_music_looped()
	check(audio.current_track_id == "first_sub_20", "shuffle mode changes track after a few loops")
	audio.set_music_mode("follow")
	audio.stop_all()


# --- Buy x1 / x10 / Max (task 3.3) ------------------------------------------------

## (The Club: the Friend's first copy is free since 5.0, which would skew the sums.)
func test_bulk_buying() -> void:
	var g := new_game()
	var one_by_one := 0.0
	for i in 10:
		one_by_one += ceilf(60.0 * pow(1.15, i))
	check_near(g.get_building_cost_for("club", 10), one_by_one, "x10 costs the same as ten single buys")
	check_near(g.get_building_cost_for("club", 1), g.get_building_cost("club"), "x1 cost = the normal cost")
	g.cheat_add_solves(one_by_one - 1.0)
	check(g.buy_buildings("club", 10) == 0, "x10 with one Solve too few buys nothing")
	check_near(g.solves, one_by_one - 1.0, "...and spends nothing")
	g.cheat_add_solves(1.0)
	check(g.buy_buildings("club", 10) == 10, "x10 with exactly enough buys 10")
	check_near(g.solves, 0.0, "...and costs exactly the sum")
	check(g.buildings["club"] == 10, "owning 10 Clubs now")
	check(g.get_max_affordable("club") == 0, "Max with no Solves = 0")
	check(g.buy_buildings("club", GameState.BUY_MAX) == 0, "buying Max with no Solves buys nothing")
	g.cheat_add_solves(1000.0)
	var max_count := g.get_max_affordable("club")
	var max_cost := g.get_building_cost_for("club", max_count)
	check(max_count > 0 and max_cost <= 1000.0 and g.get_building_cost_for("club", max_count + 1) > 1000.0,
			"Max is the most you can afford (one more would be too many)")
	check(g.buy_buildings("club", GameState.BUY_MAX) == max_count, "buying Max buys that many")
	check_near(g.solves, 1000.0 - max_cost, "...for exactly their cost")
	check(g.solves < g.get_building_cost("club"), "what's left can't buy another")
	g.free()


func test_buy_amount_toggle() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.cheat_add_solves(100.0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var friend: ShopCard = main._helper_cards["friend"]
	main.set_buy_amount(10)
	main._refresh()
	check(friend._cost.text == "×10  ·  %s Solves" % Num.format(game.get_building_cost_for("friend", 10)), "x10 shows the cost of 10")
	check(friend.affordable == (game.solves >= game.get_building_cost_for("friend", 10)), "x10 is affordable only if all 10 are")
	main.set_buy_amount(GameState.BUY_MAX)
	main._refresh()
	var n := game.get_max_affordable("friend")
	check(friend._cost.text == "×%d  ·  %s Solves" % [n, Num.format(game.get_building_cost_for("friend", n))], "Max shows how many and their cost")
	friend.pressed.emit()
	check(game.buildings["friend"] == n, "pressing the card in Max mode buys that many")
	main.set_buy_amount(1)
	main._refresh()
	check(friend._cost.text == "%s Solves" % Num.format(game.get_building_cost("friend")), "x1 shows the single cost")
	main.free()
	game.reset_state()


# --- Welcome back panel (task 3.6) ---------------------------------------------------

func test_welcome_panel() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var panel: Control = main.get_node("%WelcomePanel")
	check(not panel.visible, "no panel when nothing was earned away")
	main.free()
	# Now with offline earnings.
	var presets: Dictionary = load("res://tools/screenshot_presets.gd").PRESETS
	var data: Dictionary = presets["welcome"].duplicate(true)
	var now := Time.get_unix_time_from_system()
	data["saved_at"] = now - float(data["away_seconds"])
	game.apply_save_data(data, now)
	var earned := float(game.offline_report["solves"])
	check(earned > 0.0, "2h 15m away earns Solves")
	game.set_process(false)  # freeze the economy: live solves would chime and rate-limit the Collect chime
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	panel = main.get_node("%WelcomePanel")
	check(panel.visible, "the Welcome back panel shows after time away")
	check((panel.get_node("%Away") as Label).text == "You were away for 2h 15m.", "it says how long you were away")
	check((panel.get_node("%Earned") as Label).text == "+%s Solves" % Num.format(earned), "it shows what you earned")
	check(not (panel.get_node("%Notice") as Label).visible, "no damaged-save notice")
	check((panel.get_node("%Detail") as Label).text == "Your helpers kept solving while you were gone.", "it says the helpers kept solving")
	var lab_only: Control = load("res://scenes/welcome_panel.tscn").instantiate()
	root.add_child(lab_only)
	lab_only.show_report({"seconds": 600.0, "solves": 0.0, "research": "CFOP"}, "")
	check((lab_only.get_node("%Detail") as Label).text == "The Lab finished CFOP." and not (lab_only.get_node("%Earned") as Label).visible,
			"no helpers, only research: it says just that")
	lab_only.free()
	main._animate_counter(1.0)
	check_near(main._shown_solves, game.solves - earned, "the counter waits for Collect")
	main._unhandled_input(key_event(KEY_SPACE, true, false))
	var moves_before := game.total_moves
	check_near(game.total_moves, moves_before, "Space doesn't tap the cube while the panel is open")
	var audio: AudioManager = root.get_node("Audio")
	await create_timer(0.3).timeout
	var chimes_before := int(audio.played["chime"])
	audio._last_played.clear()  # deterministic: don't depend on the rate-limit clock
	panel.collect()
	check(_closed(panel), "Collect closes the panel")
	check(int(audio.played["chime"]) == chimes_before + 1, "collecting chimes")
	for i in 120:
		main._animate_counter(1.0 / 60.0)
	check_near(main._shown_solves, game.solves, "after Collect the counter counts up to the total")
	main.free()
	# A damaged-save notice alone shows with an OK button.
	game.reset_state()
	game.load_notice = "Your save file was damaged, so the backup was loaded."
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	panel = main.get_node("%WelcomePanel")
	check(panel.visible and (panel.get_node("%Notice") as Label).visible and not (panel.get_node("%Earned") as Label).visible,
			"a load notice alone shows the panel with just the notice")
	check((panel.get_node("%CollectButton") as Button).text == "OK", "...and an OK button")
	check(game.load_notice == "", "the notice is shown once")
	main.free()
	game.set_process(true)
	game.reset_state()


# --- Puzzles (Phase 4) -----------------------------------------------------------------

func test_puzzle_data() -> void:
	var previous_rate := 0.0
	var previous_cost := -1.0
	var ids := {}
	for def: Dictionary in Content.PUZZLES:
		for field: String in ["id", "name", "moves_per_solve", "solve_value", "unlock_cost", "requires_prestige"]:
			check(def.has(field), "puzzle %s has '%s'" % [def.get("id", "?"), field])
		check(not ids.has(def["id"]), "puzzle id %s is unique" % def["id"])
		ids[def["id"]] = true
		var rate := float(def["solve_value"]) / float(def["moves_per_solve"])
		check(rate > previous_rate, "%s earns more Solves per move than the puzzle before it" % def["id"])
		check(float(def["unlock_cost"]) > previous_cost, "%s costs more to unlock than the one before it" % def["id"])
		previous_rate = rate
		previous_cost = float(def["unlock_cost"])
	check(float(Content.PUZZLES[0]["unlock_cost"]) == 0.0, "the first puzzle is free")
	for def: Dictionary in Content.TRACKS:
		check(def["unlock"] == "championship" or ids.has(def["unlock"]), "track %s is linked to a real puzzle" % def["id"])
	for def: Dictionary in Content.PUZZLES:
		var linked := false
		for track: Dictionary in Content.TRACKS:
			linked = linked or track["unlock"] == def["id"]
		check(linked, "puzzle %s has a track" % def["id"])


func test_parallel_puzzles() -> void:
	var g := new_game()
	check(g.get_unlocked_puzzle_ids() == (["2x2"] as Array[String]), "a new game has only the 2x2")
	check(g.get_next_locked_puzzle() == "3x3", "the next puzzle is the 3x3")
	check(not g.unlock_puzzle("4x4"), "puzzles unlock in ladder order")
	check(not g.unlock_puzzle("3x3"), "can't unlock without the Solves")
	g.cheat_add_solves(float(Content.get_puzzle("3x3")["unlock_cost"]))
	var focus_events := [0]
	g.focus_changed.connect(func(_id: String) -> void: focus_events[0] += 1)
	check(g.unlock_puzzle("3x3"), "its unlock cost in Solves unlocks the 3x3")
	check_near(g.solves, 0.0, "unlocking spends its cost")
	check(g.get_focused_puzzle_id() == "3x3" and focus_events[0] == 1, "the new puzzle gets the focus")
	check_near(g.get_puzzle_share("3x3"), 1.0, "unlocking moves the whole split onto it")
	check_near(g.get_puzzle_share("2x2"), 0.0, "...so the old one gets no helper moves")
	# Split
	g.set_split({"2x2": 3.0, "3x3": 1.0, "7x7": 5.0, "banana": 2.0})
	check_near(g.get_puzzle_share("2x2"), 0.75, "weights become shares (locked and unknown puzzles ignored)")
	var total := 0.0
	for id: String in g.get_split():
		total += float(g.get_split()[id])
	check_near(total, 1.0, "shares add up to 100 %")
	g.set_split({"2x2": -4.0, "3x3": 0.0})
	check_near(g.get_puzzle_share("3x3"), 1.0, "all-zero weights fall back to the newest puzzle")
	g.set_split_preset("even")
	check_near(g.get_puzzle_share("2x2"), 0.5, "Spread evenly: 50/50")
	g.set_split_preset("newest")
	check_near(g.get_puzzle_share("3x3"), 1.0, "Focus newest: all on the 3x3")
	# Helper moves are divided by the split; each puzzle solves on its own terms.
	g.set_split_preset("even")
	var moves_before := g.total_moves
	g.add_moves(80.0)
	check_near(g.total_moves - moves_before, 80.0, "puzzle moves add up to the helper moves")
	check_near(g.get_move_progress("2x2"), 0.0, "2x2 got 40 moves = 5 solves exactly")
	check_near(g.get_move_progress("3x3"), 0.0, "3x3 got 40 moves = 2 solves exactly")
	check_near(g.solves, 5.0 * 1.0 + 2.0 * 4.0, "Solves = 5 x 1 (2x2) + 2 x 4 (3x3)")
	# Taps go to the focused puzzle only.
	g.set_focus("2x2")
	var tap_moves := g.get_tap_moves()
	check_near(g.tap(), tap_moves, "tap() returns the moves it made")
	check_near(g.get_move_progress("2x2"), tap_moves, "a tap goes to the focused puzzle")
	check_near(g.get_move_progress("3x3"), 0.0, "...not to the others")
	# Rates
	g.cheat_add_solves(5.0)
	g.buy_building("friend")
	var e := float(Content.VARIETY["exponent"])
	check_near(g.get_puzzle_moves_per_second("2x2") + g.get_puzzle_moves_per_second("3x3"), g.get_moves_per_second() * 2.0 * pow(0.5, e),
			"per-puzzle moves/s = helper moves × share^exponent each (the variety bonus)")
	check_near(g.get_solves_per_second(), g.get_puzzle_solves_per_second("2x2") + g.get_puzzle_solves_per_second("3x3"), "total Solves/s = sum of puzzles")
	check(not g.can_unlock_puzzle("7x7"), "7x7 needs a World Championship")
	# Save round trip
	var data := g.get_save_data()
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.get_unlocked_puzzle_ids() == g.get_unlocked_puzzle_ids(), "unlocked puzzles survive save/load")
	check(loaded.get_focused_puzzle_id() == "2x2", "the focus survives save/load")
	check_near(loaded.get_puzzle_share("2x2"), 0.5, "the split survives save/load")
	check_near(loaded.get_move_progress("2x2"), g.get_move_progress("2x2"), "puzzle progress survives save/load")
	g.free()
	loaded.free()


func test_save_v1_to_v2_migration() -> void:
	var v1 := {"version": 1, "saved_at": 1000.0, "solves": 50.0, "total_solves": 500.0, "total_moves": 7000.0,
		"move_progress": 6.0, "buildings": {"friend": 3}, "upgrades": ["lube"]}
	var g := new_game()
	g.apply_save_data(v1.duplicate(true), 1000.0)
	check(g.get_unlocked_puzzle_ids() == (["2x2", "3x3"] as Array[String]), "a v1 player with upgrades gets the 2x2 and 3x3")
	check(g.get_focused_puzzle_id() == "3x3" and is_equal_approx(g.get_puzzle_share("3x3"), 1.0), "...focused on and splitting to the 3x3")
	check_near(g.get_move_progress("2x2"), 6.0, "v1 move progress goes to the starting puzzle")
	check_near(g.solves, 50.0, "Solves carry over")
	check(g.buildings["friend"] == 3 and g.upgrades.has("lube"), "helpers and upgrades carry over")
	check(int(g.get_save_data()["version"]) == GameState.SAVE_VERSION, "it saves as the current version")
	var fresh_v1 := {"version": 1, "saved_at": 1000.0, "solves": 2.0, "total_solves": 2.0, "move_progress": 3.0, "buildings": {}, "upgrades": []}
	g.apply_save_data(fresh_v1, 1000.0)
	check(g.get_unlocked_puzzle_ids() == (["2x2"] as Array[String]) and g.get_focused_puzzle_id() == "2x2", "a brand-new v1 player gets just the 2x2")
	g.free()


func test_puzzle_row() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	check(view.puzzle_id == "2x2", "a new game shows the 2x2 in the big view")
	var locked: PuzzleChip = main._locked_chip
	check(locked.visible and locked.locked and locked.puzzle_id == "3x3", "the 3x3 shows as the next locked puzzle")
	check(locked._unlock.disabled, "...and can't be unlocked without the Solves")
	game.cheat_add_solves(float(Content.get_puzzle("3x3")["unlock_cost"]))
	main._refresh()
	check(not locked._unlock.disabled, "with the 3x3's cost in Solves the Unlock button is enabled")
	var audio: AudioManager = root.get_node("Audio")
	await create_timer(0.6).timeout
	var unlock_sounds := int(audio.played["unlock"])
	audio._last_played.clear()  # deterministic: don't depend on the rate-limit clock
	locked._unlock.pressed.emit()
	check(game.is_puzzle_unlocked("3x3"), "pressing Unlock unlocks the 3x3")
	check(view.puzzle_id == "3x3", "the big view switches to the new puzzle")
	check(view._drop > 0.0, "it drops in")
	check(int(audio.played["unlock"]) == unlock_sounds + 1, "the unlock sting plays")
	var chip_2x2: PuzzleChip = main._chips["2x2"]
	check(chip_2x2.visible and not main._chips["3x3"].visible, "the 2x2 moved to the row; the focused 3x3 isn't in it")
	check(locked.puzzle_id == "4x4", "the 4x4 is now the next locked puzzle")
	# Click-to-focus: a click on the small 2x2 makes it the big one.
	chip_2x2.view._gui_input(mouse_button(true, Vector2(40, 40)))
	chip_2x2.view._gui_input(mouse_button(false, Vector2(40, 40)))
	check(game.get_focused_puzzle_id() == "2x2" and view.puzzle_id == "2x2", "clicking a small puzzle focuses it")
	check(main._chips["3x3"].visible and not main._chips["2x2"].visible, "...and the views swap")
	check_near(game.total_moves, 0.0, "clicking a small puzzle doesn't tap")
	check(chip_2x2.view.graphics_quality == "low" and not chip_2x2.view.sway_enabled, "small views are Low and don't sway")
	main.free()
	game.reset_state()


func test_split_controls() -> void:
	var g := new_game()
	g.cheat_add_solves(1e9)
	g.unlock_puzzle("3x3")
	g.unlock_puzzle("4x4")
	g.set_split_preset("even")
	g.set_share("2x2", 0.5)
	check_near(g.get_puzzle_share("2x2"), 0.5, "set_share sets one share")
	check_near(g.get_puzzle_share("3x3"), 0.25, "...and rescales the others in proportion")
	check_near(g.get_puzzle_share("4x4"), 0.25, "...both of them")
	for i in 20:  # push way past 100 %
		g.adjust_share("4x4", 0.1)
	check_near(g.get_puzzle_share("4x4"), 1.0, "a share stops at 100 %")
	for i in 3:
		g.adjust_share("4x4", -0.1)
	check_near(g.get_puzzle_share("4x4"), 0.7, "−10 % three times = 70 %")
	check_near(g.get_puzzle_share("2x2") + g.get_puzzle_share("3x3"), 0.3, "the rest goes to the others")
	var shares_ok := true
	var rng := seeded_rng(9)
	for i in 200:
		var ids := g.get_unlocked_puzzle_ids()
		g.adjust_share(ids[rng.randi_range(0, ids.size() - 1)], rng.randf_range(-0.4, 0.4))
		var total := 0.0
		for id in ids:
			total += g.get_puzzle_share(id)
			shares_ok = shares_ok and g.get_puzzle_share(id) >= -0.0001
		shares_ok = shares_ok and absf(total - 1.0) < 0.0001
	check(shares_ok, "after 200 random adjustments the shares still add up to 100 % and none is negative")
	g.set_split_preset("even")
	check_near(g.get_puzzle_share("3x3"), 1.0 / 3.0, "Spread evenly gives each a third")
	g.set_split_preset("newest")
	check_near(g.get_puzzle_share("4x4"), 1.0, "Focus newest puts everything on the 4x4")
	g.free()
	# The panel drives the same calls.
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.cheat_add_solves(float(Content.get_puzzle("3x3")["unlock_cost"]))
	game.unlock_puzzle("3x3")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var panel: Node = main.get_node("%SplitPanel")  # untyped: SplitPanel uses the Game autoload by name
	var labels: Dictionary = panel._row_labels
	check(labels.size() == 2, "the panel has a row per unlocked puzzle")
	(labels["3x3"]["minus"] as Button).pressed.emit()
	check_near(game.get_puzzle_share("3x3"), 0.9, "− takes 10 % off")
	check_near(game.get_puzzle_share("2x2"), 0.1, "...and gives it to the other puzzle")
	check((labels["3x3"]["share"] as Label).text == "90%", "the row shows the new share")
	var margin: Control = main.get_node("Margin")
	check(margin.get_combined_minimum_size().x <= 1280.0, "long numbers never make the page wider than 1280 px (min %.0f)" % margin.get_combined_minimum_size().x)
	(main.get_node("%PresetEven") as Button).pressed.emit()
	check_near(game.get_puzzle_share("2x2"), 0.5, "the Spread evenly button splits 50/50")
	check((labels["2x2"]["info"] as Label).text.contains("Solves/s"), "each row shows moves/s and Solves/s")
	main.free()
	game.reset_state()


func test_megaminx_model() -> void:
	var mega := PuzzleShapes.from_id("megaminx")
	check(mega != null and mega.notation_style == "pochmann", "megaminx builds with Pochmann notation")
	check(mega.piece_count() == 62, "62 pieces: 12 centres, 30 edges, 20 corners")
	var stickers := 0
	for normals in mega.sticker_normals:
		stickers += normals.size()
	check(stickers == 132, "132 stickers (11 per face)")
	check(mega._group.size() == 60, "the rotation group has 60 elements")
	check(mega.is_solved(), "starts solved")
	var all_back := true
	for face in mega.face_names.size():
		var move := mega.make_move(face, 1)
		for i in 5:
			mega.apply(move)
			if i < 4 and mega.is_solved():
				all_back = false
		all_back = all_back and mega.is_solved()
	check(all_back, "every face turn applied 5x is solved again (and not before)")
	var r_pp := mega.parse("R++")
	for i in 5:
		mega.apply(r_pp)
	check(mega.is_solved(), "R++ applied 5x is solved")
	var moves := mega.scramble(70, seeded_rng(5))
	check(not mega.is_solved(), "a 70-move scramble isn't solved")
	mega.apply_all(mega.inverse_sequence(moves))
	check(mega.is_solved(), "scramble + inverse = solved")
	check(mega.notation(mega.parse("R++")) == "R++" and mega.notation(mega.parse("D--")) == "D--", "R++ and D-- notation")
	check(mega.notation(mega.parse("U")) == "U" and mega.notation(mega.parse("U'")) == "U'", "U and U' notation")
	check(mega.notation(mega.parse("BL2'")) == "BL2'", "multi-letter faces: BL2'")
	var kinds := {}
	var rng := seeded_rng(6)
	var previous := {}
	var round_trip := true
	for i in 60:
		previous = mega.random_move(rng, previous)
		kinds[mega.notation(previous).trim_suffix("'").trim_suffix("+").trim_suffix("+").trim_suffix("-").trim_suffix("-")] = true
		round_trip = round_trip and mega.parse(mega.notation(previous)) == previous
	check(round_trip, "random scramble moves round-trip through notation")
	check(kinds.has("R") and kinds.has("D") and kinds.has("U"), "scrambles use R, D and U like WCA Megaminx scrambles")
	check(mega.face_names.has("F") and mega.face_names.has("DBL"), "WCA face names")
	check(PuzzleShapes.palette(mega).size() == 12, "12 colours")


func test_megaminx_view() -> void:
	var view := new_view()
	view.set_puzzle("megaminx")
	check(view._mega_pieces.size() == 62, "the Megaminx view has a node per piece")
	view.set_speed(5.0)
	for i in 60:
		view.scramble_step()
		if i % 4 == 0:
			view._process(0.05)
	view._process(5.0)
	view._process(0.0)
	check(view.is_idle(), "the Megaminx animation queue empties")
	var all_placed := true
	for piece in view.model.piece_count():
		var expected := Transform3D(view.model.piece_basis(piece), view.model.piece_position(piece))
		all_placed = all_placed and view._mega_pieces[piece].transform.is_equal_approx(expected)
	check(all_placed, "after animated turns every Megaminx piece is where the model says")
	view.set_puzzle("3x3")
	check(view._mega_pieces.is_empty() and view._bodies.multimesh != null, "switching back to a cube uses the MultiMeshes again")
	view.free()



func test_jukebox_locks() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var settings: GameSettings = root.get_node("Settings")
	settings.persistence_enabled = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var panel: Control = main.get_node("%SettingsPanel")
	panel.open()
	var rows: Array = panel._jukebox.get_children()
	check(rows.size() == Content.TRACKS.size(), "a Jukebox row per track")
	check(rows[0] is Button, "Practice Room (2x2) is playable from the start")
	check(rows[1] is Label and (rows[1] as Label).text.contains("Unlock 3×3 to hear this"), "First Sub-20 says unlock the 3x3")
	check((rows[5] as Label).text.contains("Unlock Megaminx"), "Twelve Faces says unlock the Megaminx")
	check((rows[6] as Label).text.contains("World Championship"), "Finals says win a World Championship")
	game.cheat_add_solves(1e13)
	game.unlock_puzzle("3x3")
	game.unlock_puzzle("4x4")
	game.unlock_puzzle("5x5")
	panel.sync()
	rows = panel._jukebox.get_children()
	var playable := 0
	for row in rows:
		if row is Button:
			playable += 1
	check(playable == 4, "after unlocking up to the 5x5, four tracks are playable")
	check(rows[4] is Label and (rows[4] as Label).text.contains("Unlock 7×7"), "Long Solve still needs the 7x7")
	panel.close()
	main.free()
	settings.persistence_enabled = true
	game.reset_state()


# --- Puzzle Mastery (task 4.6) -------------------------------------------------------

func test_mastery() -> void:
	var g := new_game()
	check(g.get_mastery_level("2x2") == 1 and g.get_mastery_xp("2x2") == 0.0, "puzzles start at mastery level 1")
	check_near(g.get_mastery_xp_per_solve("2x2"), 1.0, "a 2x2 solve gives 1 XP")
	check_near(g.get_mastery_xp_per_solve("4x4"), 7.5, "a 4x4 solve gives 7.5 XP (same XP per move)")
	check_near(g.get_mastery_xp_for_level(1), 25.0, "level 1 -> 2 needs 25 XP")
	var levels := []
	g.mastery_level_up.connect(func(id: String, level: int) -> void: levels.append([id, level]))
	g.add_moves_to("2x2", 8.0 * 25.0)  # 25 solves = 25 XP
	check(g.get_mastery_level("2x2") == 2, "25 XP reaches level 2")
	check(levels == [["2x2", 2]], "the level-up is signalled")
	check_near(g.get_puzzle_moves_mult("2x2"), 1.01, "level 2 gives +1 % moves on that puzzle")
	# Jump to level 10: milestones at 5 (+10 % moves) and 10 (-10 % moves per solve).
	var xp_10 := 0.0
	for l in range(1, 10):
		xp_10 += g.get_mastery_xp_for_level(l)
	g._add_mastery_xp("2x2", xp_10 - g.get_mastery_xp("2x2"))
	check(g.get_mastery_level("2x2") == 10, "enough XP reaches level 10")
	check(levels.size() == 9 and levels.back() == ["2x2", 10], "every level on the way is signalled once")
	check_near(g.get_puzzle_moves_mult("2x2"), (1.0 + 0.09) * 1.10, "level 10: +9 % per level and the level-5 +10 % moves")
	check_near(g.get_moves_per_solve("2x2"), 8.0 * 0.9, "level 10: 10 % fewer moves per solve")
	var before := g.total_moves
	g.add_moves_to("2x2", 10.0)
	check_near(g.total_moves - before, 10.0 * 1.09 * 1.10, "moves on a mastered puzzle are multiplied")
	check(g.get_next_mastery_milestone("2x2")["level"] == 25, "the next milestone is level 25")
	check(g.get_mastery_progress("2x2") >= 0.0 and g.get_mastery_progress("2x2") < 1.0, "progress through the level is 0..1")
	# Other puzzles are independent, except "all moves" milestones.
	g.cheat_add_solves(float(Content.get_puzzle("3x3")["unlock_cost"]))
	g.unlock_puzzle("3x3")
	check(g.get_mastery_level("3x3") == 1 and is_equal_approx(g.get_puzzle_moves_mult("3x3"), 1.0), "each puzzle has its own mastery")
	var xp_50 := 0.0
	for l in range(1, 50):
		xp_50 += g.get_mastery_xp_for_level(l)
	g._add_mastery_xp("2x2", xp_50 - g.get_mastery_xp("2x2"))
	check_near(g.get_puzzle_moves_mult("3x3"), 1.05, "a level-50 puzzle gives +5 % moves on every puzzle")
	check_near(g.get_solve_value("2x2"), 1.25, "level 25: +25 % Solves per solve")
	# Save round trip
	var data := g.get_save_data()
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.get_mastery_level("2x2") == 50 and is_equal_approx(loaded.get_mastery_xp("2x2"), g.get_mastery_xp("2x2")), "mastery survives save/load")
	g.free()
	loaded.free()


func test_save_v2_to_v3_migration() -> void:
	var v2 := {"version": 2, "saved_at": 1000.0, "solves": 10.0, "total_solves": 900.0, "total_moves": 9000.0,
		"puzzles": {"unlocked": ["2x2", "3x3"], "progress": {"3x3": 5.0}, "focus": "3x3", "split": {"3x3": 1.0}},
		"buildings": {"friend": 4}, "upgrades": ["lube"]}
	var g := new_game()
	g.apply_save_data(v2.duplicate(true), 1000.0)
	check(g.get_unlocked_puzzle_ids() == (["2x2", "3x3"] as Array[String]) and g.get_focused_puzzle_id() == "3x3", "v2 puzzles load into v3")
	check(g.get_mastery_level("2x2") == 1 and g.get_mastery_level("3x3") == 1, "v2 players start at mastery level 1")
	check(int(g.get_save_data()["version"]) == GameState.SAVE_VERSION, "it saves as the current version")
	g.free()


# --- Methods (task 5.1) -------------------------------------------------------------

func test_method_chain() -> void:
	var g := new_game()
	check(g.method == "beginner" and g.is_method_learned("beginner") and not g.is_method_learned("cfop"), "everyone starts with the Beginner Method")
	check_near(g.get_method_mult(), 1.0, "the Beginner Method changes nothing")
	check(g.get_next_method()["id"] == "cfop", "CFOP is next")
	check(not g.is_method_available("cfop"), "CFOP is hidden until half its cost is earned")
	g.cheat_add_solves(1e12)
	check(not g.is_method_available("roux") and not g.buy_method("roux"), "Roux can't be learned before CFOP")
	var bought := []
	g.purchased.connect(func(kind: String, id: String) -> void: bought.append([kind, id]))
	check(g.buy_method("cfop"), "start learning CFOP (it's Lab research since 5.6)")
	check(not g.is_method_learned("cfop") and bought.is_empty() and g.research["id"] == "method_cfop", "...it isn't learned until the research is done")
	check(not g.buy_method("cfop"), "...and can't be started twice")
	g.update_research(float(Content.get_method("cfop")["research_seconds"]) + 0.1)
	check(g.is_method_learned("cfop") and bought == [["method", "cfop"]], "learned when the research finishes, signalled as kind 'method'")
	check(not g.buy_method("cfop"), "a method can't be learned twice")
	check_near(g.solves, 1e12 - 200.0, "CFOP costs 200 Solves")
	check_near(g.get_moves_per_solve("2x2"), 8.0 * 0.7, "CFOP: 30 % fewer moves per solve")
	check(g.is_method_learned("beginner") and g.is_method_learned("cfop") and g.get_next_method()["id"] == "roux", "Roux is next")
	for id: String in ["roux", "zz", "gods_number"]:
		check(g.buy_method(id), "learn %s in order" % id)
		g.finish_research()
	check(g.method == "gods_number" and g.get_next_method().is_empty(), "God's Number ends the chain")
	check_near(g.get_method_mult(), pow(0.7, 4), "four methods: ×0.7 each")
	g.unlock_puzzle("3x3")
	check_near(g.get_moves_per_solve("3x3"), 20.0 * pow(0.7, 4), "the 3×3 isn't at its floor yet")
	# Save round trip, and an unknown id
	var data := g.get_save_data()
	check(data["method"] == "gods_number", "the method is saved")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.method == "gods_number", "the method survives save/load")
	data["method"] = "blindfolded"
	loaded.apply_save_data(data, float(data["saved_at"]))
	check(loaded.method == "beginner", "an unknown method id falls back to the Beginner Method")
	g.free()
	loaded.free()


func test_method_floor() -> void:
	var g := new_game()
	g.cheat_add_solves(1e12)
	for def: Dictionary in Content.METHODS.slice(1):
		g.buy_method(def["id"])
		g.finish_research()
	check_near(g.get_moves_floor("2x2"), 2.0, "the 2×2 can't go below 2 moves per solve")
	check(8.0 * g.get_method_mult() < 2.0, "...and every method together would push it below that")
	check_near(g.get_moves_per_solve("2x2"), 2.0, "so it stops at the floor")
	var xp_10 := 0.0
	for l in range(1, 10):
		xp_10 += g.get_mastery_xp_for_level(l)
	g._add_mastery_xp("2x2", xp_10)
	check_near(g.get_moves_per_solve("2x2"), 2.0, "mastery's fewer-moves perk can't break the floor either")
	var solves_before := g.total_solves
	g.add_moves_to("2x2", 21.0 / g.get_puzzle_moves_mult("2x2"))  # 21 real moves = 10 solves at the floor
	check_near(g.total_solves - solves_before, 10.0 * g.get_solve_value("2x2"), "solves at the floor take exactly the floor's moves")
	check_near(g.get_moves_floor("megaminx"), 140.0, "every puzzle has its own floor")
	g.free()


func test_save_v3_to_v4_migration() -> void:
	var v3 := {"version": 3, "saved_at": 1000.0, "solves": 10.0, "total_solves": 90000.0, "total_moves": 9000.0,
		"puzzles": {"unlocked": ["2x2", "3x3"], "progress": {"3x3": 5.0}, "focus": "3x3", "split": {"3x3": 1.0}},
		"mastery": {}, "buildings": {"friend": 4}, "upgrades": ["lube", "cfop", "magnets"]}
	var g := new_game()
	g.apply_save_data(v3.duplicate(true), 1000.0)
	check(g.method == "cfop", "the old CFOP upgrade becomes the CFOP method")
	check(g.upgrades.has("lube") and g.upgrades.has("magnets") and not g.upgrades.has("cfop"), "...and leaves the upgrade list; other upgrades stay")
	check_near(g.get_moves_per_solve("3x3"), 20.0 * 0.7, "a migrated CFOP player has 30 % fewer moves per solve")
	var data := g.get_save_data()
	check(int(data["version"]) == GameState.SAVE_VERSION and data["method"] == "cfop" and not (data["upgrades"] as Array).has("cfop"), "it saves as v4")
	var roux_only := v3.duplicate(true)
	roux_only["upgrades"] = ["roux"]  # v3 let you buy Roux without CFOP
	g.apply_save_data(roux_only, 1000.0)
	check(g.method == "roux" and g.is_method_learned("cfop") and g.upgrades.is_empty(), "the old Roux upgrade becomes Roux, with CFOP learned too")
	var neither := v3.duplicate(true)
	neither["upgrades"] = ["lube"]
	g.apply_save_data(neither, 1000.0)
	check(g.method == "beginner" and g.upgrades.has("lube"), "without either it's the Beginner Method")
	var v1 := {"version": 1, "saved_at": 1000.0, "solves": 5.0, "total_solves": 50.0, "move_progress": 3.0, "buildings": {}, "upgrades": ["cfop", "roux"]}
	g.apply_save_data(v1, 1000.0)
	check(g.method == "roux" and g.upgrades.is_empty(), "a v1 save migrates all the way to v4")
	g.free()


func test_method_tiles() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var cfop: UpgradeTile = main._method_tiles["cfop"]
	check(not cfop.visible, "no method tile at the start")
	check(not main._method_tiles.has("beginner"), "the Beginner Method has no tile (everyone has it)")
	game.cheat_add_solves(300.0)
	main._refresh()
	check(cfop.visible and not cfop.owned and not cfop.disabled, "CFOP shows up as a buyable tile once it's in reach")
	var first_visible: UpgradeTile = null
	for child in (main.get_node("%UpgradeList") as GridContainer).get_children():
		if (child as UpgradeTile).visible:
			first_visible = child
			break
	check(first_visible == cfop, "the next method comes first in the grid")
	check(cfop._description.contains("2×2: 8 → 5.6 moves per solve"), "its tooltip says what it does to the focused puzzle")
	cfop.pressed.emit()
	main._refresh()
	check(game.research.get("id", "") == "method_cfop" and cfop._cost.text.begins_with("Researching"), "pressing the tile starts researching CFOP")
	game.finish_research()
	main._refresh()
	check(game.method == "cfop" and cfop.owned and cfop._cost.text == "Owned", "once it's done CFOP is learned; it stays as an Owned tile")
	check(not main._method_tiles["roux"].visible, "Roux stays hidden until it's in reach")
	main.free()
	game.reset_state()



func test_variety_bonus() -> void:
	var g := new_game()
	g.cheat_add_solves(5.0)
	g.buy_building("friend")
	check_near(g.get_puzzle_moves_per_second("2x2"), g.get_moves_per_second(), "one puzzle: no bonus, all helper moves")
	check_near(g.get_puzzle_variety_bonus("2x2"), 1.0, "...a ×1 variety bonus")
	g.cheat_add_solves(1e6)
	g.unlock_puzzle("3x3")
	g.set_split({"2x2": 0.1, "3x3": 0.9})
	var e := float(Content.VARIETY["exponent"])
	check_near(g.get_puzzle_variety_bonus("2x2"), pow(0.1, e) / 0.1, "a 10 %% share gets a ×%.1f bonus" % (pow(0.1, e) / 0.1))
	check(g.get_puzzle_variety_bonus("2x2") > g.get_puzzle_variety_bonus("3x3"), "smaller shares get bigger bonuses")
	var before := g.total_moves
	g.add_helper_moves(10.0)
	check_near(g.total_moves - before, g.get_moves_per_second() * 10.0 * (pow(0.1, e) + pow(0.9, e)), "10 s of helpers adds share^exponent of the moves to each puzzle")
	# Spreading beats focusing for income once there's more than one puzzle (the point of task 4.7).
	g.set_split_preset("newest")
	var focused := g.get_solves_per_second()
	var sim: RefCounted = load("res://tools/simulator.gd").new()
	sim.choose_split(g)
	check(g.get_solves_per_second() > focused, "the bot's mixed split earns more than everything on the newest puzzle")
	var top := 0.0
	for id: String in g.get_split():
		top = maxf(top, float(g.get_split()[id]))
	check(top < 0.99, "...and it really is a mix")
	g.free()


# --- Solve Station (task S.1) -------------------------------------------------------

func test_rotation_and_slice_notation() -> void:
	var cube := PuzzleShapes.cube(3)
	var f := cube.face_names
	check(cube.parse("x") == cube.make_move(f.find("R"), 1, 3), "x is every layer turning like R")
	check(cube.notation(cube.make_move(f.find("L"), 1, 3)) == "x'", "every layer turning like L is x'")
	check(cube.notation(cube.make_move(f.find("D"), 2, 3)) == "y2", "...like D twice is y2")
	check(cube.parse("M") == cube.make_move(f.find("L"), 1, 1, 1), "M is the middle layer turning like L")
	check(cube.notation(cube.make_move(f.find("R"), 1, 1, 1)) == "M'", "the middle layer turning like R is M'")
	var round_trip := true
	for text: String in ["x", "x'", "x2", "y", "y'", "y2", "z", "z'", "z2", "M", "M'", "M2", "E", "E'", "E2", "S", "S'", "S2"]:
		round_trip = round_trip and cube.notation(cube.parse(text)) == text
	check(round_trip, "x y z M E S (and primes and doubles) round-trip on a 3×3")
	check(cube.parse("r") == cube.parse("Rw") and cube.parse("u'") == cube.parse("Uw'"), "lowercase r is Rw")
	check(PuzzleShapes.cube(4).parse("l2") == PuzzleShapes.cube(4).parse("Lw2"), "...on a 4×4 too")
	check(PuzzleShapes.cube(2).parse("r").is_empty(), "r on a 2×2 would be a rotation, so it's not a move")
	check(PuzzleShapes.cube(4).parse("M").is_empty() and PuzzleShapes.cube(2).parse("E").is_empty(), "M/E/S only on the 3×3")
	check(PuzzleShapes.cube(4).notation(PuzzleShapes.cube(4).parse("y")) == "y", "rotations on big cubes are named too")
	cube.apply(cube.parse("x"))
	check(cube.is_solved(), "a rotation doesn't unsolve the cube")
	check(cube.color_at(Vector3(0, 1, 0), f.find("U")) == cube.face_colors[f.find("F")], "x brings F to the top (like R)")
	cube.reset()
	cube.apply(cube.parse("M"))
	check(cube.color_at(Vector3(0, 0, 1), f.find("F")) == cube.face_colors[f.find("U")], "M brings the U centre to the front (like L)")
	cube.reset()
	cube.apply(cube.parse("E"))
	check(cube.color_at(Vector3(1, 0, 0), f.find("R")) == cube.face_colors[f.find("F")], "E brings the F centre to the right (like D)")
	cube.reset()
	cube.apply(cube.parse("S"))
	check(cube.color_at(Vector3(1, 0, 0), f.find("R")) == cube.face_colors[f.find("U")], "S brings the U centre to the right (like F)")


func test_solve_keys_cstimer_layout() -> void:
	var session := SolveSession.new()
	session.start("3x3", 0.0)
	var expected := {
		KEY_I: "R", KEY_K: "R'", KEY_J: "U", KEY_F: "U'", KEY_H: "F", KEY_G: "F'", KEY_D: "L", KEY_E: "L'",
		KEY_S: "D", KEY_L: "D'", KEY_W: "B", KEY_O: "B'", KEY_SEMICOLON: "y", KEY_A: "y'", KEY_T: "x", KEY_Y: "x",
		KEY_B: "x'", KEY_N: "x'", KEY_P: "z", KEY_Q: "z'", KEY_U: "Rw", KEY_M: "Rw'", KEY_V: "Lw", KEY_R: "Lw'",
		KEY_5: "M", KEY_6: "M", KEY_X: "M'", KEY_PERIOD: "M'", KEY_2: "E", KEY_9: "E'", KEY_0: "S", KEY_1: "S'",
		KEY_COMMA: "Uw", KEY_C: "Uw'", KEY_Z: "Dw", KEY_SLASH: "Dw'",
	}
	var all_match := true
	for key: int in expected:
		var got := session.model.notation(session.move_for_key(key))
		if got != expected[key]:
			all_match = false
			print("  key %s: expected %s, got %s" % [OS.get_keycode_string(key), expected[key], got])
	check(all_match, "every key makes csTimer's move on a 3×3")
	check(expected.size() == Content.SOLVE_KEYS.size(), "...and every mapped key is checked")
	check(session.move_for_key(KEY_F1).is_empty(), "unmapped keys do nothing")
	var small := SolveSession.new()
	small.start("2x2", 0.0)
	check(small.move_for_key(KEY_2).is_empty(), "no E slice on a 2×2")
	check(small.model.notation(small.move_for_key(KEY_U)) == "x", "r on a 2×2 turns the whole cube, like csTimer")
	var big := SolveSession.new()
	big.start("5x5", 0.0)
	check(big.model.notation(big.move_for_key(KEY_I)) == "R", "5×5: I is R with the hand outside")
	big.press_key(KEY_7, 0.0)
	check(big.right_hand == 2 and big.model.notation(big.move_for_key(KEY_I)) == "Rw", "7 moves the right hand in: I is now Rw")
	check(big.model.notation(big.move_for_key(KEY_PERIOD)) == "3R", "...and . turns the third layer")
	big.press_key(KEY_4, 0.0)
	check(big.left_hand == 2 and big.model.notation(big.move_for_key(KEY_E)) == "Lw'", "4 moves the left hand in")
	for i in 6:
		big.press_key(KEY_7, 0.0)
	check(big.right_hand == 4, "hands stop one layer short of the far side")
	big.press_key(KEY_SPACE, 0.0)
	check(big.left_hand == 1 and big.right_hand == 1, "Space puts both hands back")
	check(big.press_key(KEY_8, 0.0).is_empty() and big.right_hand == 1, "hand keys don't turn anything, and stop at the outside")


func test_solve_session() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var session := SolveSession.new()
	check(not session.start("megaminx", 0.0), "the Megaminx isn't in the station yet")
	check(session.start("3x3", 0.0, rng), "start a 3×3 attempt")
	check(session.scramble.size() == int(Content.get_puzzle("3x3")["scramble_length"]), "the scramble has the 3×3's length")
	check(not session.model.is_solved() and session.state == "inspecting", "scrambled, inspection running")
	check(session.scramble_text().split(" ").size() == session.scramble.size(), "the scramble reads as WCA notation")
	session.press_key(KEY_SEMICOLON, 3.0)
	check(session.state == "inspecting" and session.moves == 0, "a rotation during inspection doesn't start the timer")
	check_near(session.inspection_left(5.0), 10.0, "inspection counts down from 15 s")
	# Undo the rotation, then the scramble, one turn every 0.5 s from 5 s.
	session.press_key(KEY_A, 4.0)
	var solution := session.model.inverse_sequence(session.scramble)
	var now := 5.0
	for move: Dictionary in solution:
		session.turn(move, now)
		now += 0.5
		if session.state == "done" and move != solution.back():
			check(false, "done before the last turn")
	check(session.state == "done", "solving the puzzle stops the timer")
	check_near(session.elapsed(100.0), 0.5 * (solution.size() - 1), "the time runs from the first turn to the solving one")
	check(session.moves == solution.size() and session.penalty == "", "every turn is counted; started in time, no penalty")
	check(session.results.size() == 1 and session.results[0]["scramble"] == session.scramble_text(), "the result is recorded")
	check_near(session.tps(100.0), solution.size() / session.elapsed(100.0), "TPS = moves / time")
	session.turn(session.model.parse("R"), 120.0)
	check(session.results.size() == 1 and session.state == "done", "turning after the solve changes nothing")
	# Solved in another orientation still counts.
	session.start("3x3", 200.0, rng)
	var m := session.model
	m.reset()
	m.apply(m.parse("x"))
	m.apply(m.parse("R"))
	m.apply(m.parse("U"))
	session.turn(m.parse("U'"), 201.0)
	check(session.state == "solving", "one turn left")
	session.turn(m.parse("R'"), 203.0)
	check(session.state == "done" and is_equal_approx(session.elapsed(0.0), 2.0), "solved upside down still stops the timer")


func test_solve_inspection_and_averages() -> void:
	check(SolveSession.inspection_penalty(15.0) == "", "starting at 15 s is fine")
	check(SolveSession.inspection_penalty(16.0) == "+2", "after 15 s: +2")
	check(SolveSession.inspection_penalty(17.5) == "DNF", "after 17 s: DNF")
	var session := SolveSession.new()
	session.start("2x2", 0.0)
	session.turn(session.model.parse("R"), 16.0)
	check(session.penalty == "+2" and session.state == "solving", "a late start is +2")
	session.start("2x2", 100.0)
	session.update(118.0)
	check(session.penalty == "DNF" and session.inspection_left(118.0) < 0.0, "sitting in inspection past 17 s is a DNF")
	session.inspection = false
	session.start("2x2", 200.0)
	check(session.state == "ready", "with inspection off the attempt is just ready")
	session.update(300.0)
	session.turn(session.model.parse("R"), 300.0)
	check(session.penalty == "" and session.state == "solving", "...and never gets a penalty")
	check(is_inf(SolveSession.final_time({"time": 9.0, "penalty": "DNF"})), "a DNF counts as infinitely slow")
	check_near(SolveSession.final_time({"time": 9.0, "penalty": "+2"}), 11.0, "+2 adds 2 s")
	session.results.clear()
	check(session.average(5) < 0.0, "no ao5 before 5 solves")
	for t: float in [10.0, 12.0, 11.0, 9.0, 13.0]:
		session.results.append({"time": t, "penalty": "", "moves": 50})
	check_near(session.average(5), 11.0, "ao5 drops the best and worst: (10 + 11 + 12) / 3")
	check_near(session.best(), 9.0, "best single")
	session.results.append({"time": 8.0, "penalty": "DNF", "moves": 50})
	check_near(session.average(5), 12.0, "one DNF is dropped as the worst (12, 11, 13 counted)")
	session.results.append({"time": 8.0, "penalty": "DNF", "moves": 50})
	check(is_inf(session.average(5)), "two DNFs make the average a DNF")
	check_near(SolveSession.trimmed_average([10.0, 10.0, 10.01, 10.0, 10.0] as Array[float]), 10.0, "averages round to the hundredth")
	check(Num.solve_time(9.876) == "9.87", "singles are truncated: 9.876 -> 9.87")
	check(Num.solve_time(62.345) == "1:02.34" and Num.solve_time(10.0) == "10.00", "minutes and trailing zeros")
	check(Num.solve_time(INF) == "DNF", "INF reads DNF")


func test_solve_station() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	root.get_node("Settings").persistence_enabled = false
	root.get_node("Settings").set_value("inspection", true)
	game.cheat_add_solves(1000.0)
	game.unlock_puzzle("3x3")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var station: Node = main.get_node("%SolveStation")
	check(not station.visible, "the station starts closed")
	(main.get_node("%SolveButton") as Button).pressed.emit()
	check(station.visible and station.session.puzzle_id == game.get_focused_puzzle_id(), "Solve it yourself opens it on the focused puzzle")
	check(station._picker_buttons.size() == 2, "the picker offers the unlocked cubes")
	station.select_puzzle("3x3")
	var view: PuzzleView3D = station.get_node("%View")
	check(view.model.orientations == station.session.model.orientations, "the view shows the session's scrambled cube")
	check((station.get_node("%ScrambleLabel") as Label).text == station.session.scramble_text(), "the scramble is shown")
	check(station.keys_help_text().contains("R I") and station.keys_help_text().contains("M 5/6"), "the key help is generated from the key map")
	# A real key event (physical key) turns the cube, and never reaches the main screen's tap.
	var before_moves := game.total_moves
	var event := InputEventKey.new()
	event.physical_keycode = KEY_J
	event.pressed = true
	station._input(event)
	view.finish_animations()
	check(station.session.moves == 1 and station.session.state == "solving", "pressing J (U) starts the solve")
	check(view.model.orientations == station.session.model.orientations, "the view follows the turn")
	var tap := InputEventAction.new()
	tap.action = &"tap"
	tap.pressed = true
	main._unhandled_input(tap)
	check(game.total_moves == before_moves, "Space/Enter taps don't reach the idle game while the station is open")
	# Solve it with keys: undo U, then the scramble, quarter turns only.
	var key_for := {}
	for key: int in Content.SOLVE_KEYS:
		var name: String = station.session.model.notation(station.session.move_for_key(key))
		if not key_for.has(name):
			key_for[name] = key
	var keys: Array[int] = [KEY_F]
	for move: Dictionary in station.session.model.inverse_sequence(station.session.scramble):
		var quarter: Dictionary = station.session.model.make_move(int(move["face"]), signi(int(move["turns"])))
		for i in absi(int(move["turns"])):
			keys.append(key_for[station.session.model.notation(quarter)])
	for key in keys:
		station.handle_key(key)
	view.finish_animations()
	check(station.session.state == "done", "solving with the keyboard finishes the attempt")
	check((station.get_node("%TimerLabel") as Label).theme_type_variation == &"TimerDone", "the timer turns green")
	check(game.get_solve_history("3x3").size() == 1 and game.get_hand_solve_count("3x3") == 1, "the solve is recorded in GameState")
	check(station.last_info.get("pb_single", false), "the first solve is a PB single")
	var rows := station.get_node("%TimesRows") as VBoxContainer
	check(rows.get_child_count() == 1 and (rows.get_child(0).get_child(0) as Label).text.begins_with("1."), "it shows in the times list")
	(rows.get_child(0).get_child(2) as Button).pressed.emit()  # DNF
	check(game.get_solve_history("3x3")[0]["p"] == "DNF", "the row's DNF button sets the penalty")
	station._refresh()
	(rows.get_child(0).get_child(3) as Button).pressed.emit()  # ×
	check(game.get_solve_history("3x3").is_empty(), "the × button deletes the time")
	check(view.model.is_solved(), "the view shows it solved")
	station.handle_key(KEY_ENTER)
	check(station.session.state == "inspecting" and not station.session.model.is_solved(), "Enter scrambles the next attempt")
	station.handle_key(KEY_ESCAPE)
	check(_closed(station), "Esc closes the station")
	main.free()
	game.reset_state()


# --- Solve records (task S.2) -------------------------------------------------------

func test_solve_records() -> void:
	var g := new_game()
	var changes := []
	g.solve_records_changed.connect(func(id: String) -> void: changes.append(id))
	check(g.get_solve_history("3x3").is_empty() and is_inf(float(g.get_solve_bests("3x3")["single"])), "no records at the start")
	check(g.record_hand_solve("nope", 10.0, "", 50).is_empty() and g.record_hand_solve("3x3", 10.0, "+3", 50).is_empty(), "bad input is ignored")
	var info := g.record_hand_solve("3x3", 12.0, "", 50)
	check(info["pb_single"] and is_equal_approx(float(info["final"]), 12.0), "the first solve is a PB")
	check(changes == ["3x3"], "recording is signalled")
	check(not g.record_hand_solve("3x3", 13.0, "", 50)["pb_single"], "a slower solve isn't")
	check(g.record_hand_solve("3x3", 11.0, "+2", 50)["pb_single"] == false, "11 + 2 = 13 isn't a PB either")
	check(g.record_hand_solve("3x3", 9.0, "", 50)["pb_single"], "9 is")
	info = g.record_hand_solve("3x3", 10.0, "", 50)
	check(info["pb_averages"] == [5], "the fifth solve sets the first ao5")
	check_near(g.get_current_average("3x3", 5), 11.67, "ao5 of 12, 13, 13 (+2), 9, 10 = (10 + 12 + 13) / 3, rounded")
	check(g.get_current_average("3x3", 12) < 0.0, "no ao12 yet")
	check(g.set_hand_solve_penalty("3x3", 3, "DNF"), "mark the 9 as a DNF")
	check_near(float(g.get_solve_bests("3x3")["single"]), 10.0, "the PB single is recomputed without it")
	check_near(g.get_current_average("3x3", 5), 12.67, "one DNF is dropped as the worst: (12 + 13 + 13) / 3")
	check(g.delete_hand_solve("3x3", 0) and g.get_solve_history("3x3").size() == 4, "delete a time")
	check(g.get_hand_solve_count("3x3") == 5, "the all-time count keeps deleted solves")
	check(not g.set_hand_solve_penalty("3x3", 99, "") and not g.delete_hand_solve("3x3", -1), "bad indices are refused")
	# ao50 trims 3 each side (csTimer): 47 good times and 3 DNFs is still an average, 4 DNFs isn't.
	var times: Array[float] = []
	for i in 47:
		times.append(10.0)
	for i in 3:
		times.append(INF)
	check_near(SolveSession.trimmed_average(times, SolveSession.trim_count(50)), 10.0, "ao50 survives 3 DNFs")
	times[0] = INF
	check(is_inf(SolveSession.trimmed_average(times, SolveSession.trim_count(50))), "...but not 4")
	check(SolveSession.trim_count(5) == 1 and SolveSession.trim_count(12) == 1 and SolveSession.trim_count(100) == 5, "trim sizes")
	# History cap: bests set before old solves drop off are kept.
	var capped := new_game()
	capped.record_hand_solve("2x2", 1.5, "", 10)
	for i in GameState.SOLVE_HISTORY_LIMIT:
		capped.record_hand_solve("2x2", 5.0, "", 10)
	check(capped.get_solve_history("2x2").size() == GameState.SOLVE_HISTORY_LIMIT, "the history keeps the last 1000 solves")
	check_near(float(capped.get_solve_bests("2x2")["single"]), 1.5, "an old PB survives dropping out of the history")
	# Save round trip
	var data := g.get_save_data()
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.get_solve_history("3x3").size() == 4 and loaded.get_hand_solve_count("3x3") == 5, "records survive save/load")
	check(loaded.get_solve_history("3x3")[2]["p"] == "DNF", "...penalties too")
	check_near(float(loaded.get_solve_bests("3x3")["single"]), float(g.get_solve_bests("3x3")["single"]), "...and the bests are rebuilt")
	g.free()
	capped.free()
	loaded.free()


func test_save_v4_to_v5_migration() -> void:
	var v4 := {"version": 4, "saved_at": 1000.0, "solves": 10.0, "total_solves": 900.0, "total_moves": 9000.0,
		"puzzles": {"unlocked": ["2x2", "3x3"], "progress": {}, "focus": "3x3", "split": {"3x3": 1.0}},
		"mastery": {}, "buildings": {"friend": 4}, "upgrades": ["lube"], "method": "cfop"}
	var g := new_game()
	g.apply_save_data(v4.duplicate(true), 1000.0)
	check(g.method == "cfop" and g.buildings["friend"] == 4, "a v4 save loads")
	check(g.get_solve_history("3x3").is_empty() and g.get_hand_solve_count("3x3") == 0, "with no hand solves yet")
	var data := g.get_save_data()
	check(int(data["version"]) >= 5 and data.has("solve_records"), "it saves as v5 (or later)")
	var junk := data.duplicate(true)
	junk["solve_records"] = {"3x3": {"history": [{"t": 8.5, "p": "+7", "m": 40}, "bad", {"t": -1.0}], "count": 1}, "pyraminx": {}}
	g.apply_save_data(junk, float(data["saved_at"]))
	check(g.get_solve_history("3x3").size() == 1 and g.get_solve_history("3x3")[0]["p"] == "", "damaged entries are cleaned up")
	g.free()


# --- Staged solver (task R.1) -----------------------------------------------------

## Scrambles `count` cubes, solves each with `method`, applies the stages one by one and checks every stage's goal and
## the end. Returns [failures, average solve ms, average moves].
func _check_staged_solves(puzzle_id: String, method: String, count: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var bad := 0
	var stage_misses := {}
	var total_usec := 0
	var total_moves := 0
	for i in count:
		var model := PuzzleShapes.from_id(puzzle_id)
		model.scramble(25, rng)
		var start := Time.get_ticks_usec()
		var stages := StagedSolver.solve(model, method)
		total_usec += Time.get_ticks_usec() - start
		for stage: Dictionary in stages:
			model.apply_all(stage["moves"])
			if stage["id"] != "inspection":
				total_moves += (stage["moves"] as Array).size()
				if not StagedSolver.is_stage_done(model, stage["id"]):
					stage_misses[stage["id"]] = true
		if not model.is_solved():
			bad += 1
	check(stage_misses.is_empty(), "%s %s: every stage reaches its goal (missed: %s)" % [puzzle_id, method, stage_misses.keys()])
	return [bad, total_usec / 1000.0 / count, float(total_moves) / count]


func test_staged_solver_solves() -> void:
	var start := Time.get_ticks_usec()
	StagedSolver.warm_up("3x3")
	StagedSolver.warm_up("2x2")
	var warm_ms := (Time.get_ticks_usec() - start) / 1000.0
	check(warm_ms < 3000.0, "warming up the solver takes well under a few seconds (took %.0f ms)" % warm_ms)
	var expected_stages := {
		"cfop": ["inspection", "cross", "f2l_1", "f2l_2", "f2l_3", "f2l_4", "oll", "pll"],
		"beginner": ["inspection", "cross", "first_layer", "second_layer", "yellow_cross", "yellow_edges", "corner_cycle",
				"corner_twist"],
		"roux": ["inspection", "first_block", "second_block", "cmll", "lse"],  # R.5
		"zz": ["inspection", "eoline", "zz_f2l", "last_layer"],
	}
	for method: String in ["cfop", "beginner", "roux", "zz"]:
		var result := _check_staged_solves("3x3", method, 200, 11)
		check(result[0] == 0, "3x3 %s: 200 random scrambles are all solved (%d failed)" % [method, result[0]])
		check(result[1] < 50.0, "3x3 %s: a solve takes under 50 ms on average after warm-up (%.1f ms)" % [method, result[1]])
		var model := PuzzleShapes.from_id("3x3")
		model.scramble(25)
		var ids := []
		for stage: Dictionary in StagedSolver.solve(model, method):
			ids.append(stage["id"])
			check(stage["name"] != "" and stage["name"] != stage["id"], "stage %s has a display name" % stage["id"])
		check(ids == expected_stages[method], "3x3 %s has the expected stages (got %s)" % [method, ids])
	# Realistic lengths: 2-look CFOP is ~55-70 moves, the beginner method ~100-140.
	var cfop := _check_staged_solves("3x3", "cfop", 30, 12)
	var beginner := _check_staged_solves("3x3", "beginner", 30, 12)
	check(cfop[2] > 45.0 and cfop[2] < 75.0, "a CFOP solve is about 55-70 moves (%.1f)" % cfop[2])
	check(beginner[2] > cfop[2] + 25.0, "the beginner method takes clearly more moves (%.1f)" % beginner[2])
	var roux := _check_staged_solves("3x3", "roux", 30, 12)
	var zz := _check_staged_solves("3x3", "zz", 30, 12)
	check(roux[2] > 40.0 and roux[2] < cfop[2] + 5.0, "a Roux solve is short, about 45-60 moves (%.1f)" % roux[2])
	check(zz[2] > 50.0 and zz[2] < 80.0, "a ZZ solve is about 55-70 moves (%.1f)" % zz[2])
	for method: String in ["cfop", "beginner"]:
		var result := _check_staged_solves("2x2", method, 200, 13)
		check(result[0] == 0, "2x2 %s: 200 random scrambles are all solved (%d failed)" % [method, result[0]])
		check(result[1] < 50.0, "2x2 %s: under 50 ms on average (%.1f ms)" % [method, result[1]])


func test_staged_solver_details() -> void:
	# WCA scrambles are held white on top, green in front; the solver turns the cube over for a white cross (z2 keeps
	# green in front), like a real solver in inspection.
	var model := PuzzleShapes.from_id("3x3")
	model.scramble(25)
	var stages := StagedSolver.solve(model, "cfop")
	var inspection := model.notation_sequence(stages[0]["moves"])
	check(inspection in ["z2", "z2 y", "z2 y'", "z2 y2"], "a CFOP solve starts with z2 (and maybe a y) in inspection: %s" % inspection)
	var cross_moves: Array = stages[1]["moves"]
	check(cross_moves.size() <= 8, "the cross is planned in at most 8 moves (%d)" % cross_moves.size())
	# The input model is never changed.
	var copy := model.orientations.duplicate()
	StagedSolver.solve(model, "beginner")
	check(model.orientations == copy, "solve() leaves the model alone")
	# Already solved: every stage is a skip, nothing but the z2.
	var solved := PuzzleShapes.from_id("3x3")
	var total := 0
	for stage: Dictionary in StagedSolver.solve(solved, "cfop"):
		if stage["id"] != "inspection":
			total += (stage["moves"] as Array).size()
	check(total == 0, "a solved cube needs no moves")
	# Held in another orientation (e.g. after rotations in the Solve Station): still solved.
	var turned := PuzzleShapes.from_id("3x3")
	turned.apply_all(turned.parse_sequence("x y'"))
	turned.scramble(20)
	for stage: Dictionary in StagedSolver.solve(turned, "cfop"):
		turned.apply_all(stage["moves"])
	check(turned.is_solved(), "a cube held in another orientation is solved too")
	# God's Number has no stages of its own in the solver (the showcase plays it): CFOP; unsupported puzzles give nothing.
	var roux := PuzzleShapes.from_id("3x3")
	roux.scramble(25)
	var roux_stages := StagedSolver.solve(roux, "gods_number")
	check(roux_stages.size() == 8 and roux_stages[6]["id"] == "oll", "God's Number falls back to CFOP in the solver")
	# Roux's LSE uses only M and U; ZZ's F2L only R, U and L (R.5). ZZ with the full OLL/PLL sets solves too.
	var lse_faces := {}
	var f2l_faces := {}
	var face_rng := RandomNumberGenerator.new()
	face_rng.seed = 31
	for i in 10:
		var cube := PuzzleShapes.from_id("3x3")
		cube.scramble(25, face_rng)
		for move: Dictionary in StagedSolver.solve(cube, "roux")[-1]["moves"]:
			lse_faces[cube.notation(move).left(1)] = true
		for move: Dictionary in StagedSolver.solve(cube, "zz")[2]["moves"]:
			f2l_faces[cube.notation(move).left(1)] = true
		var full := PuzzleShapes.from_id("3x3")
		full.orientations = cube.orientations.duplicate()
		for stage: Dictionary in StagedSolver.solve(cube, "zz", {"full_oll": true, "full_pll": true}):
			full.apply_all(stage["moves"])
		check(full.is_solved(), "ZZ with full OLL/PLL solves scramble %d" % i)
	check(not lse_faces.is_empty() and lse_faces.keys().all(func(f: String) -> bool: return f in ["M", "U"]),
			"Roux LSE is M and U only: %s" % str(lse_faces.keys()))
	check(not f2l_faces.is_empty() and f2l_faces.keys().all(func(f: String) -> bool: return f in ["R", "U", "L"]),
			"ZZ F2L is R, U and L only: %s" % str(f2l_faces.keys()))
	check(StagedSolver.supports("3x3") and StagedSolver.supports("2x2"), "3x3 and 2x2 are supported")
	check(not StagedSolver.supports("4x4") and not StagedSolver.supports("megaminx"), "bigger cubes come in R.6")
	check(StagedSolver.solve(PuzzleShapes.from_id("4x4")).is_empty(), "an unsupported puzzle gives no stages")
	check(StagedSolver.solve(PuzzleShapes.from_id("megaminx")).is_empty(), "...the Megaminx too")
	# Beginner's last step is the real R' D' R D corner twist.
	var b := PuzzleShapes.from_id("3x3")
	b.scramble(25)
	var twist := ""
	for stage: Dictionary in StagedSolver.solve(b, "beginner"):
		if stage["id"] == "corner_twist":
			twist = b.notation_sequence(stage["moves"])
	check(twist == "" or "R' D' R D" in twist, "the beginner corner twist uses R' D' R D (%s)" % twist)
	# Looks right to a speedcuber: pairs, first-layer corners and middle edges go in at the front (R, L, F and U turns),
	# with y turns of the whole cube to bring a back slot round, never B turns.
	var back := 0
	var rotations := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for method: String in ["cfop", "beginner"]:
		for i in 30:
			var cube := PuzzleShapes.from_id("3x3")
			cube.scramble(25, rng)
			for stage: Dictionary in StagedSolver.solve(cube, method):
				if not (stage["id"].begins_with("f2l") or stage["id"] in ["first_layer", "second_layer", "corner_cycle"]):
					continue
				for move: Dictionary in stage["moves"]:
					if cube.face_names[int(move["face"])] == "B":
						back += 1
					if cube.is_rotation(move):
						rotations += 1
	check(back == 0, "F2L and the beginner layers never turn B (%d B turns)" % back)
	check(rotations > 30, "...they turn the cube with y instead (%d y turns in 60 solves)" % rotations)
	# simplify() merges turns of the same layer.
	var m := PuzzleShapes.from_id("3x3")
	check(m.notation_sequence(StagedSolver.simplify(m, m.parse_sequence("R R U U' F F F"))) == "R2 F'", "R R U U' F F F -> R2 F'")


## Every algorithm in Content.ALGORITHMS parses, and does what its set promises on a solved 3×3 (white on top).
func test_algorithm_data() -> void:
	var ids := {}
	for alg: Dictionary in Content.ALGORITHMS:
		check(not ids.has(alg["id"]), "algorithm id %s is unique" % alg["id"])
		ids[alg["id"]] = true
		check(alg["set"] in ["OLL", "PLL", "Beginner"], "%s has a known set" % alg["id"])
		var model := PuzzleShapes.from_id("3x3")
		var moves := model.parse_sequence(alg["alg"])
		check(not moves.is_empty(), "%s parses: %s" % [alg["id"], alg["alg"]])
		if alg.get("full", false) and not alg.get("two_look", false):
			continue  # full-set algorithms are checked relative to the centres in test_full_oll_pll_data (V perm has a y)
		model.apply_all(moves)
		var keeps: String = {"OLL": "f2l", "PLL": "f2l_and_top_color", "Beginner": ""}[alg["set"]]
		match alg["id"]:
			"beg_yellow_cross", "beg_yellow_edges", "beg_corner_cycle":
				keeps = "f2l"
			"beg_edge_right", "beg_edge_left":
				keeps = "bottom"
		if keeps == "":
			continue
		var kept := true
		for piece in model.piece_count():
			var home := model.home_positions[piece]
			if model.sticker_normals[piece].size() == 1:  # centres: must stay put (spinning in place looks the same)
				if model.piece_position(piece).distance_to(home) > 0.01:
					kept = false
				continue
			var must_stay := home.y < -0.5 if keeps == "bottom" else home.y < 0.5
			if must_stay and model.orientations[piece] != 0:
				kept = false
		if keeps == "f2l_and_top_color":
			for piece in model.piece_count():
				for s in model.sticker_normals[piece].size():
					var facing := model.piece_basis(piece) * model.sticker_normals[piece][s]
					if facing.y > 0.99 and model.sticker_colors[piece][s] != PuzzleShapes.COLOR_WHITE:
						kept = false
		check(kept, "%s keeps the %s in place" % [alg["id"], keeps.replace("_", " ")])
	# The two that are used repeatedly: R U R' U' six times, and R' D' R D six times, are back to solved.
	for id: String in ["beg_corner", "beg_corner_twist"]:
		var model := PuzzleShapes.from_id("3x3")
		for i in 6:
			model.apply_all(model.parse_sequence(Content.get_algorithm(id)["alg"]))
		check(model.is_solved(), "%s six times is back to solved" % id)


# --- Showcase solve (task R.2) -----------------------------------------------------

func test_showcase_solve_rules() -> void:
	# Speed: from the method, a bit more per 10× moves/s, capped, and never faster than the real moves.
	check_near(ShowcaseSolve.tps_for("beginner", 0.0), 0.0, "no helpers: the showcase only moves on taps")
	check_near(ShowcaseSolve.tps_for("beginner", 0.5), 0.5, "one Friend (0.5 moves/s): half a turn a second")
	check(ShowcaseSolve.tps_for("beginner", 10.0) > 3.0 and ShowcaseSolve.tps_for("beginner", 10.0) < 5.0, "Beginner ~3-4 TPS")
	check(ShowcaseSolve.tps_for("cfop", 1e5) > ShowcaseSolve.tps_for("beginner", 1e5), "CFOP turns faster than Beginner")
	check_near(ShowcaseSolve.tps_for("gods_number", 1e30), float(Content.SHOWCASE["max_tps"]), "capped at max_tps")
	# A whole solve played by time: inspection, every stage, solved, then a new scramble.
	var show := ShowcaseSolve.new("3x3", "cfop", 3)
	var events := []
	show.started.connect(func() -> void: events.append("started"))
	show.finished.connect(func() -> void: events.append("finished"))
	var view_model := PuzzleShapes.from_id("3x3")
	view_model.apply_all(show.scramble)
	check(show.phase == "inspection" and not view_model.is_solved(), "it starts on a scrambled cube, inspecting")
	var played := 0
	for i in 2000:
		for move in show.advance(0.05, 8.0):
			view_model.apply(move)
			played += 1
		if show.phase == "solved":
			break
	check(show.phase == "solved" and events == ["finished"], "playing on finishes the solve")
	check(view_model.is_solved() and show.model.is_solved(), "the moves it returns really solve the scramble")
	check(played > 40 and played < 90, "a CFOP showcase is a real-length solve (%d moves incl. inspection)" % played)
	for i in 40:  # 2 s: past the 1.4 s hold, still inspecting the next one
		show.advance(0.05, 8.0)
	check(events == ["finished", "started"] and show.phase == "inspection", "after a moment it starts the next scramble")
	# Taps: end inspection and play the next move at once, even with no helpers.
	var tapped := ShowcaseSolve.new("3x3", "beginner", 4)
	var first := tapped.tap()
	check(tapped.phase == "solving" and first.size() >= 2, "a tap in inspection does the inspection turns and the first move")
	check(tapped.advance(10.0, 0.0).is_empty(), "with 0 TPS nothing moves by itself")
	var before := tapped.move_index
	check(tapped.tap().size() == 1, "each tap is one move")
	check(tapped.move_index == before + 1 or tapped.move_index == 0, "...the next one")
	# A method learned mid-solve is used from the next scramble on.
	tapped.method = "cfop"
	check(tapped.current_stage()["id"] in ["cross", "first_layer"], "the current solve keeps its stages")
	tapped.start_new()
	check(tapped.stages[-1]["id"] == "pll", "the next solve is CFOP")
	# 2×2 and the unsupported puzzles.
	check(ShowcaseSolve.supports("2x2") and not ShowcaseSolve.supports("5x5"), "2×2/3×3 only, for now (R.6)")
	# Roux and ZZ (R.5) are staged too; God's Number undoes the cube's history, labelled, and is short.
	for method: String in ["roux", "zz", "gods_number"]:
		var other := ShowcaseSolve.new("3x3", method, 21)
		var shown := PuzzleShapes.from_id("3x3")
		shown.apply_all(other.scramble)
		var guard := 0
		while other.phase != "solved" and guard < 300:
			for move in other.tap():
				shown.apply(move)
			guard += 1
		check(other.phase == "solved" and shown.is_solved(), "%s: the showcase solves the scramble (%d taps)" % [method, guard])
	var gods := ShowcaseSolve.new("3x3", "gods_number", 22)
	check(gods.chip_stages().size() == 1 and gods.chip_stages()[0]["name"] == "God's Number", "God's Number: one labelled stage")
	check((gods.stages[0]["moves"] as Array).size() <= 25, "...no longer than the scramble (%d)" % (gods.stages[0]["moves"] as Array).size())
	gods.tap()
	gods.player_turn(gods.model.parse("R"))
	gods.tap()  # a click: the team takes it back and plans from here
	var rest := PuzzleShapes.from_id("3x3")
	rest.orientations = gods.model.orientations.duplicate()
	rest.apply_all((gods.stages[0]["moves"] as Array).slice(gods.move_index))
	check(rest.is_solved(), "God's Number after your turns still solves the cube")
	# Many turns of your own: the history gets long, so the team shows its shortest staged solve, never a long
	# "God's Number".
	var busy := ShowcaseSolve.new("3x3", "gods_number", 23)
	var busy_rng := RandomNumberGenerator.new()
	busy_rng.seed = 24
	for i in 40:
		busy.player_turn(busy.model.random_move(busy_rng))
	busy.advance(float(Content.TAPS["resume_after"]) + 0.1, 8.0)
	var named_gods := busy.stages.any(func(st: Dictionary) -> bool: return st["id"] == "gods_number")
	var gods_moves := 0
	for st: Dictionary in busy.stages:
		if st["id"] == "gods_number":
			gods_moves += (st["moves"] as Array).size()
	check(gods_moves <= 25, "a God's Number stage is never longer than a scramble (%d)" % gods_moves)
	check(named_gods or busy.stages.any(func(st: Dictionary) -> bool: return st["id"] == "lse"), "...else it's a Roux solve")
	# Cubers write two-layer moves on a 3×3 in lower case.
	var m := PuzzleShapes.from_id("3x3")
	check(ShowcaseSolve.notation(m, m.parse("Rw'")) == "r'" and ShowcaseSolve.notation(m, m.parse("R2")) == "R2", "Rw' -> r'")
	var big := PuzzleShapes.from_id("5x5")
	check(ShowcaseSolve.notation(big, big.parse("Rw")) == "Rw", "big cubes keep Rw")


## Smoke check: the main screen plays full showcase solves on the 3×3 with two methods, taps turn it, chips follow.
func test_showcase_on_main_screen() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.cheat_add_solves(1000.0)
	game.unlock_puzzle("3x3")
	game.set_focus("3x3")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	var chips: HBoxContainer = main.get_node("%StageChips")
	var chip_counts := {"beginner": 7, "cfop": 4, "roux": 4, "zz": 3, "gods_number": 1}
	for method: String in chip_counts:
		game.method = method
		main._start_showcase()
		var show: ShowcaseSolve = main._showcase
		check(show != null and show.method == method, "%s: the 3×3 gets a showcase solve" % method)
		check(chips.visible and chips.get_child_count() == int(chip_counts[method]), "%s: one chip per stage (F2L shares one)" % method)
		var moves_before := game.total_moves
		var taps := 0
		while show.phase != "solved" and taps < 400:
			main._on_tap_pressed()
			taps += 1
		view.finish_animations()
		check(show.phase == "solved", "%s: tapping plays the whole solve (%d taps)" % [method, taps])
		check(view.model.is_solved(), "%s: the big cube ends solved" % method)
		check(game.total_moves > moves_before, "%s: the taps still counted as taps" % method)
		main._process(0.016)
		var ticker := (main.get_node("%MoveTicker") as RichTextLabel).text
		check("Solved in" in ticker, "%s: the ticker says it's solved: %s" % [method, ticker])
		for label: Label in chips.get_children():
			check(label.theme_type_variation == &"StageChipDone", "%s: every chip is done" % method)
	# A puzzle without a staged solver yet keeps the old scramble + rewind, and the chips hide.
	game.cheat_add_solves(1e9)
	game.unlock_puzzle("4x4")
	game.set_focus("4x4")
	check(main._showcase == null and not chips.visible, "the 4×4 has no showcase yet (R.6)")
	main.free()
	game.reset_state()


# --- Turns are taps + TPS streak (task S.7) ---------------------------------------------------------------------

func test_tap_streak() -> void:
	var g := new_game()
	var data: Dictionary = Content.TAPS
	check_near(g.streak, 0.0, "no streak at the start")
	check_near(g.get_streak_mult(), 1.0, "...so taps are ×1")
	check_near(g.get_tap_share(), float(data["helper_share"]), "no tap_share upgrades yet")
	check_near(g.get_tap_moves(), g.get_tap_moves_flat() + g.get_tap_moves_from_helpers(), "tap = flat + the helpers' share")
	# "tap_share" upgrades add a share of the focused puzzle's helper moves/s to every tap.
	g.cheat_add_solves(1e9)
	g.buy_buildings("friend", 20)
	g.buy_building("robot")
	check(g.buy_upgrade("metronome"), "buy Metronome Practice")
	var share := float(data["helper_share"]) + float(Content.get_upgrade("metronome")["effect"]["value"])
	check_near(g.get_tap_share(), share, "Metronome Practice adds its share")
	check_near(g.get_tap_moves_from_helpers(), share * g.get_puzzle_moves_per_second("2x2") / g.get_puzzle_moves_mult("2x2"),
			"a tap adds that share of the focused puzzle's helper moves/s")
	check(g.get_tap_moves_from_helpers() > 0.0, "...which is something with a team")
	g.buy_buildings("robot", 9)
	check(g.buy_upgrade("tps_drills"), "buy TPS Drills (10 Robots)")
	check_near(g.get_tap_share(), share + float(Content.get_upgrade("tps_drills")["effect"]["value"]), "the shares add up")
	g.tap()
	check_near(g.streak, float(data["fill_per_tap"]), "a tap fills the meter by fill_per_tap")
	g.update_streak(1.0)
	check_near(g.streak, maxf(0.0, float(data["fill_per_tap"]) - float(data["drain_per_second"])), "...and it drains")
	# Steady turning at 3 TPS fills it; the streak multiplies the helpers' share of a tap up to streak_max_mult.
	for i in 30 * 30:  # 30 s in 1/30 s steps, a tap every 10 steps
		if i % 10 == 0:
			g.tap()
		g.update_streak(1.0 / 30.0)
	check(g.streak > 0.95, "30 s at 3 TPS fills the meter (%s)" % g.streak)
	g.streak = 1.0
	check_near(g.get_streak_mult(), float(data["streak_max_mult"]), "a full meter: ×streak_max_mult")
	check(absf(g.get_recent_tps() - 3.0) <= 0.5, "the shown TPS is about 3 (%s)" % g.get_recent_tps())
	check_near(g.get_tap_moves(), g.get_tap_moves_flat() + g.get_tap_moves_from_helpers() * float(data["streak_max_mult"]),
			"the streak multiplies the helpers' share (not the flat move: the first minutes' pacing stays)")
	g.update_streak(30.0)
	check_near(g.streak, 0.0, "stopping drains it")
	check_near(g.get_recent_tps(), 0.0, "...and the TPS falls to 0")
	# Slow tapping (1 a second) never builds a streak: it only grows above drain / fill taps a second.
	for i in 30:
		g.tap()
		g.update_streak(1.0)
	check(g.streak <= float(data["fill_per_tap"]) + 0.0001, "1 TPS never builds a streak (%s)" % g.streak)
	check(float(data["drain_per_second"]) / float(data["fill_per_tap"]) < 3.0, "3 TPS is above the build threshold")
	g.reset_state()
	check_near(g.streak, 0.0, "reset clears the streak")
	check_near(g.get_recent_tps(), 0.0, "...and the TPS")
	check_near(g.get_tap_share(), float(data["helper_share"]), "...and the upgrades")
	g.free()


func test_showcase_player_turns() -> void:
	var show := ShowcaseSolve.new("3x3", "cfop", 11)
	var resumed := [0]
	var finished := [0]
	show.resumed.connect(func() -> void: resumed[0] += 1)
	show.finished.connect(func() -> void: finished[0] += 1)
	var view_model := PuzzleShapes.from_id("3x3")
	view_model.apply_all(show.scramble)
	for i in 8:
		for move in show.tap():
			view_model.apply(move)
	check(show.phase == "solving", "the showcase is solving")
	var m := show.model
	for text: String in ["R", "U", "R'", "y"]:
		for move in show.player_turn(m.parse(text)):
			view_model.apply(move)
	check(show.phase == "player" and show.player_moves.size() == 4, "key turns take the cube over")
	check(show.advance(float(Content.TAPS["resume_after"]) * 0.5, 8.0).is_empty(), "while you pause briefly it waits")
	check(show.phase == "player", "...still yours")
	show.advance(float(Content.TAPS["resume_after"]), 8.0)
	check(show.phase == "inspection" and resumed[0] == 1, "after resume_after the team takes it back")
	var played := 0
	for i in 3000:
		for move in show.advance(0.05, 8.0):
			view_model.apply(move)
			played += 1
		if show.phase == "solved":
			break
	check(show.phase == "solved" and finished[0] == 1 and not show.by_player, "the team solves it from where you left it")
	check(view_model.is_solved(), "...really (%d moves)" % played)
	# A click hands it back at once.
	var clicked := ShowcaseSolve.new("3x3", "beginner", 12)
	clicked.tap()
	clicked.player_turn(clicked.model.parse("F"))
	var moves := clicked.tap()
	check(clicked.phase == "solving" and moves.size() >= 1, "a click ends your turn and plays on")
	# You can finish the solve yourself.
	var own := ShowcaseSolve.new("2x2", "beginner", 13)
	own.finished.connect(func() -> void: finished[0] += 1)
	for move in own.model.inverse_sequence(own.scramble):
		own.player_turn(move)
	check(own.model.is_solved(), "undoing the scramble solves it")
	own.advance(float(Content.TAPS["resume_after"]) + 0.1, 8.0)
	check(own.phase == "solved" and own.by_player and finished[0] == 2, "solved by you: it counts as solved")
	own.advance(float(Content.SHOWCASE["solved_hold"]) + 0.1, 8.0)
	check(own.phase == "inspection" and not own.by_player and own.player_moves.is_empty(), "then a new scramble")
	# Turning a solved cube as a whole doesn't count as solving it.
	var spun := ShowcaseSolve.new("3x3", "beginner", 14)
	for move in spun.model.inverse_sequence(spun.scramble):
		spun.player_turn(move)
	spun.advance(float(Content.TAPS["resume_after"]) + 0.1, 8.0)
	spun.advance(float(Content.SHOWCASE["solved_hold"]) + 0.1, 8.0)
	var guard := 0
	while spun.phase != "solved" and guard < 500:  # the team plays its whole solve
		spun.tap()
		guard += 1
	spun.player_turn(spun.model.parse("y"))
	spun.advance(float(Content.TAPS["resume_after"]) + 0.1, 8.0)
	check(spun.phase == "solved" and not spun.by_player, "a y on the team's solved cube isn't your solve")
	spun.player_turn(spun.model.parse("R"))
	spun.player_turn(spun.model.parse("R'"))
	spun.advance(float(Content.TAPS["resume_after"]) + 0.1, 8.0)
	check(spun.phase == "solved" and not spun.by_player, "...nor is R R' on it")


func test_main_screen_key_turns() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var settings: Node = root.get_node("Settings")
	settings.persistence_enabled = false
	settings.set_value("solve_keys", "cstimer")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var show: ShowcaseSolve = main._showcase
	check(show != null, "the 2×2 has a showcase")
	var tap_moves := game.get_tap_moves()
	check(main.handle_turn_key(KEY_I), "I is a csTimer key")
	check_near(game.total_moves, tap_moves, "a key turn is a tap")
	check(show.phase == "player" and show.model.notation(show.player_moves[-1]) == "R", "...and turns R on the big cube")
	var moves := game.total_moves
	check(main.handle_turn_key(KEY_Y) and show.model.is_rotation(show.player_moves[-1]), "Y is the x rotation")
	check_near(game.total_moves, moves, "a rotation isn't a tap")
	check(not main.handle_turn_key(KEY_F12), "other keys aren't used")
	check(game.streak > 0.0, "key turns build the streak")
	main._unhandled_input(key_event(KEY_J, true, false))
	check(show.model.notation(show.player_moves[-1]) == "U" and game.total_moves > moves, "J from the keyboard: U, a tap")
	main._process(0.016)
	check("Your turns" in (main.get_node("%MoveTicker") as RichTextLabel).text, "the ticker shows your turns")
	main._refresh_golden()
	var streak_chip: StatChip = main.get_node("%StreakChip")
	check(not streak_chip.visible, "no streak chip while taps have no team share (it would multiply nothing)")
	game.upgrades["metronome"] = true
	game.invalidate_upgrade_cache()
	main._refresh_golden()
	check(streak_chip.visible and streak_chip.get_text().begins_with("×") and "TPS" in streak_chip.get_text(),
			"the streak shows in the top bar: %s" % streak_chip.get_text())
	# Space while you're turning: csTimer's hand reset, and the cube stays yours.
	main._key_session.right_hand = 2
	main._unhandled_input(key_event(KEY_SPACE, true, false))
	check(show.phase == "player" and main._key_session.right_hand == 1, "Space resets the hands and doesn't hand the cube back")
	main._unhandled_input(key_event(KEY_SPACE, false, false))
	# The simple layout follows the setting.
	settings.set_value("solve_keys", "simple")
	check(main.handle_turn_key(KEY_F, true) and show.model.notation(show.player_moves[-1]) == "F'", "simple: Shift+F = F'")
	# Overlays keep the keys.
	main.get_node("%SettingsPanel").visible = true
	moves = game.total_moves
	main._unhandled_input(key_event(KEY_R, true, false))
	check_near(game.total_moves, moves, "no key turns while the settings are open")
	main.get_node("%SettingsPanel").visible = false
	# Without a showcase (4×4 until R.6), turns are still taps.
	game.cheat_add_solves(1e9)
	game.unlock_puzzle("3x3")
	game.unlock_puzzle("4x4")
	game.set_focus("4x4")
	moves = game.total_moves
	check(main._showcase == null and main.handle_turn_key(KEY_R) and game.total_moves > moves, "4×4: R is still a tap")
	# A championship or reset changes focus without focus_changed: the keys follow the new puzzle.
	game.reset_state()
	main._rebuild_after_reset()
	check(main._key_session.model.size == 2, "after a reset the keys turn the 2×2 again")
	settings.set_value("solve_keys", "cstimer")
	main.free()
	game.reset_state()


# --- Solve Station controls (owner, 2026-11-03: drag to turn, key hints, simple keys) --------------------------------

func test_simple_key_layout() -> void:
	var session := SolveSession.new()
	session.layout = "simple"
	session.inspection = false
	session.start("3x3", 0.0)
	var m := session.model
	check(m.notation(session.press_key(KEY_R, 1.0)) == "R", "R is R")
	check(m.notation(session.press_key(KEY_R, 1.1, true)) == "R'", "Shift+R is R'")
	check(m.notation(session.press_key(KEY_U, 1.2, true)) == "U'", "Shift+U is U'")
	check(m.notation(session.press_key(KEY_X, 1.3)) == "x" and m.notation(session.press_key(KEY_Y, 1.4, true)) == "y'", "X/Y rotate")
	check(m.notation(session.press_key(KEY_M, 1.5)) == "M" and m.notation(session.press_key(KEY_S, 1.6, true)) == "S'", "M E S are slices")
	check(session.press_key(KEY_2, 1.7).is_empty() and session.next_width == 2, "a number sets the next turn's width")
	check(m.notation(session.press_key(KEY_R, 1.8)) == "Rw", "2 then R is a wide R (Rw)")
	check(session.next_width == 1, "...and the width goes back to 1")
	check(session.press_key(KEY_I, 1.9).is_empty(), "csTimer's I does nothing in the simple layout")
	var big := SolveSession.new()
	big.layout = "simple"
	big.start("5x5", 0.0)
	big.press_key(KEY_3, 0.5)
	check(big.model.notation(big.press_key(KEY_R, 1.0, true)) == "3Rw'", "5×5: 3 then Shift+R is 3Rw'")
	big.press_key(KEY_6, 1.1)
	check(big.next_width == 4, "the width stops at size - 1 (a full width would be a rotation)")
	var two := SolveSession.new()
	two.layout = "simple"
	two.start("2x2", 0.0)
	check(two.press_key(KEY_M, 1.0).is_empty(), "no M on a 2×2")
	# csTimer stays the default.
	check(SolveSession.new().layout == "cstimer", "csTimer's layout is the default")


## A drag across the cube turns the layer it runs along, like swiping a real cube (S.8, done early for the owner).
func test_drag_to_turn() -> void:
	var view := new_view()
	view.sway_enabled = false
	view.drag_turns = true
	for size: int in [3, 4]:
		view.set_puzzle("%dx%d" % [size, size])
		view.finish_animations()
		var h := size / 2.0
		var m := view.model
		# [press point on the surface, direction to drag (model space), expected move]
		var cases: Array = [
			[Vector3(h - 0.5, 0, h), Vector3.UP, "R"], [Vector3(h - 0.5, 0, h), Vector3.DOWN, "R'"],
			[Vector3(-h + 0.5, 0, h), Vector3.UP, "L'"], [Vector3(0.2, -h + 0.5, h), Vector3.LEFT, "D'"],
			[Vector3(0, h, h - 0.5), Vector3.RIGHT, "F"], [Vector3(h, h - 0.5, 0), Vector3.BACK, "U"],
		]
		if size == 3:
			cases.append([Vector3(0, 0.2, h), Vector3.UP, "M'"])
		else:
			cases.append([Vector3(0.5, 0.2, h), Vector3.UP, "2R"])
			cases.append([Vector3(-0.5, 0.2, h), Vector3.UP, "2L'"])
		for c: Array in cases:
			var at := view.screen_position(c[0])
			var hit := view.pick(at)
			check(not hit.is_empty() and (hit["point"] as Vector3).distance_to(c[0]) < 0.05,
					"%d×%d: the press at %s lands on the cube there" % [size, size, c[0]])
			var drag := (view.screen_position(c[0] + (c[1] as Vector3) * 0.4) - at) * 3.0
			var move := view.move_for_drag(hit, drag)
			check(not move.is_empty() and m.notation(move) == c[2],
					"%d×%d: dragging %s from %s is %s (got %s)" % [size, size, c[1], c[0], c[2], m.notation(move) if not move.is_empty() else "nothing"])
	check(view.pick(Vector2(2, 2)).is_empty(), "the corner of the view is background")
	# Through real mouse events: press on a sticker, drag up, one turn and no tap.
	view.set_puzzle("3x3")
	view.finish_animations()
	var turned: Array = []
	var taps: Array = []
	view.drag_turned.connect(func(move: Dictionary) -> void: turned.append(move))
	view.tapped.connect(func(at: Vector2) -> void: taps.append(at))
	var start := view.screen_position(Vector3(1, 0, 1.5))
	var up := (view.screen_position(Vector3(1, 1, 1.5)) - start).normalized()
	view._gui_input(mouse_button(true, start))
	for step in 4:
		var motion := InputEventMouseMotion.new()
		motion.position = start + up * 8.0 * (step + 1)
		motion.relative = up * 8.0
		view._gui_input(motion)
	view._gui_input(mouse_button(false, start + up * 32.0))
	check(turned.size() == 1 and view.model.notation(turned[0]) == "R", "a drag up the right column is one R")
	check(taps.is_empty() and view.drag_offset() == Vector2.ZERO, "...not a tap, and the view didn't turn")
	view.queue_free()


func test_solve_station_controls() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var settings: Node = root.get_node("Settings")
	settings.persistence_enabled = false
	settings.set_value("inspection", false)
	settings.set_value("solve_keys", "cstimer")
	settings.set_value("key_hints", true)
	game.cheat_add_solves(1e9)
	game.unlock_puzzle("3x3")
	game.unlock_puzzle("4x4")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var station: Node = main.get_node("%SolveStation")
	station.open("3x3")
	# Key hints: one per face, from the key map.
	check(station.face_hint_text("R") == "R  I / K" and station.face_hint_text("U") == "U  J / F", "csTimer hints: R I / K, U J / F")
	check(station.get_node("%KeyHints").get_child_count() == 6, "a hint for each of the six faces")
	check(station.extra_keys_text().contains("y ;/A") and station.extra_keys_text().contains("M 5/6"), "rotations and slices under the cube")
	await process_frame  # let the station lay out first
	await process_frame
	station._place_hints()
	var view: PuzzleView3D = station.get_node("%View")
	var rect := Rect2(Vector2.ZERO, station.size)
	for label: Label in station.get_node("%KeyHints").get_children():
		check(rect.has_point(label.position), "hint %s is on screen" % label.text)
	(station.get_node("%HintsToggle") as Button).toggled.emit(false)
	check(station.get_node("%KeyHints").get_child_count() == 0 and not settings.get_value("key_hints"), "Key hints off hides them")
	(station.get_node("%HintsToggle") as Button).toggled.emit(true)
	# The simple layout, switched in the station (and saved as a setting).
	(station.get_node("%SimpleKeysToggle") as Button).toggled.emit(true)
	check(settings.get_value("solve_keys") == "simple" and station.session.layout == "simple", "Simple keys switches the layout")
	check(station.face_hint_text("R") == "R / ⇧R", "simple hints: R / ⇧R")
	check(station.keys_help_text().contains("R R / Shift+R"), "the full key list follows the layout")
	station.handle_key(KEY_R, true)
	view.finish_animations()
	check(station.session.moves == 1 and view.model.orientations == station.session.model.orientations, "Shift+R turns R'")
	station.select_puzzle("4x4")
	station.handle_key(KEY_2)
	check((station.get_node("%HandLabel") as Label).text.contains("Next turn: 2 layers"), "the width shows before the turn")
	station.handle_key(KEY_R)
	view.finish_animations()
	check(view.model.orientations == station.session.model.orientations, "2 then R turns two layers")
	(station.get_node("%SimpleKeysToggle") as Button).toggled.emit(false)
	check(station.session.layout == "cstimer", "back to csTimer's layout")
	# A drag on the cube turns it like a key does (and starts the timer).
	station.select_puzzle("3x3")
	var start := view.screen_position(Vector3(1, 0, 1.5))
	var hit := view.pick(start)
	view.drag_turned.emit(view.move_for_drag(hit, (view.screen_position(Vector3(1, 1, 1.5)) - start) * 2.0))
	view.finish_animations()
	check(station.session.moves == 1 and station.session.state == "solving", "a drag turn counts as a turn and starts the timer")
	check(view.model.orientations == station.session.model.orientations, "...and the view shows it")
	station.close()
	main.free()
	settings.set_value("inspection", true)
	game.reset_state()


# --- Cube times and goals (task R.3) ---------------------------------------------------

func test_cube_time_format() -> void:
	check(Num.cube_time(9.876) == "9.87 s", "9.876 s -> 9.87 s (truncated, like WCA)")
	check(Num.cube_time(83.45) == "1:23.45", "a minute and more -> 1:23.45")
	check(Num.cube_time(0.00408) == "4.08 ms" and Num.cube_time(3.8e-5) == "38.0 µs", "milliseconds and microseconds")
	check(Num.cube_time(1.2e-8) == "12.0 ns" and Num.cube_time(1e-12) == "<1 ns", "nanoseconds, and below")
	check(Num.cube_time(INF) == "—", "no helpers: a dash")


func test_helper_solve_times_and_tiers() -> void:
	var g := new_game()
	check(is_inf(g.get_team_solve_time("2x2")) and g.get_time_tier("2x2").is_empty(), "no helpers: no team time, no tier")
	var reached: Array = []
	g.time_tier_reached.connect(func(id: String, tier: String, seconds: float) -> void: reached.append([id, tier, seconds]))
	g.cheat_add_solves(5.0)
	g.buy_building("friend")
	var expected := g.get_moves_per_solve("2x2") / (g.get_building_mps("friend") * g.get_puzzle_moves_mult("2x2"))
	check_near(g.get_helper_solve_time("friend", "2x2"), expected, "a Friend's 2×2 time = moves per solve ÷ its moves/s")
	check_near(g.get_team_solve_time("2x2"), expected, "the team's best is the only helper's")
	check(reached.size() == 1 and reached[0][0] == "2x2" and reached[0][1] == g.get_time_tier("2x2")["name"],
			"the first helper crosses a tier and it pops once: %s" % [reached])
	g.cheat_add_solves(100.0)
	g.buy_building("friend")
	check(reached.size() == 1, "another Friend is no faster: no new tier")
	g.cheat_add_solves(1e4)
	g.buy_building("club")
	check_near(g.get_team_solve_time("2x2"), g.get_helper_solve_time("club", "2x2"), "the faster helper sets the team's best")
	check(reached.size() == 2 and reached[1][1] == g.get_time_tier("2x2")["name"], "a big jump pops only the best tier reached")
	var next := g.get_next_time_tier("2x2")
	check(not next.is_empty() and float(next["seconds"]) < float(g.get_time_tier("2x2")["seconds"]), "the next tier is faster")
	# Loading a save or unlocking a puzzle never pops tiers reached earlier.
	var data := g.get_save_data()
	g.apply_save_data(data, float(data["saved_at"]))
	g.cheat_add_solves(1e6)
	g.unlock_puzzle("3x3")
	check(reached.size() == 2, "no pops from loading or from a new puzzle's first look (%s)" % [reached])
	check(not g.get_time_tier("3x3").is_empty(), "the 3×3 has its own tier from the start")
	for id: String in Content.TIME_TIERS:
		var tiers: Array = Content.TIME_TIERS[id]
		for i in range(1, tiers.size()):
			check(float(tiers[i][0]) < float(tiers[i - 1][0]), "%s tiers get faster: %s" % [id, tiers[i][1]])
	for def: Dictionary in Content.PUZZLES:
		check(Content.TIME_TIERS.has(def["id"]), "%s has time tiers" % def["id"])
	g.free()


func test_goals() -> void:
	var g := new_game()
	var goals := g.get_goals(3)
	check(not goals.is_empty() and goals[0]["id"] == "friend", "a new game's first goal is the first Friend")
	check(float(goals[0]["seconds"]) == 0.0 and float(goals[0]["progress"]) == 1.0, "the free Friend is ready now (5.0)")
	g.buy_building("friend")
	g.update_flow(0.0)
	var later := g.get_goals(3)
	check(float(later[0]["missing"]) > 0.0 and float(later[0]["progress"]) < 1.0, "after it, goals have Solves to go")
	check(goals.size() <= 3, "at most 3 goals")
	var kinds := {}
	for goal in g.get_goals(10):
		check(not kinds.has(goal["kind"]), "one goal per kind (%s)" % goal["kind"])
		kinds[goal["kind"]] = true
	check(kinds.has("mastery") and kinds.has("puzzle") and kinds.has("helper"), "mastery, puzzles and helpers are all goals")
	g.cheat_add_solves(5.0)
	g.buy_building("friend")
	g.cheat_add_solves(3.0)
	goals = g.get_goals(10)
	for i in range(1, goals.size()):
		check(float(goals[i]["seconds"]) >= float(goals[i - 1]["seconds"]), "goals are soonest first")
	for goal in goals:
		if goal["unit"] == "Solves" and float(goal["missing"]) > 0.0:
			check_near(float(goal["seconds"]), float(goal["missing"]) / g.get_solves_per_second(), "%s: ETA = missing ÷ Solves/s" % goal["name"])
			check(float(goal["progress"]) > 0.0 and float(goal["progress"]) < 1.0, "%s: progress is part-way" % goal["name"])
		if goal["kind"] == "mastery":
			var xp_rate := g.get_puzzle_solve_rate("2x2") * g.get_mastery_xp_per_solve("2x2")
			check_near(float(goal["seconds"]), float(goal["missing"]) / xp_rate, "mastery: ETA = XP missing ÷ XP/s")
			check(String(goal["name"]).contains("Mastery 5"), "the mastery goal is the next milestone: %s" % goal["name"])
	check_near(g.get_puzzle_solve_rate("2x2"), g.get_puzzle_moves_per_second("2x2") / g.get_moves_per_solve("2x2"), "solve rate = moves/s ÷ moves per solve")
	g.cheat_add_solves(1e3)
	check(g.get_goals(1)[0]["missing"] == 0.0 and float(g.get_goals(1)[0]["seconds"]) == 0.0, "something affordable comes first: ready now")
	g.free()


func test_goal_bar_on_main_screen() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	var presets: Dictionary = load("res://tools/screenshot_presets.gd").PRESETS
	game.apply_save_data(presets["late"].duplicate(true), Time.get_unix_time_from_system())
	game.set_process(false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._refresh()
	var focus := game.get_focused_puzzle_id()
	check(game.get_puzzle_solve_rate(focus) > Content.GOAL_BAR_SOLVES_PER_SECOND, "the late game solves far faster than 10/s")
	check((main.get_node("%ProgressLabel") as Label).text.begins_with("Next goal:"), "so the moves bar becomes the next-goal bar")
	var goals: Array[Dictionary] = game.get_goals(3)
	check((main.get_node("%ProgressLabel") as Label).text.contains(String(goals[0]["name"])), "the card's main slot is the first goal")
	check((main.get_node("%Goal1Label") as Label).text.begins_with(String(goals[1]["name"]))
			and (main.get_node("%Goal2Bar") as ProgressBar).is_visible_in_tree(), "...then the next two, with bars")
	check((main.get_node("%TeamBest") as Label).visible and (main.get_node("%TeamBest") as Label).text.begins_with("Team best "),
			"the team's best time is a badge on the stage")
	main.free()
	game.reset_state()
	game.set_process(true)
	var fresh: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(fresh)
	fresh._refresh()
	check((fresh.get_node("%ProgressLabel") as Label).text.contains("moves"), "a new game keeps the moves-to-next-solve bar")
	fresh.free()


# --- News feed (task R.4) ---------------------------------------------------------------

func test_news_feed_rules() -> void:
	var feed := NewsFeed.new()
	var interval := float(Content.NEWS["interval"])
	feed.push("a", "first")
	feed.push("b", "second")
	feed.push("c", "third")
	check(feed.advance(0.0) == "first", "the first line shows at once")
	check(feed.advance(interval * 0.5) == "", "the next waits for the interval")
	check(feed.advance(interval * 0.6) == "second", "...then it shows")
	check(feed.history == ["second", "first"] and feed.pending() == 1, "history is newest first")
	# Same kind while waiting: merged, only the newest kept.
	feed.push("mastery:3x3", "3×3 Mastery 11")
	feed.push("mastery:3x3", "3×3 Mastery 12")
	check(feed.pending() == 2, "two mastery level-ups waiting together make one line")
	feed.advance(interval)
	check(feed.advance(interval) == "3×3 Mastery 12", "...the newest")
	# The queue is capped; the history keeps the last 20.
	for i in 30:
		feed.push("k%d" % i, "line %d" % i)
	check(feed.pending() == int(Content.NEWS["queue"]), "the waiting queue is capped (oldest dropped)")
	for i in 40:
		feed.advance(interval)
		feed.push("x%d" % i, "more %d" % i)
	check(feed.history.size() == int(Content.NEWS["history"]), "the list keeps the last 20 lines")
	var levels := NewsFeed.new()
	for level in [2, 9, 11, 12, 15, 25, 33]:
		levels.on_mastery_level_up("2x2", level)
		levels.advance(interval)
	check(levels.history == ["2×2 Mastery 25: +25 % Solves per solve", "2×2 Mastery 15", "2×2 Mastery 9", "2×2 Mastery 2"],
			"mastery lines: every level to 10, then every 5th and milestones (%s)" % [levels.history])
	# Lines for each kind of event.
	var lines := NewsFeed.new()
	var out: Array[String] = []
	var events: Array[Callable] = [
		lines.on_helper_best_time.bind("club", "3x3", 9.876, false, 8),
		lines.on_helper_best_time.bind("robot", "3x3", 0.21, true, 1),
		lines.on_mastery_level_up.bind("3x3", 25),
		lines.on_purchased.bind("method", "cfop"),
		lines.on_purchased.bind("puzzle", "4x4"),
		lines.on_purchased.bind("building", "friend"),
		lines.on_purchased.bind("upgrade", "lube"),
		lines.on_time_tier.bind("3x3", "Sub-10", 9.87),
		lines.on_solves_milestone.bind(1e6),
		lines.on_hand_pb.bind("3x3", true, [5, 12], 8.77),
	]
	for event in events:
		event.call()
		var text := lines.advance(interval)
		if text != "":
			out.append(text)
	check(out.size() == 8, "8 events make 8 lines; buying a helper or an upgrade makes none on its own (%d)" % out.size())
	check(out[0].begins_with("Club member ") and out[0].ends_with(": 9.87 s 3×3 single!"), "a helper's best: %s" % out[0])
	check(out[1].begins_with("Robot ") and out[1].contains("joins the team: 0.21 s a 3×3"), "a new helper kind: %s" % out[1])
	check(out[2] == "3×3 Mastery 25: +25 % Solves per solve", "a milestone level says what it gives: %s" % out[2])
	check(out[3].begins_with("Your team learned CFOP."), "a method: %s" % out[3])
	check(out[4].begins_with("New puzzle: 4×4"), "a puzzle: %s" % out[4])
	check(out[5] == "3×3 team: Sub-10! 9.87 s" and out[6] == "1.00M lifetime Solves!", "a tier and a milestone")
	check(out[7] == "Your new 3×3 PB: single 8.77, ao5, ao12", "your own PBs: %s" % out[7])
	check(NewsFeed.member_name("club", 8) == NewsFeed.member_name("club", 8), "a member keeps the same name")
	check(NewsFeed.member_name("robot", 3).begins_with("Robot ") and not NewsFeed.member_name("robot", 3).contains("Ana"), "robots get codes, not people's names")


func test_news_events_from_game() -> void:
	var g := new_game()
	var helper_events: Array = []
	var milestones: Array = []
	var pbs: Array = []
	g.helper_best_time.connect(func(id: String, puzzle: String, seconds: float, first: bool) -> void: helper_events.append([id, puzzle, seconds, first]))
	g.solves_milestone.connect(func(amount: float) -> void: milestones.append(amount))
	g.hand_solve_pb.connect(func(puzzle: String, single: bool, averages: Array, seconds: float) -> void: pbs.append([puzzle, single, averages]))
	g.cheat_add_solves(5.0)
	g.buy_building("friend")
	check(helper_events.size() == 1 and helper_events[0][0] == "friend" and helper_events[0][3], "the first Friend joins (first = true)")
	g.cheat_add_solves(100.0)
	g.buy_building("friend")
	check(helper_events.size() == 1, "a second Friend is no faster: no line")
	g.cheat_add_solves(1e5)
	for def: Dictionary in Content.UPGRADES:
		var effect: Dictionary = def["effect"]
		if effect["type"] == "building_mult" and effect.get("target", "") == "friend":
			g.buy_upgrade(def["id"])
	if helper_events.size() > 1:
		check(helper_events[-1][0] == "friend" and not helper_events[-1][3], "a Friend upgrade makes Friends faster: a new best")
	# Milestones: once per power of ten, the highest one passed (a fresh game: cheats skip the milestone check).
	g.free()
	g = new_game()
	g.solves_milestone.connect(func(amount: float) -> void: milestones.append(amount))
	g.helper_best_time.connect(func(id: String, puzzle: String, seconds: float, first: bool) -> void: helper_events.append([id, puzzle, seconds, first]))
	g.hand_solve_pb.connect(func(puzzle: String, single: bool, averages: Array, seconds: float) -> void: pbs.append([puzzle, single, averages]))
	g.add_moves_to("2x2", g.get_moves_per_solve("2x2") * 150.0)
	check(milestones == [100.0], "passing 100 lifetime Solves is a milestone (%s)" % [milestones])
	g.add_moves_to("2x2", g.get_moves_per_solve("2x2") * 20000.0)
	check(milestones == [100.0, 10000.0], "jumping past 1K and 10K at once gives one line, for 10K (%s)" % [milestones])
	# Nothing fires again for what a load restores.
	var data := g.get_save_data()
	g.apply_save_data(data, float(data["saved_at"]))
	var before := helper_events.size()
	g.add_moves_to("2x2", g.get_moves_per_solve("2x2"))
	check(milestones.size() == 2 and helper_events.size() == before, "after a load: no repeats")
	# Hand-solve PBs.
	g.record_hand_solve("3x3", 12.0, "", 50)
	g.record_hand_solve("3x3", 14.0, "", 50)
	g.record_hand_solve("3x3", 11.0, "", 50)
	check(pbs.size() == 2 and pbs[0][1] and pbs[1][1], "a first solve and a faster one are PBs; a slower one isn't (%s)" % [pbs])
	g.free()


func test_career_data() -> void:
	var ids := {}
	for def: Dictionary in Content.CAREER:
		var id: String = def["id"]
		check(not ids.has(id), "career ids are unique (%s)" % id)
		ids[id] = true
		check(String(def["text"]).length() > 10, "%s has a story line" % id)
		check(Content.get_career_moment(id) == def, "get_career_moment finds %s" % id)
		var trigger: Dictionary = def["trigger"]
		var target := String(trigger.get("id", ""))
		match String(trigger["type"]):
			"helper":
				check(not Content.get_building(target).is_empty(), "%s: helper %s exists" % [id, target])
			"upgrade":
				check(not Content.get_upgrade(target).is_empty(), "%s: upgrade %s exists" % [id, target])
			"puzzle":
				check(not Content.get_puzzle(target).is_empty(), "%s: puzzle %s exists" % [id, target])
			"method":
				check(Content.get_method_index(target) > 0, "%s: method %s exists" % [id, target])
			"lifetime_solves", "championships":
				check(float(trigger["value"]) > 0.0, "%s has a threshold" % id)
			_:
				check(false, "%s has a known trigger type (%s)" % [id, trigger["type"]])


## Each moment fires once at its trigger, in data order, and never again (7.0a).
func test_career_moments_fire_once() -> void:
	var g := new_game()
	var heard: Array[String] = []
	g.career_moment.connect(func(id: String) -> void: heard.append(id))
	check(g.check_career().is_empty(), "a new game has no story yet")
	for def: Dictionary in Content.CAREER:
		var trigger: Dictionary = def["trigger"]
		var target := String(trigger.get("id", ""))
		match String(trigger["type"]):
			"lifetime_solves":
				g.cheat_add_solves(float(trigger["value"]) - g.total_solves)
			"helper":
				g.buildings[target] = 1
			"upgrade":
				g.upgrades[target] = true
			"puzzle":
				g.puzzles_reached[target] = true
			"method":
				g.method = target
			"championships":
				g.championships = int(trigger["value"])
		var fired := g.check_career()
		check(Array(fired) == [def["id"]], "%s fires at its trigger (fired: %s)" % [def["id"], fired])
		check(g.check_career().is_empty(), "...once")
	check(heard.size() == Content.CAREER.size(), "every moment was signalled once (%d)" % heard.size())
	# After a championship the same unlocks happen again: no repeats.
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	check(g.compete() > 0, "test setup: a championship")
	g.cheat_add_solves(1000.0)
	check(g.buy_building("friend") and g.buy_building("club") and g.unlock_puzzle("3x3"), "test setup: the same unlocks again")
	check(heard.size() == Content.CAREER.size(), "nothing fires again in a new run")
	var data := g.get_save_data()
	var loaded := new_game()
	loaded.career_moment.connect(func(id: String) -> void: heard.append(id))
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.career_seen.size() == Content.CAREER.size() and loaded.check_career().is_empty()
			and heard.size() == Content.CAREER.size(), "...or after a reload")
	loaded.free()
	g.free()
	# Buying fires at once (no wait for the once-a-second check); lifetime Solves are checked once a second.
	var live := new_game()
	var live_heard: Array[String] = []
	live.career_moment.connect(func(id: String) -> void: live_heard.append(id))
	live.buy_building("friend")
	check(Array(live_heard) == ["first_friend"], "the first Friend's moment fires when it's bought (%s)" % [live_heard])
	live.cheat_add_solves(5.0)
	live._process(0.5)
	check(not live_heard.has("first_solve"), "lifetime Solves wait for the once-a-second check")
	live._process(0.6)
	check(live_heard.has("first_solve"), "...then fire")
	live.free()
	var feed := NewsFeed.new()
	feed.on_career_moment("first_4x4")
	check(feed.advance(0.0) == Content.get_career_moment("first_4x4")["text"], "the news feed shows a moment's line")
	feed.on_career_moment("banana")
	check(feed.pending() == 0, "...and nothing for an unknown id")


func test_career_save() -> void:
	var g := new_game()
	g.buildings["club"] = 3
	g.check_career()
	var data := g.get_save_data()
	check(GameState.SAVE_VERSION >= 13 and int(data["version"]) == GameState.SAVE_VERSION, "saves as v13 or later")
	data["career"] = ["banana", 5, "first_3x3", "cubing_club"]
	var damaged := new_game()
	damaged.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(damaged.career_seen.keys() == ["first_3x3", "cubing_club"], "unknown ids are dropped (%s)" % [damaged.career_seen.keys()])
	damaged.free()
	# v12 -> v13: what an old save already lived through is marked seen without a signal, the rest still comes.
	var v12 := g.get_save_data()
	v12["version"] = 12
	v12.erase("career")
	v12["buildings"]["friend"] = 2
	v12["championship"]["reached"] = ["2x2", "3x3"]
	var old := new_game()
	var heard: Array[String] = []
	old.career_moment.connect(func(id: String) -> void: heard.append(id))
	old.apply_save_data(JSON.parse_string(JSON.stringify(v12)), float(v12["saved_at"]))
	check(heard.is_empty() and old.career_seen.has("first_friend") and old.career_seen.has("cubing_club")
			and old.career_seen.has("first_3x3"), "v12 → v13: moments already lived are seen, silently (%s)" % [old.career_seen.keys()])
	check(not old.career_seen.has("first_robot") and old.check_career().is_empty(), "...and the others wait for their trigger")
	# A trigger reached while away (CFOP research finishing) isn't signalled during the load (no UI listens yet),
	# so it isn't lost: it fires at the first check afterwards.
	var away := new_game()
	away.cheat_add_solves(1e4)
	away.research = {"id": "method_cfop", "left": 60.0}
	var away_data := away.get_save_data()
	away_data["saved_at"] = 1000.0
	away.free()
	var back := new_game()
	var back_heard: Array[String] = []
	back.career_moment.connect(func(id: String) -> void: back_heard.append(id))
	back.apply_save_data(JSON.parse_string(JSON.stringify(away_data)), 1000.0 + 3600.0)
	check(back.method == "cfop" and back_heard.is_empty() and not back.career_seen.has("learn_cfop"),
			"CFOP learned while away: nothing signalled during the load (%s)" % [back_heard])
	back._process(1.0)
	check(back_heard.has("learn_cfop"), "...it fires at the first check after loading")
	back.free()
	old.buildings["robot"] = 1
	check(Array(old.check_career()) == ["first_robot"], "...then fire")
	check(int(old.get_save_data()["version"]) == GameState.SAVE_VERSION, "...and it saves as the current version")
	old.free()
	g.reset_state()
	check(g.career_seen.is_empty(), "a wiped save starts the story over")
	g.free()


## 7.1a: the achievement data is complete and every tier can be reached with today's content.
func test_achievement_data() -> void:
	var all := Content.get_achievements()
	check(all.size() >= 100, "about 100 achievements (%d)" % all.size())
	var ids := {}
	var full_cases := 0
	for alg: Dictionary in Content.ALGORITHMS:
		if alg.get("full", false):
			full_cases += 1
	var previous := {}  # row -> the previous tier's value
	for def: Dictionary in all:
		var id: String = def["id"]
		check(not ids.has(id), "achievement ids are unique (%s)" % id)
		ids[id] = true
		check(Content.get_achievement(id) == def, "get_achievement finds %s" % id)
		check(Content.ACHIEVEMENT_TYPES.has(def["type"]), "%s has a known type (%s)" % [id, def["type"]])
		check(ResourceLoader.exists(Content.ICON_DIR + String(def["icon"]) + ".svg"), "%s has an icon file" % id)
		var text := Content.describe_achievement(def)
		check(String(def["name"]).length() > 2 and text.ends_with(".") and not text.contains("%"),
				"%s has a name and a finished text (%s)" % [id, text])
		var value := float(def["value"])
		var target := String(def["target"])
		if previous.has(def["row"]):
			check(value > float(previous[def["row"]]), "%s: tiers go up" % id)
		previous[def["row"]] = value
		match String(def["type"]):
			"helper":
				check(not Content.get_building(target).is_empty(), "%s: helper %s exists" % [id, target])
			"puzzle":
				check(not Content.get_puzzle(target).is_empty() and float(Content.get_puzzle(target)["unlock_cost"]) > 0.0,
						"%s: puzzle %s exists and must be unlocked" % [id, target])
			"method":
				check(Content.get_method_index(target) > 0, "%s: method %s exists" % [id, target])
			"drill_set":
				check(not Content.get_drill_set(target).is_empty(), "%s: drill set %s exists" % [id, target])
			"mastery":
				check(value <= float(Content.MASTERY["max_level"]), "%s: the level exists" % id)
			"perks":
				check(value <= _buyable_perks().size(), "%s: that many perks can be bought" % id)
			"hand_tier":
				check(value < (Content.SOLVE_REWARDS["tiers"] as Array).size() and Content.describe_achievement(def).contains(
						Content.SOLVE_REWARDS["tiers"][int(value)]), "%s: the tier exists and is named" % id)
			"drill_cases":
				check(value <= full_cases, "%s: there are that many drill cases (%d)" % [id, full_cases])
			"research":
				check(value <= (Content.LAB["projects"] as Array).size(), "%s: there are that many Lab projects" % id)
			"tracks":
				check(value <= Content.TRACKS.size(), "%s: there are that many tracks" % id)
			"upgrades":
				check(value <= Content.get_upgrades().size(), "%s: there are that many upgrades" % id)
	var say := func(id: String) -> String: return Content.describe_achievement(Content.get_achievement(id))
	check(say.call("team_friend_2") == "Own 10 Cubing Friends at once." and say.call("team_friend_1") == "Own 1 Cubing Friend at once."
			and say.call("team_factory_2") == "Own 10 Cube Factories at once.", "a helper row reads naturally (%s)" % say.call("team_factory_2"))
	check(say.call("solves_1") == "Earn 1 Solve in total." and say.call("champion_1") == "Win 1 World Championship."
			and say.call("champion_2") == "Win 3 World Championships.", "one is singular (%s)" % say.call("solves_1"))
	check(say.call("solves_4") == "Earn 1K Solves in total." and Content.get_achievement("solves_4")["name"] == "Solver IV",
			"numbers are round in the text (%s)" % say.call("solves_4"))
	check(say.call("hand_tier_3") == "Reach Gold with a Solve Station single on any puzzle.", "labels replace numbers")
	check(Content._short_number(1e5) == "100K" and Content._short_number(1.5e3) == "1.5K" and Content._short_number(7.0) == "7",
			"short numbers (%s, %s)" % [Content._short_number(1e5), Content._short_number(1.5e3)])
	var notation := Num.notation
	Num.notation = "scientific"
	check(say.call("solves_16") == "Earn 1e15 Solves in total.", "the text follows the notation setting (%s)" % say.call("solves_16"))
	Num.notation = notation


## The perks a player can buy (`buyable` isn't false).
func _buyable_perks() -> Array:
	return Content.PERKS.filter(func(perk: Dictionary) -> bool: return perk.get("buyable", true))


## A panel is closed for the game: hidden, or fading out (V.6 animates closing).
func _closed(panel: Control) -> bool:
	return not panel.visible or UiFx.is_closing(panel)


## Puts a game exactly at an achievement's condition (for test_achievement_conditions).
func _reach_achievement(g: GameState, def: Dictionary) -> void:
	var value := float(def["value"])
	var target := String(def["target"])
	match String(def["type"]):
		"lifetime_solves":
			g.total_solves = value
		"lifetime_moves":
			g.total_moves = value
		"solves_per_second":
			g.buildings["friend"] = 1  # a slow team, then just enough trophies (+2 % each) to reach the value
			var base := g.get_solves_per_second()
			g.trophies = ceili((value / base - 1.0) / g.get_bonus_per_trophy() * 1.001)
		"helper":
			g.buildings[target] = int(value)
		"upgrades":
			for up: Dictionary in Content.get_upgrades().slice(0, int(value)):
				g.upgrades[up["id"]] = true
		"puzzle":
			g.puzzles_reached[target] = true
		"method":
			g.method = target
		"mastery":
			g._add_mastery_xp("2x2", g._mastery_xp_at(int(value)))
		"championships":
			g.championships = int(value)
		"perks":
			for perk: Dictionary in _buyable_perks().slice(0, int(value)):
				g.perks[perk["id"]] = true
		"hand_solves":
			g.solve_records["2x2"] = {"history": [], "count": int(value)}
		"hand_tier":
			g.record_hand_solve("3x3", float(Content.SOLVE_REWARDS["targets"]["3x3"][int(value)]) * 0.99, "", 40)
		"drill_cases":
			var learned := 0
			for alg: Dictionary in Content.ALGORITHMS:
				if alg.get("full", false) and learned < int(value):
					g.drills[alg["id"]] = {"best": 5.0, "clean": int(Content.DRILLS["clean_needed"]), "count": 5}
					learned += 1
		"drill_set":
			for alg: Dictionary in Content.get_drill_cases(target):
				g.drills[alg["id"]] = {"best": 5.0, "clean": int(Content.DRILLS["clean_needed"]), "count": 5}
		"research":
			for project: Dictionary in (Content.LAB["projects"] as Array).slice(0, int(value)):
				g.research_done[project["id"]] = true
		"taps", "golden_solved", "dailies", "time_played":
			g.stats[def["type"]] = value
		"tracks":
			for puzzle: Dictionary in Content.PUZZLES:
				if g.get_unlocked_track_ids().size() < int(value):
					g.puzzles_reached[puzzle["id"]] = true
			if g.get_unlocked_track_ids().size() < int(value):
				g.championships = 1


## 7.1a: every achievement is earned exactly at its condition (not before, and not the next tier with it), once.
func test_achievement_conditions() -> void:
	var types := {}
	for def: Dictionary in Content.get_achievements():
		var id: String = def["id"]
		types[def["type"]] = true
		var g := new_game()
		var heard: Array[String] = []
		g.achievement_earned.connect(func(earned: String) -> void: heard.append(earned))
		check(not g.check_achievements().has(id), "%s isn't earned by a new game" % id)
		_reach_achievement(g, def)
		var earned := g.check_achievements()
		check(earned.has(id) and heard.has(id) and g.is_achievement_earned(id), "%s is earned at its condition (%s)" % [id, earned])
		var next := Content.get_achievement("%s_%d" % [def["row"], int(def["tier"]) + 2])
		if int(def["tier"]) >= 0 and not next.is_empty():
			check(not g.is_achievement_earned(next["id"]), "...but not %s with it" % next["id"])
		check(g.check_achievements().is_empty(), "%s: nothing is earned twice" % id)
		g.free()
	for type: String in Content.ACHIEVEMENT_TYPES:
		check(types.has(type), "achievement type %s is used" % type)
	# They're checked once a second (GameState._process), purchases included.
	var live := new_game()
	var live_heard: Array[String] = []
	live.achievement_earned.connect(func(id: String) -> void: live_heard.append(id))
	live.buy_building("friend")
	live.cheat_add_solves(5.0)
	live._process(0.5)
	check(live_heard.is_empty(), "nothing is earned before the once-a-second check (%s)" % [live_heard])
	live._process(0.6)
	check(live_heard.has("solves_1") and live_heard.has("team_friend_1"), "...then they are (%s)" % [live_heard])
	live.free()


## 7.1a: each achievement gives +1 % trophies per championship (owner, 2026-11-12: not moves), kept through championships.
func test_achievement_bonus() -> void:
	var g := new_game()
	var moves_before := g.get_puzzle_moves_mult("2x2")
	g.total_solves = 100.0
	var earned := g.check_achievements()
	check(earned.size() == 3, "100 Solves earn Solver I–III (%s)" % [earned])
	check_near(g.get_achievement_mult(), 1.0, "before the first championship they give nothing yet (the first run's pacing)")
	check_near(g.get_puzzle_moves_mult("2x2"), moves_before, "...and never more moves")
	var progress := g.get_achievement_progress()
	check(int(progress["earned"]) == 3 and int(progress["total"]) == Content.get_achievements().size(), "x/y: %s" % progress)
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	check(g.compete() > 0, "test setup: a championship")
	g._load_collection({})  # its Cube Collection drop could be a 2×2 cube: moves are measured below
	check(g.is_achievement_earned("solves_3"), "achievements stay through a championship")
	g.check_achievements()  # (after the first championship achievements also drop items: cleared again below)
	g._load_collection({})
	check(g.is_achievement_earned("champion_1"), "...and the first win earns Champion I")
	var count := g.achievements.size()
	check_near(g.get_achievement_mult(), 1.0 + 0.01 * count, "after it: +1 %% trophies each (%d)" % count)
	check_near(g.get_trophy_gain_mult(), g.get_achievement_mult(), "...in the trophy gain multiplier")
	check_near(g.get_puzzle_moves_mult("2x2"), moves_before * g.get_trophy_mult(), "...and still not in moves")
	var run := GameState.solves_for_trophies(100)
	g.cheat_add_solves(run)
	check(g.get_pending_trophies() == GameState.trophies_for(g.get_run_solves(), g.get_achievement_mult())
			and g.get_pending_trophies() > 100, "Solves for 100 trophies win more (%d)" % g.get_pending_trophies())
	check_near(float(g.get_championship_preview()["gain_mult"]), g.get_achievement_mult(), "the Compete screen shows the ×")
	check(Array(Content.CHAMPIONSHIP["keeps"]).any(func(line: String) -> bool: return line.begins_with("Achievements")),
			"the Compete screen lists achievements as kept")
	g.free()


## 7.1a: achievements are saved; unknown ids are dropped; v13 saves earn what they already reached, silently (v14).
func test_achievement_save() -> void:
	var g := new_game()
	g.buildings["friend"] = 10
	g.total_solves = 1000.0
	g.check_achievements()
	var data := g.get_save_data()
	check(int(data["version"]) == GameState.SAVE_VERSION and GameState.SAVE_VERSION >= 14, "saves as v14 or later")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.achievements.keys() == g.achievements.keys(), "achievements survive save/load")
	check_near(loaded.get_trophy_gain_mult(), g.get_trophy_gain_mult(), "...with their bonus")
	loaded.free()
	data["achievements"] = ["banana", 5, "solves_1", "team_friend_2"]
	var damaged := new_game()
	damaged.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(damaged.achievements.keys() == ["solves_1", "team_friend_2"], "unknown ids are dropped (%s)" % [damaged.achievements.keys()])
	damaged.free()
	# v13 -> v14: what the save already reached is earned without a signal; the rest waits.
	var v13 := g.get_save_data()
	v13["version"] = 13
	v13.erase("achievements")
	var old := new_game()
	var heard: Array[String] = []
	old.achievement_earned.connect(func(id: String) -> void: heard.append(id))
	old.apply_save_data(JSON.parse_string(JSON.stringify(v13)), float(v13["saved_at"]))
	check(heard.is_empty() and old.is_achievement_earned("team_friend_2") and old.is_achievement_earned("solves_4"),
			"v13 → v14: what an old save reached is earned, silently (%s)" % [old.achievements.keys()])
	check(not old.is_achievement_earned("team_friend_3") and not old.is_achievement_earned("solves_5"), "...and nothing more")
	old.championships = 1
	check_near(old.get_achievement_mult(), 1.0 + 0.01 * old.achievements.size(), "...with its bonus (after a championship)")
	old.free()
	# Reached while away (CFOP learned): not signalled during the load, earned at the first check afterwards.
	var away := new_game()
	away.cheat_add_solves(1e4)
	away.research = {"id": "method_cfop", "left": 60.0}
	var away_data := away.get_save_data()
	away_data["saved_at"] = 1000.0
	away.free()
	var back := new_game()
	var back_heard: Array[String] = []
	back.achievement_earned.connect(func(id: String) -> void: back_heard.append(id))
	back.apply_save_data(JSON.parse_string(JSON.stringify(away_data)), 1000.0 + 3600.0)
	check(back.method == "cfop" and not back_heard.has("method_cfop"), "CFOP learned while away: nothing signalled during the load")
	back._process(1.0)
	check(back_heard.has("method_cfop"), "...it's earned at the first check after loading")
	back.free()
	# The same from a v13 save: the backfill runs before the time away, so CFOP isn't earned silently with it.
	away_data["version"] = 13
	away_data.erase("achievements")
	var back13 := new_game()
	var back13_heard: Array[String] = []
	back13.achievement_earned.connect(func(id: String) -> void: back13_heard.append(id))
	back13.apply_save_data(JSON.parse_string(JSON.stringify(away_data)), 1000.0 + 3600.0)
	check(back13.method == "cfop" and back13.is_achievement_earned("solves_5") and not back13.is_achievement_earned("method_cfop"),
			"v13 + time away: the backfill earned what was reached before leaving, not CFOP")
	back13._process(1.0)
	check(back13_heard.has("method_cfop") and not back13_heard.has("solves_5"), "...CFOP is signalled at the first check (%s)" % [back13_heard])
	back13.free()
	g.free()


## 7.2a: the Stats counters count what they say, and a championship keeps all but this run's time.
func test_stats_counting() -> void:
	var g := new_game()
	var fresh := g.get_stats()
	for key: String in ["time_played", "run_time", "fastest_championship", "taps", "best_solves_per_second", "puzzle_solves",
			"trophies_won", "golden_solved", "dailies", "lifetime_solves", "lifetime_moves", "run_solves", "championships",
			"trophies", "hand_solves", "achievements_earned", "achievements_total"]:
		check(fresh.has(key), "get_stats() has %s" % key)
	check(float(fresh["taps"]) == 0.0 and (fresh["puzzle_solves"] as Dictionary).is_empty(), "a new game has counted nothing")
	for i in 3:
		g.tap()
	check(float(g.get_stats()["taps"]) == 3.0, "taps are counted")
	g._process(0.5)
	g._process(0.6)
	check_near(float(g.get_stats()["time_played"]), 1.1, "time played adds up while the game runs")
	check_near(float(g.get_stats()["run_time"]), 1.1, "...and so does this run's time")
	g.cheat_add_solves(5.0)
	g.buy_building("friend")
	g._process(1.0)
	check(float(g.get_stats()["best_solves_per_second"]) > 0.0
			and is_equal_approx(float(g.get_stats()["best_solves_per_second"]), g.get_solves_per_second()),
			"the best Solves/s is checked once a second")
	var signalled := [0.0]
	g.solved.connect(func(count: int, puzzle_id: String) -> void:
		if puzzle_id == "2x2":
			signalled[0] += count)
	var before_2x2 := float((g.get_stats()["puzzle_solves"] as Dictionary).get("2x2", 0.0))
	g.add_moves_to("2x2", g.get_moves_per_solve("2x2") * 4.0)
	var per_puzzle: Dictionary = g.get_stats()["puzzle_solves"]
	check(signalled[0] >= 4.0 and float(per_puzzle.get("2x2", 0.0)) - before_2x2 == signalled[0] and not per_puzzle.has("3x3"),
			"solves are counted per puzzle, exactly (%s, %s signalled)" % [per_puzzle, signalled[0]])
	var counted_2x2 := float(per_puzzle["2x2"])
	per_puzzle["2x2"] = -1.0
	check(float((g.stats["puzzle_solves"] as Dictionary)["2x2"]) == counted_2x2, "get_stats() hands out a copy")
	g.golden_attempt_left = 10.0
	g.finish_golden(false)
	g.golden_attempt_left = 10.0
	g.finish_golden(true)
	check(float(g.get_stats()["golden_solved"]) == 1.0, "a Golden Scramble solved in time counts, a missed one doesn't")
	g.daily_now = 1.8e9
	g.record_daily("3x3", "time", 30.0)
	g.record_daily("3x3", "time", 20.0)
	check(float(g.get_stats()["dailies"]) == 1.0, "a daily reward counts once a day")
	# A championship: trophies won add up, the run's time becomes the fastest, and only the run's time resets.
	g.stats["run_time"] = 5000.0
	g.cheat_add_solves(GameState.solves_for_trophies(3))
	var won := g.compete()
	var after := g.get_stats()
	check(won > 0 and float(after["trophies_won"]) == won, "trophies won are counted (%d)" % won)
	check_near(float(after["fastest_championship"]), 5000.0, "the run's time is the fastest championship so far")
	check(float(after["run_time"]) == 0.0, "a new run starts its clock at 0")
	check(float(after["taps"]) == 3.0 and float(after["golden_solved"]) == 1.0 and float(after["dailies"]) == 1.0
			and float((after["puzzle_solves"] as Dictionary)["2x2"]) == counted_2x2 and float(after["time_played"]) > 1.0
			and float(after["best_solves_per_second"]) > 0.0, "every other counter is kept through it")
	g.perks["comp_prep"] = true
	g.trophies -= 1
	check(float(g.get_stats()["trophies_won"]) == won, "spending trophies doesn't lower trophies won")
	g.stats["run_time"] = 9000.0
	g.cheat_add_solves(GameState.solves_for_trophies(3))
	g.compete()
	check_near(float(g.get_stats()["fastest_championship"]), 5000.0, "a slower run doesn't replace the fastest")
	g.stats["run_time"] = 100.0
	g.cheat_add_solves(GameState.solves_for_trophies(3))
	g.compete()
	check_near(float(g.get_stats()["fastest_championship"]), 100.0, "a faster one does")
	g.free()
	# Time from _process reaches the championship.
	var timed := new_game()
	timed._process(30.0)
	timed.cheat_add_solves(GameState.solves_for_trophies(1))
	timed.compete()
	check_near(float(timed.get_stats()["fastest_championship"]), 30.0, "the run's played time is what a championship records")
	timed.free()


## 7.2a: stats are saved; damaged values are dropped; v14 saves start them (trophies won worked out); time away counts
## for the run, not as time played.
func test_stats_save() -> void:
	var g := new_game()
	g.tap()
	g.update_play_time(120.0)
	g.add_moves_to("2x2", g.get_moves_per_solve("2x2") * 2.0)
	g.stats["golden_solved"] = 4.0
	var data := g.get_save_data()
	check(int(data["version"]) == GameState.SAVE_VERSION and GameState.SAVE_VERSION >= 15, "saves as v15 or later")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.stats == g.stats, "stats survive save/load (%s)" % loaded.stats)
	loaded.free()
	data["stats"] = {"taps": "lots", "time_played": -5.0, "golden_solved": 2, "banana": 1.0,
			"puzzle_solves": {"2x2": 3.0, "9x9": 1.0, "3x3": "x"}}
	var damaged := new_game()
	damaged.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(float(damaged.stats["taps"]) == 0.0 and float(damaged.stats["time_played"]) == 0.0
			and float(damaged.stats["golden_solved"]) == 2.0 and not damaged.stats.has("banana")
			and damaged.stats["puzzle_solves"] == {"2x2": 3.0}, "damaged values are dropped (%s)" % damaged.stats)
	damaged.free()
	var not_a_dict := g.get_save_data()
	not_a_dict["stats"] = [1, 2]
	var odd := new_game()
	odd.apply_save_data(JSON.parse_string(JSON.stringify(not_a_dict)), float(not_a_dict["saved_at"]))
	check(odd.stats == GameState._new_stats(), "stats that aren't a dictionary start fresh")
	odd.free()
	# v14 -> v15: trophies won = the ones held + the ones spent on perks; the rest starts at 0.
	var v14 := g.get_save_data()
	v14["version"] = 14
	v14.erase("stats")
	v14["championship"]["trophies"] = 7
	v14["championship"]["count"] = 1
	v14["championship"]["perks"] = ["warm_up", "team_captain", "warm_up", "banana"]
	var old := new_game()
	old.apply_save_data(JSON.parse_string(JSON.stringify(v14)), float(v14["saved_at"]))
	var spent := float(Content.get_perk("warm_up")["cost"]) + float(Content.get_perk("team_captain")["cost"])
	check(old.perks.size() == 2 and float(old.stats["trophies_won"]) == 7.0 + spent,
			"v14 → v15: trophies won = held + spent on perks (%s)" % old.stats["trophies_won"])
	check(float(old.stats["taps"]) == 0.0 and float(old.stats["time_played"]) == 0.0, "...and the rest starts at 0")
	old.update_play_time(1200.0)
	old.cheat_add_solves(GameState.solves_for_trophies(1))
	check(old.compete() > 0 and float(old.stats["fastest_championship"]) == 0.0,
			"...and the run it was in (started before its clock) doesn't set the fastest championship")
	old.update_play_time(900.0)
	old.cheat_add_solves(GameState.solves_for_trophies(1))
	old.compete()
	check_near(float(old.stats["fastest_championship"]), 900.0, "...the next one does")
	check(int(old.get_save_data()["version"]) == GameState.SAVE_VERSION, "...and it saves as the current version")
	old.free()
	for champ: Variant in [null, {"trophies": 3, "perks": null}, {"trophies": 3, "perks": "warm_up"}]:
		var odd_v14 := v14.duplicate(true)
		if typeof(champ) == TYPE_NIL:
			odd_v14.erase("championship")
		else:
			odd_v14["championship"] = champ
		var odd_old := new_game()
		odd_old.apply_save_data(JSON.parse_string(JSON.stringify(odd_v14)), float(odd_v14["saved_at"]))
		check(float(odd_old.stats["trophies_won"]) == (0.0 if typeof(champ) == TYPE_NIL else 3.0), "a damaged v14 championship still loads (%s)" % [champ])
		odd_old.free()
	# Time away: the run goes on, nobody played.
	var away := g.get_save_data()
	away["saved_at"] = 1000.0
	var back := new_game()
	back.apply_save_data(JSON.parse_string(JSON.stringify(away)), 1000.0 + 600.0)
	check_near(float(back.stats["run_time"]), float(g.stats["run_time"]) + 600.0, "time away counts for the run")
	check_near(float(back.stats["time_played"]), float(g.stats["time_played"]), "...not as time played")
	back.free()
	g.free()


## 7.3a: the Cube Collection's data is complete and uses made-up brands.
func test_collection_data() -> void:
	var items: Array = Content.COLLECTION["items"]
	check(items.size() >= 36 and items.size() <= 45, "about 40 items (%d)" % items.size())
	var ids := {}
	var per_rarity := {}
	var kinds := {}
	for def: Dictionary in items:
		var id: String = def["id"]
		check(not ids.has(id), "item ids are unique (%s)" % id)
		ids[id] = true
		check(Content.get_collection_item(id) == def, "get_collection_item finds %s" % id)
		check(String(def["name"]).length() > 3 and String(def["brand"]) != "", "%s has a name and a brand" % id)
		check(Content.COLLECTION_KINDS.has(def["kind"]), "%s has a known kind" % id)
		kinds[def["kind"]] = true
		check(Content.get_rarity_index(def["rarity"]) >= 0, "%s has a known rarity" % id)
		per_rarity[def["rarity"]] = int(per_rarity.get(def["rarity"], 0)) + 1
		check(ResourceLoader.exists(Content.ICON_DIR + String(def["icon"]) + ".svg"), "%s has an icon file" % id)
		var effect: Dictionary = def["effect"]
		check(Content.COLLECTION_EFFECT_TYPES.has(effect["type"]) and Content.EFFECT_TYPES.has(effect["type"]),
				"%s has a multiplying upgrade effect (%s)" % [id, effect["type"]])
		if effect["type"] == "puzzle_mult":
			check(not (effect.get("puzzles", []) as Array).is_empty(), "%s: a puzzle_mult names its puzzles" % id)
		if effect["type"] == "building_mult":
			check(effect.has("target"), "%s: a building_mult names its helper" % id)
		for puzzle: Variant in effect.get("puzzles", []):
			check(not Content.get_puzzle(str(puzzle)).is_empty(), "%s: puzzle %s exists" % [id, puzzle])
		if effect.has("target"):
			check(not Content.get_building(effect["target"]).is_empty(), "%s: helper %s exists" % [id, effect["target"]])
		check(Content.get_item_per_star(def) > 0.0 and Content.get_item_per_star(def) <= 0.1, "%s has a small passive" % id)
		for real: String in ["gan", "moyu", "qiyi", "yj", "dayan", "shengshou", "x-man", "speedstacks", "cyclone", "rubik"]:
			check(not String(def["name"]).to_lower().contains(real) and String(def["brand"]).to_lower() != real,
					"%s doesn't use a real brand (%s)" % [id, real])
	for rarity: Dictionary in Content.COLLECTION["rarities"]:
		check(int(per_rarity.get(rarity["id"], 0)) > 0 and float(rarity["weight"]) > 0.0, "rarity %s has items and a weight" % rarity["id"])
	for kind: String in Content.COLLECTION_KINDS:
		check(kinds.has(kind), "there are %s items (for 7.4's Comp Kit)" % kind)
	for source: String in Content.COLLECTION["sources"]:
		var def: Dictionary = Content.COLLECTION["sources"][source]
		check(float(def["chance"]) > 0.0 and float(def["chance"]) <= 1.0 and int(def["pity"]) >= 1, "source %s: a chance and a pity" % source)
	check(Content.get_rarity_index(Content.COLLECTION["rarity_pity"]["rarity"]) > 0, "the rarity pity names a rare-or-better rarity")


## 7.3a: drops: every source's pity caps a dry streak, the rarity pity caps a streak of low rarities, duplicates add a
## star up to the max, and a maxed collection gets nothing.
func test_collection_drops_and_pity() -> void:
	var g := new_game()
	g.championships = 1  # achievements drop items only from the first championship on
	g.collection_rng.seed = 12345
	var heard: Array = []
	g.collection_drop.connect(func(id: String, stars: int, source: String) -> void: heard.append([id, stars, source]))
	for source: String in Content.COLLECTION["sources"]:
		var pity := int(Content.COLLECTION["sources"][source]["pity"])
		var streak := 0
		var longest := 0
		var drops := 0
		for i in 300:
			if g.roll_collection_drop(source) == "":
				streak += 1
				longest = maxi(longest, streak)
			else:
				streak = 0
				drops += 1
			if g.get_collection_stars_total() >= 150:
				g._load_collection({})  # keep room to grow
		check(longest <= pity - 1, "%s: never more than %d misses in a row (%d)" % [source, pity - 1, longest])
		check(drops > 0, "%s drops something" % source)
	check(g.roll_collection_drop("banana") == "", "an unknown source drops nothing")
	# The rarity pity: never more than `after` drops in a row below its rarity.
	var floor_index := Content.get_rarity_index(Content.COLLECTION["rarity_pity"]["rarity"])
	var after := int(Content.COLLECTION["rarity_pity"]["after"])
	g._load_collection({})
	var low := 0
	var longest_low := 0
	for i in 400:
		if g.get_collection_stars_total() >= 180:
			g._load_collection({"pity": {"rarity": g.collection_pity.get("rarity", 0)}})
		var id := g.roll_collection_drop("championship")
		low = low + 1 if Content.get_rarity_index(Content.get_collection_item(id)["rarity"]) < floor_index else 0
		longest_low = maxi(longest_low, low)
	check(longest_low <= after, "never more than %d drops in a row below %s (%d)" % [after, Content.COLLECTION["rarity_pity"]["rarity"], longest_low])
	# Merging: a duplicate is the next star; the signal says so.
	var fresh := new_game()
	fresh.collection_rng.seed = 99
	var got: Array = []
	fresh.collection_drop.connect(func(id: String, stars: int, source: String) -> void: got.append([id, stars, source]))
	var first := fresh.roll_collection_drop("championship")
	check(first != "" and fresh.get_collection_stars(first) == 1 and got[0] == [first, 1, "championship"], "a new item starts at 1 star")
	var maxed := {}
	for def: Dictionary in Content.COLLECTION["items"]:
		maxed[def["id"]] = int(Content.COLLECTION["max_stars"])
	maxed[first] = 1
	fresh._load_collection({"items": maxed})
	check(fresh.roll_collection_drop("championship") == first and fresh.get_collection_stars(first) == 2
			and got.back() == [first, 2, "championship"], "a duplicate merges into the next star (and drops land where they can grow)")
	maxed[first] = int(Content.COLLECTION["max_stars"])
	fresh._load_collection({"items": maxed})
	var stars_before := fresh.get_collection_stars_total()
	check(fresh.roll_collection_drop("championship") == "" and fresh.get_collection_stars_total() == stars_before,
			"a full collection gets nothing, and nothing goes past max stars")
	var progress := fresh.get_collection_progress()
	check(int(progress["owned"]) == int(progress["total"]) and int(progress["stars"]) == int(progress["max_stars"]), "x/y: %s" % progress)
	fresh.free()
	g.free()


## 7.3a: passives: 1 + per_star × stars, on the effect they name only.
func test_collection_passives() -> void:
	var g := new_game()
	g.cheat_add_solves(1e6)
	g.buy_building("friend")
	g.unlock_puzzle("3x3")
	var moves_3x3 := g.get_puzzle_moves_mult("3x3")
	var moves_2x2 := g.get_puzzle_moves_mult("2x2")
	var tap := g.get_tap_moves_flat()
	var helper := g.get_building_mps("friend")
	var value := g.get_solve_value("3x3")
	g._load_collection({"items": {"torque_3m": 2, "pocket_lube": 3, "pocket_mat": 1, "kestrel_pro_timer": 1}})
	check(g.is_equipped("torque_3m") and g.is_equipped("pocket_lube") and g.is_equipped("pocket_mat")
			and g.is_equipped("kestrel_pro_timer"), "the kit filled itself (7.4a): full passives below")
	check_near(g.get_item_mult("torque_3m"), 1.0 + 0.02 * 2, "a rare item at 2 stars: +4 %")
	check_near(g.get_puzzle_moves_mult("3x3"), moves_3x3 * 1.04, "a 3×3 cube speeds up the 3×3")
	check_near(g.get_puzzle_moves_mult("2x2"), moves_2x2, "...and nothing else")
	check_near(g.get_tap_moves_flat(), tap * 1.03, "lube: taps")
	check_near(g.get_building_mps("friend"), helper * 1.01, "a mat: helpers")
	check_near(g.get_solve_value("3x3"), value * 1.05, "a legendary timer: Solves per solve")
	check_near(g.get_item_mult("swift_duo"), 1.0, "an item not owned does nothing")
	g.free()


## 7.4a: the Comp Kit's data: five typed slots, sets of real brands that can be completed.
func test_comp_kit_data() -> void:
	var kinds := {}
	for slot: Dictionary in Content.COMP_KIT["slots"]:
		check(Content.COLLECTION_KINDS.has(slot["kind"]) and Content.get_kit_slot(slot["id"]) == slot, "slot %s has a known kind" % slot["id"])
		kinds[slot["kind"]] = int(kinds.get(slot["kind"], 0)) + 1
	check(Content.COMP_KIT["slots"].size() == 5 and kinds.get("cube", 0) == 2, "Main cube, Backup cube, Timer, Mat, Lube")
	for set_def: Dictionary in Content.COMP_KIT["sets"]:
		var fits := 0
		for slot: Dictionary in Content.COMP_KIT["slots"]:
			var items := 0
			for item: Dictionary in Content.COLLECTION["items"]:
				if item["brand"] == set_def["brand"] and item["kind"] == slot["kind"]:
					items += 1
			fits += mini(items, kinds[slot["kind"]]) if slot["kind"] != "cube" or slot["id"] == "main" else 0
		check(fits >= int(set_def["pieces"]), "%s (%d pieces) can be completed (%d fit)" % [set_def["name"], set_def["pieces"], fits])
		check(Content.COLLECTION_EFFECT_TYPES.has(set_def["effect"]["type"]) and float(set_def["effect"]["value"]) > 1.0,
				"%s has a multiplying bonus" % set_def["name"])
	check(float(Content.COMP_KIT["owned_share"]) > 0.0 and float(Content.COMP_KIT["owned_share"]) < 1.0, "items outside the kit give a share")


## 7.4a: equipping (slot types, swaps, manual vs auto slots), the owned share and brand sets.
func test_comp_kit_rules() -> void:
	var g := new_game()
	var changes := [0]
	g.kit_changed.connect(func() -> void: changes[0] += 1)
	g._load_collection({"items": {"pocket_classic": 1, "pocket_mini": 1, "torque_3m": 1, "pocket_timer": 2, "pocket_lube": 1}})
	check(g.get_kit() == {"main": "torque_3m", "backup": "pocket_mini", "timer": "pocket_timer", "lube": "pocket_lube"},
			"auto slots take the best of their kind (ties: data order), cubes in Main then Backup (%s)" % g.get_kit())
	# The owned share: an item outside the kit gives a quarter.
	check_near(g.get_item_mult("pocket_classic"), 1.0 + 0.01 * float(Content.COMP_KIT["owned_share"]), "outside the kit: a share of its passive")
	check_near(g.get_item_mult("pocket_mini"), 1.01, "in the kit: all of it")
	# Slot types.
	check(not g.equip("timer", "pocket_lube") and not g.equip("main", "swift_duo") and not g.equip("banana", "pocket_mini"),
			"wrong kind, not owned or no such slot: refused")
	# A manual pick sticks; a swap between the cube slots.
	var before: int = changes[0]
	check(g.equip("main", "pocket_classic") and g.get_kit()["main"] == "pocket_classic" and g.is_slot_manual("main"), "equip a cube by hand")
	check(changes[0] > before, "kit_changed is signalled")
	check(g.get_kit()["backup"] == "torque_3m" and not g.is_slot_manual("backup"), "...and the auto Backup takes the best one left (%s)" % g.get_kit())
	check(g.equip("main", "torque_3m") and g.get_kit()["main"] == "torque_3m" and g.get_kit()["backup"] == "pocket_classic"
			and g.is_slot_manual("backup"), "picking the Backup's cube for Main swaps them (%s)" % g.get_kit())
	g.collection_rng.seed = 2
	var maxed := {}
	for item: Dictionary in Content.COLLECTION["items"]:
		if item["kind"] == "cube" and item["rarity"] != "legendary":
			maxed[item["id"]] = int(Content.COLLECTION["max_stars"])
	maxed.merge({"torque_3m": 1, "pocket_mini": 1, "pocket_timer": 2, "pocket_lube": 1}, true)
	g._load_collection({"items": maxed})
	check(g.get_kit()["main"] == "torque_3m" and g.get_kit()["backup"] == "pocket_classic", "better cubes don't replace manual picks")
	g.set_slot_auto("backup")
	check(g.get_kit()["backup"] != "pocket_classic" and not g.is_slot_manual("backup"), "back on auto, the slot takes the best (%s)" % g.get_kit()["backup"])
	check(g.equip("lube", "") and not g.get_kit().has("lube") and g.is_slot_manual("lube"), "a slot can be emptied by hand, and stays empty")
	g.free()
	# Moving the only cube into the empty Backup leaves Main on auto, so the next cube fills it.
	var mover := new_game()
	mover._load_collection({"items": {"pocket_mini": 1}})
	check(mover.get_kit() == {"main": "pocket_mini"}, "test setup: one cube, in Main")
	check(mover.equip("backup", "pocket_mini") and mover.get_kit() == {"backup": "pocket_mini"}
			and not mover.is_slot_manual("main"), "moving it to Backup leaves Main empty but on auto (%s)" % [mover.kit_manual])
	mover.collection_rng.seed = 4
	mover._load_collection({"items": {"pocket_mini": 1, "torque_3m": 1}})
	check(mover.get_kit().get("main", "") == "torque_3m" and mover.get_kit()["backup"] == "pocket_mini", "...so a new cube goes there")
	check(mover.equip("backup", "pocket_mini") and mover.get_kit()["backup"] == "pocket_mini", "equipping a slot's own item changes nothing")
	mover.free()
	# Brand sets: 3 Pocket pieces add the Budget Kit, 5 its bigger tier instead.
	var s := new_game()
	var tap := s.get_tap_moves_flat()
	s._load_collection({"items": {"pocket_classic": 1, "pocket_stickered": 1, "pocket_timer": 1}})
	var three: Array = s.get_active_kit_sets()
	check(three.size() == 1 and three[0]["pieces"] == 3 and three[0]["brand"] == "pocket", "three Pocket pieces: the Budget Kit (%s)" % [three])
	check_near(s.get_tap_moves_flat(), tap * 1.15, "...×1.15 taps")
	s._load_collection({"items": {"pocket_classic": 1, "pocket_stickered": 1, "pocket_timer": 1, "pocket_mat": 1, "pocket_lube": 1}})
	var five: Array = s.get_active_kit_sets()
	check(five.size() == 1 and five[0]["pieces"] == 5, "five: only the bigger tier (%s)" % [five])
	check_near(s.get_tap_moves_flat(), tap * 1.4 * 1.01, "...×1.4 taps, with the lube's own +1 %")
	s.equip("main", "")
	check(s.get_active_kit_sets().size() == 1 and s.get_active_kit_sets()[0]["pieces"] == 3, "one piece out: back to the 3-piece bonus")
	s.free()


## 7.4a: the kit is kept through championships and saved (v17); older saves get a kit that fills itself.
func test_comp_kit_save() -> void:
	var g := new_game()
	g._load_collection({"items": {"pocket_classic": 1, "torque_3m": 1, "pocket_timer": 1}})
	g.equip("backup", "torque_3m")
	var kit := g.get_kit()
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	g.compete()
	check(g.get_kit()["backup"] == "torque_3m" and g.is_slot_manual("backup"), "the kit is kept through a championship")
	var data := g.get_save_data()
	check(int(data["version"]) == GameState.SAVE_VERSION and GameState.SAVE_VERSION >= 17, "saves as v17 or later")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.get_kit() == g.get_kit() and loaded.kit_manual == g.kit_manual, "the kit and its manual slots survive save/load (%s)" % loaded.get_kit())
	loaded.free()
	data["kit"] = {"slots": {"main": "banana", "backup": "pocket_timer", "timer": "swift_comp_timer", "mat": 5}, "manual": ["backup", "nope", 3]}
	var damaged := new_game()
	damaged.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(not damaged.get_kit().has("backup") and damaged.kit_manual.keys() == ["backup"] and damaged.get_kit()["timer"] != "swift_comp_timer"
			and damaged.get_collection_stars(damaged.get_kit()["timer"]) > 0,
			"wrong kinds, unknown or unowned items and slots are dropped; auto slots refill (%s)" % damaged.get_kit())
	damaged.free()
	var v16 := g.get_save_data()
	v16["version"] = 16
	v16.erase("kit")
	var old := new_game()
	old.apply_save_data(JSON.parse_string(JSON.stringify(v16)), float(v16["saved_at"]))
	check(old.kit_manual.is_empty() and old.get_kit().has("main") and old.get_kit().has("timer"), "v16 → v17: every slot on auto, filled (%s)" % old.get_kit())
	old.free()
	g.free()


## 7.3a: what drops when (Golden Scrambles, achievements, championships), kept through championships, saved (v16).
func test_collection_sources_and_save() -> void:
	var g := new_game()
	g.collection_rng.seed = 5
	var sources: Array[String] = []
	g.collection_drop.connect(func(_id: String, _stars: int, source: String) -> void: sources.append(source))
	for i in int(Content.COLLECTION["sources"]["golden"]["pity"]):
		g.golden_attempt_left = 10.0
		g.finish_golden(true)
	check(sources.count("golden") >= 1, "Golden Scrambles drop items (at the latest at their pity)")
	var golden_drops := sources.count("golden")
	g.golden_attempt_left = 10.0
	g.finish_golden(false)
	check(sources.count("golden") == golden_drops and int(g.collection_pity.get("golden", 0)) <= 2, "a missed one doesn't try")
	g.total_solves = 1e6
	g.check_achievements()
	check(not sources.has("achievement") and not g.collection_pity.has("achievement"),
			"before the first championship achievements drop nothing, and their pity doesn't move (owner, 2026-11-12)")
	var before := g.get_collection_stars_total()
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	g.compete()
	check(sources.has("championship") and g.get_collection_stars_total() > before, "a championship always drops one, and the collection stays")
	for i in int(Content.COLLECTION["sources"]["achievement"]["pity"]):
		g.total_solves = pow(10.0, i + 7)
		g.check_achievements()
	check(sources.has("achievement"), "after it, achievements drop items (at the latest at their pity)")
	var data := g.get_save_data()
	check(int(data["version"]) == GameState.SAVE_VERSION and GameState.SAVE_VERSION >= 16, "saves as v16 or later")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.collection == g.collection and loaded.collection_pity == g.collection_pity
			and loaded.get_collection_stars_total() == g.get_collection_stars_total(), "the collection and its pity survive save/load")
	loaded.free()
	data["collection"] = {"items": {"torque_3m": 9, "banana": 2, "pocket_mini": "x", "lumen_neon": 0, "swift_duo": 2.0},
			"pity": {"golden": 2, "banana": 5, "rarity": -3, "achievement": "x"}}
	var damaged := new_game()
	damaged.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(damaged.collection == {"torque_3m": int(Content.COLLECTION["max_stars"]), "swift_duo": 2}
			and damaged.get_collection_stars_total() == int(Content.COLLECTION["max_stars"]) + 2, "damaged items are dropped or clamped (%s)" % damaged.collection)
	check(damaged.collection_pity == {"golden": 2, "rarity": 0}, "damaged pity is dropped (%s)" % damaged.collection_pity)
	damaged.free()
	var v15 := g.get_save_data()
	v15["version"] = 15
	v15.erase("collection")
	var old := new_game()
	var old_drops: Array = []
	old.collection_drop.connect(func(id: String, _stars: int, _source: String) -> void: old_drops.append(id))
	old.apply_save_data(JSON.parse_string(JSON.stringify(v15)), float(v15["saved_at"]))
	check(old.championships == 1 and old.get_collection_stars_total() == 1 and old_drops.size() == 1,
			"v15 → v16: one item per championship already won (the drops they'd give now) (%s)" % [old.collection])
	check(int(old.get_save_data()["version"]) == GameState.SAVE_VERSION, "...and it saves as the current version")
	var again := new_game()
	again.apply_save_data(JSON.parse_string(JSON.stringify(v15)), float(v15["saved_at"]))
	check(again.collection == old.collection, "...the same items each time that save loads (%s, %s)" % [again.collection, old.collection])
	again.free()
	old.free()
	var huge := v15.duplicate(true)
	huge["championship"]["count"] = 1000000
	var veteran := new_game()
	veteran.apply_save_data(JSON.parse_string(JSON.stringify(huge)), float(huge["saved_at"]))
	var full := veteran.get_collection_progress()
	check(int(full["stars"]) <= int(full["max_stars"]), "...and a huge count just fills the collection (no endless loop)")
	veteran.free()
	v15["championship"]["count"] = 0
	var rookie := new_game()
	rookie.apply_save_data(JSON.parse_string(JSON.stringify(v15)), float(v15["saved_at"]))
	check(rookie.collection.is_empty(), "...none before a first championship")
	rookie.free()
	g.free()


## V.7: big-moment banners: one at a time, same-kind moments merge, the queue stays short, a kind cools down, a
## championship always gets through; Reduce motion keeps the banner but drops confetti.
func test_banner_queue() -> void:
	var banner: Banner = load("res://scenes/banner.tscn").instantiate()
	root.add_child(banner)
	var was := UiFx.reduce_motion
	UiFx.reduce_motion = false
	var view := func(kind: String, title: String) -> Dictionary:
		return {"kind": kind, "title": title, "subtitle": "", "icon": Content.icon("friend"), "category": &"helpers"}
	check(banner.push(view.call("puzzle", "New puzzle unlocked: 3×3")), "a moment queues")
	banner.advance(0.0)
	check(banner.is_showing() and banner.get_showing()["title"] == "New puzzle unlocked: 3×3" and banner._title.text.contains("3×3"),
			"...and shows at once")
	check(banner._confetti.emitting, "...with confetti")
	for name: String in ["Friend", "Club", "Robot", "Competition"]:
		banner.push(view.call("helper", "New helper: " + name))
	check(banner.get_waiting() == 1, "four helpers while one shows: they merge into one waiting banner")
	banner.push(view.call("method", "Method learned: CFOP"))
	banner.push(view.call("puzzle", "New puzzle unlocked: 4×4"))
	banner.push(view.call("championship", "World Champion!"))
	check(banner.get_waiting() <= Banner.MAX_QUEUE, "the queue stays short (%d)" % banner.get_waiting())
	var seen: Array[String] = []
	for step in 200:  # 20 s
		var before := banner.shown_count
		banner.advance(0.1)
		if banner.shown_count > before:
			seen.append(String(banner.get_showing()["kind"]))
	check(seen.has("championship"), "a championship always gets through (%s)" % [seen])
	check(seen.size() <= Banner.MAX_QUEUE, "the oldest ordinary moment made room: no more than the queue holds (%s)" % [seen])
	# The helper banner names the merged ones.
	var merged: Banner = load("res://scenes/banner.tscn").instantiate()
	root.add_child(merged)
	merged.push(view.call("puzzle", "first"))
	merged.advance(0.0)
	merged.push(view.call("helper", "New helper: Friend"))
	merged.push(view.call("helper", "New helper: Club"))
	merged.advance(Banner.HOLD + 0.01)
	merged.advance(Banner.GAP + 0.01)
	check(merged.get_showing().get("kind", "") == "helper" and merged._subtitle.text.contains("1 more")
			and merged._subtitle.text.contains("Club"), "a merged banner says how many more came (%s)" % merged._subtitle.text)
	# A kind cools down: a second helper banner waits.
	merged.advance(Banner.HOLD + 0.01)
	merged.push(view.call("helper", "New helper: Robot"))
	merged.advance(Banner.GAP + 0.01)
	check(not merged.is_showing() and merged.get_waiting() == 1, "the same kind again waits for its cooldown")
	merged.advance(Banner.COOLDOWN)
	check(merged.is_showing(), "...then shows")
	merged.free()
	# Reduce motion: shown, no confetti.
	UiFx.reduce_motion = true
	var calm: Banner = load("res://scenes/banner.tscn").instantiate()
	root.add_child(calm)
	calm.stage_rect = Rect2(0, 100, 600, 400)  # (with a stage the sweep would run, with motion)
	calm.push(view.call("puzzle", "New puzzle unlocked: 5×5"))
	calm.advance(0.0)
	check(calm.is_showing() and calm._band.visible and not calm._confetti.emitting and not calm._sweep.visible,
			"Reduce motion: the banner shows, without confetti or the sweep")
	calm.push(view.call("helper", "New helper: Club"))
	calm.clear()
	check(not calm.is_showing() and calm.get_waiting() == 0 and not calm._band.visible, "clear() drops the banner up and the waiting ones")
	calm.free()
	UiFx.reduce_motion = was
	banner.free()


## V.7: three fast runs through the real main screen (every helper, puzzle and method as soon as possible, 10 minutes
## each, a championship between them) never spam banners: the same kind is at least a cooldown apart, the queue stays short, and later runs don't repeat "new" things the player had.
func test_banner_no_spam() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.set_process(false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var banner: Banner = main.banner
	var step := 0.5
	var clock := 0.0
	var last_shown := {}  # kind -> clock it last showed
	var too_close: Array[String] = []
	var later_news: Array[String] = []
	var pushes_in_run_one := 0
	for run in 3:
		for i in 1200:  # 10 minutes in 0.5 s steps
			game.cheat_add_solves(1e3 * pow(1.03, i))  # a fast, steadily growing income: every puzzle within the run
			for def: Dictionary in Content.BUILDINGS:
				if game.is_building_unlocked(def["id"]):
					game.buy_building(def["id"])
			var next := game.get_next_locked_puzzle()
			if next != "" and game.can_unlock_puzzle(next):
				game.unlock_puzzle(next)
			var method := game.get_next_method()
			if not method.is_empty() and game.is_method_available(method["id"]):
				game.buy_method(method["id"])
			game.update_research(step)
			game.check_achievements()
			main._refresh()
			var shown_before := banner.shown_count
			banner.advance(step)
			clock += step
			if banner.shown_count > shown_before:
				var kind := String(banner.get_showing()["kind"])
				if last_shown.has(kind) and kind != "championship" and clock - float(last_shown[kind]) < Banner.COOLDOWN:
					too_close.append(kind)
				last_shown[kind] = clock
				if run > 0 and kind in ["helper", "method"]:
					later_news.append(String(banner.get_showing()["title"]))
		if run == 0:
			pushes_in_run_one = banner.pushed_count
			check(game.is_puzzle_unlocked("5x5") and int(game.buildings["quantum"]) > 0, "test setup: run 1 got through the game")
			check(banner.shown_count <= banner.pushed_count and banner.shown_count >= 4,
					"a handful of moments, each shown at most once (%d of %d)" % [banner.shown_count, banner.pushed_count])
		if game.can_compete():
			game.compete()
	check(too_close.is_empty(), "the same kind never shows twice within its cooldown (%s)" % [too_close])
	check(later_news.is_empty(), "later runs don't announce helpers or methods the player already had (%s)" % [later_news])
	check(banner.pushed_count - pushes_in_run_one <= 12, "later runs push few moments (championships, new puzzles) (%d)" % (banner.pushed_count - pushes_in_run_one))
	main.free()
	game.set_process(true)
	game.reset_state()


## V.7: the solve burst's rim-light flash: High only, not with Reduce motion, at most every RIM_FLASH_INTERVAL, and it
## fades back to the resting light.
func test_rim_flash() -> void:
	var view: PuzzleView3D = load("res://scenes/puzzle_view_3d.tscn").instantiate()
	root.add_child(view)
	view.set_graphics("high")
	view.set_reduce_motion(false)
	check(view.rim_flash() and view.get_rim_energy() >= PuzzleView3D.RIM_ENERGY - 0.01, "a flash on High")
	view._process(0.016)
	check(view.get_rim_energy() > PuzzleView3D.RIM_ENERGY + 1.0, "...the rim light flares")
	check(not view.rim_flash(), "...and not again right away (bursts come every 0.5 s at speed)")
	view._process(1.0)
	check(is_equal_approx(view.get_rim_energy(), PuzzleView3D.RIM_ENERGY), "...then it's back to rest")
	view._process(PuzzleView3D.RIM_FLASH_INTERVAL)
	view.set_reduce_motion(true)
	check(not view.rim_flash(), "Reduce motion: no flash")
	view.set_reduce_motion(false)
	view.set_graphics("low")
	check(not view.rim_flash(), "Low (no rim light): no flash")
	view.free()


## V.8: the Trophy Perks header shows its numbers as StatChips (unspent trophies, singular for one, and the bonus).
func test_perk_header_chips() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	game.trophies = 1
	main.open_perks()
	var trophies: StatChip = main.perk_panel.get_node("%TrophyChip")
	var bonus: StatChip = main.perk_panel.get_node("%BonusChip")
	check(trophies.get_text() == "1 unspent trophy" and bonus.get_text() == "+2 % moves",
			"one trophy: \"%s\", \"%s\"" % [trophies.get_text(), bonus.get_text()])
	game.trophies = 34
	main._refresh()
	check(trophies.get_text() == "34 unspent trophies" and bonus.get_text() == "+68 % moves", "34: \"%s\", \"%s\"" % [trophies.get_text(), bonus.get_text()])
	main.free()
	game.reset_state()


func test_news_on_main_screen() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	game.cheat_add_solves(5.0)
	game.buy_building("friend")
	main._process(0.016)
	var list: VBoxContainer = main.get_node("%NewsList")
	check(list.get_child_count() == 1 and (list.get_child(0) as Label).text.contains("joins the team"), "buying the first Friend makes a news line: it joins the team")
	main._process(float(Content.NEWS["interval"]))
	check(list.get_child_count() == 2 and (list.get_child(0) as Label).text.contains("team: "), "...then its time tier")
	check((list.get_child(0) as Label).theme_type_variation == &"NewsNew", "the newest line is bright")
	main.free()
	game.reset_state()


# --- Golden Scramble (task S.6) ------------------------------------------------------

func test_golden_scramble_timing() -> void:
	var g := new_game()
	var data: Dictionary = Content.GOLDEN
	check(g.golden_next >= float(data["spawn_min"]) and g.golden_next <= float(data["spawn_max"]), "the first one comes in 2-5 min")
	var events: Array = []
	g.golden_spawned.connect(func() -> void: events.append("spawned"))
	g.golden_expired.connect(func() -> void: events.append("expired"))
	g.golden_finished.connect(func(success: bool, buff: Dictionary) -> void: events.append("hit" if success else "miss"))
	check(not g.claim_golden(), "nothing to claim before it glows")
	g.update_golden(g.golden_next - 1.0)
	check(events.is_empty() and g.golden_glow_left == 0.0, "not yet")
	g.update_golden(2.0)
	check(events == ["spawned"] and is_equal_approx(g.golden_glow_left, float(data["glow"])), "then it glows for 12 s")
	g.update_golden(float(data["glow"]) + 0.1)
	check(events == ["spawned", "expired"], "unclaimed, it goes away")
	check(g.golden_next >= float(data["spawn_min"]) and g.golden_next <= float(data["spawn_max"]), "...and the next one is 2-5 min off")
	# Claimed: 10 s to solve; no new sticker meanwhile; running out is a miss.
	g.update_golden(g.golden_next + 0.01)
	check(g.claim_golden() and is_equal_approx(g.golden_attempt_left, float(data["solve_seconds"])), "claiming starts a 10 s clock")
	check(not g.claim_golden(), "you can't claim it twice")
	g.update_golden(float(data["solve_seconds"]) + 0.1)
	check(events.back() == "miss" and g.golden_attempt_left == 0.0, "too slow is a miss")
	check(g.finish_golden(true).is_empty() and g.buff.is_empty(), "finishing after the clock ran out gives nothing")
	# In time: a buff (rolled by weight from the data).
	g.update_golden(g.golden_next + 0.01)
	g.claim_golden()
	g.update_golden(3.0)
	var result := g.finish_golden(true)
	check(events.back() == "hit" and String(result.get("id", "")) in ["frenzy", "lucky"], "in time: a buff (%s)" % result)
	var case_moves := g.roll_golden_case_moves()
	check(case_moves >= int(data["case_moves_min"]) and case_moves <= int(data["case_moves_max"]), "the case is 2-5 moves from solved")
	g.free()


func test_golden_buffs() -> void:
	var g := new_game()
	var frenzy: Dictionary = Content.GOLDEN["buffs"][0]
	var lucky: Dictionary = Content.GOLDEN["buffs"][1]
	g.add_moves_to("2x2", 4.0)
	var plain := g.total_moves
	var result := g._apply_golden_buff(frenzy)
	check_near(g.get_buff_mult(), float(frenzy["mult"]), "Frenzy: ×7 moves")
	check(result["text"] == "Frenzy: ×7 moves for 30s", "...and says so: %s" % result["text"])
	g.add_moves_to("2x2", 4.0)
	check_near(g.total_moves - plain, 4.0 * float(frenzy["mult"]), "every move counts 7 times")
	g.update_golden(float(frenzy["seconds"]) - 1.0)
	check(not g.buff.is_empty(), "it lasts 30 s")
	g.update_golden(1.1)
	check(g.buff.is_empty() and g.get_buff_mult() == 1.0, "then it's over")
	# Lucky: 15 minutes of Solves/s, at least 10 solves' worth.
	var before := g.solves
	result = g._apply_golden_buff(lucky)
	check_near(g.solves - before, float(lucky["min_solves_value"]) * g.get_solve_value(), "with no helpers: the minimum (10 solves' worth)")
	g.cheat_add_solves(1e4)
	g.buy_building("club")
	before = g.solves
	g._apply_golden_buff(lucky)
	check_near(g.solves - before, g.get_solves_per_second() * float(lucky["minutes"]) * 60.0, "with helpers: 15 minutes of Solves/s")
	# A buff survives save/load (it pauses while closed) and never counts for offline progress.
	g._apply_golden_buff(frenzy)
	g.buff["left"] = 12.5
	var next_before := g.golden_next
	var data := g.get_save_data()
	check(int(data["version"]) >= 6 and data["golden"]["buff"]["id"] == "frenzy", "the buff is saved (save v6)")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.buff.get("id", "") == "frenzy" and is_equal_approx(float(loaded.buff["left"]), 12.5), "it's still running after a load")
	check(is_equal_approx(loaded.golden_next, next_before), "and the next golden sticker keeps its time")
	var away_with := new_game()
	away_with.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]) + 3600.0)
	var no_buff: Dictionary = JSON.parse_string(JSON.stringify(data))
	no_buff["golden"]["buff"] = {}
	var away_without := new_game()
	away_without.apply_save_data(no_buff, float(data["saved_at"]) + 3600.0)
	check_near(away_with.total_moves, away_without.total_moves, "an hour away earns the same with or without a buff")
	check(is_equal_approx(float(away_with.buff["left"]), 12.5), "...and the buff waited (12.5 s left)")
	# v5 saves get a Golden Scramble timer.
	var v5 := data.duplicate(true)
	v5.erase("golden")
	v5["version"] = 5
	var migrated := new_game()
	migrated.apply_save_data(v5, float(data["saved_at"]))
	check(migrated.buff.is_empty() and is_equal_approx(migrated.golden_next, float(Content.GOLDEN["spawn_max"])), "a v5 save: no buff, first golden in 5 min")
	g.free()
	loaded.free()
	away_with.free()
	away_without.free()
	migrated.free()


func test_golden_scramble_on_screen() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	root.get_node("Settings").persistence_enabled = false
	game.cheat_add_solves(1000.0)
	game.unlock_puzzle("3x3")
	game.set_focus("3x3")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	var station: Node = main.get_node("%SolveStation")
	var button: Button = main.get_node("%GoldenButton")
	await process_frame
	game.golden_next = 0.0
	game.update_golden(0.01)
	main._refresh_golden()
	check(view.is_golden_shown() and button.visible, "a golden sticker glows on the cube and the button shows")
	# Clicking the golden sticker opens the case (a click elsewhere on the cube would just tap).
	var at := view.screen_position(view.golden_point())
	check(view.hits_golden(at), "the click lands on the golden sticker")
	var moves_before := game.total_moves
	view._gui_input(mouse_button(true, at))
	view._gui_input(mouse_button(false, at))
	check(station.visible and station.golden_mode and game.golden_attempt_left > 0.0, "it opens the 10 s case")
	check(is_equal_approx(game.total_moves, moves_before), "that click wasn't a tap")
	check(not view.is_golden_shown() and not button.visible, "the sticker is gone once claimed")
	var case_size: int = station.session.scramble.size()
	check(case_size >= 2 and case_size <= 5 and not station.session.model.is_solved(), "the case is a few moves from solved")
	# Solve it: the buff comes, and it's not a record.
	var count_before := game.get_hand_solve_count("3x3")
	var solves_before := game.solves
	for move in station.session.model.inverse_sequence(station.session.scramble):
		station.play_move(move)
	check(station.golden_result != "" and (not game.buff.is_empty() or game.solves > solves_before), "solving it in time gives a buff: %s" % station.golden_result)
	check(game.get_hand_solve_count("3x3") == count_before, "a golden case isn't a hand-solve record")
	station._process(float(station.GOLDEN_CLOSE_DELAY) + 0.1)  # untyped: SolveStation uses the autoloads by name
	check(_closed(station), "the station closes by itself after showing the buff")
	# Esc on a case is a miss.
	game.update_golden(game.golden_next + 0.01)
	main.open_golden()
	var missed := []
	game.golden_finished.connect(func(success: bool, _buff: Dictionary) -> void: missed.append(success), CONNECT_ONE_SHOT)
	station.handle_key(KEY_ESCAPE)
	check(missed == [false] and _closed(station), "Esc walks away from the case: a miss")
	main.free()
	game.reset_state()


# --- Hand-solve rewards (task S.3) -----------------------------------------------------

func test_hand_solve_tiers_and_flow() -> void:
	var g := new_game()
	var data: Dictionary = Content.SOLVE_REWARDS
	check(g.get_hand_tier("3x3", 400.0) == -1 and g.get_hand_tier("3x3", 300.0) == 0, "3×3: over 5:00 is no tier, 5:00 is Bronze")
	check(g.get_hand_tier("3x3", 89.0) == 2 and GameState.hand_tier_name(2) == "Gold", "1:29 is Gold")
	check(g.get_hand_tier("3x3", 24.0) == 5 and g.get_hand_tier("2x2", 5.0) == 5, "Master is the fastest target")
	for id: String in data["targets"]:
		var targets: Array = data["targets"][id]
		check(targets.size() == (data["tiers"] as Array).size(), "%s has a target per tier" % id)
		for i in range(1, targets.size()):
			check(float(targets[i]) < float(targets[i - 1]), "%s targets get faster" % id)
	for def: Dictionary in Content.PUZZLES:
		check((data["targets"] as Dictionary).has(def["id"]), "%s has time targets" % def["id"])
	# Flow: by the solve's tier, for max(2 min, 1.5 × the time); it multiplies every move.
	var tiers: Array = []
	g.hand_tier_reached.connect(func(id: String, tier: String) -> void: tiers.append([id, tier]))
	g.cheat_add_solves(1000.0)
	g.unlock_puzzle("3x3")
	var xp_before := g.get_mastery_xp("3x3")
	var info := g.record_hand_solve("3x3", 89.0, "", 60)
	check_near(g.get_flow_mult(), float(data["flow_by_tier"][3]), "a Gold solve: Gold's Flow")
	check_near(float(g.flow["left"]), 89.0 * 1.5, "Flow lasts 1.5 × the solve (2:13), at least 2 min")
	check(int(info["tier"]) == 2 and is_equal_approx(float(info["flow_mult"]), float(data["flow_by_tier"][3])), "the solve's info says so")
	g.add_moves_to("3x3", 1.0)
	var moves_before := g.total_moves
	var mult_before := g.get_puzzle_moves_mult("3x3")  # (the moves can level mastery up, which changes it)
	g.add_moves_to("3x3", 10.0)
	check_near(g.total_moves - moves_before, 10.0 * mult_before * float(data["flow_by_tier"][3]), "every move counts ×Flow")
	g.update_flow(200.0)
	check(g.flow.is_empty() and g.get_flow_mult() == 1.0, "then it runs out")
	g.record_hand_solve("3x3", 250.0, "", 60)
	check_near(g.get_flow_mult(), float(data["flow_by_tier"][1]), "a slower solve replaces it with its own Flow (Bronze's)")
	check_near(float(g.flow["left"]), 375.0, "...for 1.5 × 4:10")
	g.flow = {}
	g.record_hand_solve("3x3", 50.0, "DNF", 60)
	check(g.flow.is_empty(), "a DNF earns no Flow")
	g.record_hand_solve("3x3", 500.0, "", 60)
	check_near(g.get_flow_mult(), float(data["flow_by_tier"][0]), "even a solve under every target gives a little Flow (×1.5)")
	check_near(float(g.flow["left"]), 750.0, "...for 1.5 × its time")
	# Mastery XP: 10 idle solves' worth, ×5 for a PB single.
	var per_solve := float(data["xp_solves"]) * g.get_mastery_xp_per_solve("3x3")
	check(g.get_mastery_xp("3x3") >= xp_before + per_solve * float(data["xp_pb_factor"]), "the first (PB) solve gave ×5 XP")
	var xp := g.get_mastery_xp("3x3")
	g.record_hand_solve("3x3", 120.0, "", 60)
	check_near(g.get_mastery_xp("3x3") - xp, per_solve, "a non-PB solve gives 10 idle solves' XP")
	# The permanent bonus: +5 % moves per tier the PB single has reached; each new tier pops once.
	check(tiers == [["3x3", "Gold"]], "the first PB reached Gold (once): %s" % [tiers])
	check_near(g.get_hand_tier_mult("3x3"), 1.15, "Gold PB: +15 % moves on the 3×3")
	check_near(g.get_hand_tier_mult("2x2"), 1.0, "...and nothing on the 2×2")
	g.record_hand_solve("3x3", 39.0, "", 60)
	check(tiers.size() == 2 and tiers[1][1] == "Diamond" and is_equal_approx(g.get_hand_tier_mult("3x3"), 1.25), "a 39 s PB: Diamond, +25 %")
	# Flow isn't saved and never counts offline; the tier bonus comes back from the records.
	var saved := g.get_save_data()
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(saved)), float(saved["saved_at"]))
	check(loaded.flow.is_empty() and is_equal_approx(loaded.get_hand_tier_mult("3x3"), 1.25), "after a load: no Flow, the tier bonus stays")
	var away := new_game()
	g.record_hand_solve("3x3", 89.0, "", 60)
	away.flow = {"mult": 3.0, "left": 1e6, "tier": 5}
	away._offline_catch_up = true
	check(away.get_flow_mult() == 1.0, "Flow never counts for offline progress")
	g.free()
	loaded.free()
	away.free()


func test_hand_solve_rewards_on_screen() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	root.get_node("Settings").persistence_enabled = false
	game.cheat_add_solves(1000.0)
	game.unlock_puzzle("3x3")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var station: Node = main.get_node("%SolveStation")
	station.open("3x3")
	check((station.get_node("%TargetsLabel") as Label).text.contains("Gold 1:30"), "the records panel lists the targets")
	var info: Dictionary = game.record_hand_solve("3x3", 85.0, "", 60)
	station._refresh_records()
	check((station.get_node("%TargetsLabel") as Label).text.contains("✓ Gold"), "...and ticks the ones reached")
	var reward: String = station.reward_text(info)
	check(reward.contains("Gold: Flow ×%s" % Num.format(float(Content.SOLVE_REWARDS["flow_by_tier"][3]))) and reward.contains("new tier"), "after a solve: tier, Flow and the new tier: %s" % reward)
	station.close()
	main._refresh_golden()
	var flow_chip: StatChip = main.get_node("%FlowChip")
	check(flow_chip.visible and flow_chip.get_text().begins_with("×%s " % Num.format(float(Content.SOLVE_REWARDS["flow_by_tier"][3]))),
			"the top bar shows the Flow: %s" % flow_chip.get_text())
	main.free()
	game.reset_state()


# --- Algorithm drills (task S.4) -------------------------------------------------------

## The case an algorithm solves: a solved 3×3 with the algorithm undone (then U^before ... U^after around it), read
## relative to the centres (so rotations inside an algorithm, like the V perm's y, don't matter).
func _alg_case_code(alg: String, kind: String, before: int, after: int) -> int:
	var m := PuzzleShapes.from_id("3x3")
	var u := m.face_names.find("U")
	m.apply(m.make_move(u, before))
	m.apply_all(m.inverse_sequence(m.parse_sequence(alg)))
	m.apply(m.make_move(u, after))
	var run = StagedSolver._Run.new(StagedSolver._shape(3), m)
	return run._project(kind, run.u_corners, run.u_edges, run._tracked_slots(run.u_corners, run.u_edges))


func test_full_oll_pll_data() -> void:
	var oll_cases := {}
	var pll_cases := {}
	var oll_count := 0
	var pll_count := 0
	for alg: Dictionary in Content.ALGORITHMS:
		if not alg.get("full", false):
			continue
		var m := PuzzleShapes.from_id("3x3")
		m.apply_all(m.parse_sequence(alg["alg"]))
		var keeps := StagedSolver.is_stage_done(m, "second_layer")
		check(keeps, "%s keeps the first two layers (relative to the centres): %s" % [alg["name"], alg["alg"]])
		if alg["set"] == "OLL":
			oll_count += 1
			var best := -1
			for k in 4:  # the same case seen from any side is one case
				var code := _alg_case_code(alg["alg"], "orient", 0, k)
				best = code if best < 0 else mini(best, code)
			check(best != 0, "%s's case isn't already oriented" % alg["name"])
			check(not oll_cases.has(best), "%s is a different case from %s" % [alg["name"], oll_cases.get(best, "")])
			oll_cases[best] = alg["name"]
		else:
			pll_count += 1
			check(StagedSolver.is_stage_done(m, "oll"), "%s keeps the top oriented" % alg["name"])
			var best := -1
			for a in 4:
				for b in 4:
					var code := _alg_case_code(alg["alg"], "full", a, b)
					best = code if best < 0 else mini(best, code)
			var solved_code := _alg_case_code("", "full", 0, 0)
			check(best != solved_code, "%s's case isn't already solved" % alg["name"])
			check(not pll_cases.has(best), "%s is a different case from %s" % [alg["name"], pll_cases.get(best, "")])
			pll_cases[best] = alg["name"]
	check(oll_count == 57 and oll_cases.size() == 57, "57 OLL algorithms for 57 different cases (%d, %d)" % [oll_count, oll_cases.size()])
	check(pll_count == 21 and pll_cases.size() == 21, "21 PLL algorithms for 21 different cases (%d, %d)" % [pll_count, pll_cases.size()])


func test_drill_rules() -> void:
	var g := new_game()
	var target := float(Content.get_drill_set("2look_pll")["target"])
	var needed := int(Content.DRILLS["clean_needed"])
	var learned: Array = []
	var sets: Array = []
	g.drill_case_learned.connect(func(id: String) -> void: learned.append(id))
	g.drill_set_learned.connect(func(id: String) -> void: sets.append(id))
	var r := g.record_drill("2look_pll", "pll_t", target + 5.0)
	check(r["pb"] and not r["clean"] and int(r["clean_count"]) == 0, "a slow first try: a PB, not clean")
	r = g.record_drill("2look_pll", "pll_t", target - 1.0)
	check(r["pb"] and r["clean"] and int(r["clean_count"]) == 1, "under the target: clean")
	r = g.record_drill("2look_pll", "pll_t", target - 0.5)
	check(not r["pb"] and r["clean"], "slower than the best but still clean")
	for i in needed - 2:
		r = g.record_drill("2look_pll", "pll_t", target - 1.0)
	check(r["learned_now"] and g.is_case_learned("pll_t") and learned == ["pll_t"], "%d clean solves learn the case (once)" % needed)
	g.record_drill("2look_pll", "pll_t", target - 1.0)
	check(learned.size() == 1, "...and it's only learned once")
	check_near(float(g.get_drill_record("pll_t")["best"]), target - 1.0, "best time kept")
	var cases := Content.get_drill_cases("2look_pll")
	check(cases.size() == 8 and Content.get_drill_cases("pll").size() == 21 and Content.get_drill_cases("oll").size() == 57,
			"sets: 2-look PLL 8, full PLL 21, full OLL 57")
	check(Content.get_drill_cases("2look_oll").size() == 9, "2-look OLL: 2 edge + 7 corner cases")
	check(g.get_drill_set_progress("2look_pll") == {"learned": 1, "total": 8}, "1 of 8 learned")
	for alg in cases:
		for i in needed:
			g.record_drill("2look_pll", alg["id"], 1.0)
	check(g.is_drill_set_learned("2look_pll") and sets == ["2look_pll"], "every case learned: the set is learned")
	check(g.get_drill_set_progress("pll")["learned"] == 8, "the 2-look cases count for full PLL too")
	check(g.record_drill("nope", "pll_t", 1.0).is_empty() and g.record_drill("pll", "nope", 1.0).is_empty(), "unknown set or case: nothing")
	# Saved (v7); a v6 save has none.
	var data := g.get_save_data()
	check(int(data["version"]) >= 7 and data["drills"].has("pll_t"), "drill records are saved (v7)")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.is_drill_set_learned("2look_pll") and is_equal_approx(float(loaded.get_drill_record("pll_t")["best"]), 1.0), "and load back")
	var v6: Dictionary = data.duplicate(true)
	v6.erase("drills")
	v6["version"] = 6
	var migrated := new_game()
	migrated.apply_save_data(v6, float(data["saved_at"]))
	check(migrated.drills.is_empty() and int(migrated.get_save_data()["version"]) >= 7, "a v6 save gets empty drills")
	g.free()
	loaded.free()
	migrated.free()


## Every drill case is the right case: its own algorithm (with U turns before/after) solves it, and yellow is on top.
func test_drill_cases() -> void:
	var session := SolveSession.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bad: Array = []
	for alg: Dictionary in Content.ALGORITHMS:
		if alg["set"] == "Beginner":
			continue
		session.start_drill(alg["alg"], 0.0, rng)
		check(session.state == "solving" and not session.model.is_solved(), "%s: a case, the clock running" % alg["name"])
		var solved := false
		for a in 4:
			for b in 4:
				var m := PuzzleShapes.from_id("3x3")
				m.orientations = session.model.orientations.duplicate()
				var u := m.face_names.find("U")
				m.apply(m.make_move(u, a))
				m.apply_all(m.parse_sequence(alg["alg"]))
				m.apply(m.make_move(u, b))
				solved = solved or m.is_solved()
		if not solved:
			bad.append(alg["name"])
	check(bad.is_empty(), "every case is solved by its own algorithm plus AUF (not: %s)" % [bad])
	session.start_drill("R U R' U R U2 R'", 0.0, rng)
	check(session.model.color_at(Vector3(0, 1, 0), session.model.face_names.find("U")) == PuzzleShapes.COLOR_YELLOW, "yellow on top, like cubers drill")
	for move in session.model.inverse_sequence(session.scramble):
		session.turn(move, 4.25)
	check(session.state == "done" and is_equal_approx(session.elapsed(4.25), 4.25), "the clock ran from the case appearing to solved")


func test_drill_station_and_showcase() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	root.get_node("Settings").persistence_enabled = false
	game.cheat_add_solves(1000.0)
	game.unlock_puzzle("3x3")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var station: Node = main.get_node("%SolveStation")
	station.open("3x3")
	station.frozen_now = 100.0
	(station.get_node("%DrillsToggle") as Button).toggled.emit(true)
	check(station.drill_mode and station.get_node("%PuzzlePicker").get_child_count() == Content.DRILLS["sets"].size(), "Drills: the picker shows the sets")
	station.select_drill_set("2look_pll")
	var case_name: String = station.drill_case["name"]
	check(station.session.state == "solving" and not (station.get_node("%StatusLabel") as Label).text.contains(case_name), "the case's name stays hidden while you solve")
	station.frozen_now = 104.0
	var count_before := game.get_hand_solve_count("3x3")
	for move in station.session.model.inverse_sequence(station.session.scramble):
		station.play_move(move)
	check(int(game.get_drill_record(station.drill_case["id"])["count"]) == 1, "solving it records the drill")
	check(game.get_hand_solve_count("3x3") == count_before, "drills aren't hand-solve records")
	var status := (station.get_node("%StatusLabel") as Label).text
	check(status.contains(case_name) and status.contains(String(station.drill_case["alg"])) and status.contains("clean 1/5"), "then it names the case and its algorithm: %s" % status)
	check(station.get_node("%TimesRows").get_child_count() == 8, "the side panel lists the set's 8 cases")
	station.handle_key(KEY_ENTER)
	check(station.session.state == "solving", "Enter: the next case")
	(station.get_node("%DrillsToggle") as Button).toggled.emit(false)
	check(not station.drill_mode and station.session.state != "solving", "Drills off: back to normal solves")
	station.close()
	# Learning full PLL puts it in the team's showcase solves.
	check(main._solver_options().is_empty(), "nothing learned: two-look in the showcase")
	for alg in Content.get_drill_cases("pll"):
		for i in int(Content.DRILLS["clean_needed"]):
			game.record_drill("pll", alg["id"], 1.0)
	check(main._solver_options() == {"full_pll": true} and main._showcase.solver_options == {"full_pll": true}, "full PLL learned: one-look PLL in the showcase")
	main.free()
	game.reset_state()


# --- Daily scramble and FMC (task S.5) -------------------------------------------------

func test_daily_scramble_rules() -> void:
	# The seed comes from the date and puzzle only (FNV-1a), so everyone gets the same scramble that day.
	check(GameState.daily_seed("2026-11-04", "3x3") == GameState.daily_seed("2026-11-04", "3x3"), "same day, same seed")
	check(GameState.daily_seed("2026-11-04", "3x3") != GameState.daily_seed("2026-11-05", "3x3"), "another day, another seed")
	check(GameState.daily_seed("2026-11-04", "3x3") != GameState.daily_seed("2026-11-04", "2x2"), "another puzzle, another seed")
	check(GameState.daily_seed("2026-11-04", "3x3") == 2657919017, "the seed is fixed forever (FNV-1a, checked against Python; not the engine's hash): %d" % GameState.daily_seed("2026-11-04", "3x3"))
	var scrambles := []
	for i in 2:
		var session := SolveSession.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = GameState.daily_seed("2026-11-04", "3x3")
		session.start("3x3", 0.0, rng)
		scrambles.append(session.scramble_text())
	check(scrambles[0] == scrambles[1], "the same seed makes the same scramble: %s" % scrambles[0])
	var g := new_game()
	g.daily_now = 1793750400.0  # 2026-11-04 00:00 UTC
	check(g.get_daily_date() == "2026-11-04", "the date is UTC: %s" % g.get_daily_date())
	g.daily_now += 86399.0
	check(g.get_daily_date() == "2026-11-04", "...all day")
	# Records and the once-a-day reward.
	check(g.is_daily_reward_ready(), "a reward is waiting")
	var r := g.record_daily("3x3", "time", INF)
	check(r["reward"] == 0.0 and g.is_daily_reward_ready(), "a DNF doesn't collect it")
	var before := g.solves
	r = g.record_daily("3x3", "fmc", 45.0)
	var expected := float(Content.DAILY["min_solves_value"]) * g.get_solve_value()
	check_near(float(r["reward"]), expected, "the first finished daily pays (no helpers: 50 solves' worth)")
	check_near(g.solves - before, expected, "...into Solves")
	check(not g.is_daily_reward_ready(), "...once")
	r = g.record_daily("3x3", "fmc", 38.0)
	check(r["reward"] == 0.0 and r["pb_today"] and is_equal_approx(float(r["best"]), 38.0), "a better FMC is today's best, no second reward")
	r = g.record_daily("3x3", "fmc", 41.0)
	check(not r["pb_today"] and is_equal_approx(float(r["best"]), 38.0), "a worse one isn't")
	g.record_daily("3x3", "time", 63.5)
	check(is_equal_approx(float(g.get_daily()["times"]["3x3"]), 63.5), "today's best time")
	# A new day: fresh results and reward; the best FMC ever stays. Saved (v8).
	var data := g.get_save_data()
	check(int(data["version"]) >= 8 and data["daily"]["fmc"]["3x3"] == 38.0, "saved (v8)")
	g.daily_now += 10.0  # 2026-11-05
	check(g.get_daily()["date"] == "2026-11-05" and g.is_daily_reward_ready() and g.get_daily()["fmc"].is_empty(), "the next day starts fresh")
	check(is_equal_approx(float(g.get_daily()["fmc_ever"]["3x3"]), 38.0), "...but the best FMC ever stays")
	var loaded := new_game()
	loaded.daily_now = 1793750400.0
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(not loaded.is_daily_reward_ready() and is_equal_approx(float(loaded.get_daily()["fmc"]["3x3"]), 38.0), "a load keeps today's results")
	var v7: Dictionary = data.duplicate(true)
	v7.erase("daily")
	v7["version"] = 7
	var migrated := new_game()
	migrated.apply_save_data(v7, float(data["saved_at"]))
	check(migrated.is_daily_reward_ready() and int(migrated.get_save_data()["version"]) >= 8, "a v7 save gets an empty daily")
	g.free()
	loaded.free()
	migrated.free()


func test_daily_in_station() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.daily_now = 1793750400.0
	var settings: Node = root.get_node("Settings")
	settings.persistence_enabled = false
	settings.set_value("inspection", false)
	game.cheat_add_solves(1000.0)
	game.unlock_puzzle("3x3")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var station: Node = main.get_node("%SolveStation")
	station.open("3x3")
	station.frozen_now = 50.0
	(station.get_node("%DailyToggle") as Button).toggled.emit(true)
	var daily_scramble: String = station.session.scramble_text()
	check(station.daily_mode and (station.get_node("%FmcToggle") as Button).visible, "Daily on: today's scramble, and an FMC toggle")
	check((station.get_node("%ScrambleLabel") as Label).text.contains("Daily 2026-11-04"), "the label names the day")
	station.handle_key(KEY_ENTER)
	check(station.session.scramble_text() == daily_scramble, "Enter gives the same scramble again (it's the day's)")
	# FMC: count moves, Backspace starts over, solving records the moves and pays the day's reward.
	(station.get_node("%FmcToggle") as Button).toggled.emit(true)
	check(station.fmc_mode and station.session.scramble_text() == daily_scramble, "FMC uses the same scramble")
	var solution: Array = station.session.model.inverse_sequence(station.session.scramble)
	station.play_move(solution[0])
	check((station.get_node("%TimerLabel") as Label).text == "1 moves", "the big number counts moves")
	station.handle_key(KEY_BACKSPACE)
	check(station.session.moves == 0 and station.session.scramble_text() == daily_scramble, "Backspace starts over, no moves counted")
	var count_before := game.get_hand_solve_count("3x3")
	var solves_before := game.solves
	for move in solution:
		station.play_move(move)
	check(station.session.state == "done" and is_equal_approx(float(game.get_daily()["fmc"]["3x3"]), float(solution.size())), "FMC records the move count")
	check(game.solves > solves_before and not game.is_daily_reward_ready(), "the day's reward is paid")
	check(game.get_hand_solve_count("3x3") == count_before, "an FMC isn't a timed record")
	check((station.get_node("%StatusLabel") as Label).text.contains("daily reward"), "and says so")
	# Timed daily: also a normal hand solve.
	(station.get_node("%FmcToggle") as Button).toggled.emit(false)
	station.frozen_now = 60.0
	var timed: Array = station.session.model.inverse_sequence(station.session.scramble)
	station.play_move(timed[0])  # the clock starts...
	station.frozen_now = 121.4   # ...and stops a minute later
	for move in timed.slice(1):
		station.play_move(move)
	check(game.get_hand_solve_count("3x3") == count_before + 1 and game.get_daily()["times"].has("3x3"), "a timed daily is a record and today's time")
	(station.get_node("%DailyToggle") as Button).toggled.emit(false)
	check(not station.daily_mode and station.session.scramble_text() != daily_scramble, "Daily off: random scrambles again")
	station.close()
	main.free()
	settings.set_value("inspection", true)
	game.daily_now = -1.0
	game.reset_state()


# --- Generated helper milestones (task 5.2) --------------------------------------------

func test_helper_milestones() -> void:
	var all := Content.get_upgrades()
	check(all.size() == Content.UPGRADES.size() + Content.BUILDINGS.size() * Content.HELPER_MILESTONES.size(),
			"every helper gets every milestone (%d upgrades)" % all.size())
	for helper: Dictionary in Content.BUILDINGS:
		var previous_cost := 0.0
		for row: Dictionary in Content.HELPER_MILESTONES:
			var def := Content.get_upgrade("ms_%s_%d" % [helper["id"], row["owned"]])
			check(not def.is_empty(), "%s has a milestone at %d" % [helper["id"], row["owned"]])
			if def.is_empty():
				continue
			check(def["effect"]["type"] in Content.EFFECT_TYPES and def["effect"]["target"] == helper["id"], "%s: boosts that helper" % def["name"])
			check_near(float(def["effect"]["value"]), float(row["mult"]), "%s: ×%s" % [def["name"], row["mult"]])
			check(int(def["requires"][helper["id"]]) == int(row["owned"]), "%s: needs %d" % [def["name"], row["owned"]])
			check(float(def["cost"]) > previous_cost, "%s costs more than the last one" % def["name"])
			check(def["icon"] == helper["icon"], "%s uses the helper's icon" % def["name"])
			previous_cost = float(def["cost"])
	# In play: a milestone appears once you own enough, and doubles that helper.
	var g := new_game()
	g.buy_building("friend")  # free
	var id := "ms_friend_1"
	var cost := float(Content.get_upgrade(id)["cost"])
	g.cheat_add_solves(cost)
	check(g.is_upgrade_available(id), "Practice Partners I shows up with 1 Friend")
	check(not g.is_upgrade_available("ms_friend_10"), "...III needs 10")
	var before := g.get_building_mps("friend")
	check(g.buy_upgrade(id) and is_equal_approx(g.get_building_mps("friend"), before * 2.0), "and doubles Friends")
	check(not g.is_upgrade_available(id), "once")
	g.free()
	# A helper added to the data gets its milestones by itself (the generator only reads BUILDINGS + the table).
	var fake := {"id": "test_helper", "icon": "friend", "name": "Test Helper", "milestone_name": "Testing", "base_cost": 100}
	var made := Content.milestones_for(fake)
	check(made.size() == Content.HELPER_MILESTONES.size() and made[0]["id"] == "ms_test_helper_1" and made[0]["name"] == "Testing I",
			"a new helper gets its milestones from the table: %s" % [made.map(func(d: Dictionary) -> String: return d["name"])])
	check(made[-1]["requires"] == {"test_helper": 200} and is_equal_approx(float(made[1]["cost"]), 100.0 * float(Content.HELPER_MILESTONES[1]["cost_mult"])),
			"...with the table's thresholds and costs")


# --- Synergies and solve value (task 5.3) -----------------------------------------------

func test_synergies_and_solve_value() -> void:
	var g := new_game()
	g.cheat_add_solves(1e12)
	g.buy_building("friend")
	g.buy_buildings("club", 5)
	var friend_before := g.get_building_mps("friend")
	var club_before := g.get_building_mps("club")
	check(g.is_upgrade_available("club_coaching"), "Club Coaching shows up with 5 Clubs")
	g.buy_upgrade("club_coaching")
	var per_club := float(Content.get_upgrade("club_coaching")["effect"]["value"])
	check_near(g.get_building_mps("friend"), friend_before * (1.0 + per_club * 5), "synergy: each of 5 Clubs makes each Friend faster")
	check_near(g.get_building_mps("club"), club_before, "...and leave the Clubs alone")
	g.buy_buildings("club", 5)
	check_near(g.get_building_mps("friend"), friend_before * (1.0 + per_club * 10), "it grows with every Club (10 Clubs: twice the bonus)")
	g.buy_buildings("robot", 5)
	var club_mps := g.get_building_mps("club")
	g.buy_upgrade("robot_sparring")
	check_near(g.get_building_mps("club"), club_mps * 1.10, "Robot Sparring: 5 Robots → Clubs +10 %")
	# Solve value: Sponsorship ×1.5, Prize Money ×2, multiplied together.
	var value := g.get_solve_value("2x2")
	g.buy_building("competition")
	check(g.buy_upgrade("sponsorship"), "Sponsorship needs a Local Competition")
	check_near(g.get_solve_value("2x2"), value * 1.5, "every solve pays 50 % more")
	g.buy_buildings("competition", 19)
	g.buy_upgrade("prize_money")
	check_near(g.get_solve_value("2x2"), value * 3.0, "Prize Money doubles it again (×3 in all)")
	for def: Dictionary in Content.UPGRADES:
		var effect: Dictionary = def["effect"]
		if effect["type"] == "synergy":
			check(Content.get_building(effect["target"]).size() > 0 and Content.get_building(effect["source"]).size() > 0,
					"%s links two real helpers" % def["id"])
			check(float(effect["value"]) > 0.0 and float(effect["value"]) < 0.1, "%s is a small per-copy bonus" % def["id"])
	g.free()


# --- Six more helpers (task 5.5) ---------------------------------------------------------

# Task 5.8: the upgrade cache must not survive a swap of one owned upgrade for another (the same count). The balance
# bot tries upgrades on one at a time; before 5.8 every trial after the first reused the first one's numbers.
func test_upgrade_cache_swaps() -> void:
	var g := new_game()
	var taps := g.get_tap_moves()
	var friend := g.get_building_mps("friend")
	g.upgrades["lube"] = true
	g.invalidate_upgrade_cache()
	check_near(g.get_tap_moves(), taps * 2.0, "trying Cube Lube on: taps ×2")
	g.upgrades.erase("lube")
	g.upgrades["stackmat"] = true  # same count, another upgrade
	g.invalidate_upgrade_cache()
	check_near(g.get_tap_moves(), taps, "swapped for Stackmat Timer: taps back to normal")
	check_near(g.get_building_mps("friend"), friend * 2.0, "...and Friends ×2")
	g.upgrades.erase("stackmat")
	g.invalidate_upgrade_cache()
	# Buying, a reset and a load drop the cache by themselves.
	g.cheat_add_solves(100.0)
	check(g.buy_upgrade("lube") and is_equal_approx(g.get_tap_moves(), taps * 2.0), "buying drops the cache")
	var data := g.get_save_data()
	var other := new_game()
	other.upgrades["stackmat"] = true  # one owned upgrade before the load, one in the save
	other.invalidate_upgrade_cache()
	check_near(other.get_tap_moves(), taps, "before the load: Stackmat only")
	other.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check_near(other.get_tap_moves(), taps * 2.0, "after loading a save with Cube Lube: taps ×2")
	g.reset_state()
	check_near(g.get_tap_moves(), taps, "a reset drops it too")
	# The balance bot values each upgrade on its own (the never-tapping bot used to value them all like Cube Lube: 0).
	var sim: RefCounted = load("res://tools/simulator.gd").new()
	var idle := new_game()
	idle.buildings["friend"] = 7
	var base: float = sim.income(idle, 0.0)
	var lube_gain: float = sim._income_gain(idle, {"kind": "upgrade", "id": "lube"}, 0.0, base)
	var partners_gain: float = sim._income_gain(idle, {"kind": "upgrade", "id": "ms_friend_1"}, 0.0, base)
	check(is_zero_approx(lube_gain) and is_equal_approx(partners_gain, base), "the bot: Lube gains nothing idle, Practice Partners I doubles it")
	idle.free()
	other.free()
	g.free()


func test_helper_ladder() -> void:
	check(Content.BUILDINGS.size() == 12, "12 helpers, Friend to Quantum Solver")
	for i in range(1, Content.BUILDINGS.size()):
		var a: Dictionary = Content.BUILDINGS[i - 1]
		var b: Dictionary = Content.BUILDINGS[i]
		check(float(b["base_cost"]) > float(a["base_cost"]) * 5.0 and float(b["mps"]) > float(a["mps"]), "%s costs and makes more than %s" % [b["name"], a["name"]])
		if i >= 6:  # the six past the Lab (5.5): each a bit less efficient per Solve than the one before
			check(float(b["mps"]) / float(b["base_cost"]) < float(a["mps"]) / float(a["base_cost"]), "%s is a bit less efficient per Solve" % b["name"])
		check(b.has("milestone_name") and (Content.NEWS["who"] as Dictionary).has(b["id"]), "%s has milestone names and a news title" % b["name"])
	check(float(Content.BUILDINGS.back()["base_cost"]) >= 1e13, "the top helper costs 10T+ (copies pass 1e15)")


# --- Algorithm Lab (task 5.6) -----------------------------------------------------------

func test_lab_research() -> void:
	var g := new_game()
	var events: Array = []
	g.research_started.connect(func(id: String) -> void: events.append("start " + id))
	g.research_finished.connect(func(id: String) -> void: events.append("done " + id))
	check(not g.is_research_visible("finger_tricks") and not g.start_research("finger_tricks"), "nothing in reach at the start")
	g.cheat_add_solves(1e4)
	var taps := g.get_tap_moves()
	check(g.start_research("finger_tricks") and is_equal_approx(g.solves, 1e4 - 500.0), "Finger Tricks: paid when it starts")
	check(not g.can_start_research("two_look_oll"), "one project at a time")
	check_near(g.get_tap_moves(), taps, "no effect while it's being researched")
	g.update_research(60.0)
	check_near(float(g.get_research_progress()["fraction"]), 0.5, "half way after half its time")
	g.update_research(61.0)
	check(g.is_research_done("finger_tricks") and g.research.is_empty() and events == ["start finger_tricks", "done finger_tricks"], "done after 2 minutes")
	check_near(g.get_tap_moves(), taps * 2.0, "then taps count ×2")
	check(not g.is_research_visible("finger_tricks"), "a done project can't be researched again")
	check(not g.is_research_visible("full_pll"), "Full PLL needs 2-look PLL first")
	# Methods are projects too.
	g.cheat_add_solves(1e6)
	check(g.buy_method("cfop") and g.research["id"] == "method_cfop" and not g.is_method_learned("cfop"), "buying CFOP starts its research")
	g.update_research(float(Content.get_method("cfop")["research_seconds"]))
	check(g.is_method_learned("cfop") and g.is_research_done("method_cfop"), "...and learns it when done")
	# Drill sets count as research: learning 2-look OLL in the Solve Station finishes the project for free.
	var solves_before := g.solves
	for alg in Content.get_drill_cases("2look_oll"):
		for i in int(Content.DRILLS["clean_needed"]):
			g.record_drill("2look_oll", alg["id"], 1.0)
	check(g.is_research_done("two_look_oll") and is_equal_approx(g.solves, solves_before), "learning 2-look OLL in drills finishes its Lab project, free")
	# ...even while it's the project running: it finishes, and the Lab is free again.
	check(g.start_research("two_look_pll") and g.research["id"] == "two_look_pll", "start 2-look PLL")
	for alg in Content.get_drill_cases("2look_pll"):
		for i in int(Content.DRILLS["clean_needed"]):
			g.record_drill("2look_pll", alg["id"], 1.0)
	check(g.is_research_done("two_look_pll") and g.research.is_empty(), "drilling the running project's set finishes it and frees the Lab")
	g.free()


func test_lab_goals() -> void:
	var g := new_game()
	g.cheat_add_solves(1e4)
	var kinds := func() -> Array:
		var found: Array = []
		for goal in g.get_goals(10):
			found.append(goal["kind"])
		return found
	check(kinds.call().has("method") and not kinds.call().has("research"), "the next method is a goal")
	g.buy_method("cfop")
	check(not kinds.call().has("method") and g.get_next_goal().get("kind", "") != "method", "...but not while it's being researched")
	var running: Dictionary = {}
	for goal in g.get_goals(10):
		if goal["kind"] == "research":
			running = goal
	check(not running.is_empty() and running["name"] == "Research CFOP" and running["unit"] == "time"
			and is_equal_approx(float(running["seconds"]), float(Content.get_method("cfop")["research_seconds"])), "the research is a goal, with its time left")
	g.free()


func test_choices() -> void:
	var g := new_game()
	g.cheat_add_solves(1e12)
	check(g.is_upgrade_available("speed_practice") and g.is_upgrade_available("efficient_solving"), "both sides of a choice are on offer")
	check(g.get_choice_partners("speed_practice") == ["efficient_solving"] and g.get_choice_partners("lube").is_empty(), "partners")
	check(g._goal_name(Content.get_upgrade("efficient_solving")) == "Efficient Solving or Speed Practice"
			and g._goal_name(Content.get_upgrade("lube")) == "Cube Lube", "goal names")
	var taps := g.get_tap_moves()
	check(g.buy_upgrade("speed_practice") and is_equal_approx(g.get_tap_moves(), taps * 3.0), "Speed Practice: taps ×3")
	check(g.get_choice_pick("practice") == "speed_practice", "it's the pick of its group")
	check(g.is_upgrade_locked_out("efficient_solving") and not g.is_upgrade_available("efficient_solving"), "the other side is locked out")
	var goal_ids: Array = []
	for goal in g.get_goals(20):
		goal_ids.append(goal["id"])
	check(not goal_ids.has("efficient_solving") and g.get_next_goal().get("id", "") != "efficient_solving", "...and is never a goal")
	var solves := g.solves
	check(not g.buy_upgrade("efficient_solving") and is_equal_approx(g.solves, solves), "...and can't be bought")
	check(not g.is_upgrade_locked_out("speed_practice"), "the pick itself isn't locked out")
	# Effects: specialists boost only their puzzles; Deliberate Practice multiplies mastery XP.
	g._add_puzzle("4x4")
	var small := g.get_puzzle_moves_mult("3x3")
	var big := g.get_puzzle_moves_mult("4x4")
	check(g.buy_upgrade("big_cubes") and is_equal_approx(g.get_puzzle_moves_mult("4x4"), big * 1.5)
			and is_equal_approx(g.get_puzzle_moves_mult("3x3"), small), "Big-Cube Specialist: ×1.5 on 4×4, nothing on 3×3")
	check(g.is_upgrade_locked_out("small_cubes"), "...and Small-Cube Specialist is locked out")
	var other := new_game()
	other.cheat_add_solves(1e9)
	other._add_puzzle("4x4")
	var small_taps := other.get_puzzle_moves_mult("3x3")
	var big_other := other.get_puzzle_moves_mult("4x4")
	var before := other.total_moves
	other.tap()
	var tap_before := other.total_moves - before
	check(other.buy_upgrade("small_cubes") and is_equal_approx(other.get_puzzle_moves_mult("3x3"), small_taps * 2.0)
			and is_equal_approx(other.get_puzzle_moves_mult("4x4"), big_other), "Small-Cube Specialist: ×2 on 3×3, nothing on 4×4")
	before = other.total_moves
	other.tap()  # the focused puzzle is the 2×2
	check(is_equal_approx(other.total_moves - before, tap_before * 2.0), "...and it doubles taps on the 2×2 too")
	other.free()
	var xp := g.get_mastery_xp_per_solve("3x3")
	check(g.buy_upgrade("mastery_focus") and is_equal_approx(g.get_mastery_xp_per_solve("3x3"), xp * 3.0), "Deliberate Practice: ×3 mastery XP")
	# Saved and loaded with the run; a damaged save with both sides keeps only one.
	var data := g.get_save_data()
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.upgrades.has("speed_practice") and loaded.is_upgrade_locked_out("efficient_solving"), "the choice survives save/load")
	data["upgrades"] = ["efficient_solving", "speed_practice"]
	loaded.apply_save_data(data, float(data["saved_at"]))
	check(loaded.upgrades.has("efficient_solving") and not loaded.upgrades.has("speed_practice"), "a damaged save with both sides keeps one")
	# A new run (a championship resets upgrades, 6.2; reset_state for now) opens the choice again.
	g.reset_state()
	g.cheat_add_solves(1e4)
	check(g.is_upgrade_available("speed_practice") and g.is_upgrade_available("efficient_solving"), "a new run: choose again")
	g.free()
	loaded.free()


func test_choice_tiles() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	game.cheat_add_solves(1000)
	main._refresh()
	var speed: UpgradeTile = main._upgrade_tiles["speed_practice"]
	var efficient: UpgradeTile = main._upgrade_tiles["efficient_solving"]
	check(speed.visible and efficient.visible and speed._badge.visible and speed._badge.text == "PICK 1", "a pair shows with PICK 1 badges")
	check(speed._choice.contains("Efficient Solving"), "the tooltip names the other side")
	check(not main._upgrade_tiles["lube"]._badge.visible, "ordinary upgrades have no badge")
	speed.pressed.emit()
	main._refresh()
	check(game.upgrades.has("speed_practice") and speed._badge.text == "PICKED", "picking one")
	check(efficient.visible and efficient.locked_out and efficient.disabled and efficient._badge.text == "NOT PICKED",
			"the other side stays visible, greyed out")
	check(efficient.get_index() == speed.get_index() + 1, "next to its pick")
	check(efficient._choice == "You picked Speed Practice this run. A championship lets you choose again.", "the other side's tooltip says what you picked")
	var tabs: TabContainer = main.get_node("%Tabs")
	game.solves = 0.0
	main._refresh()
	check(main.get_tab_count(main.UPGRADES_TAB) == 0, "a locked-out side never counts as affordable")
	main.free()
	game.reset_state()


func test_lab_content() -> void:
	var ids := {}
	for def: Dictionary in Content.get_lab_projects():
		var id: String = def["id"]
		check(not ids.has(id), "Lab project %s: unique id" % id)
		check(FileAccess.file_exists("res://assets/icons/%s.svg" % def["icon"]), "Lab project %s: its icon exists" % id)
		check(float(def["cost"]) > 0.0 and float(def["seconds"]) > 0.0 and float(def["seconds"]) <= GameState.MAX_OFFLINE_SECONDS,
				"Lab project %s: a cost and a time (at most the offline cap)" % id)
		check(String(def.get("topic", "")) != "", "Lab project %s: a topic" % id)
		if def["kind"] == "research":
			check(Content.EFFECT_TYPES.has(def["effect"]["type"]), "Lab project %s: a known effect type" % id)
			if def.has("drill_set"):
				check(not Content.get_drill_set(def["drill_set"]).is_empty(), "Lab project %s: its drill set exists" % id)
		for need: String in def.get("requires", []):
			check(ids.has(need), "Lab project %s: requires %s, listed before it" % [id, need])
		ids[id] = true


func test_num_clock() -> void:
	check(Num.clock(32.0) == "0:32" and Num.clock(240.0) == "4:00" and Num.clock(3723.0) == "1:02:03", "clock: m:ss, h:mm:ss")
	check(Num.clock(0.2) == "0:01" and Num.clock(0.0) == "0:00" and Num.clock(-5.0) == "0:00", "clock: rounds up, never negative")


func test_lab_offline_and_saves() -> void:
	var g := new_game()
	g.cheat_add_solves(1e8)
	g.start_research("finger_tricks")
	g.update_research(30.0)
	var data := g.get_save_data()
	check(int(data["version"]) >= 9 and data["lab"]["current"]["id"] == "finger_tricks", "the running project is saved (v9)")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.research.get("id", "") == "finger_tricks" and is_equal_approx(float(loaded.research["left"]), 90.0), "it loads mid-research (90 s left)")
	# Away long enough: it finishes while the game is closed, and the welcome-back report says so.
	var away := new_game()
	away.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]) + 600.0)
	check(away.is_research_done("finger_tricks") and away.research.is_empty(), "10 minutes away: the research finished offline")
	check(away.offline_report.get("research", "") == "Finger Tricks", "and the welcome back report names it")
	# Time away counts down a long project; a damaged save can't claim more time left than the project takes.
	var slow := new_game()
	slow.cheat_add_solves(1e12)
	slow.research_done["two_look_oll"] = true
	slow.invalidate_upgrade_cache()
	slow.research = {"id": "full_oll", "left": 3.0 * 3600.0}
	var slow_data := slow.get_save_data()
	var later := new_game()
	later.apply_save_data(JSON.parse_string(JSON.stringify(slow_data)), float(slow_data["saved_at"]) + 2.0 * 3600.0)
	check(not later.is_research_done("full_oll") and is_equal_approx(float(later.research["left"]), 3600.0), "2 h away: 1 h of Full OLL left")
	slow_data["lab"]["current"]["left"] = 50.0 * 3600.0
	later.apply_save_data(JSON.parse_string(JSON.stringify(slow_data)), float(slow_data["saved_at"]))
	check(is_equal_approx(float(later.research["left"]), 3.0 * 3600.0), "a damaged time left is clamped to the project's length")
	# Damaged or impossible Lab data is dropped, not trusted.
	var bad: Dictionary = slow_data.duplicate(true)
	bad["lab"] = {"current": {"id": "full_oll", "left": 10.0}, "done": ["lookahead", "nonsense"]}
	later.apply_save_data(JSON.parse_string(JSON.stringify(bad)), float(bad["saved_at"]))
	check(later.research.is_empty() and later.research_done.is_empty(), "projects whose requirements aren't done (and unknown ids) are dropped")
	bad["lab"] = {"current": {"id": "method_zz", "left": "x"}, "done": "oops"}
	later.apply_save_data(JSON.parse_string(JSON.stringify(bad)), float(bad["saved_at"]))
	check(later.research.is_empty(), "a method that isn't the next one can't be running")
	bad["lab"] = [1, 2]
	later.apply_save_data(JSON.parse_string(JSON.stringify(bad)), float(bad["saved_at"]))
	check(later.research.is_empty() and later.research_done.is_empty(), "a Lab that isn't a dictionary loads as empty")
	# A drill set learned before the Lab existed (a v8 save) counts as its project done.
	var drilled := new_game()
	for alg in Content.get_drill_cases("2look_pll"):
		for i in int(Content.DRILLS["clean_needed"]):
			drilled.record_drill("2look_pll", alg["id"], 1.0)
	var drilled_data := drilled.get_save_data()
	drilled_data.erase("lab")
	drilled_data["version"] = 8
	var drilled_loaded := new_game()
	drilled_loaded.apply_save_data(drilled_data, float(drilled_data["saved_at"]))
	check(drilled_loaded.is_research_done("two_look_pll") and not drilled_loaded.is_research_done("two_look_oll"), "drill sets learned before v9 finish their Lab project on load")
	drilled.free()
	drilled_loaded.free()
	# Done projects are saved; v8 saves get an empty Lab (and keep their methods).
	g.finish_research()
	data = g.get_save_data()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.is_research_done("finger_tricks"), "done projects survive save/load")
	var v8: Dictionary = data.duplicate(true)
	v8.erase("lab")
	v8["version"] = 8
	v8["method"] = "roux"
	var migrated := new_game()
	migrated.apply_save_data(v8, float(data["saved_at"]))
	check(migrated.research.is_empty() and migrated.research_done.is_empty() and migrated.is_research_done("method_cfop"), "a v8 save: empty Lab, its methods still learned")
	for node in [g, loaded, away, slow, later, migrated]:
		node.free()


func test_lab_tab() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._refresh()
	check((main.get_node("%LabStatus") as Label).text.begins_with("No projects yet"), "an empty Lab says so (V.9)")
	game.cheat_add_solves(1e4)
	main._refresh()
	var tabs: TabContainer = main.get_node("%Tabs")
	check(tabs.get_tab_title(main.LAB_TAB).begins_with("Lab"), "there's a Lab tab")
	var card: ShopCard = main._lab_cards["finger_tricks"]
	check(card.visible and card.affordable, "Finger Tricks can be started")
	check(main.get_tab_count(main.LAB_TAB) >= 1, "the Lab tab's bubble counts what can be started (V.5)")
	card.pressed.emit()
	check(game.research.get("id", "") == "finger_tricks", "pressing the card starts it")
	main._refresh()
	check((main.get_node("%LabStatus") as Label).text.begins_with("Researching Finger Tricks") and tabs.get_tab_title(main.LAB_TAB) == "Lab · 2:00", "the tab shows what's running and the time left")
	check(main.get_tab_count(main.LAB_TAB) == 0, "...and no count bubble while research runs (V.5)")
	check(card._content.modulate.a == 1.0 and card.disabled, "the running project is bright but can't be pressed again")
	check(main._goal_text({"kind": "research", "name": "Research Finger Tricks", "more": false, "unit": "time", "missing": 120.0,
			"seconds": 120.0, "progress": 0.0}) == "Research Finger Tricks  ·  2:00", "a research goal reads as its time left")
	game.finish_research()
	main._refresh()
	check(card._owned.text == "✓" and not card.affordable, "a done project is ticked")
	main.free()
	game.reset_state()


# --- World Championship: trophies and the Compete screen (task 6.1) ----------------------

func test_trophy_formula() -> void:
	var div := float(Content.CHAMPIONSHIP["divisor"])
	check(GameState.trophies_for(0.0) == 0 and GameState.trophies_for(-5.0) == 0, "no Solves, no trophies")
	check(GameState.trophies_for(div - 1.0) == 0 and GameState.trophies_for(div) == 1, "the first trophy at exactly one divisor")
	check(GameState.trophies_for(4.0 * div - 1.0) == 1 and GameState.trophies_for(4.0 * div) == 2, "floor(sqrt): 2 trophies at 4 divisors")
	check(GameState.trophies_for(100.0 * div) == 10, "10 trophies at 100 divisors")
	for n: int in [1, 2, 10, 51, 166, 1000]:
		var at := GameState.solves_for_trophies(n)
		check(GameState.trophies_for(at) == n and GameState.trophies_for(at * 0.999) == n - 1,
				"solves_for_trophies(%d) is exactly where trophy %d arrives" % [n, n])
	# The divisor is picked from BALANCE.md: the tapping bot competes at ~84 min with ~3.3e14 run Solves (D6, S.7).
	var at_90 := GameState.trophies_for(3.3e14)
	check(at_90 >= 30 and at_90 <= 80, "a ~90-minute run gives a few dozen trophies, not thousands (got %d)" % at_90)
	check(GameState.trophies_for(1e13) < at_90 and GameState.trophies_for(1.5e15) > at_90 * 2, "waiting longer gives more, less than linearly")
	var per := float(Content.CHAMPIONSHIP["bonus_per_trophy"])
	check_near(per, 0.02, "each unspent trophy is +2 % moves (PLAN §4.4)")
	check(not (Content.CHAMPIONSHIP["keeps"] as Array).is_empty() and not (Content.CHAMPIONSHIP["resets"] as Array).is_empty(),
			"the Compete screen has a keep list and a reset list")

	var g := new_game()
	check(g.get_pending_trophies() == 0 and not g.can_compete() and not g.is_compete_visible(), "a new game can't compete yet")
	check_near(g.get_trophy_mult(), 1.0, "no trophies: ×1")
	g.run_solves = div * 0.5
	check(g.is_compete_visible() and not g.can_compete(), "the Compete button shows at half the first trophy's Solves, like an upgrade")
	g.run_solves = div
	check(g.can_compete() and g.get_pending_trophies() == 1, "one trophy to win: competing is possible")
	var fresh := new_game()
	fresh.cheat_add_solves(123.0)
	check_near(fresh.get_run_solves(), 123.0, "Solves earned count for the run (and the lifetime)")
	fresh.free()
	# The bonus applies to every move: helpers and taps.
	g.buildings["friend"] = 1
	var helper_rate := g.get_puzzle_moves_per_second("2x2")
	check(helper_rate > 0.0, "a Friend makes helper moves")
	var before := g.total_moves
	g.tap()
	var tap_moves := g.total_moves - before
	g.trophies = 10
	check_near(g.get_trophy_mult(), 1.0 + 10.0 * per, "10 trophies: ×1.2")
	check_near(g.get_trophy_mult(51), 1.0 + 51.0 * per, "a count can be asked for: 51 trophies ×2.02")
	check_near(g.get_puzzle_moves_per_second("2x2"), helper_rate * 1.2, "helper moves get the trophy bonus")
	before = g.total_moves
	g.tap()
	check_near(g.total_moves - before, tap_moves * 1.2, "taps get it too")
	# The preview the Compete screen shows.
	g.trophies = 3
	g.run_solves = (GameState.solves_for_trophies(5) + GameState.solves_for_trophies(6)) * 0.5
	var p := g.get_championship_preview()
	check(int(p["trophies"]) == 3 and int(p["gain"]) == 5 and int(p["after"]) == 8, "preview: 3 owned + 5 won = 8")
	check_near(float(p["mult_now"]), 1.0 + 3.0 * per, "preview: the bonus now")
	check_near(float(p["mult_after"]), 1.0 + 8.0 * per, "preview: the bonus after competing")
	check_near(float(p["next_at"]), GameState.solves_for_trophies(6), "preview: Solves for the next trophy")
	check_near(float(p["next_progress"]), 0.5, "preview: halfway from trophy 5 to 6")
	check(g.is_compete_visible(), "owning trophies keeps the button visible")
	g.reset_state()
	check(g.trophies == 0, "wiping the save clears trophies")
	g.free()


func test_music_override() -> void:
	var audio: AudioManager = root.get_node("Audio")
	audio.stop_all()
	audio.set_window_focused(true)
	audio.set_music_mode("follow")
	audio.music_clock = AudioManager.MUSIC_START_DELAY
	var tracks: Array[String] = ["practice_room", "first_sub_20"]
	audio.set_music_context(tracks, "practice_room")
	check(audio.current_track_id == "practice_room", "follow mode plays the focused puzzle's track")
	audio.set_music_override("finals")
	check(audio.current_track_id == "finals", "a screen's track plays even before it's unlocked (Finals on the Compete screen)")
	audio.set_music_context(tracks, "first_sub_20")
	check(audio.current_track_id == "finals", "the game's refresh doesn't take the music back while the screen is open")
	for i in 10:
		audio.on_music_looped()
	check(audio.current_track_id == "finals", "it just loops (no variety detours)")
	audio.set_music_override("")
	check(audio.current_track_id == "first_sub_20" and audio.override_track_id == "", "closing the screen goes back to the follow track")
	# Shuffle mode resumes the track from before, even once Finals is unlocked (it would otherwise keep Finals).
	var with_finals: Array[String] = ["practice_room", "first_sub_20", "finals"]
	audio.set_music_context(with_finals, "first_sub_20")
	audio.set_music_mode("shuffle")
	var before := audio.current_track_id
	audio.set_music_override("finals")
	audio.set_music_override("")
	check(audio.current_track_id == before and before != "finals", "shuffle: closing the screen resumes the earlier track")
	audio.set_music_mode("follow")
	audio.stop_all()


func test_compete_panel() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.set_process(false)
	var audio: AudioManager = root.get_node("Audio")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var button: Button = main.get_node("%CompeteButton")
	var panel: CompetePanel = main.get_node("%CompetePanel")
	check(not button.visible and not panel.visible, "a new game shows no Compete button")
	game.run_solves = GameState.solves_for_trophies(51) + 1.0
	main._refresh()
	check(button.visible and button.text == "Compete +51" and button.tooltip_text == "World Championship: +51 trophies now.",
			"the top bar shows what competing gives (short; the tooltip spells it out)")
	audio.music_clock = AudioManager.MUSIC_START_DELAY
	button.pressed.emit()
	check(panel.visible, "the button opens the Compete screen")
	check(audio.override_track_id == "finals", "the Compete screen plays Finals")
	check((panel.get_node("%Gain") as Label).text == "+51 trophies", "it shows the trophies you'd win")
	check((panel.get_node("%MovesNow") as StatChip).get_text() == "+0 % now" and (panel.get_node("%MovesAfter") as StatChip).get_text() == "+102 % after",
			"and the bonus before and after, as StatChips (V.8)")
	check((panel.get_node("%KeepList") as VBoxContainer).get_child_count() == (Content.CHAMPIONSHIP["keeps"] as Array).size()
			and (panel.get_node("%ResetList") as VBoxContainer).get_child_count() == (Content.CHAMPIONSHIP["resets"] as Array).size(),
			"it lists everything you keep and everything that starts over")
	var compete: Button = panel.get_node("%CompeteButton")
	check(not compete.disabled and not (panel.get_node("%CompeteHint") as Label).visible, "competing works (6.2): no preview hint")
	var moves_before := game.total_moves
	main._unhandled_input(key_event(KEY_SPACE, true, false))
	check_near(game.total_moves, moves_before, "Space doesn't tap the cube while the screen is open")
	game.run_solves = GameState.solves_for_trophies(52)
	main._refresh()
	check((panel.get_node("%Gain") as Label).text == "+52 trophies", "the open screen keeps up with the run")
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	panel._unhandled_input(escape)
	check(_closed(panel) and audio.override_track_id == "", "Escape closes it and the music goes back")
	# Wording at the edges: one trophy, none yet, and the enabled button (6.2).
	panel.compete_enabled = true
	panel.set_preview({"gain": 1, "mult_now": 1.0, "mult_after": 1.02, "run_solves": 5e10, "next_at": 1.6e11, "next_progress": 0.1})
	check((panel.get_node("%Gain") as Label).text == "+1 trophy" and compete.text == "Compete for 1 trophy" and not compete.disabled,
			"one trophy reads singular, and the button works once enabled")
	panel.set_preview({"gain": 0, "mult_now": 1.0, "mult_after": 1.0, "run_solves": 2e10, "next_at": 4e10, "next_progress": 0.5})
	check((panel.get_node("%Gain") as Label).text == "No trophies yet" and compete.disabled, "no trophies: nothing to compete for")
	check((panel.get_node("%NextLabel") as Label).text.ends_with("for your first trophy"), "...and it says what the first one needs")
	check(CompetePanel.bonus_text(2.02) == "+102 %" and CompetePanel.bonus_text(1.0) == "+0 %", "bonus text")
	# Pressing Compete wins the trophies and starts a new run (6.2).
	game.buildings["friend"] = 5
	button.pressed.emit()
	check(panel.visible, "the screen opens again")
	compete.pressed.emit()
	check(game.trophies == 52 and game.championships == 1 and _closed(panel) and audio.override_track_id == "",
			"pressing Compete wins 52 trophies, closes the screen and the music goes back")
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	check(int(game.buildings["friend"]) == 0 and view.puzzle_id == "2x2", "the new run starts on the 2×2 with no helpers")
	for i in 3:
		main.news.advance(10.0)
	check(main.news.history.size() > 0 and String(main.news.history[0]).begins_with("World Champion! +52 trophies"),
			"the news feed says so")
	main._refresh()
	check(button.visible and button.text == "Compete", "the button stays (trophies are owned) with nothing to win yet")
	audio.stop_all()
	main.free()
	game.set_process(true)
	game.reset_state()


# --- World Championship reset (task 6.2) -------------------------------------------

func test_championship_reset() -> void:
	var g := new_game()
	check(g.compete() == 0 and g.championships == 0, "no trophy to win: competing does nothing")
	# A run with a bit of everything.
	g.cheat_add_solves(GameState.solves_for_trophies(20) + 5.0)
	g.unlock_puzzle("3x3")
	g.unlock_puzzle("4x4")
	g.buy_buildings("friend", 30)
	g.buy_buildings("robot", 5)
	g.buy_upgrade("lube")
	g.buy_upgrade("small_cubes")
	check(g.is_upgrade_locked_out("big_cubes"), "a choice made this run")
	g.buy_method("cfop")
	g.finish_research()
	g.start_research("finger_tricks")
	g.mastery_xp["3x3"] = 5000.0
	g._mastery_levels["3x3"] = g._level_for_xp(5000.0)
	var level_3x3 := g.get_mastery_level("3x3")
	g.record_hand_solve("3x3", 30.0, "", 50)
	var hand_bonus := g.get_hand_tier_mult("3x3")
	for case: Dictionary in Content.get_drill_cases("2look_pll"):  # a drill set learned by hand
		for i in int(Content.DRILLS["clean_needed"]):
			g.record_drill("2look_pll", case["id"], 1.0)
	check(g.is_research_done("two_look_pll"), "learning 2-look PLL by hand finished its Lab project")
	g.buff = {"id": "frenzy", "mult": 7.0, "left": 20.0}
	g.flow = {"mult": 2.0, "left": 60.0, "tier": 2}
	g.golden_glow_left = 5.0  # a golden sticker glowing at the moment of competing
	g._add_mastery_xp("4x4", g._mastery_xp_at(50))  # the 4×4 at level 50: +5 % moves on every puzzle
	check(g.get_mastery_level("4x4") >= 50 and g.get_mastery_level("4x4") < 100, "the 4×4 reached mastery level 50")
	var lifetime := g.total_solves
	var lifetime_moves := g.total_moves
	var drills := g.drills.duplicate(true)
	check(g.get_unlocked_track_ids().has("parity") and not g.get_unlocked_track_ids().has("finals"), "the 4×4's music; no Finals yet")
	check(g.get_next_locked_puzzle() == "5x5", "the ladder goes on to the 5×5")

	var won := [0]
	g.championship_won.connect(func(n: int) -> void: won[0] = n)
	var gain := g.get_pending_trophies()
	check(gain == 20 and g.compete() == 20 and won[0] == 20, "competing wins the pending trophies (20) and says so")
	# Kept
	check(g.trophies == 20 and g.championships == 1 and g.has_won_championship(), "trophies and the win are kept")
	check_near(g.get_trophy_mult(), 1.4, "20 unspent trophies: +40 % moves")
	check(g.get_mastery_level("3x3") == level_3x3, "puzzle mastery is kept")
	check(g.get_hand_solve_count("3x3") == 1 and is_equal_approx(g.get_hand_tier_mult("3x3"), hand_bonus),
			"Solve Station records and their tier bonus are kept")
	check(g.drills == drills, "drill records are kept")
	check(g.is_research_done("two_look_pll"), "...and a drill set learned by hand keeps its Lab project done")
	check(is_equal_approx(g.total_solves, lifetime) and is_equal_approx(g.total_moves, lifetime_moves), "lifetime stats are kept")
	var tracks := g.get_unlocked_track_ids()
	check(tracks.has("parity") and tracks.has("first_sub_20") and tracks.has("finals"), "music stays unlocked, and Finals joins it")
	# Reset
	check(is_zero_approx(g.solves) and is_zero_approx(g.get_run_solves()), "Solves and this run's Solves start over")
	check(g.unlocked_puzzles == (["2x2"] as Array[String]) and g.get_focused_puzzle_id() == "2x2" and is_equal_approx(g.get_puzzle_share("2x2"), 1.0),
			"puzzles go back to the 2×2")
	var helpers := 0
	for id: String in g.buildings:
		helpers += int(g.buildings[id])
	check(helpers == 0 and g.get_building_cost("friend") == 0.0, "helpers start over (the first Friend is free again)")
	check(g.upgrades.is_empty() and not g.is_upgrade_locked_out("big_cubes"), "upgrades start over, so the choices open again")
	check(g.method == "beginner" and g.research.is_empty() and not g.is_research_done("finger_tricks"),
			"methods and Lab research start over")
	check(g.buff.is_empty() and g.flow.is_empty(), "running Golden and Flow buffs end")
	check(is_equal_approx(g.golden_glow_left, 5.0), "a glowing golden sticker isn't a buff: it keeps glowing")
	var with_4x4 := g.get_puzzle_moves_mult("2x2")
	var level_4x4: int = g._mastery_levels["4x4"]
	g._mastery_levels.erase("4x4")
	var without_4x4 := g.get_puzzle_moves_mult("2x2")
	g._mastery_levels["4x4"] = level_4x4
	check(not g.is_puzzle_unlocked("4x4") and is_equal_approx(with_4x4 / without_4x4, 1.05),
			"the 4×4's level-50 bonus (+5 % everywhere) still counts with the 4×4 locked again")
	check(not g.can_compete() and g.is_compete_visible(), "nothing to win right away; the button stays")
	# The new run reveals the shop by its own Solves, not the lifetime ones.
	check(not g.is_building_unlocked("robot") and not g.is_upgrade_available("magnets"), "the Robot and Magnetic Cube hide again")
	g.cheat_add_solves(float(Content.get_upgrade("lube")["cost"]))
	check(g.is_upgrade_available("lube"), "...and show up at half their cost as the run goes")
	# After the first win the ladder goes on past the 5×5.
	g.cheat_add_solves(1e15)
	for id: String in ["3x3", "4x4", "5x5"]:
		g.unlock_puzzle(id)
	check(g.get_next_locked_puzzle() == "7x7" and g.unlock_puzzle("7x7") and g.unlock_puzzle("megaminx"),
			"the 7×7 and the Megaminx can be unlocked now")
	check(g.get_unlocked_track_ids().has("twelve_faces"), "with their music")
	# A second championship adds to the first.
	var second := g.get_pending_trophies()
	g.compete()
	check(g.trophies == 20 + second and g.championships == 2, "a second championship adds its trophies")
	g.free()

	# Without a championship the 7×7 stays out of reach.
	var before := new_game()
	before.cheat_add_solves(1e15)
	for id: String in ["3x3", "4x4", "5x5"]:
		before.unlock_puzzle(id)
	check(before.get_next_locked_puzzle() == "" and not before.unlock_puzzle("7x7"), "no championship: no 7×7")
	before.free()


func test_championship_save() -> void:
	var g := new_game()
	g.cheat_add_solves(GameState.solves_for_trophies(9))
	g.unlock_puzzle("3x3")
	g.unlock_puzzle("4x4")
	g.compete()
	g.cheat_add_solves(1234.0)
	var data := g.get_save_data()
	check(int(data["version"]) == GameState.SAVE_VERSION and GameState.SAVE_VERSION >= 10, "saves as v10 or later")
	g.free()
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.trophies == 9 and loaded.championships == 1 and loaded.has_won_championship(), "trophies and wins load")
	check_near(loaded.get_run_solves(), 1234.0, "this run's Solves load")
	check(loaded.get_unlocked_track_ids().has("parity") and loaded.unlocked_puzzles.size() == 1,
			"music from puzzles reached in an earlier run loads, though only the 2×2 is unlocked now")
	loaded.free()
	# A damaged save can't claim more run Solves than lifetime ones, or negative trophies.
	data["championship"] = {"trophies": -4, "count": -1, "run_solves": 1e30, "reached": ["3x3", "banana"]}
	var damaged := new_game()
	damaged.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(damaged.trophies == 0 and damaged.championships == 0 and damaged.get_run_solves() <= damaged.total_solves,
			"a damaged championship block is cleaned up")
	check(damaged.puzzles_reached.has("3x3") and not damaged.puzzles_reached.has("banana"), "unknown puzzles are dropped")
	damaged.free()
	# v9 -> v10: no championship yet, the run is the whole lifetime, music from the puzzles unlocked.
	var v9 := {"version": 9, "saved_at": 1000.0, "solves": 50.0, "total_solves": GameState.solves_for_trophies(3),
		"total_moves": 10.0, "puzzles": {"unlocked": ["2x2", "3x3"], "progress": {}, "focus": "3x3", "split": {"3x3": 1.0}},
		"mastery": {}, "buildings": {"friend": 3}, "upgrades": ["lube"], "method": "beginner", "solve_records": {},
		"golden": {"next": 100.0, "buff": {}}, "drills": {}, "daily": {}, "lab": {"current": {}, "done": []}}
	var old := new_game()
	old.apply_save_data(v9, 1000.0)
	check(old.trophies == 0 and old.championships == 0 and not old.has_won_championship(), "v9 → v10: no championship yet")
	check_near(old.get_run_solves(), GameState.solves_for_trophies(3), "v9 → v10: this run's Solves are the lifetime ones")
	check(old.get_pending_trophies() == 3 and old.puzzles_reached.has("3x3"), "...so the trophies wait, and the 3×3 counts as reached")
	check(int(old.get_save_data()["version"]) == GameState.SAVE_VERSION, "it saves as the current version")
	old.free()


# --- Trophy perk tree (task 6.3) -----------------------------------------------------

## A game that has won `trophies` trophies in one championship (so perks can be bought).
func perk_game(trophy_count: int) -> GameState:
	var g := new_game()
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	g.compete()
	g._load_collection({})  # the championship's Cube Collection drop (7.3a) would add its own passive to the numbers
	g.trophies = trophy_count
	return g


func test_perk_data() -> void:
	var ids := {}
	var branches := {}
	for branch: Dictionary in Content.PERK_BRANCHES:
		branches[branch["id"]] = 0
	for def: Dictionary in Content.PERKS:
		var id: String = def["id"]
		check(not ids.has(id), "perk ids are unique (%s)" % id)
		check(branches.has(def["branch"]), "%s is in a known branch" % id)
		check(ResourceLoader.exists(Content.ICON_DIR + String(def["icon"]) + ".svg"), "%s has an icon" % id)
		check(int(def["cost"]) > 0, "%s costs trophies" % id)
		var effect: Dictionary = def["effect"]
		check(Content.EFFECT_TYPES.has(effect["type"]) or Content.PERK_EFFECT_TYPES.has(effect["type"]),
				"%s has a known effect type (%s)" % [id, effect["type"]])
		for need: Variant in def["requires"]:
			check(ids.has(str(need)), "%s needs a perk listed before it (%s)" % [id, need])
			check(Content.get_perk(str(need)).get("branch", "") == def["branch"], "%s needs a perk of its own branch" % id)
		if (def["requires"] as Array).is_empty():
			branches[def["branch"]] = int(branches[def["branch"]]) + 1
		check(Content.get_perk(id) == def, "get_perk finds %s" % id)
		ids[id] = true
	for branch: String in branches:
		check(int(branches[branch]) == 1, "the %s branch has exactly one first node" % branch)
	check(Content.PERK_BRANCHES.size() == 4, "four branches: Practice, Team, Competition, Automation")
	check(PerkPanel.layout_rows("practice").size() == 3 and (PerkPanel.layout_rows("practice")[0] as Array) == ["warm_up"],
			"the tree layout puts a branch's first node alone on the top row")


func test_perk_buying() -> void:
	var g := perk_game(20)
	check(g.get_perk_status("warm_up") == "available" and g.can_buy_perk("warm_up"), "a first node can be bought")
	check(g.get_perk_status("practice_away") == "locked" and not g.buy_perk("practice_away"), "a node needs its parent")
	var mult_before := g.get_trophy_mult()
	check(g.buy_perk("warm_up") and g.has_perk("warm_up"), "buying a perk")
	check(g.trophies == 15, "it costs its trophies (20 - 5)")
	check(g.get_trophy_mult() < mult_before and is_equal_approx(g.get_trophy_mult(), 1.0 + 0.02 * 15),
			"only unspent trophies give +2 %%, so spending lowers the bonus (owner, 2026-11-06)")
	check(g.get_perk_status("warm_up") == "owned" and not g.buy_perk("warm_up"), "a perk is bought once")
	check(g.get_perk_status("practice_away") == "available", "...and opens its children")
	g.trophies = 3
	check(not g.can_buy_perk("practice_away") and not g.buy_perk("practice_away") and g.trophies == 3, "too few trophies: nothing happens")
	check(not g.buy_perk("banana"), "an unknown perk can't be bought")
	g.free()
	var fresh := new_game()
	check(not fresh.can_buy_perk("warm_up"), "a new game has no trophies to spend")
	fresh.free()


## Every perk in Content.PERKS has its own check here; a new perk fails this test until it gets one.
func test_each_perk() -> void:
	var tested := {}

	# warm_up: the 3×3 at the start of every run (and at once).
	var g := perk_game(100)
	check(g.buy_perk("warm_up") and g.is_puzzle_unlocked("3x3") and g.get_focused_puzzle_id() == "3x3",
			"Warm-up Routine unlocks the 3×3 at once and focuses it")
	check_near(g.get_puzzle_share("3x3"), 1.0, "...with the whole split, like unlocking it")
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	g.compete()
	check(g.is_puzzle_unlocked("3x3") and g.get_focused_puzzle_id() == "3x3" and g.unlocked_puzzles.size() == 2,
			"...and every new run starts with it")
	tested["warm_up"] = true

	# big_cube_prep: the 4×4 too.
	check(g.buy_perk("big_cube_prep") and g.is_puzzle_unlocked("4x4") and g.get_focused_puzzle_id() == "4x4",
			"Big Cube Prep unlocks the 4×4")
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	g.compete()
	check(Array(g.unlocked_puzzles) == ["2x2", "3x3", "4x4"], "...and every run starts with the 2×2 to 4×4")
	tested["big_cube_prep"] = true

	# practice_away / overnight: the offline cap.
	check_near(g.get_offline_cap_seconds(), 8.0 * 3600.0, "the offline cap is 8 h")
	g.buy_perk("practice_away")
	check_near(g.get_offline_cap_seconds(), 12.0 * 3600.0, "Practice While Away: 12 h")
	tested["practice_away"] = true
	g.buy_perk("overnight")
	check_near(g.get_offline_cap_seconds(), 16.0 * 3600.0, "Overnight Sessions: 16 h")
	tested["overnight"] = true
	g.buildings["friend"] = 10
	var data := g.get_save_data()
	data["saved_at"] = 1000.0
	var away := new_game()
	away.apply_save_data(JSON.parse_string(JSON.stringify(data)), 1000.0 + 24.0 * 3600.0)
	check_near(float(away.offline_report.get("seconds", 0.0)), 16.0 * 3600.0, "...a day away counts 16 h")
	away.free()
	g.free()

	# team_captain / club_founder: helpers at the start of a run (topped up at once).
	g = perk_game(100)
	g.buildings["friend"] = 3
	check(g.buy_perk("team_captain") and int(g.buildings["friend"]) == 10, "Team Captain tops Friends up to 10 at once")
	g.buildings["friend"] = 25
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	g.compete()
	check(int(g.buildings["friend"]) == 10, "...and every run starts with 10 Friends")
	check(g.get_building_cost("friend") > 0.0, "...so the 11th isn't free")
	tested["team_captain"] = true
	check(g.buy_perk("club_founder") and int(g.buildings["club"]) == 10, "Club Founder: 10 Clubs")
	g.buildings["club"] = 40
	g.buy_perk("team_spirit")
	check(int(g.buildings["club"]) == 40, "a run-start perk never takes helpers away")
	tested["club_founder"] = true

	# team_spirit / team_chemistry: every helper faster, taps not.
	var g2 := perk_game(100)
	g2.buy_perk("team_captain")
	var friend_mps := g2.get_building_mps("friend")
	var tap := g2.get_tap_moves()
	g2.buy_perk("team_spirit")
	check_near(g2.get_building_mps("friend"), friend_mps * 1.5, "Team Spirit: helpers ×1.5")
	check_near(g2.get_tap_moves(), tap, "...taps are not helpers")
	tested["team_spirit"] = true
	g2.buy_perk("team_chemistry")
	check_near(g2.get_building_mps("club"), float(Content.get_building("club")["mps"]) * 3.0, "Team Chemistry: ×2 more (×3 in all)")
	tested["team_chemistry"] = true
	g2.free()
	g.free()

	# comp_circuit: Competitions don't exist yet, so it can't be bought, and its children don't wait for it.
	g = perk_game(100)
	check(g.get_perk_status("comp_circuit") == "soon" and not g.buy_perk("comp_circuit"), "Competition Circuit arrives with Competitions (8.3)")
	check(not g.is_system_unlocked("competitions"), "...so Competitions stay closed")
	check(g.get_perk_status("comp_prep") == "available" and g.get_perk_status("home_crowd") == "available",
			"...and the rest of its branch works today (owner, 2026-11-06)")
	tested["comp_circuit"] = true

	# comp_prep: ×1.25 trophies.
	g.trophies = 50
	g.cheat_add_solves(GameState.solves_for_trophies(8) - g.get_run_solves())
	check(g.get_pending_trophies() == 8, "8 trophies before Comp Prep")
	g.buy_perk("comp_prep")
	check(g.get_pending_trophies() == 10, "Comp Prep: 25 %% more (8 -> 10)")
	var preview := g.get_championship_preview()
	check(int(preview["gain"]) == 10 and is_equal_approx(float(preview["gain_mult"]), 1.25), "...and the Compete screen shows it")
	check(GameState.trophies_for(float(preview["next_at"]), 1.25) == 11 and GameState.trophies_for(float(preview["next_at"]) * 0.999, 1.25) == 10,
			"...with the next trophy exactly where it arrives")
	tested["comp_prep"] = true

	# home_crowd: +3 % per unspent trophy.
	g.trophies = 40
	g.buy_perk("home_crowd")
	check_near(g.get_bonus_per_trophy(), 0.03, "Home Crowd: +3 % per trophy")
	check_near(g.get_trophy_mult(), 1.0 + 0.03 * 20, "...on the 20 trophies left")
	check_near(g.get_bonus_per_trophy(), 0.03, "...read again from the cache")
	tested["home_crowd"] = true

	# appearance_fees: ×2 Solves per solve.
	g.trophies = 30
	var value := g.get_solve_value("2x2")
	g.buy_perk("appearance_fees")
	check_near(g.get_solve_value("2x2"), value * 2.0, "Appearance Fees: ×2 Solves per solve")
	tested["appearance_fees"] = true

	# automation: opens the Auto tab; each auto_* perk opens its auto-buyer (details in the test_auto_* tests).
	g.trophies = 200
	check(not g.is_system_unlocked("automation") and g.buy_perk("automation") and g.is_system_unlocked("automation"),
			"Automation opens the Automation system (the Auto tab)")
	tested["automation"] = true
	for kind: String in Content.AUTOMATION["kinds"]:
		var perk_id := "auto_" + kind
		check(not g.is_auto_unlocked(kind), "%s isn't usable before its perk" % kind)
		if perk_id == "auto_puzzles":
			g.buy_perk("auto_helpers")
		if perk_id == "auto_compete":
			g.buy_perk("auto_upgrades")
		check(g.buy_perk(perk_id) and g.is_auto_unlocked(kind), "%s opens the %s auto-buyer" % [perk_id, kind])
		check(g.is_auto_on(kind) == (kind != "compete"), "...switched %s when bought" % ("off" if kind == "compete" else "on"))
		tested[perk_id] = true
	g.free()

	for def: Dictionary in Content.PERKS:
		check(tested.has(def["id"]), "perk %s has a test in test_each_perk" % def["id"])


func test_perks_kept_and_saved() -> void:
	var g := perk_game(60)
	for id: String in ["warm_up", "practice_away", "team_captain", "team_spirit", "comp_prep"]:
		g.buy_perk(id)
	var spent_left := g.trophies
	g.cheat_add_solves(GameState.solves_for_trophies(4))
	var won := g.compete()
	check(won == 5 and g.trophies == spent_left + 5, "a championship keeps perks and adds trophies (4 × 1.25 = 5)")
	check(g.has_perk("team_spirit") and g.perks.size() == 5, "perks are kept through a championship")
	var data := g.get_save_data()
	check(GameState.SAVE_VERSION >= 11 and int(data["version"]) == GameState.SAVE_VERSION, "saves as v11 or later")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.perks.size() == 5 and loaded.has_perk("comp_prep") and loaded.trophies == g.trophies, "perks load")
	check_near(loaded.get_building_mps("friend"), g.get_building_mps("friend"), "...and work after loading")
	loaded.free()
	# A damaged list: unknown ids, perks without their parent and not-yet-buyable ones are dropped.
	(data["championship"] as Dictionary)["perks"] = ["banana", "overnight", "team_chemistry", "comp_circuit", "warm_up", 7]
	var damaged := new_game()
	damaged.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(damaged.perks.keys() == ["warm_up"], "a damaged perk list keeps only what could have been bought")
	damaged.free()
	(data["championship"] as Dictionary)["perks"] = "nope"
	var broken := new_game()
	broken.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(broken.perks.is_empty(), "a perk list that isn't a list loads as none")
	broken.free()
	# v10 -> v11: no perks yet.
	var v10 := g.get_save_data()
	v10["version"] = 10
	(v10["championship"] as Dictionary).erase("perks")
	var old := new_game()
	old.apply_save_data(JSON.parse_string(JSON.stringify(v10)), float(v10["saved_at"]))
	check(old.perks.is_empty() and old.trophies == g.trophies, "v10 → v11: no perks, trophies kept")
	check(int(old.get_save_data()["version"]) == GameState.SAVE_VERSION, "...and it saves as the current version")
	old.free()
	g.reset_state()
	check(g.perks.is_empty() and g.trophies == 0, "a wiped save has no perks")
	g.free()


# --- Auto-buyers (task 6.3b) -------------------------------------------------------------

## A game in a new run with these Automation perks bought (their auto-buyers switched on, auto-Compete too).
func auto_game(perk_ids: Array) -> GameState:
	var g := perk_game(500)
	g.buy_perk("automation")
	for id: Variant in perk_ids:
		check(g.buy_perk(str(id)), "bought %s" % id)
	for kind: String in Content.AUTOMATION["kinds"]:
		g.set_auto(kind, true)
	g.trophies = 0  # no trophy bonus: income stays small and predictable
	return g


func test_auto_nothing_before_bought() -> void:
	var g := perk_game(500)
	g.cheat_add_solves(1e12)
	for kind: String in Content.AUTOMATION["kinds"]:
		g.automation[kind] = true  # even a save that says "on" can't run one that isn't bought
		g.set_auto(kind, true)
		check(not g.is_auto_on(kind), "%s isn't on before it's bought" % kind)
	var solves_before := g.solves
	check(g.run_automation() == 0 and is_equal_approx(g.solves, solves_before) and g.upgrades.is_empty()
			and int(g.buildings["friend"]) == 0 and g.unlocked_puzzles.size() == 1 and g.championships == 1,
			"nothing is bought, unlocked or competed before an auto-buyer is bought")
	g.buy_perk("automation")
	check(g.run_automation() == 0, "the Automation perk alone buys nothing either")
	g.free()


func test_auto_helpers() -> void:
	var g := auto_game(["auto_helpers"])
	g.cheat_add_solves(5000.0)
	var bought := g.run_automation()
	check(bought > 1 and int(g.buildings["friend"]) > 1, "Team Manager buys helpers (%d)" % bought)
	var cheapest := INF
	for def: Dictionary in Content.BUILDINGS:
		if g.is_building_unlocked(def["id"]):
			cheapest = minf(cheapest, g.get_building_cost(def["id"]))
	check(g.solves < cheapest, "...until even the cheapest one is out of reach")
	check(g.upgrades.is_empty() and g.unlocked_puzzles.size() == 1, "...and nothing but helpers")
	check(not g.automation_running, "the running flag is cleared after a tick")
	g.set_auto("helpers", false)
	g.cheat_add_solves(5000.0)
	var owned := int(g.buildings["friend"])
	check(g.run_automation() == 0 and int(g.buildings["friend"]) == owned, "switched off, it buys nothing")
	g.free()


func test_auto_upgrades() -> void:
	var g := auto_game(["auto_upgrades"])
	g.buildings["friend"] = 200
	g.buildings["club"] = 200
	g.cheat_add_solves(1e9)
	check(g.run_automation() > 0 and not g.upgrades.is_empty(), "Shopping List buys upgrades")
	var cheapest_left := INF
	for def: Dictionary in Content.get_upgrades():
		check(not (g.upgrades.has(def["id"]) and String(def.get("choice_group", "")) != ""),
				"...never a choice pair (%s): picking a side stays the player's" % def["id"])
		if String(def.get("choice_group", "")) == "" and g.is_upgrade_available(def["id"]):
			cheapest_left = minf(cheapest_left, float(def["cost"]))
	check(g.solves < cheapest_left, "...every one it can afford, cheapest first")
	check(int(g.buildings["friend"]) == 200, "...and no helpers")
	g.free()


func test_auto_puzzles() -> void:
	var g := auto_game(["auto_helpers", "auto_puzzles"])
	g.set_auto("helpers", false)
	g.cheat_add_solves(299.0)
	check(g.run_automation() == 0 and not g.is_puzzle_unlocked("3x3"), "Puzzle Scout waits until the next puzzle is affordable")
	g.cheat_add_solves(1.0)
	check(g.run_automation() == 1 and g.is_puzzle_unlocked("3x3") and g.get_focused_puzzle_id() == "3x3",
			"...then unlocks it, like the Unlock button")
	check(not g.is_puzzle_unlocked("4x4"), "...one at a time, and only what it can afford")
	g.free()


func test_auto_compete() -> void:
	var g := auto_game(["auto_upgrades", "auto_compete", "auto_helpers"])
	check(g.get_auto_compete_at() == int(Content.AUTOMATION["compete_at_default"]), "auto-Compete starts with the default target")
	g.set_auto_compete_at(10)
	g.cheat_add_solves(GameState.solves_for_trophies(9))
	var won_before := g.championships
	g.run_automation()
	check(g.championships == won_before and g.get_pending_trophies() == 9, "below its target (9 < 10) it doesn't compete")
	g.cheat_add_solves(GameState.solves_for_trophies(10) - g.get_run_solves())
	var trophies_before := g.trophies
	check(g.run_automation() == 1 and g.championships == won_before + 1, "at its target it competes")
	check(g.trophies == trophies_before + 10, "...for the trophies it waited for")
	# (The first Friend of a new run is free, so without the early stop the helper pass would buy it right away.)
	check(int(g.buildings["friend"]) == 0 and g.upgrades.is_empty(), "...and buys nothing in that tick (a new run starts)")
	check(g.is_auto_on("compete") and g.get_auto_compete_at() == 10, "...and stays on, with its target, for the next run")
	g.set_auto_compete_at(1)
	g.cheat_add_solves(GameState.solves_for_trophies(1))
	g.auto_compete_held = true
	var held_wins := g.championships
	g.run_automation()
	check(g.championships == held_wins, "auto-Compete waits while the UI holds it (a hand solve, the Compete screen)")
	g.auto_compete_held = false
	g.run_automation()
	check(g.championships == held_wins + 1, "...and competes once it's let go")
	g.set_auto_compete_at(0)
	check(g.get_auto_compete_at() == 1, "the target is at least 1 trophy")
	var panel: Variant = load("res://scripts/ui/automation_panel.gd")  # untyped: AutomationPanel uses Game by name
	check(panel.step(10, 1) == 15 and panel.step(10, -1) == 5 and panel.step(1, -1) == 1 and panel.step(12, -1) == 10,
			"the Auto tab's − / + step through round numbers")
	g.free()


func test_auto_runs_once_a_second() -> void:
	var g := auto_game(["auto_helpers"])
	g.cheat_add_solves(5000.0)
	g._process(0.5)
	check(int(g.buildings["friend"]) == 0, "nothing before a second has passed")
	g._process(0.6)
	check(int(g.buildings["friend"]) > 0, "the auto-buyers run once a second")
	g.free()


func test_auto_save() -> void:
	var g := auto_game(["auto_helpers", "auto_upgrades", "auto_compete"])
	g.set_auto("upgrades", false)
	g.set_auto_compete_at(75)
	var data := g.get_save_data()
	check(GameState.SAVE_VERSION >= 12 and int(data["version"]) == GameState.SAVE_VERSION, "saves as v12 or later")
	var loaded := new_game()
	loaded.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(loaded.is_auto_on("helpers") and not loaded.is_auto_on("upgrades") and loaded.is_auto_on("compete")
			and loaded.get_auto_compete_at() == 75, "the switches and the target load")
	loaded.free()
	data["automation"] = {"helpers": "yes", "compete_at": -5, "banana": true}
	var damaged := new_game()
	damaged.apply_save_data(JSON.parse_string(JSON.stringify(data)), float(data["saved_at"]))
	check(not damaged.is_auto_on("helpers") and damaged.get_auto_compete_at() == 1 and not damaged.automation.has("banana"),
			"damaged switches load as off, a bad target is clamped, unknown keys are dropped")
	damaged.free()
	var v11 := g.get_save_data()
	v11["version"] = 11
	v11.erase("automation")
	var old := new_game()
	old.apply_save_data(JSON.parse_string(JSON.stringify(v11)), float(v11["saved_at"]))
	check(old.has_perk("auto_helpers") and old.is_auto_unlocked("helpers") and not old.is_auto_on("helpers"),
			"v11 → v12: auto-buyers bought before load switched off")
	check(old.get_auto_compete_at() == int(Content.AUTOMATION["compete_at_default"]), "...with the default target")
	old.free()
	g.free()


func test_auto_saves_up() -> void:
	var g := auto_game(["auto_helpers", "auto_puzzles"])
	g.buildings["friend"] = 10
	var reach := g.get_solves_per_second() * float(Content.AUTOMATION["save_seconds"])
	check(reach > 15.0 and reach < 290.0, "test setup: the 3×3 is in reach from 290 Solves, not from 0 (%s)" % reach)
	g.cheat_add_solves(290.0)
	check_near(g.get_auto_reserve(), 300.0, "with Puzzle Scout on and the 3×3 close, Team Manager keeps its cost back")
	var owned := int(g.buildings["friend"])
	g.run_automation()
	check(int(g.buildings["friend"]) == owned and g.solves >= 290.0, "...so it buys no helper while saving up")
	g.cheat_add_solves(10.0)
	g.run_automation()
	check(g.is_puzzle_unlocked("3x3"), "...and Puzzle Scout gets the 3×3 as soon as it's affordable")
	g.free()

	var far := auto_game(["auto_helpers", "auto_puzzles"])
	far.cheat_add_solves(20.0)
	check_near(far.get_auto_reserve(), 0.0, "a puzzle far out of reach isn't saved for")
	check(far.run_automation() > 0, "...so Team Manager keeps buying helpers")
	far.free()

	var shop := auto_game(["auto_helpers", "auto_upgrades"])
	shop.buildings["friend"] = 10
	var cheapest := INF
	for def: Dictionary in Content.get_upgrades():
		if String(def.get("choice_group", "")) == "" and shop.is_upgrade_available(def["id"]):
			cheapest = minf(cheapest, float(def["cost"]))
	shop.cheat_add_solves(1.0)
	check(cheapest == INF or is_equal_approx(shop.get_auto_reserve(), cheapest) == (cheapest - 1.0
			<= shop.get_solves_per_second() * float(Content.AUTOMATION["save_seconds"])),
			"Shopping List's next upgrade is saved for when it's close")
	shop.free()


func test_auto_pause_and_cap() -> void:
	var g := auto_game(["auto_helpers"])
	g.cheat_add_solves(1e40)
	g.automation_paused = true
	check(g.run_automation() == 0 and int(g.buildings["friend"]) == 0, "nothing runs while paused (Welcome back open)")
	g.automation_paused = false
	check(g.run_automation() == int(Content.AUTOMATION["helper_buys_per_tick"]), "at most 100 helpers a tick")
	g.free()


func test_bot_prestige_rules() -> void:
	# The balance bot's championship (6.4): compete once it at least doubles the trophy bonus; spend at most half.
	var sim: RefCounted = load("res://tools/simulator.gd").new()
	var g := new_game()
	g.cheat_add_solves(GameState.solves_for_trophies(49))
	check(not sim.should_compete(g), "49 trophies (×1.98) isn't worth competing for yet")
	g.cheat_add_solves(GameState.solves_for_trophies(50) - g.get_run_solves())
	check(sim.should_compete(g), "50 trophies (×2) is")
	check(g.compete() == 50, "test setup: 50 trophies won")
	var bought: Array[String] = sim.buy_perks(g)
	check(not bought.is_empty() and g.trophies >= 25, "the bot buys perks but keeps at least half its trophies (%s)" % [bought])
	g.free()


func test_mult_cache_with_perks() -> void:
	# 6.4 found _upgrade_mult using a cache key without perks while the perk sums used one with them: with any perk
	# owned they wiped each other's cache on every call. Every cache user must agree on the key.
	var g := perk_game(100)
	g.buy_perk("team_captain")
	g.get_moves_per_second()
	g.get_trophy_mult()
	g._synergy_mult("club")
	check(g._mult_cache_owned == g._mult_cache_key(), "after every kind of lookup the cache is built for today's key")
	var size := g._mult_cache.size()
	g.get_moves_per_second()
	check(size > 1 and g._mult_cache.size() == size, "...and stays filled (it isn't wiped between calls)")
	g.free()


# --- V.4: a decluttered main screen -------------------------------------------------

func test_main_screen_declutter() -> void:
	var game: GameState = root.get_node("Game")
	game.persistence_enabled = false
	game.reset_state()
	game.set_process(false)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._refresh()
	var stage: VBoxContainer = main.get_node("Margin/Rows/Columns/Stage")
	var names: Array[String] = []
	for child in stage.get_children():
		names.append(child.name)
	check(names == (["StageArea"] as Array[String]), "nothing under the stage: the shelf is on it too (got %s)" % [names])
	for path: String in ["%StageChips", "%MoveTicker", "%GoalCard", "%TeamBest", "%HintLabel", "%Shelf"]:
		check(main.get_node("%StageArea").is_ancestor_of(main.get_node(path)), "%s sits on the stage" % path)
	check(main.get_node_or_null("%StatsLabel") == null, "no Lifetime line under the cube")
	check((main.get_node("%SolvesBox") as Control).tooltip_text.contains("Lifetime: "), "Lifetime is in the Solves tooltip")
	var hint: Label = main.get_node("%HintLabel")
	check(hint.visible, "a new player sees the first-time hint")
	check((main.get_node("%ProgressLabel") as Control).tooltip_text.contains("drag to look around"),
			"the how-to stays in the goal card's tooltip")
	check((main.get_node("%PuzzleView") as Control).tooltip_text == "", "no tooltip pops up over the puzzle itself")
	var news_panel: Control = main.get_node("%NewsPanel")
	check(not news_panel.visible, "no empty news box")
	main.news.push("test", "Something happened.")
	main.news.advance(10.0)
	main._show_news()
	check(news_panel.visible, "it appears with the first line")
	var locked: PuzzleChip = main._locked_chip
	var cost_text := Num.format(float(Content.get_puzzle("3x3")["unlock_cost"]))
	check(is_zero_approx(locked._unlock.modulate.a) and locked._unlock.disabled and locked._name.text.contains(cost_text),
			"a locked puzzle you can't afford is one line: name and cost (the button's slot is kept, invisible)")
	await process_frame
	await process_frame
	var shelf_height := (main.get_node("%Shelf") as Control).get_combined_minimum_size().y
	game.cheat_add_solves(float(Content.get_puzzle("3x3")["unlock_cost"]) * 2.0)
	game.total_moves = 1e6
	main._refresh()
	await process_frame
	await process_frame
	check(is_equal_approx(locked._unlock.modulate.a, 1.0) and not locked._unlock.disabled and locked._name.text.contains(cost_text),
			"once affordable, the Unlock button appears and the cost stays")
	check(is_equal_approx((main.get_node("%Shelf") as Control).get_combined_minimum_size().y, shelf_height),
			"...without the shelf changing height (%s → %s)" % [shelf_height, (main.get_node("%Shelf") as Control).get_combined_minimum_size().y])
	check(not hint.visible, "after a while the first-time hint goes away")
	# The goal card sits on the stage, so the puzzle is framed between it and the bottom strip, a little zoomed in.
	await process_frame
	await process_frame
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	var top: Control = main.get_node("%StageTop")
	var strip: Control = main.get_node("%StageOverlay")
	check(view.frame_inset_top > 0.0 and is_equal_approx(view.frame_inset_top, top.size.y), "the view knows what the card covers")
	check(view.frame_inset_bottom > 0.0 and is_equal_approx(view.frame_inset_bottom, strip.size.y), "...and the strip")
	check(is_equal_approx(view.frame_zoom, main.STAGE_ZOOM), "and zooms in a little")
	var cam: Camera3D = view._camera
	var e := view._extent() / 2.0
	var lowest := -INF
	var highest := INF
	for i in 8:
		var corner := view._base_puzzle * Vector3(e if i & 1 else -e, e if i & 2 else -e, e if i & 4 else -e)
		var at := cam.unproject_position(corner)
		lowest = maxf(lowest, at.y)
		highest = minf(highest, at.y)
	var band_top := view.frame_inset_top
	var band_bottom := view.size.y - view.frame_inset_bottom
	check(highest >= band_top - 1.0 and lowest <= band_bottom + 1.0,
			"the cube at rest sits between the card and the strip (%d..%d in %d..%d)" % [highest, lowest, band_top, band_bottom])
	# The shelf on the stage's left: the puzzle is framed right of it, and is at least half the screen's height (V.4).
	var shelf: Control = main.get_node("%Shelf")
	check(shelf.visible and is_equal_approx(view.frame_inset_left, shelf.size.x), "the view knows what the shelf covers")
	var left := INF
	for i in 8:
		var corner := view._base_puzzle * Vector3(e if i & 1 else -e, e if i & 2 else -e, e if i & 4 else -e)
		left = minf(left, cam.unproject_position(corner).x)
	check(left >= shelf.size.x - 1.0, "...and the cube at rest stays right of it (%d ≥ %d)" % [left, shelf.size.x])
	var screen := float(ProjectSettings.get_setting("display/window/size/viewport_height"))  # the logical screen (720)
	check((lowest - highest) / screen >= 0.5, "the puzzle is at least half the screen's height (%d %%)" % roundi((lowest - highest) / screen * 100.0))
	check(main.puzzle_row.columns == 1, "a short shelf is one column")
	for id: String in ["3x3", "4x4", "5x5", "7x7"]:  # four besides the focused 2×2
		game._add_puzzle(id)
	main._build_puzzle_row()
	check(main.puzzle_row.columns == 2, "four puzzles or more take two columns")
	await process_frame
	await process_frame
	check(shelf.size.x > 150.0 and is_equal_approx(view.frame_inset_left, shelf.size.x), "the view follows the wider shelf")
	var mat_left := INF
	var mat_right := -INF
	for corner: Vector3 in view._mat_corners():
		var at := cam.unproject_position(corner)  # _mat_corners() are already where the view sees them at rest
		mat_left = minf(mat_left, at.x)
		mat_right = maxf(mat_right, at.x)
	check(mat_left >= view.frame_inset_left - 1.0 and mat_right <= view.size.x + 1.0,
			"...and the mat stays between the shelf and the view's edge (%d..%d in %d..%d)" % [mat_left, mat_right, view.frame_inset_left, view.size.x])
	main.free()
	game.set_process(true)
	game.reset_state()
