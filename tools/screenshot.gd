extends Node
## Takes one screenshot of the main scene in a preset game state, then quits.
## Run through tools/screenshot.sh, which passes:
##   -- --preset <name> --out <file.png> [--puzzle 5x5] [--pose turn|solved] [--graphics high|low] [--tab 1] [--juice 1] [--buy 10|-1] [--settings 1] [--solve inspecting|solving|done] [--showcase <moves>] [--method beginner|cfop|...] [--keys cstimer|simple] [--news 1] [--golden glow|case|buff] [--flow 1]
## Presets "bench" and "bench_row" are special: the row5 state (all cubes, late-game helpers) with the economy running
## (speed mode, solves every frame), BENCH_FRAMES frames at each graphics quality, logging the average and worst frame
## time. "bench" runs only the 7×7 (one 3D view); "bench_row" runs all five cubes (the big 7×7 + four small views).
## Task 4.3a: bench_row must stay within 1.5× of bench.
## Not part of the game: never reference this from scenes/ or scripts/.

const Presets := preload("res://tools/screenshot_presets.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const SETTLE_FRAMES := 30  ## lets layout, the cube's punch animation and the UI refresh settle
const RANDOM_SEED := 1     ## same cube colours every run, so before/after shots compare
const BENCH_FRAMES := 600
const BENCH_WARMUP := 60


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var preset: String = args.get("preset", "fresh")
	var out: String = args.get("out", "")
	var bench := preset in ["bench", "bench_row"]
	var single_puzzle := preset == "bench"
	var bench_name := preset
	if bench:
		preset = "row5"
	if out == "" or not Presets.PRESETS.has(preset):
		push_error("Usage: -- --preset <%s> --out <file.png>" % "|".join(Presets.PRESETS.keys()))
		_quit(2)
		return

	Game.persistence_enabled = false  # never write a save from here
	Settings.persistence_enabled = false  # nor settings
	Audio.music_enabled = false  # nothing to hear, and a track still playing at exit is reported as a leak
	var data: Dictionary = Presets.PRESETS[preset].duplicate(true)
	var now := Time.get_unix_time_from_system()
	if data.has("away_seconds"):
		data["saved_at"] = now - float(data["away_seconds"])
	if bench and single_puzzle:
		data["puzzles"] = {"unlocked": ["7x7"], "progress": {}, "focus": "7x7", "split": {"7x7": 1.0}}
	Game.apply_save_data(data, now)
	if args.has("method"):  # e.g. a Beginner showcase solve on a preset that has CFOP
		Game.method = String(args["method"])
	Game.set_process(bench)  # freeze the economy so the numbers match the preset (the bench keeps it running)
	seed(RANDOM_SEED)
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	var puzzle: String = args.get("puzzle", "")
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	if puzzle != "":
		view.set_puzzle(puzzle)
		main._start_showcase(puzzle)
	if args.has("settings"):
		main.get_node("%SettingsPanel").open()
	if args.has("keys"):  # the Solve Station's key layout: cstimer | simple
		Settings.set_value("solve_keys", String(args["keys"]))
	if args.has("solve"):
		_stage_solve(main.get_node("%SolveStation"), String(args["solve"]), puzzle if puzzle != "" else "3x3")
	if args.has("buy"):
		main.set_buy_amount(int(args["buy"]))
	if args.has("tab"):
		(main.get_node("%Tabs") as TabContainer).current_tab = int(args["tab"])
	var graphics: String = args.get("graphics", "")
	if graphics != "":
		view.set_graphics(graphics)
	if bench:
		for quality: String in ["low", "high"]:  # high last, so the saved PNG shows it
			await _bench(view, quality, bench_name)
	if args.has("news"):  # a few typical news lines, through the real feed
		var feed: NewsFeed = main.news
		feed.on_solves_milestone(1000.0)
		feed.on_helper_best_time("robot", "3x3", 0.21, true, 2)
		feed.on_time_tier("3x3", "Robot record pace", 0.21)
		feed.on_mastery_level_up("2x2", 5)
		feed.on_hand_pb("3x3", true, [5], 8.77)
		feed.on_helper_best_time("club", "3x3", 0.87, false, 8)
		for i in 10:
			feed.advance(10.0)
		main._show_news()
	if args.has("flow"):  # S.3: Flow running after a Gold hand solve
		Game.record_hand_solve("3x3", 84.2, "", 58)
		Game.flow["left"] = 105.0
		main._refresh_golden()
	if args.has("golden"):  # Golden Scramble: glow (sticker + button) | case (the 10 s case open) | buff (Frenzy running)
		var mode := String(args["golden"])
		Game.golden_rng.seed = RANDOM_SEED
		if mode == "buff":
			Game._apply_golden_buff(Content.GOLDEN["buffs"][0])
			Game.buff["left"] = 24.0
		else:
			Game.golden_next = 0.0
			Game.update_golden(0.01)
			Game.golden_glow_left = 9.0
			if mode == "case":
				main.open_golden()
				Game.golden_attempt_left = 7.4
		main._refresh_golden()
	if args.has("showcase"):  # the showcase solve held N moves in
		main.pose_showcase(int(args["showcase"]))
	var pose: String = args.get("pose", "")
	if pose != "":
		for i in SETTLE_FRAMES:  # let the starting animations finish first
			await get_tree().process_frame
		view.pose(pose)

	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	if args.has("juice"):  # a few taps and a solve, caught mid-animation
		var center := view.get_global_rect().get_center()
		for offset: Vector2 in [Vector2(-60, -20), Vector2(40, 30), Vector2(90, -50)]:
			main._on_tap_pressed(center + offset)
		main._pending_solve_value = 5.0
		main._pop_solves(0.0)
		for i in 8:
			await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	if err != OK:
		push_error("Could not write %s: %s" % [out, error_string(err)])
		_quit(1)
		return
	print("Saved %s (%dx%d, preset '%s')" % [out, image.get_width(), image.get_height(), bench_name if bench else preset])
	_quit(0)


## The Solve Station in a repeatable moment: "inspecting" (9 s left), "solving" (half way, clock running) or "done"
## (just solved, with a few earlier times in the list). The solve is the scramble undone, turned at a steady pace.
func _stage_solve(station: Node, mode: String, puzzle: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = RANDOM_SEED
	station.open(puzzle)
	station.frozen_now = 100.0
	station.new_attempt(rng)
	var session: SolveSession = station.session
	if mode != "inspecting":
		for t: float in [71.84, 64.02, 58.77, 82.41, 66.36, 61.95, 69.48]:  # earlier solves at our player's pace (~1:00)
			Game.record_hand_solve(puzzle, t, "+2" if t == 82.41 else "", 58)
	if mode == "inspecting":
		station.frozen_now = 106.2
		station.handle_key(KEY_SEMICOLON)  # a y rotation during inspection
		return
	var solution := session.model.inverse_sequence(session.scramble)
	var now := 108.0  # 8 s of inspection
	var count := solution.size() if mode == "done" else solution.size() / 2
	for i in count:
		session.turn(solution[i], now)
		station.get_node("%View").turn(solution[i])
		now += 2.3
	station.frozen_now = now - 2.3 if mode == "done" else now + 0.2
	if mode == "done":
		var result: Dictionary = session.results.back()
		station.last_info = Game.record_hand_solve(puzzle, float(result["time"]), String(result["penalty"]), int(result["moves"]))
		station.get_node("%View").flash()
	station._refresh()


## Stops sounds and gives the audio thread a moment, so no playback is reported as leaked at exit.
func _quit(code: int) -> void:
	Game.set_process(false)
	Audio.shut_down()
	for i in 6:  # the audio thread releases stopped sound effects on its next mixes (slower under a heavy bench)
		await get_tree().create_timer(0.1).timeout
	get_tree().quit(code)


func _bench(view: PuzzleView3D, quality: String, bench_name: String) -> void:
	view.set_graphics(quality)
	for i in BENCH_WARMUP:
		await get_tree().process_frame
	var started := Time.get_ticks_usec()
	var previous := started
	var worst := 0
	for i in BENCH_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - previous)
		previous = now
	var average_ms := (previous - started) / 1000.0 / BENCH_FRAMES
	print("Bench %s %s: %.2f ms/frame average (%.0f fps), worst %.2f ms, %d frames, %s, %s pieces x %d triangles, speed mode %s" % [
		bench_name, quality, average_ms, 1000.0 / average_ms, worst / 1000.0, BENCH_FRAMES, view.puzzle_id,
		view.model.piece_count(), view.body_triangles(), "on" if view.speed_mode else "off",
	])


func _parse_args(user_args: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < user_args.size():
		var arg := user_args[i]
		if arg.begins_with("--") and i + 1 < user_args.size():
			result[arg.trim_prefix("--")] = user_args[i + 1]
			i += 2
		else:
			i += 1
	return result
