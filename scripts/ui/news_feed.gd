class_name NewsFeed
extends RefCounted
## The news feed's rules (task R.4), with no nodes so tests drive it with fake time: GameState events come in through
## the `on_*` methods, which format a line; `advance(delta)` lets one line out every Content.NEWS["interval"] seconds.
## Lines of the same kind waiting together are merged (only the newest is kept: three mastery level-ups in a second
## make one line), the queue is capped (oldest dropped), and the last Content.NEWS["history"] lines are kept for the
## scrollable list, newest first. main.gd connects the signals and shows `history`.

signal line_added(text: String)   ## a line just left the queue (main.gd adds it to the list)

var history: Array[String] = []   ## newest first
var _queue: Array[Dictionary] = []  ## [{key, text}], oldest first
var _wait := 0.0


## Queues a line. Lines with the same `key` replace each other while they wait.
func push(key: String, text: String) -> void:
	for i in _queue.size():
		if _queue[i]["key"] == key:
			_queue.remove_at(i)
			break
	_queue.append({"key": key, "text": text})
	while _queue.size() > int(Content.NEWS["queue"]):
		_queue.pop_front()


## Lets out at most one line per interval. Returns the line shown this call, or "".
func advance(delta: float) -> String:
	_wait -= delta
	if _wait > 0.0 or _queue.is_empty():
		return ""
	_wait = float(Content.NEWS["interval"])
	var text: String = _queue.pop_front()["text"]
	history.push_front(text)
	while history.size() > int(Content.NEWS["history"]):
		history.pop_back()
	line_added.emit(text)
	return text


func pending() -> int:
	return _queue.size()


# --- Events -> lines ---------------------------------------------------------------

## "Club member Ana: 9.87 s 3×3 single!" (or "...joins the team: 9.87 s a 3×3" for the first of a kind).
func on_helper_best_time(building_id: String, puzzle_id: String, seconds: float, first: bool, owned: int = 1) -> void:
	var who := member_name(building_id, owned)
	var puzzle: String = Content.get_puzzle(puzzle_id).get("name", puzzle_id)
	if first:
		push("helper:" + building_id, "%s joins the team: %s a %s" % [who, Num.cube_time(seconds), puzzle])
	else:
		push("helper:" + building_id, "%s: %s %s single!" % [who, Num.cube_time(seconds), puzzle])


## Every level up to 10, then every 5th and every milestone (late on, levels come too fast to read them all).
func on_mastery_level_up(puzzle_id: String, level: int) -> void:
	var text := "%s Mastery %d" % [Content.get_puzzle(puzzle_id).get("name", puzzle_id), level]
	var milestone_level := false
	for milestone: Dictionary in Content.MASTERY["milestones"]:
		if int(milestone["level"]) == level:
			text += ": %s" % milestone["text"]
			milestone_level = true
	if level <= 10 or level % 5 == 0 or milestone_level:
		push("mastery:" + puzzle_id, text)


## Methods and puzzles (from GameState.purchased); helpers and upgrades have their own lines or none.
func on_purchased(kind: String, id: String) -> void:
	match kind:
		"method":
			var def := Content.get_method(id)
			push("method", "Your team learned %s. %s" % [String(def.get("name", id)).trim_prefix("Learn "),
					String(def.get("description", "")).get_slice(".", 0) + "."])
		"puzzle":
			push("puzzle", "New puzzle: %s. Your helpers start on it now." % Content.get_puzzle(id).get("name", id))


func on_time_tier(puzzle_id: String, tier: String, seconds: float) -> void:
	push("tier:" + puzzle_id, "%s team: %s! %s" % [Content.get_puzzle(puzzle_id).get("name", puzzle_id), tier, Num.cube_time(seconds)])


func on_solves_milestone(amount: float) -> void:
	push("milestone", "%s lifetime Solves!" % Num.format(amount))


## The player's own records in the Solve Station.
func on_hand_pb(puzzle_id: String, single: bool, averages: Array, seconds: float) -> void:
	var puzzle: String = Content.get_puzzle(puzzle_id).get("name", puzzle_id)
	var parts := PackedStringArray()
	if single:
		parts.append("single %s" % Num.solve_time(seconds))
	for size: int in averages:
		parts.append("ao%d" % size)
	push("hand:" + puzzle_id, "Your new %s PB: %s" % [puzzle, ", ".join(parts)])


## A puzzle's PB reached a new Solve Station tier (S.3): a permanent bonus.
func on_hand_tier(puzzle_id: String, tier: String) -> void:
	var puzzle: String = Content.get_puzzle(puzzle_id).get("name", puzzle_id)
	var index: int = (Content.SOLVE_REWARDS["tiers"] as Array).find(tier)
	var bonus := roundi(float(Content.SOLVE_REWARDS["tier_moves_bonus"]) * (index + 1) * 100.0)
	push("hand_tier:" + puzzle_id, "Your %s: %s tier! +%d %% moves on the %s for good" % [puzzle, tier, bonus, puzzle])


## A helper's name, the same every time for the same copy: "Club member Ana", "Robot Unit 7".
static func member_name(building_id: String, copy: int) -> String:
	var who: Array = (Content.NEWS["who"] as Dictionary).get(building_id, ["Helper", "people"])
	var pool: Array = Content.NEWS[who[1]]
	var index := absi(hash("%s:%d" % [building_id, copy])) % pool.size()
	return "%s %s" % [who[0], pool[index]]
