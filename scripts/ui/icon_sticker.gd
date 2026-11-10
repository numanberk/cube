class_name IconSticker
extends PanelContainer
## An item's icon as a coloured "sticker" (task V.2, D15b): a rounded tile in the item's category colour with a
## gradient and a bevel (the IconTile style, a greyscale texture tinted by self_modulate), the glyph on top with a
## soft shadow. Category colours are the theme's Palette tokens `cat_<category>`; light ones (yellow, white) get a
## dark glyph. `muted` (a card that can't be bought) darkens and greys the tile and keeps the glyph white, so the
## icon stays readable when the card also dims its content. Display only.

const CATEGORIES: Array[StringName] = [&"helpers", &"upgrades", &"puzzles", &"lab", &"trophies", &"station", &"locked"]
const LIGHT_LUMINANCE := 0.6  ## above this the glyph is dark instead of white
const INK_DARK := Color(0.09, 0.1, 0.12, 0.9)
const MUTE_GREY := 0.45     ## how far a muted tile goes towards grey
const MUTE_DARKEN := 0.35

@export var texture: Texture2D:
	set(value):
		texture = value
		_apply()
@export var category: StringName = &"helpers":
	set(value):
		category = value
		_apply()
@export var muted := false:
	set(value):
		muted = value
		_apply()


func _ready() -> void:
	_apply()


## The tile's colour: the Palette token for this category.
func get_colour() -> Color:
	return colour_of(self, category)


static func colour_of(control: Control, which: StringName) -> Color:
	return control.get_theme_color(StringName("cat_%s" % which), &"Palette")


func _apply() -> void:
	if not is_node_ready():
		return
	var icon: TextureRect = %Glyph
	var shadow: TextureRect = %GlyphShadow
	icon.texture = texture
	shadow.texture = texture
	var colour := get_colour()
	if muted:
		var grey := colour.get_luminance()
		colour = colour.lerp(Color(grey, grey, grey), MUTE_GREY).darkened(MUTE_DARKEN)
	self_modulate = colour
	var light := colour.get_luminance() > LIGHT_LUMINANCE
	icon.modulate = INK_DARK if light else Color.WHITE
	shadow.visible = not light
