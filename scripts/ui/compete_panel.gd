class_name CompetePanel
extends Control
## The Compete screen (task 6.1): what a World Championship would give right now (trophies, the moves bonus before and
## after, progress to the next trophy, the formula) and exactly what you keep and what starts over
## (Content.CHAMPIONSHIP). Display only: main.gd opens it with Game.get_championship_preview(), refreshes it while
## open, and plays "Finals" while it's up. The Compete button emits `compete_pressed`; it stays disabled until the
## championship reset exists (6.2 sets `compete_enabled`). Escape, Close, "Not yet" or a click outside close it.

signal closed
signal compete_pressed

@onready var _dim: ColorRect = %Dim
@onready var _close: Button = %CloseButton
@onready var _gain: Label = %Gain
@onready var _bonus: Label = %Bonus
@onready var _next_label: Label = %NextLabel
@onready var _next_bar: ProgressBar = %NextBar
@onready var _formula: Label = %Formula
@onready var _keep_list: VBoxContainer = %KeepList
@onready var _reset_list: VBoxContainer = %ResetList
@onready var _unlocks: Label = %Unlocks
@onready var _not_yet: Button = %NotYetButton
@onready var _compete: Button = %CompeteButton
@onready var _hint: Label = %CompeteHint

var compete_enabled := false  ## the reset (6.2) isn't built yet: the button is a preview
var preview: Dictionary = {}  ## the last Game.get_championship_preview() shown


func _ready() -> void:
	_close.pressed.connect(close)
	_not_yet.pressed.connect(close)
	_dim.gui_input.connect(_on_dim_input)
	_compete.pressed.connect(func() -> void: compete_pressed.emit())
	_fill_list(_keep_list, Content.CHAMPIONSHIP["keeps"])
	_fill_list(_reset_list, Content.CHAMPIONSHIP["resets"])
	_unlocks.text = Content.CHAMPIONSHIP["unlocks"]


func open(data: Dictionary) -> void:
	set_preview(data)
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


## Fills the screen from Game.get_championship_preview():
## {run_solves, trophies, gain, after, mult_now, mult_after, next_at, next_progress}.
func set_preview(data: Dictionary) -> void:
	preview = data
	var gain := int(data.get("gain", 0))
	_gain.text = "+%s %s" % [Num.format(float(gain)), "trophy" if gain == 1 else "trophies"] if gain > 0 \
			else "No trophies yet"
	_bonus.text = "Moves on every puzzle: %s → %s" % [bonus_text(float(data.get("mult_now", 1.0))),
			bonus_text(float(data.get("mult_after", 1.0)))]
	var run := float(data.get("run_solves", 0.0))
	var next_at := float(data.get("next_at", 0.0))
	_next_label.text = "%s / %s Solves this run for %s" % [Num.format(run), Num.format(next_at),
			"your first trophy" if gain == 0 else "trophy %s" % Num.format(float(gain + 1))]
	_next_bar.value = float(data.get("next_progress", 0.0))
	_formula.text = "Trophies = √(Solves this run ÷ %s), rounded down. Each unspent trophy: +%s %% moves." % [
		Num.format(float(Content.CHAMPIONSHIP["divisor"])),
		Num.format(float(Content.CHAMPIONSHIP["bonus_per_trophy"]) * 100.0),
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
