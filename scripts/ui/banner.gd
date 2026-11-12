class_name Banner
extends Control
## Big moments (task V.7): a full-width banner for "New puzzle unlocked", "New helper", "Method learned" and a
## championship won: the item's icon sticker, a title in the display font and a line under it, with a burst of confetti
## in the six sticker colours and a light sweeping over the stage. Display only: main.gd pushes moments in, and calls
## advance(delta) every frame (tests drive it with fake time).
## One at a time, in order. So fast play never spams: a moment of a kind already waiting merges into it ("and 2 more"),
## at most MAX_QUEUE wait (the oldest ordinary one goes first), and a kind shown recently waits out its cooldown.
## clear() empties it all (a championship or a reset starts a new story). Reduce motion (UiFx.reduce_motion): the banner still shows (it carries
## information) but without sliding, confetti or the sweep.

const HOLD := 2.6            ## seconds a banner stays up
const GAP := 0.35            ## seconds between two banners
const MAX_QUEUE := 3
const COOLDOWN := 8.0        ## seconds before a kind may show again (championships: never wait)
const SWEEP_TIME := 0.7
const SLIDE := Vector2(0, -36)

@onready var _band: Control = %Band
@onready var _strip: Control = %Strip
@onready var _icon: IconSticker = %Icon
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _accent_top: ColorRect = %AccentTop
@onready var _accent_bottom: ColorRect = %AccentBottom
@onready var _confetti: CPUParticles2D = %Confetti
@onready var _sweep: TextureRect = %Sweep

var stage_rect := Rect2()     ## where the light sweeps (main.gd: the puzzle view's global rect)
var shown_count := 0          ## banners shown so far (tests)
var pushed_count := 0         ## moments pushed so far (tests)
var _queue: Array[Dictionary] = []
var _showing: Dictionary = {}
var _left := 0.0              ## of the one showing
var _gap := 0.0
var _cooldowns: Dictionary = {}  ## kind -> seconds left
var _band_home := Vector2.ZERO


func _ready() -> void:
	_band_home = _band.position
	_confetti.color_initial_ramp = _sticker_ramp()
	var gradient := Gradient.new()  # the sweep: a soft bright stripe
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 1.0])  # soft on both sides, light (additive) in the middle
	gradient.colors = PackedColorArray([Color(1, 0.95, 0.85, 0), Color(1, 0.95, 0.85, 0.04), Color(1, 0.95, 0.85, 0.16),
			Color(1, 0.95, 0.85, 0.04), Color(1, 0.95, 0.85, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 4
	_sweep.texture = texture
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sweep.material = additive


## Queues a moment: {kind (puzzle|helper|method|championship), title, subtitle, icon: Texture2D, category}.
## Returns false if it merged into one already waiting.
##   name: a short name for a merged banner's "and 2 more: Cubing Club" (default: the title).
func push(view: Dictionary) -> bool:
	pushed_count += 1
	var kind := String(view.get("kind", ""))
	for waiting: Dictionary in _queue:
		if waiting["kind"] == kind and kind != "championship":
			waiting["more"] = int(waiting.get("more", 0)) + 1
			waiting["latest"] = view.get("name", view.get("title", ""))
			return false
	_queue.append(view.duplicate())
	while _queue.size() > MAX_QUEUE:
		for i in _queue.size():
			if _queue[i]["kind"] != "championship":
				_queue.remove_at(i)
				break
		if _queue.size() > MAX_QUEUE:  # all championships: keep the newest few
			_queue.pop_front()
	return true


## Time passing: the banner up counts down, then the next waiting one (whose kind isn't cooling down) shows.
func advance(delta: float) -> void:
	for kind: String in _cooldowns.keys():
		_cooldowns[kind] = float(_cooldowns[kind]) - delta
		if float(_cooldowns[kind]) <= 0.0:
			_cooldowns.erase(kind)
	if not _showing.is_empty():
		_left -= delta
		if _left <= 0.0:
			_hide()
		return
	_gap -= delta
	if _gap > 0.0:
		return
	for i in _queue.size():
		var kind := String(_queue[i]["kind"])
		if kind == "championship" or not _cooldowns.has(kind):
			_show(_queue.pop_at(i))
			return


## Drops the banner up now, every waiting one and the cooldowns.
func clear() -> void:
	_queue.clear()
	_cooldowns.clear()
	_gap = 0.0
	if not _showing.is_empty():
		_showing = {}
		_band.visible = false


func is_showing() -> bool:
	return not _showing.is_empty()


## The banner up now ({} if none) and how many wait (tests and screenshots).
func get_showing() -> Dictionary:
	return _showing


func get_waiting() -> int:
	return _queue.size()


func _show(view: Dictionary) -> void:
	_showing = view
	_left = HOLD
	shown_count += 1
	var kind := String(view["kind"])
	if kind != "championship":
		_cooldowns[kind] = COOLDOWN
	_title.text = String(view.get("title", ""))
	var subtitle := String(view.get("subtitle", ""))
	if int(view.get("more", 0)) > 0:  # merged: the first one's title, then how many more came
		subtitle = "and %d more: %s" % [int(view["more"]), view.get("latest", "")]
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""
	_icon.texture = view.get("icon")
	_icon.category = StringName(view.get("category", &"puzzles"))
	var accent := IconSticker.colour_of(self, _icon.category)
	_accent_top.color = accent
	_accent_bottom.color = accent
	_band.position = _band_home
	UiFx.slide_in(_band, SLIDE)
	if UiFx.reduce_motion:
		return
	_confetti.position = Vector2(size.x / 2.0, _band_home.y)
	_confetti.emission_rect_extents = Vector2(size.x / 2.0, 6.0)
	_confetti.amount = 150 if kind == "championship" else 90
	_confetti.restart()
	_sweep_stage()


func _hide() -> void:
	_showing = {}
	_gap = GAP
	if UiFx.reduce_motion:
		_band.visible = false
		return
	var tween := _band.create_tween()
	tween.tween_property(_band, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void:
		if _showing.is_empty():  # (a new banner may have started meanwhile)
			_band.visible = false)


## A bright stripe slides across the stage once.
func _sweep_stage() -> void:
	if stage_rect.size.x <= 0.0:
		return
	var local := get_global_transform().affine_inverse()
	var start := local * stage_rect.position
	_sweep.size = Vector2(220.0, stage_rect.size.y)
	_sweep.position = start  # stays on the stage: from its left edge to its right one
	_sweep.visible = true
	_sweep.modulate.a = 1.0
	var tween := _sweep.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_sweep, "position:x", start.x + stage_rect.size.x - _sweep.size.x, SWEEP_TIME)
	tween.tween_callback(func() -> void: _sweep.visible = false)


## The six sticker colours of a real cube (the 3D cube's own, PuzzleShapes.CUBE_COLORS), one each, for the confetti.
func _sticker_ramp() -> Gradient:
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var colours := PackedColorArray()
	var offsets := PackedFloat32Array()
	var stickers: Array[Color] = PuzzleShapes.CUBE_COLORS
	for i in stickers.size():
		colours.append(stickers[i])
		offsets.append(float(i) / stickers.size())
	ramp.offsets = offsets
	ramp.colors = colours
	return ramp
