extends Node
## Takes one screenshot of the main scene in a preset game state, then quits.
## Run through tools/screenshot.sh, which passes:  -- --preset <name> --out <file.png> [--puzzle 5x5] [--pose turn|solved]
## Not part of the game: never reference this from scenes/ or scripts/.

const Presets := preload("res://tools/screenshot_presets.gd")
const MAIN_SCENE := preload("res://scenes/main.tscn")
const SETTLE_FRAMES := 30  ## lets layout, the cube's punch animation and the UI refresh settle
const RANDOM_SEED := 1     ## same cube colours every run, so before/after shots compare


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var preset: String = args.get("preset", "fresh")
	var out: String = args.get("out", "")
	if out == "" or not Presets.PRESETS.has(preset):
		push_error("Usage: -- --preset <%s> --out <file.png>" % "|".join(Presets.PRESETS.keys()))
		get_tree().quit(2)
		return

	Game.persistence_enabled = false  # never write a save from here
	Game.apply_save_data(Presets.PRESETS[preset], Time.get_unix_time_from_system())
	Game.set_process(false)  # freeze the economy so the numbers match the preset exactly
	seed(RANDOM_SEED)
	var main := MAIN_SCENE.instantiate()
	add_child(main)
	var puzzle: String = args.get("puzzle", "")
	var view: PuzzleView3D = main.get_node("%PuzzleView")
	if puzzle != "":
		view.set_puzzle(puzzle)
	var pose: String = args.get("pose", "")
	if pose != "":
		for i in SETTLE_FRAMES:  # let the starting animations finish first
			await get_tree().process_frame
		view.pose(pose)

	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	if err != OK:
		push_error("Could not write %s: %s" % [out, error_string(err)])
		get_tree().quit(1)
		return
	print("Saved %s (%dx%d, preset '%s')" % [out, image.get_width(), image.get_height(), preset])
	get_tree().quit(0)


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
