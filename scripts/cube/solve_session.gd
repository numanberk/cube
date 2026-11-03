class_name SolveSession
extends RefCounted
## The Solve Station's solving rules (task S.1): scramble, WCA inspection, timer, move count and session results.
## Pure data like TwistyModel: no nodes, no economy. Times come in as `now` (seconds, any clock) so tests can drive it.
## GameState will keep records and pay rewards from the results (tasks S.2, S.3).
##
## States: "idle" (nothing started), "inspecting" (scrambled, inspection running; rotations allowed), "ready" (scrambled,
## inspection off), "solving" (timer running), "done" (solved; turning still works but changes nothing).
## The timer starts with the first turn that isn't a whole-puzzle rotation and stops the moment the puzzle is solved
## (in any orientation). Inspection: starting after 15 s is +2, after 17 s a DNF (Content.INSPECTION).
## Keys follow csTimer's layout (Content.SOLVE_KEYS), with movable hands on big cubes.

const AVERAGE_SIZES := [5, 12]

var puzzle_id := ""
var model: TwistyModel = null
var scramble: Array[Dictionary] = []
var state := "idle"
var inspection := true       ## WCA inspection on (set before start)
var penalty := ""            ## "", "+2" or "DNF" for the current attempt
var moves := 0               ## turns since the timer started (rotations don't count)
var left_hand := 1           ## depth of the left hand (csTimer's keys 3/4), 1 = outer layer
var right_hand := 1          ## depth of the right hand (keys 8/7)
var results: Array[Dictionary] = []  ## this session: {time (raw seconds), penalty, moves, scramble (notation)}

var _inspection_started := 0.0
var _started_at := 0.0
var _finished_at := 0.0


## Scrambles a new attempt on a cube ("2x2" ... "7x7"). Returns false for anything else (the Megaminx comes later).
func start(id: String, now: float, rng: RandomNumberGenerator = null) -> bool:
	var new_model := PuzzleShapes.from_id(id)
	if new_model == null or new_model.size == 0:
		return false
	puzzle_id = id
	model = new_model
	var length := int(Content.get_puzzle(id).get("scramble_length", 25))
	scramble = model.scramble(length, rng)
	while model.is_solved():  # vanishingly rare, but a solved scramble would be silly
		scramble.append_array(model.scramble(1, rng))
	state = "inspecting" if inspection else "ready"
	penalty = ""
	moves = 0
	left_hand = 1
	right_hand = 1
	_inspection_started = now
	_started_at = 0.0
	_finished_at = 0.0
	return true


func scramble_text() -> String:
	return "" if model == null else model.notation_sequence(scramble)


## Handles one key press. Returns the move it made ({} if none), so the view can animate it.
func press_key(key: int, now: float) -> Dictionary:
	if model == null:
		return {}
	if key == Content.SOLVE_HAND_RESET_KEY:
		left_hand = 1
		right_hand = 1
		return {}
	if Content.SOLVE_HAND_KEYS.has(key):
		var hand: Array = Content.SOLVE_HAND_KEYS[key]
		var limit := maxi(1, model.size - 1)
		if hand[0] == "l":
			left_hand = clampi(left_hand + int(hand[1]), 1, limit)
		else:
			right_hand = clampi(right_hand + int(hand[1]), 1, limit)
		return {}
	var move := move_for_key(key)
	if move.is_empty():
		return {}
	turn(move, now)
	return move


## The move a key makes on this cube with the current hands, or {} if the key isn't mapped (or makes no sense here,
## like E on a 2×2).
func move_for_key(key: int) -> Dictionary:
	if model == null or not Content.SOLVE_KEYS.has(key):
		return {}
	var entry: Array = Content.SOLVE_KEYS[key]
	var n := model.size
	var first := _layer(entry[0], n)
	var last := mini(_layer(entry[1], n), n)
	var face := model.face_names.find(String(entry[2]))
	if face < 0 or first < 1 or first > last:
		return {}
	return model.make_move(face, int(entry[3]), last - first + 1, first - 1)


func _layer(token: Variant, n: int) -> int:
	if typeof(token) == TYPE_INT:
		return int(token)
	match String(token):
		"n":
			return n
		"n-1":
			return n - 1
		"l":
			return left_hand
		"l+1":
			return left_hand + 1
		"r":
			return right_hand
		"r+1":
			return right_hand + 1
	push_warning("Unknown layer token '%s' in Content.SOLVE_KEYS" % token)
	return 0


## Applies a move. The first real turn starts the timer (and settles the inspection penalty); solving stops it.
func turn(move: Dictionary, now: float) -> void:
	if model == null or state == "idle":
		return
	model.apply(move)
	if state == "done":
		return
	var rotation := model.is_rotation(move)
	if state in ["inspecting", "ready"]:
		if rotation:
			return
		if state == "inspecting":
			penalty = inspection_penalty(now - _inspection_started)
		state = "solving"
		_started_at = now
	if not rotation:
		moves += 1
	if model.is_solved():
		state = "done"
		_finished_at = now
		results.append({"time": _finished_at - _started_at, "penalty": penalty, "moves": moves, "scramble": scramble_text()})


## Called every frame: an inspection that runs past 17 s becomes a DNF (the attempt can still be finished).
func update(now: float) -> void:
	if state == "inspecting" and now - _inspection_started > float(Content.INSPECTION["plus_two_until"]):
		penalty = "DNF"


static func inspection_penalty(inspected: float) -> String:
	if inspected > float(Content.INSPECTION["plus_two_until"]):
		return "DNF"
	if inspected > float(Content.INSPECTION["seconds"]):
		return "+2"
	return ""


## Seconds of inspection left (negative once it's over), or 0 when not inspecting.
func inspection_left(now: float) -> float:
	if state != "inspecting":
		return 0.0
	return float(Content.INSPECTION["seconds"]) - (now - _inspection_started)


## The running (or final) time, without penalties.
func elapsed(now: float) -> float:
	match state:
		"solving":
			return now - _started_at
		"done":
			return _finished_at - _started_at
	return 0.0


## Turns per second of the finished (or running) attempt.
func tps(now: float) -> float:
	var t := elapsed(now)
	return moves / t if t > 0.0 else 0.0


## A result's time with its penalty: +2 adds 2 s, a DNF is INF.
static func final_time(result: Dictionary) -> float:
	match String(result.get("penalty", "")):
		"DNF":
			return INF
		"+2":
			return float(result["time"]) + 2.0
	return float(result["time"])


## Best single this session (INF if none or all DNF).
func best() -> float:
	var top := INF
	for result in results:
		top = minf(top, final_time(result))
	return top


## WCA average of the last `count` results: drop the best and the worst, average the rest (rounded to 0.01 s). One DNF is dropped as the
## worst; two or more make the average a DNF (INF). Returns -1 when there aren't enough results yet.
func average(count: int) -> float:
	if results.size() < count:
		return -1.0
	var times: Array[float] = []
	for result in results.slice(results.size() - count):
		times.append(final_time(result))
	return SolveSession.trimmed_average(times)


static func trimmed_average(times: Array[float]) -> float:
	var sorted := times.duplicate()
	sorted.sort()
	var counted := sorted.slice(1, sorted.size() - 1)
	var total := 0.0
	for t: float in counted:
		if is_inf(t):
			return INF
		total += t
	return snappedf(total / counted.size(), 0.01)  # WCA rounds averages to the hundredth (singles are truncated)
