class_name UiFx
extends RefCounted
## The motion kit (task V.6): small static helpers that animate UI nodes with tweens. No game rules, display only.
## Every helper honours Reduce motion: with `UiFx.reduce_motion` on it puts the node in its end state at once and
## returns null (no tween). Otherwise it returns the Tween it started (callers may kill or await it).
## main.gd sets `reduce_motion` and `backdrop_blur` (Graphics High) from Settings.

const OPEN_TIME := 0.18      ## a panel opening (scale + fade); closing takes CLOSE_TIME
const CLOSE_TIME := 0.12
const OPEN_SCALE := 0.94     ## a panel grows from this to 1 as it opens
const POP_SCALE := 1.08      ## pop(): how far it swells
const POP_TIME := 0.22
const SQUASH := Vector2(1.04, 0.9)  ## squash(): a pressed card's shape at the bottom of the press
const SQUASH_TIME := 0.2
const SHAKE_TIME := 0.3
const ROLL_TIME := 0.35
const SHEEN_TIME := 0.5
const FLY_TIME := 0.45
const BLUR_SHADER := preload("res://scripts/ui/shaders/backdrop_blur.gdshader")

static var reduce_motion := false
static var _dims: Array[WeakRef] = []  ## panel backdrops open_panel() dressed (blur on), kept for backdrop_blur changes
## Graphics High: open panels blur what's behind them; Low: a plain dim. Changing it re-dresses every panel backdrop
## seen so far, also one that is open now (switching Graphics in the open Settings panel).
static var backdrop_blur := true:
	set(value):
		backdrop_blur = value
		var alive: Array[WeakRef] = []
		for ref: WeakRef in _dims:
			var dim := ref.get_ref() as ColorRect
			if dim != null:
				dim.material = _blur() if value else null
				alive.append(ref)
		_dims = alive

static var _blur_material: ShaderMaterial


## Fades and grows `node` in from `from_scale` (around its centre).
static func pop_in(node: Control, duration: float = OPEN_TIME, from_scale: float = OPEN_SCALE) -> Tween:
	node.visible = true
	if reduce_motion:
		node.scale = Vector2.ONE
		node.modulate.a = 1.0
		return null
	_centre_pivot(node)
	node.scale = Vector2.ONE * from_scale
	node.modulate.a = 0.0
	var tween := node.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Explicit starts: a parent Container lays the node out (and resets its scale to 1) as it becomes visible, before
	# the tween's first step would read its start values.
	tween.tween_property(node, "scale", Vector2.ONE, duration).from(Vector2.ONE * from_scale)
	tween.tween_property(node, "modulate:a", 1.0, duration * 0.8).from(0.0).set_trans(Tween.TRANS_QUAD)
	return tween


## Swells `node` once and settles back (a newly affordable card).
static func pop(node: Control, amount: float = POP_SCALE, duration: float = POP_TIME) -> Tween:
	if reduce_motion:
		node.scale = Vector2.ONE
		return null
	_centre_pivot(node)
	var tween := node.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector2.ONE * amount, duration * 0.4)
	tween.tween_property(node, "scale", Vector2.ONE, duration * 0.6).set_ease(Tween.EASE_IN_OUT)
	return tween


## A press you can feel: `node` squashes (wider, shorter) and springs back (buying a card).
static func squash(node: Control, shape: Vector2 = SQUASH, duration: float = SQUASH_TIME) -> Tween:
	if reduce_motion:
		node.scale = Vector2.ONE
		return null
	_centre_pivot(node)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", shape, duration * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector2.ONE, duration * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween


## Slides `node` in from `offset` (pixels away from where it ends) while fading in.
static func slide_in(node: Control, offset: Vector2, duration: float = OPEN_TIME) -> Tween:
	var end := node.position
	node.visible = true
	if reduce_motion:
		node.modulate.a = 1.0
		return null
	node.position = end + offset
	node.modulate.a = 0.0
	var tween := node.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position", end, duration)
	tween.tween_property(node, "modulate:a", 1.0, duration)
	return tween


## Shakes `node` sideways ("no": can't afford, wrong key). It ends where it started.
static func shake(node: Control, strength: float = 6.0, duration: float = SHAKE_TIME) -> Tween:
	if reduce_motion:
		return null
	var home := node.position
	var tween := node.create_tween()
	var steps := 6
	for i in steps:
		var side := strength * (1.0 - float(i) / steps) * (1.0 if i % 2 == 0 else -1.0)
		tween.tween_property(node, "position:x", home.x + side, duration / steps)
	tween.tween_property(node, "position", home, 0.02)
	return tween


## Rolls a number shown by `label` from `from` to `to`, formatting each step with `format` (e.g. Num.format).
static func roll_number(label: Label, from: float, to: float, format: Callable, duration: float = ROLL_TIME) -> Tween:
	if reduce_motion or is_equal_approx(from, to):
		label.text = format.call(to)
		return null
	var tween := label.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(value: float) -> void: label.text = format.call(value), from, to, duration)
	return tween


## A light passing over a bar (a goal reached, a bar filled): it brightens and fades back.
static func sheen(node: CanvasItem, duration: float = SHEEN_TIME) -> Tween:
	if reduce_motion:
		node.self_modulate = Color.WHITE
		return null
	node.self_modulate = Color(1.6, 1.6, 1.6)
	var tween := node.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "self_modulate", Color.WHITE, duration)
	return tween


## A slow endless glow on `node`'s alpha between `low` and 1. Kill the tween to stop it. Reduce motion: steady.
static func breathe(node: CanvasItem, low: float = 0.7, period: float = 2.6) -> Tween:
	node.modulate.a = 1.0
	if reduce_motion:
		return null
	var tween := node.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "modulate:a", low, period / 2.0)
	tween.tween_property(node, "modulate:a", 1.0, period / 2.0)
	return tween


## Opens an overlay panel: `root` shows, its `dim` (the darkened, on High blurred backdrop) fades in and its
## `content` (the panel itself) grows and fades in. `blur` false keeps the dim's own look (an opaque backdrop).
static func open_panel(root: Control, dim: CanvasItem, content: Control, blur: bool = true) -> Tween:
	_kill(root)
	root.set_meta(&"ui_fx_closing", false)
	root.visible = true
	if blur and dim is ColorRect:
		(dim as ColorRect).material = _blur() if backdrop_blur else null
		if not _dims.any(func(ref: WeakRef) -> bool: return ref.get_ref() == dim):
			_dims.append(weakref(dim))
	if reduce_motion:
		dim.modulate.a = 1.0
		content.scale = Vector2.ONE
		content.modulate.a = 1.0
		return null
	dim.modulate.a = 0.0
	var tween := pop_in(content)
	tween.tween_property(dim, "modulate:a", 1.0, OPEN_TIME).set_trans(Tween.TRANS_QUAD)  # no overshoot (the panel's BACK ease)
	root.set_meta(&"ui_fx_tween", tween)
	return tween


## Closes an overlay panel the same way backwards, then hides `root` and calls `done` (if valid).
static func close_panel(root: Control, dim: CanvasItem, content: Control, done: Callable = Callable()) -> Tween:
	_kill(root)
	root.set_meta(&"ui_fx_closing", false)
	if reduce_motion or not root.visible:
		root.visible = false
		if done.is_valid():
			done.call()
		return null
	_centre_pivot(content)
	var tween := root.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(content, "scale", Vector2.ONE * OPEN_SCALE, CLOSE_TIME)
	tween.tween_property(content, "modulate:a", 0.0, CLOSE_TIME)
	tween.tween_property(dim, "modulate:a", 0.0, CLOSE_TIME)
	root.set_meta(&"ui_fx_closing", true)
	tween.chain().tween_callback(func() -> void:
		root.set_meta(&"ui_fx_closing", false)
		root.visible = false
		content.scale = Vector2.ONE
		content.modulate.a = 1.0
		dim.modulate.a = 1.0
		if done.is_valid():
			done.call())
	root.set_meta(&"ui_fx_tween", tween)
	return tween


## A "+1" (any text) that flies from `from` to `to` (global positions) on `layer` and fades out on arrival.
## Returns the label's tween; the label frees itself. Reduce motion: nothing flies (returns null).
static func fly_text(layer: Control, text: String, from: Vector2, to: Vector2, variation: StringName = &"PopTap",
		duration: float = FLY_TIME) -> Tween:
	if reduce_motion:
		return null
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	label.size = label.get_combined_minimum_size()
	var to_local := layer.get_global_transform().affine_inverse()
	label.position = to_local * from - label.size / 2.0
	var tween := label.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(label, "position", to_local * to - label.size / 2.0, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration * 0.35).set_delay(duration * 0.65)
	tween.chain().tween_callback(label.queue_free)
	return tween


## True while close_panel() is animating `root` away (it's still visible, but already closed for the game).
static func is_closing(root: Control) -> bool:
	return bool(root.get_meta(&"ui_fx_closing", false))


static func _centre_pivot(node: Control) -> void:
	node.pivot_offset = node.size / 2.0


static func _kill(root: Control) -> void:
	if not root.has_meta(&"ui_fx_tween"):  # (get_meta with a null default still errors on a missing key)
		return
	var running: Variant = root.get_meta(&"ui_fx_tween")
	if running is Tween and (running as Tween).is_valid():
		(running as Tween).kill()
	root.remove_meta(&"ui_fx_tween")


static func _blur() -> ShaderMaterial:
	if _blur_material == null:
		_blur_material = ShaderMaterial.new()
		_blur_material.shader = BLUR_SHADER
	return _blur_material
