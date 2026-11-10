class_name UpgradeTile
extends Button
## One upgrade in the Upgrades grid: an icon tile with its cost underneath. Hovering shows a tooltip panel
## with the name, description and cost. Display only: main.gd fills it with set_view() and connects `pressed`.

const PRESS_DEPTH := 2.0
const DIM_UNAFFORDABLE := 0.55
const DIM_OWNED := 0.7
const DIM_LOCKED_OUT := 0.35

@onready var _content: Control = %Content
@onready var _icon: IconSticker = %Icon
@onready var _cost: Label = %Cost
@onready var _badge: Label = %Badge

var affordable := false
var owned := false
var _title := ""
var _description := ""
var _cost_text := ""
var _choice := ""        ## choices (5.7b): "Pick one: ..." line in the tooltip, "" for ordinary upgrades
var locked_out := false  ## the other upgrade of its pair was picked this run


func _ready() -> void:
	# The pressed style sinks 2 px (V.2); the content, laid out by anchors, sinks with it.
	button_down.connect(func() -> void: _content.position.y = PRESS_DEPTH)
	button_up.connect(func() -> void: _content.position.y = 0.0)


## view: {icon: Texture2D, title, description, cost (strings), affordable: bool, owned: bool,
##   choice: String (a choice upgrade's "Pick one" note), locked_out: bool (its partner was picked),
##   category: StringName (the sticker colour, IconSticker.CATEGORIES; default upgrades)}
func set_view(view: Dictionary) -> void:
	_icon.texture = view.get("icon")
	_icon.category = StringName(view.get("category", &"upgrades"))
	_title = view.get("title", "")
	_description = view.get("description", "")
	_cost_text = view.get("cost", "")
	_choice = view.get("choice", "")
	owned = view.get("owned", false)
	locked_out = view.get("locked_out", false) and not owned
	affordable = view.get("affordable", false) and not owned and not locked_out
	disabled = not affordable
	_badge.visible = _choice != ""
	_badge.text = "PICKED" if owned else ("NOT PICKED" if locked_out else "PICK 1")
	_cost.text = "Owned" if owned else ("—" if locked_out else _cost_text)
	_cost.theme_type_variation = &"CostAffordable" if affordable or owned else &"CostUnaffordable"
	_icon.muted = not affordable
	_content.modulate.a = 1.0 if affordable else (DIM_OWNED if owned else (DIM_LOCKED_OUT if locked_out else DIM_UNAFFORDABLE))
	tooltip_text = _title  # must be non-empty for the custom tooltip below to appear


## The tooltip panel: name, description and cost.
func _make_custom_tooltip(_for_text: String) -> Object:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(240, 0)
	box.add_child(_label(_title, &"CardTitle"))
	var description := _label(_description, &"CardLine")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	if _choice != "":
		var choice := _label(_choice, &"CardLine")
		choice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(choice)
	if locked_out:
		box.add_child(_label("Not picked this run", &"CostUnaffordable"))
	elif owned:
		box.add_child(_label("Owned", &"CostAffordable"))
	else:
		box.add_child(_label("Costs %s Solves" % _cost_text, &"CostAffordable" if affordable else &"CostUnaffordable"))
	return box


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
