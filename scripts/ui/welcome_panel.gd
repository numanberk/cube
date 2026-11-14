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
@onready var _dim: ColorRect = %Dim
@onready var _panel: Control = %Panel

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
		_earned.visible = _solves > 0.0
		_earned.text = "+%s Solves" % Num.format(_solves)
		var lines: Array[String] = []
		if _solves > 0.0:
			lines.append("Your helpers kept solving while you were gone.")
		if String(report.get("research", "")) != "":  # the Lab finished something meanwhile (5.6)
			lines.append("The Lab finished %s." % report["research"])
		lines.append_array(away_lines(report))
		_detail.text = "\n".join(lines)
	_notice.visible = notice != ""
	_notice.text = notice
	_collect.text = "Collect" if earned else "OK"
	UiFx.open_panel(self, _dim, _panel)  # V.6
	return true


## 7.9: mastery levels gained and achievements reached while away, as lines ("3×3 mastery Lv 5 → 8, 4×4 Lv 2 → 3.",
## "Achievements: Solver VI, Turning Point III and 2 more.").
static func away_lines(report: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	var mastery: Dictionary = report.get("mastery", {})
	if not mastery.is_empty():
		var parts := PackedStringArray()
		for id: String in mastery:
			parts.append("%s Lv %d → %d" % [Content.get_puzzle(id).get("name", id), int(mastery[id][0]), int(mastery[id][1])])
		lines.append("Mastery: %s." % ", ".join(parts))
	var reached: Array = report.get("achievements", [])
	if not reached.is_empty():
		var names := PackedStringArray()
		for id: Variant in reached.slice(0, 3):
			names.append(String(Content.get_achievement(str(id)).get("name", id)))
		var more := reached.size() - names.size()
		lines.append("%s: %s%s." % ["Achievement" if reached.size() == 1 else "Achievements", ", ".join(names),
				" and %d more" % more if more > 0 else ""])
	return lines


func collect() -> void:
	if not visible or UiFx.is_closing(self):
		return  # already collected (the panel is fading out)
	UiFx.close_panel(self, _dim, _panel)
	collected.emit(_solves)


func _unhandled_input(event: InputEvent) -> void:
	if visible and not UiFx.is_closing(self) and (event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"tap", false)):
		collect()
		get_viewport().set_input_as_handled()
