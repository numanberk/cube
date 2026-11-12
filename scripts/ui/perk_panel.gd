class_name PerkPanel
extends Control
## The trophy perk tree (task 6.3): one column per branch of Content.PERK_BRANCHES, each a small tree of PerkNodes
## (a node sits one row below the perk it needs) joined by lines. Display only: main.gd opens it and refreshes it with
## set_view() (a view per perk from Game), and buys a perk when a node emits `perk_pressed`.
## Escape, Close or a click outside close it.

signal closed
signal perk_pressed(id: String)

const PerkNodeScene := preload("res://scenes/perk_node.tscn")
const NODE_SIZE := Vector2(116, 108)  ## matches perk_node.tscn's minimum size
const GAP := Vector2(14, 26)
const COLUMN_WIDTH := 2.0 * 116.0 + 14.0

@onready var _dim: ColorRect = %Dim
@onready var _panel: Control = %Panel
@onready var _close: Button = %CloseButton
@onready var _trophy_chip: StatChip = %TrophyChip
@onready var _bonus_chip: StatChip = %BonusChip
@onready var _branches: HBoxContainer = %Branches

var _nodes: Dictionary = {}   ## perk id -> PerkNode
var _areas: Dictionary = {}   ## branch id -> the Control its nodes and lines are drawn in
var _owned: Dictionary = {}   ## perk id -> true, for the line colours


func _ready() -> void:
	_close.pressed.connect(close)
	_dim.gui_input.connect(_on_dim_input)
	_build()


func open(header: Dictionary, views: Dictionary) -> void:
	set_view(header, views)
	UiFx.open_panel(self, _dim, _panel)  # V.6


func close() -> void:
	if not visible or UiFx.is_closing(self):
		return
	UiFx.close_panel(self, _dim, _panel)
	closed.emit()


## header: {trophies: "111", unit: "unspent trophies", bonus: "+222 %"} (V.8: StatChips);
## views: perk id -> PerkNode.set_view() dictionary.
func set_view(header: Dictionary, views: Dictionary) -> void:
	_trophy_chip.set_stat(String(header.get("trophies", "0")), String(header.get("unit", "trophies")))
	_bonus_chip.set_stat(String(header.get("bonus", "+0 %")), "moves")
	_owned.clear()
	for id: String in views:
		if _nodes.has(id):
			(_nodes[id] as PerkNode).set_view(views[id])
		if views[id].get("status", "") == "owned":
			_owned[id] = true
	for area: Control in _areas.values():
		area.queue_redraw()


## Rows of perk ids for one branch: row 0 is the branch's first node, then each node one row below its parent.
static func layout_rows(branch_id: String) -> Array:
	var depth := {}
	var rows: Array = []
	for def: Dictionary in Content.PERKS:  # parents come before their children in Content.PERKS
		if def["branch"] != branch_id:
			continue
		var d := 0
		for need: Variant in def.get("requires", []):
			d = maxi(d, int(depth.get(str(need), -1)) + 1)
		depth[def["id"]] = d
		while rows.size() <= d:
			rows.append([])
		(rows[d] as Array).append(def["id"])
	return rows


func _build() -> void:
	for branch: Dictionary in Content.PERK_BRANCHES:
		var column := VBoxContainer.new()
		column.theme_type_variation = &"TightBox"
		column.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
		var title := Label.new()
		title.theme_type_variation = &"CardTitle"
		title.text = branch["name"]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
		var blurb := Label.new()
		blurb.theme_type_variation = &"FaintLabel"
		blurb.text = branch["description"]
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
		column.add_child(blurb)
		var area := Control.new()
		area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rows := layout_rows(branch["id"])
		area.custom_minimum_size = Vector2(COLUMN_WIDTH, rows.size() * NODE_SIZE.y + maxi(0, rows.size() - 1) * GAP.y)
		for r in rows.size():
			var row: Array = rows[r]
			var row_width := row.size() * NODE_SIZE.x + (row.size() - 1) * GAP.x
			for i in row.size():
				var node: PerkNode = PerkNodeScene.instantiate()
				var x := (COLUMN_WIDTH - row_width) * 0.5 + i * (NODE_SIZE.x + GAP.x)
				var parents: Array = Content.get_perk(String(row[i])).get("requires", [])
				if row.size() == 1 and parents.size() == 1 and _nodes.has(str(parents[0])):
					x = (_nodes[str(parents[0])] as PerkNode).position.x  # a lone child sits right under its parent
				node.position = Vector2(x, r * (NODE_SIZE.y + GAP.y))
				node.size = NODE_SIZE
				node.pressed.connect(func() -> void: perk_pressed.emit(String(row[i])))
				area.add_child(node)
				_nodes[row[i]] = node
		area.draw.connect(_draw_lines.bind(area, String(branch["id"])))
		column.add_child(area)
		_areas[branch["id"]] = area
		_branches.add_child(column)


## A line from each perk's parent down to it: bright once the perk is owned.
func _draw_lines(area: Control, branch_id: String) -> void:
	for def: Dictionary in Content.PERKS:
		if def["branch"] != branch_id or not _nodes.has(def["id"]):
			continue
		var child: PerkNode = _nodes[def["id"]]
		for need: Variant in def.get("requires", []):
			if not _nodes.has(str(need)):
				continue
			var parent: PerkNode = _nodes[str(need)]
			var from := parent.position + Vector2(NODE_SIZE.x * 0.5, NODE_SIZE.y)
			var to := child.position + Vector2(NODE_SIZE.x * 0.5, 0.0)
			var owned := _owned.has(def["id"])
			var color := get_theme_color(&"line_owned" if owned else &"line", &"PerkTree")
			var mid := (from.y + to.y) * 0.5
			var path := PackedVector2Array([from, Vector2(from.x, mid), Vector2(to.x, mid), to])
			if owned:  # V.8: an owned path glows (a wide soft line under the bright one)
				area.draw_polyline(path, Color(color, 0.18), 10.0, true)
				area.draw_polyline(path, Color(color, 0.3), 5.0, true)
			area.draw_polyline(path, color, 2.5 if owned else 2.0, true)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()
