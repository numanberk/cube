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
	check_near(g.get_moves_per_solve(), 8.0 * 0.7, "CFOP cuts moves per solve by 30%")
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
	check_near(goal["missing"], 5.0, "it says how many Solves are missing")
	check(is_inf(float(goal["seconds"])), "with no helpers the time is unknown (tap to get there)")
	g.cheat_add_solves(5.0)
	check_near(g.get_next_goal()["missing"], 0.0, "with enough Solves it's ready to buy")
	g.buy_building("friend")
	goal = g.get_next_goal()
	check(goal["id"] == "lube", "next is the cheapest new thing (Cube Lube, 15)")
	check(float(goal["seconds"]) > 0.0 and not is_inf(float(goal["seconds"])), "with a helper there's a time estimate")
	g.cheat_add_solves(1e12)
	for def: Dictionary in Content.BUILDINGS:
		g.buy_building(def["id"])
	for def: Dictionary in Content.UPGRADES:
		g.buy_upgrade(def["id"])
	goal = g.get_next_goal()
	check(goal["kind"] == "puzzle" and goal["id"] == "3x3", "with every helper and upgrade owned it aims at the next puzzle")
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
	check((main.get_node("%NextGoalLabel") as Label).text.begins_with("Next: Cubing Friend"), "the strip shows the next goal")
	main.free()
	game.reset_state()


# --- Shop cards (task 2.3) ---------------------------------------------------------

func test_content_icons_exist() -> void:
	for def: Dictionary in Content.BUILDINGS + Content.UPGRADES:
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
	check(friend.visible and not friend.affordable and friend.disabled, "fresh: the Friend card shows but isn't affordable")
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
	check(tabs.get_tab_title(main.UPGRADES_TAB) == "Upgrades (1)", "the Upgrades tab shows a badge for the affordable Lube")
	friend.pressed.emit()
	check(game.buildings["friend"] == 1, "clicking an affordable card buys the helper")
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
	check(not main._upgrade_tiles["roux"].visible, "upgrades far out of reach stay hidden")
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
	check((main.get_node("%PuzzleView") as PuzzleView3D).speed_mode, "the puzzle is in speed mode")
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
	g.cheat_add_solves(150.0)
	g.unlock_puzzle("3x3")
	check(g.get_unlocked_track_ids() == (["practice_room", "first_sub_20"] as Array[String]), "unlocking the 3x3 unlocks its track")
	check(g.get_track_for_puzzle("3x3") == "first_sub_20", "3x3's track is First Sub-20")
	check(g.get_track_for_puzzle("4x4") == "", "a track without a file isn't offered")
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

func test_bulk_buying() -> void:
	var g := new_game()
	var one_by_one := 0.0
	for i in 10:
		one_by_one += ceilf(5.0 * pow(1.15, i))
	check_near(g.get_building_cost_for("friend", 10), one_by_one, "x10 costs the same as ten single buys")
	check_near(g.get_building_cost_for("friend", 1), g.get_building_cost("friend"), "x1 cost = the normal cost")
	g.cheat_add_solves(one_by_one - 1.0)
	check(g.buy_buildings("friend", 10) == 0, "x10 with one Solve too few buys nothing")
	check_near(g.solves, one_by_one - 1.0, "...and spends nothing")
	g.cheat_add_solves(1.0)
	check(g.buy_buildings("friend", 10) == 10, "x10 with exactly enough buys 10")
	check_near(g.solves, 0.0, "...and costs exactly the sum")
	check(g.buildings["friend"] == 10, "owning 10 Friends now")
	check(g.get_max_affordable("friend") == 0, "Max with no Solves = 0")
	check(g.buy_buildings("friend", GameState.BUY_MAX) == 0, "buying Max with no Solves buys nothing")
	g.cheat_add_solves(1000.0)
	var max_count := g.get_max_affordable("friend")
	var max_cost := g.get_building_cost_for("friend", max_count)
	check(max_count > 0 and max_cost <= 1000.0 and g.get_building_cost_for("friend", max_count + 1) > 1000.0,
			"Max is the most you can afford (one more would be too many)")
	check(g.buy_buildings("friend", GameState.BUY_MAX) == max_count, "buying Max buys that many")
	check_near(g.solves, 1000.0 - max_cost, "...for exactly their cost")
	check(g.solves < g.get_building_cost("friend"), "what's left can't buy another")
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
	g.cheat_add_solves(150.0)
	var focus_events := [0]
	g.focus_changed.connect(func(_id: String) -> void: focus_events[0] += 1)
	check(g.unlock_puzzle("3x3"), "150 Solves unlock the 3x3")
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
	check_near(g.get_puzzle_moves_per_second("2x2") + g.get_puzzle_moves_per_second("3x3"), g.get_moves_per_second(), "per-puzzle moves/s add up")
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
	game.cheat_add_solves(150.0)
	main._refresh()
	check(not locked._unlock.disabled, "with 150 Solves the Unlock button is enabled")
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
	game.cheat_add_solves(200.0)
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
