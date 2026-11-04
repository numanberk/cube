class_name SolveStation
extends Control
## The Solve Station (task S.1): solve the puzzles yourself, csTimer-style. A full-screen overlay with its own 3D puzzle,
## turned with the keyboard (by physical key: csTimer's layout, or the simple "key = face" layout) or by dragging across
## the cube (a drag on the background turns the view), a WCA scramble, inspection, a big timer and this puzzle's records
## (S.2: PBs, current averages, the times with +2/DNF/delete). Key hints sit on and around the cube's faces.
## The solving rules live in SolveSession, the records in GameState; this script only shows them and forwards input.
## Uses Game/Settings/Audio by name, so tests use it untyped.

const TURN_TIME := 0.055      ## quarter-turn animation here: snappy enough for 8+ TPS
const LIST_LENGTH := 50       ## times shown in the list (the newest)

@onready var _view: PuzzleView3D = %View
@onready var _scramble_label: Label = %ScrambleLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _status_label: Label = %StatusLabel
@onready var _hand_label: Label = %HandLabel
@onready var _records_title: Label = %RecordsTitle
@onready var _bests_label: Label = %BestsLabel
@onready var _current_label: Label = %CurrentLabel
@onready var _targets_label: Label = %TargetsLabel
@onready var _times_rows: VBoxContainer = %TimesRows
@onready var _keys_help: Label = %KeysHelp
@onready var _puzzle_picker: HBoxContainer = %PuzzlePicker
@onready var _inspection_toggle: Button = %InspectionToggle
@onready var _keys_toggle: Button = %KeysToggle
@onready var _close_button: Button = %CloseButton
@onready var _simple_toggle: Button = %SimpleKeysToggle
@onready var _drills_toggle: Button = %DrillsToggle
@onready var _hints_toggle: Button = %HintsToggle
@onready var _hints_layer: Control = %KeyHints
@onready var _footer: Label = %FooterHint

var session := SolveSession.new()
var frozen_now := -1.0     ## screenshots: show the clock at this time instead of the real one
var _picker_buttons: Dictionary = {}  ## puzzle id -> Button
var _puzzle := "3x3"
var _records_dirty := true
var last_info: Dictionary = {}       ## what Game.record_hand_solve() said about the last solve (PBs)
var _hint_labels: Dictionary = {}    ## face index -> Label (key hints on the cube)
var golden_mode := false             ## a Golden Scramble case (S.6): short scramble, 10 s clock, not a record
var golden_result := ""              ## what the case gave ("" while it runs)
const GOLDEN_CLOSE_DELAY := 2.2      ## seconds the result shows before the station closes by itself
var _golden_close_left := 0.0
var drill_mode := false              ## algorithm drills (S.4): the picker shows drill sets, each attempt is one case
var drill_set := "2look_pll"
var drill_case: Dictionary = {}      ## the Content.ALGORITHMS entry being drilled
var drill_result: Dictionary = {}    ## what Game.record_drill() said about the last one
var drill_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_view.turn_time = TURN_TIME
	_view.sway_enabled = false
	_close_button.pressed.connect(close)
	_keys_toggle.toggled.connect(func(on: bool) -> void: _keys_help.visible = on)
	_inspection_toggle.toggled.connect(_on_inspection_toggled)
	_simple_toggle.toggled.connect(func(on: bool) -> void: set_layout("simple" if on else "cstimer"))
	_hints_toggle.toggled.connect(func(on: bool) -> void:
		Settings.set_value("key_hints", on)
		_build_hints())
	_view.drag_turns = true
	_view.drag_turned.connect(play_move)
	Game.golden_finished.connect(_on_golden_finished)
	_drills_toggle.toggled.connect(set_drill_mode)
	drill_rng.randomize()
	Game.solve_records_changed.connect(func(_id: String) -> void: _records_dirty = true)
	set_process(false)


## Opens the station on a puzzle (the focused one if it's a cube the player has, else their biggest cube).
func open(puzzle_id: String = "") -> void:
	visible = true
	set_process(true)
	_build_picker()
	if not _picker_buttons.has(puzzle_id):
		puzzle_id = _picker_buttons.keys().back()
	_inspection_toggle.set_pressed_no_signal(bool(Settings.get_value("inspection")))
	session.layout = String(Settings.get_value("solve_keys"))
	_simple_toggle.set_pressed_no_signal(session.layout == "simple")
	_hints_toggle.set_pressed_no_signal(bool(Settings.get_value("key_hints")))
	_view.set_reduce_motion(bool(Settings.get_value("reduce_motion")))
	_view.set_graphics(String(Settings.get_value("quality")))
	select_puzzle(puzzle_id)


func close() -> void:
	if drill_mode:
		set_drill_mode(false, false)
	if golden_mode and Game.golden_attempt_left > 0.0:
		Game.finish_golden(false)  # walking away from a golden case is a miss
	golden_mode = false
	_puzzle_picker.visible = true
	visible = false
	set_process(false)


## Opens a Golden Scramble case (S.6): the puzzle `moves` turns from solved, no inspection, solved against the 10 s
## clock that GameState runs (claim_golden() must have started it). Not a record.
func open_golden(puzzle_id: String, moves: int) -> void:
	open(puzzle_id)
	set_drill_mode(false, false)
	golden_mode = true
	golden_result = ""
	_golden_close_left = 0.0
	_puzzle_picker.visible = false
	session.inspection = false
	session.start(_puzzle, _now(), null, moves)
	last_info = {}
	_view.show_state(session.scramble)
	_scramble_label.text = "Golden Scramble:  %s" % session.scramble_text()
	_build_hints()
	_refresh()


func _on_golden_finished(success: bool, buff: Dictionary) -> void:
	if not golden_mode or not visible:
		return
	golden_result = String(buff.get("text", "")) if success else "Too slow: the golden case got away. Next time!"
	_golden_close_left = GOLDEN_CLOSE_DELAY
	if success:
		_view.flash()
	_refresh()


## Switches puzzle and scrambles a new attempt.
func select_puzzle(puzzle_id: String) -> void:
	_puzzle = puzzle_id
	if session.puzzle_id != puzzle_id:
		session.results.clear()
	_records_dirty = true
	for id: String in _picker_buttons:
		(_picker_buttons[id] as Button).set_pressed_no_signal(id == puzzle_id)
	if _view.puzzle_id != puzzle_id:
		_view.set_puzzle(puzzle_id)
	new_attempt()


## A fresh scramble on the current puzzle.
func new_attempt(rng: RandomNumberGenerator = null) -> void:
	session.inspection = bool(Settings.get_value("inspection"))
	session.start(_puzzle, _now(), rng)
	last_info = {}
	_view.show_state(session.scramble)
	_scramble_label.text = session.scramble_text()
	_keys_help.text = keys_help_text()
	_build_hints()
	_refresh()


## "cstimer" or "simple" (saved as the solve_keys setting). Takes effect at once.
func set_layout(layout: String) -> void:
	Settings.set_value("solve_keys", layout)
	session.layout = layout
	session.next_width = 1
	_simple_toggle.set_pressed_no_signal(layout == "simple")
	_keys_help.text = keys_help_text()
	_build_hints()
	_refresh()


## Every key the station knows, as "R I · R' K · ..." for this puzzle (generated from Content.SOLVE_KEYS).
func keys_help_text() -> String:
	if session.layout == "simple":
		var simple := PackedStringArray()
		for key: int in Content.SOLVE_KEYS_SIMPLE:
			if not session.move_for_simple_key(key).is_empty():
				var letter: String = Content.SOLVE_KEYS_SIMPLE[key]
				simple.append("%s %s / Shift+%s" % [letter, _key_name(key), _key_name(key)])
		var help := "   ".join(simple)
		if session.model != null and session.model.size > 2:
			help += "\nWide turns: press 2 (or 3...) first, then the face: 2 R = Rw."
		return help
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


# --- Algorithm drills (task S.4) -------------------------------------------------------

## Drills on (the picker shows the sets; a 3×3 case each time) or off (back to normal solves).
func set_drill_mode(on: bool, restart: bool = true) -> void:
	drill_mode = on
	_drills_toggle.set_pressed_no_signal(on)
	_inspection_toggle.visible = not on
	_records_dirty = true
	if on:
		if _puzzle != "3x3" or _view.puzzle_id != "3x3":
			_puzzle = "3x3"
			_view.set_puzzle("3x3")
		_build_drill_picker()
		new_drill()
	else:
		_build_picker()
		if restart and visible:
			select_puzzle(_puzzle if _picker_buttons.has(_puzzle) else _picker_buttons.keys().back())


func select_drill_set(set_id: String) -> void:
	drill_set = set_id
	_build_drill_picker()
	_records_dirty = true
	new_drill()


## The next case: one not learned yet (fewest clean solves first, at random among them), else any case in the set.
func new_drill(case_id: String = "") -> void:
	var cases := Content.get_drill_cases(drill_set)
	if cases.is_empty():
		return
	drill_case = {}
	if case_id != "":
		for alg in cases:
			if alg["id"] == case_id:
				drill_case = alg
	if drill_case.is_empty():
		var candidates: Array[Dictionary] = cases.filter(func(alg: Dictionary) -> bool: return not Game.is_case_learned(alg["id"]))
		if candidates.is_empty():
			candidates = cases  # all learned: keep practising any of them
		var fewest := 1 << 30
		var pool: Array[Dictionary] = []
		for alg in candidates:
			var clean := int(Game.get_drill_record(alg["id"])["clean"])
			if clean < fewest:
				fewest = clean
				pool = [alg]
			elif clean == fewest:
				pool.append(alg)
		drill_case = pool[drill_rng.randi_range(0, pool.size() - 1)]
	drill_result = {}
	session.start_drill(drill_case["alg"], _now(), drill_rng)
	_view.show_state(session.scramble)
	var set_def := Content.get_drill_set(drill_set)
	_scramble_label.text = "%s drill  ·  clean = under %ds  ·  %d clean solves learn a case" % [set_def["name"],
			int(set_def["target"]), int(Content.DRILLS["clean_needed"])]
	_build_hints()
	_refresh()


## After a drill: "T perm · 6.42 · best 5.90 · clean 3/5 · R U R' U' ... · Enter: next case".
func drill_status_text() -> String:
	if drill_case.is_empty():
		return ""
	var record: Dictionary = Game.get_drill_record(drill_case["id"])
	var clean_text := "learned!" if drill_result.get("learned_now", false) else (
			"learned" if Game.is_case_learned(drill_case["id"]) else "clean %d/%d" % [int(record["clean"]), int(Content.DRILLS["clean_needed"])])
	var parts := PackedStringArray([String(drill_case["name"]), "best %s%s" % [Num.solve_time(float(record["best"])),
			" (PB!)" if drill_result.get("pb", false) else ""], clean_text, String(drill_case["alg"])])
	if drill_result.get("set_learned_now", false):
		parts.append("%s learned!" % Content.get_drill_set(drill_set)["name"])
	return "  ·  ".join(parts) + "  ·  Enter: next case"


func _build_drill_picker() -> void:
	for child in _puzzle_picker.get_children():
		_puzzle_picker.remove_child(child)
		child.queue_free()
	_picker_buttons.clear()
	for drill: Dictionary in Content.DRILLS["sets"]:
		var progress := Game.get_drill_set_progress(drill["id"])
		var button := _row_button("%s %d/%d" % [drill["name"], progress["learned"], progress["total"]], &"ToggleChip")
		button.toggle_mode = true
		button.set_pressed_no_signal(drill["id"] == drill_set)
		button.pressed.connect(select_drill_set.bind(String(drill["id"])))
		_puzzle_picker.add_child(button)


## The side panel in drill mode: every case in the set with its best time and clean solves, learned ones ticked.
func _refresh_drill_list() -> void:
	var set_def := Content.get_drill_set(drill_set)
	var progress := Game.get_drill_set_progress(drill_set)
	_records_title.text = "%s  ·  %d/%d learned" % [set_def["name"], progress["learned"], progress["total"]]
	_bests_label.text = "A solve under %ds is clean; %d clean solves learn a case." % [int(set_def["target"]), int(Content.DRILLS["clean_needed"])]
	_current_label.text = "Learn every case of Full OLL or Full PLL and your team uses it in its solves."
	_targets_label.text = " "
	for child in _times_rows.get_children():
		_times_rows.remove_child(child)
		child.queue_free()
	for alg in Content.get_drill_cases(drill_set):
		var record: Dictionary = Game.get_drill_record(alg["id"])
		var label := Label.new()
		label.theme_type_variation = &"CardLine"
		label.text = "%s%s   best %s   clean %d/%d" % ["✓ " if Game.is_case_learned(alg["id"]) else "", alg["name"],
				"—" if is_inf(float(record["best"])) else Num.solve_time(float(record["best"])),
				mini(int(record["clean"]), int(Content.DRILLS["clean_needed"])), int(Content.DRILLS["clean_needed"])]
		label.tooltip_text = String(alg["alg"])
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_times_rows.add_child(label)


# --- Key hints --------------------------------------------------------------------

## The hint for a face: "R  I / K" (csTimer: the keys for R and R') or "R / ⇧R" (simple), "" if no key turns it.
func face_hint_text(face_name: String) -> String:
	if session.model == null:
		return ""
	var face := session.model.face_names.find(face_name)
	var keys := ["", ""]  # clockwise, counter-clockwise
	if session.layout == "simple":
		for key: int in Content.SOLVE_KEYS_SIMPLE:
			if Content.SOLVE_KEYS_SIMPLE[key] == face_name:
				return "%s / ⇧%s" % [_key_name(key), _key_name(key)]  # the key is the face, so no face letter
		return ""
	for key: int in Content.SOLVE_KEYS:
		var move := session.move_for_key(key)
		if move.is_empty() or int(move["face"]) != face or int(move.get("depth", 0)) != 0 or int(move.get("width", 1)) != 1:
			continue
		var slot := 0 if int(move["turns"]) == 1 else (1 if int(move["turns"]) == -1 else -1)
		if slot >= 0 and keys[slot] == "":
			keys[slot] = _key_name(key)
	if keys[0] == "" and keys[1] == "":
		return ""
	return "%s  %s / %s" % [face_name, keys[0], keys[1]]


## Rotations and slices, under the cube: "x T/Y  y ;/A  z P/Q  M 5/6 ..." (simple: "x X  y Y  z Z · ⇧ = prime ...").
func extra_keys_text() -> String:
	if session.model == null:
		return ""
	if session.layout == "simple":
		var text := "x X  ·  y Y  ·  z Z"
		if session.model.size == 3:
			text += "  ·  M E S"
		text += "  ·  ⇧ = prime"
		if session.model.size > 2:
			text += "  ·  2 then R = Rw"
		return text
	var parts := PackedStringArray()
	for name: String in ["x", "y", "z", "M", "E", "S"]:
		var keys := PackedStringArray()
		for key: int in Content.SOLVE_KEYS:
			var move := session.move_for_key(key)
			if move.is_empty():
				continue
			var written := session.model.notation(move)
			if written == name or written == name + "'":
				keys.append(_key_name(key))
		if not keys.is_empty():
			parts.append("%s %s" % [name, "/".join(keys)])
	return "  ·  ".join(parts)


func _build_hints() -> void:
	for child in _hints_layer.get_children():
		_hints_layer.remove_child(child)
		child.queue_free()
	_hint_labels.clear()
	if not bool(Settings.get_value("key_hints")) or session.model == null:
		return
	for face_name: String in ["U", "D", "F", "B", "R", "L"]:
		var text := face_hint_text(face_name)
		if text == "":
			continue
		var label := Label.new()
		label.theme_type_variation = &"KeyHint"
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hints_layer.add_child(label)
		_hint_labels[session.model.face_names.find(face_name)] = label
	_place_hints()


## Keeps each hint on (or next to) its face as the cube sways or is turned with a drag. Hidden faces' hints are dimmer.
func _place_hints() -> void:
	var origin := _view.get_global_rect().position - _hints_layer.get_global_rect().position
	for face: int in _hint_labels:
		var label: Label = _hint_labels[face]
		var info := _view.face_label_position(face)
		if info.is_empty():
			continue
		label.size = label.get_combined_minimum_size()
		label.position = origin + (info["position"] as Vector2) - label.size / 2.0
		label.modulate.a = 1.0 if info["facing"] else 0.5


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
	handle_key(code, key.shift_pressed)


## One key press (tests call this directly). `shift`: Shift held (the simple layout's prime turns).
func handle_key(code: int, shift: bool = false) -> void:
	match code:
		KEY_ESCAPE:
			close()
			return
		KEY_ENTER, KEY_KP_ENTER:
			if drill_mode:
				new_drill()
				return
			if golden_mode:
				if golden_result != "":
					close()
				return
			new_attempt()
			return
	var was_done := session.state == "done"
	var move := session.press_key(code, _now(), shift)
	if not move.is_empty():
		_view.turn(move)
		_after_turn(was_done)
	_refresh()


## A turn from a drag across the cube (or anything else that isn't a key).
func play_move(move: Dictionary) -> void:
	if not visible or session.model == null:
		return
	var was_done := session.state == "done"
	session.turn(move, _now())
	_view.turn(move)
	_after_turn(was_done)
	_refresh()


func _after_turn(was_done: bool) -> void:
	if drill_mode:
		if session.state == "done" and not was_done:
			drill_result = Game.record_drill(drill_set, drill_case.get("id", ""), session.elapsed(_now()))
			_records_dirty = true
			_view.flash()
			Audio.play_solve()
		return
	if golden_mode:
		if session.state == "done" and not was_done and golden_result == "":
			Game.finish_golden(true)  # golden_finished shows the buff
			Audio.play_solve()
		return
	if session.state == "done" and not was_done:
		var result: Dictionary = session.results.back()
		last_info = Game.record_hand_solve(session.puzzle_id, float(result["time"]), String(result["penalty"]),
				int(result["moves"]))
		_view.flash()
		Audio.play_solve()


func _on_inspection_toggled(on: bool) -> void:
	Settings.set_value("inspection", on)
	if session.state in ["inspecting", "ready"]:
		new_attempt()


# --- Display ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if golden_mode and _golden_close_left > 0.0:
		_golden_close_left -= delta
		if _golden_close_left <= 0.0:
			close()
			return
	session.update(_now())
	_refresh_clock()
	_place_hints()


func _refresh() -> void:
	_refresh_clock()
	var lines := PackedStringArray()
	if Settings.get_value("key_hints"):
		lines.append(extra_keys_text())
	if session.layout == "simple":
		if session.next_width > 1:
			lines.append("Next turn: %d layers" % session.next_width)
	elif session.model != null and session.model.size > 3:
		lines.append("Hands: left %d · right %d" % [session.left_hand, session.right_hand])
	_hand_label.text = "   ·   ".join(lines) if not lines.is_empty() else " "
	_footer.text = "%s  ·  drag a row to turn it  ·  Enter: new scramble  ·  Esc: close" % (
			"Simple keys" if session.layout == "simple" else "csTimer keys")
	if _records_dirty:
		_records_dirty = false
		_refresh_records()


func _refresh_clock() -> void:
	var now := _now()
	if drill_mode:
		_timer_label.text = Num.solve_time(session.elapsed(now))
		_timer_label.theme_type_variation = &"TimerDone" if session.state == "done" else &"TimerLabel"
		_status_label.text = drill_status_text() if session.state == "done" else "Recognise the case, then solve it. The clock is running."
		return
	if golden_mode:
		if golden_result != "":
			_timer_label.text = Num.solve_time(session.elapsed(now)) if session.state == "done" else "0.0"
			_timer_label.theme_type_variation = &"TimerDone" if session.state == "done" else &"TimerWaiting"
			_status_label.text = golden_result
		else:
			_timer_label.text = "%.1f" % maxf(0.0, Game.golden_attempt_left)
			_timer_label.theme_type_variation = &"TimerGolden"
			_status_label.text = "Golden Scramble: %d moves from solved. Solve it before the clock runs out!" % session.scramble.size()
		return
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
			_status_label.text = "%s  %d moves  ·  %.2f TPS%s  ·  Enter: next scramble" % [
				pb_text(last_info), int(result["moves"]), session.tps(now), reward_text(last_info)]
		_:
			_timer_label.text = "0.00"
			_status_label.text = " "


func _refresh_records() -> void:
	if drill_mode:
		_refresh_drill_list()
		return
	var id := _puzzle
	_records_title.text = "%s records  ·  %d solves" % [Content.get_puzzle(id)["name"], Game.get_hand_solve_count(id)]
	var bests: Dictionary = Game.get_solve_bests(id)
	var best_parts := PackedStringArray(["single %s" % _time_or_dash(float(bests["single"]))])
	var now_parts := PackedStringArray()
	for size: int in Game.AVERAGE_SIZES:
		best_parts.append("ao%d %s" % [size, _time_or_dash(float(bests[size]))])
		var current: float = Game.get_current_average(id, size)
		now_parts.append("ao%d %s" % [size, "—" if current < 0.0 else Num.solve_time(current)])
	_bests_label.text = "PB   " + "  ·  ".join(best_parts)
	_targets_label.text = targets_text(id)
	_current_label.text = "Now  " + "  ·  ".join(now_parts)
	for child in _times_rows.get_children():
		_times_rows.remove_child(child)
		child.queue_free()
	var history: Array = Game.get_solve_history(id)
	if history.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"DimLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = "No solves yet. Inspect, then turn: your times are saved here."
		_times_rows.add_child(empty)
		return
	for i in range(history.size() - 1, maxi(-1, history.size() - 1 - LIST_LENGTH), -1):
		_times_rows.add_child(_time_row(id, i, history[i]))


## One line of the times list: "34.  12.34+   52 moves" and +2 / DNF / × buttons.
func _time_row(id: String, index: int, entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.theme_type_variation = &"CardLine"
	label.text = "%d.  %s   %d moves" % [index + 1, result_text({"time": entry["t"], "penalty": entry["p"]}), int(entry["m"])]
	row.add_child(label)
	for penalty: String in ["+2", "DNF"]:
		var toggle := _row_button(penalty, &"ToggleChip")
		toggle.toggle_mode = true
		toggle.set_pressed_no_signal(entry["p"] == penalty)
		toggle.pressed.connect(func() -> void:
			Game.set_hand_solve_penalty(id, index, "" if entry["p"] == penalty else penalty))
		row.add_child(toggle)
	var delete := _row_button("×", &"SubtleButton")
	delete.tooltip_text = "Delete this time"
	delete.pressed.connect(func() -> void: Game.delete_hand_solve(id, index))
	row.add_child(delete)
	return row


func _row_button(text: String, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = variation
	return button


static func _time_or_dash(seconds: float) -> String:
	return "—" if is_inf(seconds) else Num.solve_time(seconds)


## What a solve earned (S.3): "  ·  Gold: Flow ×2.0 for 2:15" (+ "  ·  new tier: +15 % moves on the 3×3 for good").
static func reward_text(info: Dictionary) -> String:
	if not info.has("flow_mult"):
		return ""
	var tier := int(info.get("tier", -1))
	var text := "  ·  %s: Flow ×%s for %s" % [GameState.hand_tier_name(tier) if tier >= 0 else "Under every target",
			Num.format(float(info["flow_mult"])), Num.solve_time(float(info["flow_seconds"])).get_slice(".", 0)]
	if int(info.get("new_tier", -1)) >= 0:
		var bonus := float(Content.SOLVE_REWARDS["tier_moves_bonus"]) * (int(info["new_tier"]) + 1) * 100.0
		text += "  ·  new tier: +%d %% moves here for good" % roundi(bonus)
	return text


## The time targets for a puzzle, the ones its PB has reached ticked: "Targets  ✓ Bronze 5:00 · ✓ Silver 2:30 · Gold 1:30 ...".
func targets_text(puzzle_id: String) -> String:
	var targets: Array = (Content.SOLVE_REWARDS["targets"] as Dictionary).get(puzzle_id, [])
	var reached: int = Game.get_best_hand_tier(puzzle_id)
	var parts := PackedStringArray()
	for i in targets.size():
		parts.append("%s%s %s" % ["✓ " if i <= reached else "", GameState.hand_tier_name(i),
				Num.solve_time(float(targets[i])).trim_suffix(".00")])
	return "Targets   " + "  ·  ".join(parts)


## "Solved!" or the PBs the last solve set ("New PB single and ao5!").
static func pb_text(info: Dictionary) -> String:
	var parts := PackedStringArray()
	if info.get("pb_single", false):
		parts.append("single")
	for size: int in info.get("pb_averages", []):
		parts.append("ao%d" % size)
	if parts.is_empty():
		return "Solved!"
	return "New PB %s!" % " and ".join(parts) if parts.size() <= 2 else "New PB %s!" % ", ".join(parts)


## "12.34", "14.34+" (a +2) or "DNF(12.34)", as csTimer writes them.
static func result_text(result: Dictionary) -> String:
	match String(result.get("penalty", "")):
		"DNF":
			return "DNF(%s)" % Num.solve_time(float(result["time"]))
		"+2":
			return Num.solve_time(SolveSession.final_time(result)) + "+"
	return Num.solve_time(float(result["time"]))


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
