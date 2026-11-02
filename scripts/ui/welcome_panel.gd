class_name WelcomePanel
extends Control
## "Welcome back" panel (task 3.6): time away, Solves earned offline and a Collect button. Also shows the
## damaged-save notice (Game.load_notice) when there is one. Display only: main.gd fills it and reacts to `collected`.

signal collected(solves: float)

@onready var _away: Label = %Away
@onready var _earned: Label = %Earned
@onready var _detail: Label = %Detail
@onready var _notice: Label = %Notice
@onready var _collect: Button = %CollectButton

var _solves := 0.0


func _ready() -> void:
	_collect.pressed.connect(collect)


## Shows the panel. `report` is Game.offline_report ({seconds, solves} or {}); `notice` is Game.load_notice.
## Returns false (and stays hidden) if there's nothing to show.
func show_report(report: Dictionary, notice: String) -> bool:
	var earned := not report.is_empty()
	if not earned and notice == "":
		return false
	_solves = float(report.get("solves", 0.0))
	_away.visible = earned
	_earned.visible = earned
	_detail.visible = earned
	if earned:
		_away.text = "You were away for %s." % Num.format_duration(report["seconds"])
		_earned.text = "+%s Solves" % Num.format(_solves)
	_notice.visible = notice != ""
	_notice.text = notice
	_collect.text = "Collect" if earned else "OK"
	show()
	return true


func collect() -> void:
	hide()
	collected.emit(_solves)


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"tap", false)):
		collect()
		get_viewport().set_input_as_handled()
