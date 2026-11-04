class_name StagedSolver
extends RefCounted
## Solves a cube the way a person would, in named stages (task R.1). The main cube's showcase solve (R.2) plays the
## result, so the player sees a real Beginner or CFOP solve instead of random turns.
##
##   var stages := StagedSolver.solve(model, "cfop")   # model is not changed
##   for stage in stages: stage["id"], stage["name"], stage["moves"] (TwistyModel moves; may be empty = a "skip")
##
## Applying every stage's moves in order solves the model. Supported: 3×3 (Beginner, CFOP) and 2×2 (layer by layer).
## Other methods fall back to CFOP until R.5 adds Roux and ZZ; bigger cubes come in R.6. Visual only, never game state.
##
## How it works. Pieces are tracked as *slots*: a corner slot is position × 3 + twist, an edge slot position × 2 + flip
## (24 each). Every move becomes a table slot -> slot, built from the model's own geometry, so a whole move is a few
## array lookups. Pieces are named by where they belong, judged by the centre colours (2×2: by the corner at the back,
## bottom, left, which the 2×2 solve never moves), so a cube held in any orientation works.
##   Cross       an optimal search (IDA*) over the four bottom edges, guided by tables of every 3-edge pattern.
##   F2L pairs   the easiest pair first, each solved with real inserts (R U R', F' U' F, ...) and U turns, never
##               touching the cross or a finished pair (a shortest-path search over that pair's 576 states).
##   OLL / PLL   the same search over the last layer, with the algorithms in Content.ALGORITHMS as its steps.
##   Beginner    corners with repeated R U R' U', edges with the two classic inserts, then yellow cross, yellow edges,
##               corner cycle and the R' D' R D corner twist, as a beginner learns it.

const METHODS := ["beginner", "cfop"]
const PUZZLES := ["2x2", "3x3"]
const CROSS_COLOR := PuzzleShapes.COLOR_WHITE   ## 3×3: the cross colour, turned to the bottom (2×2: see read_state)
## Whole-cube rotations tried (in this order) to put the cross colour on the bottom. z2 keeps green in front.
const ORIENT_ROTATIONS := ["", "z2", "x'", "x", "z", "z'"]
const ALG_COST := 100        ## an algorithm costs this much more than its moves, so the search uses as few as it can
const MAX_CROSS_DEPTH := 10
## Extra cost of turning the whole cube by y^k before a pair (k = 0..3: none, y, y2, y'), so the solver only rotates
## when it saves moves, and prefers y / y' to y2.
const ROTATION_COST := [0, 2, 3, 2]

const STAGE_NAMES := {
	"inspection": "Inspection", "cross": "Cross", "f2l_1": "F2L 1", "f2l_2": "F2L 2", "f2l_3": "F2L 3",
	"f2l_4": "F2L 4", "oll": "OLL", "pll": "PLL",
	"first_layer": "First layer", "second_layer": "Second layer", "yellow_cross": "Yellow cross",
	"yellow_edges": "Yellow edges", "corner_cycle": "Corner positions", "corner_twist": "Corner twist",
	"orient": "Orient", "permute": "Permute",
}

static var _shapes := {}  ## model size -> _Shape (tables are built once)


## True if `solve` gives a real staged solve for this puzzle id (else the showcase keeps scramble + rewind).
static func supports(puzzle_id: String) -> bool:
	return puzzle_id in PUZZLES


## The solve as stages: [{"id", "name", "moves": Array[Dictionary]}]. `method` is a Content.METHODS id.
## Returns [] for a puzzle it can't solve (see supports()).
## `options`: {"full_oll": true, "full_pll": true} uses one-look OLL / PLL (the player learned the full set, S.4).
static func solve(model: TwistyModel, method: String = "cfop", options: Dictionary = {}) -> Array[Dictionary]:
	if model == null or model.notation_style != "wca" or not ("%dx%d" % [model.size, model.size]) in PUZZLES:
		return []
	var shape := _shape(model.size)
	var work := PuzzleShapes.cube(model.size)
	work.orientations = model.orientations.duplicate()
	var run := _Run.new(shape, work)
	if model.size == 2:
		run.solve_2x2(method)
	elif method == "beginner":
		run.solve_beginner()
	else:
		run.solve_cfop(options)
	return run.stages


## Builds the solver's tables for a puzzle now (they are cached for the whole session). The first solve otherwise
## builds what it needs itself, which can take ~0.5 s on a 3×3; call this while loading, or from a thread.
static func warm_up(puzzle_id: String = "3x3") -> void:
	if not supports(puzzle_id):
		return
	var model := PuzzleShapes.from_id(puzzle_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	model.scramble(25, rng)
	for method: String in METHODS:
		solve(model, method)
	if model.size == 3:
		var run := _Run.new(_shape(3), PuzzleShapes.cube(3))
		run.warm_up_cfop()


## True if the model has reached the goal of a stage (tests use this). Cross colour must already be on the bottom.
static func is_stage_done(model: TwistyModel, stage_id: String) -> bool:
	var run := _Run.new(_shape(model.size), model)
	return run.stage_done(stage_id)


static func _shape(size: int) -> _Shape:
	if not _shapes.has(size):
		_shapes[size] = _Shape.new(size)
	return _shapes[size]


## Merges neighbouring turns of the same layer (R R -> R2, R R' -> nothing).
static func simplify(model: TwistyModel, moves: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for move: Dictionary in moves:
		if not out.is_empty():
			var last: Dictionary = out[-1]
			if int(last["face"]) == int(move["face"]) and int(last.get("width", 1)) == int(move.get("width", 1)) \
					and int(last.get("depth", 0)) == int(move.get("depth", 0)):
				out.pop_back()
				var merged := model.make_move(move["face"], int(last["turns"]) + int(move["turns"]),
						move.get("width", 1), move.get("depth", 0))
				if int(merged["turns"]) != 0:
					out.append(merged)
				continue
		out.append(move)
	return out


# --- Geometry and move tables --------------------------------------------------

class _Shape:
	var size := 0
	var model: TwistyModel                          ## a solved cube of this size, for geometry and parsing
	var corner_pos: Array[Vector3] = []
	var corner_dirs: Array[PackedInt32Array] = []   ## faces at each corner position: U/D face first, then clockwise
	var edge_pos: Array[Vector3] = []
	var edge_dirs: Array[PackedInt32Array] = []     ## faces at each edge position: U/D (else F/B) face first
	var face_moves: Array[Dictionary] = []          ## the 18 outer-layer turns
	var _tables := {}                               ## "face,turns,width,depth" -> [corner table, edge table]
	var _patterns := {}                             ## key -> PackedByteArray of distances (see pattern_table)
	var macro_tables := {}                          ## key -> {code: cost to the goal} (see _Run.table_search)
	var u_face := 0
	var d_face := 0

	func _init(n: int) -> void:
		size = n
		model = PuzzleShapes.cube(n)
		u_face = model.face_names.find("U")
		d_face = model.face_names.find("D")
		var half := (n - 1) / 2.0
		var priority := ["U", "D", "F", "B", "R", "L"]
		var coords: Array[float] = [-half, half]
		if n > 2:
			coords.insert(1, 0.0)
		for x in coords:
			for y in coords:
				for z in coords:
					var p := Vector3(x, y, z)
					var faces := PackedInt32Array()
					for name: String in priority:
						var f := model.face_names.find(name)
						if p.dot(model.face_normals[f]) > half - 0.01:
							faces.append(f)
					if faces.size() == 3:
						var n0 := model.face_normals[faces[0]]
						if n0.cross(model.face_normals[faces[1]]).dot(p) < 0.0:
							faces = PackedInt32Array([faces[0], faces[2], faces[1]])
						corner_pos.append(p)
						corner_dirs.append(faces)
					elif faces.size() == 2 and n > 2:
						edge_pos.append(p)
						edge_dirs.append(faces)
		for f in model.face_names.size():
			for t: int in [1, -1, 2]:
				face_moves.append(model.make_move(f, t))

	func corner_index(p: Vector3) -> int:
		for i in corner_pos.size():
			if corner_pos[i].distance_squared_to(p) < 1e-3:
				return i
		return -1

	func edge_index(p: Vector3) -> int:
		for i in edge_pos.size():
			if edge_pos[i].distance_squared_to(p) < 1e-3:
				return i
		return -1

	func _layer(p: Vector3, face: int) -> int:
		var d := p.dot(model.face_normals[face])
		var layer := 0
		for cut in model.layer_cuts:
			if d < cut:
				layer += 1
		return layer

	## [corner table, edge table] for one move: slot -> slot after the move.
	func tables(move: Dictionary) -> Array:
		var key := "%d,%d,%d,%d" % [move["face"], move["turns"], move.get("width", 1), move.get("depth", 0)]
		if _tables.has(key):
			return _tables[key]
		var face: int = move["face"]
		var first := int(move.get("depth", 0))
		var last := first + int(move.get("width", 1)) - 1
		var rotation := Basis(model.face_normals[face], -model.step_angle * int(move["turns"]))
		var back := rotation.inverse()
		var result := [
			_table(corner_pos, corner_dirs, 3, face, first, last, rotation, back),
			_table(edge_pos, edge_dirs, 2, face, first, last, rotation, back),
		]
		_tables[key] = result
		return result

	func _table(positions: Array[Vector3], dirs: Array[PackedInt32Array], twists: int, face: int, first: int,
			last: int, rotation: Basis, back: Basis) -> PackedInt32Array:
		var table := PackedInt32Array()
		table.resize(positions.size() * twists)
		for i in positions.size():
			var layer := _layer(positions[i], face)
			var moves := layer >= first and layer <= last
			var j := i
			var shift := 0
			if moves:
				var p := rotation * positions[i]
				j = corner_index(p) if twists == 3 else edge_index(p)
				var came_from := model.face_index(back * model.face_normals[dirs[j][0]])
				shift = dirs[i].find(came_from)
			for o in twists:
				table[i * twists + o] = j * twists + (o + shift) % twists
		return table

	## Corner and edge tables of a whole sequence.
	func sequence_tables(moves: Array) -> Array:
		var ct := PackedInt32Array()
		var et := PackedInt32Array()
		for s in corner_pos.size() * 3:
			ct.append(s)
		for s in edge_pos.size() * 2:
			et.append(s)
		for move: Dictionary in moves:
			var t: Array = tables(move)
			var mc: PackedInt32Array = t[0]
			var me: PackedInt32Array = t[1]
			for s in ct.size():
				ct[s] = mc[ct[s]]
			for s in et.size():
				et[s] = me[et[s]]
		return [ct, et]

	## Distances to solved for a small set of pieces (each 24 slots), over `moves`, as one byte per pattern.
	## Pieces are given as [kind, index] with kind 0 = corner, 1 = edge. Built once, then cached.
	func pattern_table(key: String, pieces: Array, moves: Array[Dictionary]) -> PackedByteArray:
		if _patterns.has(key):
			return _patterns[key]
		var count := pieces.size()
		var total := 1
		for k in count:
			total *= 24
		var dist := PackedByteArray()
		dist.resize(total)
		dist.fill(255)
		var piece_tables: Array = []  # [move][k] -> slot table for piece k
		for move in moves:
			var t: Array = tables(move)
			var per_piece: Array[PackedInt32Array] = []
			for k in count:
				per_piece.append(t[0] if pieces[k][0] == 0 else t[1])
			piece_tables.append(per_piece)
		var goal := 0
		var scale := 1
		for k in count:
			var piece: Array = pieces[k]
			goal += int(piece[1]) * (3 if piece[0] == 0 else 2) * scale
			scale *= 24
		dist[goal] = 0
		var frontier := PackedInt32Array([goal])
		var depth := 0
		var slots := PackedInt32Array()
		slots.resize(count)
		while not frontier.is_empty():
			var next := PackedInt32Array()
			for code in frontier:
				var rest := code
				for k in count:
					slots[k] = rest % 24
					rest /= 24
				for per_piece: Array[PackedInt32Array] in piece_tables:
					var new_code := 0
					scale = 1
					for k in count:
						new_code += per_piece[k][slots[k]] * scale
						scale *= 24
					if dist[new_code] == 255:
						dist[new_code] = depth + 1
						next.append(new_code)
			frontier = next
			depth += 1
		_patterns[key] = dist
		return dist


# --- One solve -------------------------------------------------------------------

## One solve. A macro is a fixed move sequence used as one search step: {id, moves, ct, et, cost, dc, de}: ct/et are its
## corner/edge slot tables, dc/de bit masks of the corner/edge positions it disturbs, id names it for table caching.
class _Run:
	var shape: _Shape
	var model: TwistyModel             ## the work copy; every stage's moves are applied to it
	var corners := PackedInt32Array()  ## slot of each corner piece (piece i belongs at corner position i)
	var edges := PackedInt32Array()
	var stages: Array[Dictionary] = []
	var u_corners: Array[int] = []     ## pieces (= home positions) in the top and bottom layers, and the middle
	var d_corners: Array[int] = []
	var u_edges: Array[int] = []
	var d_edges: Array[int] = []
	var mid_edges: Array[int] = []
	var _u_turns: Array = []
	var _none: Array[int] = []

	func _init(s: _Shape, m: TwistyModel) -> void:
		shape = s
		model = m
		for i in shape.corner_pos.size():
			if shape.corner_pos[i].y > 0.0:
				u_corners.append(i)
			else:
				d_corners.append(i)
		for i in shape.edge_pos.size():
			var y := shape.edge_pos[i].y
			if y > 0.1:
				u_edges.append(i)
			elif y < -0.1:
				d_edges.append(i)
			else:
				mid_edges.append(i)
		for t: int in [1, -1, 2]:
			_u_turns.append(macro([model.make_move(shape.u_face, t)], 0))
		read_state()

	# --- State --------------------------------------------------------------

	## Reads every piece's slot from the model, naming pieces by the colours they should sit next to.
	func read_state() -> void:
		var face_color := PackedInt32Array()
		face_color.resize(6)
		face_color.fill(-1)
		if shape.size == 2:
			var anchor := _piece_at(Vector3(-0.5, -0.5, -0.5))
			for s in model.sticker_normals[anchor].size():
				var f := model.face_index(model.piece_basis(anchor) * model.sticker_normals[anchor][s])
				face_color[f] = model.sticker_colors[anchor][s]
			for f in 6:
				if face_color[f] == -1:
					var opposite := model.face_index(-model.face_normals[f])
					var solved_face := model.face_colors.find(face_color[opposite])
					face_color[f] = model.face_colors[model.face_index(-model.face_normals[solved_face])]
		else:
			for piece in model.piece_count():
				if model.sticker_normals[piece].size() == 1:
					var f := model.face_index(model.piece_basis(piece) * model.sticker_normals[piece][0])
					face_color[f] = model.sticker_colors[piece][0]
		var color_face := {}
		for f in 6:
			color_face[face_color[f]] = f
		var half := (shape.size - 1) / 2.0
		corners.resize(shape.corner_pos.size())
		edges.resize(shape.edge_pos.size())
		for piece in model.piece_count():
			var normals := model.sticker_normals[piece]
			if normals.size() < 2:
				continue
			var basis := model.piece_basis(piece)
			var at := shape.corner_index(model.piece_position(piece)) if normals.size() == 3 \
					else shape.edge_index(model.piece_position(piece))
			var dirs: PackedInt32Array = shape.corner_dirs[at] if normals.size() == 3 else shape.edge_dirs[at]
			var home := Vector3.ZERO
			var on_ref := -1
			for s in normals.size():
				var color := model.sticker_colors[piece][s]
				home += model.face_normals[color_face[color]] * half
				if model.face_index(basis * normals[s]) == dirs[0]:
					on_ref = color
			if normals.size() == 3:
				var h := shape.corner_index(home)
				corners[h] = at * 3 + _index_of_color(shape.corner_dirs[h], face_color, on_ref)
			else:
				var h := shape.edge_index(home)
				edges[h] = at * 2 + _index_of_color(shape.edge_dirs[h], face_color, on_ref)

	func _index_of_color(dirs: PackedInt32Array, face_color: PackedInt32Array, color: int) -> int:
		for k in dirs.size():
			if face_color[dirs[k]] == color:
				return k
		return 0

	func _piece_at(p: Vector3) -> int:
		for piece in model.piece_count():
			if model.piece_position(piece).distance_squared_to(p) < 1e-3:
				return piece
		return -1

	func corner_done(i: int) -> bool:
		return corners[i] == i * 3

	func edge_done(i: int) -> bool:
		return edges[i] == i * 2

	func all_done(c: Array[int], e: Array[int]) -> bool:
		for i in c:
			if not corner_done(i):
				return false
		for i in e:
			if not edge_done(i):
				return false
		return true

	## The F2L slots: [corner piece, edge piece] for each bottom corner and the middle edge above it.
	func f2l_pairs() -> Array:
		var pairs := []
		for c in d_corners:
			var p := shape.corner_pos[c]
			for e in mid_edges:
				var q := shape.edge_pos[e]
				if is_equal_approx(q.x, p.x) and is_equal_approx(q.z, p.z):
					pairs.append([c, e])
		return pairs

	func stage_done(stage_id: String) -> bool:
		match stage_id:
			"cross":
				return all_done(_none, d_edges)
			"first_layer":
				return all_done(d_corners, d_edges)
			"second_layer":
				return all_done(d_corners, _join(d_edges, mid_edges))
			"yellow_cross":
				return stage_done("second_layer") and _oriented(_none, u_edges)
			"yellow_edges":
				return stage_done("second_layer") and all_done(_none, u_edges)
			"corner_cycle":
				for c in u_corners:
					if corners[c] / 3 != c:
						return false
				return stage_done("yellow_edges")
			"oll", "orient":
				return all_done(d_corners, _join(d_edges, mid_edges)) and _oriented(u_corners, u_edges)
			"pll", "permute", "corner_twist":
				return model.is_solved()
		if stage_id.begins_with("f2l_"):
			var needed := int(stage_id.substr(4))
			var solved := 0
			for pair: Array in f2l_pairs():
				if corner_done(pair[0]) and edge_done(pair[1]):
					solved += 1
			return stage_done("cross") and solved >= needed
		return false

	func _join(a: Array[int], b: Array[int]) -> Array[int]:
		var out: Array[int] = a.duplicate()
		out.append_array(b)
		return out

	func _oriented(c: Array[int], e: Array[int]) -> bool:
		for i in c:
			if corners[i] % 3 != 0:
				return false
		for i in e:
			if edges[i] % 2 != 0:
				return false
		return true

	# --- Moves ----------------------------------------------------------------

	func macro(moves: Array, extra_cost: int, id: String = "") -> Dictionary:
		var t: Array = shape.sequence_tables(moves)
		var ct: PackedInt32Array = t[0]
		var et: PackedInt32Array = t[1]
		var dc := 0
		var de := 0
		for i in shape.corner_pos.size():
			if ct[i * 3] != i * 3:
				dc |= 1 << i
		for i in shape.edge_pos.size():
			if et[i * 2] != i * 2:
				de |= 1 << i
		if id == "":
			id = model.notation_sequence(moves)
		return {"id": id, "moves": moves, "ct": ct, "et": et, "cost": moves.size() + extra_cost, "dc": dc, "de": de}

	func alg_macro(id: String, extra_cost: int = ALG_COST) -> Dictionary:
		var moves := model.parse_sequence(Content.get_algorithm(id).get("alg", ""))
		if moves.is_empty():
			return {}
		return macro(moves, extra_cost)

	func apply_moves(moves: Array) -> void:
		for move: Dictionary in moves:
			var t: Array = shape.tables(move)
			var ct: PackedInt32Array = t[0]
			var et: PackedInt32Array = t[1]
			for i in corners.size():
				corners[i] = ct[corners[i]]
			for i in edges.size():
				edges[i] = et[edges[i]]
			model.apply(move)

	func add_stage(id: String, moves: Array) -> void:
		var clean := StagedSolver.simplify(model, moves)
		apply_moves(clean)
		stages.append({"id": id, "name": StagedSolver.STAGE_NAMES.get(id, id), "moves": clean})

	## Macros that leave every listed piece (which must be solved) alone.
	func safe(macros: Array, keep_c: Array[int], keep_e: Array[int]) -> Array:
		var mc := 0
		var me := 0
		for i in keep_c:
			mc |= 1 << i
		for i in keep_e:
			me |= 1 << i
		var out := []
		for m: Dictionary in macros:
			if not m.is_empty() and int(m["dc"]) & mc == 0 and int(m["de"]) & me == 0:
				out.append(m)
		return out

	## Cheapest macro sequence that takes the tracked pieces to their goal, or null if it can't be reached.
	## kind decides what counts and what the goal is (only the tracked pieces matter):
	##   "full"    every tracked piece home and untwisted
	##   "orient"  every tracked piece untwisted (they sit at the tracked pieces' home positions, e.g. the top layer)
	##   "perm"    every tracked piece at its home position, twisted or not
	## The cost to the goal of every reachable state is worked out once per (kind, pieces, macros) and cached on the
	## shape, so a solve only walks downhill through the table.
	func table_search(kind: String, track_c: Array[int], track_e: Array[int], macros: Array) -> Variant:
		var dist: Variant = cost_table(kind, track_c, track_e, macros)
		var code := _project(kind, track_c, track_e, _tracked_slots(track_c, track_e))
		var left := _cost_at(dist, code)
		if left < 0:
			return null
		var moves: Array = []
		while left > 0:
			var stepped := false
			for m: Dictionary in macros:
				var next := _step(kind, track_c, track_e, code, m)
				var after := _cost_at(dist, next)
				if after >= 0 and int(m["cost"]) + after == left:
					left = after
					moves.append_array(m["moves"])
					code = next
					stepped = true
					break
			if not stepped:
				return null
		return moves

	## Cost to the goal from where the tracked pieces are now (-1 if it can't be reached).
	func cost_to_goal(kind: String, track_c: Array[int], track_e: Array[int], macros: Array) -> int:
		var dist: Variant = cost_table(kind, track_c, track_e, macros)
		return _cost_at(dist, _project(kind, track_c, track_e, _tracked_slots(track_c, track_e)))

	func _cost_at(dist: Variant, code: int) -> int:
		if dist is PackedInt32Array:
			var table: PackedInt32Array = dist
			return table[code] if code >= 0 and code < table.size() else -1
		var costs: Dictionary = dist
		return int(costs.get(code, -1))

	## Dictionary {code: cost}, or for one or two whole pieces a PackedInt32Array indexed by code (-1 = unreachable).
	func cost_table(kind: String, track_c: Array[int], track_e: Array[int], macros: Array) -> Variant:
		var ids := PackedStringArray()
		for m: Dictionary in macros:
			ids.append(m["id"])
		var key := "%s|%s|%s|%s" % [kind, track_c, track_e, ",".join(ids)]
		if not shape.macro_tables.has(key):
			if kind == "full" and track_c.size() + track_e.size() <= 2:
				shape.macro_tables[key] = _build_small_table(track_c, track_e, macros)
			else:
				shape.macro_tables[key] = _build_table(kind, track_c, track_e, macros)
		return shape.macro_tables[key]

	## The same as _build_table for one or two whole pieces (24 or 576 states), with flat arrays: every state's next
	## state for every macro, then the steps turned around, then a shortest-path search from the goal.
	func _build_small_table(track_c: Array[int], track_e: Array[int], macros: Array) -> PackedInt32Array:
		var nc := track_c.size()
		var count := nc + track_e.size()
		var size := 24 if count == 1 else 576
		var piece_tables: Array[PackedInt32Array] = []  # [macro * count + k]
		var costs := PackedInt32Array()
		for m: Dictionary in macros:
			for k in count:
				piece_tables.append(m["ct"] if k < nc else m["et"])
			costs.append(int(m["cost"]))
		var mcount := macros.size()
		var into_count := PackedInt32Array()
		into_count.resize(size + 1)
		var next_of := PackedInt32Array()
		next_of.resize(size * mcount)
		for code in size:
			var a := code / 24 if count == 2 else code
			var b := code % 24
			for m in mcount:
				var next := piece_tables[m * count][a]
				if count == 2:
					next = next * 24 + piece_tables[m * count + 1][b]
				next_of[code * mcount + m] = next
				into_count[next + 1] += 1
		for code in size:
			into_count[code + 1] += into_count[code]
		var from_list := PackedInt32Array()
		from_list.resize(size * mcount)
		var cost_list := PackedInt32Array()
		cost_list.resize(size * mcount)
		var fill := into_count.duplicate()
		for code in size:
			for m in mcount:
				var next := next_of[code * mcount + m]
				from_list[fill[next]] = code
				cost_list[fill[next]] = costs[m]
				fill[next] += 1
		var homes := PackedInt32Array()
		for i in track_c:
			homes.append(i * 3)
		for i in track_e:
			homes.append(i * 2)
		var goal := homes[0] if count == 1 else homes[0] * 24 + homes[1]
		var dist := PackedInt32Array()
		dist.resize(size)
		dist.fill(-1)
		dist[goal] = 0
		var buckets: Array = [PackedInt32Array([goal])]
		var cost := 0
		while cost < buckets.size():
			var bucket: PackedInt32Array = buckets[cost]
			for code in bucket:
				if dist[code] != cost:
					continue
				for i in range(into_count[code], into_count[code + 1]):
					var from := from_list[i]
					var d := cost + cost_list[i]
					if dist[from] >= 0 and dist[from] <= d:
						continue
					dist[from] = d
					while buckets.size() <= d:
						buckets.append(PackedInt32Array())
					var target: PackedInt32Array = buckets[d]
					target.append(from)
					buckets[d] = target
			cost += 1
		return dist

	## Cost to the goal for every state that can reach it: walk out from the goal, then a shortest-path search
	## backwards along those steps (so a macro's inverse needn't be in the set).
	func _build_table(kind: String, track_c: Array[int], track_e: Array[int], macros: Array) -> Dictionary:
		var home := PackedInt32Array()
		for i in track_c:
			home.append(i * 3)
		for i in track_e:
			home.append(i * 2)
		var goal := _project(kind, track_c, track_e, home)
		var into := {goal: []}   # code -> [[from code, cost], ...]
		var queue := [goal]
		var head := 0
		while head < queue.size():
			var code: int = queue[head]
			head += 1
			for m: Dictionary in macros:
				var next := _step(kind, track_c, track_e, code, m)
				if not into.has(next):
					into[next] = []
					queue.append(next)
				(into[next] as Array).append([code, int(m["cost"])])
		var dist := {goal: 0}
		var buckets: Array = [[goal]]
		var cost := 0
		while cost < buckets.size():
			for code: int in buckets[cost]:
				if int(dist[code]) != cost:
					continue
				for edge: Array in into[code]:
					var from: int = edge[0]
					var d := cost + int(edge[1])
					if dist.has(from) and int(dist[from]) <= d:
						continue
					dist[from] = d
					while buckets.size() <= d:
						buckets.append([])
					buckets[d].append(from)
			cost += 1
		return dist

	func _tracked_slots(track_c: Array[int], track_e: Array[int]) -> PackedInt32Array:
		var slots := PackedInt32Array()
		for i in track_c:
			slots.append(corners[i])
		for i in track_e:
			slots.append(edges[i])
		return slots

	## One number for what `kind` cares about in these slots (tracked corners first, then edges). -1 = not a state
	## of this kind (a tracked piece outside the tracked positions).
	func _project(kind: String, track_c: Array[int], track_e: Array[int], slots: PackedInt32Array) -> int:
		var nc := track_c.size()
		var code := 0
		if kind == "full":
			for s in slots:
				code = code * 24 + s
			return code
		var digits := PackedInt32Array()
		digits.resize(slots.size())
		for k in slots.size():
			var twists := 3 if k < nc else 2
			var at := slots[k] / twists
			var j := track_c.find(at) if k < nc else track_e.find(at)
			if j < 0:
				return -1
			if k >= nc:
				j += nc
			digits[j] = slots[k] % twists if kind == "orient" else k
		for d in digits:
			code = code * 16 + d
		return code

	## The code after one macro.
	func _step(kind: String, track_c: Array[int], track_e: Array[int], code: int, m: Dictionary) -> int:
		var nc := track_c.size()
		var count := nc + track_e.size()
		var slots := PackedInt32Array()
		slots.resize(count)
		if kind == "full":
			for k in range(count - 1, -1, -1):
				slots[k] = code % 24
				code /= 24
		else:
			for j in range(count - 1, -1, -1):
				var d := code % 16
				code /= 16
				var home := track_c[j] * 3 if j < nc else track_e[j - nc] * 2
				if kind == "orient":  # any piece will do: only the position and twist matter
					slots[j] = home + d
				else:  # piece d sits at position j
					slots[d] = home
		var ct: PackedInt32Array = m["ct"]
		var et: PackedInt32Array = m["et"]
		for k in count:
			slots[k] = ct[slots[k]] if k < nc else et[slots[k]]
		return _project(kind, track_c, track_e, slots)

	# --- Methods ----------------------------------------------------------------

	## Turns the whole cube so the cross colour's centre is on the bottom (a real solver does this in inspection).
	func orient_for_cross() -> void:
		for text: String in StagedSolver.ORIENT_ROTATIONS:
			var moves: Array[Dictionary] = []
			if text != "":
				moves = model.parse_sequence(text)
			var probe := PuzzleShapes.cube(shape.size)
			probe.orientations = model.orientations.duplicate()
			probe.apply_all(moves)
			if _bottom_center_color(probe) == StagedSolver.CROSS_COLOR:
				if not moves.is_empty():
					model.apply_all(moves)
					read_state()
					stages.append({"id": "inspection", "name": StagedSolver.STAGE_NAMES["inspection"], "moves": moves})
				return

	func _bottom_center_color(m: TwistyModel) -> int:
		for piece in m.piece_count():
			if m.sticker_normals[piece].size() == 1:
				var f := m.face_index(m.piece_basis(piece) * m.sticker_normals[piece][0])
				if f == shape.d_face:
					return m.sticker_colors[piece][0]
		return -1

	## Cross: IDA* over the four bottom edges. The heuristic is the exact cost of every three of them, from one table
	## (three edges) looked up four times, turned by y, y2 and y' (the other triples are the same pattern rotated).
	func solve_cross() -> void:
		# Like a solver in inspection: try the four ways to hold the cube (y turns) and take the shortest cross,
		# then the one with fewest B turns (awkward to do).
		var best_k := 0
		var best_path: Array = []
		var best_score := -1
		for k: int in [0, 1, 3, 2]:
			var probe := self
			if k != 0:
				var probe_model := PuzzleShapes.cube(shape.size)
				probe_model.orientations = model.orientations.duplicate()
				probe_model.apply(model.make_move(shape.u_face, k, shape.size))
				probe = _Run.new(shape, probe_model)
			var path := probe.plan_cross()
			var score := path.size() * 10
			for move: Dictionary in path:
				if int(move["face"]) == model.face_names.find("B"):
					score += 1
			if best_score < 0 or score < best_score:
				best_score = score
				best_k = k
				best_path = path
		if best_k != 0:
			var turn := model.make_move(shape.u_face, best_k, shape.size)
			apply_moves([turn])
			read_state()
			if not stages.is_empty() and stages[-1]["id"] == "inspection":
				(stages[-1]["moves"] as Array).append(turn)
			else:
				stages.append({"id": "inspection", "name": StagedSolver.STAGE_NAMES["inspection"], "moves": [turn]})
		add_stage("cross", best_path)

	## The shortest cross from here, as moves (not applied).
	func plan_cross() -> Array:
		var lookups := _cross_lookups()
		var table: PackedByteArray = lookups[0]
		var state := PackedInt32Array()
		for e in d_edges:
			state.append(edges[e])
		var move_edges: Array[PackedInt32Array] = []
		for move in shape.face_moves:
			move_edges.append(shape.tables(move)[1])
		var path: Array[int] = []
		for limit in StagedSolver.MAX_CROSS_DEPTH + 1:
			if _cross_dfs(state, 0, limit, -1, path, table, lookups[1], move_edges):
				break
		var moves: Array = []
		for m in path:
			moves.append(shape.face_moves[m])
		return moves

	## [table, rotations]: the 3-edge table for d_edges[0..2], and for each y turn k: [i0, i1, i2, unturn table], so
	## the cost of the triple turned by y^k is table[unturn[s[i0]] + 24 * unturn[s[i1]] + 576 * unturn[s[i2]]].
	func _cross_lookups() -> Array:
		if shape.macro_tables.has("cross"):
			return shape.macro_tables["cross"]
		var base: Array = [[1, d_edges[0]], [1, d_edges[1]], [1, d_edges[2]]]
		var table := shape.pattern_table("cross", base, shape.face_moves)
		var rotations: Array = []
		for k in 4:
			var turn: PackedInt32Array = shape.tables(model.make_move(shape.u_face, k, 3))[1]
			var unturn: PackedInt32Array = shape.tables(model.make_move(shape.u_face, -k, 3))[1]
			var entry: Array = []
			for j in 3:  # the piece that sits where base piece j would after turning the whole cube by y^k
				entry.append(d_edges.find(turn[d_edges[j] * 2] / 2))
			entry.append(unturn)
			rotations.append(entry)
		var result := [table, rotations]
		shape.macro_tables["cross"] = result
		return result

	func _cross_h(s: PackedInt32Array, table: PackedByteArray, rotations: Array) -> int:
		var h := 0
		for r: Array in rotations:
			var unturn: PackedInt32Array = r[3]
			h = maxi(h, table[unturn[s[r[0]]] + 24 * unturn[s[r[1]]] + 576 * unturn[s[r[2]]]])
		return h

	func _cross_dfs(s: PackedInt32Array, depth: int, limit: int, last_face: int, path: Array[int],
			table: PackedByteArray, rotations: Array, move_edges: Array[PackedInt32Array]) -> bool:
		var h := _cross_h(s, table, rotations)
		if h == 0:
			return true
		if depth + h > limit:
			return false
		for m in move_edges.size():
			var face: int = shape.face_moves[m]["face"]
			if face == last_face or (last_face >= 0 and face == (last_face ^ 1) and face < last_face):
				continue  # same face twice, or opposite faces in the other order (U D = D U)
			var t := move_edges[m]
			var next := PackedInt32Array([t[s[0]], t[s[1]], t[s[2]], t[s[3]]])
			path.append(m)
			if _cross_dfs(next, depth + 1, limit, face, path, table, rotations, move_edges):
				return true
			path.pop_back()
		return false

	## F2L: the cheapest unsolved pair each time. Like a real solver, it only inserts at the front (R U R', F' U' F,
	## L' U' L, ...; never B) and turns the whole cube with y to bring a back pair round to the front.
	func solve_f2l() -> void:
		var jobs := f2l_pairs()
		var front := _front_macros("f2l", _f2l_front_moves())
		var cross: Array[int] = d_edges
		for n in 4:
			var moves: Variant = _solve_next(jobs, front, _none, cross)
			_record_applied("f2l_%d" % (n + 1), moves if moves != null else [])

	## X U^k X' style inserts on the front faces (R, L, F), both directions, k = 1, -1, 2.
	func _f2l_front_moves() -> Array:
		var sequences := []
		for side: String in ["R", "L", "F"]:
			var f := model.face_names.find(side)
			for s: int in [1, -1]:
				for k: int in [1, -1, 2]:
					sequences.append([model.make_move(f, s), model.make_move(shape.u_face, k), model.make_move(f, -s)])
		return sequences

	## Macros for a list of move sequences (cached on the shape under `key`).
	func _front_macros(key: String, sequences: Array) -> Array:
		if not shape.macro_tables.has("front|" + key):
			var macros := []
			for moves: Array in sequences:
				macros.append(macro(moves, 0))
			shape.macro_tables["front|" + key] = macros
		return shape.macro_tables["front|" + key]

	## Solves the cheapest unsolved job (a [corner, edge] pair; -1 = none of that kind) from `jobs`, turning the cube by y
	## first if that's cheaper, with `front` macros plus U turns, never disturbing `keep_c`/`keep_e` or a solved job.
	## Applies the moves and returns them (with the rotation), or null if every job is already solved.
	func _solve_next(jobs: Array, front: Array, keep_c: Array[int], keep_e: Array[int]) -> Variant:
		var best := {}
		for job: Array in jobs:
			if _job_done(job):
				continue
			for r in 4:
				var option := _rotated_option(job, r, jobs, front, keep_c, keep_e)
				if option.is_empty():
					continue
				var cost := int(option["cost"]) + int(StagedSolver.ROTATION_COST[r])
				if best.is_empty() or cost < int(best["total"]):
					best = option
					best["total"] = cost
					best["r"] = r
		if best.is_empty():
			for job: Array in jobs:
				if not _job_done(job):
					return _pop_out(jobs, front, keep_c, keep_e)
			return null
		var moves: Array = []
		if int(best["r"]) != 0:
			var turn := model.make_move(shape.u_face, int(best["r"]), shape.size)
			moves.append(turn)
			apply_moves([turn])
			read_state()  # pieces are named by the centres, which just moved
		var path: Variant = table_search("full", best["c"], best["e"], best["macros"])
		if path != null:
			moves.append_array(path)
			apply_moves(path)
		return moves

	## A piece stuck in the wrong slot below, where the front inserts can't reach from its own slot: hold that slot at the
	## front (a y turn) and do one insert there to pop it up, as a beginner does. Then solve on as normal.
	func _pop_out(jobs: Array, front: Array, keep_c: Array[int], keep_e: Array[int]) -> Variant:
		for r in [0, 1, 3, 2]:
			var t: Array = shape.tables(model.make_move(shape.u_face, r, shape.size))
			var rc: PackedInt32Array = t[0]
			var re: PackedInt32Array = t[1]
			var kc: Array[int] = []
			var ke: Array[int] = []
			for i in keep_c:
				kc.append(rc[i * 3] / 3)
			for i in keep_e:
				ke.append(re[i * 2] / 2)
			for job: Array in jobs:
				if _job_done(job):
					if int(job[0]) >= 0:
						kc.append(rc[int(job[0]) * 3] / 3)
					if int(job[1]) >= 0:
						ke.append(re[int(job[1]) * 2] / 2)
			for job: Array in jobs:
				if _job_done(job):
					continue
				var at_c := rc[corners[job[0]]] / 3 if int(job[0]) >= 0 else -1
				var at_e := re[edges[job[1]]] / 2 if int(job[1]) >= 0 else -1
				for m: Dictionary in safe(front, kc, ke):
					var hits := (at_c >= 0 and int(m["dc"]) & (1 << at_c) != 0) or \
							(at_e >= 0 and int(m["de"]) & (1 << at_e) != 0)
					var stuck := (at_c >= 0 and at_c in d_corners) or (at_e >= 0 and at_e in mid_edges)
					if not hits or not stuck:
						continue
					var moves: Array = []
					if r != 0:
						var turn := model.make_move(shape.u_face, r, shape.size)
						moves.append(turn)
						apply_moves([turn])
						read_state()
					moves.append_array(m["moves"])
					apply_moves(m["moves"])
					var rest: Variant = _solve_next(jobs, front, keep_c, keep_e)
					if rest != null:
						moves.append_array(rest)
					return moves
		return null

	func _job_done(job: Array) -> bool:
		return (int(job[0]) < 0 or corner_done(job[0])) and (int(job[1]) < 0 or edge_done(job[1]))

	## The cost of `job` after turning the cube by y^r, worked out without turning it: where its pieces and the kept
	## ones would be (and how they'd be named) after the turn. {} if the front macros can't solve it from there.
	## {cost, c, e, macros}: the job's pieces and the macros as named after the turn.
	func _rotated_option(job: Array, r: int, jobs: Array, front: Array, keep_c: Array[int], keep_e: Array[int]) -> Dictionary:
		var t: Array = shape.tables(model.make_move(shape.u_face, r, shape.size))
		var rc: PackedInt32Array = t[0]
		var re: PackedInt32Array = t[1]
		var kc: Array[int] = []
		var ke: Array[int] = []
		for i in keep_c:
			kc.append(rc[i * 3] / 3)
		for i in keep_e:
			ke.append(re[i * 2] / 2)
		for other: Array in jobs:
			if other != job and _job_done(other):
				if int(other[0]) >= 0:
					kc.append(rc[int(other[0]) * 3] / 3)
				if int(other[1]) >= 0:
					ke.append(re[int(other[1]) * 2] / 2)
		var tc: Array[int] = []
		var te: Array[int] = []
		var code := 0
		if int(job[0]) >= 0:
			tc.append(rc[int(job[0]) * 3] / 3)
			code = _renamed(rc, corners[job[0]], rc[int(job[0]) * 3] % 3, 3)
		if int(job[1]) >= 0:
			te.append(re[int(job[1]) * 2] / 2)
			code = code * 24 + _renamed(re, edges[job[1]], re[int(job[1]) * 2] % 2, 2)
		var macros: Array = _u_turns + safe(front, kc, ke)
		var cost := _cost_at(cost_table("full", tc, te, macros), code)
		if cost < 0:
			return {}
		return {"cost": cost, "c": tc, "e": te, "macros": macros}

	## A piece's slot after a whole-cube turn, counted from its new home: the turn moves its home too, and `shift` is how
	## far the turn moves its home's first sticker (so its twist is measured the way read_state() would).
	func _renamed(turn: PackedInt32Array, slot: int, shift: int, twists: int) -> int:
		var moved := turn[slot]
		return (moved / twists) * twists + posmod(moved % twists - shift, twists)

	## Builds every table a CFOP solve can need (cross, each front pair with each set of finished pairs, last layer).
	func warm_up_cfop() -> void:
		_cross_lookups()
		var pairs := f2l_pairs()
		var front := _front_macros("f2l", _f2l_front_moves())
		for k in pairs.size():
			for mask in 8:
				var kc: Array[int] = []
				var ke: Array[int] = d_edges.duplicate()
				var bit := 0
				for j in pairs.size():
					if j == k:
						continue
					if mask & (1 << bit):
						kc.append(pairs[j][0])
						ke.append(pairs[j][1])
					bit += 1
				var tc: Array[int] = [pairs[k][0]]
				var te: Array[int] = [pairs[k][1]]
				cost_table("full", tc, te, _u_turns + safe(front, kc, ke))

	func solve_last_layer(oll_ids: Array, pll_ids: Array, oll_stage: String, pll_stage: String) -> void:
		var keep_c: Array[int] = d_corners
		var keep_e: Array[int] = _join(d_edges, mid_edges)
		var oll := []
		for id: String in oll_ids:
			oll.append(alg_macro(id))
		var pll := []
		for id: String in pll_ids:
			pll.append(alg_macro(id))
		var moves: Variant = table_search("orient", u_corners, u_edges, _u_turns + safe(oll, keep_c, keep_e))
		add_stage(oll_stage, moves if moves != null else [])
		moves = table_search("full", u_corners, u_edges, _u_turns + safe(pll, keep_c, keep_e))
		add_stage(pll_stage, moves if moves != null else [])

	func solve_cfop(options: Dictionary = {}) -> void:
		orient_for_cross()
		solve_cross()
		solve_f2l()
		var oll_key := "full" if options.get("full_oll", false) else "two_look"
		var pll_key := "full" if options.get("full_pll", false) else "two_look"
		var oll_ids := []
		var pll_ids := []
		for alg: Dictionary in Content.ALGORITHMS:
			if alg["set"] == "OLL" and alg.get(oll_key, false):
				oll_ids.append(alg["id"])
			elif alg["set"] == "PLL" and alg.get(pll_key, false):
				pll_ids.append(alg["id"])
		solve_last_layer(oll_ids, pll_ids, "oll", "pll")

	func solve_beginner() -> void:
		orient_for_cross()
		solve_cross()
		# First layer: one corner at a time, held at the front and inserted with repeated R U R' U' (or L' U' L U),
		# turning the cube with y to bring it round, as a beginner does.
		var corner_jobs := []
		for c in d_corners:
			corner_jobs.append([c, -1])
		var sexy := _front_macros("beg_corner", [model.parse_sequence(Content.get_algorithm("beg_corner")["alg"]),
				model.parse_sequence("L' U' L U")])
		var corner_moves: Array = []
		for n in 4:
			var moves: Variant = _solve_next(corner_jobs, sexy, _none, d_edges)
			if moves == null:
				break
			corner_moves.append_array(moves)
		_record_applied("first_layer", corner_moves)
		# Second layer: one edge at a time with the two classic inserts, from the front.
		var edge_jobs := []
		for e in mid_edges:
			edge_jobs.append([-1, e])
		var inserts := _front_macros("beg_edge", [
				model.parse_sequence(Content.get_algorithm("beg_edge_right")["alg"]),
				model.parse_sequence(Content.get_algorithm("beg_edge_left")["alg"])])
		var edge_moves: Array = []
		for n in 4:
			var moves: Variant = _solve_next(edge_jobs, inserts, d_corners, d_edges)
			if moves == null:
				break
			edge_moves.append_array(moves)
		_record_applied("second_layer", edge_moves)
		# Last layer, step by step.
		var keep_c: Array[int] = d_corners
		var keep_e: Array[int] = _join(d_edges, mid_edges)
		var no_c: Array[int] = []
		var cross_alg := safe([alg_macro("beg_yellow_cross")], keep_c, keep_e)
		var moves: Variant = table_search("orient", no_c, u_edges, _u_turns + cross_alg)
		add_stage("yellow_cross", moves if moves != null else [])
		var edges_alg := safe([alg_macro("beg_yellow_edges")], keep_c, keep_e)
		moves = table_search("full", no_c, u_edges, _u_turns + edges_alg)
		add_stage("yellow_edges", moves if moves != null else [])
		_corner_cycle()
		_corner_twist()

	## Beginner corner positions: hold the cube so the one corner already in place is at the front right (a y turn) and
	## cycle the other three with U R U' L' U R' U' L until they're home. If no corner is in place yet, cycle once first.
	func _corner_cycle() -> void:
		var cycle := alg_macro("beg_corner_cycle", ALG_COST)
		var moves: Array = []
		for attempt in 3:
			var best_r := -1
			var best_cost := -1
			for r in 4:
				var probe_model := PuzzleShapes.cube(shape.size)
				probe_model.orientations = model.orientations.duplicate()
				probe_model.apply(model.make_move(shape.u_face, r, shape.size))
				var probe := _Run.new(shape, probe_model)
				var cost := probe.cost_to_goal("perm", probe.u_corners, _none, [cycle])
				if cost >= 0:
					cost += int(StagedSolver.ROTATION_COST[r])
					if best_cost < 0 or cost < best_cost:
						best_cost = cost
						best_r = r
			if best_r < 0:  # no corner in place: one cycle from here puts one in place
				moves.append_array(cycle["moves"])
				apply_moves(cycle["moves"])
				continue
			if best_r != 0:
				var turn := model.make_move(shape.u_face, best_r, shape.size)
				moves.append(turn)
				apply_moves([turn])
				read_state()
			var path: Variant = table_search("perm", u_corners, _none, [cycle])
			if path != null:
				moves.append_array(path)
				apply_moves(path)
			break
		_record_applied("corner_cycle", moves)

	## Beginner's last step: hold each top corner at the front-right and repeat R' D' R D until it's twisted right,
	## turning only the top (U) between corners. The bottom comes back by itself once all four are done.
	func _corner_twist() -> void:
		var once: Array = model.parse_sequence(Content.get_algorithm("beg_corner_twist")["alg"])
		var twist: Array = once + once  # (R' D' R D) twice turns the front-right top corner by a third
		var u := model.make_move(shape.u_face, 1)
		var spot := shape.corner_index(Vector3(1, 1, 1) * (shape.size - 1) / 2.0)
		var moves: Array = []
		for n in 4:
			for repeat in 3:
				var piece := -1
				for c in corners.size():
					if corners[c] / 3 == spot:
						piece = c
				if corners[piece] % 3 == 0:
					break
				moves.append_array(twist)
				apply_moves(twist)
			if n < 3 or not model.is_solved():
				moves.append(u)
				apply_moves([u])
		for n in 3:
			if model.is_solved():
				break
			moves.append(u)
			apply_moves([u])
		_record_applied("corner_twist", moves)

	## Adds a stage whose moves were already applied piece by piece.
	func _record_applied(id: String, moves: Array) -> void:
		stages.append({"id": id, "name": StagedSolver.STAGE_NAMES.get(id, id),
				"moves": StagedSolver.simplify(model, moves)})

	## 2×2: first layer (an optimal search over its three free corners, turning only U, R and F), then the top.
	func solve_2x2(method: String) -> void:
		var free: Array[int] = []
		var pieces: Array = []
		var anchor := shape.corner_index(Vector3(-0.5, -0.5, -0.5))
		for c in d_corners:
			if c != anchor:
				free.append(c)
				pieces.append([0, c])
		var urf: Array[Dictionary] = []
		for move in shape.face_moves:
			if model.face_names[int(move["face"])] in ["U", "R", "F"]:
				urf.append(move)
		var table := shape.pattern_table("2x2_first", pieces, urf)
		var moves: Array = []
		for step in 20:
			var code := corners[free[0]] + 24 * corners[free[1]] + 576 * corners[free[2]]
			if table[code] == 0:
				break
			for move in urf:
				var t: PackedInt32Array = shape.tables(move)[0]
				if table[t[corners[free[0]]] + 24 * t[corners[free[1]]] + 576 * t[corners[free[2]]]] < table[code]:
					moves.append(move)
					apply_moves([move])
					break
		_record_applied("first_layer", moves)
		if method == "beginner":
			solve_last_layer(["oll_sune", "oll_antisune"], ["pll_t", "pll_y"], "orient", "permute")
		else:
			var oll_ids := []
			for alg: Dictionary in Content.ALGORITHMS:
				if alg["set"] == "OLL" and alg["two_look"]:
					oll_ids.append(alg["id"])
			solve_last_layer(oll_ids, ["pll_t", "pll_y"], "oll", "pll")
