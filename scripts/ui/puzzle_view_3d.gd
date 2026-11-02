class_name PuzzleView3D
extends SubViewportContainer
## The 3D puzzle on screen, drawn from a TwistyModel.
## Same API as the old 2D CubeView: scramble_step() for each visible move, show_solved() on a solve,
## plus set_puzzle(id) ("2x2" ... "7x7"). Clicking it emits `tapped`; main.gd turns that into Game.tap().
##
## All piece bodies are one MultiMesh and all stickers another, so even a 7×7 is two draw calls.
## Scene: Viewport > Puzzle (tilts the top towards the camera, 28°) > Turntable (turns F/R into view, −38°)
## > Bodies + Stickers. Rotate Turntable for spins and drags; Puzzle is scaled for the tap "punch".
## Visual state only: nothing here affects game numbers.

signal tapped

const DEFAULT_PUZZLE := "3x3"
const BODY_COLOR := Color("#14161b")
const CUBIE_HALF := 0.47        ## half a cubie's edge (cubies are 1 apart, so this leaves a small gap)
const CUBIE_RADIUS := 0.1
const STICKER_HALF := 0.4
const STICKER_RADIUS := 0.1
const STICKER_LIFT := 0.004     ## keeps stickers just above the body surface
const SOLVED_HOLD := 0.35       ## seconds a solved puzzle stays solved before moves scramble it again
const PUNCH_DECAY := 7.0
const PUNCH_SCALE := 0.03
const START_MOVES_PER_SIZE := 4 ## a new puzzle starts with size × this many scramble moves
const CAMERA_FOV := 30.0
const FRAME_DISTANCE := 0.92    ## 1.0 = the bounding sphere just touches the view edges; smaller zooms in
const TAP_SLOP := 6.0           ## pixels the mouse may move between press and release and still tap

@onready var _camera: Camera3D = %Camera
@onready var _puzzle: Node3D = %Puzzle
@onready var _bodies: MultiMeshInstance3D = %Bodies
@onready var _stickers: MultiMeshInstance3D = %Stickers

var model: TwistyModel
var puzzle_id := ""

var _rng := RandomNumberGenerator.new()
var _last_move := {}
var _solved_timer := 0.0
var _punch := 0.0
var _sticker_piece := PackedInt32Array()       ## sticker instance -> piece index
var _sticker_local: Array[Transform3D] = []    ## sticker instance -> transform in its piece's home frame
var _body_mesh: ArrayMesh
var _sticker_mesh: ArrayMesh
var _press_position := Vector2.ZERO
var _pressing := false


func _ready() -> void:
	_rng.seed = randi()  # follows the global seed, so screenshots are repeatable
	_body_mesh = PuzzleMeshes.rounded_box(CUBIE_HALF, CUBIE_RADIUS)
	_body_mesh.surface_set_material(0, _make_body_material())
	_sticker_mesh = PuzzleMeshes.rounded_rect(STICKER_HALF, STICKER_RADIUS)
	_sticker_mesh.surface_set_material(0, _make_sticker_material())
	_camera.fov = CAMERA_FOV
	resized.connect(_frame_camera)
	set_puzzle(DEFAULT_PUZZLE)


func _process(delta: float) -> void:
	if _solved_timer > 0.0:
		_solved_timer -= delta
	if _punch > 0.0:
		_punch = maxf(0.0, _punch - delta * PUNCH_DECAY)
		_puzzle.scale = Vector3.ONE * (1.0 - PUNCH_SCALE * _punch)


# --- Public API ----------------------------------------------------------------

## Shows another puzzle ("2x2" ... "7x7"). It starts part-scrambled, like a solve in progress.
func set_puzzle(id: String) -> void:
	var new_model := PuzzleShapes.from_id(id)
	if new_model == null:
		push_warning("Unknown puzzle '%s'" % id)
		return
	model = new_model
	puzzle_id = id
	_build_instances()
	_frame_camera()
	var moves := model.scramble(model.size * START_MOVES_PER_SIZE, _rng)
	_last_move = moves.back() if not moves.is_empty() else {}
	_update_transforms()


## One visible move: a random scramble-style turn.
func scramble_step() -> void:
	_punch = 1.0
	if model == null or _solved_timer > 0.0:
		return
	_last_move = model.random_move(_rng, _last_move)
	model.apply(_last_move)
	_update_transforms()


## A solve just completed: show the puzzle solved for a moment.
func show_solved() -> void:
	if model == null:
		return
	model.reset()
	_last_move = {}
	_solved_timer = SOLVED_HOLD
	_punch = 1.0
	_update_transforms()


# --- Input -----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_pressing = true
		_press_position = button.position
	elif _pressing:
		_pressing = false
		if button.position.distance_to(_press_position) <= TAP_SLOP:
			tapped.emit()
	accept_event()


# --- Building and drawing --------------------------------------------------------

func _build_instances() -> void:
	var piece_count := model.piece_count()
	var bodies := MultiMesh.new()
	bodies.transform_format = MultiMesh.TRANSFORM_3D
	bodies.mesh = _body_mesh
	bodies.instance_count = piece_count
	_bodies.multimesh = bodies

	_sticker_piece.clear()
	_sticker_local.clear()
	var colors: Array[Color] = []
	for piece in piece_count:
		var normals := model.sticker_normals[piece]
		for s in normals.size():
			var normal := normals[s]
			var up := Vector3.UP if absf(normal.y) < 0.9 else Vector3.BACK
			# Sticker meshes face +Z; looking_at points -Z at the target, so look away from the normal.
			var local := Transform3D(Basis.looking_at(-normal, up), normal * (CUBIE_HALF + STICKER_LIFT))
			_sticker_piece.append(piece)
			_sticker_local.append(local)
			colors.append(PuzzleShapes.CUBE_COLORS[model.sticker_colors[piece][s]])
	var stickers := MultiMesh.new()
	stickers.transform_format = MultiMesh.TRANSFORM_3D
	stickers.use_colors = true
	stickers.mesh = _sticker_mesh
	stickers.instance_count = _sticker_piece.size()
	for i in colors.size():
		stickers.set_instance_color(i, colors[i])
	_stickers.multimesh = stickers


func _update_transforms() -> void:
	var piece_transforms: Array[Transform3D] = []
	for piece in model.piece_count():
		var t := Transform3D(model.piece_basis(piece), model.piece_position(piece))
		piece_transforms.append(t)
		_bodies.multimesh.set_instance_transform(piece, t)
	for i in _sticker_piece.size():
		_stickers.multimesh.set_instance_transform(i, piece_transforms[_sticker_piece[i]] * _sticker_local[i])


## Moves the camera back far enough for the whole puzzle to fit, whatever its size.
func _frame_camera() -> void:
	if model == null or not is_node_ready():
		return
	var radius := sqrt(3.0) * model.size / 2.0  # bounding sphere of an n×n×n cube
	var half_fov := deg_to_rad(_camera.fov) / 2.0
	if size.x > 0.0 and size.y > 0.0 and size.x < size.y:
		half_fov = atan(tan(half_fov) * size.x / size.y)  # narrow views are limited by their width
	_camera.position = Vector3(0.0, 0.0, radius * FRAME_DISTANCE / sin(half_fov))
	_camera.near = 0.1
	_camera.far = _camera.position.z + radius * 2.0


func _make_body_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = BODY_COLOR
	material.roughness = 0.45
	return material


func _make_sticker_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true  # MultiMesh instance colours arrive as vertex colour
	material.vertex_color_is_srgb = true
	material.roughness = 0.3
	return material
