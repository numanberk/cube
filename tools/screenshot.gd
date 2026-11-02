extends Node
## Takes one screenshot of the main scene in a preset game state, then quits.
## Run through tools/screenshot.sh, which passes:
##   -- --preset <name> --out <file.png> [--puzzle 5x5] [--pose turn|solved] [--graphics high|low] [--tab 1] [--juice 1] [--buy 10|-1]
## Preset "bench" is special: the late-game state on a 7×7 with the economy running (speed mode, a solve every
## frame), BENCH_FRAMES frames at each graphics quality, logging the average and worst frame time.
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
	var bench := preset == "bench"
	if bench:
		preset = "late"
		args["puzzle"] = "7x7"
	if out == "" or not Presets.PRESETS.has(preset):
		push_error("Usage: -- --preset <%s> --out <file.png>" % "|".join(Presets.PRESETS.keys()))
		_quit(2)
		return

	Game.persistence_enabled = false  # never write a save from here
	Game.apply_save_data(Presets.PRESETS[preset], Time.get_unix_time_from_system())
	Game.set_process(bench)  # freeze the economy so the numbers match the preset (the bench keeps it running)
	seed(RANDOM_SEED)
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	var puzzle: String = args.get("puzzle", "")
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	if puzzle != "":
		view.set_puzzle(puzzle)
	if args.has("buy"):
		main.set_buy_amount(int(args["buy"]))
	if args.has("tab"):
		(main.get_node("%Tabs") as TabContainer).current_tab = int(args["tab"])
	var graphics: String = args.get("graphics", "")
	if graphics != "":
		view.set_graphics(graphics)
	if bench:
		for quality: String in ["low", "high"]:  # high last, so the saved PNG shows it
			await _bench(view, quality)
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
	print("Saved %s (%dx%d, preset '%s')" % [out, image.get_width(), image.get_height(), "bench" if bench else preset])
	_quit(0)


## Stops sounds and gives the audio thread a moment, so no playback is reported as leaked at exit.
func _quit(code: int) -> void:
	Audio.stop_all()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(code)


func _bench(view: PuzzleView3D, quality: String) -> void:
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
	print("Bench %s: %.2f ms/frame average (%.0f fps), worst %.2f ms, %d frames, %s, %s pieces x %d triangles, speed mode %s" % [
		quality, average_ms, 1000.0 / average_ms, worst / 1000.0, BENCH_FRAMES, view.puzzle_id,
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
