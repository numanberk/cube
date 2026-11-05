extends Control
## Main screen. Reads numbers from the Game autoload and turns clicks into Game calls.
## Keep game rules out of this file; they belong in scripts/autoload/game.gd.

const UI_REFRESH_INTERVAL := 0.1
const MAX_VISUAL_MOVES_PER_SECOND := 12.0
const TAP_ACTION := &"tap"  ## Space / Enter (project.godot input map); held keys don't repeat
const UPGRADES_TAB := 1
const LAB_TAB := 3
const SOLVE_POP_INTERVAL := 0.25   ## at most ~4 "+X Solves" pops a second, however many solves happen
const BURST_INTERVAL := 0.5
const COUNTER_EASE := 12.0         ## how fast the Solves counter catches up (higher = faster)
const ShopCardScene := preload("res://scenes/shop_card.tscn")
const PuzzleChipScene := preload("res://scenes/puzzle_chip.tscn")
const UpgradeTileScene := preload("res://scenes/upgrade_tile.tscn")

@onready var solves_label: Label = %SolvesLabel
@onready var rate_label: Label = %RateLabel
@onready var puzzle_view: PuzzleView3D = %PuzzleView
@onready var move_ticker: RichTextLabel = %MoveTicker
@onready var stage_chips: HBoxContainer = %StageChips
@onready var news_list: VBoxContainer = %NewsList
@onready var lab_list: VBoxContainer = %LabList
@onready var lab_status: Label = %LabStatus
@onready var lab_progress: ProgressBar = %LabProgress
@onready var buff_label: Label = %BuffLabel
@onready var flow_label: Label = %FlowLabel
@onready var golden_button: Button = %GoldenButton
@onready var hint_label: Label = %HintLabel
@onready var settings_button: Button = %SettingsButton
@onready var settings_panel: SettingsPanel = %SettingsPanel
@onready var solve_button: Button = %SolveButton
@onready var solve_station: SolveStation = %SolveStation
@onready var next_goal_label: Label = %NextGoalLabel
@onready var goal_labels: Array[Label] = [%NextGoalLabel, %Goal1Label, %Goal2Label]
@onready var goal_bars: Array[ProgressBar] = [%Goal0Bar, %Goal1Bar, %Goal2Bar]
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
@onready var compete_button: Button = %CompeteButton
@onready var compete_panel: CompetePanel = %CompetePanel

var _helper_cards: Dictionary = {}    ## building id -> ShopCard
var _upgrade_tiles: Dictionary = {}   ## upgrade id -> UpgradeTile
var _method_tiles: Dictionary = {}    ## method id -> UpgradeTile (every method after the Beginner Method)
var _lab_cards: Dictionary = {}       ## Lab project id -> ShopCard (task 5.6)
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
var _hold_counter := false        ## keeps the counter still while the Welcome back panel is open
var _showcase: ShowcaseSolve      ## the real solve the big cube plays (task R.2); null for puzzles without one yet
var showcase_paused := false       ## screenshots freeze the showcase at a chosen move
var news := NewsFeed.new()          ## the news feed (task R.4): GameState events in, a line every ~1.2 s out


func _ready() -> void:
	puzzle_view.tapped.connect(_on_tap_pressed)
	settings_button.pressed.connect(settings_panel.open)
	compete_button.pressed.connect(open_compete)
	compete_panel.closed.connect(func() -> void: Audio.set_music_override(""))
	compete_panel.compete_enabled = true  # the championship reset exists since 6.2
	compete_panel.compete_pressed.connect(func() -> void: Game.compete())
	Game.championship_won.connect(_on_championship_won)
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
	Game.time_tier_reached.connect(_on_time_tier_reached)
	_connect_news()
	Game.golden_spawned.connect(_on_golden_spawned)
	Game.golden_expired.connect(_on_golden_gone)
	Game.golden_finished.connect(_on_golden_finished)
	puzzle_view.golden_clicked.connect(open_golden)
	golden_button.pressed.connect(open_golden)
	_build_puzzle_row()
	puzzle_view.set_puzzle(Game.get_focused_puzzle_id())
	for id: String in StagedSolver.PUZZLES:  # builds the solver's tables now (~0.3 s, cached), not mid-game
		StagedSolver.warm_up(id)
	_start_showcase()
	_shown_solves = Game.solves
	welcome_panel.collected.connect(_on_welcome_collected)
	_build_shop()
	for def: Dictionary in Content.BUILDINGS:
		if Game.is_building_unlocked(def["id"]):
			_revealed[def["id"]] = true  # already known at start: no sound
	_refresh()
	_show_offline_report()


func _process(delta: float) -> void:
	if _goal_bar_mode():
		var goals := Game.get_goals(1)
		solve_progress.value = float(goals[0]["progress"]) if not goals.is_empty() else 1.0
	else:
		solve_progress.value = Game.get_move_progress() / Game.get_moves_per_solve()
	if _showcase != null:
		_play_showcase(delta)
	else:
		var ticker := puzzle_view.ticker_text()
		move_ticker.text = "[center]%s[/center]" % (ticker if ticker != "" else " ")  # keep the line's height when empty
		_animate_helper_moves(delta)
	for id: String in _chips:
		(_chips[id] as PuzzleChip).advance(delta, Game.get_puzzle_moves_per_second(id))
	_animate_counter(delta)
	_pop_solves(delta)
	if news.advance(delta) != "":
		_show_news()
	_refresh_golden()
	_refresh_timer += delta
	if _refresh_timer >= UI_REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Space / Enter tap from anywhere. allow_echo = false: holding the key down doesn't repeat (PLAN: no hold-to-repeat).
	if event.is_action_pressed(TAP_ACTION, false) and not settings_panel.visible and not welcome_panel.visible \
			and not solve_station.visible and not compete_panel.visible:
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
	for def: Dictionary in Content.get_upgrades():
		var tile: UpgradeTile = UpgradeTileScene.instantiate()
		tile.pressed.connect(Game.buy_upgrade.bind(def["id"]))
		upgrade_list.add_child(tile)
		_upgrade_tiles[def["id"]] = tile
	for def: Dictionary in Content.get_lab_projects():
		var card: ShopCard = ShopCardScene.instantiate()
		card.pressed.connect(_on_lab_card_pressed.bind(String(def["id"])))
		lab_list.add_child(card)
		_lab_cards[def["id"]] = card
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
	var goals := Game.get_goals(3)
	if _goal_bar_mode() and not goals.is_empty():
		# Too many solves a second to follow the moves bar: it tracks the top goal instead.
		progress_label.text = "Next goal: %s" % _goal_text(goals[0], true)
	else:
		progress_label.text = "%s / %s moves  ·  %s mastery Lv %d%s" % [
			Num.format(Game.get_move_progress()), Num.format(Game.get_moves_per_solve()),
			Content.get_puzzle(focus)["name"], Game.get_mastery_level(focus),
			"" if next_milestone.is_empty() else " → Lv %d: %s" % [next_milestone["level"], next_milestone["text"]],
		]
	var tap_moves := Game.get_tap_moves()
	hint_label.text = "%sClick the cube or press Space: +%s %s   ·   drag to look around" % [
		_team_time_text(), Num.format(tap_moves), "move" if is_equal_approx(tap_moves, 1.0) else "moves",
	]
	_refresh_goal_strip(goals)
	Audio.set_music_context(Game.get_unlocked_track_ids(), Game.get_track_for_puzzle(Game.get_focused_puzzle_id()))
	_refresh_compete()
	stats_label.text = "Lifetime: %s solves  ·  %s moves" % [
		Num.format(Game.total_solves),
		Num.format(Game.total_moves),
	]

	_refresh_helper_cards()
	_refresh_upgrade_tiles()
	_refresh_lab()
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
			var focus_name: String = Content.get_puzzle(Game.get_focused_puzzle_id())["name"]
			var rate := "%s a %s  ·  +%s moves/s each" % [Num.cube_time(Game.get_helper_solve_time(id)), focus_name, Num.format(each)]
			if owned > 0:
				rate += " (+%s/s)" % Num.format(each * owned)
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
				"line1": "A new helper appears at %s Solves this run" % Num.format(unlock_at),
				"line2": "%s / %s" % [Num.format(Game.get_run_solves()), Num.format(unlock_at)],
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
		var researching := String(Game.research.get("id", "")) == "method_" + id
		tile.visible = learned or researching or Game.is_method_available(id)
		if not tile.visible:
			continue
		any_visible = true
		var cost := float(def["cost"])
		var can_buy := not learned and not researching and Game.research.is_empty() and Game.solves >= cost
		if can_buy:
			affordable_count += 1
		var cost_text := Num.format(cost)
		if researching:  # learning a method is Lab research (5.6)
			cost_text = "Researching  %s" % Num.clock(float(Game.research["left"]))
		var lab_note := ""
		if not learned and not researching and not Game.research.is_empty():
			lab_note = "\nThe Lab is busy with %s: this can start when it's done." \
					% Content.get_lab_project(String(Game.research["id"])).get("topic", "")
		tile.set_view({
			"icon": Content.icon(def["icon"]), "title": def["name"],
			"description": "%s\n%s\nLearning it takes %s of research in the Lab.%s" % [def["description"], _method_effect_text(def, learned),
					Num.format_duration(float(def.get("research_seconds", 0.0))), lab_note],
			"cost": cost_text, "affordable": can_buy, "owned": learned,
		})
		(owned_order if learned else order).append(tile)
	for def: Dictionary in Content.get_upgrades():
		var id: String = def["id"]
		var tile: UpgradeTile = _upgrade_tiles[id]
		var cost := float(def["cost"])
		var owned: bool = Game.upgrades.has(id)
		var locked_out := Game.is_upgrade_locked_out(id)
		var partners := Game.get_choice_partners(id)
		# A choice (5.7b) shows with its partner: both while open, the loser greyed out once one is picked.
		tile.visible = owned or Game.is_upgrade_available(id) or (locked_out and Game.get_run_solves() >= cost * 0.5)
		if not tile.visible:
			continue
		any_visible = true
		var can_buy := not owned and not locked_out and Game.solves >= cost
		if can_buy:
			affordable_count += 1
		tile.set_view({
			"icon": Content.icon(def["icon"]), "title": def["name"], "description": def["description"],
			"cost": Num.format(cost), "affordable": can_buy, "owned": owned, "locked_out": locked_out,
			"choice": _choice_text(id, partners, owned, locked_out),
		})
	# Buyable tiles first (the next method, then upgrades in content order), then the owned ones the same way.
	for def: Dictionary in Content.get_upgrades():
		var settled: bool = Game.upgrades.has(def["id"]) or Game.is_upgrade_locked_out(def["id"])  # a lost choice sits by its pick
		(owned_order if settled else order).append(_upgrade_tiles[def["id"]])
	order.append_array(owned_order)
	for index in order.size():
		upgrade_list.move_child(order[index], index)
	upgrade_empty.visible = not any_visible
	tabs.set_tab_title(UPGRADES_TAB, "Upgrades (%d)" % affordable_count if affordable_count > 0 else "Upgrades")


## The "Pick one" line in a choice upgrade's tooltip (5.7b), "" for an ordinary upgrade.
func _choice_text(id: String, partners: Array[String], owned: bool, locked_out: bool) -> String:
	if partners.is_empty():
		return ""
	var names: Array[String] = []
	for partner in partners:
		names.append(String(Content.get_upgrade(partner)["name"]))
	var other := " or ".join(names)
	if owned:
		return "You picked this over %s. A championship lets you choose again." % other
	if locked_out:
		return "You picked %s this run. A championship lets you choose again." % Content.get_upgrade(Game.get_choice_pick(
				String(Content.get_upgrade(id)["choice_group"])))["name"]
	return "Pick one: buying this locks %s for this run." % other


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


## "Cubing Friend · ready!", "Learn ZZ · 1m 14s", "Cube Lube · 15 Solves" (no estimate yet: what's left),
## "Research CFOP · 0:32" (Lab research) or, with `long`, "Learn ZZ · 46.00M more Solves · about 1m 14s".
func _goal_text(goal: Dictionary, long: bool = false) -> String:
	var name: String = ("another " if goal["more"] else "") + String(goal["name"])
	if goal["unit"] == "time":  # Lab research (5.6): paid already, only its time left
		return "%s  ·  %s%s" % [name, Num.clock(float(goal["seconds"])), " left in the Lab" if long else ""]
	if float(goal["missing"]) <= 0.0:
		return "%s  —  ready%s!" % [name, " to buy" if goal["unit"] == "Solves" else ""]
	var seconds := float(goal["seconds"])
	if is_inf(seconds) and not long:  # no estimate yet (no helpers): say what's left instead
		return "%s  ·  %s %s" % [name, Num.format(goal["missing"]), goal["unit"]]
	var eta := ("tap to get there" if goal["unit"] == "Solves" else "solve it to level up") if is_inf(seconds) \
			else ("under 1s" if seconds < 1.0 else ("about " if long else "") + Num.format_duration(seconds))
	if long:
		return "%s  ·  %s more %s  ·  %s" % [name, Num.format(goal["missing"]), goal["unit"], eta]
	return "%s  ·  %s" % [name, eta]


## The goal strip: the three soonest goals, each with its progress bar (the first, the next one, is brighter).
func _refresh_goal_strip(goals: Array[Dictionary]) -> void:
	for i in goal_labels.size():
		var shown := i < goals.size()
		goal_bars[i].visible = shown
		goal_labels[i].get_parent().visible = shown or i == 0
		if not shown:
			if i == 0:
				goal_labels[0].text = "Keep solving"
			continue
		goal_labels[i].text = _goal_text(goals[i])
		goal_labels[i].tooltip_text = _goal_text(goals[i], true)
		goal_bars[i].value = float(goals[i]["progress"])


## True when the focused puzzle solves too fast for the moves bar to mean anything.
func _goal_bar_mode() -> bool:
	return Game.get_puzzle_solve_rate(Game.get_focused_puzzle_id()) > Content.GOAL_BAR_SOLVES_PER_SECOND


## A time tier crossed: "3×3 team: Sub-10!  9.87 s".
func _on_time_tier_reached(puzzle_id: String, tier: String, seconds: float) -> void:
	var at := puzzle_view.get_global_rect().get_center() - Vector2(0.0, puzzle_view.size.y * 0.35)
	if puzzle_id != Game.get_focused_puzzle_id() and _chips.has(puzzle_id):
		at = (_chips[puzzle_id] as PuzzleChip).get_global_rect().get_center()
	fx.pop("%s team: %s!  %s" % [Content.get_puzzle(puzzle_id)["name"], tier, Num.cube_time(seconds)], at, &"PopSolve", 2.0)
	Audio.play_unlock()


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
	if _showcase != null:
		for move in _showcase.tap():  # a tap plays the next move of the showcase solve
			puzzle_view.turn(move)
	else:
		puzzle_view.scramble_step()
	puzzle_view.squash()
	var size := 3 if puzzle_view.model == null else (puzzle_view.model.size if puzzle_view.model.size > 0 else 6)
	Audio.play_click(size)  # the Megaminx (size 0) clicks like a big cube
	if at == Vector2.INF:
		at = puzzle_view.get_global_rect().get_center()
	fx.pop("+%s" % Num.format(Game.get_tap_moves()), at)


func _on_solved(count: int, puzzle_id: String) -> void:
	if puzzle_id == Game.get_focused_puzzle_id():
		if _showcase == null:  # the showcase solve finishes on its own schedule
			puzzle_view.show_solved()
	elif _chips.has(puzzle_id):
		(_chips[puzzle_id] as PuzzleChip).view.show_solved()
	Audio.play_solve()
	_pending_solve_value += count * Game.get_solve_value(puzzle_id)


func _on_focus_changed(puzzle_id: String) -> void:
	puzzle_view.set_puzzle(puzzle_id)
	_start_showcase()
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


# --- Showcase solve (task R.2) -------------------------------------------------------

## The big cube plays one real solve (StagedSolver) of the focused puzzle at a speed you can follow; puzzles without a
## staged solver yet (4×4+, Megaminx) keep the old scramble + rewind. Visual only: numbers never wait for it.
func _start_showcase(puzzle_id: String = "") -> void:
	if puzzle_id == "":
		puzzle_id = Game.get_focused_puzzle_id()
	_showcase = null
	if ShowcaseSolve.supports(puzzle_id):
		_showcase = ShowcaseSolve.new(puzzle_id, Game.method, randi())
		_showcase.solver_options = _solver_options()
		if not _showcase.solver_options.is_empty():
			_showcase.start_new()  # the first scramble was solved before the options were known
		_showcase.started.connect(_on_showcase_started)
		_showcase.stage_changed.connect(_on_showcase_stage)
		_showcase.finished.connect(puzzle_view.flash)
		puzzle_view.set_speed(0.0)
		_on_showcase_started()
	else:
		puzzle_view.turn_time = PuzzleView3D.TURN_TIME
		_build_stage_chips()


## One-look OLL / PLL in the showcase once the player has learned the full set in the drills (S.4).
func _solver_options() -> Dictionary:
	var options := {}
	if Game.is_drill_set_learned("oll"):
		options["full_oll"] = true
	if Game.is_drill_set_learned("pll"):
		options["full_pll"] = true
	return options


func _on_showcase_started() -> void:
	puzzle_view.show_state(_showcase.scramble)
	_build_stage_chips()


func _on_showcase_stage(_index: int) -> void:
	_refresh_stage_chips()


func _play_showcase(delta: float) -> void:
	var focus := Game.get_focused_puzzle_id()
	var tps := ShowcaseSolve.tps_for(_showcase.method, Game.get_puzzle_moves_per_second(focus))
	# Quarter turns a bit quicker than the pace, so a turn always ends before the next starts.
	puzzle_view.turn_time = clampf(0.7 / maxf(tps, 1.0), 0.05, PuzzleView3D.TURN_TIME)
	if not showcase_paused:
		for move in _showcase.advance(delta, tps):
			puzzle_view.turn(move)
	move_ticker.text = _showcase_ticker(Game.get_puzzle_solves_per_second(focus))


## "F2L 2   U F' U' F R' U2 R": the moves played so far dim, the one just played in the accent colour, the rest faint.
## With many solves a second, a note says this is one of them.
func _showcase_ticker(solves_per_second: float) -> String:
	var text := ""
	var m := puzzle_view.model
	match _showcase.phase:
		"inspection":
			var turns: Array = _showcase.stages[0]["moves"] if not _showcase.stages.is_empty() \
					and _showcase.stages[0]["id"] == "inspection" else []
			text = "[color=#ecedf2]Inspection[/color]   %s" % _moves_text(m, turns, _showcase.move_index if turns.size() > 0 else 0)
		"solved":
			var count := 0
			for stage in _showcase.chip_stages():
				count += (stage["moves"] as Array).size()
			text = "[color=#3ccf8e]Solved in %d moves  ·  %s[/color]" % [count, Content.get_method(_showcase.method).get("name", "")]
		_:
			var stage := _showcase.current_stage()
			if not stage.is_empty():
				text = "[color=#ecedf2]%s[/color]   %s" % [stage["name"], _moves_text(m, stage["moves"], _showcase.move_index)]
	if solves_per_second >= 2.0:
		text += "   [color=#5d6370]·  1 of %s solves/s[/color]" % Num.format(solves_per_second)
	return "[center]%s[/center]" % text


## "Team best 0.16 s (Robot record pace)   ·   " for the focused puzzle (the hint line starts with it), "" with no helpers.
func _team_time_text() -> String:
	var focus := Game.get_focused_puzzle_id()
	var time := Game.get_team_solve_time(focus)
	if is_inf(time):
		return ""
	var tier := Game.get_time_tier(focus)
	return "Team best %s%s   ·   " % [Num.cube_time(time), " (%s)" % tier["name"] if not tier.is_empty() else ""]


## Long stages (a beginner's second layer is ~35 moves) show a window around the current move, so the line stays short.
const TICKER_BEFORE := 5
const TICKER_AFTER := 7

func _moves_text(m: TwistyModel, moves: Array, played: int) -> String:
	var parts := PackedStringArray()
	var first := maxi(0, played - TICKER_BEFORE)
	var last := mini(moves.size(), first + TICKER_BEFORE + TICKER_AFTER)
	first = maxi(0, mini(first, last - TICKER_BEFORE - TICKER_AFTER))
	if first > 0:
		parts.append("…")
	for i in range(first, last):
		var name := ShowcaseSolve.notation(m, moves[i])
		if i == played - 1:
			parts.append("[color=#3ccf8e][b]%s[/b][/color]" % name)
		elif i < played:
			parts.append("[color=#aab0bd]%s[/color]" % name)
		else:
			parts.append(name)
	if last < moves.size():
		parts.append("…")
	return " ".join(parts)


## Chip labels for the stages (F2L 1-4 share one chip, "F2L 2/4" while it plays); short names so a row fits.
const CHIP_NAMES := {
	"cross": "Cross", "oll": "OLL", "pll": "PLL", "first_layer": "Layer 1", "second_layer": "Layer 2",
	"yellow_cross": "Yellow cross", "yellow_edges": "Yellow edges", "corner_cycle": "Corners",
	"corner_twist": "Twist", "orient": "Orient", "permute": "Permute",
}

## [{name, ids: [stage ids]}] in order.
func _chip_groups() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	if _showcase == null:
		return groups
	for stage in _showcase.chip_stages():
		var id: String = stage["id"]
		if id.begins_with("f2l_") and not groups.is_empty() and groups[-1]["name"] == "F2L":
			(groups[-1]["ids"] as Array).append(id)
		else:
			groups.append({"name": "F2L" if id.begins_with("f2l_") else CHIP_NAMES.get(id, stage["name"]), "ids": [id]})
	return groups


func _build_stage_chips() -> void:
	for child in stage_chips.get_children():
		stage_chips.remove_child(child)
		child.queue_free()
	stage_chips.visible = _showcase != null
	for group in _chip_groups():
		var label := Label.new()
		label.theme_type_variation = &"StageChip"
		label.text = group["name"]
		stage_chips.add_child(label)
	_refresh_stage_chips()


## Done chips green, the playing one lit (F2L shows which pair), the rest faint.
func _refresh_stage_chips() -> void:
	if _showcase == null:
		return
	var current := _showcase.current_stage()
	var current_id: String = current.get("id", "")
	var done := {}
	for i in mini(_showcase.stage_index, _showcase.stages.size()):
		done[_showcase.stages[i]["id"]] = true
	var solved := _showcase.phase == "solved"
	var groups := _chip_groups()
	for i in mini(groups.size(), stage_chips.get_child_count()):
		var label := stage_chips.get_child(i) as Label
		var ids: Array = groups[i]["ids"]
		var all_done := true
		for id: String in ids:
			if not done.has(id):
				all_done = false
		var playing := not solved and _showcase.phase == "solving" and current_id in ids
		label.theme_type_variation = &"StageChipActive" if playing else (&"StageChipDone" if all_done or solved else &"StageChip")
		label.text = groups[i]["name"]
		if playing and ids.size() > 1:
			label.text = "%s %d/%d" % [groups[i]["name"], ids.find(current_id) + 1, ids.size()]


## Screenshots: plays the showcase `moves` moves in (instantly) and holds it there.
func pose_showcase(moves: int) -> void:
	if _showcase == null:
		return
	for i in moves:
		for move in _showcase.tap():
			puzzle_view.turn(move)
	puzzle_view.finish_animations()
	showcase_paused = true
	_refresh_stage_chips()


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
		chip.tooltip_text = "%s: +%s Solves/s, %d %% of the helpers, team best %s" % [Content.get_puzzle(id)["name"],
				Num.format(Game.get_puzzle_solves_per_second(id)), roundi(Game.get_puzzle_share(id) * 100.0),
				Num.cube_time(Game.get_team_solve_time(id))]
		chip.update_running("%s  ·  %d%%" % [Num.cube_time(Game.get_team_solve_time(id)), roundi(Game.get_puzzle_share(id) * 100.0)],
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


# --- News feed (task R.4) ------------------------------------------------------------

func _connect_news() -> void:
	Game.helper_best_time.connect(func(id: String, puzzle: String, seconds: float, first: bool) -> void:
		news.on_helper_best_time(id, puzzle, seconds, first, int(Game.buildings.get(id, 1))))
	Game.mastery_level_up.connect(news.on_mastery_level_up)
	Game.purchased.connect(news.on_purchased)
	Game.time_tier_reached.connect(news.on_time_tier)
	Game.solves_milestone.connect(news.on_solves_milestone)
	Game.hand_solve_pb.connect(news.on_hand_pb)
	Game.hand_tier_reached.connect(news.on_hand_tier)
	Game.research_finished.connect(func(id: String) -> void:
		var project := Content.get_lab_project(id)
		if project.get("kind", "") == "method":
			return  # purchased("method") already gives the news line (and the buy sound)
		news.push("lab", "Research done: %s." % project.get("topic", id))
		Audio.play_unlock())
	Game.research_started.connect(func(_id: String) -> void:
		Audio.play_buy()
		_refresh())
	Game.daily_rewarded.connect(func(amount: float) -> void:
		news.push("daily", "Daily scramble done! +%s Solves. A new one comes tomorrow." % Num.format(amount)))
	Game.drill_set_learned.connect(func(set_id: String) -> void:
		news.push("drill_set", "You learned %s! Your team uses it in its solves now." % Content.get_drill_set(set_id)["name"]
				if set_id in ["oll", "pll"] else "You learned %s!" % Content.get_drill_set(set_id)["name"])
		if _showcase != null:
			_showcase.solver_options = _solver_options())
	Game.drill_case_learned.connect(func(case_id: String) -> void:
		news.push("drill_case", "Learned %s." % Content.get_algorithm(case_id).get("name", case_id)))


## The list under the shop: newest first and bright, older ones dim; it scrolls back through the last 20.
func _show_news() -> void:
	for child in news_list.get_children():
		news_list.remove_child(child)
		child.queue_free()
	for i in news.history.size():
		var label := Label.new()
		label.theme_type_variation = &"NewsNew" if i == 0 else &"NewsOld"
		label.text = news.history[i]
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = news.history[i]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		news_list.add_child(label)


# --- Golden Scramble (task S.6) ------------------------------------------------------

func _on_golden_spawned() -> void:
	puzzle_view.set_golden(true)
	Audio.play_unlock()
	_refresh_golden()


func _on_golden_gone() -> void:
	puzzle_view.set_golden(false)
	_refresh_golden()


## Clicking the golden sticker or the button: start the 10 s case in the Solve Station (on the focused puzzle, or the
## biggest cube the player has when the focused puzzle isn't a cube).
func open_golden() -> void:
	if solve_station.visible or not Game.claim_golden():
		return
	_on_golden_gone()
	solve_station.open_golden(Game.get_focused_puzzle_id(), Game.roll_golden_case_moves())


func _on_golden_finished(success: bool, buff: Dictionary) -> void:
	if success:
		news.push("golden", "Golden Scramble solved! %s" % buff.get("text", ""))
		fx.pop(String(buff.get("text", "")), buff_label.get_global_rect().get_center() + Vector2(0, 40), &"PopSolve", 2.0)
	else:
		news.push("golden", "The golden case got away.")


## The golden button sits at the bottom of the big cube's area while a sticker glows ("Golden Scramble! 9s"); the top bar shows
## a running buff ("Frenzy ×7 · 24s").
func _refresh_golden() -> void:
	var glowing := Game.golden_glow_left > 0.0 and not solve_station.visible
	golden_button.visible = glowing
	if glowing:
		golden_button.text = "Golden Scramble!  %ds" % ceili(Game.golden_glow_left)
		golden_button.size = golden_button.get_combined_minimum_size()
		var rect := puzzle_view.get_global_rect()
		golden_button.global_position = Vector2(rect.get_center().x - golden_button.size.x / 2.0,
				rect.end.y - golden_button.size.y - 6.0)  # under the cube, so the golden sticker on top stays visible
	if puzzle_view.is_golden_shown() != glowing and not solve_station.visible:
		puzzle_view.set_golden(glowing)
	flow_label.visible = not Game.flow.is_empty()
	if flow_label.visible:  # S.3: Flow from hand solves in the Solve Station
		flow_label.text = "Flow ×%s  ·  %s" % [Num.format(float(Game.flow["mult"])),
				Num.solve_time(float(Game.flow["left"])).get_slice(".", 0)]
		flow_label.tooltip_text = "Your last hand solve: every move counts ×%s until the Flow runs out. Solve again to keep it." \
				% Num.format(float(Game.flow["mult"]))
	buff_label.visible = not Game.buff.is_empty()
	if buff_label.visible:
		var buff_name := String(Game.buff["id"])
		for def: Dictionary in Content.GOLDEN["buffs"]:
			if def["id"] == Game.buff["id"]:
				buff_name = def["name"]
		buff_label.text = "%s ×%s  ·  %ds" % [buff_name, Num.format(float(Game.buff["mult"])), ceili(float(Game.buff["left"]))]


# --- Algorithm Lab (task 5.6) ---------------------------------------------------------

## The Lab tab: the running project with its bar, then every project you can see (done ones last, ticked). The tab title
## shows the time left ("Lab · 2:13") or how many can start now ("Lab (2)").
func _refresh_lab() -> void:
	var running := Game.get_research_progress()
	if running.is_empty():
		lab_status.text = "The Lab is free: start a project. Research keeps going while the game is closed."
		lab_progress.value = 0.0
	else:
		lab_status.text = "Researching %s  ·  %s left" % [running["topic"], Num.clock(float(running["left"]))]
		lab_progress.value = float(running["fraction"])
	var startable := 0
	var order: Array[ShopCard] = []
	var done_order: Array[ShopCard] = []
	for def: Dictionary in Content.get_lab_projects():
		var id: String = def["id"]
		var card: ShopCard = _lab_cards[id]
		var done := Game.is_research_done(id)
		var is_running: bool = String(running.get("id", "")) == id
		card.visible = done or is_running or Game.is_research_visible(id)
		if not card.visible:
			continue
		var can_start := Game.can_start_research(id)
		if can_start:
			startable += 1
		var line2 := "Takes %s" % Num.format_duration(float(def["seconds"]))
		if is_running:
			line2 = "Researching  ·  %s left" % Num.clock(float(running["left"]))
		elif done:
			line2 = "Done"
		elif not running.is_empty():
			line2 += "  ·  the Lab is busy"
		elif String(def.get("drill_set", "")) != "":
			line2 += "  ·  or learn %s in the Solve Station drills" % Content.get_drill_set(def["drill_set"]).get("name", "")
		card.set_view({
			"icon": Content.icon(def["icon"]), "title": def["name"], "line1": def["description"], "line2": line2,
			"owned": "✓" if done else "", "affordable": can_start, "active": is_running,
			"cost": "" if done or is_running else "%s Solves" % Num.format(float(def["cost"])),
		})
		(done_order if done else order).append(card)
	order.append_array(done_order)
	for index in order.size():
		lab_list.move_child(order[index], index)
	var title := "Lab"
	if not running.is_empty():
		title = "Lab · %s" % Num.clock(float(running["left"]))
	elif startable > 0:
		title = "Lab (%d)" % startable
	tabs.set_tab_title(LAB_TAB, title)


func _on_lab_card_pressed(id: String) -> void:
	var def := Content.get_lab_project(id)
	if def.get("kind", "") == "method":
		Game.buy_method(def["method"])
	else:
		Game.start_research(id)
	_refresh()


func _on_state_reset() -> void:
	news = NewsFeed.new()
	_rebuild_after_reset()


## A World Championship (6.2) started a new run: the screen goes back to the 2×2 like a new game, but the news feed
## keeps its lines and says what happened.
func _on_championship_won(trophies_won: int) -> void:
	compete_panel.close()
	news.push("championship", "World Champion! +%s %s, +%s %% moves. New run!" % [
		Num.format(float(trophies_won)), "trophy" if trophies_won == 1 else "trophies",
		Num.format(roundf((Game.get_trophy_mult() - 1.0) * 100.0))])
	Audio.play_unlock()
	_rebuild_after_reset()


func _rebuild_after_reset() -> void:
	puzzle_view.set_puzzle(Game.get_focused_puzzle_id())
	_start_showcase()
	_build_puzzle_row()
	_shown_solves = Game.solves
	_revealed.clear()
	for def: Dictionary in Content.BUILDINGS:
		if Game.is_building_unlocked(def["id"]):
			_revealed[def["id"]] = true
	_refresh()


func _on_purchased(kind: String, _id: String) -> void:
	if kind == "method" and _showcase != null:
		_showcase.method = Game.method  # the next showcase solve uses it
	Audio.play_buy()
	_refresh()


# --- World Championship (task 6.1) -------------------------------------------------

## Opens the Compete screen with what competing would give now, and plays "Finals" while it's open.
func open_compete() -> void:
	compete_panel.open(Game.get_championship_preview())
	Audio.set_music_override("finals")


## The top-bar Compete button (from half the first trophy's Solves) and the open Compete screen.
func _refresh_compete() -> void:
	compete_button.visible = Game.is_compete_visible()
	var gain := Game.get_pending_trophies()
	compete_button.text = "Compete" if gain < 1 else "Compete +%s" % Num.format(float(gain))  # short: the top bar is full
	compete_button.tooltip_text = "World Championship: %s now." % ("no trophies yet" if gain < 1 else "+%s %s" % [
		Num.format(float(gain)), "trophy" if gain == 1 else "trophies"])
	if compete_panel.visible:
		compete_panel.set_preview(Game.get_championship_preview())


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
