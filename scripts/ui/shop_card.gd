class_name ShopCard
extends Button
## One helper in the shop: icon, name, description, rate line, owned count and cost.
## Display only: main.gd fills it from Game with set_view() and connects `pressed` to the purchase.
## Affordable cards are bright with a green cost and lift on hover; others are dimmed with a grey cost.
## A locked card shows "???", a padlock and what unlocks it. The icon is a sticker in the card's category colour
## (V.2): helpers by default, `category` in the view for others (Lab); a locked card's sticker is grey.
## V.5: a bar along the bottom fills towards the cost (green and gently breathing once affordable, so buyable, close
## and far cards read at a glance), milestone pips under the owned count, and a locked helper's icon as a silhouette.

const LIFT := 3.0          ## pixels an affordable card rises on hover
const LIFT_TIME := 0.12
const PRESS_DEPTH := 2.0   ## pixels the content sinks while held, with the card's pressed style (V.2)
const DIM_UNAFFORDABLE := 0.62
const DIM_LOCKED := 0.45
const PIP_SIZE := Vector2(7, 7)
const BREATHE_SPEED := 2.4  ## radians per second of the affordable bar's glow
const BREATHE_LOW := 0.7    ## the glow's dimmest alpha

static var reduce_motion := false  ## set by main.gd from Settings (no breathing bar then)

@onready var _content: Control = %Content
@onready var _sticker: IconSticker = %IconTile
@onready var _title: Label = %Title
@onready var _line1: Label = %Line1
@onready var _line2: Label = %Line2
@onready var _owned: Label = %Owned
@onready var _cost: Label = %Cost
@onready var _pips: HBoxContainer = %Pips
@onready var _bar: ProgressBar = %Bar

var affordable := false
var locked := false
var _hovered := false
var _held := false
var _tween: Tween
var _shown := false        ## set_view() ran before (V.6: only a change pops, not the first view)
var _owned_roll: Tween     ## the owned count rolling up after a buy (V.6)...
var _owned_target := ""    ## ...and the count it rolls to
var _pop: Tween            ## the pop when the card becomes affordable (V.6)


func _ready() -> void:
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	set_process(false)


## The affordable bar breathes: its alpha eases between BREATHE_LOW and 1.
func _process(_delta: float) -> void:
	if reduce_motion:
		_bar.modulate.a = 1.0
		return
	# One clock for every card, so affordable bars breathe together.
	_bar.modulate.a = lerpf(BREATHE_LOW, 1.0, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * BREATHE_SPEED))


## view: {icon: Texture2D, title, line1, line2, owned, cost (strings), affordable: bool, locked: bool, active: bool,
##   category: StringName (IconSticker.CATEGORIES; default helpers), progress: float (0..1 towards the cost or the
##   unlock; absent = no bar), pips: [bought, total, ready] (milestone upgrades bought, all milestones, and how many
##   more are reached but not bought yet; absent = none), silhouette: bool}
## `active`: shown bright but not pressable (the Lab project being researched).
func set_view(view: Dictionary) -> void:
	_sticker.texture = view.get("icon")
	_title.text = view.get("title", "")
	_line1.text = view.get("line1", "")
	_line2.text = view.get("line2", "")
	_line2.visible = _line2.text != ""
	_set_owned(String(view.get("owned", "")))
	_cost.text = view.get("cost", "")
	locked = view.get("locked", false)
	_sticker.category = &"locked" if locked else StringName(view.get("category", &"helpers"))
	var was_affordable := affordable
	affordable = view.get("affordable", false) and not locked
	if _shown and affordable and not was_affordable:  # V.6: a card you can now buy pops once, its bar shines
		_pop = UiFx.pop(self)
		UiFx.sheen(_bar)
	_shown = true
	disabled = not affordable
	_cost.theme_type_variation = &"CostAffordable" if affordable else &"CostUnaffordable"
	_content.modulate.a = 1.0 if affordable or view.get("active", false) else (DIM_LOCKED if locked else DIM_UNAFFORDABLE)
	_sticker.muted = not affordable and not locked and not view.get("active", false)
	_sticker.silhouette = view.get("silhouette", false)
	_bar.visible = view.has("progress")
	_bar.value = clampf(float(view.get("progress", 0.0)), 0.0, 1.0)
	_bar.theme_type_variation = &"CostBar" if affordable else &"CostBarDim"
	set_process(_bar.visible and affordable)
	if not is_processing():
		_bar.modulate.a = 1.0
	_set_pips(view.get("pips", []))
	_update_lift()


## The owned count; a count that went up rolls up to its new value (V.6).
func _set_owned(text: String) -> void:
	var rolling := _owned_roll != null and _owned_roll.is_valid() and _owned_roll.is_running()
	if rolling and text == _owned_target:
		return  # rolling to it already
	if rolling:
		_owned_roll.kill()  # a new count while rolling: roll on from where it is
	var before := _owned.text
	_owned_target = text
	if _shown and before.is_valid_int() and text.is_valid_int() and int(text) > int(before):
		_owned_roll = UiFx.roll_number(_owned, float(before), float(text),
				func(value: float) -> String: return str(roundi(value)))
		if _owned_roll != null:
			return
	_owned.text = text


## Where the owned count is (global), for a "+1" flying to it.
func get_owned_center() -> Vector2:
	return _owned.get_global_rect().get_center()


## Milestone pips (V.5): the bought ones gold, then the ready ones (reached, buyable in Upgrades) outlined in gold.
func _set_pips(pips: Array) -> void:
	_pips.visible = pips.size() >= 2 and int(pips[1]) > 0
	if not _pips.visible:
		return
	var total := int(pips[1])
	while _pips.get_child_count() < total:
		var pip := Panel.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pips.add_child(pip)
	for i in _pips.get_child_count():
		var pip: Panel = _pips.get_child(i)
		pip.visible = i < total
		var ready := int(pips[2]) if pips.size() > 2 else 0
		pip.theme_type_variation = &"PipOn" if i < int(pips[0]) else (&"PipReady" if i < int(pips[0]) + ready else &"Pip")


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
