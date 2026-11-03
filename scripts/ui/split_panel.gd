class_name SplitPanel
extends VBoxContainer
## The "Puzzles" shop tab (task 4.3b, D9): how the helpers' moves are shared between the running puzzles.
## One row per unlocked puzzle with − / + (10 % steps), its share, and its moves/s and Solves/s; plus the presets.
## Every change goes through Game (set the share there; it keeps the total at 100 %). Display only.

const STEP := 0.1

@onready var _rows: VBoxContainer = %SplitRows
@onready var _hint: Label = %SplitHint
@onready var _newest: Button = %PresetNewest
@onready var _even: Button = %PresetEven

var _row_labels: Dictionary = {}  ## puzzle id -> {share: Label, info: Label, minus: Button, plus: Button}


func _ready() -> void:
	_newest.pressed.connect(Game.set_split_preset.bind("newest"))
	_even.pressed.connect(Game.set_split_preset.bind("even"))
	Game.split_changed.connect(refresh)
	Game.puzzle_unlocked.connect(func(_id: String) -> void: rebuild())
	Game.state_reset.connect(rebuild)
	rebuild()


func rebuild() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_row_labels.clear()
	for id in Game.get_unlocked_puzzle_ids():
		var row := HBoxContainer.new()
		var name_label := _label(Content.get_puzzle(id)["name"], &"CardTitle")
		name_label.custom_minimum_size = Vector2(84, 0)
		row.add_child(name_label)
		var minus := _button("−")
		minus.pressed.connect(Game.adjust_share.bind(id, -STEP))
		row.add_child(minus)
		var share := _label("100%", &"CardOwned")
		share.custom_minimum_size = Vector2(74, 0)
		share.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(share)
		var plus := _button("+")
		plus.pressed.connect(Game.adjust_share.bind(id, STEP))
		row.add_child(plus)
		var info := _label("", &"CardLine")
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(info)
		_rows.add_child(row)
		_row_labels[id] = {"share": share, "info": info, "minus": minus, "plus": plus}
	refresh()


func refresh() -> void:
	var several := Game.get_unlocked_puzzle_ids().size() > 1
	_hint.text = ("Your helpers' moves are shared between your puzzles. Each puzzle solves on its own, and higher puzzles "
			+ "pay more per move.") if several else "Unlock the 3×3 to share your helpers between two puzzles."
	_newest.disabled = not several
	_even.disabled = not several
	for id: String in _row_labels:
		var labels: Dictionary = _row_labels[id]
		var share := Game.get_puzzle_share(id)
		(labels["share"] as Label).text = "%d%%" % roundi(share * 100.0)
		(labels["info"] as Label).text = "%s moves/s  ·  +%s Solves/s" % [
			Num.format(Game.get_puzzle_moves_per_second(id)), Num.format(Game.get_puzzle_solves_per_second(id)),
		]
		(labels["minus"] as Button).disabled = not several or share <= 0.0
		(labels["plus"] as Button).disabled = not several or share >= 1.0


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"ToggleChip"
	button.custom_minimum_size = Vector2(36, 0)
	return button
