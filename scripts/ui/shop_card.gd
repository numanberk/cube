class_name ShopCard
extends Button
## One helper in the shop: icon, name, description, rate line, owned count and cost.
## Display only: main.gd fills it from Game with set_view() and connects `pressed` to the purchase.
## Affordable cards are bright with a green cost and lift on hover; others are dimmed with a grey cost.
## A locked card shows "???", a padlock and what unlocks it. The icon is a sticker in the card's category colour
## (V.2): helpers by default, `category` in the view for others (Lab); a locked card's sticker is grey.

const LIFT := 3.0          ## pixels an affordable card rises on hover
const LIFT_TIME := 0.12
const PRESS_DEPTH := 2.0   ## pixels the content sinks while held, with the card's pressed style (V.2)
const DIM_UNAFFORDABLE := 0.62
const DIM_LOCKED := 0.45

@onready var _content: Control = %Content
@onready var _sticker: IconSticker = %IconTile
@onready var _title: Label = %Title
@onready var _line1: Label = %Line1
@onready var _line2: Label = %Line2
@onready var _owned: Label = %Owned
@onready var _cost: Label = %Cost

var affordable := false
var locked := false
var _hovered := false
var _held := false
var _tween: Tween


func _ready() -> void:
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


## view: {icon: Texture2D, title, line1, line2, owned, cost (strings), affordable: bool, locked: bool, active: bool,
##   category: StringName (IconSticker.CATEGORIES; default helpers)}
## `active`: shown bright but not pressable (the Lab project being researched).
func set_view(view: Dictionary) -> void:
	_sticker.texture = view.get("icon")
	_title.text = view.get("title", "")
	_line1.text = view.get("line1", "")
	_line2.text = view.get("line2", "")
	_line2.visible = _line2.text != ""
	_owned.text = view.get("owned", "")
	_cost.text = view.get("cost", "")
	locked = view.get("locked", false)
	_sticker.category = &"locked" if locked else StringName(view.get("category", &"helpers"))
	affordable = view.get("affordable", false) and not locked
	disabled = not affordable
	_cost.theme_type_variation = &"CostAffordable" if affordable else &"CostUnaffordable"
	_content.modulate.a = 1.0 if affordable or view.get("active", false) else (DIM_LOCKED if locked else DIM_UNAFFORDABLE)
	_sticker.muted = not affordable and not locked and not view.get("active", false)
	_update_lift()


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_update_lift()


## The pressed style sinks the face 2 px (V.2): the content, laid out by anchors, sinks with it. Read from the draw
## mode (not button_down/up), so it also comes back up when the card is disabled mid-press or the mouse leaves.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW:
		sync_press.call_deferred()


func sync_press(mode: int = -1) -> void:
	if mode < 0:
		mode = get_draw_mode()
	var held := affordable and (mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED)
	if held != _held:
		_held = held
		if not held:
			_content.position.y = 0.0  # back up at once, like the face
		_update_lift()


func _update_lift() -> void:
	if _held:  # at once: a click is shorter than the lift tween
		if _tween != null:
			_tween.kill()
		_content.position.y = PRESS_DEPTH
		return
	var target := -LIFT if _hovered and affordable else 0.0
	if is_equal_approx(_content.position.y, target):
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_content, "position:y", target, LIFT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
