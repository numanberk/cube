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
