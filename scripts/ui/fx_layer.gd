class_name FxLayer
extends Control
## Floating "+N" texts and solve bursts drawn over the main screen (task 2.4). Display only.
## Labels are pooled: never more than POOL_SIZE on screen; when all are busy, the oldest is reused.
## The burst is one CPUParticles2D restarted in place. Reduce motion turns `particles_enabled` off (the floating
## numbers stay: they carry information).

const POOL_SIZE := 20
const RISE := 70.0        ## pixels a text floats up over its lifetime
const LIFETIME := 0.9
const JITTER := 14.0      ## random sideways offset, so rapid taps don't stack exactly

@onready var _burst: CPUParticles2D = %Burst

var enabled := true
var particles_enabled := true
var _labels: Array[Label] = []
var _ages := PackedFloat32Array()
var _lifetimes := PackedFloat32Array()
var _starts: Array[Vector2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in POOL_SIZE:
		var label := Label.new()
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_labels.append(label)
		_ages.append(0.0)
		_lifetimes.append(LIFETIME)
		_starts.append(Vector2.ZERO)


## Shows `text` centred on `at` (global position), floating up and fading. `variation` is a theme Label variation.
func pop(text: String, at: Vector2, variation: StringName = &"PopTap", lifetime: float = LIFETIME) -> void:
	if not enabled:
		return
	var index := _free_slot()
	var label := _labels[index]
	label.text = text
	label.theme_type_variation = variation
	label.size = label.get_combined_minimum_size()
	var local := get_global_transform().affine_inverse() * at
	_starts[index] = local - label.size / 2.0 + Vector2(randf_range(-JITTER, JITTER), 0.0)
	label.position = _starts[index]
	label.modulate.a = 1.0
	label.visible = true
	_ages[index] = 0.0
	_lifetimes[index] = lifetime


## A one-shot burst of cube-coloured squares at `at` (global position).
func burst(at: Vector2) -> void:
	if not enabled or not particles_enabled:
		return
	_burst.position = get_global_transform().affine_inverse() * at
	_burst.restart()


## How many floating texts are on screen right now.
func active_count() -> int:
	var count := 0
	for label in _labels:
		if label.visible:
			count += 1
	return count


func _process(delta: float) -> void:
	for i in _labels.size():
		var label := _labels[i]
		if not label.visible:
			continue
		_ages[i] += delta
		var t := _ages[i] / _lifetimes[i]
		if t >= 1.0:
			label.visible = false
			continue
		label.position = _starts[i] + Vector2(0.0, -RISE * (1.0 - pow(1.0 - t, 2.0)))
		label.modulate.a = 1.0 - t * t


func _free_slot() -> int:
	var oldest := 0
	for i in _labels.size():
		if not _labels[i].visible:
			return i
		if _ages[i] > _ages[oldest]:
			oldest = i
	return oldest
