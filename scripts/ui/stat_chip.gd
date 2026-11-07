class_name StatChip
extends PanelContainer
## A stat in a pill (task V.1): icon + value + an optional small unit ("+73" "/s"). Display only: main.gd fills it
## with set_stat(). The value uses the display font, which has proportional digits, so `value_min_width` keeps a
## changing number from pushing its neighbours around.

## The icon on the left (assets/icons/stat_*.svg).
@export var icon: Texture2D:
	set(value):
		icon = value
		if is_node_ready():
			_icon.texture = value
## Colour of the value: "normal" (white), "accent" (green) or "gold".
@export_enum("normal", "accent", "gold") var tone := "normal":
	set(value):
		tone = value
		if is_node_ready():
			_apply_tone()
## Tint the icon in the value's colour (off for icons that have their own colours, like the Solves cube).
@export var tint_icon := true:
	set(value):
		tint_icon = value
		if is_node_ready():
			_apply_tone()
## Minimum width of the value, in pixels (0: just fit the text).
@export var value_min_width := 0.0:
	set(value):
		value_min_width = value
		if is_node_ready():
			_value.custom_minimum_size.x = value

const TONE_VARIATIONS := {"normal": &"StatValue", "accent": &"StatValueAccent", "gold": &"StatValueGold"}

@onready var _icon: TextureRect = %Icon
@onready var _value: Label = %Value
@onready var _unit: Label = %Unit


func _ready() -> void:
	_icon.texture = icon
	_value.custom_minimum_size.x = value_min_width
	_apply_tone()


## value: the number, already formatted with Num.format(); unit: "/s", "TPS", "12 s"... ("" hides it).
func set_stat(value: String, unit: String = "") -> void:
	_value.text = value
	_unit.text = unit
	_unit.visible = unit != ""


## What the chip reads, e.g. "+73 /s" (for tests and tooltips).
func get_text() -> String:
	return _value.text if _unit.text == "" else "%s %s" % [_value.text, _unit.text]


func _apply_tone() -> void:
	_value.theme_type_variation = TONE_VARIATIONS.get(tone, &"StatValue")
	# The colour comes from the theme (StatValueAccent / StatValueGold), so it's retuned there, not here.
	_icon.modulate = _value.get_theme_color(&"font_color") if tint_icon and tone != "normal" else Color.WHITE
