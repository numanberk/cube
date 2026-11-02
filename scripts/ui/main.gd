extends Control
## Main screen. Reads numbers from the Game autoload and turns clicks into Game calls.
## Keep game rules out of this file; they belong in scripts/autoload/game.gd.

const UI_REFRESH_INTERVAL := 0.1
const MAX_VISUAL_MOVES_PER_SECOND := 12.0
const TAP_ACTION := &"tap"  ## Space / Enter (project.godot input map); held keys don't repeat
const MENU_GRAPHICS_HIGH := 0
const MENU_GRAPHICS_LOW := 1
const UPGRADES_TAB := 1
const SOLVE_POP_INTERVAL := 0.25   ## at most ~4 "+X Solves" pops a second, however many solves happen
const BURST_INTERVAL := 0.5
const COUNTER_EASE := 12.0         ## how fast the Solves counter catches up (higher = faster)
const ShopCardScene := preload("res://scenes/shop_card.tscn")
const UpgradeTileScene := preload("res://scenes/upgrade_tile.tscn")

@onready var solves_label: Label = %SolvesLabel
@onready var rate_label: Label = %RateLabel
@onready var puzzle_view: PuzzleView3D = %PuzzleView
@onready var move_ticker: Label = %MoveTicker
@onready var hint_label: Label = %HintLabel
@onready var settings_button: MenuButton = %SettingsButton
@onready var next_goal_label: Label = %NextGoalLabel
@onready var solve_progress: ProgressBar = %SolveProgress
@onready var progress_label: Label = %ProgressLabel
@onready var stats_label: Label = %StatsLabel
@onready var helper_list: VBoxContainer = %HelperList
@onready var upgrade_list: GridContainer = %UpgradeList
@onready var tabs: TabContainer = %Tabs
@onready var fx: FxLayer = %FxLayer
@onready var buy_one: Button = %BuyOne
@onready var buy_ten: Button = %BuyTen
@onready var buy_max: Button = %BuyMax
@onready var upgrade_empty: Label = %UpgradeEmpty
@onready var offline_dialog: AcceptDialog = %OfflineDialog

var _helper_cards: Dictionary = {}    ## building id -> ShopCard
var _upgrade_tiles: Dictionary = {}   ## upgrade id -> UpgradeTile
var _refresh_timer := 0.0
var _visual_move_timer := 0.0
var _shown_solves := 0.0          ## what the counter shows; eases towards Game.solves
var _pending_solve_value := 0.0   ## Solves earned since the last "+X Solves" pop
var _solve_pop_timer := 0.0
var _burst_timer := 0.0
var _buy_amount := 1               ## 1, 10 or GameState.BUY_MAX (the ×1 / ×10 / Max toggle)
var _revealed: Dictionary = {}    ## helper ids already shown unlocked (a newly revealed one plays the unlock sound)


func _ready() -> void:
	puzzle_view.tapped.connect(_on_tap_pressed)
	_build_settings_menu()
	buy_one.pressed.connect(set_buy_amount.bind(1))
	buy_ten.pressed.connect(set_buy_amount.bind(10))
	buy_max.pressed.connect(set_buy_amount.bind(GameState.BUY_MAX))
	_apply_graphics(GraphicsConfig.load_quality())
	Game.solved.connect(_on_solved)
	Game.purchased.connect(_on_purchased)
	Game.state_reset.connect(_on_state_reset)
	_shown_solves = Game.solves
	_build_shop()
	for def: Dictionary in Content.BUILDINGS:
		if Game.is_building_unlocked(def["id"]):
			_revealed[def["id"]] = true  # already known at start: no sound
	_refresh()
	_show_offline_report()


func _process(delta: float) -> void:
	solve_progress.value = Game.move_progress / Game.get_moves_per_solve()
	var ticker := puzzle_view.ticker_text()
	move_ticker.text = ticker if ticker != "" else " "  # keep the line's height when empty
	_animate_helper_moves(delta)
	_animate_counter(delta)
	_pop_solves(delta)
	_refresh_timer += delta
	if _refresh_timer >= UI_REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Space / Enter tap from anywhere. allow_echo = false: holding the key down doesn't repeat (PLAN: no hold-to-repeat).
	if event.is_action_pressed(TAP_ACTION, false):
		_on_tap_pressed()
		get_viewport().set_input_as_handled()
		return
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
		var card: ShopCard = ShopCardScene.instantiate()
		card.tooltip_text = def["description"]
		card.pressed.connect(_on_helper_card_pressed.bind(def["id"]))
		helper_list.add_child(card)
		_helper_cards[def["id"]] = card
	for def: Dictionary in Content.UPGRADES:
		var tile: UpgradeTile = UpgradeTileScene.instantiate()
		tile.pressed.connect(Game.buy_upgrade.bind(def["id"]))
		upgrade_list.add_child(tile)
		_upgrade_tiles[def["id"]] = tile


# --- Refreshing --------------------------------------------------------------

func _refresh() -> void:
	rate_label.text = "+%s solves/s   ·   %s moves/s" % [
		Num.format(Game.get_solves_per_second()),
		Num.format(Game.get_moves_per_second()),
	]
	progress_label.text = "%s / %s moves to next solve" % [
		Num.format(Game.move_progress),
		Num.format(Game.get_moves_per_solve()),
	]
	var tap_moves := Game.get_tap_moves()
	hint_label.text = "Click the cube or press Space: +%s %s   ·   drag to look around" % [
		Num.format(tap_moves), "move" if is_equal_approx(tap_moves, 1.0) else "moves",
	]
	next_goal_label.text = _next_goal_text(Game.get_next_goal())
	Audio.set_music_context(Game.get_unlocked_track_ids(), Game.get_track_for_puzzle(Game.get_focused_puzzle_id()))
	stats_label.text = "Lifetime: %s solves  ·  %s moves" % [
		Num.format(Game.total_solves),
		Num.format(Game.total_moves),
	]

	_refresh_helper_cards()
	_refresh_upgrade_tiles()


## Unlocked helpers show as full cards; the first locked one shows as a "???" card with its requirement
## (so there's always a visible next target); the rest stay hidden.
func _refresh_helper_cards() -> void:
	var shown_locked := false
	for def: Dictionary in Content.BUILDINGS:
		var id: String = def["id"]
		var card: ShopCard = _helper_cards[id]
		if Game.is_building_unlocked(id):
			if not _revealed.has(id):
				_revealed[id] = true
				Audio.play_unlock()
			var owned: int = Game.buildings[id]
			var each := Game.get_building_mps(id)
			var count := _buy_count(id)
			var cost := Game.get_building_cost_for(id, count)
			var rate := "+%s moves/s each" % Num.format(each)
			if owned > 0:
				rate += "  ·  +%s/s total" % Num.format(each * owned)
			card.visible = true
			card.set_view({
				"icon": Content.icon(def["icon"]), "title": def["name"], "line1": def["description"], "line2": rate,
				"owned": str(owned), "affordable": Game.solves >= cost,
				"cost": "%s Solves" % Num.format(cost) if _buy_amount == 1 else "×%d  ·  %s Solves" % [count, Num.format(cost)],
			})
		elif not shown_locked:
			shown_locked = true
			var unlock_at := Game.get_building_unlock_at(id)
			card.visible = true
			card.set_view({
				"icon": Content.icon(Content.LOCKED_ICON), "title": "???",
				"line1": "A new helper appears at %s lifetime Solves" % Num.format(unlock_at),
				"line2": "%s / %s" % [Num.format(Game.total_solves), Num.format(unlock_at)],
				"owned": "", "cost": "", "locked": true,
			})
		else:
			card.visible = false


## How many copies of a helper the current toggle means (Max with nothing affordable shows 1, unaffordable).
func _buy_count(id: String) -> int:
	if _buy_amount == GameState.BUY_MAX:
		return maxi(1, Game.get_max_affordable(id))
	return _buy_amount


## The ×1 / ×10 / Max toggle (1, 10 or GameState.BUY_MAX).
func set_buy_amount(amount: int) -> void:
	_buy_amount = amount
	buy_one.set_pressed_no_signal(amount == 1)
	buy_ten.set_pressed_no_signal(amount == 10)
	buy_max.set_pressed_no_signal(amount == GameState.BUY_MAX)
	_refresh()


func _on_helper_card_pressed(id: String) -> void:
	Game.buy_buildings(id, _buy_amount)


## Upgrades are a grid of icon tiles (details in each tile's tooltip): ones you can buy, then a dimmer "Owned" tile for
## each one bought. The tab title shows how many are affordable.
func _refresh_upgrade_tiles() -> void:
	var any_visible := false
	var affordable_count := 0
	for def: Dictionary in Content.UPGRADES:
		var id: String = def["id"]
		var tile: UpgradeTile = _upgrade_tiles[id]
		var cost := float(def["cost"])
		var owned: bool = Game.upgrades.has(id)
		tile.visible = owned or Game.is_upgrade_available(id)
		if not tile.visible:
			continue
		any_visible = true
		var can_buy := not owned and Game.solves >= cost
		if can_buy:
			affordable_count += 1
		tile.set_view({
			"icon": Content.icon(def["icon"]), "title": def["name"], "description": def["description"],
			"cost": Num.format(cost), "affordable": can_buy, "owned": owned,
		})
	# Buyable upgrades first (in content order), then the owned ones.
	var index := 0
	for owned_pass: bool in [false, true]:
		for def: Dictionary in Content.UPGRADES:
			if Game.upgrades.has(def["id"]) == owned_pass:
				upgrade_list.move_child(_upgrade_tiles[def["id"]], index)
				index += 1
	upgrade_empty.visible = not any_visible
	tabs.set_tab_title(UPGRADES_TAB, "Upgrades (%d)" % affordable_count if affordable_count > 0 else "Upgrades")


## The Solves counter counts up smoothly instead of jumping; spending snaps it down at once.
func _animate_counter(delta: float) -> void:
	var target := Game.solves
	if target <= _shown_solves or absf(target - _shown_solves) <= maxf(0.5, target * 0.002):
		_shown_solves = target
	else:
		_shown_solves = lerpf(_shown_solves, target, 1.0 - exp(-delta * COUNTER_EASE))
	solves_label.text = "%s Solves" % Num.format(floorf(_shown_solves) if _shown_solves < target else _shown_solves)


## "+X Solves" rising from the puzzle plus a particle burst, rate-limited so fast play stays readable.
func _pop_solves(delta: float) -> void:
	_solve_pop_timer -= delta
	_burst_timer -= delta
	if _pending_solve_value <= 0.0 or _solve_pop_timer > 0.0:
		return
	var center := puzzle_view.get_global_rect().get_center()
	fx.pop("+%s Solves" % Num.format(_pending_solve_value), center - Vector2(0.0, puzzle_view.size.y * 0.25), &"PopSolve")
	_pending_solve_value = 0.0
	_solve_pop_timer = SOLVE_POP_INTERVAL
	if _burst_timer <= 0.0:
		fx.burst(center)
		_burst_timer = BURST_INTERVAL


func _next_goal_text(goal: Dictionary) -> String:
	if goal.is_empty():
		return "Next: keep solving"
	var name: String = ("another " if goal["more"] else "") + String(goal["name"])
	if float(goal["missing"]) <= 0.0:
		return "Next: %s  —  ready to buy!" % name
	var eta := "tap to get there" if is_inf(float(goal["seconds"])) else "about %s" % Num.format_duration(goal["seconds"])
	return "Next: %s  ·  %s more Solves  ·  %s" % [name, Num.format(goal["missing"]), eta]


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

## A tap from a click (`at` = where, global) or the keyboard (no position: the puzzle's centre).
func _on_tap_pressed(at: Vector2 = Vector2.INF) -> void:
	Game.tap()
	puzzle_view.scramble_step()
	puzzle_view.squash()
	Audio.play_click(puzzle_view.model.size if puzzle_view.model != null else 3)
	if at == Vector2.INF:
		at = puzzle_view.get_global_rect().get_center()
	fx.pop("+%s" % Num.format(Game.get_tap_moves()), at)


func _on_solved(count: int) -> void:
	puzzle_view.show_solved()
	Audio.play_solve()
	_pending_solve_value += count * Game.get_solve_value()


func _on_state_reset() -> void:
	_shown_solves = Game.solves
	_revealed.clear()
	for def: Dictionary in Content.BUILDINGS:
		if Game.is_building_unlocked(def["id"]):
			_revealed[def["id"]] = true
	_refresh()


func _on_purchased(_kind: String, _id: String) -> void:
	Audio.play_buy()
	_refresh()


# --- Settings menu (temporary home until the Settings tab, task 3.4) ------------

func _build_settings_menu() -> void:
	var popup := settings_button.get_popup()
	popup.add_radio_check_item("Graphics: High", MENU_GRAPHICS_HIGH)
	popup.add_radio_check_item("Graphics: Low", MENU_GRAPHICS_LOW)
	popup.set_item_tooltip(popup.get_item_index(MENU_GRAPHICS_HIGH), "Smooth edges, rounded pieces, stage glow and shadow.")
	popup.set_item_tooltip(popup.get_item_index(MENU_GRAPHICS_LOW), "Faster on older PCs.")
	popup.id_pressed.connect(_on_settings_id_pressed)


func _on_settings_id_pressed(id: int) -> void:
	match id:
		MENU_GRAPHICS_HIGH, MENU_GRAPHICS_LOW:
			var quality := "high" if id == MENU_GRAPHICS_HIGH else "low"
			GraphicsConfig.save_quality(quality)
			_apply_graphics(quality)


func _apply_graphics(quality: String) -> void:
	puzzle_view.set_graphics(quality)
	var popup := settings_button.get_popup()
	popup.set_item_checked(popup.get_item_index(MENU_GRAPHICS_HIGH), quality == "high")
	popup.set_item_checked(popup.get_item_index(MENU_GRAPHICS_LOW), quality == "low")
