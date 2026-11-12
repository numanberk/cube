class_name UpgradeTile
extends Button
## One upgrade in the Upgrades grid: an icon tile with its cost underneath. Hovering shows a tooltip panel
## with the name, description and cost. Display only: main.gd fills it with set_view() and connects `pressed`.
## V.5: a frame in the category colour (bright when affordable) and a corner badge: "PICK 1" on a choice, ✓ once owned.

const PRESS_DEPTH := 2.0
const BADGE_TOP := 3.0     ## the corner badge's top (the scene's Badge offset_top)
const CONTENT_TOP := 10.0  ## room for the corner badge above the icon (V.5; the scene's Content offset_top)
const DIM_UNAFFORDABLE := 0.55
const DIM_OWNED := 0.7
const DIM_LOCKED_OUT := 0.35
const FRAME_ALPHA := {"affordable": 1.0, "owned": 0.45, "other": 0.3}  ## the category frame's strength (V.5)

@onready var _content: Control = %Content
@onready var _icon: IconSticker = %Icon
@onready var _cost: Label = %Cost
@onready var _badge: Label = %Badge
@onready var _frame: Panel = %Frame

var affordable := false
var owned := false
var _title := ""
var _description := ""
var _cost_text := ""
var _choice := ""        ## choices (5.7b): "Pick one: ..." line in the tooltip, "" for ordinary upgrades
var locked_out := false  ## the other upgrade of its pair was picked this run


## The pressed style sinks the face 2 px (V.2): the content, laid out by anchors, sinks with it (its offsets, so a
## release puts it back exactly). Read from the draw mode, so it also comes back up when the button is disabled
## mid-press or the mouse leaves it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW:
		sync_press.call_deferred()


func sync_press(mode: int = -1) -> void:
	if mode < 0:
		mode = get_draw_mode()
	var sink := PRESS_DEPTH if mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED else 0.0
	_content.offset_top = CONTENT_TOP + sink
	_content.offset_bottom = sink
	_frame.offset_top = sink  # the frame and badge sink with the face
	_badge.position.y = BADGE_TOP + sink


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
	_badge.visible = _choice != "" or owned
	_badge.text = ("PICKED" if owned else ("NOT PICKED" if locked_out else "PICK 1")) if _choice != "" else "✓"
	var frame := IconSticker.colour_of(self, _icon.category)
	frame.a = FRAME_ALPHA["affordable"] if affordable else (FRAME_ALPHA["owned"] if owned else FRAME_ALPHA["other"])
	_frame.self_modulate = frame
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
