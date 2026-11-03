class_name SolveStation
extends Control
## The Solve Station (task S.1): solve the puzzles yourself, csTimer-style. A full-screen overlay with its own 3D puzzle,
## turned with the keyboard (Content.SOLVE_KEYS, by physical key), a WCA scramble, inspection, a big timer and this
## session's times. The rules live in SolveSession; this script only shows them and forwards keys.
## Records and rewards come in S.2/S.3 (through GameState). Uses Game/Settings/Audio by name, so tests use it untyped.

const TURN_TIME := 0.055      ## quarter-turn animation here: snappy enough for 8+ TPS
const LIST_LENGTH := 50       ## times shown in the list

@onready var _view: PuzzleView3D = %View
@onready var _scramble_label: Label = %ScrambleLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _status_label: Label = %StatusLabel
@onready var _hand_label: Label = %HandLabel
@onready var _session_stats: Label = %SessionStats
@onready var _times_list: Label = %TimesList
@onready var _keys_help: Label = %KeysHelp
@onready var _puzzle_picker: HBoxContainer = %PuzzlePicker
@onready var _inspection_toggle: Button = %InspectionToggle
@onready var _keys_toggle: Button = %KeysToggle
@onready var _close_button: Button = %CloseButton

var session := SolveSession.new()
var frozen_now := -1.0     ## screenshots: show the clock at this time instead of the real one
var _picker_buttons: Dictionary = {}  ## puzzle id -> Button
var _puzzle := "3x3"
var _shown_results := -1


func _ready() -> void:
	_view.turn_time = TURN_TIME
	_view.sway_enabled = false
	_close_button.pressed.connect(close)
	_keys_toggle.toggled.connect(func(on: bool) -> void: _keys_help.visible = on)
	_inspection_toggle.toggled.connect(_on_inspection_toggled)
	set_process(false)


## Opens the station on a puzzle (the focused one if it's a cube the player has, else their biggest cube).
func open(puzzle_id: String = "") -> void:
	visible = true
	set_process(true)
	_build_picker()
	if not _picker_buttons.has(puzzle_id):
		puzzle_id = _picker_buttons.keys().back()
	_inspection_toggle.set_pressed_no_signal(bool(Settings.get_value("inspection")))
	_view.set_reduce_motion(bool(Settings.get_value("reduce_motion")))
	_view.set_graphics(String(Settings.get_value("quality")))
	select_puzzle(puzzle_id)


func close() -> void:
	visible = false
	set_process(false)


## Switches puzzle and scrambles a new attempt.
func select_puzzle(puzzle_id: String) -> void:
	_puzzle = puzzle_id
	if session.puzzle_id != puzzle_id:
		session.results.clear()
		_shown_results = -1
	for id: String in _picker_buttons:
		(_picker_buttons[id] as Button).set_pressed_no_signal(id == puzzle_id)
	if _view.puzzle_id != puzzle_id:
		_view.set_puzzle(puzzle_id)
	new_attempt()


## A fresh scramble on the current puzzle.
func new_attempt(rng: RandomNumberGenerator = null) -> void:
	session.inspection = bool(Settings.get_value("inspection"))
	session.start(_puzzle, _now(), rng)
	_view.show_state(session.scramble)
	_scramble_label.text = session.scramble_text()
	_keys_help.text = keys_help_text()
	_refresh()


## Every key the station knows, as "R I · R' K · ..." for this puzzle (generated from Content.SOLVE_KEYS).
func keys_help_text() -> String:
	var by_move: Dictionary = {}  # notation -> key names
	for key: int in Content.SOLVE_KEYS:
		var move := session.move_for_key(key)
		if move.is_empty():
			continue
		var name := session.model.notation(move)
		if not by_move.has(name):
			by_move[name] = []
		(by_move[name] as Array).append(_key_name(key))
	var parts := PackedStringArray()
	for name: String in by_move:
		parts.append("%s %s" % [name, "/".join(by_move[name])])
	var text := "   ".join(parts)
	if session.model != null and session.model.size > 3:
		text += "\nHands: 3/4 move the left hand, 8/7 the right one, Space resets."
	return text


func _key_name(key: int) -> String:
	match key:
		KEY_SEMICOLON:
			return ";"
		KEY_COMMA:
			return ","
		KEY_PERIOD:
			return "."
		KEY_SLASH:
			return "/"
	return OS.get_keycode_string(key)


# --- Input -----------------------------------------------------------------------

## Keys go to the station while it's open (and never reach the main screen's Space/Enter tap).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null:
		return
	get_viewport().set_input_as_handled()
	if not key.pressed or key.echo or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	handle_key(code)


## One key press (tests call this directly).
func handle_key(code: int) -> void:
	match code:
		KEY_ESCAPE:
			close()
			return
		KEY_ENTER, KEY_KP_ENTER:
			new_attempt()
			return
	var was_done := session.state == "done"
	var move := session.press_key(code, _now())
	if not move.is_empty():
		_view.turn(move)
		if session.state == "done" and not was_done:
			_view.flash()
			Audio.play_solve()
	_refresh()


func _on_inspection_toggled(on: bool) -> void:
	Settings.set_value("inspection", on)
	if session.state in ["inspecting", "ready"]:
		new_attempt()


# --- Display ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	session.update(_now())
	_refresh_clock()


func _refresh() -> void:
	_refresh_clock()
	var hands := session.model != null and session.model.size > 3
	_hand_label.text = "Hands: left %d · right %d" % [session.left_hand, session.right_hand] if hands else " "
	if _shown_results != session.results.size():
		_shown_results = session.results.size()
		_refresh_times()


func _refresh_clock() -> void:
	var now := _now()
	match session.state:
		"inspecting":
			var left := session.inspection_left(now)
			_timer_label.text = str(ceili(left)) if left > 0.0 else ("DNF" if session.penalty == "DNF" else "+2")
			_timer_label.theme_type_variation = &"TimerWaiting"
			_status_label.text = "Inspection: look around (rotations are free). Your first turn starts the timer."
		"ready":
			_timer_label.text = "0.00"
			_timer_label.theme_type_variation = &"TimerWaiting"
			_status_label.text = "Your first turn starts the timer."
		"solving":
			_timer_label.text = Num.solve_time(session.elapsed(now))
			_timer_label.theme_type_variation = &"TimerLabel"
			_status_label.text = "%d moves" % session.moves + ("  ·  +2 (inspection)" if session.penalty == "+2" else "")
		"done":
			var result: Dictionary = session.results.back()
			_timer_label.text = result_text(result)
			_timer_label.theme_type_variation = &"TimerDone"
			_status_label.text = "Solved!  %d moves  ·  %.2f TPS%s  ·  Enter: next scramble" % [
				int(result["moves"]), session.tps(now), "  ·  new session best" if _is_session_best(result) else ""]
		_:
			_timer_label.text = "0.00"
			_status_label.text = " "


func _refresh_times() -> void:
	var avg5 := session.average(5)
	var avg12 := session.average(12)
	_session_stats.text = "Best %s  ·  ao5 %s  ·  ao12 %s" % [
		"—" if session.results.is_empty() else Num.solve_time(session.best()),
		"—" if avg5 < 0.0 else Num.solve_time(avg5),
		"—" if avg12 < 0.0 else Num.solve_time(avg12),
	]
	if session.results.is_empty():
		_times_list.text = "No solves yet. Scramble's ready: inspect, then turn."
		return
	var lines := PackedStringArray()
	var count := session.results.size()
	for i in range(count - 1, maxi(-1, count - 1 - LIST_LENGTH), -1):
		var result: Dictionary = session.results[i]
		lines.append("%d.  %s   (%d moves)" % [i + 1, result_text(result), int(result["moves"])])
	_times_list.text = "\n".join(lines)


## "12.34", "14.34+" (a +2) or "DNF(12.34)", as csTimer writes them.
static func result_text(result: Dictionary) -> String:
	match String(result.get("penalty", "")):
		"DNF":
			return "DNF(%s)" % Num.solve_time(float(result["time"]))
		"+2":
			return Num.solve_time(SolveSession.final_time(result)) + "+"
	return Num.solve_time(float(result["time"]))


func _is_session_best(result: Dictionary) -> bool:
	return session.results.size() > 1 and not is_inf(SolveSession.final_time(result)) \
			and is_equal_approx(SolveSession.final_time(result), session.best())


func _build_picker() -> void:
	for child in _puzzle_picker.get_children():
		_puzzle_picker.remove_child(child)
		child.queue_free()
	_picker_buttons.clear()
	for id: String in Game.get_unlocked_puzzle_ids():
		var shape := PuzzleShapes.from_id(id)
		if shape == null or shape.size == 0:
			continue  # cubes only for now (the Megaminx needs its own keys)
		var button := Button.new()
		button.text = String(Content.get_puzzle(id)["name"])
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.theme_type_variation = &"ToggleChip"
		button.pressed.connect(select_puzzle.bind(id))
		_puzzle_picker.add_child(button)
		_picker_buttons[id] = button


func _now() -> float:
	return frozen_now if frozen_now >= 0.0 else Time.get_ticks_usec() / 1_000_000.0
