class_name ShowcaseSolve
extends RefCounted
## The main cube's showcase solve (task R.2): a real WCA scramble, a short inspection, then a StagedSolver solve played a
## move at a time, then the next scramble. 4×4, 5×5 and 7×7 are solved by BigCubeSolver (R.6: centres, edges,
## parity, then the method's own stages on the reduced cube); with `plan_budget_usec` set, their solve is planned a few
## ms per `advance` during inspection (a 7×7's takes ~0.1 s), and `planned` tells when `stages` are there. Pure data (no nodes), so tests drive it with fake time; main.gd feeds the
## moves it returns to PuzzleView3D's manual mode (show_state / turn). Visual only: it never changes a game number.
##
##   var show := ShowcaseSolve.new("3x3", "cfop")
##   view.show_state(show.scramble)                   # also after every `started`
##   for move in show.advance(delta, tps): view.turn(move)
##   for move in show.tap(): view.turn(move)          # a tap plays the next move straight away
##
## Phases: "inspection" (the scramble is shown; the inspection turns, like z2 y, play during it), "solving", "solved"
## (held for a moment, then a new scramble). Timing is Content.SHOWCASE.
##
## The player's own key turns (task S.7) take the cube over: `player_turn(move)` applies a move and enters the "player"
## phase, where the showcase waits. After Content.TAPS["resume_after"] seconds without a turn (or at the next click) the
## team takes it back: it solves the cube from wherever the player left it (a short inspection, then a new staged
## solve), or, if the player solved it, it counts as solved.

signal started                    ## a new scramble is ready: show `scramble` (the view resets to it)
signal stage_changed(index: int)  ## `stage_index` moved on (the stage chips follow it)
signal finished                   ## the solve is done (flash!)
signal resumed                    ## the team took the cube back from the player: new `stages`, same cube (no reset)
signal planned                    ## a solve planned over several `advance` calls is ready: `stages` changed

var puzzle_id := ""
var method := "beginner"          ## used from the next scramble on (a method learned mid-solve waits for it)
var solver_options := {}          ## StagedSolver options, e.g. {"full_pll": true} once the player learned full PLL (S.4)
var plan_budget_usec := 0         ## big cubes: plan for at most about this long per `advance` (0 = all at once)
var phase := "inspection"
var scramble: Array[Dictionary] = []
var stages: Array[Dictionary] = []
var stage_index := 0              ## the stage being played (or about to be)
var move_index := 0               ## next move within that stage
var solves_shown := 0
var model: TwistyModel            ## the puzzle as it looks once every returned move is played
var player_moves: Array[Dictionary] = []  ## the player's turns since they took the cube (newest last, at most 12)
var by_player := false            ## the last solve was finished by the player's own turns
var _history: Array[Dictionary] = []  ## every move since the scramble began (God's Number undoes them, R.5)
var _taken_solved := false        ## the cube was already solved when the player took it (undoing R with R' isn't a solve)
var _planner: BigCubeSolver.Planner   ## a big cube's solve being planned (stages are [] until it's done)

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _move_clock := 0.0


func _init(puzzle: String, method_id: String = "beginner", seed: int = -1, budget_usec: int = 0) -> void:
	puzzle_id = puzzle
	method = method_id
	plan_budget_usec = budget_usec
	if seed >= 0:
		_rng.seed = seed
	else:
		_rng.seed = randi()  # follows the global seed, so screenshots are repeatable
	start_new()


## True if this puzzle can be shown as a real staged solve (else the main cube keeps its scramble + rewind).
static func supports(puzzle: String) -> bool:
	return StagedSolver.supports(puzzle) or BigCubeSolver.supports(puzzle)


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
	_history = scramble.duplicate()
	stages = _plan()
	phase = "inspection"
	stage_index = 0
	move_index = 0
	_timer = float(Content.SHOWCASE["inspection"])
	_move_clock = 0.0
	player_moves.clear()
	by_player = false
	started.emit()


## The player turned the cube with the keys (S.7): the move is played now and the showcase waits for them.
## Returns the moves to show (just this one).
func player_turn(move: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if move.is_empty():
		return out
	_planner = null  # planned for a cube that's changing: the team plans again when it takes the cube back
	if phase != "player":
		player_moves.clear()
		_taken_solved = model.is_solved()
	model.apply(move)
	_history.append(move)
	out.append(move)
	phase = "player"
	player_moves.append(move)
	if player_moves.size() > 12:
		player_moves.pop_front()
	_timer = float(Content.TAPS["resume_after"])
	return out


## The team takes the cube back from the player: solved already -> "solved", else a new staged solve from here.
func _resume() -> void:
	if model.is_solved():
		stages = []
		stage_index = 0
		move_index = 0
		by_player = not _taken_solved
		resumed.emit()
		_finish()
		return
	stages = _plan()
	phase = "inspection"
	stage_index = 0
	move_index = 0
	_timer = float(Content.SHOWCASE["inspection"])
	_move_clock = 0.0
	resumed.emit()


## The solve from where the cube is now. God's Number (the last method) isn't a way people solve, and there's no
## optimal solver here, so it undoes everything done to the cube since the scramble, merged (R.5), as one stage
## labelled "God's Number": at most the scramble's length on a fresh scramble. After the player's own turns (S.7) or a
## method learned mid-solve that history can get long; when it's longer than the scramble, the team shows its
## shortest staged solve (Roux) instead, with Roux's own stage names, so nothing long is labelled God's Number.
func _plan() -> Array[Dictionary]:
	_planner = null
	if method == "gods_number":
		var undo := StagedSolver.simplify(model, model.inverse_sequence(StagedSolver.simplify(model, _history)))
		if undo.size() <= int(Content.get_puzzle(puzzle_id).get("scramble_length", 25)):
			return [{"id": "gods_number", "name": "God's Number", "moves": undo}]
		return _staged("roux")
	return _staged(method)


func _staged(method_id: String) -> Array[Dictionary]:
	_planner = null
	if BigCubeSolver.supports(puzzle_id):
		if plan_budget_usec > 0:
			_planner = BigCubeSolver.plan(model, method_id, solver_options)
			var later: Array[Dictionary] = []
			return later
		return BigCubeSolver.solve(model, method_id, solver_options)
	return StagedSolver.solve(model, method_id, solver_options)


## True while a big cube's solve is still being planned (no `stages` yet).
func is_planning() -> bool:
	return _planner != null


## Plans the rest now, in one go (screenshots pose the solve straight away).
func finish_plan() -> void:
	_plan_step(-1)


## Plans for about `budget_usec` (-1: to the end); when done, the stages are in and `planned` is emitted.
func _plan_step(budget_usec: int) -> void:
	if _planner == null or not _planner.step(budget_usec):
		return
	stages = _planner.stages()
	_planner = null
	planned.emit()


## Moves to play for `delta` seconds at `tps` turns per second (0 = only taps turn it).
func advance(delta: float, tps: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match phase:
		"inspection":
			_timer -= delta
			_plan_step(plan_budget_usec)
			if _planner != null:  # inspection lasts until the plan is ready
				_timer = maxf(_timer, 0.0)
				return out
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
		"player":
			_timer -= delta
			if _timer <= 0.0:
				_resume()
	return out


## A tap plays the next move now (in inspection it ends inspection first). Returns the moves to show.
func tap() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if phase == "player":  # a click hands the cube back to the team straight away
		_resume()
	if phase == "inspection":
		if _planner != null:  # still planning: the tap ends inspection, the solve starts once planned (no frame stall)
			_timer = 0.0
			return out
		out.append_array(_take_inspection())
		_begin_solving()
	if phase == "solving":
		out.append_array(_next_move())
	return out


## The stage being played: {id, name, moves}, or {} before the first / after the last.
func current_stage() -> Dictionary:
	return stages[stage_index] if stage_index < stages.size() else {}


## The stages a viewer follows (no inspection): the chips under the cube. While a big cube is being planned, its first
## two (known before the plan: the rest wait for it), so the row doesn't empty.
func chip_stages() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_planning():
		for id: String in ["centres", "edges"]:
			out.append({"id": id, "name": BigCubeSolver.STAGE_NAMES[id], "moves": []})
		return out
	for stage in stages:
		if stage["id"] != "inspection":
			out.append(stage)
	return out


## Moves in a stage written the way cubers write algorithms: on the 3×3, two-layer moves as lower case (r U R' U' r').
## On a bigger cube, every inner layer together is M, E or S, as in its 3×3 stage (not "2-4Lw").
static func notation(m: TwistyModel, move: Dictionary) -> String:
	if m.size > 3 and int(move.get("depth", 0)) == 1 and int(move.get("width", 1)) == m.size - 2:
		var slice: Array = TwistyModel.SLICES[m.face_names[int(move["face"])]]
		return m._named_turn(slice[0], int(move["turns"]) * int(slice[1]))
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
		_history.append(m)
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
	_history.append(move)
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
