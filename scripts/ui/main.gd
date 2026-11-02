extends Control
## Main screen. Reads numbers from the Game autoload and turns clicks into Game calls.
## Keep game rules out of this file; they belong in scripts/autoload/game.gd.

const UI_REFRESH_INTERVAL := 0.1
const MAX_VISUAL_MOVES_PER_SECOND := 12.0

@onready var solves_label: Label = %SolvesLabel
@onready var rate_label: Label = %RateLabel
@onready var puzzle_view: PuzzleView3D = %PuzzleView
@onready var move_ticker: Label = %MoveTicker
@onready var graphics_button: Button = %GraphicsButton
@onready var solve_progress: ProgressBar = %SolveProgress
@onready var progress_label: Label = %ProgressLabel
@onready var tap_button: Button = %TapButton
@onready var stats_label: Label = %StatsLabel
@onready var helper_list: VBoxContainer = %HelperList
@onready var upgrade_list: VBoxContainer = %UpgradeList
@onready var upgrade_empty: Label = %UpgradeEmpty
@onready var offline_dialog: AcceptDialog = %OfflineDialog

var _helper_buttons: Dictionary = {}   ## building id -> Button
var _upgrade_buttons: Dictionary = {}  ## upgrade id -> Button
var _refresh_timer := 0.0
var _visual_move_timer := 0.0


func _ready() -> void:
	tap_button.pressed.connect(_on_tap_pressed)
	puzzle_view.tapped.connect(_on_tap_pressed)
	graphics_button.pressed.connect(_on_graphics_pressed)
	_apply_graphics(GraphicsConfig.load_quality())
	Game.solved.connect(_on_solved)
	Game.purchased.connect(_on_purchased)
	Game.state_reset.connect(_refresh)
	_build_shop()
	_refresh()
	_show_offline_report()
	tap_button.grab_focus()


func _process(delta: float) -> void:
	solve_progress.value = Game.move_progress / Game.get_moves_per_solve()
	var ticker := puzzle_view.ticker_text()
	move_ticker.text = ticker if ticker != "" else " "  # keep the line's height when empty
	_animate_helper_moves(delta)
	_refresh_timer += delta
	if _refresh_timer >= UI_REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F9:
			Game.cheat_add_solves(1000.0)
		KEY_F10:
			Game.wipe_save()


# --- Building the shop -------------------------------------------------------

func _build_shop() -> void:
	for def: Dictionary in Content.BUILDINGS:
		var button := _make_shop_button()
		button.tooltip_text = def["description"]
		button.pressed.connect(Game.buy_building.bind(def["id"]))
		helper_list.add_child(button)
		_helper_buttons[def["id"]] = button
	for def: Dictionary in Content.UPGRADES:
		var button := _make_shop_button()
		button.pressed.connect(Game.buy_upgrade.bind(def["id"]))
		upgrade_list.add_child(button)
		_upgrade_buttons[def["id"]] = button


func _make_shop_button() -> Button:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 64)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE  # keeps Space/Enter on the Turn button
	return button


# --- Refreshing --------------------------------------------------------------

func _refresh() -> void:
	solves_label.text = "%s Solves" % Num.format(Game.solves)
	rate_label.text = "%s moves/s  ·  %s solves/s" % [
		Num.format(Game.get_moves_per_second()),
		Num.format(Game.get_solves_per_second()),
	]
	progress_label.text = "%s / %s moves to next solve" % [
		Num.format(Game.move_progress),
		Num.format(Game.get_moves_per_solve()),
	]
	tap_button.text = "Turn the cube  (+%s)" % Num.format(Game.get_tap_moves())
	stats_label.text = "Lifetime: %s solves  ·  %s moves" % [
		Num.format(Game.total_solves),
		Num.format(Game.total_moves),
	]

	for def: Dictionary in Content.BUILDINGS:
		var id: String = def["id"]
		var button: Button = _helper_buttons[id]
		var cost := Game.get_building_cost(id)
		button.visible = Game.is_building_unlocked(id)
		button.disabled = Game.solves < cost
		button.text = "%s   (owned %d)\n+%s moves/s each  ·  Costs %s Solves" % [
			def["name"], Game.buildings[id], Num.format(Game.get_building_mps(id)), Num.format(cost),
		]

	var any_upgrade_visible := false
	for def: Dictionary in Content.UPGRADES:
		var id: String = def["id"]
		var button: Button = _upgrade_buttons[id]
		var cost := float(def["cost"])
		button.visible = Game.is_upgrade_available(id)
		button.disabled = Game.solves < cost
		button.text = "%s   ·   Costs %s Solves\n%s" % [def["name"], Num.format(cost), def["description"]]
		any_upgrade_visible = any_upgrade_visible or button.visible
	upgrade_empty.visible = not any_upgrade_visible


func _animate_helper_moves(delta: float) -> void:
	var mps := Game.get_moves_per_second()
	puzzle_view.set_speed(mps)
	if mps <= 0.0:
		return
	_visual_move_timer += delta * minf(mps, MAX_VISUAL_MOVES_PER_SECOND)
	while _visual_move_timer >= 1.0:
		_visual_move_timer -= 1.0
		puzzle_view.scramble_step()


func _show_offline_report() -> void:
	var parts: PackedStringArray = []
	if Game.load_notice != "":
		parts.append(Game.load_notice)
	if not Game.offline_report.is_empty():
		parts.append("You were away for %s.\nYour helpers earned %s Solves." % [
			Num.format_duration(Game.offline_report["seconds"]),
			Num.format(Game.offline_report["solves"]),
		])
	if parts.is_empty():
		return
	offline_dialog.dialog_text = "\n\n".join(parts)
	offline_dialog.popup_centered()
	Game.load_notice = ""  # show it once


# --- Signals -----------------------------------------------------------------

func _on_tap_pressed() -> void:
	Game.tap()
	puzzle_view.scramble_step()


func _on_solved(_count: int) -> void:
	puzzle_view.show_solved()


func _on_purchased(_kind: String, _id: String) -> void:
	_refresh()


## Temporary home for Graphics: High / Low until the Settings tab (task 3.4).
func _on_graphics_pressed() -> void:
	var quality := "low" if puzzle_view.graphics_quality == "high" else "high"
	GraphicsConfig.save_quality(quality)
	_apply_graphics(quality)


func _apply_graphics(quality: String) -> void:
	puzzle_view.set_graphics(quality)
	graphics_button.text = "Graphics: %s" % quality.capitalize()
	graphics_button.tooltip_text = "High: smooth edges, rounded pieces, stage glow and shadow.\nLow: faster on older PCs."
