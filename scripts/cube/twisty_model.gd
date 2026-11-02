class_name TwistyModel
extends RefCounted
## A twisty puzzle as pure data (no nodes): pieces, faces, layers and moves.
## Build one with PuzzleShapes (e.g. PuzzleShapes.cube(3)); don't fill the fields by hand.
##
## How it works: every piece has a fixed *home* position and stickers. Its current state is one
## int, an index into the puzzle's rotation group (24 rotations for cubes, 60 for a Megaminx).
## Its position is group[orientation] * home. A move multiplies the orientation of every piece in
## the turning layers by the move's rotation, using a precomputed table. Everything stays exact,
## so a million moves never drift.
##
## A move is a Dictionary: {"face": int, "turns": int, "width": int, "depth": int}
##   face   index into face_names (cube: U D F B R L)
##   turns  clockwise steps looking at that face; normalized so 1 = R, -1 = R', 2 = R2
##   depth  first layer that turns, counted from the face (0 = the outer layer)
##   width  how many layers turn (R = 1, Rw = 2, 3Rw = 3)
## This is visual state only. It never affects game numbers and isn't saved.

var id := ""
var size := 0                        ## cube edge length (2-7); 0 for non-cubes
var step_angle := PI / 2.0           ## one turn: 90° for cubes, 72° for a Megaminx
var face_names := PackedStringArray()
var face_normals := PackedVector3Array()
var face_colors := PackedInt32Array()  ## colour index of each face when solved
var layer_cuts := PackedFloat32Array() ## dot-product boundaries between layers, from the face inwards
var scramble_widths := 1             ## random_move() turns outer blocks of 1..this many layers

var home_positions := PackedVector3Array()
var sticker_normals: Array[PackedVector3Array] = []  ## per piece, in the home frame
var sticker_colors: Array[PackedInt32Array] = []     ## per piece, same order as sticker_normals
var orientations := PackedInt32Array()               ## per piece, index into the rotation group

var _group: Array[Basis] = []
var _mult := PackedInt32Array()      ## _mult[a * group size + b] = index of group[a] * group[b]
var _identity := 0
var _order := 4                      ## turns until a face is back where it started
var _turn_rotation: Array[PackedInt32Array] = []  ## [face][turns mod order] -> group index


# --- Setup (called by PuzzleShapes) ------------------------------------------

## Builds the rotation group and move tables after the faces and pieces are set. Then resets to solved.
func finish_setup() -> void:
	_order = int(round(TAU / step_angle))
	_build_group()
	_turn_rotation.clear()
	for f in face_normals.size():
		var row := PackedInt32Array()
		for t in _order:
			var index := _find(Basis(face_normals[f], -step_angle * t))
			assert(index >= 0, "face turn is not in the rotation group")
			row.append(index)
		_turn_rotation.append(row)
	reset()


func _build_group() -> void:
	_group = [Basis.IDENTITY]
	var generators: Array[Basis] = []
	for normal in face_normals:
		generators.append(Basis(normal, step_angle))
	var i := 0
	while i < _group.size():
		for generator in generators:
			var product := _snap(generator * _group[i])
			if _find(product) < 0:
				_group.append(product)
		i += 1
		if _group.size() > 120:
			push_error("TwistyModel: rotation group too large; check the face normals")
			break
	_identity = 0
	var count := _group.size()
	_mult.resize(count * count)
	for a in count:
		for b in count:
			_mult[a * count + b] = _find(_snap(_group[a] * _group[b]))


func _find(basis: Basis) -> int:
	for i in _group.size():
		var g := _group[i]
		if (g.x - basis.x).length_squared() + (g.y - basis.y).length_squared() + (g.z - basis.z).length_squared() < 1e-6:
			return i
	return -1


## Cleans float noise: re-orthonormalizes, and rounds values that are almost -1, 0 or 1.
func _snap(basis: Basis) -> Basis:
	var b := basis.orthonormalized()
	for column in 3:
		var v := b[column]
		for axis in 3:
			if absf(v[axis] - roundf(v[axis])) < 1e-5:
				v[axis] = roundf(v[axis])
		b[column] = v
	return b


# --- State -------------------------------------------------------------------

func reset() -> void:
	orientations.resize(home_positions.size())
	orientations.fill(_identity)


func piece_count() -> int:
	return home_positions.size()


func piece_basis(piece: int) -> Basis:
	return _group[orientations[piece]]


func piece_position(piece: int) -> Vector3:
	return _group[orientations[piece]] * home_positions[piece]


## Layer of a piece counted from `face` (0 = the outer layer on that face).
func layer_of(piece: int, face: int) -> int:
	var d := piece_position(piece).dot(face_normals[face])
	var layer := 0
	for cut in layer_cuts:
		if d < cut:
			layer += 1
	return layer


## Index of the face whose normal points most along `direction`.
func face_index(direction: Vector3) -> int:
	var best := 0
	var best_dot := -INF
	for f in face_normals.size():
		var d := direction.dot(face_normals[f])
		if d > best_dot:
			best_dot = d
			best = f
	return best


## Colour index of the sticker at `position` facing `face`, or -1 if there's none.
## Positions are in model units (cube: one per cubie, centred on the origin).
func color_at(position: Vector3, face: int) -> int:
	var normal := face_normals[face]
	for piece in home_positions.size():
		if piece_position(piece).distance_squared_to(position) > 1e-4:
			continue
		var basis := _group[orientations[piece]]
		var normals := sticker_normals[piece]
		for s in normals.size():
			if (basis * normals[s]).dot(normal) > 0.99:
				return sticker_colors[piece][s]
		return -1
	return -1


## Solved = every face shows one colour (whole-puzzle rotations and swapped identical centres still count).
func is_solved() -> bool:
	var seen := PackedInt32Array()
	seen.resize(face_normals.size())
	seen.fill(-1)
	for piece in home_positions.size():
		var basis := _group[orientations[piece]]
		var normals := sticker_normals[piece]
		var colors := sticker_colors[piece]
		for s in normals.size():
			var f := face_index(basis * normals[s])
			if seen[f] == -1:
				seen[f] = colors[s]
			elif seen[f] != colors[s]:
				return false
	return true


# --- Moves -------------------------------------------------------------------

func make_move(face: int, turns: int, width: int = 1, depth: int = 0) -> Dictionary:
	var t := posmod(turns, _order)
	if t > _order / 2:
		t -= _order
	return {"face": face, "turns": t, "width": width, "depth": depth}


func apply(move: Dictionary) -> void:
	var turns := posmod(int(move["turns"]), _order)
	if turns == 0:
		return
	var face: int = move["face"]
	var rotation := _turn_rotation[face][turns]
	var first := int(move.get("depth", 0))
	var last := first + int(move.get("width", 1)) - 1
	var count := _group.size()
	for piece in home_positions.size():
		var layer := layer_of(piece, face)
		if layer >= first and layer <= last:
			orientations[piece] = _mult[rotation * count + orientations[piece]]


func apply_all(moves: Array) -> void:
	for move: Dictionary in moves:
		apply(move)


func inverse(move: Dictionary) -> Dictionary:
	return make_move(move["face"], -int(move["turns"]), move.get("width", 1), move.get("depth", 0))


## Inverse of a whole sequence (reversed, each move inverted).
func inverse_sequence(moves: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(moves.size() - 1, -1, -1):
		result.append(inverse(moves[i]))
	return result


## A random scramble-style move: an outer block (width 1..scramble_widths) of a random face,
## never the same face as `previous`, so consecutive moves don't merge or cancel.
func random_move(rng: RandomNumberGenerator = null, previous: Dictionary = {}) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var face := rng.randi_range(0, face_normals.size() - 1)
	while not previous.is_empty() and face == int(previous["face"]) and face_normals.size() > 1:
		face = rng.randi_range(0, face_normals.size() - 1)
	var turns := rng.randi_range(1, _order - 1)  # any non-zero amount, normalized by make_move
	return make_move(face, turns, rng.randi_range(1, scramble_widths))


## Applies `count` random moves and returns them.
func scramble(count: int, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var previous := {}
	for i in count:
		previous = random_move(rng, previous)
		apply(previous)
		moves.append(previous)
	return moves


# --- Notation (WCA for cubes) --------------------------------------------------

## WCA notation: R, R', R2, Rw (2 layers), 3Rw (3 layers). Inner slices use SiGN: 2R, 2-3Rw.
func notation(move: Dictionary) -> String:
	var face_name := face_names[int(move["face"])]
	var depth := int(move.get("depth", 0))
	var width := int(move.get("width", 1))
	var text := ""
	if depth == 0:
		if width == 1:
			text = face_name
		elif width == 2:
			text = face_name + "w"
		else:
			text = "%d%sw" % [width, face_name]
	elif width == 1:
		text = "%d%s" % [depth + 1, face_name]
	else:
		text = "%d-%d%sw" % [depth + 1, depth + width, face_name]
	var turns := int(move["turns"])
	var amount := absi(turns)
	if amount > 1:
		text += str(amount)
	if turns < 0:
		text += "'"
	return text


func notation_sequence(moves: Array) -> String:
	var parts := PackedStringArray()
	for move: Dictionary in moves:
		parts.append(notation(move))
	return " ".join(parts)


## Parses one move like R, U', F2, Rw, 3Rw2, 2R (SiGN slice). Returns {} if it isn't valid here.
func parse(text: String) -> Dictionary:
	var regex := RegEx.create_from_string("^(\\d+)?([A-Z])(w)?(\\d)?(')?$")
	var found := regex.search(text.strip_edges())
	if found == null:
		return {}
	var face := face_names.find(found.get_string(2))
	if face < 0:
		return {}
	var number := int(found.get_string(1)) if found.get_string(1) != "" else 0
	var width := 1
	var depth := 0
	if found.get_string(3) == "w":
		width = number if number > 0 else 2
	elif number > 0:
		depth = number - 1
	var layers := layer_cuts.size() + 1
	if depth + width > layers or width >= layers:  # turning every layer is a rotation, not a move
		return {}
	var amount := int(found.get_string(4)) if found.get_string(4) != "" else 1
	if found.get_string(5) == "'":
		amount = -amount
	return make_move(face, amount, width, depth)


## Parses a space-separated sequence. Returns [] if any move is invalid.
func parse_sequence(text: String) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for token in text.split(" ", false):
		var move := parse(token)
		if move.is_empty():
			return []
		moves.append(move)
	return moves
