class_name CubeView
extends Control
## Draws one face of a Rubik's cube.
## Call scramble_step() for each visible move and show_solved() when a solve completes.
## (A 3D Three.js-style cube can replace this later; keep the same two methods.)

const COLORS := [
	Color("#f4f4f4"),  # white
	Color("#ffd500"),  # yellow
	Color("#c41e3a"),  # red
	Color("#ff5800"),  # orange
	Color("#0051ba"),  # blue
	Color("#009e60"),  # green
]
const BODY_COLOR := Color("#14161b")
const SOLVED_HOLD := 0.35
const PUNCH_DECAY := 7.0

var _stickers: Array[int] = []
var _solved_timer := 0.0
var _punch := 0.0
var _body_style := StyleBoxFlat.new()
var _sticker_style := StyleBoxFlat.new()


func _ready() -> void:
	_stickers.resize(9)
	_randomize_all()
	_body_style.bg_color = BODY_COLOR
	_body_style.set_corner_radius_all(18)
	_sticker_style.set_corner_radius_all(8)


func scramble_step() -> void:
	_punch = 1.0
	if _solved_timer > 0.0:
		return
	# Recolor one row or column, like a single face turn.
	var line := randi() % 3
	var horizontal := randf() < 0.5
	for i in 3:
		var index := line * 3 + i if horizontal else i * 3 + line
		_stickers[index] = randi() % COLORS.size()
	queue_redraw()


func show_solved() -> void:
	var center := _stickers[4]
	for i in 9:
		_stickers[i] = center
	_solved_timer = SOLVED_HOLD
	_punch = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if _solved_timer > 0.0:
		_solved_timer -= delta
		if _solved_timer <= 0.0:
			_randomize_all()
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - delta * PUNCH_DECAY)
		queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y) * (1.0 - 0.05 * _punch)
	var origin := (size - Vector2(side, side)) / 2.0
	_body_style.draw(get_canvas_item(), Rect2(origin, Vector2(side, side)))

	var pad := side * 0.05
	var cell := (side - pad * 2.0) / 3.0
	var gap := cell * 0.06
	for row in 3:
		for col in 3:
			var top_left := origin + Vector2(pad + col * cell + gap, pad + row * cell + gap)
			_sticker_style.bg_color = COLORS[_stickers[row * 3 + col]]
			_sticker_style.draw(get_canvas_item(), Rect2(top_left, Vector2(cell - gap * 2.0, cell - gap * 2.0)))


func _randomize_all() -> void:
	for i in 9:
		_stickers[i] = randi() % COLORS.size()
	queue_redraw()
