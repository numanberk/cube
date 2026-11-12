extends SceneTree
## Renders the boot splash (task V.9): assets/images/brand/icon.svg above wordmark.svg, centred on a transparent
## image (project.godot's boot_splash/bg_color is the palette's bg behind it). Re-run after tools/make_wordmark.py:
##   godot --headless --path . -s res://tools/make_splash.gd
## With `-- --preview <dir>` it also writes the icon and wordmark alone as PNGs there (to look at them).

const SIZE := Vector2i(720, 400)
const ICON_PX := 176
const WORDMARK_W := 440
const GAP := 18


func _initialize() -> void:
	var icon := _svg("res://assets/images/brand/icon.svg", ICON_PX / 256.0)
	var wordmark_source := FileAccess.get_file_as_string("res://assets/images/brand/wordmark.svg")
	var natural := Image.new()
	natural.load_svg_from_string(wordmark_source, 1.0)
	var wordmark := _svg("res://assets/images/brand/wordmark.svg", float(WORDMARK_W) / natural.get_width())
	var splash := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	var top := (SIZE.y - icon.get_height() - GAP - wordmark.get_height()) / 2
	splash.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), Vector2i((SIZE.x - icon.get_width()) / 2, top))
	splash.blend_rect(wordmark, Rect2i(Vector2i.ZERO, wordmark.get_size()),
			Vector2i((SIZE.x - wordmark.get_width()) / 2, top + icon.get_height() + GAP))
	splash.save_png("res://assets/images/brand/splash.png")
	print("Wrote res://assets/images/brand/splash.png")
	var args := OS.get_cmdline_user_args()
	var at := args.find("--preview")
	if at >= 0 and at + 1 < args.size():
		icon.save_png(args[at + 1].path_join("icon.png"))
		wordmark.save_png(args[at + 1].path_join("wordmark.png"))
	quit(0)


func _svg(path: String, scale: float) -> Image:
	var image := Image.new()
	var err := image.load_svg_from_string(FileAccess.get_file_as_string(path), scale)
	if err != OK:
		push_error("Could not read %s" % path)
	return image
