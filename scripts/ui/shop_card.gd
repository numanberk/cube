class_name ShopCard
extends Button
## One helper in the shop: icon, name, description, rate line, owned count and cost.
## Display only: main.gd fills it from Game with set_view() and connects `pressed` to the purchase.
## Affordable cards are bright with a green cost and lift on hover; others are dimmed with a grey cost.
## A locked card shows "???", a padlock and what unlocks it.

const LIFT := 3.0          ## pixels an affordable card rises on hover
const LIFT_TIME := 0.12
const DIM_UNAFFORDABLE := 0.62
const DIM_LOCKED := 0.45

@onready var _content: Control = %Content
@onready var _icon: TextureRect = %Icon
@onready var _title: Label = %Title
@onready var _line1: Label = %Line1
@onready var _line2: Label = %Line2
@onready var _owned: Label = %Owned
@onready var _cost: Label = %Cost

var affordable := false
var locked := false
var _hovered := false
var _tween: Tween


func _ready() -> void:
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


## view: {icon: Texture2D, title, line1, line2, owned, cost (strings), affordable: bool, locked: bool}
func set_view(view: Dictionary) -> void:
	_icon.texture = view.get("icon")
	_title.text = view.get("title", "")
	_line1.text = view.get("line1", "")
	_line2.text = view.get("line2", "")
	_line2.visible = _line2.text != ""
	_owned.text = view.get("owned", "")
	_cost.text = view.get("cost", "")
	locked = view.get("locked", false)
	affordable = view.get("affordable", false) and not locked
	disabled = not affordable
	_cost.theme_type_variation = &"CostAffordable" if affordable else &"CostUnaffordable"
	_content.modulate.a = 1.0 if affordable else (DIM_LOCKED if locked else DIM_UNAFFORDABLE)
	_update_lift()


func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_update_lift()


func _update_lift() -> void:
	var target := -LIFT if _hovered and affordable else 0.0
	if is_equal_approx(_content.position.y, target):
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_content, "position:y", target, LIFT_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
