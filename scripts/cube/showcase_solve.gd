class_name ShowcaseSolve
extends RefCounted
## The main cube's showcase solve (task R.2): a real WCA scramble, a short inspection, then a StagedSolver solve played a
## move at a time, then the next scramble. Pure data (no nodes), so tests drive it with fake time; main.gd feeds the
## moves it returns to PuzzleView3D's manual mode (show_state / turn). Visual only: it never changes a game number.
##
##   var show := ShowcaseSolve.new("3x3", "cfop")
##   view.show_state(show.scramble)                   # also after every `started`
##   for move in show.advance(delta, tps): view.turn(move)
##   for move in show.tap(): view.turn(move)          # a tap plays the next move straight away
##
## Phases: "inspection" (the scramble is shown; the inspection turns, like z2 y, play during it), "solving", "solved"
## (held for a moment, then a new scramble). Timing is Content.SHOWCASE.

signal started                    ## a new scramble is ready: show `scramble` (the view resets to it)
signal stage_changed(index: int)  ## `stage_index` moved on (the stage chips follow it)
signal finished                   ## the solve is done (flash!)

var puzzle_id := ""
var method := "beginner"          ## used from the next scramble on (a method learned mid-solve waits for it)
var phase := "inspection"
var scramble: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var stage_index := 0              ## the stage being played (or about to be)
var move_index := 0               ## next move within that stage
var solves_shown := 0
var model: TwistyModel            ## the puzzle as it looks once every returned move is played

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _move_clock := 0.0


func _init(puzzle: String, method_id: String = "beginner", seed: int = -1) -> void:
	puzzle_id = puzzle
	method = method_id
	if seed >= 0:
		_rng.seed = seed
	else:
		_rng.seed = randi()  # follows the global seed, so screenshots are repeatable
	start_new()


## True if this puzzle can be shown as a real staged solve (else the main cube keeps its scramble + rewind).
static func supports(puzzle: String) -> bool:
	return StagedSolver.supports(puzzle)


## Turns per second for a method and the focused puzzle's real moves per second (see Content.SHOWCASE).
static func tps_for(method_id: String, moves_per_second: float) -> float:
	var data: Dictionary = Content.SHOWCASE
	var base := float((data["tps_by_method"] as Dictionary).get(method_id, 3.0))
	var style := base + float(data["tps_per_decade"]) * log(maxf(1.0, moves_per_second)) / log(10.0)
	return minf(minf(style, float(data["max_tps"])), maxf(0.0, moves_per_second))


## A fresh scramble and its solve. Emits `started`.
func start_new() -> void:
	model = PuzzleShapes.from_id(puzzle_id)
	var length := int(Content.get_puzzle(puzzle_id).get("scramble_length", 25))
	scramble = model.scramble(length, _rng)
	stages = StagedSolver.solve(model, method)
	phase = "inspection"
	stage_index = 0
	move_index = 0
	_timer = float(Content.SHOWCASE["inspection"])
	_move_clock = 0.0
	started.emit()


## Moves to play for `delta` seconds at `tps` turns per second (0 = only taps turn it).
func advance(delta: float, tps: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match phase:
		"inspection":
			_timer -= delta
			var turns := _inspection_moves()
			if turns.size() > move_index and _timer < float(Content.SHOWCASE["inspection"]) * 0.6:
				out.append_array(_take_inspection())  # pick the cube up and turn it, part-way through inspection
			if _timer <= 0.0:
				out.append_array(_take_inspection())
				_begin_solving()
		"solving":
			_move_clock += delta * maxf(0.0, tps)
			while _move_clock >= 1.0 and phase == "solving":
				_move_clock -= 1.0
				out.append_array(_next_move())
		"solved":
			_timer -= delta
			if _timer <= 0.0:
				start_new()
	return out


## A tap plays the next move now (in inspection it ends inspection first). Returns the moves to show.
func tap() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if phase == "inspection":
		out.append_array(_take_inspection())
		_begin_solving()
	if phase == "solving":
		out.append_array(_next_move())
	return out


## The stage being played: {id, name, moves}, or {} before the first / after the last.
func current_stage() -> Dictionary:
	return stages[stage_index] if stage_index < stages.size() else {}


## The stages a viewer follows (no inspection): the chips under the cube.
func chip_stages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stage in stages:
		if stage["id"] != "inspection":
			out.append(stage)
	return out


## Moves in a stage written the way cubers write algorithms: on the 3×3, two-layer moves as lower case (r U R' U' r').
static func notation(m: TwistyModel, move: Dictionary) -> String:
	var text := m.notation(move)
	if m.size == 3 and text.length() >= 2 and text[1] == "w":
		text = text[0].to_lower() + text.substr(2)
	return text


func _inspection_moves() -> Array:
	if not stages.is_empty() and stages[0]["id"] == "inspection":
		return stages[0]["moves"]
	return []


func _take_inspection() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var turns := _inspection_moves()
	while move_index < turns.size():
		out.append(turns[move_index])
		move_index += 1
	for m in out:
		model.apply(m)
	return out


func _begin_solving() -> void:
	phase = "solving"
	_move_clock = 0.0
	if not stages.is_empty() and stages[0]["id"] == "inspection":
		stage_index = 1
	move_index = 0
	_skip_empty()
	stage_changed.emit(stage_index)


## The next move of the solve (skipping stages with no moves); finishes the solve after the last.
func _next_move() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_skip_empty()
	if stage_index >= stages.size():
		_finish()
		return out
	var move: Dictionary = stages[stage_index]["moves"][move_index]
	model.apply(move)
	out.append(move)
	move_index += 1
	if move_index >= (stages[stage_index]["moves"] as Array).size():
		stage_index += 1
		move_index = 0
		_skip_empty()
		stage_changed.emit(stage_index)
		if stage_index >= stages.size():
			_finish()
	return out


func _skip_empty() -> void:
	while stage_index < stages.size() and (stages[stage_index]["moves"] as Array).is_empty():
		stage_index += 1
		move_index = 0


func _finish() -> void:
	if phase == "solved":
		return
	phase = "solved"
	solves_shown += 1
	_timer = float(Content.SHOWCASE["solved_hold"])
	finished.emit()
