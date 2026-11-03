extends Control
## Main screen. Reads numbers from the Game autoload and turns clicks into Game calls.
## Keep game rules out of this file; they belong in scripts/autoload/game.gd.

const UI_REFRESH_INTERVAL := 0.1
const MAX_VISUAL_MOVES_PER_SECOND := 12.0
const TAP_ACTION := &"tap"  ## Space / Enter (project.godot input map); held keys don't repeat
const UPGRADES_TAB := 1
const SOLVE_POP_INTERVAL := 0.25   ## at most ~4 "+X Solves" pops a second, however many solves happen
const BURST_INTERVAL := 0.5
const COUNTER_EASE := 12.0         ## how fast the Solves counter catches up (higher = faster)
const ShopCardScene := preload("res://scenes/shop_card.tscn")
const PuzzleChipScene := preload("res://scenes/puzzle_chip.tscn")
const UpgradeTileScene := preload("res://scenes/upgrade_tile.tscn")

@onready var solves_label: Label = %SolvesLabel
@onready var rate_label: Label = %RateLabel
@onready var puzzle_view: PuzzleView3D = %PuzzleView
@onready var move_ticker: Label = %MoveTicker
@onready var hint_label: Label = %HintLabel
@onready var settings_button: Button = %SettingsButton
@onready var settings_panel: SettingsPanel = %SettingsPanel
@onready var solve_button: Button = %SolveButton
@onready var solve_station: SolveStation = %SolveStation
@onready var next_goal_label: Label = %NextGoalLabel
@onready var solve_progress: ProgressBar = %SolveProgress
@onready var progress_label: Label = %ProgressLabel
@onready var stats_label: Label = %StatsLabel
@onready var helper_list: VBoxContainer = %HelperList
@onready var upgrade_list: GridContainer = %UpgradeList
@onready var tabs: TabContainer = %Tabs
@onready var fx: FxLayer = %FxLayer
@onready var puzzle_row: HBoxContainer = %PuzzleRow
@onready var split_panel: SplitPanel = %SplitPanel
@onready var buy_one: Button = %BuyOne
@onready var buy_ten: Button = %BuyTen
@onready var buy_max: Button = %BuyMax
@onready var upgrade_empty: Label = %UpgradeEmpty
@onready var welcome_panel: WelcomePanel = %WelcomePanel

var _helper_cards: Dictionary = {}    ## building id -> ShopCard
var _upgrade_tiles: Dictionary = {}   ## upgrade id -> UpgradeTile
var _method_tiles: Dictionary = {}    ## method id -> UpgradeTile (every method after the Beginner Method)
var _refresh_timer := 0.0
var _visual_move_timer := 0.0
var _shown_solves := 0.0          ## what the counter shows; eases towards Game.solves
var _pending_solve_value := 0.0   ## Solves earned since the last "+X Solves" pop
var _solve_pop_timer := 0.0
var _burst_timer := 0.0
var _buy_amount := 1               ## 1, 10 or GameState.BUY_MAX (the ×1 / ×10 / Max toggle)
var _revealed: Dictionary = {}
var _chips: Dictionary = {}          ## unlocked puzzle id -> PuzzleChip (the focused one is hidden)
var _locked_chip: PuzzleChip         ## the next puzzle to unlock
var _hold_counter := false        ## keeps the counter still while the Welcome back panel is open    ## helper ids already shown unlocked (a newly revealed one plays the unlock sound)


func _ready() -> void:
	puzzle_view.tapped.connect(_on_tap_pressed)
	settings_button.pressed.connect(settings_panel.open)
	solve_button.pressed.connect(func() -> void: solve_station.open(Game.get_focused_puzzle_id()))
	Settings.changed.connect(_on_setting_changed)
	buy_one.pressed.connect(set_buy_amount.bind(1))
	buy_ten.pressed.connect(set_buy_amount.bind(10))
	buy_max.pressed.connect(set_buy_amount.bind(GameState.BUY_MAX))
	_apply_display_settings()
	Game.solved.connect(_on_solved)
	Game.purchased.connect(_on_purchased)
	Game.state_reset.connect(_on_state_reset)
	Game.focus_changed.connect(_on_focus_changed)
	Game.puzzle_unlocked.connect(_on_puzzle_unlocked)
	Game.mastery_level_up.connect(_on_mastery_level_up)
	_build_puzzle_row()
	puzzle_view.set_puzzle(Game.get_focused_puzzle_id())
	_shown_solves = Game.solves
	welcome_panel.collected.connect(_on_welcome_collected)
	_build_shop()
	for def: Dictionary in Content.BUILDINGS:
		if Game.is_building_unlocked(def["id"]):
			_revealed[def["id"]] = true  # already known at start: no sound
	_refresh()
	_show_offline_report()


func _process(delta: float) -> void:
	solve_progress.value = Game.get_move_progress() / Game.get_moves_per_solve()
	var ticker := puzzle_view.ticker_text()
	move_ticker.text = ticker if ticker != "" else " "  # keep the line's height when empty
	_animate_helper_moves(delta)
	for id: String in _chips:
		(_chips[id] as PuzzleChip).advance(delta, Game.get_puzzle_moves_per_second(id))
	_animate_counter(delta)
	_pop_solves(delta)
	_refresh_timer += delta
	if _refresh_timer >= UI_REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Space / Enter tap from anywhere. allow_echo = false: holding the key down doesn't repeat (PLAN: no hold-to-repeat).
	if event.is_action_pressed(TAP_ACTION, false) and not settings_panel.visible and not welcome_panel.visible \
			and not solve_station.visible:
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
	for def: Dictionary in Content.METHODS.slice(1):  # everyone starts with the Beginner Method
		var tile: UpgradeTile = UpgradeTileScene.instantiate()
		tile.pressed.connect(Game.buy_method.bind(def["id"]))
		upgrade_list.add_child(tile)
		_method_tiles[def["id"]] = tile


# --- Refreshing --------------------------------------------------------------

func _refresh() -> void:
	rate_label.text = "+%s solves/s   ·   %s moves/s" % [
		Num.format(Game.get_solves_per_second()),
		Num.format(Game.get_moves_per_second()),
	]
	var focus := Game.get_focused_puzzle_id()
	var next_milestone := Game.get_next_mastery_milestone(focus)
	progress_label.text = "%s / %s moves  ·  %s mastery Lv %d%s" % [
		Num.format(Game.get_move_progress()), Num.format(Game.get_moves_per_solve()),
		Content.get_puzzle(focus)["name"], Game.get_mastery_level(focus),
		"" if next_milestone.is_empty() else " → Lv %d: %s" % [next_milestone["level"], next_milestone["text"]],
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
	_refresh_puzzle_row()
	split_panel.refresh()


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
## each one bought. The next method in the chain is a tile here too (first), and learned methods count as owned.
## The tab title shows how many are affordable.
func _refresh_upgrade_tiles() -> void:
	var any_visible := false
	var affordable_count := 0
	var order: Array[UpgradeTile] = []      # buyable tiles, in order
	var owned_order: Array[UpgradeTile] = []
	for def: Dictionary in Content.METHODS.slice(1):
		var id: String = def["id"]
		var tile: UpgradeTile = _method_tiles[id]
		var learned := Game.is_method_learned(id)
		tile.visible = learned or Game.is_method_available(id)
		if not tile.visible:
			continue
		any_visible = true
		var cost := float(def["cost"])
		var can_buy := not learned and Game.solves >= cost
		if can_buy:
			affordable_count += 1
		tile.set_view({
			"icon": Content.icon(def["icon"]), "title": def["name"],
			"description": "%s\n%s" % [def["description"], _method_effect_text(def, learned)],
			"cost": Num.format(cost), "affordable": can_buy, "owned": learned,
		})
		(owned_order if learned else order).append(tile)
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
	# Buyable tiles first (the next method, then upgrades in content order), then the owned ones the same way.
	for def: Dictionary in Content.UPGRADES:
		(owned_order if Game.upgrades.has(def["id"]) else order).append(_upgrade_tiles[def["id"]])
	order.append_array(owned_order)
	for index in order.size():
		upgrade_list.move_child(order[index], index)
	upgrade_empty.visible = not any_visible
	tabs.set_tab_title(UPGRADES_TAB, "Upgrades (%d)" % affordable_count if affordable_count > 0 else "Upgrades")


## What a method does to the focused puzzle: "3×3: 20 → 14 moves per solve" (or the floor note once it's reached).
func _method_effect_text(def: Dictionary, learned: bool) -> String:
	var focus := Game.get_focused_puzzle_id()
	var puzzle_name: String = Content.get_puzzle(focus)["name"]
	var now := Game.get_moves_per_solve(focus)
	var floor_moves := Game.get_moves_floor(focus)
	if learned:
		return "Learned. %s: %s moves per solve (never below %s)." % [puzzle_name, Num.format(now), Num.format(floor_moves)]
	var after := maxf(floor_moves, now * float(def["mult"]))
	return "%s: %s → %s moves per solve (never below %s)." % [puzzle_name, Num.format(now), Num.format(after), Num.format(floor_moves)]


## The Solves counter counts up smoothly instead of jumping; spending snaps it down at once.
func _animate_counter(delta: float) -> void:
	if _hold_counter:
		solves_label.text = "%s Solves" % Num.format(_shown_solves)
		return
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
	var mps := Game.get_puzzle_moves_per_second(Game.get_focused_puzzle_id())  # the big view shows its own share
	puzzle_view.set_speed(mps)
	if mps <= 0.0:
		return
	_visual_move_timer += delta * minf(mps, MAX_VISUAL_MOVES_PER_SECOND)
	while _visual_move_timer >= 1.0:
		_visual_move_timer -= 1.0
		puzzle_view.scramble_step()


## The "Welcome back" panel after time away (or a damaged-save notice). The Solves counter holds the old amount
## until Collect, then counts up with a chime.
func _show_offline_report() -> void:
	if welcome_panel.show_report(Game.offline_report, Game.load_notice):
		_shown_solves = Game.solves - float(Game.offline_report.get("solves", 0.0))
		_hold_counter = true
	Game.load_notice = ""  # show it once
	Game.offline_report = {}


func _on_welcome_collected(solves: float) -> void:
	_hold_counter = false
	if solves > 0.0:
		Audio.play_solve()
		fx.pop("+%s Solves" % Num.format(solves), solves_label.get_global_rect().get_center() + Vector2(0, 30), &"PopSolve")


# --- Signals -----------------------------------------------------------------

## A tap from a click (`at` = where, global) or the keyboard (no position: the puzzle's centre).
func _on_tap_pressed(at: Vector2 = Vector2.INF) -> void:
	Game.tap()
	puzzle_view.scramble_step()
	puzzle_view.squash()
	var size := 3 if puzzle_view.model == null else (puzzle_view.model.size if puzzle_view.model.size > 0 else 6)
	Audio.play_click(size)  # the Megaminx (size 0) clicks like a big cube
	if at == Vector2.INF:
		at = puzzle_view.get_global_rect().get_center()
	fx.pop("+%s" % Num.format(Game.get_tap_moves()), at)


func _on_solved(count: int, puzzle_id: String) -> void:
	if puzzle_id == Game.get_focused_puzzle_id():
		puzzle_view.show_solved()
	elif _chips.has(puzzle_id):
		(_chips[puzzle_id] as PuzzleChip).view.show_solved()
	Audio.play_solve()
	_pending_solve_value += count * Game.get_solve_value(puzzle_id)


func _on_focus_changed(puzzle_id: String) -> void:
	puzzle_view.set_puzzle(puzzle_id)
	_refresh_puzzle_row()


## Milestone levels get a pop and the unlock sting; other level-ups just move the bar.
func _on_mastery_level_up(puzzle_id: String, level: int) -> void:
	for milestone: Dictionary in Content.MASTERY["milestones"]:
		if int(milestone["level"]) == level:
			var at := puzzle_view.get_global_rect().get_center()
			if puzzle_id != Game.get_focused_puzzle_id() and _chips.has(puzzle_id):
				at = (_chips[puzzle_id] as PuzzleChip).get_global_rect().get_center()
			fx.pop("%s Mastery %d: %s" % [Content.get_puzzle(puzzle_id)["name"], level, milestone["text"]], at, &"PopSolve", 2.0)
			Audio.play_unlock()


func _on_puzzle_unlocked(_puzzle_id: String) -> void:
	_build_puzzle_row()
	puzzle_view.drop_in()
	Audio.play_unlock()


# --- Puzzle row (D9) --------------------------------------------------------------

## One chip per unlocked puzzle (the focused one hidden, as it's the big view) plus the next locked puzzle.
func _build_puzzle_row() -> void:
	for id in Game.get_unlocked_puzzle_ids():
		if not _chips.has(id):
			var chip: PuzzleChip = PuzzleChipScene.instantiate()
			puzzle_row.add_child(chip)
			chip.show_running(id, Content.get_puzzle(id)["name"])
			chip.chosen.connect(Game.set_focus)
			chip.set_reduce_motion(Settings.get_value("reduce_motion"))
			_chips[id] = chip
	for id: String in _chips.keys():
		if not Game.is_puzzle_unlocked(id):  # after a save reset
			(_chips[id] as PuzzleChip).queue_free()
			puzzle_row.remove_child(_chips[id])
			_chips.erase(id)
	if _locked_chip == null:
		_locked_chip = PuzzleChipScene.instantiate()
		puzzle_row.add_child(_locked_chip)
		_locked_chip.unlock_pressed.connect(_on_unlock_pressed)
	puzzle_row.move_child(_locked_chip, -1)
	_refresh_puzzle_row()


func _refresh_puzzle_row() -> void:
	var focused := Game.get_focused_puzzle_id()
	for id: String in _chips:
		var chip: PuzzleChip = _chips[id]
		chip.visible = id != focused
		chip.update_running("+%s/s  ·  %d%%" % [Num.format(Game.get_puzzle_solves_per_second(id)), roundi(Game.get_puzzle_share(id) * 100.0)],
				Game.get_mastery_level(id), Game.get_mastery_progress(id))
	if _locked_chip == null:
		return
	var next := Game.get_next_locked_puzzle()
	_locked_chip.visible = next != ""
	if next != "":
		var cost := Game.get_puzzle_unlock_cost(next)
		_locked_chip.show_locked(next, Content.get_puzzle(next)["name"], "%s Solves" % Num.format(cost), Game.solves >= cost)


func _on_unlock_pressed(puzzle_id: String) -> void:
	Game.unlock_puzzle(puzzle_id)


func _on_state_reset() -> void:
	puzzle_view.set_puzzle(Game.get_focused_puzzle_id())
	_build_puzzle_row()
	_shown_solves = Game.solves
	_revealed.clear()
	for def: Dictionary in Content.BUILDINGS:
		if Game.is_building_unlocked(def["id"]):
			_revealed[def["id"]] = true
	_refresh()


func _on_purchased(_kind: String, _id: String) -> void:
	Audio.play_buy()
	_refresh()


# --- Settings ----------------------------------------------------------------------

## Graphics and Reduce motion are applied here (main owns the views); audio and notation apply themselves in Settings.
func _apply_display_settings() -> void:
	puzzle_view.set_graphics(Settings.get_value("quality"))
	var reduce: bool = Settings.get_value("reduce_motion")
	puzzle_view.set_reduce_motion(reduce)
	fx.particles_enabled = not reduce
	for id: String in _chips:
		(_chips[id] as PuzzleChip).set_reduce_motion(reduce)


func _on_setting_changed(key: String) -> void:
	if key in ["quality", "reduce_motion"]:
		_apply_display_settings()
	elif key == "notation":
		_refresh()
