class_name PuzzleView3D
extends SubViewportContainer
## The 3D puzzle on screen, drawn from a TwistyModel.
## API: scramble_step() for each visible move, show_solved() on a solve, set_puzzle(id) ("2x2" ... "7x7"),
## set_speed(moves_per_second) and set_graphics("high" | "low").
## Clicking it emits `tapped`; main.gd turns that into Game.tap().
##
## All piece bodies are one MultiMesh and all stickers another, so even a 7×7 is two draw calls.
## Scene: Viewport > Puzzle (tilts the top towards the camera, 28°) > Turntable (turns F/R into view, −38°)
## > Bodies + Stickers. Puzzle is scaled for the punch/bounce; Turntable wobbles in speed mode.
##
## Turns: scramble_step() queues a move. The front of the queue animates (the turning layer's transforms are
## rotated around the face axis) and is applied to the model when it finishes, so the model always matches
## what's on screen once the animation ends. Turns get shorter as the queue grows; past MAX_QUEUE the backlog
## is applied instantly. Above SPEED_MODE_ON moves/s (set_speed) moves snap without animation and the
## puzzle wobbles. show_solved() plays the recent moves backwards, then flashes and bounces.
## Stage (task 1.4): a radial backdrop (child of the camera) and a soft contact shadow under the puzzle, both
## unshaded quads with tiny shaders in scripts/ui/shaders/. Dragging turns the view and it springs back; it also
## sways gently when idle. The last few moves are kept for a ticker (ticker_text()).
## Graphics (task 1.5): "high" = MSAA 4×, rounded pieces, glow and shadow; "low" = no MSAA, bevelled pieces
## (about 5× fewer triangles), no glow or shadow. main.gd applies the player's choice from Settings.
## Reduce motion (set_reduce_motion) turns off sway, squash, bounce and the speed-mode wobble.
## Stage v2 (task V.3): the puzzle sits on a cubing mat (Floor > Mat + MatInset, rounded slabs made in code; the
## contact shadow lies on it). Floor tilts with the puzzle (resting tilt, drag, sway, wobble) but doesn't take its
## squash, bounce or drop-in, and Turntable's spin happens above it. The camera frames puzzle and mat together. A warm key light, a cool rim light from behind (High only) so the silhouette pops, and a warm glow.
## `floor_enabled = false` hides the mat (the small puzzle chips).
## Manual mode (Solve Station, task S.1): show_state(moves) shows an exact state (solved + those moves), turn(move)
## animates one given move, turn_time sets how fast (pros turn at 5-10 TPS, so the station uses a short time) and
## flash() celebrates without resetting the puzzle.
## Visual state only: nothing here affects game numbers.

signal tapped(at: Vector2)  ## global position of the click
signal drag_turned(move: Dictionary)  ## with drag_turns on: a drag across the puzzle asked for this layer turn
signal golden_clicked  ## a click landed on the glowing golden sticker (S.6), instead of a tap

const DEFAULT_PUZZLE := "3x3"
const BODY_COLOR := Color("#14161b")
const CUBIE_HALF := 0.47        ## half a cubie's edge (cubies are 1 apart, so this leaves a small gap)
const CUBIE_RADIUS := 0.1
const STICKER_HALF := 0.4
const STICKER_RADIUS := 0.1
const STICKER_LIFT := 0.004     ## keeps stickers just above the body surface
const START_MOVES_PER_SIZE := 4 ## a new puzzle starts with size × this many scramble moves
const CAMERA_FOV := 30.0
const FRAME_DISTANCE := 1.0    ## 1.0 = the bounding sphere just touches the view edges; smaller zooms in
const TAP_SLOP := 6.0           ## pixels the mouse may move between press and release and still tap

const TURN_TIME := 0.12         ## seconds for a quarter turn with an empty queue
const HALF_TURN_FACTOR := 1.4   ## a 180° turn takes this much longer
const QUEUE_SPEEDUP := 0.6      ## each queued move makes turns this much (×) faster: time / (1 + q × this)
const MAX_QUEUE := 6            ## more than this and the backlog is applied instantly
const SPEED_MODE_ON := 12.0     ## moves/s above which turns stop animating
const SPEED_MODE_OFF := 9.0     ## ...and below which they animate again
const WOBBLE_YAW := 0.07        ## radians
const WOBBLE_TILT := 0.04
const REWIND_TIME := 0.9        ## a solve's backwards replay takes at most this long
const REWIND_MAX_MOVES := 30    ## only the last this-many moves are replayed; the rest snap at the end
const SOLVED_HOLD := 0.35       ## seconds the solved puzzle stays solved before moves scramble it again
const FLASH_ENERGY := 0.45
const FLASH_DECAY := 3.5
const FLASH_MIN_INTERVAL := 0.6 ## never flash more often than this (fast solves just pulse)
const PUNCH_SCALE := 0.03
const PUNCH_DECAY := 7.0
const BOUNCE_SCALE := 0.08
const BOUNCE_TIME := 0.45
const SQUASH_DOWN := 0.07       ## a tap squashes the puzzle this much vertically...
const SQUASH_OUT := 0.04        ## ...and bulges it this much sideways
const SQUASH_DECAY := 9.0
const DROP_TIME := 0.55         ## a newly unlocked puzzle drops into place over this long
const DRAG_SPEED := 0.01        ## radians per pixel dragged
const DRAG_MAX_PITCH := 0.7
const DRAG_SPRING := 2.5        ## how fast a released drag returns (higher = faster)
const DRAG_TURN_SLOP := 12.0    ## pixels a drag on the puzzle must travel before it picks its layer turn
const SWAY_YAW := 0.06          ## idle sway, radians
const SWAY_PITCH := 0.025
const TICKER_LENGTH := 8        ## moves shown under the puzzle
const BODY_STEPS_HIGH := 3      ## segments per rounded edge of a piece body
const BODY_STEPS_LOW := 1       ## one segment = a simple bevel
const STAGE_GLOW_COLOR := Color(0.36, 0.29, 0.21)  ## warm, like the desk lamp in the background (V.3)
const MAT_HALF_WIDTH := 1.05    ## the mat, × the puzzle's bounding radius (fits cubes and the Megaminx): half its width...
const MAT_HALF_DEPTH := 1.0     ## ...half its depth (front to back)...
const MAT_THICKNESS := 0.06     ## ...and its thickness, × the puzzle's width
const MAT_GAP := 0.015          ## the puzzle floats this × its width above the mat (no z-fighting at the corners)
const MAT_COLOR := Color("#2b2e38")        ## the mat's rim (its body)...
const MAT_INSET_COLOR := Color("#0c0d11")  ## ...and the darker playing surface set into it, like a speed-cubing mat
const MAT_RIM := 0.07           ## the rim's width, × the puzzle's bounding radius
const MAT_STEPS := 3
const RIM_DIRECTION := Vector3(-0.45, -0.5, 0.75)  ## the rim light shines from behind the puzzle, towards the camera
const RIM_ENERGY := 0.9         ## the rim light's resting energy (the scene's RimLight)...
const RIM_FLASH := 2.6          ## ...the extra a solve burst adds (V.7: the stage light flashes, not only 2D sparks)...
const RIM_FLASH_DECAY := 6.0    ## ...how fast that extra fades, per second...
const RIM_FLASH_INTERVAL := 3.0 ## ...and at most one flash this often (solve bursts come every 0.5 s at speed)
const CAMERA_DROP := 0.1        ## camera sits this × size below centre, so the puzzle rides higher (room for the shadow)
const BackdropShader := preload("res://scripts/ui/shaders/stage_backdrop.gdshader")
const ShadowShader := preload("res://scripts/ui/shaders/contact_shadow.gdshader")

@onready var _viewport: SubViewport = %Viewport
@onready var _camera: Camera3D = %Camera
@onready var _puzzle: Node3D = %Puzzle
@onready var _turntable: Node3D = %Turntable
@onready var _bodies: MultiMeshInstance3D = %Bodies
@onready var _stickers: MultiMeshInstance3D = %Stickers
@onready var _backdrop: MeshInstance3D = %Backdrop
@onready var _shadow: MeshInstance3D = %Shadow
@onready var _floor: Node3D = %Floor
@onready var _mat: MeshInstance3D = %Mat
@onready var _mat_inset: MeshInstance3D = %MatInset
@onready var _rim_light: DirectionalLight3D = %RimLight

var model: TwistyModel
var puzzle_id := ""
var speed_mode := false         ## true while moves snap instead of animating
var recorded_moves: Array[Dictionary] = []  ## when record_moves is on: every move applied, in order (tests)
var record_moves := false
var sway_enabled := true        ## idle sway; "Reduce motion" (3.4) turns it off
var graphics_quality := "high"  ## see set_graphics()
var reduce_motion := false      ## see set_reduce_motion()
var _rim_boost := 0.0           ## rim_flash()'s extra light, fading
var _last_rim_flash := -INF     ## _clock at the last rim flash
## Multiplies FRAME_DISTANCE for this view (< 1 zooms in). The main stage uses a little zoom (V.4): the bounding sphere
## is a safe but loose frame, and what it would crop first is the mat's front edge, which the stage overlay covers anyway.
var frame_zoom := 1.0:
	set(value):
		frame_zoom = value
		_frame_camera()
## Pixels at the top of the view covered by UI (V.4: the goal card sits on the stage): the puzzle is framed into the
## part below it, so nothing hides behind the card.
var frame_inset_top := 0.0:
	set(value):
		if is_equal_approx(value, frame_inset_top):
			return
		frame_inset_top = value
		_frame_camera()
## Pixels at the bottom covered by UI (V.4: the stage chips and ticker strip), like frame_inset_top.
var frame_inset_bottom := 0.0:
	set(value):
		if is_equal_approx(value, frame_inset_bottom):
			return
		frame_inset_bottom = value
		_frame_camera()
## Pixels at the left covered by UI (V.4: the puzzle shelf sits on the stage's left), like frame_inset_top.
var frame_inset_left := 0.0:
	set(value):
		if is_equal_approx(value, frame_inset_left):
			return
		frame_inset_left = value
		_frame_camera()
var floor_enabled := true:      ## the cubing mat under the puzzle (V.3); chips turn it off
	set(value):
		floor_enabled = value
		if is_node_ready():
			_floor.visible = value

var _rng := RandomNumberGenerator.new()
var _last_move := {}             ## last move generated (so the next one uses another face)
var _queue: Array[Dictionary] = []
var _current := {}               ## the move being animated, or {}
var _current_pieces := PackedInt32Array()
var _current_turn := Transform3D.IDENTITY  ## partial rotation drawn for the current turn
var _current_time := 0.0
var _current_duration := TURN_TIME
var _history: Array[Dictionary] = []  ## moves applied since the last solve (newest last, capped)
var _rewinding := false
var _rewind_turn_time := TURN_TIME  ## per-move time during a replay, so it all fits in REWIND_TIME
var _solved_timer := 0.0
var _dirty := false              ## transforms need a full refresh this frame
var _frozen := false             ## set by pose(): stop all animation (screenshots)
var _clock := 0.0
var _wobble := 0.0               ## 0..1, eases in and out with speed mode
var _flash := 0.0
var _last_flash_at := -INF
var _last_speed_solve_at := -INF
var _punch := 0.0
var _bounce := 0.0               ## counts down from BOUNCE_TIME
var _squash := 0.0               ## 1 right after a tap, decays to 0
var _drop := 0.0                 ## counts down from DROP_TIME while a new puzzle drops in
var _base_turntable := Basis.IDENTITY
var _base_puzzle := Basis.IDENTITY

var _piece_transforms: Array[Transform3D] = []  ## baked transform of each piece (matches the model)
var _piece_stickers: Array[PackedInt32Array] = []  ## piece -> its sticker instance indices
var _sticker_piece := PackedInt32Array()        ## sticker instance -> piece index
var _sticker_local: Array[Transform3D] = []     ## sticker instance -> transform in its piece's home frame
var _sticker_drawn: Array[Transform3D] = []     ## sticker instance -> transform last sent to the MultiMesh
var _sticker_colors: Array[Color] = []          ## sticker instance -> colour sent to the MultiMesh
var _body_mesh: ArrayMesh
var _sticker_mesh: ArrayMesh
var _sticker_material: StandardMaterial3D
var _shaped_sticker_material: StandardMaterial3D  ## the Megaminx's copy (culling off); flashes with the other
var _mega_pieces: Array[MeshInstance3D] = []      ## one node per piece for shaped puzzles (see _build_shaped_pieces)
var _press_position := Vector2.ZERO
var _pressing := false
var _dragging := false
var _drag_yaw := 0.0
var _drag_pitch := 0.0
var _ticker := PackedStringArray()  ## last few moves in notation, newest last
var _mat_extent := 0.0             ## the puzzle width the mat mesh was made for
var turn_time := TURN_TIME          ## seconds for a quarter turn with an empty queue (the Solve Station sets it shorter)
var drag_turns := false             ## Solve Station (S.8): a drag that starts on the puzzle turns that layer, not the view
var _press_hit := {}                ## where the press landed on the puzzle ({normal, point} in model space), or {}
var _drag_turn_done := false
var _golden: MeshInstance3D           ## the Golden Scramble sticker (S.6), or null; sits on the top face
var _golden_material: StandardMaterial3D
const GOLDEN_COLOR := Color("#ffb300")


func _ready() -> void:
	_rng.seed = randi()  # follows the global seed, so screenshots are repeatable
	_base_turntable = _turntable.basis
	_base_puzzle = _puzzle.basis
	_body_mesh = _make_body_mesh(BODY_STEPS_HIGH)
	_sticker_material = _make_sticker_material()
	_sticker_mesh = PuzzleMeshes.rounded_rect(STICKER_HALF, STICKER_RADIUS)
	_sticker_mesh.surface_set_material(0, _sticker_material)
	_camera.fov = CAMERA_FOV
	_backdrop.mesh = QuadMesh.new()
	var backdrop_material := ShaderMaterial.new()
	backdrop_material.shader = BackdropShader
	backdrop_material.set_shader_parameter("glow_color", STAGE_GLOW_COLOR)
	_backdrop.material_override = backdrop_material
	_shadow.mesh = PlaneMesh.new()  # lies flat on the mat
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = ShadowShader
	_shadow.material_override = shadow_material
	var mat_material := StandardMaterial3D.new()
	mat_material.albedo_color = MAT_COLOR
	mat_material.roughness = 0.9
	mat_material.metallic_specular = 0.2
	_mat.material_override = mat_material
	var inset_material := mat_material.duplicate() as StandardMaterial3D
	inset_material.albedo_color = MAT_INSET_COLOR
	_mat_inset.material_override = inset_material
	_floor.visible = floor_enabled
	_rim_light.look_at_from_position(Vector3.ZERO, RIM_DIRECTION)
	resized.connect(_frame_camera)
	set_puzzle(DEFAULT_PUZZLE)


func _process(delta: float) -> void:
	if _frozen or model == null:
		return
	_clock += delta
	if _solved_timer > 0.0:
		_solved_timer -= delta
	_advance_turns(delta)
	if _dirty:
		_dirty = false
		_refresh_all()
	_animate_effects(delta)


# --- Public API ----------------------------------------------------------------

## Shows another puzzle ("2x2" ... "7x7"). It starts part-scrambled, like a solve in progress.
func set_puzzle(id: String) -> void:
	var new_model := PuzzleShapes.from_id(id)
	if new_model == null:
		push_warning("Unknown puzzle '%s'" % id)
		return
	model = new_model
	puzzle_id = id
	_queue.clear()
	_current = {}
	_history.clear()
	_ticker.clear()
	_rewinding = false
	_solved_timer = 0.0
	_build_instances()
	_frame_camera()
	if _golden != null:  # keep a glowing golden sticker on the new puzzle (or drop it on a non-cube)
		set_golden(true)
	for i in maxi(model.size * START_MOVES_PER_SIZE, 16):
		_last_move = model.random_move(_rng, _last_move)
		model.apply(_last_move)
		_remember(_last_move)
	_refresh_all()


## "high" or "low" (see the header). Safe to call at any time; the puzzle keeps its state.
func set_graphics(quality: String) -> void:
	if not quality in GameSettings.SPEC["quality"]["choices"]:
		push_warning("Unknown graphics quality '%s'" % quality)
		return
	graphics_quality = quality
	var high := quality == "high"
	_viewport.msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED
	_backdrop.visible = high
	_shadow.visible = high
	_rim_light.visible = high
	_body_mesh = _make_body_mesh(BODY_STEPS_HIGH if high else BODY_STEPS_LOW)
	if _bodies.multimesh != null:
		_bodies.multimesh.mesh = _body_mesh


## Triangles in one piece body at the current quality (tests and the bench use this).
func body_triangles() -> int:
	return _body_mesh.surface_get_array_len(0) / 3


## Tells the view how fast moves are really happening, to pick animated turns or speed mode.
func set_speed(moves_per_second: float) -> void:
	if _frozen:
		return
	if speed_mode and moves_per_second < SPEED_MODE_OFF:
		speed_mode = false
	elif not speed_mode and moves_per_second > SPEED_MODE_ON:
		speed_mode = true
		_flush()


## A tap's squash-and-stretch (bigger than the punch every move gets). Off with Reduce motion.
func squash() -> void:
	if not reduce_motion:
		_squash = 1.0


## A newly unlocked puzzle drops in from above with a small bounce. Skipped with Reduce motion.
func drop_in() -> void:
	if not reduce_motion:
		_drop = DROP_TIME


## A brief flare of the rim light (V.7, with the solve burst), at most every RIM_FLASH_INTERVAL. High only (Low has
## no rim light); not with Reduce motion. Returns true if it flared.
func rim_flash() -> bool:
	if not _rim_light.visible or reduce_motion or _clock - _last_rim_flash < RIM_FLASH_INTERVAL:
		return false
	_last_rim_flash = _clock
	_rim_boost = RIM_FLASH
	return true


## The rim light's energy now (tests).
func get_rim_energy() -> float:
	return _rim_light.light_energy


## Reduce motion: no idle sway, tap squash, solve bounce or speed-mode wobble. Turns still animate (they're the game).
func set_reduce_motion(on: bool) -> void:
	reduce_motion = on
	sway_enabled = not on
	if on:
		_squash = 0.0
		_bounce = 0.0


## One visible move: a random scramble-style turn.
func scramble_step() -> void:
	if _frozen:
		return
	_punch = 1.0
	if model == null or _rewinding or _solved_timer > 0.0:
		return
	_last_move = model.random_move(_rng, _last_move)
	if speed_mode:
		_flush()
		_bake(_last_move)
		return
	if _queue.size() >= MAX_QUEUE:
		_flush()
	_queue.append(_last_move)


## Manual mode: shows the puzzle solved plus `moves`, at once (no animation), with nothing queued.
func show_state(moves: Array) -> void:
	if model == null:
		return
	_queue.clear()
	_current = {}
	_history.clear()
	_ticker.clear()
	_rewinding = false
	_solved_timer = 0.0
	_last_move = {}
	model.reset()
	model.apply_all(moves)
	_dirty = false
	_refresh_all()


## Manual mode: animates one given move (queued behind any turn still in progress).
func turn(move: Dictionary) -> void:
	if model == null or _frozen:
		return
	_punch = 0.5
	if _queue.size() >= MAX_QUEUE:
		_flush()
	_queue.append(move)


## Manual mode: the solved flash and bounce, without resetting the puzzle (it may be solved in another orientation).
func flash() -> void:
	_flash = FLASH_ENERGY
	_last_flash_at = _clock
	if not reduce_motion:
		_bounce = BOUNCE_TIME


## A solve just completed: replay the recent moves backwards, then flash and bounce.
## In speed mode (or if it's already replaying) it just snaps to solved with a small pulse.
func show_solved() -> void:
	if model == null or _rewinding or _frozen:
		return
	if speed_mode:
		# Solves can come every frame here. Show one now and then, and never hold, so the snapping turns stay visible.
		if _clock - _last_speed_solve_at < FLASH_MIN_INTERVAL:
			return
		_last_speed_solve_at = _clock
		_flush()
		_finish_solve()
		_solved_timer = 0.0
		return
	_flush()
	if _history.is_empty():
		_finish_solve()
		return
	_rewinding = true
	var count := mini(_history.size(), REWIND_MAX_MOVES)
	_rewind_turn_time = minf(TURN_TIME, REWIND_TIME / count)
	for i in count:
		_queue.append(model.inverse(_history[_history.size() - 1 - i]))
	_history.clear()


## The last few moves in notation, oldest first, e.g. "R U' Fw2 L" (for the ticker under the puzzle).
func ticker_text() -> String:
	return " ".join(_ticker)


## Number of moves waiting to animate (not counting the one in progress).
func queued_moves() -> int:
	return _queue.size()


## True when nothing is animating or waiting.
func is_idle() -> bool:
	return _current.is_empty() and _queue.is_empty()


## Applies everything queued right away (no animation).
func finish_animations() -> void:
	_flush()
	if _rewinding:
		_rewinding = false
		_finish_solve()
	_refresh_all()


## Freezes a staged moment for screenshots: "turn" (a quarter turn half done) or "solved" (flash at its peak).
func pose(name: String) -> void:
	finish_animations()
	match name:
		"turn":
			_queue.append(model.make_move(model.face_names.find("R"), 1))
			_advance_turns(0.0)
			_current_time = _current_duration * 0.5
			_draw_current()
		"solved":
			_finish_solve()
			_flash = FLASH_ENERGY
			_sticker_material.emission_energy_multiplier = _flash
			if _shaped_sticker_material != null:
				_shaped_sticker_material.emission_energy_multiplier = _flash
			_puzzle.scale = Vector3.ONE * (1.0 + BOUNCE_SCALE * 0.6)
		_:
			push_warning("Unknown pose '%s'" % name)
	_frozen = true


## The colour of every sticker as drawn: [{position, normal, color}] in model space.
## Tests compare this with the model, so view and model can't silently disagree. It reads a CPU-side copy
## of what was sent to the MultiMesh, because the headless (dummy) renderer doesn't keep that data.
## With `unturn`, the half-done current turn is rotated back out, so it should match the model exactly.
func drawn_stickers(unturn: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var turning := {}
	if unturn and not _current.is_empty():
		for piece in _current_pieces:
			turning[piece] = true
	var back := _current_turn.affine_inverse()
	for i in _sticker_drawn.size():
		var t := _sticker_drawn[i]
		if turning.has(_sticker_piece[i]):
			t = back * t
		var normal := t.basis.z.normalized()
		result.append({
			"position": t.origin - normal * (CUBIE_HALF + STICKER_LIFT),
			"normal": normal,
			"color": _sticker_colors[i],
		})
	return result


# --- Turning -------------------------------------------------------------------

func _advance_turns(delta: float) -> void:
	var remaining := delta
	while true:
		if _current.is_empty():
			if _queue.is_empty():
				if _rewinding:
					_rewinding = false
					_finish_solve()
				return
			_start(_queue.pop_front())
		_current_time += remaining
		if _current_time < _current_duration:
			_draw_current()
			return
		remaining = _current_time - _current_duration
		var move := _current
		_current = {}
		_bake(move)
		if remaining <= 0.0:
			return


func _start(move: Dictionary) -> void:
	_current = move
	_current_time = 0.0
	_current_turn = Transform3D.IDENTITY
	if _dirty:  # the previous turn was just applied; start from up-to-date transforms
		_dirty = false
		_refresh_all()
	if _rewinding:
		_current_duration = _rewind_turn_time
	else:
		var duration := turn_time * (HALF_TURN_FACTOR if absi(int(move["turns"])) >= 2 else 1.0)
		_current_duration = duration / (1.0 + _queue.size() * QUEUE_SPEEDUP)
	_current_pieces.clear()
	var first := int(move.get("depth", 0))
	var last := first + int(move.get("width", 1)) - 1
	for piece in model.piece_count():
		var layer := model.layer_of(piece, int(move["face"]))
		if layer >= first and layer <= last:
			_current_pieces.append(piece)


## Applies a move to the model and marks the drawing for a refresh.
func _bake(move: Dictionary) -> void:
	model.apply(move)
	if record_moves:
		recorded_moves.append(move)
	_ticker.append(model.notation(move))
	if _ticker.size() > TICKER_LENGTH:
		_ticker.remove_at(0)
	if not _rewinding:
		_remember(move)
	_dirty = true


func _remember(move: Dictionary) -> void:
	_history.append(move)
	if _history.size() > REWIND_MAX_MOVES:
		_history.pop_front()


## Finishes the current turn and applies every queued move instantly.
func _flush() -> void:
	if not _current.is_empty():
		var move := _current
		_current = {}
		_bake(move)
	while not _queue.is_empty():
		_bake(_queue.pop_front())


func _finish_solve() -> void:
	model.reset()
	_history.clear()
	_ticker.clear()
	_last_move = {}
	_solved_timer = SOLVED_HOLD
	_dirty = false
	_refresh_all()
	if _clock - _last_flash_at >= FLASH_MIN_INTERVAL and not speed_mode:
		_last_flash_at = _clock
		_flash = FLASH_ENERGY
		if not reduce_motion:
			_bounce = BOUNCE_TIME
	else:
		_punch = 1.0


# --- Drawing -------------------------------------------------------------------

func _build_instances() -> void:
	for node in _mega_pieces:
		node.queue_free()
	_mega_pieces.clear()
	if not model.piece_geometry.is_empty():
		_build_shaped_pieces()
		return
	var piece_count := model.piece_count()
	var bodies := MultiMesh.new()
	bodies.transform_format = MultiMesh.TRANSFORM_3D
	bodies.mesh = _body_mesh
	bodies.instance_count = piece_count
	_bodies.multimesh = bodies

	_sticker_piece.clear()
	_sticker_local.clear()
	_piece_stickers.clear()
	_piece_transforms.clear()
	_piece_transforms.resize(piece_count)
	var colors := _sticker_colors
	colors.clear()
	for piece in piece_count:
		var normals := model.sticker_normals[piece]
		var own := PackedInt32Array()
		for s in normals.size():
			var normal := normals[s]
			var up := Vector3.UP if absf(normal.y) < 0.9 else Vector3.BACK
			# Sticker meshes face +Z; looking_at points -Z at the target, so look away from the normal.
			var local := Transform3D(Basis.looking_at(-normal, up), normal * (CUBIE_HALF + STICKER_LIFT))
			own.append(_sticker_piece.size())
			_sticker_piece.append(piece)
			_sticker_local.append(local)
			colors.append(PuzzleShapes.palette(model)[model.sticker_colors[piece][s]])
		_piece_stickers.append(own)
	var stickers := MultiMesh.new()
	stickers.transform_format = MultiMesh.TRANSFORM_3D
	stickers.use_colors = true
	stickers.mesh = _sticker_mesh
	stickers.instance_count = _sticker_piece.size()
	_sticker_drawn.resize(_sticker_piece.size())
	for i in colors.size():
		stickers.set_instance_color(i, colors[i])
	_stickers.multimesh = stickers


## Puzzles whose pieces aren't all the same shape (the Megaminx): one MeshInstance3D per piece, built from the
## model's piece_geometry (a dark body and coloured sticker polygons, relative to the piece's home position),
## so the same Transform3D(basis, position) as the cubes places it. 62 small meshes; the MultiMeshes stay empty.
func _build_shaped_pieces() -> void:
	_bodies.multimesh = null
	_stickers.multimesh = null
	_sticker_piece.clear()
	_sticker_local.clear()
	_sticker_drawn.clear()
	_sticker_colors.clear()
	_piece_stickers.clear()
	_piece_transforms.clear()
	_piece_transforms.resize(model.piece_count())
	var body_material := _make_body_material()
	body_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sticker_material := _sticker_material.duplicate() as StandardMaterial3D
	sticker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shaped_sticker_material = sticker_material
	var colors := PuzzleShapes.palette(model)
	for piece in model.piece_count():
		var node := MeshInstance3D.new()
		node.mesh = PuzzleMeshes.shaped_piece(model.piece_geometry[piece], colors, body_material, sticker_material)
		_turntable.add_child(node)
		_mega_pieces.append(node)
		_piece_stickers.append(PackedInt32Array())


## Redraws every piece from the model.
func _refresh_all() -> void:
	for piece in model.piece_count():
		_piece_transforms[piece] = Transform3D(model.piece_basis(piece), model.piece_position(piece))
		_draw_piece(piece, _piece_transforms[piece])


## Redraws only the turning layer, part-way through its turn.
func _draw_current() -> void:
	var progress := clampf(_current_time / _current_duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - progress, 3.0)  # ease-out cubic: snappy start, soft landing
	var face := int(_current["face"])
	var angle := -model.step_angle * int(_current["turns"]) * eased
	_current_turn = Transform3D(Basis(model.face_normals[face], angle), Vector3.ZERO)
	for piece in _current_pieces:
		_draw_piece(piece, _current_turn * _piece_transforms[piece])


func _draw_piece(piece: int, t: Transform3D) -> void:
	if not _mega_pieces.is_empty():
		_mega_pieces[piece].transform = t
		return
	_bodies.multimesh.set_instance_transform(piece, t)
	for sticker in _piece_stickers[piece]:
		var sticker_transform := t * _sticker_local[sticker]
		_sticker_drawn[sticker] = sticker_transform
		_stickers.multimesh.set_instance_transform(sticker, sticker_transform)


# --- Golden Scramble sticker (S.6) ------------------------------------------------------

## Shows (or hides) a glowing gold sticker on the middle of the top face. Clicking it emits golden_clicked.
## Cubes only (the Megaminx has no sticker for it yet; the main screen's golden button works for every puzzle).
func set_golden(on: bool) -> void:
	if not on or model == null or model.size <= 0:
		if _golden != null:
			_golden.queue_free()
			_golden = null
		return
	if _golden == null:
		_golden_material = StandardMaterial3D.new()
		_golden_material.albedo_color = GOLDEN_COLOR
		_golden_material.emission_enabled = true
		_golden_material.emission = GOLDEN_COLOR
		_golden_material.emission_energy_multiplier = 1.4
		_golden_material.roughness = 0.15
		_golden_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # always bright, whatever the light
		_golden = MeshInstance3D.new()
		_golden.mesh = PuzzleMeshes.rounded_rect(STICKER_HALF * 1.06, STICKER_RADIUS)
		_golden.material_override = _golden_material
		_turntable.add_child(_golden)
	_golden.transform = _golden_transform()


func is_golden_shown() -> bool:
	return _golden != null


## The golden sticker's centre on the top face (model space): the middle sticker, or one next to the middle on even cubes.
func golden_point() -> Vector3:
	var offset := 0.0 if model.size % 2 == 1 else 0.5
	return Vector3(offset, model.size / 2.0, offset)


func _golden_transform() -> Transform3D:
	var basis := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)  # the sticker mesh faces +z; turn that to face up
	return Transform3D(basis, golden_point() + Vector3.UP * (STICKER_LIFT * 3.0))


## True if a click at `at` (local pixels) lands on the golden sticker.
func hits_golden(at: Vector2) -> bool:
	if _golden == null:
		return false
	var hit := pick(at)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.5:
		return false
	var point: Vector3 = hit["point"]
	var center := golden_point()
	return absf(point.x - center.x) < 0.55 and absf(point.z - center.z) < 0.55


func _animate_effects(delta: float) -> void:
	if _golden != null and _golden_material != null:
		var pulse := 1.0 if reduce_motion else 0.5 + 0.5 * sin(_clock * 6.0)
		_golden_material.albedo_color = GOLDEN_COLOR.lerp(Color(1.0, 0.95, 0.7), pulse * 0.6)
	var target_wobble := 1.0 if speed_mode and not reduce_motion else 0.0
	_wobble = move_toward(_wobble, target_wobble, delta * 3.0)
	if not _pressing:  # a released drag springs back
		var spring := exp(-delta * DRAG_SPRING)
		_drag_yaw *= spring
		_drag_pitch *= spring
	var yaw := _drag_yaw + sin(_clock * 7.0) * WOBBLE_YAW * _wobble
	var pitch := _drag_pitch + sin(_clock * 5.3) * WOBBLE_TILT * _wobble
	if sway_enabled:
		yaw += sin(_clock * 0.75) * SWAY_YAW
		pitch += sin(_clock * 0.53) * SWAY_PITCH
	# Turntable spins around the puzzle's own up axis; Puzzle tilts around the screen's horizontal axis.
	_turntable.basis = _base_turntable.rotated(Vector3.UP, yaw)
	_puzzle.basis = _base_puzzle.rotated(Vector3.RIGHT, pitch)
	_floor.basis = _base_puzzle.rotated(Vector3.RIGHT, pitch)  # the drag/wobble tilt (not the squash), or the puzzle would dip into the mat

	if _rim_boost > 0.0 or not is_equal_approx(_rim_light.light_energy, RIM_ENERGY):
		_rim_boost = maxf(0.0, _rim_boost - delta * RIM_FLASH_DECAY)
		_rim_light.light_energy = RIM_ENERGY + _rim_boost
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * FLASH_DECAY)
		_sticker_material.emission_energy_multiplier = _flash
		if _shaped_sticker_material != null:
			_shaped_sticker_material.emission_energy_multiplier = _flash
	_punch = maxf(0.0, _punch - delta * PUNCH_DECAY)
	var scale_value := 1.0 - PUNCH_SCALE * _punch
	if _bounce > 0.0:
		_bounce = maxf(0.0, _bounce - delta)
		var t := 1.0 - _bounce / BOUNCE_TIME
		scale_value += BOUNCE_SCALE * sin(t * PI) * (1.0 - t)  # a quick swell that settles
	if _drop > 0.0:
		_drop = maxf(0.0, _drop - delta)
		var t := 1.0 - _drop / DROP_TIME                       # 0 -> 1
		var fall := pow(1.0 - t, 2.0)                           # starts high, lands at 0
		var settle := sin(t * PI * 2.0) * (1.0 - t) * 0.06      # a small bounce on landing
		_puzzle.position = Vector3(0.0, fall * _extent() * 1.2, 0.0)
		scale_value *= 0.7 + 0.3 * t + settle
	else:
		_puzzle.position = Vector3.ZERO
	_squash = maxf(0.0, _squash - delta * SQUASH_DECAY)
	var squash_amount := sin(_squash * PI * 0.5)  # eases out of the squash
	_puzzle.scale = Vector3(
		scale_value * (1.0 + SQUASH_OUT * squash_amount),
		scale_value * (1.0 - SQUASH_DOWN * squash_amount),
		scale_value * (1.0 + SQUASH_OUT * squash_amount))


# --- Input -----------------------------------------------------------------------

## A click (press and release within TAP_SLOP px) taps. Moving further turns it into a drag that rotates the
## view instead, and never taps, even if the mouse comes back to where it started.
func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _pressing and not _press_hit.is_empty():  # a drag on the puzzle turns a layer, once per drag
			_dragging = _dragging or motion.position.distance_to(_press_position) > TAP_SLOP
			if not _drag_turn_done and motion.position.distance_to(_press_position) > DRAG_TURN_SLOP:
				_drag_turn_done = true
				var move := move_for_drag(_press_hit, motion.position - _press_position)
				if not move.is_empty():
					drag_turned.emit(move)
			accept_event()
			return
		if _pressing:
			if not _dragging and motion.position.distance_to(_press_position) > TAP_SLOP:
				_dragging = true
			if _dragging:
				_drag_yaw = wrapf(_drag_yaw + motion.relative.x * DRAG_SPEED, -PI, PI)
				_drag_pitch = clampf(_drag_pitch + motion.relative.y * DRAG_SPEED, -DRAG_MAX_PITCH, DRAG_MAX_PITCH)
			accept_event()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		_pressing = true
		_dragging = false
		_press_position = button.position
		_drag_turn_done = false
		_press_hit = pick(button.position) if drag_turns else {}
	elif _pressing:
		_pressing = false
		_press_hit = {}
		if not _dragging and button.position.distance_to(_press_position) <= TAP_SLOP:
			if hits_golden(button.position):
				golden_clicked.emit()
			else:
				tapped.emit(get_global_transform() * button.position)
		_dragging = false
	accept_event()


## Where a point in the view (local pixels) hits the puzzle: {normal, point} in model space (a cube's outer surface), or
## {} for the background (or a non-cube puzzle).
func pick(at: Vector2) -> Dictionary:
	if model == null or model.size <= 0:
		return {}
	var to_model := _turntable.global_transform.affine_inverse()
	var origin := to_model * _camera.project_ray_origin(at)
	var direction := to_model.basis * _camera.project_ray_normal(at)
	var half := model.size / 2.0
	var near := -INF
	var far := INF
	var axis_in := -1
	for axis in 3:
		if absf(direction[axis]) < 1e-9:
			if absf(origin[axis]) > half:
				return {}
			continue
		var t1 := (-half - origin[axis]) / direction[axis]
		var t2 := (half - origin[axis]) / direction[axis]
		if minf(t1, t2) > near:
			near = minf(t1, t2)
			axis_in = axis
		far = minf(far, maxf(t1, t2))
	if axis_in < 0 or near > far or far < 0.0:
		return {}
	var point := origin + direction * near
	var normal := Vector3.ZERO
	normal[axis_in] = signf(point[axis_in])
	return {"normal": normal, "point": point}


## The layer turn a drag across the puzzle means, like swiping a real cube: the drag picks the sticker row or column it
## runs along, and turns that layer the way the drag goes. `hit` is pick() at the press; `drag` is in pixels.
func move_for_drag(hit: Dictionary, drag: Vector2) -> Dictionary:
	if hit.is_empty() or drag.length() < 1.0:
		return {}
	var normal: Vector3 = hit["normal"]
	var point: Vector3 = hit["point"]
	var best := Vector3.ZERO
	var best_dot := 0.0
	for axis in 3:  # the face's two in-plane directions, as they look on screen
		if absf(normal[axis]) > 0.5:
			continue
		var along := Vector3.ZERO
		along[axis] = 1.0
		var on_screen := screen_position(point + along * 0.5) - screen_position(point)
		if on_screen.length() < 0.001:
			continue
		var d := on_screen.normalized().dot(drag.normalized())
		if absf(d) > absf(best_dot):
			best_dot = d
			best = along * signf(d)
	if best == Vector3.ZERO:
		return {}
	var axis_of_turn := normal.cross(best)  # turning +90° about it moves the pressed sticker along the drag
	var face := model.face_index(-axis_of_turn)  # ...which is a clockwise turn of the face on the other side
	var depth := 0
	var along_face := point.dot(model.face_normals[face])
	for cut in model.layer_cuts:
		if along_face < cut:
			depth += 1
	depth = mini(depth, model.layer_count() - 1)
	if depth > (model.layer_count() - 1) / 2.0:  # nearer the other side: name it from there (D', not 3U)
		return model.make_move(model.face_index(-model.face_normals[face]), -1, 1, model.layer_count() - 1 - depth)
	return model.make_move(face, 1, 1, depth)


## A model-space point, as a position in this view (local pixels).
func screen_position(model_point: Vector3) -> Vector2:
	return _camera.unproject_position(_turntable.global_transform * model_point)


## Where to put a label for a face (local pixels): on the middle of a face that looks at the camera, or just outside
## the puzzle's outline in that face's direction for a hidden one (so it never covers a face you can see).
## {position, facing}, or {} if there's no such face.
func face_label_position(face: int, margin: float = 22.0) -> Dictionary:
	if model == null or face < 0 or face >= model.face_normals.size():
		return {}
	var normal := model.face_normals[face]
	var half := _extent() / 2.0
	var world_normal := (_turntable.global_transform.basis * normal).normalized()
	var to_camera := (_camera.global_position - _turntable.global_transform * (normal * half)).normalized()
	var on_face := screen_position(normal * half)
	if world_normal.dot(to_camera) > 0.05:
		return {"position": on_face, "facing": true}
	var center := screen_position(Vector3.ZERO)
	var outline := 0.0
	for corner in [Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(-1, 1, 1),
			Vector3(-1, 1, -1), Vector3(-1, -1, 1), Vector3(-1, -1, -1)]:
		var along := (on_face - center).normalized()
		outline = maxf(outline, (screen_position(corner * half) - center).dot(along))
	var direction := (on_face - center).normalized() if on_face.distance_to(center) > 0.5 else Vector2.UP
	return {"position": center + direction * (outline + margin), "facing": false}


## How far the view is currently turned by a drag (radians, yaw and pitch). Tests use this.
func drag_offset() -> Vector2:
	return Vector2(_drag_yaw, _drag_pitch)


# --- Setup helpers ---------------------------------------------------------------

## The puzzle's width in cubie units (n for an n×n cube; about the same scale for the Megaminx).
func _extent() -> float:
	return model.radius * 2.0 / sqrt(3.0)


## Moves the camera back far enough for the whole puzzle to fit, whatever its size.
func _frame_camera() -> void:
	if model == null or not is_node_ready():
		return
	var radius := model.radius  # bounding sphere of the pieces
	var extent := _extent()
	_place_floor(radius, extent)
	# The camera looks down -Z from (0, y, distance). It must fit the puzzle's bounding sphere (it turns and sways)
	# and the mat's corners (V.3). Height is the view's fixed axis; a narrow view is limited by its width.
	var aspect := size.x / size.y if size.x > 0.0 and size.y > 0.0 else 1.0
	var tan_full := tan(deg_to_rad(_camera.fov) / 2.0)
	# Only the band between frame_inset_top and frame_inset_bottom, right of frame_inset_left, is free: frame into it (V.4).
	var inset_top := clampf(frame_inset_top / size.y, 0.0, 0.4) if size.y > 0.0 else 0.0
	var inset_bottom := clampf(frame_inset_bottom / size.y, 0.0, 0.4) if size.y > 0.0 else 0.0
	var inset_left := clampf(frame_inset_left / size.x, 0.0, 0.4) if size.x > 0.0 else 0.0
	var tan_h := tan_full * aspect * (1.0 - inset_left)
	var tan_v := tan_full * (1.0 - inset_top - inset_bottom)
	var corners := _mat_corners()
	var bottom := -radius
	for corner in corners:
		bottom = minf(bottom, corner.y)
	var centre_y := (radius + bottom) / 2.0 - extent * CAMERA_DROP
	var half_fov := atan(minf(tan_v, tan_h))
	var distance := radius / sin(half_fov) + absf(centre_y) / tan(half_fov)  # the sphere, off the view's axis
	var sideways := 0.0
	for corner in corners:
		distance = maxf(distance, corner.z + absf(corner.y - centre_y) / tan_v)
		# The camera moves sideways by -inset_left × its distance, so a corner nearer the camera (z > 0) shows
		# inset_left × z × tan further from the band's centre: fit that, not just its x.
		sideways = maxf(sideways, corner.z + absf(corner.x + inset_left * corner.z * tan_full * aspect) / tan_h)
	# frame_zoom may let the mat's front slip under the bottom strip, never its sides past the view's edges (V.4).
	distance = maxf(distance * FRAME_DISTANCE * frame_zoom, sideways * FRAME_DISTANCE)
	# The free band's centre is (top - bottom) / 2 of the view below its middle: moving the camera up by that much (in
	# world units at the puzzle) shows the puzzle there.
	var lift := (inset_top - inset_bottom) * distance * tan_full
	# Likewise sideways: the band's centre is inset_left half-widths right of the middle, so the camera moves left.
	var side := -inset_left * distance * tan_full * aspect
	_camera.position = Vector3(side, centre_y + lift, distance)
	_camera.near = 0.1

	# Backdrop: a quad behind the puzzle that exactly fills the view.
	var depth := _camera.position.z + radius * 1.5
	var height := 2.0 * depth * tan_full
	var shift := absf(centre_y + lift) / (depth * tan_full)  # how far off the camera axis the puzzle sits (in half-views)
	var shift_x := absf(side) / (depth * tan_full * aspect)
	(_backdrop.mesh as QuadMesh).size = Vector2(height * aspect, height) * (1.02 + shift + shift_x)  # still fills the view
	_backdrop.position = Vector3(-side, -centre_y - lift, -depth)  # a camera child: centred on the puzzle, not the camera
	_camera.far = depth + 1.0


## The mat's eight corners in view space (at rest), for framing and tests.
func _mat_corners() -> Array[Vector3]:
	var corners: Array[Vector3] = []
	if _mat.mesh == null:
		return corners
	var box := (_mat.mesh as ArrayMesh).get_aabb()
	for i in 8:
		var local := box.position + box.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)
		corners.append(_base_puzzle * (_mat.position + local))
	return corners


## Places the mat and the contact shadow for the current puzzle.
func _place_floor(radius: float, extent: float) -> void:
	# The mat (V.3): a slab under the puzzle's lowest point at rest, in the puzzle's tilted frame (Floor), so the
	# puzzle sits on it. The contact shadow lies on its top. Turntable spins around the puzzle's up axis, so the
	# lowest point doesn't depend on the turn.
	var lowest := 0.0
	for i in model.home_positions.size():
		var home := model.home_positions[i]
		if model.piece_geometry.is_empty():
			lowest = minf(lowest, home.y - CUBIE_HALF)
		else:  # Megaminx: its body polygons, relative to the piece's home
			for polygon: PackedVector3Array in model.piece_geometry[i]["body"]:
				for v in polygon:
					lowest = minf(lowest, home.y + v.y)
	var top := lowest - extent * MAT_GAP
	var thickness := extent * MAT_THICKNESS
	_floor.basis = _base_puzzle
	if not is_equal_approx(_mat_extent, extent):  # framing runs on every resize; the mesh only changes with the puzzle
		_mat_extent = extent
		_mat.mesh = PuzzleMeshes.rounded_slab(Vector3(radius * MAT_HALF_WIDTH, thickness / 2.0, radius * MAT_HALF_DEPTH),
				thickness * 0.45, MAT_STEPS)
		var rim := radius * MAT_RIM
		_mat_inset.mesh = PuzzleMeshes.rounded_slab(Vector3(radius * MAT_HALF_WIDTH - rim, thickness * 0.1,
				radius * MAT_HALF_DEPTH - rim), thickness * 0.09, 1)
	_mat.position = Vector3(0.0, top - thickness / 2.0, 0.0)
	_mat_inset.position = Vector3(0.0, top - thickness * 0.08, 0.0)  # its top just above the rim's top
	var width := extent * 1.45
	(_shadow.mesh as PlaneMesh).size = Vector2(width, width * 0.95)
	_shadow.position = Vector3(0.0, top + extent * 0.002, 0.0)


## The mat's highest surface (its inset), in the puzzle's tilted frame (tests).
func mat_top() -> float:
	if _mat.mesh == null:
		return 0.0
	return maxf(_mat.position.y + (_mat.mesh as ArrayMesh).get_aabb().size.y / 2.0,
			_mat_inset.position.y + (_mat_inset.mesh as ArrayMesh).get_aabb().size.y / 2.0)


func _make_body_mesh(steps: int) -> ArrayMesh:
	var mesh := PuzzleMeshes.rounded_box(CUBIE_HALF, CUBIE_RADIUS, steps)
	mesh.surface_set_material(0, _make_body_material())
	return mesh


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
	material.emission_enabled = true            # the solve flash brightens every sticker
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 0.0
	return material
