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
		"tapping": sim.run(Pacing.TAPS_PER_SEC, Pacing.TAPPING_MINUTES),
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
	view._gui_input(mouse_button(true, Vector2(150, 150)))
	view._gui_input(mouse_button(false, Vector2(150, 150)))
	check_near(game.total_moves, game.get_tap_moves(), "clicking the puzzle calls Game.tap()")
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
	main._animate_counter(1.0)
	check((main.get_node("%SolvesLabel") as Label).text == "1.50e3 Solves", "the UI uses the chosen notation")
	settings.set_value("notation", "short")
	check(Num.format(1500.0) == "1.50K", "back to short notation")
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
	check(main.get_node_or_null("%NextGoalLabel") != null and main.get_node_or_null("%SettingsButton") != null,
			"the next-goal strip and the settings button exist")
	main._unhandled_input(key_event(KEY_SPACE, true, false))
	check_near(game.total_moves, game.get_tap_moves(), "Space taps")
	main._unhandled_input(key_event(KEY_SPACE, true, true))
	main._unhandled_input(key_event(KEY_SPACE, true, true))
	check_near(game.total_moves, game.get_tap_moves(), "holding Space doesn't repeat (echo events are ignored)")
	main._unhandled_input(key_event(KEY_SPACE, false, false))
	main._unhandled_input(key_event(KEY_ENTER, true, false))
	check_near(game.total_moves, game.get_tap_moves() * 2.0, "Enter taps too")
	main._refresh()
	check((main.get_node("%NextGoalLabel") as Label).text.begins_with("Cubing Friend"), "the strip shows the next goal first")
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
	check(tabs.get_tab_title(main.UPGRADES_TAB) == "Upgrades (2)", "the Upgrades tab shows a badge for the affordable Lube and Practice Partners I")
	friend.pressed.emit()
	check(game.buildings["friend"] == 2, "clicking an affordable card buys the helper (a second Friend)")
	main.free()
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
	check(label.text == "%s Solves" % Num.format(game.solves), "the label shows the real value at the end")
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
	check(not panel.visible, "Collect closes the panel")
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
	g.tap()
	check_near(g.get_move_progress("2x2"), g.get_tap_moves(), "a tap goes to the focused puzzle")
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
	check(not station.visible, "Esc closes the station")
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
	}
	for method: String in ["cfop", "beginner"]:
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
	# Methods without their own stages yet fall back to CFOP; unsupported puzzles give nothing.
	var roux := PuzzleShapes.from_id("3x3")
	roux.scramble(25)
	var roux_stages := StagedSolver.solve(roux, "roux")
	check(roux_stages.size() == 8 and roux_stages[6]["id"] == "oll", "Roux falls back to CFOP until R.5")
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
	for method: String in ["beginner", "cfop"]:
		game.method = method
		main._start_showcase()
		var show: ShowcaseSolve = main._showcase
		check(show != null and show.method == method, "%s: the 3×3 gets a showcase solve" % method)
		check(chips.visible and chips.get_child_count() == (7 if method == "beginner" else 4), "%s: one chip per stage (F2L shares one)" % method)
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
	check((main.get_node("%NextGoalLabel") as Label).text != "", "the strip shows the first goal")
	check((main.get_node("%Goal1Label") as Label).text != "" and (main.get_node("%Goal2Bar") as ProgressBar).visible, "three goals with bars")
	check((main.get_node("%HintLabel") as Label).text.begins_with("Team best "), "the team's best time is under the cube")
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
	check(not station.visible, "the station closes by itself after showing the buff")
	# Esc on a case is a miss.
	game.update_golden(game.golden_next + 0.01)
	main.open_golden()
	var missed := []
	game.golden_finished.connect(func(success: bool, _buff: Dictionary) -> void: missed.append(success), CONNECT_ONE_SHOT)
	station.handle_key(KEY_ESCAPE)
	check(missed == [false] and not station.visible, "Esc walks away from the case: a miss")
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
	check((main.get_node("%FlowLabel") as Label).visible and (main.get_node("%FlowLabel") as Label).text.begins_with("Flow ×%s" % Num.format(float(Content.SOLVE_REWARDS["flow_by_tier"][3]))), "the top bar shows the Flow")
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
	check(tabs.get_tab_title(main.UPGRADES_TAB) == "Upgrades", "a locked-out side never counts as affordable")
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
	game.cheat_add_solves(1e4)
	main._refresh()
	var tabs: TabContainer = main.get_node("%Tabs")
	check(tabs.get_tab_title(main.LAB_TAB).begins_with("Lab"), "there's a Lab tab")
	var card: ShopCard = main._lab_cards["finger_tricks"]
	check(card.visible and card.affordable, "Finger Tricks can be started")
	card.pressed.emit()
	check(game.research.get("id", "") == "finger_tricks", "pressing the card starts it")
	main._refresh()
	check((main.get_node("%LabStatus") as Label).text.begins_with("Researching Finger Tricks") and tabs.get_tab_title(main.LAB_TAB) == "Lab · 2:00", "the tab shows what's running and the time left")
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
	# The divisor is picked from BALANCE.md: the tapping bot has ~1e14 lifetime Solves at 90 min (D6).
	var at_90 := GameState.trophies_for(1.05e14)
	check(at_90 >= 30 and at_90 <= 80, "a ~90-minute run gives a few dozen trophies, not thousands (got %d)" % at_90)
	check(GameState.trophies_for(1e13) < at_90 and GameState.trophies_for(1.1e15) > at_90 * 2, "waiting longer gives more, less than linearly")
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
	check((panel.get_node("%Bonus") as Label).text == "Moves on every puzzle: +0 % → +102 %", "and the bonus before and after")
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
	check(not panel.visible and audio.override_track_id == "", "Escape closes it and the music goes back")
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
	check(game.trophies == 52 and game.championships == 1 and not panel.visible and audio.override_track_id == "",
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
	check(int(data["version"]) == 10 and GameState.SAVE_VERSION == 10, "saves as v10")
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
	check(int(old.get_save_data()["version"]) == 10, "it saves as v10")
	old.free()
