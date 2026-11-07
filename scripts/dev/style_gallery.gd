class_name StyleGallery
extends Control
## The style gallery (task V.0, PLAN §4.7): every UI building block of ui/theme.tres, in every state, on one screen,
## so the look can be tuned and compared without any game state. Not part of the game: nothing in scenes/ or
## scripts/ references it. It never uses the Game/Settings/Audio autoloads by name; the real card scenes
## (ShopCard, UpgradeTile, PerkNode, PuzzleChip) are fed fake views.
##
## Two pages, because the game's logical screen is always 1280×720 (canvas_items stretch):
##   "kit":   type ramp, buttons in every state, tabs, bars, chips, panels
##   "parts": shop cards, upgrade tiles, perk nodes, puzzle chips, a 3D puzzle, the Solve Station timers
## Shot by tools/screenshot.sh with GALLERY=kit|parts|all (FONT=<file> previews another display font).
## Command line (after --): --page kit|parts --out <file.png> [--font <ttf/otf>] [--weight 700]
##
## When you add a type variation to the theme, show it here: test_style_gallery_covers_theme fails until you do.

const PAGES := ["kit", "parts"]
const SETTLE_FRAMES := 20
## Variations that carry the "display" voice (counters, titles, buttons). --font swaps their font, so candidate
## display faces can be compared on the real components (task V.1 picks one).
const DISPLAY_TYPES: Array[StringName] = [&"TitleLabel", &"BigAccentLabel", &"TimerLabel", &"CardOwned",
		&"CardTitle", &"PrimaryButton", &"GoldenButton", &"PopSolve", &"PopTap", &"PerkName"]
## Button-like variations drawn as swatches in each state (a real Button can't be held in "hover" for a shot).
const SWATCH_TYPES: Array[StringName] = [&"Button", &"PrimaryButton", &"SubtleButton", &"GoldenButton", &"ToggleChip"]
const SWATCH_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled"]
## Every text style, with a sample that looks like what the game shows in it.
const TEXT_SAMPLES := [
	[&"TitleLabel", "420 Solves"],
	[&"BigAccentLabel", "+1.25K Solves"],
	[&"SubtitleLabel", "+73 solves/s  ·  258 moves/s"],
	[&"CardTitle", "Cubing Friend"],
	[&"CardLine", "Practices with you after school."],
	[&"CardOwned", "150"],
	[&"CostAffordable", "41 Solves"],
	[&"CostUnaffordable", "15.87K Solves"],
	[&"DimLabel", "Inspection  ·  1 of 73 solves/s"],
	[&"FaintLabel", "Lifetime: 6.00K solves"],
	[&"HintLabel", "Click the cube or press Space: +4 moves"],
	[&"TickerLabel", "R U R' U' F2"],
	[&"GoalLabel", "Practice Partners I — ready"],
	[&"GoalLabelDim", "3×3 Mastery 5  ·  3s"],
	[&"BuffLabel", "Golden Scramble ×3  ·  0:42"],
	[&"FlowLabel", "Flow ×1.5  ·  12 s"],
	[&"ScrambleLabel", "D2 F' R2 U L2 B' R"],
	[&"PerkName", "Team Captain"],
	[&"PopTap", "+4"],
	[&"PopSolve", "+12 Solves"],
]
const TIMER_SAMPLES := [[&"TimerLabel", "12.34"], [&"TimerWaiting", "0.00"], [&"TimerDone", "28.71"],
		[&"TimerGolden", "9.87"]]

var page := "kit"


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	page = String(args.get("page", page))
	if not page in PAGES:
		push_error("Unknown gallery page '%s' (pages: %s)" % [page, ", ".join(PAGES)])
		get_tree().quit(2)
		return
	if args.has("font"):
		_use_display_font(String(args["font"]), int(args.get("weight", "700")))
	build(page)
	if args.has("out"):
		_shoot.call_deferred(String(args["out"]))


## Builds one page. Public so the tests can build every page without a window.
func build(which: String) -> void:
	page = which
	for child in get_children():
		remove_child(child)
		child.queue_free()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.086, 0.094, 0.114)  # the main scene's background
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"PageMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.theme_type_variation = &"ColumnsBox"
	margin.add_child(columns)
	if which == "parts":
		_build_parts(columns)
	else:
		_build_kit(columns)


## Every theme_type_variation this page uses (nodes and swatches), for the coverage test.
func used_variations() -> Dictionary:
	var used := {}
	_collect(self, used)
	return used


# --- Page "kit" ---------------------------------------------------------------------------------------------------

func _build_kit(columns: HBoxContainer) -> void:
	var column := _column(columns, "Type")
	var text := VBoxContainer.new()
	text.theme_type_variation = &"TightBox"
	column.add_child(text)
	for sample: Array in TEXT_SAMPLES:
		text.add_child(_label(sample[1], sample[0]))
	var ticker := RichTextLabel.new()
	ticker.theme_type_variation = &"TickerText"
	ticker.bbcode_enabled = true
	ticker.fit_content = true
	ticker.scroll_active = false
	ticker.text = "R U [b]R'[/b] U'  (TickerText)"
	text.add_child(ticker)

	var controls := _column(columns, "Buttons: normal, hover, pressed, hover+pressed, disabled")
	for type_name in SWATCH_TYPES:
		var row := HBoxContainer.new()
		var name_label := _label(String(type_name), &"FaintLabel")
		name_label.custom_minimum_size = Vector2(104, 0)
		row.add_child(name_label)
		for state: String in SWATCH_STATES:
			row.add_child(_swatch(type_name, state, "Buy" if type_name != &"ToggleChip" else "×10"))
		controls.add_child(row)
	controls.add_child(_heading("Tabs, bars, chips"))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 44)
	for tab_name: String in ["Helpers", "Upgrades (4)", "Puzzles", "Lab"]:
		var empty := Control.new()
		empty.name = tab_name
		tabs.add_child(empty)
	controls.add_child(tabs)
	controls.add_child(_bar(&"", 0.62))
	controls.add_child(_bar(&"GoalBar", 0.35))
	var slider := HSlider.new()
	slider.value = 70
	slider.focus_mode = Control.FOCUS_NONE
	controls.add_child(slider)
	var chips := HBoxContainer.new()
	chips.theme_type_variation = &"StageChipRow"
	for chip: Array in [[&"StageChipDone", "Cross"], [&"StageChipActive", "F2L 2"], [&"StageChip", "OLL"],
			[&"StageChip", "PLL"]]:
		chips.add_child(_label(chip[1], chip[0]))
	controls.add_child(chips)
	var badges := HBoxContainer.new()
	badges.add_child(_label("R", &"KeyHint"))
	badges.add_child(_label("U'", &"KeyHint"))
	badges.add_child(_label("PICK 1", &"ChoiceBadge"))
	controls.add_child(badges)

	var panels := _column(columns, "Panels")
	for panel: Array in [[&"TopBar", "TopBar: the Solves counter"], [&"GoalStrip", "GoalStrip: next goals"],
			[&"SidePanel", "SidePanel: shop / Solve Station"], [&"PuzzleChipPanel", "PuzzleChipPanel"],
			[&"", "PanelContainer (default)"]]:
		panels.add_child(_panel(panel[0], panel[1]))
	var news := PanelContainer.new()
	news.theme_type_variation = &"NewsPanel"
	var news_lines := VBoxContainer.new()
	news_lines.theme_type_variation = &"TightBox"
	news_lines.add_child(_label("Robot set a team record: 0.21 s", &"NewsNew"))
	news_lines.add_child(_label("2×2 mastery reached Lv 5", &"NewsOld"))
	news.add_child(news_lines)
	panels.add_child(news)
	var tiles := HBoxContainer.new()
	for icon: String in ["friend", "club", "robot", "lab"]:
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"IconTile"
		tile.custom_minimum_size = Vector2(56, 56)
		var image := TextureRect.new()
		image.texture = _icon(icon)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.add_child(image)
		tiles.add_child(tile)
	panels.add_child(tiles)
	panels.add_child(_label("IconTile", &"FaintLabel"))


# --- Page "parts" -------------------------------------------------------------------------------------------------

func _build_parts(columns: HBoxContainer) -> void:
	var cards := _column(columns, "Shop cards")
	cards.size_flags_horizontal = Control.SIZE_FILL
	cards.custom_minimum_size = Vector2(420, 0)
	var card_scene: PackedScene = load("res://scenes/shop_card.tscn")
	var card_views := [
		{"icon": _icon("friend"), "title": "Cubing Friend", "line1": "Practices with you after school.",
			"line2": "7.00 s a 3×3  ·  +2 moves/s each", "owned": "15", "cost": "41 Solves", "affordable": true},
		{"icon": _icon("robot"), "title": "Solving Robot", "line1": "Never gets tired.",
			"line2": "0.21 s a 3×3  ·  +66 moves/s each", "owned": "2", "cost": "15.87K Solves", "affordable": false},
		{"icon": _icon("lab"), "title": "Algorithm Lab", "line1": "Researching: Look-ahead",
			"line2": "12m left", "owned": "", "cost": "running", "affordable": false, "active": true},
		{"icon": _icon("locked"), "title": "???", "line1": "A new helper appears at 50.00K Solves",
			"line2": "6.00K / 50.00K", "owned": "", "cost": "", "locked": true},
	]
	for view: Dictionary in card_views:
		var card: Control = card_scene.instantiate()
		cards.add_child(card)
		card.set_view(view)
	cards.add_child(_heading("Solve Station timers"))
	var timers := HBoxContainer.new()
	timers.theme_type_variation = &"ColumnsBox"
	for sample: Array in TIMER_SAMPLES.slice(0, 2):
		timers.add_child(_label(sample[1], sample[0]))
	cards.add_child(timers)
	var timers2 := HBoxContainer.new()
	timers2.theme_type_variation = &"ColumnsBox"
	for sample: Array in TIMER_SAMPLES.slice(2):
		timers2.add_child(_label(sample[1], sample[0]))
	cards.add_child(timers2)

	var middle := _column(columns, "Upgrade tiles: buyable, owned, too dear, pick 1, not picked")
	var grid := GridContainer.new()
	grid.theme_type_variation = &"UpgradeGrid"
	grid.columns = 5
	middle.add_child(grid)
	var tile_scene: PackedScene = load("res://scenes/upgrade_tile.tscn")
	var tile_views := [
		{"icon": _icon("lube"), "title": "Cube Lube", "cost": "15", "affordable": true},
		{"icon": _icon("stackmat"), "title": "Stackmat", "cost": "60", "owned": true},
		{"icon": _icon("magnets"), "title": "Magnets", "cost": "12.00K", "affordable": false},
		{"icon": _icon("speed_practice"), "title": "Speed Practice", "cost": "800", "affordable": true,
			"choice": "Pick one: Speed or Theory"},
		{"icon": _icon("efficient_solving"), "title": "Theory", "cost": "800", "choice": "Pick one",
			"locked_out": true},
	]
	for view: Dictionary in tile_views:
		var tile: Control = tile_scene.instantiate()
		grid.add_child(tile)
		tile.set_view(view)
	middle.add_child(_heading("Perk nodes: owned, buyable, too dear, locked, soon"))
	var perks := HBoxContainer.new()
	perks.theme_type_variation = &"ColumnsBox"
	middle.add_child(perks)
	var perk_scene: PackedScene = load("res://scenes/perk_node.tscn")
	var perk_views := [
		{"icon": _icon("friend"), "title": "Team Captain", "cost": 10, "status": "owned"},
		{"icon": _icon("club"), "title": "Team Spirit", "cost": 15, "status": "available", "affordable": true},
		{"icon": _icon("pro_team"), "title": "Club Founder", "cost": 25, "status": "available", "affordable": false},
		{"icon": _icon("museum"), "title": "Overnight", "cost": 30, "status": "locked"},
		{"icon": _icon("competition"), "title": "Circuit", "cost": 5, "status": "soon"},
	]
	for view: Dictionary in perk_views:
		var perk: Control = perk_scene.instantiate()
		perk.custom_minimum_size = Vector2(108, 100)
		perks.add_child(perk)
		perk.set_view(view)

	middle.add_child(_heading("Stage and puzzle row: running, locked, unlockable"))
	var row := HBoxContainer.new()
	row.theme_type_variation = &"ColumnsBox"
	middle.add_child(row)
	var view: Control = load("res://scenes/puzzle_view_3d.tscn").instantiate()
	view.custom_minimum_size = Vector2(260, 240)
	row.add_child(view)
	var chip_scene: PackedScene = load("res://scenes/puzzle_chip.tscn")
	var running: Control = chip_scene.instantiate()
	row.add_child(running)
	var locked: Control = chip_scene.instantiate()
	row.add_child(locked)
	var buyable: Control = chip_scene.instantiate()
	row.add_child(buyable)
	for chip: Control in [running, locked, buyable]:
		chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	running.show_running("2x2", "2×2")
	running.update_running("0.08 s  ·  40%", 12, 0.4)
	locked.show_locked("4x4", "4×4", "180.0M Solves", false)
	buyable.show_locked("5x5", "5×5", "250.0B Solves", true)


# --- Building blocks ----------------------------------------------------------------------------------------------

func _column(parent: Control, title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.theme_type_variation = &"StackBox"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_heading(title))
	parent.add_child(column)
	return column


func _heading(text: String) -> Label:
	return _label(text.to_upper(), &"FaintLabel")


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


func _panel(variation: StringName, text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = variation
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"CardMargin"
	margin.add_child(_label(text, &"DimLabel"))
	panel.add_child(margin)
	return panel


func _bar(variation: StringName, value: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.theme_type_variation = variation
	bar.max_value = 1.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	return bar


func _swatch(type_name: StringName, state: String, text: String) -> Swatch:
	var swatch := Swatch.new()
	swatch.type_name = type_name
	# Looked up through the Swatch's own variation, theme lookups follow the variation chain (PrimaryButton ->
	# Button) exactly like a real Button does; asked by name alone, Godot wouldn't fall back to the base type.
	if ThemeDB.get_project_theme().get_type_variation_base(type_name) != &"":
		swatch.theme_type_variation = type_name
	swatch.state = state
	swatch.text = text
	return swatch


func _icon(icon_name: String) -> Texture2D:
	return load("res://assets/icons/%s.svg" % icon_name)


## Hidden nodes (a tile's unused Pick-1 badge, a running chip's Unlock button) don't count: they aren't on screen.
func _collect(node: Node, used: Dictionary) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Swatch:
		used[(node as Swatch).type_name] = true
	elif node is Control and (node as Control).theme_type_variation != &"":
		used[(node as Control).theme_type_variation] = true
	for child in node.get_children():
		_collect(child, used)


## Every styled node must be fully on screen, or the shot doesn't really show it: an ERROR fails screenshot.sh.
func _check_on_screen(node: Node, screen: Rect2) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Control and ((node as Control).theme_type_variation != &"" or node is Swatch):
		var control := node as Control
		if not screen.encloses(control.get_global_rect().grow(-0.5)):
			push_error("Gallery '%s': %s (%s) is off screen at %s" % [page, control.name,
					control.theme_type_variation, control.get_global_rect()])
	for child in node.get_children():
		_check_on_screen(child, screen)


## A theme copy whose display variations use another font (candidate previews for V.1). Nothing is saved.
func _use_display_font(path: String, weight: int) -> void:
	var file := FontFile.new()
	if file.load_dynamic_font(path) != OK:
		push_error("Can't load font %s" % path)
		return
	var font := FontVariation.new()
	font.base_font = file
	var server := TextServerManager.get_primary_interface()
	font.variation_opentype = {server.name_to_tag("wght"): weight}
	var preview: Theme = (ThemeDB.get_project_theme() as Theme).duplicate()
	for type_name in DISPLAY_TYPES:
		preview.set_font(&"font", type_name, font)
	theme = preview


func _shoot(out: String) -> void:
	var audio := get_node_or_null("/root/Audio")  # a track still playing at exit is reported as a leak
	if audio != null:
		audio.set("music_enabled", false)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	_check_on_screen(self, get_viewport_rect())
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	if err != OK:
		push_error("Couldn't save %s (%s)" % [out, error_string(err)])
		get_tree().quit(1)
		return
	print("Saved %s (%dx%d, gallery '%s')" % [out, image.get_width(), image.get_height(), page])
	get_tree().quit(0)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	var i := 0
	while i < args.size() - 1:
		if args[i].begins_with("--"):
			parsed[args[i].substr(2)] = args[i + 1]
			i += 2
		else:
			i += 1
	return parsed


## One button style in one state, drawn straight from the theme (a real Button can't be held in "hover").
class Swatch:
	extends Control

	const COLOR_KEYS := {"normal": &"font_color", "hover": &"font_hover_color", "pressed": &"font_pressed_color",
			"hover_pressed": &"font_hover_pressed_color", "disabled": &"font_disabled_color"}

	var type_name: StringName = &"Button"
	var state := "normal"
	var text := ""

	func _get_minimum_size() -> Vector2:
		var box := get_theme_stylebox(StringName(state), type_name)
		var font := get_theme_font(&"font", type_name)
		var font_size := get_theme_font_size(&"font_size", type_name)
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) + box.get_minimum_size()

	func _draw() -> void:
		var box := get_theme_stylebox(StringName(state), type_name)
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var font := get_theme_font(&"font", type_name)
		var font_size := get_theme_font_size(&"font_size", type_name)
		var color := get_theme_color(COLOR_KEYS.get(state, &"font_color"), type_name)
		# Centred in the box's content rect, as a Button does (a thicker bottom margin moves the text up).
		var content := Rect2(box.get_offset(), size - box.get_minimum_size())
		var baseline := content.position.y + (content.size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
		draw_string(font, Vector2(content.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, content.size.x,
				font_size, color)
