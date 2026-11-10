class_name PuzzleChip
extends PanelContainer
## One card in the puzzle row under the stage (task 4.3a, D9). Display only; main.gd drives it.
## Running: a small PuzzleView3D (always Graphics Low, no sway) turning at the speed of its share of helper moves,
## with the puzzle's name and Solves/s. Clicking the puzzle emits `chosen` (main focuses it).
## Locked: the next puzzle on the ladder as a padlock card with its cost and an Unlock button (`unlock_pressed`).

signal chosen(puzzle_id: String)
signal unlock_pressed(puzzle_id: String)

const MAX_VISUAL_MOVES := 4.0   ## small puzzles turn at most this many times a second (speed mode above that)

@onready var view: PuzzleView3D = %ChipView
@onready var _lock: TextureRect = %Lock
@onready var _name: Label = %ChipName
@onready var _rate: Label = %ChipRate
@onready var _unlock: Button = %UnlockButton
@onready var _mastery: ProgressBar = %MasteryBar

var puzzle_id := ""
var locked := false
var _base_name := ""
var _move_timer := 0.0


func _ready() -> void:
	view.tapped.connect(func(_at: Vector2) -> void: chosen.emit(puzzle_id))
	_unlock.pressed.connect(func() -> void: unlock_pressed.emit(puzzle_id))
	view.set_graphics("low")
	view.sway_enabled = false
	view.floor_enabled = false  # no cubing mat at this size (V.4 puts the chips on a shelf)


## Reduce motion for the small view; small views never sway either way.
func set_reduce_motion(on: bool) -> void:
	view.set_reduce_motion(on)
	view.sway_enabled = false


## A running puzzle: shows its 3D view.
func show_running(id: String, name: String) -> void:
	locked = false
	if puzzle_id != id:
		view.set_puzzle(id)
	puzzle_id = id
	_base_name = name
	_name.text = name
	view.visible = true
	_lock.visible = false
	_unlock.visible = false
	_mastery.visible = true


## The next locked puzzle: padlock, cost and an Unlock button (enabled when affordable).
func show_locked(id: String, name: String, cost_text: String, affordable: bool) -> void:
	locked = true
	puzzle_id = id
	view.visible = false
	_lock.visible = true
	_unlock.visible = true
	_mastery.visible = false
	_unlock.disabled = not affordable
	_unlock.text = "Unlock" if affordable else "Locked"
	_name.text = name
	_rate.text = cost_text
	_rate.theme_type_variation = &"CostAffordable" if affordable else &"CostUnaffordable"


## Every frame for a running chip: its Solves/s text and how fast its little puzzle turns.
## A running chip's texts: "2×2 · Lv 12", its rate line, and the mastery bar (progress through the level, 0..1).
func update_running(solves_text: String, mastery_level: int = 1, mastery_progress: float = 0.0) -> void:
	_name.text = "%s  ·  Lv %d" % [_base_name, mastery_level]
	_mastery.value = mastery_progress
	_rate.text = solves_text
	_rate.theme_type_variation = &"CardLine"


func advance(delta: float, moves_per_second: float) -> void:
	if locked:
		return
	view.set_speed(moves_per_second)
	if moves_per_second <= 0.0:
		return
	_move_timer += delta * minf(moves_per_second, MAX_VISUAL_MOVES)
	while _move_timer >= 1.0:
		_move_timer -= 1.0
		view.scramble_step()
