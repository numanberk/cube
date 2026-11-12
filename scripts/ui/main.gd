extends Control
## Main screen. Reads numbers from the Game autoload and turns clicks into Game calls.
## Keep game rules out of this file; they belong in scripts/autoload/game.gd.

const UI_REFRESH_INTERVAL := 0.1
const MAX_VISUAL_MOVES_PER_SECOND := 12.0
const TAP_ACTION := &"tap"  ## Space / Enter (project.godot input map); held keys don't repeat
const HELPERS_TAB := 0
const UPGRADES_TAB := 1
const LAB_TAB := 3
const AUTO_TAB := 4
const TAB_ICONS: Array[String] = ["friend", "magnets", "small_cubes", "lab", "firmware"]  ## per tab (V.5 pills): Helpers ... Auto
const PLAYER_TURN_TIME := 0.08      ## seconds per quarter turn for your own key turns on the main cube (S.7)
const SOLVE_POP_INTERVAL := 0.25   ## at most ~4 "+X Solves" pops a second, however many solves happen
const BURST_INTERVAL := 0.5
const COUNTER_EASE := 12.0         ## how fast the Solves counter catches up (higher = faster)
const ShopCardScene := preload("res://scenes/shop_card.tscn")
const PuzzleChipScene := preload("res://scenes/puzzle_chip.tscn")
const SHELF_COLUMN_MAX := 3  ## up to this many small puzzles stand in one column on the stage; more take two (V.4)
const STAGE_ZOOM := 0.92  ## the main puzzle frames a little tighter than its bounding sphere (V.4, see PuzzleView3D.frame_zoom)
const FIRST_HINT_MOVES := 300.0  ## the "Click the cube" hint shows on the stage until this many lifetime moves (V.4)
const UpgradeTileScene := preload("res://scenes/upgrade_tile.tscn")

@onready var solves_label: Label = %SolvesLabel
@onready var solves_rate: StatChip = %SolvesRate
@onready var moves_rate: StatChip = %MovesRate
@onready var puzzle_view: PuzzleView3D = %PuzzleView
@onready var background: ColorRect = %Background
@onready var _background_material: ShaderMaterial = background.material
var _lamp_center := Vector2(-1.0, -1.0)  ## last lamp_center sent to the background shader
@onready var move_ticker: RichTextLabel = %MoveTicker
@onready var stage_chips: HBoxContainer = %StageChips
@onready var news_list: VBoxContainer = %NewsList
@onready var lab_list: VBoxContainer = %LabList
@onready var lab_status: Label = %LabStatus
@onready var lab_progress: ProgressBar = %LabProgress
@onready var buff_chip: StatChip = %BuffChip
@onready var flow_chip: StatChip = %FlowChip
@onready var streak_chip: StatChip = %StreakChip
@onready var golden_button: Button = %GoldenButton
@onready var hint_label: Label = %HintLabel
@onready var settings_button: Button = %SettingsButton
@onready var settings_panel: SettingsPanel = %SettingsPanel
@onready var solve_button: Button = %SolveButton
@onready var solve_station: SolveStation = %SolveStation
## The goal card (V.4): the main goal (moves to the next solve, or the top goal once solves are too fast to follow) with
## its bar, then the next goals in two small slots.
@onready var goal_labels: Array[Label] = [%Goal1Label, %Goal2Label]
@onready var goal_bars: Array[ProgressBar] = [%Goal1Bar, %Goal2Bar]
@onready var solve_progress: ProgressBar = %SolveProgress
@onready var progress_label: Label = %ProgressLabel
@onready var solves_box: Control = %SolvesBox
@onready var team_best: Label = %TeamBest
@onready var goal_card: Control = %GoalCard
@onready var stage_top: Control = %StageTop
@onready var stage_overlay: Control = %StageOverlay
@onready var news_panel: Control = %NewsPanel
@onready var helper_list: VBoxContainer = %HelperList
@onready var upgrade_list: GridContainer = %UpgradeList
@onready var tabs: TabContainer = %Tabs
@onready var fx: FxLayer = %FxLayer
@onready var banner: Banner = %Banner
@onready var puzzle_row: GridContainer = %PuzzleRow
@onready var shelf: Control = %Shelf
@onready var split_panel: SplitPanel = %SplitPanel
@onready var buy_one: Button = %BuyOne
@onready var buy_ten: Button = %BuyTen
@onready var buy_max: Button = %BuyMax
@onready var upgrade_empty: Label = %UpgradeEmpty
@onready var welcome_panel: WelcomePanel = %WelcomePanel
@onready var compete_button: Button = %CompeteButton
@onready var compete_panel: CompetePanel = %CompetePanel
@onready var perks_button: Button = %PerksButton
@onready var perk_panel: PerkPanel = %PerkPanel
@onready var automation_panel: AutomationPanel = %AutomationPanel

var _helper_cards: Dictionary = {}    ## building id -> ShopCard
var _tab_bubbles: Dictionary = {}     ## tab index -> its count bubble (V.5), a Label on the tab bar
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
var _known_puzzles: Dictionary = {}  ## puzzles the player had before (V.7: no "New puzzle" banner for them)
var _chips: Dictionary = {}          ## unlocked puzzle id -> PuzzleChip (the focused one is hidden)
var _locked_chip: PuzzleChip         ## the next puzzle to unlock
var _hold_counter := false        ## keeps the counter still while the Welcome back panel is open
var _showcase: ShowcaseSolve      ## the real solve the big cube plays (task R.2); null for puzzles without one yet
var showcase_paused := false       ## screenshots freeze the showcase at a chosen move
## Main-screen key turning (S.7): a SolveSession that only maps keys to moves (it stays "idle", so it never times or
## applies anything); the same layout as the Solve Station (Settings "solve_keys"), with its hands and widths.
var _key_session := SolveSession.new()
var news := NewsFeed.new()          ## the news feed (task R.4): GameState events in, a line every ~1.2 s out


func _ready() -> void:
	puzzle_view.tapped.connect(_on_tap_pressed)
	_show_news()  # hidden until the first line (V.4)
	puzzle_view.frame_zoom = STAGE_ZOOM
	# The card and badges (top) and the chips/ticker strip (bottom) sit on the stage: frame the puzzle between them.
	stage_top.resized.connect(func() -> void: puzzle_view.frame_inset_top = stage_top.size.y)
	stage_overlay.resized.connect(func() -> void: puzzle_view.frame_inset_bottom = stage_overlay.size.y)
	# The shelf of small puzzles sits on the stage's left (V.4, owner's option b): frame the puzzle right of it.
	shelf.resized.connect(_frame_beside_shelf)
	shelf.visibility_changed.connect(_frame_beside_shelf)
	settings_button.pressed.connect(settings_panel.open)
	compete_button.pressed.connect(open_compete)
	compete_panel.closed.connect(func() -> void: Audio.set_music_override(""))
	compete_panel.compete_enabled = true  # the championship reset exists since 6.2
	compete_panel.compete_pressed.connect(func() -> void: Game.compete())
	Game.championship_won.connect(_on_championship_won)
	perks_button.pressed.connect(open_perks)
	perk_panel.perk_pressed.connect(func(id: String) -> void: Game.buy_perk(id))
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
	for i in TAB_ICONS.size():
		tabs.set_tab_icon(i, Content.icon(TAB_ICONS[i]))
	tabs.get_tab_bar().resized.connect(_place_tab_bubbles)
	puzzle_view.set_puzzle(Game.get_focused_puzzle_id())
	_reset_key_session()
	for id: String in StagedSolver.PUZZLES:  # builds the learned methods' tables now (cached), not mid-game
		StagedSolver.warm_up(id, _learned_methods())
	_start_showcase()
	_shown_solves = Game.solves
	welcome_panel.collected.connect(_on_welcome_collected)
	_build_shop()
	for def: Dictionary in Content.BUILDINGS:
		if Game.is_building_unlocked(def["id"]):
			_revealed[def["id"]] = true  # already known at start: no sound
	_known_puzzles = Game.puzzles_reached.duplicate()  # kept through championships (V.7)
	_refresh()
	_show_offline_report()


func _process(delta: float) -> void:
	banner.stage_rect = puzzle_view.get_global_rect()
	if not _overlay_open():  # V.7: big moments, one at a time; they wait while a panel covers them
		banner.advance(delta)
	Game.automation_paused = welcome_panel.visible  # auto-buyers (6.3b) wait until "Welcome back" is collected
	Game.auto_compete_held = solve_station.visible or compete_panel.visible  # never reset the run under the player
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
	if event.is_action_pressed(TAP_ACTION, false) and not _overlay_open():
		_on_tap_pressed()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if not _overlay_open() and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if handle_turn_key(code, key.shift_pressed):
			get_viewport().set_input_as_handled()
			return
	if not OS.is_debug_build():
		return
	match key.keycode:
		KEY_F9:
			Game.cheat_add_solves(1000.0)
		KEY_F10:
			Game.wipe_save()


## Every method up to the newest one learned (Content.METHODS is in learning order).
func _learned_methods() -> Array:
	var out := []
	for def: Dictionary in Content.METHODS:
		out.append(def["id"])
		if def["id"] == Game.method:
			break
	return out


## Is a panel over the main screen? One fading out (V.6) already counts as closed.
func _overlay_open() -> bool:
	for panel: Control in [settings_panel, welcome_panel, solve_station, compete_panel, perk_panel]:
		if _is_up(panel):
			return true
	return false


## A panel is up: shown and not fading out (V.6).
func _is_up(panel: Control) -> bool:
	return panel.visible and not UiFx.is_closing(panel)


## A Solve Station key on the main screen (S.7; tests call this directly): turns the big cube, and every turn (not a
## whole-cube rotation) is a tap. Hand and width keys only change what the next key does. Returns true if the key is
## one of the layout's keys (so it's used up), false for any other key.
func handle_turn_key(code: int, shift: bool = false) -> bool:
	var session := _key_session
	if session.model == null:
		return false
	var known := Content.SOLVE_KEYS.has(code) or Content.SOLVE_HAND_KEYS.has(code) if session.layout == "cstimer" \
			else Content.SOLVE_KEYS_SIMPLE.has(code) or Content.SOLVE_WIDTH_KEYS.has(code)
	if not known:
		return false
	var hand_key := Content.SOLVE_HAND_KEYS.has(code) if session.layout == "cstimer" else Content.SOLVE_WIDTH_KEYS.has(code)
	var move := session.press_key(code, 0.0, shift)
	if move.is_empty():
		if _showcase == null and not hand_key:  # a key with no move on this puzzle (Megaminx): still a tap, either layout
			puzzle_view.scramble_step()
			_tap_effects(Game.tap(), Vector2.INF, false)
		return true
	var rotation := session.model.is_rotation(move)
	if _showcase != null:
		for m in _showcase.player_turn(move):
			puzzle_view.turn(m)
	elif not rotation:
		puzzle_view.scramble_step()  # puzzles without a showcase yet keep their scramble + rewind look
	if not rotation:
		_tap_effects(Game.tap(), Vector2.INF, false)
	return true


func _reset_key_session() -> void:
	_key_session = SolveSession.new()
	_key_session.layout = String(Settings.get_value("solve_keys"))
	_key_session.model = PuzzleShapes.from_id(Game.get_focused_puzzle_id())


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
	solves_rate.set_stat("+%s" % Num.format(Game.get_solves_per_second()), "/s")
	moves_rate.set_stat(Num.format(Game.get_moves_per_second()), "/s")
	var focus := Game.get_focused_puzzle_id()
	var next_milestone := Game.get_next_mastery_milestone(focus)
	var goals := Game.get_goals(3)
	var tap_moves := Game.get_tap_moves()
	var how_to := "Click the cube, Space or solve keys: +%s %s  ·  drag to look around" % [
		Num.format(tap_moves), "move" if is_equal_approx(tap_moves, 1.0) else "moves"]
	if _goal_bar_mode() and not goals.is_empty():
		# Too many solves a second to follow the moves bar: it tracks the top goal instead.
		progress_label.text = "Next goal: %s" % _goal_text(goals[0])
		progress_label.tooltip_text = "Next goal: %s\n%s" % [_goal_text(goals[0], true), how_to]
	else:
		progress_label.text = "%s / %s moves  ·  %s Lv %d" % [Num.format(Game.get_move_progress()),
			Num.format(Game.get_moves_per_solve()), Content.get_puzzle(focus)["name"], Game.get_mastery_level(focus)]
		progress_label.tooltip_text = "%s / %s moves to the next solve  ·  %s mastery Lv %d%s" % [
			Num.format(Game.get_move_progress()), Num.format(Game.get_moves_per_solve()),
			Content.get_puzzle(focus)["name"], Game.get_mastery_level(focus),
			"" if next_milestone.is_empty() else " → Lv %d: %s" % [next_milestone["level"], next_milestone["text"]],
		] + "\n" + how_to
	# The how-to line is a first-time hint on the stage; afterwards it lives in the goal card's tooltip (V.4).
	hint_label.visible = Game.total_moves < FIRST_HINT_MOVES
	hint_label.text = "Click the cube or press Space to turn it"
	var best := _team_time_text()
	team_best.visible = best != ""
	team_best.text = best
	_refresh_goal_strip(goals.slice(1) if _goal_bar_mode() and not goals.is_empty() else goals)
	Audio.set_music_context(Game.get_unlocked_track_ids(), Game.get_track_for_puzzle(Game.get_focused_puzzle_id()))
	_refresh_compete()
	solves_box.tooltip_text = "Solves: what everything costs. Every finished solve on any puzzle earns some.\n" \
			+ "Lifetime: %s solves  ·  %s moves" % [Num.format(Game.total_solves), Num.format(Game.total_moves)]

	_place_lamp()
	_refresh_helper_cards()
	_refresh_upgrade_tiles()
	_refresh_lab()
	_place_tab_bubbles()  # after the counts, and the Lab title's countdown changes the tabs' widths
	_refresh_puzzle_row()
	split_panel.refresh()


## Unlocked helpers show as full cards; the first locked one shows as a "???" card with its requirement
## (so there's always a visible next target); the rest stay hidden.
func _refresh_helper_cards() -> void:
	var shown_locked := false
	var affordable_count := 0
	for def: Dictionary in Content.BUILDINGS:
		var id: String = def["id"]
		var card: ShopCard = _helper_cards[id]
		if Game.is_building_unlocked(id):
			if not _revealed.has(id):
				_revealed[id] = true
				Audio.play_unlock()
				if not Game.is_achievement_earned("team_%s_1" % id):  # V.7: only a helper never owned before is news
					banner.push({"kind": "helper", "title": "New helper: %s" % def["name"], "name": def["name"],
							"subtitle": def["description"], "icon": Content.icon(def["icon"]), "category": &"helpers"})
			var owned: int = Game.buildings[id]
			var each := Game.get_building_mps(id)
			var count := _buy_count(id)
			var cost := Game.get_building_cost_for(id, count)
			var focus_name: String = Content.get_puzzle(Game.get_focused_puzzle_id())["name"]
			# One short line (V.5): the team's total once there is one ("each" moves to the tooltip), so it never gets cut.
			var rate := "%s a %s  ·  +%s moves/s" % [Num.cube_time(Game.get_helper_solve_time(id)), focus_name,
					Num.format(each * owned) if owned > 0 else Num.format(each) + " each"]
			# V.5: one short line (the rate; the description is the tooltip), milestone pips, a bar towards the cost.
			var bought := 0
			var ready := 0
			var next_at := 0
			for row: Dictionary in Content.HELPER_MILESTONES:
				if Game.upgrades.has("ms_%s_%d" % [id, row["owned"]]):
					bought += 1
				elif owned >= int(row["owned"]):
					ready += 1
				elif next_at == 0:
					next_at = int(row["owned"])
			card.tooltip_text = "%s\n+%s moves/s each." % [def["description"], Num.format(each)] \
					+ ("\nNext milestone upgrade at %d owned." % next_at if next_at > 0 else "")
			card.visible = true
			card.set_view({
				"icon": Content.icon(def["icon"]), "title": def["name"], "line1": rate, "line2": "",
				"owned": str(owned), "affordable": Game.solves >= cost, "progress": Game.solves / cost if cost > 0.0 else 1.0,
				"pips": [bought, Content.HELPER_MILESTONES.size(), ready],
				"cost": "%s Solves" % Num.format(cost) if _buy_amount == 1 else "×%d  ·  %s Solves" % [count, Num.format(cost)],
			})
			if Game.solves >= Game.get_building_cost(id):  # the bubble counts single buys, whatever ×1/×10/Max says
				affordable_count += 1
		elif not shown_locked:
			shown_locked = true
			var unlock_at := Game.get_building_unlock_at(id)
			card.visible = true
			card.tooltip_text = "A new helper joins the team at %s Solves this run." % Num.format(unlock_at)
			card.set_view({  # V.5: its silhouette, and a bar to the unlock
				"icon": Content.icon(def["icon"]), "title": "???", "silhouette": true,
				"line1": "Appears at %s Solves this run" % Num.format(unlock_at), "line2": "",
				"owned": "?", "cost": "", "locked": true,
				"progress": Game.get_run_solves() / unlock_at if unlock_at > 0.0 else 1.0,
			})
		else:
			card.visible = false
	set_tab_count(HELPERS_TAB, affordable_count)


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
	var bought := Game.buy_buildings(id, _buy_amount)
	if bought > 0:  # V.6: the card squashes and a "+N" flies to its owned count
		var card: ShopCard = _helper_cards[id]
		UiFx.squash(card)
		UiFx.fly_text(fx, "+%d" % bought, card.get_global_rect().get_center(), card.get_owned_center(), &"PopTap")


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
			"icon": Content.icon(def["icon"]), "category": &"lab", "title": def["name"],  # methods are Lab research
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
			"icon": Content.icon(def["icon"]), "category": &"upgrades", "title": def["name"], "description": def["description"],
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
	set_tab_count(UPGRADES_TAB, affordable_count)


## A tab's round count bubble (V.5): how many things there can be bought or started now; hidden at 0.
func set_tab_count(tab: int, count: int) -> void:
	var bubble: Label = _tab_bubbles.get(tab)
	if bubble == null:
		if count <= 0:
			return
		bubble = Label.new()
		bubble.theme_type_variation = &"CountBubble"
		bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tabs.get_tab_bar().add_child(bubble)
		_tab_bubbles[tab] = bubble
	bubble.text = str(count) if count < 100 else "99+"
	bubble.set_meta(&"count", count)


func get_tab_count(tab: int) -> int:
	var bubble: Label = _tab_bubbles.get(tab)
	return 0 if bubble == null else int(bubble.get_meta(&"count", 0))



## Each bubble sits on its tab's top-right corner: shown when its count is above 0 and its tab is shown and in view.
## Run on every refresh (titles like "Lab · 4:00" change the tabs' widths) and when the tab bar resizes.
func _place_tab_bubbles() -> void:
	var bar := tabs.get_tab_bar()
	for tab: int in _tab_bubbles:
		var bubble: Label = _tab_bubbles[tab]
		var rect := bar.get_tab_rect(tab) if tab < bar.tab_count and not bar.is_tab_hidden(tab) else Rect2()
		bubble.visible = int(bubble.get_meta(&"count", 0)) > 0 and rect.size.x > 0.0 and rect.position.x >= 0.0 \
				and rect.end.x <= bar.size.x + 1.0
		if not bubble.visible:
			continue
		bubble.size = bubble.get_combined_minimum_size()
		bubble.position = Vector2(rect.end.x - bubble.size.x * 0.5 - 3.0, rect.position.y - 5.0)  # centred on the pill's edge


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
		solves_label.text = Num.format(_shown_solves)
		return
	var target := Game.solves
	if target <= _shown_solves or absf(target - _shown_solves) <= maxf(0.5, target * 0.002):
		_shown_solves = target
	else:
		_shown_solves = lerpf(_shown_solves, target, 1.0 - exp(-delta * COUNTER_EASE))
	solves_label.text = Num.format(floorf(_shown_solves) if _shown_solves < target else _shown_solves)


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
		puzzle_view.rim_flash()  # V.7: the stage light flares with the sparks
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


## The goal card's two small slots: the next goals after the main one, each with its progress bar.
func _refresh_goal_strip(goals: Array) -> void:
	for i in goal_labels.size():
		var shown := i < goals.size()
		goal_labels[i].get_parent().visible = shown
		if not shown:
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
	var amount := Game.tap()
	if at == Vector2.INF and _showcase != null and _showcase.phase == "player":
		# Space while you're turning the cube yourself: csTimer's "hands back to the outer layers", not a hand-back
		# to the team (only a click or a pause does that).
		_key_session.left_hand = 1
		_key_session.right_hand = 1
		_tap_effects(amount, at)
		return
	if _showcase != null:
		for move in _showcase.tap():  # a tap plays the next move of the showcase solve
			puzzle_view.turn(move)
	else:
		puzzle_view.scramble_step()
	_tap_effects(amount, at)


## What every tap shows: a squash (not for key turns: the turn itself is the feedback), a click, a "+N" pop.
func _tap_effects(amount: float, at: Vector2, squash: bool = true) -> void:
	if squash:
		puzzle_view.squash()
	var size := 3 if puzzle_view.model == null else (puzzle_view.model.size if puzzle_view.model.size > 0 else 6)
	Audio.play_click(size)  # the Megaminx (size 0) clicks like a big cube
	if at == Vector2.INF:
		at = puzzle_view.get_global_rect().get_center()
	fx.pop("+%s" % Num.format(amount), at)


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
	_reset_key_session()
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


func _on_puzzle_unlocked(puzzle_id: String) -> void:
	_build_puzzle_row()
	puzzle_view.drop_in()
	Audio.play_unlock()
	if not _known_puzzles.has(puzzle_id):  # V.7: only a puzzle never had before (later runs unlock them again)
		_known_puzzles[puzzle_id] = true
		banner.push(puzzle_banner(puzzle_id))


## V.7: "New puzzle unlocked: 4×4".
func puzzle_banner(puzzle_id: String) -> Dictionary:
	var def := Content.get_puzzle(puzzle_id)
	return {"kind": "puzzle", "title": "New puzzle unlocked: %s" % def.get("name", puzzle_id), "name": def.get("name", puzzle_id),
			"subtitle": "%s moves a solve, %s Solves each. Share your helpers in the Puzzles tab."
					% [Num.format(Game.get_moves_per_solve(puzzle_id)), Num.format(Game.get_solve_value(puzzle_id))],
			"icon": Content.icon("big_cubes" if float(def.get("moves_per_solve", 0.0)) >= 60.0 else "small_cubes"),
			"category": &"puzzles"}


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
		_showcase.resumed.connect(_build_stage_chips)
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
	# Quarter turns a bit quicker than the pace, so a turn always ends before the next starts. The player's own key
	# turns (S.7) are snappy, like the Solve Station's.
	puzzle_view.turn_time = PLAYER_TURN_TIME if _showcase.phase == "player" \
			else clampf(0.7 / maxf(tps, 1.0), 0.05, PuzzleView3D.TURN_TIME)
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
		"player":  # S.7: your own key turns; the team takes over after a pause
			text = "[color=#ecedf2]Your turns[/color]   %s   [color=#5d6370]·  the team takes over when you pause[/color]" \
					% _moves_text(m, _showcase.player_moves, _showcase.player_moves.size())
		"solved":
			if _showcase.by_player:
				text = "[color=#3ccf8e]You solved it![/color]"
			else:
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
	return "Team best %s%s" % [Num.cube_time(time), "  ·  %s" % tier["name"] if not tier.is_empty() else ""]


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
	"first_block": "Block 1", "second_block": "Block 2", "cmll": "CMLL", "lse": "LSE",  # Roux (R.5)
	"eoline": "EOLine", "zz_f2l": "F2L", "last_layer": "Last layer",  # ZZ
	"gods_number": "God's Number",
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
		_locked_chip.show_locked(next, Content.get_puzzle(next)["name"], Num.format(cost), Game.solves >= cost)
	_layout_shelf()


## The shelf is one column of puzzles on the stage's left, two from SHELF_COLUMN_MAX puzzles on, so it always fits
## between the goal card and the bottom strip (V.4). Hidden while it has nothing to show.
func _layout_shelf() -> void:
	var shown := 0
	for chip: Control in puzzle_row.get_children():
		if chip.visible:
			shown += 1
	shelf.visible = shown > 0
	var columns := 1 if shown <= SHELF_COLUMN_MAX else 2
	if puzzle_row.columns != columns:
		puzzle_row.columns = columns


func _frame_beside_shelf() -> void:
	puzzle_view.frame_inset_left = shelf.size.x if shelf.visible else 0.0
	_place_lamp()


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
	news_panel.visible = not news.history.is_empty()  # V.4: no empty box; it appears with the first line
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
	if _is_up(solve_station) or not Game.claim_golden():
		return
	_on_golden_gone()
	solve_station.open_golden(Game.get_focused_puzzle_id(), Game.roll_golden_case_moves())


func _on_golden_finished(success: bool, buff: Dictionary) -> void:
	if success:
		news.push("golden", "Golden Scramble solved! %s" % buff.get("text", ""))
		fx.pop(String(buff.get("text", "")), buff_chip.get_global_rect().get_center() + Vector2(0, 40), &"PopSolve", 2.0)
	else:
		news.push("golden", "The golden case got away.")


## The golden button sits at the top right of the stage, under the goal card (V.4: off the cube, so a tap on the cube
## stays a tap), while a sticker glows ("Golden Scramble! 9s"); the top bar shows
## a running buff (a gold chip: "×7  Frenzy 24s").
func _refresh_golden() -> void:
	var glowing := Game.golden_glow_left > 0.0 and not solve_station.visible
	golden_button.visible = glowing
	if glowing:
		golden_button.text = "Golden Scramble!  %ds" % ceili(Game.golden_glow_left)
		golden_button.size = golden_button.get_combined_minimum_size()
		var rect := puzzle_view.get_global_rect()
		var top := stage_top.get_global_rect()
		golden_button.global_position = Vector2(rect.end.x - golden_button.size.x - 6.0, top.end.y + 4.0)
	if puzzle_view.is_golden_shown() != glowing and not solve_station.visible:
		puzzle_view.set_golden(glowing)
	# S.7: the TPS streak (taps and key turns). It multiplies a tap's team share, so it only shows once taps have one.
	streak_chip.visible = Game.streak > 0.005 and Game.get_tap_share() > 0.0
	if streak_chip.visible:
		streak_chip.set_stat("×%s" % Num.format(Game.get_streak_mult()), "%s TPS" % Num.format(Game.get_recent_tps()))
		streak_chip.tooltip_text = ("TPS streak. Keep turning or tapping steadily (more than %s a second): the team's share in every " \
				+ "tap (%s %% of its moves/s) counts up to ×%s. Stop and it drains.") % [
				Num.format(float(Content.TAPS["drain_per_second"]) / float(Content.TAPS["fill_per_tap"])),
				Num.format(Game.get_tap_share() * 100.0), Num.format(float(Content.TAPS["streak_max_mult"]))]
	flow_chip.visible = not Game.flow.is_empty()
	if flow_chip.visible:  # S.3: Flow from hand solves in the Solve Station
		flow_chip.set_stat("×%s" % Num.format(float(Game.flow["mult"])),
				Num.solve_time(float(Game.flow["left"])).get_slice(".", 0))
		flow_chip.tooltip_text = "Flow from your last hand solve: every move counts ×%s until the Flow runs out. Solve again to keep it." \
				% Num.format(float(Game.flow["mult"]))
	buff_chip.visible = not Game.buff.is_empty()
	if buff_chip.visible:
		var buff_name := String(Game.buff["id"])
		for def: Dictionary in Content.GOLDEN["buffs"]:
			if def["id"] == Game.buff["id"]:
				buff_name = def["name"]
		buff_chip.set_stat("×%s" % Num.format(float(Game.buff["mult"])), "%ds" % ceili(float(Game.buff["left"])))
		buff_chip.tooltip_text = "Golden Scramble reward: %s, ×%s for %d more seconds." % [buff_name,
				Num.format(float(Game.buff["mult"])), ceili(float(Game.buff["left"]))]


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
			"icon": Content.icon(def["icon"]), "category": &"lab", "title": def["name"], "line1": def["description"],
			"line2": line2, "owned": "✓" if done else "", "affordable": can_start, "active": is_running,
			"cost": "" if done or is_running else "%s Solves" % Num.format(float(def["cost"])),
		})
		(done_order if done else order).append(card)
	order.append_array(done_order)
	for index in order.size():
		lab_list.move_child(order[index], index)
	tabs.set_tab_title(LAB_TAB, "Lab · %s" % Num.clock(float(running["left"])) if not running.is_empty() else "Lab")
	set_tab_count(LAB_TAB, 0 if not running.is_empty() else startable)


func _on_lab_card_pressed(id: String) -> void:
	var def := Content.get_lab_project(id)
	if def.get("kind", "") == "method":
		Game.buy_method(def["method"])
	else:
		Game.start_research(id)
	_refresh()


func _on_state_reset() -> void:
	banner.clear()
	news = NewsFeed.new()
	_show_news()
	_rebuild_after_reset()


## A World Championship (6.2) started a new run: the screen goes back to the 2×2 like a new game, but the news feed
## keeps its lines and says what happened.
func _on_championship_won(trophies_won: int) -> void:
	compete_panel.close()
	news.push("championship", "World Champion! +%s %s, +%s %% moves. New run!" % [
		Num.format(float(trophies_won)), "trophy" if trophies_won == 1 else "trophies",
		Num.format(roundf((Game.get_trophy_mult() - 1.0) * 100.0))])
	Audio.play_unlock()
	banner.clear()  # the old run's moments are old news
	banner.push({"kind": "championship", "title": "World Champion!",  # V.7
			"subtitle": "+%s %s. A new run starts." % [Num.format(float(trophies_won)), "trophy" if trophies_won == 1 else "trophies"],
			"icon": Content.icon("stat_trophy"), "category": &"trophies"})
	_rebuild_after_reset()


func _rebuild_after_reset() -> void:
	puzzle_view.set_puzzle(Game.get_focused_puzzle_id())
	_reset_key_session()  # a championship or reset changes focus without focus_changed
	_start_showcase()
	_build_puzzle_row()
	_shown_solves = Game.solves
	_known_puzzles = Game.puzzles_reached.duplicate()
	_revealed.clear()
	for def: Dictionary in Content.BUILDINGS:
		if Game.is_building_unlocked(def["id"]):
			_revealed[def["id"]] = true
	_refresh()


func _on_purchased(kind: String, _id: String) -> void:
	if kind == "method":
		for id: String in StagedSolver.PUZZLES:  # a new method's tables are built once, now (Roux ~0.2 s)
			StagedSolver.warm_up(id, [Game.method])
	if kind == "method" and _showcase != null:
		_showcase.method = Game.method  # the next showcase solve uses it
	if kind == "method" and not Game.is_achievement_earned("method_" + Game.method):  # V.7: the first time only
		var learned := Content.get_method(Game.method)
		banner.push({"kind": "method", "title": "Method learned: %s" % String(learned.get("name", "")).trim_prefix("Learn "),
				"subtitle": String(learned.get("description", "")), "icon": Content.icon(String(learned.get("icon", "cfop"))),
				"category": &"lab"})
	if Game.automation_running:  # auto-buyers (6.3b) buy quietly (no click every second); the 0.1 s refresh shows it
		return
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
	perks_button.visible = Game.trophies > 0 or not Game.perks.is_empty()
	perks_button.text = Num.format(float(Game.trophies))  # the trophy icon says what it is; the tooltip says the rest
	perks_button.tooltip_text = "Trophy perks (click to open): %s unspent %s, +%s %% moves." % [Num.format(float(Game.trophies)),
		"trophy" if Game.trophies == 1 else "trophies", Num.format(roundf((Game.get_trophy_mult() - 1.0) * 100.0))]
	if perk_panel.visible:
		perk_panel.set_view(_perk_header(), _perk_views())
	tabs.set_tab_hidden(AUTO_TAB, not Game.is_system_unlocked("automation"))  # the Auto tab (6.3b) comes with its perk
	if tabs.current_tab == AUTO_TAB:
		automation_panel.refresh()


# --- Trophy perks (task 6.3) --------------------------------------------------------

func open_perks() -> void:
	perk_panel.open(_perk_header(), _perk_views())


func _perk_header() -> Dictionary:
	return {"trophies": Num.format(float(Game.trophies)), "unit": "unspent " + ("trophy" if Game.trophies == 1 else "trophies"),
		"bonus": "+%s %%" % Num.format(roundf((Game.get_trophy_mult() - 1.0) * 100.0))}


## A PerkNode view for every perk, from Game.
func _perk_views() -> Dictionary:
	var views := {}
	for def: Dictionary in Content.PERKS:
		var id: String = def["id"]
		var needs := PackedStringArray()
		for need: Variant in def.get("requires", []):
			if not Game.has_perk(str(need)):
				needs.append(Content.get_perk(str(need)).get("name", str(need)))
		views[id] = {
			"icon": Content.icon(def["icon"]),
			"title": def["name"],
			"description": def["description"],
			"cost": int(def["cost"]),
			"status": Game.get_perk_status(id),
			"affordable": Game.can_buy_perk(id),
			"soon": def.get("soon", ""),
			"needs": " and ".join(needs),
			"have": Num.format(float(Game.trophies)),
			"bonus": Num.format(Game.get_bonus_per_trophy() * 100.0),
		}
	return views


# --- Settings ----------------------------------------------------------------------

## Graphics and Reduce motion are applied here (main owns the views); audio and notation apply themselves in Settings.
func _apply_display_settings() -> void:
	puzzle_view.set_graphics(Settings.get_value("quality"))
	var reduce: bool = Settings.get_value("reduce_motion")
	# The desk background (V.3): High only; Low keeps the ColorRect's flat bg colour. Reduce motion stops the bokeh.
	background.material = _background_material if Settings.get_value("quality") == "high" else null
	var bg := get_theme_color(&"bg", &"Palette")  # the shader's gradient follows the palette (CLAUDE.md rule 9)
	_background_material.set_shader_parameter("base_top", bg.lightened(0.02))
	_background_material.set_shader_parameter("base_bottom", bg.darkened(0.2))
	_background_material.set_shader_parameter("drift", 0.0 if reduce else 1.0)
	puzzle_view.set_reduce_motion(reduce)
	fx.particles_enabled = not reduce
	for id: String in _chips:
		(_chips[id] as PuzzleChip).set_reduce_motion(reduce)
	ShopCard.reduce_motion = reduce  # no breathing cost bars (V.5)
	UiFx.reduce_motion = reduce  # the motion kit (V.6): panels, pops, squashes, rolls
	UiFx.backdrop_blur = Settings.get_value("quality") == "high"  # open panels blur the screen behind them on High


## The background's lamp glow sits behind the puzzle, wherever the layout puts it. Called from _refresh (10×/s),
## so it follows any layout change (an ancestor moving the view doesn't change the view's own rect).
func _place_lamp() -> void:
	var screen := get_viewport_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var rect := puzzle_view.get_global_rect()  # the puzzle sits in the part right of the shelf (V.4): the lamp too
	var lamp := Vector2(rect.position.x + (puzzle_view.frame_inset_left + rect.size.x) / 2.0, rect.get_center().y) / screen
	if not lamp.is_equal_approx(_lamp_center):
		_lamp_center = lamp
		_background_material.set_shader_parameter("lamp_center", lamp)


func _on_setting_changed(key: String) -> void:
	if key in ["quality", "reduce_motion"]:
		_apply_display_settings()
	elif key == "notation":
		_refresh()
	elif key == "solve_keys":
		_reset_key_session()
