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
	view.tapped.connect(func() -> void: taps[0] += 1)
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
	view.tapped.connect(func() -> void: taps[0] += 1)
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
