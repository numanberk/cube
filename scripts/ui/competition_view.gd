class_name CompetitionView
extends VBoxContainer
## The Goals screen's Competitions tab (task 8.3b, D19): one of three states.
##   register: pick a tier (chips; a locked one says what opens it), then an event: each puzzle you have with your
##     average now, the tier's mid-field average, your best medal there and a Register button.
##   running: the competition's clock and round, "Take your attempt" (your own Solve Station solve as one attempt of
##     this round), and the result sheet of the last finished round (you highlighted, a line where the cut is).
##   result: the last competition's placing, medal, average, records and drop, until dismissed.
## Reads Game and calls enter_competition / clear_competition_result; no rules here. Uses Game by name (tests use it
## untyped). GoalsPanel builds it and calls refresh(); `attempt_requested` asks main.gd to open the Solve Station.

signal attempt_requested(puzzle_id: String)

const StickerScene := preload("res://scenes/icon_sticker.tscn")
const MEDAL_NAMES := {"gold": "Gold", "silver": "Silver", "bronze": "Bronze"}
const SHEET_ROWS := 12  ## result sheet rows shown at once (it scrolls)

var selected_tier := ""
var _summary: Label
var _tier_row: HBoxContainer
var _tier_chips: Dictionary = {}    ## tier id -> Button
var _tier_note: Label
var _events: VBoxContainer
var _event_rows: Dictionary = {}    ## puzzle id -> {row, text, medal, button}
var _register: Control
var _running: Control
var _run_title: Label
var _run_clock: Label
var _run_note: Label
var _attempt: Button
var _sheet_title: Label
var _sheet: VBoxContainer
var _result: Control
var _result_title: Label
var _result_text: Label
var _dismiss: Button
var _sheet_key := ""


func _ready() -> void:
	_summary = _label(&"CardLine")
	add_child(_summary)
	# --- register ---
	_register = VBoxContainer.new()
	_register.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_register)
	_tier_row = HBoxContainer.new()
	_register.add_child(_tier_row)
	for tier: Dictionary in Content.COMPETITIONS["tiers"]:
		var chip := Button.new()
		chip.theme_type_variation = &"ToggleChip"
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.text = String(tier["name"])
		chip.pressed.connect(select_tier.bind(String(tier["id"])))
		_tier_row.add_child(chip)
		_tier_chips[tier["id"]] = chip
	_tier_note = _label(&"FaintLabel")
	_tier_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_register.add_child(_tier_note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_register.add_child(scroll)
	_events = VBoxContainer.new()
	_events.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_events)
	for puzzle: Dictionary in Content.PUZZLES:
		var view := _event_row(puzzle)
		_events.add_child(view["row"])
		_event_rows[puzzle["id"]] = view
	# --- running ---
	_running = VBoxContainer.new()
	_running.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_running)
	var top := HBoxContainer.new()
	_running.add_child(top)
	var titles := VBoxContainer.new()
	titles.theme_type_variation = &"TightBox"
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(titles)
	_run_title = _label(&"CardTitle")
	titles.add_child(_run_title)
	_run_note = _label(&"CardLine")
	titles.add_child(_run_note)
	_run_clock = _label(&"StatValue")
	_run_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_run_clock)
	_attempt = Button.new()
	_attempt.focus_mode = Control.FOCUS_NONE
	_attempt.text = "Take your attempt"
	_attempt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_attempt.tooltip_text = "Solve the event's puzzle yourself in the Solve Station: your time replaces the team's worst attempt of this round if it's faster. Once a round; it can only help."
	_attempt.pressed.connect(func() -> void: attempt_requested.emit(String(Game.competition.get("puzzle", ""))))
	top.add_child(_attempt)
	_sheet_title = _label(&"FaintLabel")
	_running.add_child(_sheet_title)
	var sheet_scroll := ScrollContainer.new()
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_running.add_child(sheet_scroll)
	_sheet = VBoxContainer.new()
	_sheet.theme_type_variation = &"TightBox"
	_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_scroll.add_child(_sheet)
	# --- result ---
	_result = PanelContainer.new()
	_result.theme_type_variation = &"ItemCard"
	add_child(_result)
	var result_row := HBoxContainer.new()
	_result.add_child(result_row)
	var result_text := VBoxContainer.new()
	result_text.theme_type_variation = &"TightBox"
	result_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_row.add_child(result_text)
	_result_title = _label(&"CardTitle")
	result_text.add_child(_result_title)
	_result_text = _label(&"CardLine")
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_text.add_child(_result_text)
	_dismiss = Button.new()
	_dismiss.focus_mode = Control.FOCUS_NONE
	_dismiss.text = "OK"
	_dismiss.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dismiss.pressed.connect(func() -> void:
		Game.clear_competition_result()
		refresh())
	result_row.add_child(_dismiss)
	move_child(_result, 1)  # the last result sits on top, under the summary
	refresh()


func _event_row(puzzle: Dictionary) -> Dictionary:
	var row := PanelContainer.new()
	row.theme_type_variation = &"ItemCard"
	var box := HBoxContainer.new()
	row.add_child(box)
	var texts := VBoxContainer.new()
	texts.theme_type_variation = &"TightBox"
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(texts)
	texts.add_child(_label(&"CardTitle", String(puzzle["name"])))
	var text := _label(&"CardLine")
	texts.add_child(text)
	var medal := _label(&"StatValueGold")
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(medal)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.text = "Register"
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(register.bind(String(puzzle["id"])))
	box.add_child(button)
	return {"row": row, "text": text, "medal": medal, "button": button}


## "register", "running" or "result": what the tab shows now.
func state() -> String:
	if not Game.competition.is_empty():
		return "running"
	return "result" if not Game.get_competition_result().is_empty() else "register"


func select_tier(tier: String) -> void:
	selected_tier = tier
	refresh()


## Registers for the selected tier with this event. Returns true if it started.
func register(puzzle_id: String) -> bool:
	var started: bool = Game.enter_competition(selected_tier, puzzle_id)
	refresh()
	return started


func refresh() -> void:
	if not is_node_ready():
		return
	var points: int = Game.get_medal_points()
	_summary.text = "Medal points: %d  ·  +%s %% all moves, for good  ·  competitions entered: %d" % [points,
			GoalsPanel._percent(Game.get_medal_mult() - 1.0), Game.competitions_entered]
	_summary.tooltip_text = "A medal in a final is kept per competition and event. Bronze 1, silver 2, gold 3 points, times the competition's weight (Local 1 … World Cup 5). Each point: +%s %% all moves." \
			% GoalsPanel._percent(float(Content.COMPETITIONS["bonus_per_point"]))
	var now := state()
	_register.visible = now != "running"
	_running.visible = now == "running"
	_result.visible = now == "result"
	if now == "running":
		_refresh_running()
		return
	if now == "result":
		var result: Dictionary = Game.get_competition_result()
		_result_title.text = result_title(result)
		_result_text.text = result_text(result)
	_refresh_register()


func _refresh_register() -> void:
	if selected_tier == "" or not Game.is_competition_tier_open(selected_tier):
		selected_tier = ""
		for tier: Dictionary in Content.COMPETITIONS["tiers"]:  # the highest open one
			if Game.is_competition_tier_open(String(tier["id"])):
				selected_tier = String(tier["id"])
	var tiers: Array = Content.COMPETITIONS["tiers"]
	for i in tiers.size():
		var id := String(tiers[i]["id"])
		var chip: Button = _tier_chips[id]
		var open: bool = Game.is_competition_tier_open(id)
		chip.disabled = not open
		chip.set_pressed_no_signal(id == selected_tier)
		chip.tooltip_text = "" if open else "Win any medal at the %s first." % tiers[i - 1]["name"] if i > 0 else ""
	var tier := Content.get_competition_tier(selected_tier)
	if tier.is_empty():
		_tier_note.text = "Competitions open with the Competition Circuit perk."
		_events.visible = false
		return
	_events.visible = true
	var rounds: Array = tier["rounds"]
	_tier_note.text = "%s: %s of real time (it goes on while the game is closed)  ·  %d entrants  ·  %s  ·  a medal: %d to %d points and a collection item. Your team's average is taken when you register." % [
			tier["name"], length_text(float(tier["seconds"])), int(tier["field"]),
			"a final only" if rounds.size() == 1 else "%d rounds (the best %s go on)" % [rounds.size(),
					", then ".join(rounds.slice(0, rounds.size() - 1).map(func(n: Variant) -> String: return str(n)))],
			int(tier["weight"]), 3 * int(tier["weight"])]
	for id: String in _event_rows:
		var view: Dictionary = _event_rows[id]
		var has: bool = Game.is_puzzle_unlocked(id)
		(view["row"] as Control).visible = has
		if not has:
			continue
		var mine: float = Game.get_competition_average(id)
		var field := Content.competition_average(id, float(tier["rating"]))
		(view["text"] as Label).text = "Your average now: %s  ·  mid-field here: %s  ·  %s" % [Num.solve_time(mine),
				Num.solve_time(field), chance_text(Game.get_competition_rating(id) - float(tier["rating"]))]
		var record: Dictionary = Game.competition_records.get(id, {})
		(view["text"] as Label).tooltip_text = "Your average comes from your team's moves a second on the %s (its share of the helpers, your kit, mastery, trophies).%s" % [
				Content.get_puzzle(id)["name"], "" if record.is_empty() else "\nOfficial records: single %s, average %s." % [
						Num.solve_time(float(record["single"])), Num.solve_time(float(record["average"]))]]
		var medal: String = Game.get_competition_medal(selected_tier, id)
		(view["medal"] as Label).text = MEDAL_NAMES.get(medal, "")
		(view["button"] as Button).disabled = not Game.can_enter_competition(selected_tier, id)


## How a team this far above (+) or below the tier's rating should do, in words.
static func chance_text(rating_gap: float) -> String:
	if rating_gap >= 2.0:
		return "you're the favourite"
	if rating_gap >= 1.0:
		return "a medal is likely"
	if rating_gap >= 0.0:
		return "a medal is possible"
	if rating_gap >= -1.0:
		return "a long shot"
	return "out of reach for now"


func _refresh_running() -> void:
	var view: Dictionary = Game.get_competition_view()
	var tier := Content.get_competition_tier(String(view["tier"]))
	var total := (tier["rounds"] as Array).size()
	var puzzle := String(Content.get_puzzle(String(view["puzzle"]))["name"])
	_run_title.text = "%s  ·  %s" % [tier["name"], puzzle]
	_run_clock.text = Num.clock(float(view["left"]))
	var rounds: Array = view["rounds"]
	var index := int(view["round"])
	var round_name := round_label(tier, index)
	if view["out"]:
		_run_note.text = "You're out. The results are final when this round is scored."
	elif index < total:
		_run_note.text = "%s under way: results in %s  ·  your team's average: %s" % [round_name,
				Num.clock(float(view["round_left"])), Num.solve_time(float(view["average"]))]
	else:
		_run_note.text = "Scoring the final…"
	_attempt.visible = bool(view["can_attempt"]) and can_hand_solve(String(view["puzzle"]))
	if rounds.is_empty():
		_sheet_title.text = "No results yet. %d entrants, five attempts each; the average drops the best and the worst." % int(view["field"])
		_fill_sheet({}, "")
		return
	var last: Dictionary = rounds.back()
	_sheet_title.text = "%s: results%s" % [last["name"], "" if int(last["advance"]) == 0 else "  ·  the best %d go on" % int(last["advance"])]
	_fill_sheet(last, "%s:%d:%s" % [Game.competition.get("seed", 0), rounds.size(), str(Game.competition.get("hand", {}))])


## Can the Solve Station solve this puzzle (cubes only: not the Megaminx)? Only then is there a hand attempt.
static func can_hand_solve(puzzle_id: String) -> bool:
	var model := PuzzleShapes.from_id(puzzle_id)
	return model != null and model.size > 0


## A length for a sentence: "15 minutes", "45 minutes", "2 hours", "1 h 30 min".
static func length_text(seconds: float) -> String:
	var minutes := roundi(seconds / 60.0)
	if minutes < 60:
		return "%d minutes" % minutes
	if minutes % 60 == 0:
		return "%d hours" % (minutes / 60) if minutes != 60 else "1 hour"
	return "%d h %d min" % [minutes / 60, minutes % 60]


## One line for the news feed and Welcome back: the title, then the details.
static func result_line(result: Dictionary) -> String:
	var text := result_text(result)
	if String(result.get("medal", "")) == "" and result.get("final", false):
		text = text.substr(text.find("  ·  ") + 5)  # the title already says the placing
	var title := result_title(result)
	return "%s%s %s" % [title, "" if title.ends_with("!") else ".", text.left(1).to_upper() + text.substr(1)]


## The name of round `index` of a tier ("Final" for the last).
static func round_label(tier: Dictionary, index: int) -> String:
	var total := (tier["rounds"] as Array).size()
	var names: Array = Content.COMPETITIONS["round_names"]
	if index >= total - 1:
		return String(names[3])
	if index == total - 2 and total >= 3:
		return String(names[2])
	return String(names[mini(index, 1)])


## The result sheet of a finished round: place, name, average, best single; you bright, a rule under the cut.
func _fill_sheet(played: Dictionary, key: String) -> void:
	if key == _sheet_key:
		return  # the same sheet as last time: nothing to rebuild
	_sheet_key = key
	for child in _sheet.get_children():
		_sheet.remove_child(child)
		child.queue_free()
	if played.is_empty():
		return
	var results: Array = played["results"]
	for row: Dictionary in results:
		var line := HBoxContainer.new()
		var variation := &"CardTitle" if row["you"] else &"CardLine"
		var place := _label(variation, "%d." % int(row["place"]))
		place.custom_minimum_size = Vector2(44, 0)
		line.add_child(place)
		var name := _label(variation, "%s%s" % [row["name"], "  (your own solve counted)" if row.get("hand", false) else ""])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		var average := _label(variation, Num.solve_time(float(row["average"])))
		average.custom_minimum_size = Vector2(110, 0)
		average.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(average)
		var single := _label(&"FaintLabel", "best %s" % Num.solve_time(float(row["single"])))
		single.custom_minimum_size = Vector2(140, 0)
		single.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(single)
		_sheet.add_child(line)
		if int(played["advance"]) > 0 and int(row["place"]) == int(played["advance"]):
			var rule := HSeparator.new()
			rule.theme_type_variation = &"TitleRule"
			_sheet.add_child(rule)


## "Regional Championship · 3×3: Silver!" / "…: 11th of 16".
static func result_title(result: Dictionary) -> String:
	var tier := String(Content.get_competition_tier(String(result.get("tier", ""))).get("name", ""))
	var puzzle := String(Content.get_puzzle(String(result.get("puzzle", ""))).get("name", ""))
	var medal := String(result.get("medal", ""))
	if medal != "":
		return "%s  ·  %s: %s!" % [tier, puzzle, MEDAL_NAMES.get(medal, medal)]
	if result.get("final", false):
		return "%s  ·  %s: %s of %d" % [tier, puzzle, ordinal(int(result.get("place", 0))), int(result.get("field", 0))]
	return "%s  ·  %s: out in the %s" % [tier, puzzle, String(result.get("round", "")).to_lower()]


## The line under it: placing, average, records, what the medal gave.
static func result_text(result: Dictionary) -> String:
	var parts := PackedStringArray()
	if result.get("final", false):
		parts.append("%s in the final" % ordinal(int(result.get("place", 0))))
	else:
		parts.append("%s of %d, not enough to go on" % [ordinal(int(result.get("place", 0))), int(result.get("field", 0))])
	parts.append("average %s%s" % [Num.solve_time(float(result.get("average", 0.0))), " (a record!)" if result.get("pb_average", false) else ""])
	parts.append("best single %s%s" % [Num.solve_time(float(result.get("single", 0.0))), " (a record!)" if result.get("pb_single", false) else ""])
	if String(result.get("medal", "")) != "":
		if result.get("improved", false):
			var weight := int(Content.get_competition_tier(String(result.get("tier", ""))).get("weight", 0))
			parts.append("your best medal here: %d points" % (int(result.get("points", 0)) * weight))
		else:
			parts.append("you already had a medal as good here")
		var item := Content.get_collection_item(String(result.get("drop", "")))
		if not item.is_empty():
			parts.append("you won: %s" % item["name"])
	return "  ·  ".join(parts) + "."


static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


func _label(variation: StringName, text: String = "") -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label
