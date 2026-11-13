class_name Toast
extends Control
## Small pops (tasks 7.0b, 7.1b, 7.3b): a card in the stage's bottom-right corner for a career moment, an achievement
## earned or a Cube Collection drop. Smaller than a Banner (V.7): no confetti, no sweep, it doesn't cover the cube.
## Display only: main.gd pushes views in and calls advance(delta) every frame (tests drive it with fake time).
## One at a time, in order. So a burst never spams (an old save earning 20 achievements at its first check): a view of
## a kind already waiting merges into it ("and 3 more"), and at most MAX_QUEUE wait (the oldest goes first).
## clear() empties it all. Reduce motion (UiFx.reduce_motion): it still shows, without sliding.
## Built in code; %Toast in main.tscn is this script on a full-rect Control that ignores the mouse.

const HOLD := 3.4            ## seconds a toast stays up
const GAP := 0.3             ## seconds between two toasts
const MAX_QUEUE := 4
const WIDTH := 330.0
const TEXT_WIDTH := 250.0    ## WIDTH less the accent, the sticker, the gaps and the card's margins
const MARGIN := Vector2(14, 14)  ## from the corner of `corner_rect`
const SLIDE := Vector2(40, 0)
const StickerScene := preload("res://scenes/icon_sticker.tscn")

var corner_rect := Rect2()   ## the area whose bottom-right corner the toast sits in (global; main.gd: the stage)
var shown_count := 0         ## toasts shown so far (tests)
var _queue: Array[Dictionary] = []
var _showing: Dictionary = {}
var _left := 0.0
var _gap := 0.0

var _card: PanelContainer
var _accent: ColorRect
var _icon: IconSticker
var _caption: Label
var _title: Label
var _text: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.theme_type_variation = &"Toast"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(WIDTH, 0)
	_card.visible = false
	add_child(_card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)
	_accent = ColorRect.new()  # a strip in the category colour, like the Banner's accent lines
	_accent.custom_minimum_size = Vector2(3, 0)
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_accent)
	_icon = StickerScene.instantiate()
	_icon.custom_minimum_size = Vector2(44, 44)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	var text := VBoxContainer.new()
	text.theme_type_variation = &"TightBox"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	_caption = _label(&"FaintLabel")
	text.add_child(_caption)
	_title = _label(&"CardTitle")
	text.add_child(_title)
	_text = _label(&"CardLine")
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(TEXT_WIDTH, 0)  # a known width, so the card knows its height before layout
	text.add_child(_text)


## Queues a toast: {kind (career|achievement|drop), caption ("ACHIEVEMENT"), title, text, icon: Texture2D, category,
## name (a merged toast's "and 2 more: <name>", default the title)}. Returns false if it merged into one waiting.
func push(view: Dictionary) -> bool:
	var kind := String(view.get("kind", ""))
	for waiting: Dictionary in _queue:
		if waiting["kind"] == kind:
			waiting["more"] = int(waiting.get("more", 0)) + 1
			waiting["latest"] = view.get("name", view.get("title", ""))
			return false
	_queue.append(view.duplicate())
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	return true


## Time passing: the toast up counts down, then the next one shows.
func advance(delta: float) -> void:
	if not _showing.is_empty():
		_left -= delta
		if _left <= 0.0:
			_hide()
		return
	_gap -= delta
	if _gap <= 0.0 and not _queue.is_empty():
		_show(_queue.pop_front())


func clear() -> void:
	_queue.clear()
	_gap = 0.0
	_showing = {}
	if _card != null:
		_card.visible = false


func is_showing() -> bool:
	return not _showing.is_empty()


## The toast up now ({} if none), as pushed (plus "more"/"latest" if others merged into it).
func get_showing() -> Dictionary:
	return _showing


func get_waiting() -> int:
	return _queue.size()


## The labels' texts of the toast up now (tests): [caption, title, text].
func get_texts() -> Array[String]:
	return [_caption.text, _title.text, _text.text]


func _show(view: Dictionary) -> void:
	_showing = view
	_left = HOLD
	shown_count += 1
	_caption.text = String(view.get("caption", ""))
	_caption.visible = _caption.text != ""
	_title.text = String(view.get("title", ""))
	_title.visible = _title.text != ""
	var text := String(view.get("text", ""))
	if int(view.get("more", 0)) > 0:
		text = "and %d more, latest: %s" % [int(view["more"]), view.get("latest", "")]
	_text.text = text
	_text.visible = text != ""
	_icon.texture = view.get("icon")
	_icon.category = StringName(view.get("category", &"trophies"))
	_accent.color = IconSticker.colour_of(self, _icon.category)
	_card.modulate.a = 1.0
	_card.visible = true
	_card.reset_size()
	_place()
	UiFx.slide_in(_card, SLIDE)


func _hide() -> void:
	_showing = {}
	_gap = GAP
	if UiFx.reduce_motion:
		_card.visible = false
		return
	var tween := _card.create_tween()
	tween.tween_property(_card, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void:
		if _showing.is_empty():  # (a new toast may have started meanwhile)
			_card.visible = false)


## Bottom-right of corner_rect (or of this control while it has none).
func _place() -> void:
	var area := corner_rect if corner_rect.size.x > 0.0 else get_global_rect()
	var local := get_global_transform().affine_inverse() * (area.end - MARGIN)
	_card.position = local - _card.size  # (reset_size() made it its minimum size)


func _label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
