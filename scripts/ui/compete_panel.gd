class_name CompetePanel
extends Control
## The Compete screen (task 6.1): what a World Championship would give right now (trophies, the moves bonus before and
## after, progress to the next trophy, the formula) and exactly what you keep and what starts over
## (Content.CHAMPIONSHIP). Display only: main.gd opens it with Game.get_championship_preview(), refreshes it while
## open, and plays "Finals" while it's up. The Compete button emits `compete_pressed` (main.gd calls Game.compete(),
## task 6.2); it's disabled with no trophy to win, or while `compete_enabled` is off (a preview). Escape, Close,
## "Not yet" or a click outside close it.

signal closed
signal compete_pressed
signal next_run_picked(id: String)  ## 8.4: a challenge for the next run ("" = a normal run)
signal give_up_pressed              ## 8.4: give up the challenge this run is under
signal venue_picked(id: String)     ## 8.4b: the next run's host city ("" = none)

@onready var _dim: ColorRect = %Dim
@onready var _panel: Control = %Panel
@onready var _close: Button = %CloseButton
@onready var _gain: Label = %Gain
@onready var _moves_now: StatChip = %MovesNow
@onready var _moves_after: StatChip = %MovesAfter
@onready var _next_label: Label = %NextLabel
@onready var _next_bar: ProgressBar = %NextBar
@onready var _formula: Label = %Formula
@onready var _keep_list: VBoxContainer = %KeepList
@onready var _reset_list: VBoxContainer = %ResetList
@onready var _unlocks: Label = %Unlocks
@onready var _not_yet: Button = %NotYetButton
@onready var _compete: Button = %CompeteButton
@onready var _hint: Label = %CompeteHint
@onready var _intro: Label = %Intro

const LIST_WIDTH := 235.0      ## the keep / starts-over columns
const NEXT_RUN_WIDTH := 440.0  ## the "Next run" column (8.4)

var compete_enabled := false  ## false = a preview (the button stays disabled); main.gd turns it on (6.2)
var preview: Dictionary = {}  ## the last Game.get_championship_preview() shown
var _next_run: VBoxContainer           ## 8.4: the "Next run" column, built in code beside the keep/reset lists
var _running_label: Label
var _give_up: Button
var _option_flow: HFlowContainer
var _option_buttons: Dictionary = {}   ## challenge id ("" = normal) -> Button
var _option_text: Label
var _venue_title: Label                ## 8.4b: "Host city" chips under the challenges
var _venue_flow: HFlowContainer
var _venue_buttons: Dictionary = {}    ## venue id -> Button
var _venue_text: Label


func _ready() -> void:
	_compete.set_meta(&"no_press_sound", true)  # V.9: winning plays "unlock" (Audio.NO_PRESS_SOUND)
	_close.pressed.connect(close)
	_not_yet.pressed.connect(close)
	_dim.gui_input.connect(_on_dim_input)
	_compete.pressed.connect(func() -> void: compete_pressed.emit())
	_fill_list(_keep_list, Content.CHAMPIONSHIP["keeps"])
	_fill_list(_reset_list, Content.CHAMPIONSHIP["resets"])
	_unlocks.text = Content.CHAMPIONSHIP["unlocks"]
	_build_next_run()


func _build_next_run() -> void:
	_next_run = VBoxContainer.new()
	_next_run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_run.visible = false
	_keep_list.get_parent().get_parent().add_child(_next_run)
	# With the third column the panel grows wider instead of squeezing the two lists into wrapped lines.
	(_keep_list.get_parent() as Control).custom_minimum_size = Vector2(LIST_WIDTH, 0)
	(_reset_list.get_parent() as Control).custom_minimum_size = Vector2(LIST_WIDTH, 0)
	_next_run.custom_minimum_size = Vector2(NEXT_RUN_WIDTH, 0)
	var title := Label.new()
	title.theme_type_variation = &"CardTitle"
	title.text = "Next run"
	_next_run.add_child(title)
	_running_label = Label.new()
	_running_label.theme_type_variation = &"CardLine"
	_running_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next_run.add_child(_running_label)
	_give_up = Button.new()
	_give_up.theme_type_variation = &"SubtleButton"
	_give_up.focus_mode = Control.FOCUS_NONE
	_give_up.text = "Give up this challenge"
	_give_up.tooltip_text = "The rule is lifted and the run goes on. No reward; you can pick it again later."
	_give_up.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_give_up.pressed.connect(func() -> void: give_up_pressed.emit())
	_next_run.add_child(_give_up)
	var flow := HFlowContainer.new()
	_next_run.add_child(flow)
	_option_flow = flow
	_option_text = Label.new()
	_option_text.theme_type_variation = &"FaintLabel"
	_option_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_option_text.custom_minimum_size = Vector2(NEXT_RUN_WIDTH, 0)
	_next_run.add_child(_option_text)
	_venue_title = Label.new()
	_venue_title.theme_type_variation = &"CardTitle"
	_venue_title.text = "Host city"
	_next_run.add_child(_venue_title)
	_venue_flow = HFlowContainer.new()
	_next_run.add_child(_venue_flow)
	_venue_text = Label.new()
	_venue_text.theme_type_variation = &"FaintLabel"
	_venue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_venue_text.custom_minimum_size = Vector2(NEXT_RUN_WIDTH, 0)
	_next_run.add_child(_venue_text)


## 8.4: the "Next run" column. view: {open (challenges exist for this player), running: {name, text, reward} or {},
## options: [{id, name, text, reward, done, picked}] ("" = a normal run)}.
func set_next_run(view: Dictionary) -> void:
	_next_run.visible = bool(view.get("open", false))
	_unlocks.visible = not _next_run.visible  # ("After your first championship…" is old news by then, and the room is needed)
	_intro.visible = not _next_run.visible    # (the player has competed before: the room goes to the next run)
	if not _next_run.visible:
		return
	var running: Dictionary = view.get("running", {})
	_running_label.visible = not running.is_empty()
	_give_up.visible = not running.is_empty()
	if not running.is_empty():
		_running_label.text = "Now: %s. Win this championship for %s." % [running["name"], running["reward"]]
		_running_label.tooltip_text = String(running["text"])
	var picked_text := ""
	for option: Dictionary in view.get("options", []):
		var id := String(option["id"])
		var button: Button = _option_buttons.get(id)
		if button == null:
			button = Button.new()
			button.theme_type_variation = &"ToggleChip"
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func() -> void: next_run_picked.emit(id))
			_option_flow.add_child(button)
			_option_buttons[id] = button
		button.text = String(option["name"]) + ("  ✓" if option.get("done", false) else "")
		button.disabled = bool(option.get("done", false)) or bool(option.get("running", false))
		button.set_pressed_no_signal(bool(option.get("picked", false)))
		button.tooltip_text = "%s Reward: %s.%s" % [option.get("text", ""), option.get("reward", ""),
				" Done." if option.get("done", false) else ""] if id != "" else "No rule."
		if option.get("picked", false):
			picked_text = "" if id == "" else "%s Reward: %s." % [option.get("text", ""), option.get("reward", "")]
	_option_text.text = picked_text
	# 8.4b: the host cities on offer (the same until the next championship); a click picks one, another click un-picks.
	var venues: Array = view.get("venues", [])
	for id: String in _venue_buttons.keys():
		if not venues.any(func(v: Dictionary) -> bool: return v["id"] == id):
			_venue_buttons[id].queue_free()
			_venue_buttons.erase(id)
	var venue_text := "No host city picked: no twist." if not venues.is_empty() else ""
	for venue: Dictionary in venues:
		var id := String(venue["id"])
		var button: Button = _venue_buttons.get(id)
		if button == null:
			button = Button.new()
			button.theme_type_variation = &"ToggleChip"
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func() -> void: venue_picked.emit("" if bool(_venue_buttons[id].get_meta(&"picked", false)) else id))
			_venue_flow.add_child(button)
			_venue_buttons[id] = button
		button.text = String(venue["name"])
		button.tooltip_text = String(venue["text"])
		button.set_meta(&"picked", bool(venue.get("picked", false)))
		button.set_pressed_no_signal(bool(venue.get("picked", false)))
		if venue.get("picked", false):
			venue_text = String(venue["text"])
	if String(view.get("venue_now", "")) != "":  # (the chips show which is next: the line stays one or two short lines)
		_venue_title.text = "Host city  ·  now %s" % view["venue_now"]
	else:
		_venue_title.text = "Host city"
	_venue_title.visible = not venues.is_empty()
	_venue_text.text = venue_text


func open(data: Dictionary) -> void:
	set_preview(data)
	UiFx.open_panel(self, _dim, _panel)  # V.6


func close() -> void:
	if not visible or UiFx.is_closing(self):
		return
	UiFx.close_panel(self, _dim, _panel)
	closed.emit()


## Fills the screen from Game.get_championship_preview():
## {run_solves, trophies, gain, after, mult_now, mult_after, next_at, next_progress}.
func set_preview(data: Dictionary) -> void:
	preview = data
	var gain := int(data.get("gain", 0))
	_gain.text = "+%s %s" % [Num.format(float(gain)), "trophy" if gain == 1 else "trophies"] if gain > 0 \
			else "No trophies yet"
	_moves_now.set_stat(bonus_text(float(data.get("mult_now", 1.0))), "now")  # V.8: StatChips for the numbers
	_moves_after.set_stat(bonus_text(float(data.get("mult_after", 1.0))), "after")
	var run := float(data.get("run_solves", 0.0))
	var next_at := float(data.get("next_at", 0.0))
	_next_label.text = "%s / %s Solves this run for %s" % [Num.format(run), Num.format(next_at),
			"your first trophy" if gain == 0 else "trophy %s" % Num.format(float(gain + 1))]
	_next_bar.value = float(data.get("next_progress", 0.0))
	var gain_mult := float(data.get("gain_mult", 1.0))
	_formula.text = "Trophies = √(Solves this run ÷ %s)%s, rounded down. Each unspent trophy: +%s %% moves." % [
		Num.format(float(Content.CHAMPIONSHIP["divisor"])),
		"" if is_equal_approx(gain_mult, 1.0) else " × %s" % Num.format(gain_mult),
		Num.format(float(data.get("bonus_per_trophy", Content.CHAMPIONSHIP["bonus_per_trophy"])) * 100.0),
	]
	_compete.disabled = not compete_enabled or gain < 1
	_compete.text = "Compete" if gain < 1 else "Compete for %s" % _gain.text.trim_prefix("+")
	_hint.visible = not compete_enabled
	_hint.text = "Preview: entering the championship opens in the next update."


## "+0 %", "+102 %": a trophy multiplier as the bonus it gives.
static func bonus_text(mult: float) -> String:
	return "+%s %%" % Num.format(roundf((mult - 1.0) * 100.0))


func _fill_list(list: VBoxContainer, lines: Array) -> void:
	for child in list.get_children():
		child.queue_free()
	for line: String in lines:
		var label := Label.new()
		label.theme_type_variation = &"CardLine"
		label.text = "·  " + line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()
