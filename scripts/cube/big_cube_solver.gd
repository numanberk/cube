class_name BigCubeSolver
extends RefCounted
## Solves a big cube (4×4-7×7; tasks R.6a/R.6b) the way a person does, by **reduction**, in named stages, so the main
## cube's showcase solve (R.2) works on them too:
##
##   var stages := BigCubeSolver.solve(model, "cfop")   # model is not changed
##   for stage in stages: stage["id"], stage["name"], stage["moves"] (TwistyModel moves)
##
##   Centres   one face after another (first centre, the opposite one, then the four around), a piece or a bar at a
##             time: a slice turn, a face turn + slice, a slice-face-slice insert (Rw U Rw'), and, once a face turn
##             would undo finished pieces, the 8-move centre commutator (Rw U' Lw' U Rw' U' Lw U). A step never undoes
##             a finished piece: the cheapest move per piece gained is taken.
##   Edges     pairing with free slices: a few outer turns line two matching pieces up, a slice joins them, three
##             outer turns swap the finished edge for an unfinished one (R U R'), and the slice goes back
##             (Uw R U R' Uw'). The last two edges use the slice-flip-slice algorithm (Uw' R U R' F R' F' R Uw).
##   Parity    only when needed. The edge parity, one wing orbit at a time (an edge's two wings of that orbit swapped:
##             the orbit is an odd permutation, known as soon as the centres are done, so the last edges wait for this
##             stage): 5×5 and 7×7 every wing orbit, 6×6 the outer wings when they differ from the inner ones; fixed by
##             WING_PARITY on that orbit's slices (2R, 3R). Even cubes then OLL parity (one edge flipped) and PLL
##             parity (two edges swapped), found on the reduced cube; on a 6×6 the 4×4 algorithms turned in blocks (3Rw).
##   3×3 stage the reduced cube is read as a 3×3 and solved by StagedSolver with the learned method; its moves are
##             mapped back (the 3×3's middle layer = every inner layer).
##
## How it works. The cube is tracked as **facelets** (6·n² sticker places, each holding a colour). Every move is a table
## place -> place built once from the model's own geometry, so a move is a few array writes and nothing is re-read
## from the model. Centres and edges each have a library of short move sequences ("macros") with their effect stored,
## indexed by "moves the piece at A to B" (centres) or "joins the pieces at A and B" (edges); a step looks the wanted
## piece up, checks the candidates on the real colours and plays the cheapest. Visual only, never game state.
##
## On 6×6 and 7×7 the pairing also turns single inner slices (3U), so one wing orbit moves without the other.
##
## The libraries are built on first use (~0.1 s a size, a 7×7's ~0.3 s; `warm_up` does it ahead of time) and cached; a
## solve is then planned in ~15 ms (4×4) / ~22 ms (5×5) / ~100 ms (6×6, 7×7), ~170 / ~310 / ~520 / ~760 moves. `plan`
## does it a step at a time so the showcase spreads a 7×7's over its inspection: most steps take under 1 ms, a few a
## solve 20-60 ms, and now and then a route search for the last edges ~100 ms (7×7; up to ~0.3 s on the 6×6, which has
## rare slow solves, ~3 s, and isn't in the game).
## The game has no 6×6; it is solved here (and tested) because it is the even cube with two wing orbits.

const PUZZLES := ["4x4", "5x5", "6x6", "7x7"]
const STAGE_NAMES := {"centres": "Centres", "edges": "Edges", "parity": "Parity"}
## Faces in the order their centres are built: U, its opposite D, then the four around (F R B L).
const FACE_ORDER := [0, 1, 2, 4, 3, 5]
const TURNS := [1, -1, 2]
## The usual parity algorithms. OLL parity flips the edge at UF (on a 5×5: swaps its two wings); PLL parity (4×4)
## swaps the edges at UF and UB.
const OLL_PARITY := "Rw U2 x Rw U2 Rw U2 Rw' U2 Lw U2 Rw' U2 Rw U2 Rw' U2 Rw'"
## The same flip with single inner slices, which also keeps an odd cube's centres (the wide one doesn't on a 5×5).
const WING_PARITY := "2R2 B2 U2 2L U2 2R' U2 2R U2 F2 2R F2 2L' B2 2R2"
const PLL_PARITY := "2R2 U2 2R2 Uw2 2R2 Uw2"
## The edge-flip algorithms the last two edges use, between a slice and its undo (written for a U slice, edge at FR).
const EDGE_FLIPS := ["R U R' F R' F' R", "R F' U R' F"]
const MAX_ESCAPES := 6
## Two-turn set-ups the pairing search tries per planning step (of ~290), so a step stays short.
const SETUPS_PER_TICK := 30
## Zero-gain steps one sideways step (_sideways) tries before moving on to the next set-up, so a step stays short.
const SIDEWAYS_PROBES := 24

static var _shapes := {}
## How often the edge stage needed its slow way out (a look-ahead over every flip macro) since start-up. Tests watch it.
static var escapes := 0


## True if `solve` gives a real staged solve for this puzzle id.
static func supports(puzzle_id: String) -> bool:
	return puzzle_id in PUZZLES


## The solve as stages: [{"id", "name", "moves": Array[Dictionary]}]: centres, edges, parity (only if needed), then
## the 3×3 stage's own stages for `method` (a Content.METHODS id; see StagedSolver). [] for a puzzle it can't solve.
static func solve(model: TwistyModel, method: String = "cfop", options: Dictionary = {}) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if model == null or model.notation_style != "wca" or not supports("%dx%d" % [model.size, model.size]):
		return none
	var planner := plan(model, method, options)
	planner.step(-1)
	return planner.stages()


## The same solve, planned a bit at a time (a 7×7's takes ~0.1-0.25 s, too long for one frame): call
## `step(budget_usec)` once a frame until it returns true, then read `stages()`. null for a puzzle it can't solve.
## The model is read now; changing it later doesn't change the plan.
static func plan(model: TwistyModel, method: String = "cfop", options: Dictionary = {}) -> Planner:
	if model == null or model.notation_style != "wca" or not supports("%dx%d" % [model.size, model.size]):
		return null
	return Planner.new(model, method, options)


## Builds the libraries for a puzzle now (cached for the session), and the 3×3 stage's tables for `methods`.
static func warm_up(puzzle_id: String, methods: Array = ["cfop"]) -> void:
	if not supports(puzzle_id):
		return
	var model := PuzzleShapes.from_id(puzzle_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	model.scramble(40, rng)
	for method: String in methods:
		solve(model, method)


## True if the model has reached a stage's goal (tests use this): "centres" (every face's centres one colour),
## "edges" (centres, and every edge paired), "parity" (edges, and the reduced cube is a solvable 3×3).
static func is_stage_done(model: TwistyModel, stage_id: String) -> bool:
	var run := _Run.new(_shape(model.size))
	run.col = run.shape.read(model)
	match stage_id:
		"centres":
			return run.centres_done()
		"edges":
			return run.centres_done() and run.unpaired_edges() == 0
		"parity":
			return run.centres_done() and run.unpaired_edges() == 0 and not run.oll_parity() and not run.pll_parity()
	return model.is_solved()


## How many of the 12 edges aren't paired yet (tests: a 5×5 may leave the Edges stage with a parity to fix).
static func unpaired_edges(model: TwistyModel) -> int:
	var run := _Run.new(_shape(model.size))
	run.col = run.shape.read(model)
	return run.unpaired_edges()


class Planner:
	extends RefCounted
	var _run: _Run
	var _done := false


	func _init(model: TwistyModel, method: String, options: Dictionary) -> void:
		_run = _Run.new(BigCubeSolver._shape(model.size))
		_run.col = _run.shape.read(model)
		_run.start(method, options)


	## Plans for about `budget_usec` microseconds (a step is a few ms at most, a rare one more; -1 = to the end).
	## True once the plan is done.
	func step(budget_usec: int) -> bool:
		var until := Time.get_ticks_usec() + budget_usec
		while not _done:
			_done = _run.step()
			if budget_usec >= 0 and Time.get_ticks_usec() >= until:
				break
		return _done


	func is_done() -> bool:
		return _done


	## The stages (see BigCubeSolver.solve), once done; [] if no solution was found.
	func stages() -> Array[Dictionary]:
		var none: Array[Dictionary] = []
		if not _done:
			return none
		if not _run.ok:
			push_warning("BigCubeSolver: no solution found for a %d×%d state" % [_run.shape.n, _run.shape.n])
			return none
		return _run.stages


static func _shape(size: int) -> _Shape:
	if not _shapes.has(size):
		_shapes[size] = _Shape.new(size)
	return _shapes[size]


# --- Geometry, move tables and the macro libraries (one per cube size) -------------------

class _Shape:
	var n := 0
	var half := 0.0
	var model: TwistyModel               ## a solved cube of this size (make_move, parse, the rotation group)
	var count := 0                       ## facelets: 6·n²
	var face := PackedInt32Array()       ## per facelet: the face it is on
	var pos := PackedVector3Array()      ## per facelet: its piece's position
	var ids := {}                        ## _key(position, face) -> facelet
	var identity := PackedInt32Array()
	var perms := {}                      ## move code -> [dest, moved]: the colour at i goes to dest[i]; moved = the i that move
	var ref := 0                         ## index along an edge of its reference piece (odd cubes: the middle one)

	var centres := PackedInt32Array()                 ## every centre facelet
	var face_centres: Array[PackedInt32Array] = []    ## per face
	var fixed := PackedInt32Array()                   ## per face: the fixed centre (odd cubes), else -1

	var slot_fa := PackedInt32Array()                 ## per edge slot (12): its two faces, fa < fb
	var slot_fb := PackedInt32Array()
	var slot_a: Array[PackedInt32Array] = []          ## per slot: the facelets on fa, in order along the edge
	var slot_b: Array[PackedInt32Array] = []          ## ... and on fb
	var slot_of := PackedInt32Array()                 ## per facelet: its edge slot, or -1
	var side_of := PackedInt32Array()                 ## per edge facelet: 0 = on fa, 1 = on fb
	var slot_by_mask := {}                            ## (1 << fa) | (1 << fb) -> slot
	var edge_facelets := PackedInt32Array()
	var corners: Array[PackedInt32Array] = []         ## 8 corners × 3 facelets
	var corner_by_mask := {}

	var outer: Array[Dictionary] = []                 ## the 18 outer face turns (edge set-ups)
	var outer_dest: Array[PackedInt32Array] = []
	var setups: Array[PackedInt32Array] = []          ## every sequence of 0, 1, 2 outer turns (indices into outer)

	# Centre library: macro i = c_moves[i], moving the colours at c_from[i][k] to c_to[i][k].
	var c_built := false
	var c_moves: Array = []
	var c_from: Array[PackedInt32Array] = []
	var c_to: Array[PackedInt32Array] = []
	var c_cost := PackedInt32Array()
	var c_cheap := {}                                 ## from * count + to -> [macro, ...]: slice turns and inserts
	var c_comm := {}                                  ## ... and the commutators (pure three-cycles)

	# Edge library: macro i = e_moves[i], its effect on the edge facelets e_dest[i] (a full-size table).
	var e_built := false
	var e_moves: Array = []
	var e_dest: Array[PackedInt32Array] = []
	var e_source: Array[PackedInt32Array] = []        ## the inverse: the colour at x comes from e_source[i][x]
	var e_slots: Array[PackedInt32Array] = []         ## the edge slots a macro changes
	var e_index := {}                                 ## lo * count + hi -> [macro, ...] that join the pieces at lo and hi
	var e_flips := PackedInt32Array()                 ## the slice-flip-slice macros

	var slot_hand := PackedInt32Array()               ## per slot: +1 if fa × fb points along the edge's rising coordinate
	var parity_slot := 0                              ## the edge the parity algorithms work on (UF)
	var oll_alg: Array[Dictionary] = []               ## even cubes: OLL parity (the 4×4 one in blocks: 3Rw on a 6×6)
	var pll_alg: Array[Dictionary] = []               ## even cubes: PLL parity (likewise)
	var orbits := PackedInt32Array()                  ## the wing orbits, by the index of their lower wing along an edge
	var ref_orbit := -1                               ## even cubes: the orbit the reference piece is in, else -1
	var swap_algs := {}                               ## orbit -> WING_PARITY on that orbit's slices (2R, 3R, ...)
	var reduced: Array = []                           ## [3×3 piece][rotation] -> the big facelets its stickers read


	func _init(size: int) -> void:
		n = size
		half = (n - 1) / 2.0
		ref = (n - 2) / 2
		model = PuzzleShapes.cube(n)
		var kind := PackedInt32Array()
		var piece := PackedInt32Array()
		for p in model.piece_count():
			var normals := model.sticker_normals[p]
			for s in normals.size():
				var f := _face_of(normals[s])
				ids[_key(model.home_positions[p], f)] = count
				face.append(f)
				pos.append(model.home_positions[p])
				kind.append(normals.size())
				piece.append(p)
				identity.append(count)
				count += 1
		slot_of.resize(count)
		slot_of.fill(-1)
		side_of.resize(count)
		for f in 6:
			face_centres.append(PackedInt32Array())
			fixed.append(-1)
		var slot_pieces := {}  # slot key -> [[coordinate along the edge, facelet on fa, facelet on fb], ...]
		var corner_of := {}
		for i in count:
			match kind[i]:
				1:
					centres.append(i)
					face_centres[face[i]].append(i)
					if absf(pos[i].x) + absf(pos[i].y) + absf(pos[i].z) < half + 0.01:
						fixed[face[i]] = i
				2:
					edge_facelets.append(i)
					if i + 1 < count and piece[i + 1] == piece[i]:
						var a := i if face[i] < face[i + 1] else i + 1
						var b := i + 1 if a == i else i
						var slot_key := face[a] * 6 + face[b]
						if not slot_pieces.has(slot_key):
							slot_pieces[slot_key] = []
						var along := 0.0
						for axis in 3:
							if absf(pos[i][axis]) < half - 0.01:
								along = pos[i][axis]
						(slot_pieces[slot_key] as Array).append([along, a, b])
				3:
					if not corner_of.has(piece[i]):
						corner_of[piece[i]] = corners.size()
						corners.append(PackedInt32Array())
					corners[corner_of[piece[i]]].append(i)
		for slot_key: int in slot_pieces:
			var list: Array = slot_pieces[slot_key]
			list.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			var slot := slot_fa.size()
			slot_fa.append(slot_key / 6)
			slot_fb.append(slot_key % 6)
			slot_by_mask[(1 << (slot_key / 6)) | (1 << (slot_key % 6))] = slot
			var on_a := PackedInt32Array()
			var on_b := PackedInt32Array()
			for entry: Array in list:
				on_a.append(entry[1])
				on_b.append(entry[2])
				slot_of[entry[1]] = slot
				slot_of[entry[2]] = slot
				side_of[entry[1]] = 0
				side_of[entry[2]] = 1
			slot_a.append(on_a)
			slot_b.append(on_b)
		for c in corners.size():
			var mask := 0
			for i in corners[c]:
				mask |= 1 << face[i]
			corner_by_mask[mask] = c
		for f in 6:
			for turns: int in TURNS:
				var move := model.make_move(f, turns)
				outer.append(move)
				outer_dest.append(dest_of(move))
		setups.append(PackedInt32Array())
		for a in outer.size():
			setups.append(PackedInt32Array([a]))
		for a in outer.size():
			for b in outer.size():
				if a / 3 != b / 3:
					setups.append(PackedInt32Array([a, b]))
		oll_alg = in_blocks(OLL_PARITY)
		pll_alg = in_blocks(PLL_PARITY)
		var last := n - 3
		for o in range(0, (last + 1) / 2):
			orbits.append(o)
			if ref == o or ref == last - o:
				ref_orbit = o
			elif n >= 5:
				swap_algs[o] = model.parse_sequence(WING_PARITY.replace("2R", "%dR" % (o + 2)).replace("2L", "%dL" % (o + 2)))
		var flipped := identity.duplicate()  # which edge the parity algorithms work on: mark every facelet, see what moved
		for move in (swap_algs[orbits[0]] if swap_algs.has(orbits[0]) else oll_alg):
			flipped = apply(flipped, move)
		for slot in 12:
			for k in slot_a[slot].size():
				if k != ref and slot_of[flipped[slot_a[slot][k]]] == slot and flipped[slot_a[slot][k]] != slot_a[slot][k]:
					parity_slot = slot
		for slot in 12:
			var cross := model.face_normals[slot_fa[slot]].cross(model.face_normals[slot_fb[slot]])
			slot_hand.append(1 if cross.x + cross.y + cross.z > 0.0 else -1)
		_build_reduced()


	## A 4×4 algorithm on this cube with its layers in blocks (R | the inner layers on R's side | ... | L), as people
	## turn 4×4 parity algorithms on a 6×6 (Rw = 3Rw, 2R = 2-3R). On a 4×4 it is the algorithm itself.
	func in_blocks(text: String) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		var start := [0, 1, n / 2, n - 1]
		var finish := [0, n / 2 - 1, n - 2, n - 1]
		for move in PuzzleShapes.cube(4).parse_sequence(text):
			var depth := int(move.get("depth", 0))
			var first: int = start[depth]
			var last: int = finish[depth + int(move.get("width", 1)) - 1]
			out.append(model.make_move(move["face"], move["turns"], last - first + 1, first))
		return out


	func _face_of(direction: Vector3) -> int:
		var best := 0
		var best_dot := -INF
		for f in 6:
			var d := direction.dot(model.face_normals[f])
			if d > best_dot:
				best_dot = d
				best = f
		return best


	func _key(at: Vector3, f: int) -> int:
		return ((int(round(at.x + half)) * n + int(round(at.y + half))) * n + int(round(at.z + half))) * 6 + f


	## [dest, moved] for a move (cached).
	func perm(move: Dictionary) -> Array:
		var turns := posmod(int(move["turns"]), 4)
		var width := int(move.get("width", 1))
		var depth := int(move.get("depth", 0))
		var code := ((int(move["face"]) * 4 + turns) * 8 + width) * 8 + depth
		if perms.has(code):
			return perms[code]
		var normal := model.face_normals[int(move["face"])]
		var rotation := Basis(normal, -PI / 2.0 * turns)
		var dest := PackedInt32Array()
		dest.resize(count)
		var moved := PackedInt32Array()
		for i in count:
			var layer := int(round(half - pos[i].dot(normal)))
			if layer < depth or layer > depth + width - 1:
				dest[i] = i
				continue
			var j: int = ids[_key(rotation * pos[i], _face_of(rotation * model.face_normals[face[i]]))]
			dest[i] = j
			if j != i:
				moved.append(i)
		var result := [dest, moved]
		perms[code] = result
		return result


	func dest_of(move: Dictionary) -> PackedInt32Array:
		return perm(move)[0]


	func apply(col: PackedInt32Array, move: Dictionary) -> PackedInt32Array:
		var table := perm(move)
		var dest: PackedInt32Array = table[0]
		var out := col.duplicate()
		for i: int in table[1]:
			out[dest[i]] = col[i]
		return out


	## The facelet colours of a model in any state.
	func read(m: TwistyModel) -> PackedInt32Array:
		var out := PackedInt32Array()
		out.resize(count)
		for p in m.piece_count():
			var basis := m.piece_basis(p)
			var at := basis * m.home_positions[p]
			var normals := m.sticker_normals[p]
			var colors := m.sticker_colors[p]
			for s in normals.size():
				out[ids[_key(at, _face_of(basis * normals[s]))]] = colors[s]
		return out


	## One table for a whole sequence.
	func compose(moves: Array) -> PackedInt32Array:
		var out := identity.duplicate()
		for move: Dictionary in moves:
			var dest := dest_of(move)
			for i in count:
				out[i] = dest[out[i]]
		return out


	## The 3×3 the reduced cube is: for each 3×3 piece and each of the 24 rotations, the big facelets its stickers
	## would be read from (a 3×3 coordinate 0 = the reference inner piece).
	func _build_reduced() -> void:
		var three := PuzzleShapes.cube(3)
		var inner := -half + 1.0 + ref
		var group: Array[Basis] = three._group
		for p in three.piece_count():
			var by_rotation: Array[PackedInt32Array] = []
			for g in group.size():
				var at := group[g] * three.home_positions[p]
				var big := Vector3.ZERO
				for axis in 3:
					big[axis] = -half if at[axis] < -0.5 else (half if at[axis] > 0.5 else inner)
				var places := PackedInt32Array()
				for normal in three.sticker_normals[p]:
					places.append(ids[_key(big, _face_of(group[g] * normal))])
				by_rotation.append(places)
			reduced.append(by_rotation)


	# --- Centre library ---

	func _register_centre(moves: Array[Dictionary], from: PackedInt32Array, to: PackedInt32Array, index: Dictionary) -> void:
		var id := c_moves.size()
		c_moves.append(moves)
		c_from.append(from)
		c_to.append(to)
		c_cost.append(moves.size())
		for k in from.size():
			var key := from[k] * count + to[k]
			var list: PackedInt32Array = index.get(key, PackedInt32Array())
			list.append(id)
			index[key] = list


	func _trace_centres(moves: Array[Dictionary], index: Dictionary) -> void:
		var tables: Array[PackedInt32Array] = []
		for move in moves:
			tables.append(dest_of(move))
		var from := PackedInt32Array()
		var to := PackedInt32Array()
		for c in centres:
			var x := c
			for table in tables:
				x = table[x]
			if x != c:
				from.append(c)
				to.append(x)
		_register_centre(moves, from, to, index)


	func build_centres() -> void:
		if c_built:
			return
		c_built = true
		# Every inner layer as a single slice, named from its nearer face: [axis, face, depth].
		var slices: Array = []
		for axis in 3:
			for layer in range(1, n - 1):
				if layer <= (n - 1) / 2:
					slices.append([axis, axis * 2, layer])
				else:
					slices.append([axis, axis * 2 + 1, n - 1 - layer])
		# Slice turns, and slice-face-slice inserts.
		for slice: Array in slices:
			for i: int in TURNS:
				var s := model.make_move(slice[1], i, 1, slice[2])
				var one: Array[Dictionary] = [s]
				_trace_centres(one, c_cheap)
				for x in 6:
					if x / 2 == int(slice[0]):
						continue
					for k: int in TURNS:
						var insert: Array[Dictionary] = [s, model.make_move(x, k), model.inverse(s)]
						_trace_centres(insert, c_cheap)
		# Commutators [A, B] with A a slice turn and B = X S2 X' (another slice of the same axis, carried across by a
		# quarter turn of a face they both cross): where A and B share exactly one centre, it's a pure three-cycle.
		var conj := {}  # [x, k, slice index, j] code -> [moves, dest]
		for a in slices.size():
			var slice_a: Array = slices[a]
			var a_moved := PackedInt32Array()
			var a_quarter := dest_of(model.make_move(slice_a[1], 1, 1, slice_a[2]))
			for c in centres:
				if a_quarter[c] != c:
					a_moved.append(c)
			for i: int in TURNS:
				var move_a := model.make_move(slice_a[1], i, 1, slice_a[2])
				var a_dest := dest_of(move_a)
				var a_back := dest_of(model.inverse(move_a))
				for b in slices.size():
					var slice_b: Array = slices[b]
					if b == a or slice_b[0] != slice_a[0]:
						continue
					for x in 6:
						if x / 2 == int(slice_a[0]):
							continue
						for k: int in [1, -1]:
							for j: int in TURNS:
								var forward := _conjugate(conj, x, k, b, slice_b, j)
								var back := _conjugate(conj, x, k, b, slice_b, -j)
								var b_dest: PackedInt32Array = forward[1]
								var b_back: PackedInt32Array = back[1]
								var shared := 0
								var p := -1
								for c in a_moved:
									if b_dest[c] != c:
										shared += 1
										p = c
								if shared != 1:
									continue
								var points := [p, a_dest[p], a_back[p], b_dest[p], b_back[p]]
								var a_moves: Array[Dictionary] = [move_a]
								var a_undo: Array[Dictionary] = [model.inverse(move_a)]
								_commutator(points, a_moves, forward[0], a_undo, back[0], [a_dest, b_dest, a_back, b_back])
								_commutator(points, forward[0], a_moves, back[0], a_undo, [b_dest, a_dest, b_back, a_back])


	func _conjugate(cache: Dictionary, x: int, k: int, b: int, slice_b: Array, j: int) -> Array:
		var code := ((x * 4 + posmod(k, 4)) * 16 + b) * 4 + posmod(j, 4)
		if not cache.has(code):
			var moves: Array[Dictionary] = [model.make_move(x, k), model.make_move(slice_b[1], j, 1, slice_b[2]),
					model.make_move(x, -k)]
			cache[code] = [moves, compose(moves)]
		return cache[code]


	func _commutator(points: Array, first: Array, second: Array, third: Array, fourth: Array, tables: Array) -> void:
		var from := PackedInt32Array()
		var to := PackedInt32Array()
		for q: int in points:
			if q in from:
				continue
			var x := q
			for table: PackedInt32Array in tables:
				x = table[x]
			if x != q:
				from.append(q)
				to.append(x)
		if from.size() != 3:
			return
		var moves: Array[Dictionary] = []
		for part: Array in [first, second, third, fourth]:
			for move: Dictionary in part:
				moves.append(move)
		_register_centre(moves, from, to, c_comm)


	# --- Edge library ---

	func build_edges() -> void:
		if e_built:
			return
		e_built = true
		var group: Array[Basis] = model._group
		# The flip algorithms in every orientation and mirrored: {text: moves}.
		var flips := {}
		for text: String in EDGE_FLIPS:
			var base := model.parse_sequence(text)
			for g in group.size():
				for mirror in 2:
					var turned: Array[Dictionary] = []
					for move in base:
						var normal := model.face_normals[int(move["face"])]
						var turns := int(move["turns"])
						if mirror == 1:
							normal.x = -normal.x
							turns = -turns
						turned.append(model.make_move(_face_of(group[g] * normal), turns))
					flips[model.notation_sequence(turned)] = turned
		for pass_index in 2:  # the short pairing macros first, so they are tried first
			for f in 6:
				var axis := f / 2
				var middles: Array = []  # [moves, dest] of what happens between the slice and its undo
				if pass_index == 0:
					for a in 6:
						if a / 2 == axis:
							continue
						for ta: int in TURNS:
							for b: int in [axis * 2, axis * 2 + 1]:
								for j: int in TURNS:
									var swap: Array[Dictionary] = [model.make_move(a, ta), model.make_move(b, j),
											model.make_move(a, -ta)]
									middles.append([swap, compose(swap)])
				else:
					for text: String in flips:
						var alg: Array[Dictionary] = flips[text]
						var net := [0, 0, 0, 0, 0, 0]
						for move in alg:
							net[int(move["face"])] += int(move["turns"])
						var safe := true
						for x in 6:
							if x / 2 != axis and posmod(net[x], 4) != 0:
								safe = false
						if safe:
							middles.append([alg, compose(alg)])
				for layers: Vector2i in pairing_slices():
					for k: int in (TURNS if pass_index == 0 else [1, -1]):
						var slice := model.make_move(f, k, layers.x, layers.y)
						var s_dest := dest_of(slice)
						var s_back := dest_of(model.inverse(slice))
						for middle: Array in middles:
							_register_edge(slice, middle[0], s_dest, middle[1], s_back, pass_index == 1)


	## The slices pairing turns, as (width, depth): wide turns from the face (Uw, 3Uw, ...) and, on 6×6 and up, each
	## single inner slice (3U ...), so one wing orbit can move without the other.
	func pairing_slices() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for width in range(2, n / 2 + 1):
			out.append(Vector2i(width, 0))
		if n >= 6:
			for depth in range(1, n / 2):
				out.append(Vector2i(1, depth))
		return out


	func _register_edge(slice: Dictionary, middle: Array[Dictionary], s_dest: PackedInt32Array,
			m_dest: PackedInt32Array, s_back: PackedInt32Array, is_flip: bool) -> void:
		for c in centres:  # must leave the (solved) centres looking the same
			if face[s_back[m_dest[s_dest[c]]]] != face[c]:
				return
		var dest := identity.duplicate()
		var source := identity.duplicate()
		for e in edge_facelets:
			var x := s_back[m_dest[s_dest[e]]]
			dest[e] = x
			source[x] = e
		var id := e_moves.size()
		var useful := false
		var anchors := [ref] if n % 2 == 1 else range(n - 2)  # even cubes: any piece can be the one the others join
		for slot in 12:
			for side in 2:
				var places := slot_a[slot] if side == 0 else slot_b[slot]
				for at: int in anchors:
					var anchor := source[places[at]]
					for k in range(at + 1 if n % 2 == 0 else 0, places.size()):
						if k == at:
							continue
						var wing := source[places[k]]
						if wing == places[k] and anchor == places[at]:
							continue  # not touched
						if slot_of[wing] == slot_of[anchor] and side_of[wing] == side_of[anchor]:
							continue  # they were together already
						var key := (wing * count + anchor) if wing < anchor else (anchor * count + wing)
						var list: PackedInt32Array = e_index.get(key, PackedInt32Array())
						if list.is_empty() or list[-1] != id:
							list.append(id)
							e_index[key] = list
						useful = true
		if not useful and not is_flip:
			return
		var moves: Array[Dictionary] = [slice]
		moves.append_array(middle)
		moves.append(model.inverse(slice))
		var touched := PackedInt32Array()
		for slot in 12:
			for k in slot_a[slot].size():
				if dest[slot_a[slot][k]] != slot_a[slot][k] or dest[slot_b[slot][k]] != slot_b[slot][k]:
					touched.append(slot)
					break
		e_moves.append(moves)
		e_dest.append(dest)
		e_source.append(source)
		e_slots.append(touched)
		if is_flip:
			e_flips.append(id)


	## The shortest run of outer turns that carries the colour at facelet `from` to `to` (indices into outer).
	func route(from: int, to: int) -> PackedInt32Array:
		var parent := {from: [-1, -1]}
		var queue := PackedInt32Array([from])
		var head := 0
		while head < queue.size() and not parent.has(to):
			var at := queue[head]
			head += 1
			for o in outer.size():
				var next := outer_dest[o][at]
				if not parent.has(next):
					parent[next] = [at, o]
					queue.append(next)
		var out := PackedInt32Array()
		if not parent.has(to):
			return out
		var at := to
		while at != from:
			out.append(parent[at][1])
			at = parent[at][0]
		out.reverse()
		return out


# --- One solve -------------------------------------------------------------------

class _Run:
	var shape: _Shape
	var col := PackedInt32Array()        ## the colour on every facelet
	var stages: Array[Dictionary] = []
	var moves: Array[Dictionary] = []    ## the stage being built
	var ok := true


	func _init(s: _Shape) -> void:
		shape = s
		_gain_a.resize(s.n - 2)
		_gain_b.resize(s.n - 2)


	func play(move: Dictionary) -> void:
		moves.append(move)
		col = shape.apply(col, move)


	func end_stage(id: String) -> void:
		stages.append({"id": id, "name": STAGE_NAMES[id], "moves": StagedSolver.simplify(shape.model, moves)})
		moves = []


	# Planned a step at a time (Planner): `phase` is the stage being built.
	var phase := "centres"
	var method := "cfop"
	var options := {}
	var _scheme := PackedInt32Array()   ## centres: the colour each face's centres get
	var _locked := PackedByteArray()    ## centres: facelets that are finished
	var _face_index := 0                ## centres: FACE_ORDER index of the face being built
	var _face_steps := 0
	var _left := 0                      ## edges: how many edges may stay unpaired for the parity stage
	var _tier := 0                      ## edges: the pairing search _pair_tick is in (see there)
	var _targets := PackedInt32Array()  ## edges: the wanted pairs while the slower searches run
	var _route := 0                     ## edges: the next of them to route
	var _swaps := PackedInt32Array()    ## parity: the wing orbits still to swap
	var _escapes := 0
	var _gain_a := PackedInt32Array()   ## scratch arrays for _edge_gain
	var _gain_b := PackedInt32Array()


	func start(m: String, o: Dictionary) -> void:
		method = m
		options = o
		phase = "centres"
		_start_centres()


	## One step of the plan (a centre step, a pairing step, the parity stage, the 3×3 stage). True when done.
	func step() -> bool:
		match phase:
			"centres":
				if not _centre_tick():
					return false
				end_stage("centres")
				if not ok:
					return true
				shape.build_edges()
				_left = 2 * orbits_to_swap().size()  # each swap leaves one or two edges
				phase = "edges"
			"edges":
				if _pair_tick():
					return false
				end_stage("edges")
				phase = "parity"
			"parity":  # the edge parity first: wing swaps, then pairing the last edges
				_swaps = orbits_to_swap() if _edge_metric(col) < _edge_max() else PackedInt32Array()
				_escapes = 0
				phase = "swap"
			"swap":
				if not _swaps.is_empty():
					_swap_wings(shape.swap_algs[_swaps[0]])
					_swaps.remove_at(0)
					return false
				_left = 0
				_tier = 0
				phase = "repair"
			"repair":
				if _pair_tick():
					return false
				phase = "escape" if _edge_metric(col) < _edge_max() else "parity_algs"
			"escape":  # still stuck: rare (a test watches the counter)
				_escapes += 1
				if _escapes > MAX_ESCAPES or not _escape():
					ok = false
					return true
				_tier = 0
				phase = "repair"
			"parity_algs":  # even cubes: OLL and PLL parity on the reduced cube
				_fix_parity()
				if not moves.is_empty():
					end_stage("parity")
				phase = "reduced"
			"reduced":
				_solve_reduced(method, options)
				phase = "done"
				return true
			_:
				return true
		return false


	# --- Centres ---

	func centres_done() -> bool:
		for f in 6:
			var list := shape.face_centres[f]
			for i in list:
				if col[i] != col[list[0]]:
					return false
		return true


	func _start_centres() -> void:
		var s := shape
		s.build_centres()
		_scheme = PackedInt32Array()
		_locked = PackedByteArray()
		_locked.resize(s.count)
		for f in 6:
			if s.fixed[f] >= 0:
				_scheme.append(col[s.fixed[f]])
				_locked[s.fixed[f]] = 1
			else:
				_scheme.append(s.model.face_colors[f])
		_face_index = 0
		_face_steps = 0


	## One centre step (faces in FACE_ORDER, a piece or a few at a time). True when every centre is done (or stuck).
	func _centre_tick() -> bool:
		var s := shape
		while _face_index < FACE_ORDER.size():
			var f: int = FACE_ORDER[_face_index]
			var c := _scheme[f]
			var wrong := false
			for t in s.face_centres[f]:
				if col[t] == c:
					_locked[t] = 1
				else:
					wrong = true
			if not wrong or _face_steps >= 200:
				_face_index += 1
				_face_steps = 0
				continue
			_face_steps += 1
			var step := _centre_step(f, c, _locked, _scheme)
			if step.is_empty():
				ok = false
				return true
			for move in _prefer_wide(step, f, c, _locked, _scheme):
				play(move)
			return false
		return true


	## What a macro would do to face `f`: how many more of its centres show `c`, or -1 if it undoes a locked one.
	## `pre`: where each facelet's colour comes from once a set-up turn is done (identity for none).
	func _gain(id: int, pre: PackedInt32Array, f: int, c: int, locked: PackedByteArray, scheme: PackedInt32Array) -> int:
		var from := shape.c_from[id]
		var to := shape.c_to[id]
		var gain := 0
		for i in from.size():
			var colour := col[pre[from[i]]]
			var t := to[i]
			if locked[t] == 1:
				if colour != scheme[shape.face[t]]:
					return -1
			elif shape.face[t] == f and colour == c:
				gain += 1
		return gain


	## The moves of the best next step for face `f`: the fewest moves per centre gained.
	func _centre_step(f: int, c: int, locked: PackedByteArray, scheme: PackedInt32Array) -> Array[Dictionary]:
		var s := shape
		var sources := PackedInt32Array()
		for a in s.centres:
			if col[a] == c and locked[a] == 0:
				sources.append(a)
		var none: Array[Dictionary] = []
		for index: Dictionary in [s.c_cheap, s.c_comm]:
			# As it is.
			var best := -1
			var best_score := INF
			for t in s.face_centres[f]:
				for a in sources:
					var key := a * s.count + t
					if not index.has(key):
						continue
					for id: int in index[key]:
						var gain := _gain(id, s.identity, f, c, locked, scheme)
						if gain > 0 and float(s.c_cost[id]) / gain < best_score:
							best_score = float(s.c_cost[id]) / gain
							best = id
			if best >= 0:
				return s.c_moves[best]
			# After turning the face the piece is on (nothing there is finished yet).
			var best_setup := {}
			for a in sources:
				for turns: int in TURNS:
					var setup := s.model.make_move(s.face[a], turns)
					var moved := s.dest_of(setup)[a]
					var pre := s.dest_of(s.model.inverse(setup))
					for t in s.face_centres[f]:
						var key := moved * s.count + t
						if not index.has(key):
							continue
						for id: int in index[key]:
							var gain := _gain(id, pre, f, c, locked, scheme)
							if gain > 0 and float(s.c_cost[id] + 1) / gain < best_score:
								best_score = float(s.c_cost[id] + 1) / gain
								best = id
								best_setup = setup
			if best >= 0:
				var out: Array[Dictionary] = [best_setup]
				out.append_array(s.c_moves[best])
				return out
		# Last resort: any macro between an outer turn and its undo, checked on the whole cube.
		for o in s.outer.size():
			var setup := s.outer[o]
			var dest := s.outer_dest[o]
			var turned := s.apply(col, setup)
			for t in s.face_centres[f]:
				for a in sources:
					var key := dest[a] * s.count + dest[t]
					for index: Dictionary in [s.c_cheap, s.c_comm]:
						if not index.has(key):
							continue
						for id: int in index[key]:
							var after := turned
							for move: Dictionary in s.c_moves[id]:
								after = s.apply(after, move)
							after = s.apply(after, s.model.inverse(setup))
							if _centres_kept(after, f, c, locked, scheme):
								var out: Array[Dictionary] = [setup]
								out.append_array(s.c_moves[id])
								out.append(s.model.inverse(setup))
								return out
		return none


	## True if `after` keeps every locked centre and has more of face `f` right than now.
	func _centres_kept(after: PackedInt32Array, f: int, c: int, locked: PackedByteArray, scheme: PackedInt32Array) -> bool:
		for t in shape.centres:
			if locked[t] == 1 and after[t] != scheme[shape.face[t]]:
				return false
		var gained := 0
		for t in shape.face_centres[f]:
			gained += int(after[t] == c) - int(col[t] == c)
		return gained > 0


	## The same step with wide turns (Rw) for its inner slices (2R), as people turn them, when that also keeps every finished
	## centre and gains at least one.
	func _prefer_wide(step: Array[Dictionary], f: int, c: int, locked: PackedByteArray, scheme: PackedInt32Array) -> Array[Dictionary]:
		var wide: Array[Dictionary] = []
		var changed := false
		for move in step:
			if int(move.get("depth", 0)) >= 1 and int(move.get("width", 1)) == 1:
				wide.append(shape.model.make_move(move["face"], move["turns"], int(move["depth"]) + 1, 0))
				changed = true
			else:
				wide.append(move)
		if not changed:
			return step
		var after := col
		for move in wide:
			after = shape.apply(after, move)
		return wide if _centres_kept(after, f, c, locked, scheme) else step


	# --- Edges ---

	## How many wings are paired, edge by edge (all = every edge paired): see _slot_score.
	func _edge_metric(c: PackedInt32Array) -> int:
		var s := shape
		var total := 0
		var a := PackedInt32Array()
		var b := PackedInt32Array()
		a.resize(s.n - 2)
		b.resize(s.n - 2)
		for slot in 12:
			for k in s.n - 2:
				a[k] = c[s.slot_a[slot][k]]
				b[k] = c[s.slot_b[slot][k]]
			total += _slot_score(a, b)
		return total


	## The paired wings on one edge, from the colours along it on its two faces. Odd cubes: the wings that match the
	## middle piece. Even cubes: the biggest group of matching pieces, less one. Not "the ones that match the reference
	## piece's place": an outer turn can reverse an edge, which would move that place to another piece and change the
	## count without pairing anything (6×6: steps that "gained" undid each other for ever).
	func _slot_score(a: PackedInt32Array, b: PackedInt32Array) -> int:
		var size := a.size()
		if shape.n % 2 == 1:
			var middle := shape.ref
			var paired := 0
			for k in size:
				if k != middle and a[k] == a[middle] and b[k] == b[middle]:
					paired += 1
			return paired
		var best := 0
		for k in size:
			var same := 0
			for j in size:
				if a[j] == a[k] and b[j] == b[k]:
					same += 1
			best = maxi(best, same)
		return best - 1


	func _edge_max() -> int:
		return 12 * (shape.n - 3)


	func unpaired_edges() -> int:
		var s := shape
		var total := 0
		for slot in 12:
			var on_a := s.slot_a[slot]
			var on_b := s.slot_b[slot]
			for k in on_a.size():
				if col[on_a[k]] != col[on_a[s.ref]] or col[on_b[k]] != col[on_b[s.ref]]:
					total += 1
					break
		return total


	## Pairs of facelets [wing, anchor, ...] that should end up side by side: for every edge's reference piece, the
	## same-coloured sticker of each wing that belongs next to it and isn't there.
	func _edge_targets() -> PackedInt32Array:
		var s := shape
		var out := PackedInt32Array()
		var last := s.n - 3
		for slot in 12:
			var main := _main_piece(slot)
			var ra := col[s.slot_a[slot][main]]
			var rb := col[s.slot_b[slot][main]]
			for k in last + 1:
				if k == main or (col[s.slot_a[slot][k]] == ra and col[s.slot_b[slot][k]] == rb):
					continue
				var orbit := mini(k, last - k)
				for other in 12:
					for k2 in last + 1:
						if mini(k2, last - k2) != orbit or (other == slot and k2 == main):
							continue
						var pa := col[s.slot_a[other][k2]]
						var pb := col[s.slot_b[other][k2]]
						if pa == ra and pb == rb:
							if other != slot:
								out.append(s.slot_a[other][k2])
								out.append(s.slot_a[slot][main])
						elif pa == rb and pb == ra:
							out.append(s.slot_b[other][k2])
							out.append(s.slot_a[slot][main])
		return out


	## The piece on an edge the others are paired to: odd cubes the middle one; even cubes one of the biggest group of
	## matching pieces (the reference place if it is in one), so what counts as progress matches _slot_score.
	func _main_piece(slot: int) -> int:
		var s := shape
		if s.n % 2 == 1:
			return s.ref
		var on_a := s.slot_a[slot]
		var on_b := s.slot_b[slot]
		var best := s.ref
		var best_count := -1
		for k: int in [s.ref] + range(s.n - 2):
			var same := 0
			for j in s.n - 2:
				if col[on_a[j]] == col[on_a[k]] and col[on_b[j]] == col[on_b[k]]:
					same += 1
			if same > best_count:
				best_count = same
				best = k
		return best


	## One pairing step: a few outer turns, then a library macro that pairs something without unpairing more. Tried in
	## order: at most one set-up turn; any number of them that bring one wanted pair together (the last edges often
	## need three or four); every two-turn set-up.
	func _edge_step(thorough: bool = true) -> bool:
		var s := shape
		var targets := _edge_targets()
		if _try_setups(targets, 0, 19):
			return true
		if not thorough:
			return false
		var i := 0
		while i < targets.size():
			if _try_routes(targets[i], targets[i + 1]):
				return true
			i += 2
		return _try_setups(targets, 19, s.setups.size())


	func _try_setups(targets: PackedInt32Array, first: int, last: int) -> bool:
		var s := shape
		for index in range(first, last):
			var setup := s.setups[index]
			var turned := PackedInt32Array()
			var seen := {}
			var i := 0
			while i < targets.size():
				var wing := targets[i]
				var anchor := targets[i + 1]
				i += 2
				for o in setup:
					wing = s.outer_dest[o][wing]
					anchor = s.outer_dest[o][anchor]
				var key := (wing * s.count + anchor) if wing < anchor else (anchor * s.count + wing)
				if not s.e_index.has(key):
					continue
				if turned.is_empty():
					turned = col
					for o in setup:
						turned = s.apply(turned, s.outer[o])
				if _play_first_gain(setup, turned, s.e_index[key], seen):
					return true
		return false


	## Every place the two pieces can be carried to by outer turns (breadth first), until a macro joins them there.
	func _try_routes(wing: int, anchor: int) -> bool:
		var s := shape
		var start := wing * s.count + anchor
		var parent := {start: [-1, -1]}
		var queue := PackedInt32Array([start])
		var head := 0
		while head < queue.size():
			var state := queue[head]
			head += 1
			var w := state / s.count
			var a := state % s.count
			var key := state if w < a else (a * s.count + w)
			if s.e_index.has(key):
				var setup := PackedInt32Array()
				var at := state
				while at != start:
					setup.append(parent[at][1])
					at = parent[at][0]
				setup.reverse()
				var turned := col
				for o in setup:
					turned = s.apply(turned, s.outer[o])
				if _play_first_gain(setup, turned, s.e_index[key]):
					return true
			for o in s.outer.size():
				var next := s.outer_dest[o][w] * s.count + s.outer_dest[o][a]
				if not parent.has(next):
					parent[next] = [state, o]
					queue.append(next)
		return false


	## Plays `setup` and the first of `macros` that leaves more wings paired than before; false if none does.
	## `turned` is the cube after the set-up. Only the edges a macro changes are counted.
	## `seen`: macros already scored on this `turned` (skipped; they gained nothing).
	func _play_first_gain(setup: PackedInt32Array, turned: PackedInt32Array, macros: PackedInt32Array,
			seen: Dictionary = {}) -> bool:
		for id in macros:
			if seen.has(id):
				continue
			seen[id] = true
			if _edge_gain(id, turned) > 0:
				_play_macro(setup, id)
				return true
		return false


	func _play_macro(setup: PackedInt32Array, id: int) -> void:
		for o in setup:
			play(shape.outer[o])
		for move: Dictionary in shape.e_moves[id]:
			play(move)


	## How many more wings an edge macro pairs than it unpairs, on the cube `turned`.
	func _edge_gain(id: int, turned: PackedInt32Array) -> int:
		var s := shape
		var a := _gain_a
		var b := _gain_b
		var source := s.e_source[id]
		var gain := 0
		for slot in s.e_slots[id]:
			var on_a := s.slot_a[slot]
			var on_b := s.slot_b[slot]
			for k in s.n - 2:
				a[k] = turned[on_a[k]]
				b[k] = turned[on_b[k]]
			gain -= _slot_score(a, b)
			for k in s.n - 2:
				a[k] = turned[source[on_a[k]]]
				b[k] = turned[source[on_b[k]]]
			gain += _slot_score(a, b)
		return gain


	## Stuck (every pairing step unpairs as much as it pairs, e.g. a 6×6's last outer wings in a cycle): one step that
	## pairs one wing and unpairs another, when a pairing step follows it. Set-ups `first` to `last` (at most one outer
	## turn: 0-19); far cheaper than _escape, though a whole scan can take a second on a 6×6, so _pair_tick does one
	## set-up a tick.
	func _sideways(first: int = 0, last: int = 19) -> bool:
		var s := shape
		var before := _edge_metric(col)
		var targets := _edge_targets()
		var tried := {}
		for index in range(first, last):
			var setup := s.setups[index]
			var turned := PackedInt32Array()
			var i := 0
			while i < targets.size():
				var wing := targets[i]
				var anchor := targets[i + 1]
				i += 2
				for o in setup:
					wing = s.outer_dest[o][wing]
					anchor = s.outer_dest[o][anchor]
				var key := (wing * s.count + anchor) if wing < anchor else (anchor * s.count + wing)
				if not s.e_index.has(key):
					continue
				if turned.is_empty():
					turned = col
					for o in setup:
						turned = s.apply(turned, s.outer[o])
				for id: int in s.e_index[key]:
					if tried.has(index * 100000 + id) or _edge_gain(id, turned) != 0:
						continue
					tried[index * 100000 + id] = true
					if tried.size() > SIDEWAYS_PROBES * (last - first):
						return false
					var probe := _copy()
					probe._play_macro(setup, id)
					if probe._edge_step(false) and probe._edge_metric(probe.col) > before:
						moves.append_array(probe.moves)
						col = probe.col
						return true
		return false


	## True if the wings of an orbit (`orbit`: the index of its lower wing along an edge; the others are `n - 3 - orbit`)
	## are an odd permutation (centres done). A wing's home is read from its colours: the edge between the two centres
	## of those colours, on the side that keeps its handedness. Pairing keeps it (a face turn moves an orbit in two
	## 4-cycles, a slice is undone), and a paired cube has every orbit as odd as its edges are flipped, so an orbit that
	## differs (odd cubes: from the middle pieces, always even; even cubes: from the reference orbit) can't be paired
	## without swapping two of its wings: the edge parity.
	func wing_parity(orbit: int = 0) -> bool:
		var s := shape
		var sigma := _sigma()
		var perm := PackedInt32Array()
		perm.resize(24)
		for slot in 12:
			for side: int in [-1, 1]:
				var k := orbit if side < 0 else s.n - 3 - orbit
				var fa := sigma[col[s.slot_a[slot][k]]]
				var fb := sigma[col[s.slot_b[slot][k]]]
				var hand := s.slot_hand[slot] * side
				var home: int = s.slot_by_mask.get((1 << fa) | (1 << fb), 0)
				var home_side := hand * s.slot_hand[home] * (1 if fa < fb else -1)
				perm[slot * 2 + (side + 1) / 2] = home * 2 + (home_side + 1) / 2
		return _odd(perm)


	## The orbits whose wings need a swap (the edge parity; see wing_parity).
	func orbits_to_swap() -> PackedInt32Array:
		var s := shape
		var out := PackedInt32Array()
		var reference := wing_parity(s.ref_orbit) if s.ref_orbit >= 0 else false
		for o in s.orbits:
			if o != s.ref_orbit and wing_parity(o) != reference:
				out.append(o)
		return out


	## One pairing step, or one slice of a slower search; false when there's nothing more to pair now (all paired,
	## only the parity's edges left, or stuck: the parity stage's escape takes over). The searches, as in _edge_step:
	## tier 0 at most one set-up turn; when that finds nothing, tier 1 routes one wanted pair a tick, tier 2 the two-turn
	## set-ups, SETUPS_PER_TICK a tick, tier 3 a sideways step, one set-up a tick. Any success starts again at tier 0.
	func _pair_tick() -> bool:
		if _edge_metric(col) >= _edge_max() or unpaired_edges() <= _left:
			return false  # the last edges can't be paired until two wings are swapped: the parity stage
		var found := false
		match _tier:
			0:
				_targets = _edge_targets()
				found = _try_setups(_targets, 0, 19)
				if not found:
					_tier = 1
					_route = 0
				return true
			1:
				if _route < _targets.size():
					found = _try_routes(_targets[_route], _targets[_route + 1])
					_route += 2
				else:
					_tier = 2
					_route = 19
					return true
			2:
				var last := mini(_route + SETUPS_PER_TICK, shape.setups.size())
				found = _try_setups(_targets, _route, last)
				_route = last
				if not found and _route >= shape.setups.size():
					_tier = 3
					_route = 0
					return true
			_:
				if _route >= 19:
					return false
				found = _sideways(_route, _route + 1)
				_route += 1
		if found:
			_tier = 0
		return true


	func _copy() -> _Run:
		var other := _Run.new(shape)
		other.col = col
		return other


	## Stuck without every edge paired: a flip macro that pairs nothing itself but lets the next steps pair more.
	func _escape() -> bool:
		var s := shape
		var before := _edge_metric(col)
		BigCubeSolver.escapes += 1
		for id in s.e_flips:
			var probe := _copy()
			for move: Dictionary in s.e_moves[id]:
				probe.play(move)
			for step in 3:
				if not probe._edge_step(false):
					break
				if probe._edge_metric(probe.col) > before:
					moves.append_array(probe.moves)
					col = probe.col
					return true
		return false


	# --- Parity ---

	## Which face each colour's centre is on.
	func _sigma() -> PackedInt32Array:
		var sigma := PackedInt32Array()
		sigma.resize(6)
		for f in 6:
			sigma[col[shape.face_centres[f][0]]] = f
		return sigma


	## OLL parity: an odd number of flipped edges (an edge is flipped if its U/D colour, or else its F/B colour, isn't
	## on the U/D, else F/B, side of its place). Only meaningful once the centres are done and the edges paired.
	func oll_parity() -> bool:
		var s := shape
		var sigma := _sigma()
		var flips := 0
		for slot in 12:  # fa < fb, and faces come in axis pairs (U D, F B, R L), so fa is the place's leading side
			if sigma[col[s.slot_a[slot][s.ref]]] / 2 > sigma[col[s.slot_b[slot][s.ref]]] / 2:
				flips += 1
		return flips % 2 == 1


	## PLL parity: the edges' permutation is odd while the corners' is even, or the other way round.
	func pll_parity() -> bool:
		var s := shape
		var sigma := _sigma()
		var edges := PackedInt32Array()
		for slot in 12:
			var mask := (1 << sigma[col[s.slot_a[slot][s.ref]]]) | (1 << sigma[col[s.slot_b[slot][s.ref]]])
			edges.append(s.slot_by_mask.get(mask, 0))
		var corner_perm := PackedInt32Array()
		for corner in s.corners:
			var mask := 0
			for i in corner:
				mask |= 1 << sigma[col[i]]
			corner_perm.append(s.corner_by_mask.get(mask, 0))
		return _odd(edges) != _odd(corner_perm)


	func _odd(perm: PackedInt32Array) -> bool:
		var seen := PackedByteArray()
		seen.resize(perm.size())
		var odd := false
		for i in perm.size():
			var length := 0
			var at := i
			while seen[at] == 0:
				seen[at] = 1
				at = perm[at]
				length += 1
			if length > 0 and length % 2 == 0:
				odd = not odd
		return odd


	## Even cubes, every edge paired: OLL parity, then PLL parity, when the reduced cube has them.
	func _fix_parity() -> void:
		var s := shape
		if s.n % 2 == 0:
			if oll_parity():
				for move in s.oll_alg:
					play(move)
			if pll_parity():
				for move in s.pll_alg:
					play(move)


	## The edge parity of one orbit: an unfinished edge is brought to UF (whichever one, and whichever way round, leaves
	## the most paired) and its two wings of that orbit are swapped by `alg`.
	func _swap_wings(alg: Array[Dictionary]) -> void:
		var s := shape
		var uf := s.parity_slot
		var best := PackedInt32Array()
		var best_metric := -1
		for slot in 12:
			var paired := true
			for k in s.slot_a[slot].size():
				if col[s.slot_a[slot][k]] != col[s.slot_a[slot][s.ref]] or col[s.slot_b[slot][k]] != col[s.slot_b[slot][s.ref]]:
					paired = false
			if paired:
				continue
			for target: int in [s.slot_a[uf][s.ref], s.slot_b[uf][s.ref]]:
				var way := s.route(s.slot_a[slot][s.ref], target)
				var after := col
				for o in way:
					after = s.apply(after, s.outer[o])
				for move in alg:
					after = s.apply(after, move)
				var metric := _edge_metric(after)
				if metric > best_metric:
					best_metric = metric
					best = way
		for o in best:
			play(s.outer[o])
		for move in alg:
			play(move)


	# --- The 3×3 stage ---

	func _solve_reduced(method: String, options: Dictionary) -> void:
		var s := shape
		var three := PuzzleShapes.cube(3)
		for p in three.piece_count():
			var colors := three.sticker_colors[p]
			var found := false
			for g in 24:
				var places: PackedInt32Array = s.reduced[p][g]
				var fits := true
				for k in places.size():
					if col[places[k]] != colors[k]:
						fits = false
						break
				if fits:
					three.orientations[p] = g
					found = true
					break
			if not found:
				ok = false
				return
		var carried: Array[Dictionary] = []  # the 3×3 solve's inspection turns (z2 ...) open its first stage here
		for stage: Dictionary in StagedSolver.solve(three, method, options):
			var mapped: Array[Dictionary] = carried.duplicate()
			for move: Dictionary in stage["moves"]:
				var big := _from_three(move)
				mapped.append(big)
				col = s.apply(col, big)
			if stage["id"] == "inspection":
				carried = mapped
				continue
			carried = []
			stages.append({"id": stage["id"], "name": stage["name"], "moves": mapped})
		for f in 6:
			for i in s.count:
				if s.face[i] == f and col[i] != col[s.face_centres[f][0]]:
					ok = false
					return


	## A 3×3 move on the big cube: the outer layers stay outer, the middle layer is every inner layer.
	func _from_three(move: Dictionary) -> Dictionary:
		var n := shape.n
		var depth := int(move.get("depth", 0))
		var last := depth + int(move.get("width", 1)) - 1
		var first_layer := 0 if depth == 0 else (1 if depth == 1 else n - 1)
		var last_layer := 0 if last == 0 else (n - 2 if last == 1 else n - 1)
		return shape.model.make_move(move["face"], move["turns"], last_layer - first_layer + 1, first_layer)
