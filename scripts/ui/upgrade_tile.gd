class_name UpgradeTile
extends Button
## One upgrade in the Upgrades grid: an icon tile with its cost underneath. Hovering shows a tooltip panel
## with the name, description and cost. Display only: main.gd fills it with set_view() and connects `pressed`.

const DIM_UNAFFORDABLE := 0.55
const DIM_OWNED := 0.7

@onready var _content: Control = %Content
@onready var _icon: TextureRect = %Icon
@onready var _cost: Label = %Cost

var affordable := false
var owned := false
var _title := ""
var _description := ""
var _cost_text := ""


## view: {icon: Texture2D, title, description, cost (strings), affordable: bool, owned: bool}
func set_view(view: Dictionary) -> void:
	_icon.texture = view.get("icon")
	_title = view.get("title", "")
	_description = view.get("description", "")
	_cost_text = view.get("cost", "")
	owned = view.get("owned", false)
	affordable = view.get("affordable", false) and not owned
	disabled = not affordable
	_cost.text = "Owned" if owned else _cost_text
	_cost.theme_type_variation = &"CostAffordable" if affordable or owned else &"CostUnaffordable"
	_content.modulate.a = 1.0 if affordable else (DIM_OWNED if owned else DIM_UNAFFORDABLE)
	tooltip_text = _title  # must be non-empty for the custom tooltip below to appear


## The tooltip panel: name, description and cost.
func _make_custom_tooltip(_for_text: String) -> Object:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(240, 0)
	box.add_child(_label(_title, &"CardTitle"))
	var description := _label(_description, &"CardLine")
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(description)
	if owned:
		box.add_child(_label("Owned", &"CostAffordable"))
	else:
		box.add_child(_label("Costs %s Solves" % _cost_text, &"CostAffordable" if affordable else &"CostUnaffordable"))
	return box


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
