class_name PerkNode
extends Button
## One node of the trophy perk tree (task 6.3): icon, name and cost in trophies; hovering shows the description.
## Display only: PerkPanel fills it with set_view() and connects `pressed`.

const PRESS_DEPTH := 2.0
const DIM_UNAFFORDABLE := 0.7
const DIM_LOCKED := 0.4

@onready var _content: Control = %Content
@onready var _icon: IconSticker = %Icon
@onready var _name: Label = %Name
@onready var _cost: Label = %Cost

var status := ""       ## Game.get_perk_status(): owned, available, locked, soon
var affordable := false
var _title := ""
var _description := ""
var _note := ""


func _ready() -> void:
	# The pressed style sinks 2 px (V.2); the content, laid out by anchors, sinks with it.
	button_down.connect(func() -> void: _content.position.y = PRESS_DEPTH)
	button_up.connect(func() -> void: _content.position.y = 0.0)


## view: {icon: Texture2D, title, description, cost: int, status: String, affordable: bool, soon: String (a note),
##   needs: String (the missing parent's name, for "locked")}
func set_view(view: Dictionary) -> void:
	_icon.texture = view.get("icon")
	_icon.category = StringName(view.get("category", &"trophies"))
	_title = view.get("title", "")
	_description = view.get("description", "")
	status = view.get("status", "locked")
	affordable = view.get("affordable", false) and status == "available"
	var cost := int(view.get("cost", 0))
	var cost_text := "%s %s" % [Num.format(float(cost)), "trophy" if cost == 1 else "trophies"]
	_name.text = _title
	match status:
		"owned":
			_cost.text = "Owned"
			_note = "Owned. Kept in every run."
		"soon":
			_cost.text = "Soon"
			_note = "%s. Costs %s." % [view.get("soon", "Coming soon"), cost_text]
		"locked":
			_cost.text = cost_text
			_note = "Needs %s first. Costs %s." % [view.get("needs", "the perk above"), cost_text]
		_:
			_cost.text = cost_text
			_note = "Costs %s (each one you spend gives up +%s %% moves)." % [cost_text, view.get("bonus", "2")] \
					if affordable else "Costs %s. You have %s." % [cost_text, view.get("have", "0")]
			if String(view.get("soon", "")) != "":
				_note = "%s. %s" % [view["soon"], _note]
	theme_type_variation = &"PerkOwned" if status == "owned" else &"ShopCard"
	disabled = not affordable
	_cost.theme_type_variation = &"CostAffordable" if affordable or status == "owned" else &"CostUnaffordable"
	_content.modulate.a = 1.0 if affordable or status == "owned" \
			else (DIM_UNAFFORDABLE if status == "available" else DIM_LOCKED)
	tooltip_text = _title  # must be non-empty for the custom tooltip below to appear


## The tooltip panel: name, description and the cost or why it can't be bought.
func _make_custom_tooltip(_for_text: String) -> Object:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(260, 0)
	box.add_child(_label(_title, &"CardTitle"))
	box.add_child(_label(_description, &"CardLine"))
	box.add_child(_label(_note, &"CostAffordable" if affordable or status == "owned" else &"CostUnaffordable"))
	return box


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
