class_name PuzzleShapes
extends RefCounted
## Builds TwistyModels for each puzzle shape. Cubes now; the Megaminx comes in task 4.4.
##
## Cube coordinates (Godot's): +x = R, +y = U, +z = F (towards the camera), one unit per cubie,
## centred on the origin. Colours follow the standard scheme: white U, yellow D, green F,
## blue B, red R, orange L.

const COLOR_WHITE := 0
const COLOR_YELLOW := 1
const COLOR_GREEN := 2
const COLOR_BLUE := 3
const COLOR_RED := 4
const COLOR_ORANGE := 5

## Sticker colours by colour index. Views use this; the model only stores indices.
const CUBE_COLORS: Array[Color] = [
	Color("#f4f4f4"),  # white
	Color("#ffd500"),  # yellow
	Color("#009e60"),  # green
	Color("#0051ba"),  # blue
	Color("#c41e3a"),  # red
	Color("#ff5800"),  # orange
]

const CUBE_FACES: Array[Dictionary] = [
	{"name": "U", "normal": Vector3(0, 1, 0), "color": COLOR_WHITE},
	{"name": "D", "normal": Vector3(0, -1, 0), "color": COLOR_YELLOW},
	{"name": "F", "normal": Vector3(0, 0, 1), "color": COLOR_GREEN},
	{"name": "B", "normal": Vector3(0, 0, -1), "color": COLOR_BLUE},
	{"name": "R", "normal": Vector3(1, 0, 0), "color": COLOR_RED},
	{"name": "L", "normal": Vector3(-1, 0, 0), "color": COLOR_ORANGE},
]

const MIN_CUBE := 2
const MAX_CUBE := 7

## The 12 standard Megaminx colours, by colour index.
const MEGAMINX_COLORS: Array[Color] = [
	Color("#f4f4f4"),  # white (U)
	Color("#009e60"),  # green
	Color("#c41e3a"),  # red
	Color("#0051ba"),  # dark blue
	Color("#ffd500"),  # yellow
	Color("#7b3fa0"),  # purple
	Color("#8a8f99"),  # grey (D)
	Color("#7fd34e"),  # light green
	Color("#ff6fa8"),  # pink
	Color("#5ec8f2"),  # light blue
	Color("#ff8a00"),  # orange
	Color("#e8d9a8"),  # cream
]
## Megaminx face names by ring: top, the upper ring by angle (F faces the camera), the lower ring, bottom.
const MEGAMINX_UPPER := ["F", "R", "BR", "BL", "L"]
const MEGAMINX_LOWER := ["DR", "DBR", "B", "DBL", "DL"]
const MEGAMINX_INRADIUS := 1.6   ## distance from the centre to each face (a 3×3's half-width is 1.5)
const MEGA_INNER := 0.42         ## size of the centre pentagon on each face (fraction of the face)
const MEGA_EDGE_CUT := 0.3       ## where the corner/edge dividing lines meet each face edge


## Sticker colours for a model (cubes: 6, Megaminx: 12).
static func palette(model: TwistyModel) -> Array[Color]:
	return MEGAMINX_COLORS if model.palette == "megaminx" else CUBE_COLORS


## The model for a puzzle id: "2x2" ... "7x7" (Megaminx in 4.4). Returns null for an unknown id.
static func from_id(id: String) -> TwistyModel:
	var parts := id.split("x")
	if id == "megaminx":
		return megaminx()
	if parts.size() == 2 and parts[0] == parts[1] and parts[0].is_valid_int():
		var n := parts[0].to_int()
		if n >= MIN_CUBE and n <= MAX_CUBE:
			return cube(n)
	return null


## An n×n×n cube (n = 2-7), solved. Only the visible pieces exist: n³ − (n−2)³ of them.
static func cube(n: int) -> TwistyModel:
	assert(n >= MIN_CUBE and n <= MAX_CUBE, "cube size must be 2-7")
	var model := TwistyModel.new()
	model.id = "cube%d" % n
	model.size = n
	model.step_angle = PI / 2.0
	model.shape_key = "cube"
	model.radius = sqrt(3.0) * n / 2.0
	for face: Dictionary in CUBE_FACES:
		model.face_names.append(face["name"])
		model.face_normals.append(face["normal"])
		model.face_colors.append(face["color"])

	var half := (n - 1) / 2.0
	for k in n - 1:
		model.layer_cuts.append(half - k - 0.5)
	model.scramble_widths = maxi(1, n / 2)  # WCA: 4×4/5×5 use Rw, 6×6/7×7 also 3Rw

	for x in n:
		for y in n:
			for z in n:
				var position := Vector3(x - half, y - half, z - half)
				var normals := PackedVector3Array()
				var colors := PackedInt32Array()
				for face: Dictionary in CUBE_FACES:
					if position.dot(face["normal"]) > half - 0.01:
						normals.append(face["normal"])
						colors.append(face["color"])
				if normals.is_empty():
					continue  # an inner piece nobody sees
				model.home_positions.append(position)
				model.sticker_normals.append(normals)
				model.sticker_colors.append(colors)

	model.finish_setup()
	return model


## A Megaminx (a dodecahedron, 12 faces, 72° turns), solved: 12 centres, 30 edges and 20 corners = 62 pieces.
## Layers per face axis: its cap (0), the middle (1) and the opposite cap (2), so the WCA "Pochmann" scramble
## moves R++ / D-- (everything but the opposite cap, 2/5 of a turn) are exact moves. Each piece also gets
## `piece_geometry` (its body and sticker polygons, relative to its home position) for the 3D view.
static func megaminx() -> TwistyModel:
	var model := TwistyModel.new()
	model.id = "megaminx"
	model.size = 0
	model.step_angle = TAU / 5.0
	model.shape_key = "megaminx"
	model.notation_style = "pochmann"
	model.palette = "megaminx"
	var phi := (1.0 + sqrt(5.0)) / 2.0

	# Dodecahedron: face normals are the icosahedron's vertex directions; vertices are the dodecahedron's.
	var raw_normals: Array[Vector3] = []
	for a: float in [1.0, -1.0]:
		for b: float in [phi, -phi]:
			raw_normals.append(Vector3(0, b, a).normalized())  # (0, ±φ, ±1) and its cyclic permutations
			raw_normals.append(Vector3(a, 0, b).normalized())
			raw_normals.append(Vector3(b, a, 0).normalized())
	var raw_vertices: Array[Vector3] = []
	for x: float in [1.0, -1.0]:
		for y: float in [1.0, -1.0]:
			for z: float in [1.0, -1.0]:
				raw_vertices.append(Vector3(x, y, z))
	for a: float in [1.0, -1.0]:
		for b: float in [1.0, -1.0]:
			raw_vertices.append(Vector3(0, a / phi, b * phi))
			raw_vertices.append(Vector3(a / phi, b * phi, 0))
			raw_vertices.append(Vector3(b * phi, 0, a / phi))
	# Turn it so the first normal points up (U), then scale it to MEGAMINX_INRADIUS.
	var up := raw_normals[0]
	var axis := up.cross(Vector3.UP)
	var turn := Basis(axis.normalized(), up.angle_to(Vector3.UP)) if axis.length() > 1e-6 else Basis.IDENTITY
	var inradius_raw := raw_vertices[0].dot(up)
	for v in raw_vertices:
		inradius_raw = maxf(inradius_raw, v.dot(up))
	var scale := MEGAMINX_INRADIUS / inradius_raw
	var normals: Array[Vector3] = []
	for n in raw_normals:
		normals.append((turn * n).normalized())
	var vertices: Array[Vector3] = []
	for v in raw_vertices:
		vertices.append(turn * v * scale)

	# Name the faces: U (top), the upper ring by angle round the vertical (F faces +Z), the lower ring, D.
	var order: Array[int] = []
	var top := 0
	var bottom := 0
	var upper: Array[int] = []
	var lower: Array[int] = []
	for i in normals.size():
		var y := normals[i].y
		if y > 0.9:
			top = i
		elif y < -0.9:
			bottom = i
		elif y > 0.0:
			upper.append(i)
		else:
			lower.append(i)
	var by_angle := func(a: int, b: int) -> bool:
		return _azimuth(normals[a]) < _azimuth(normals[b])
	upper.sort_custom(by_angle)
	lower.sort_custom(by_angle)
	order.append(top)
	order.append_array(upper)
	order.append_array(lower)
	order.append(bottom)
	var names: Array[String] = ["U"]
	names.append_array(_ring_names(upper, normals, MEGAMINX_UPPER))
	names.append_array(_ring_names(lower, normals, MEGAMINX_LOWER))
	names.append("D")
	for k in order.size():
		model.face_names.append(names[k])
		model.face_normals.append(normals[order[k]])
		model.face_colors.append(k)

	# Each face's 5 vertices, in order round its centre.
	var face_vertices: Array = []  # per face (model order): Array[int] of vertex indices
	for f in model.face_normals.size():
		var n := model.face_normals[f]
		var on_face: Array[int] = []
		for i in vertices.size():
			if absf(vertices[i].dot(n) - MEGAMINX_INRADIUS) < 1e-3:
				on_face.append(i)
		var center := n * MEGAMINX_INRADIUS
		var u := (vertices[on_face[0]] - center).normalized()
		var w := n.cross(u)
		on_face.sort_custom(func(a: int, b: int) -> bool:
			var pa := vertices[a] - center
			var pb := vertices[b] - center
			return atan2(pa.dot(w), pa.dot(u)) < atan2(pb.dot(w), pb.dot(u)))
		face_vertices.append(on_face)

	# Pieces: centres, then edges (a pair of vertices), then corners (one vertex). Regions are added below.
	var piece_of := {}  # "c<face>" / "e<v1>_<v2>" / "v<vertex>" -> piece index
	var add_piece := func(key: String, home: Vector3) -> int:
		piece_of[key] = model.home_positions.size()
		model.home_positions.append(home)
		model.sticker_normals.append(PackedVector3Array())
		model.sticker_colors.append(PackedInt32Array())
		model.piece_geometry.append({"stickers": [], "body": [], "apex": home * 0.45})
		return piece_of[key]
	for f in model.face_normals.size():
		add_piece.call("c%d" % f, model.face_normals[f] * MEGAMINX_INRADIUS)
	for f in model.face_normals.size():
		var ring: Array = face_vertices[f]
		for i in 5:
			var a: int = ring[i]
			var b: int = ring[(i + 1) % 5]
			var key := "e%d_%d" % [mini(a, b), maxi(a, b)]
			if not piece_of.has(key):
				add_piece.call(key, (vertices[a] + vertices[b]) / 2.0)
	for i in vertices.size():
		add_piece.call("v%d" % i, vertices[i])

	# Cut each face into a centre pentagon, 5 edge quads and 5 corner kites, and give each region to its piece.
	for f in model.face_normals.size():
		var n := model.face_normals[f]
		var ring: Array = face_vertices[f]
		var center := n * MEGAMINX_INRADIUS
		var corners: Array[Vector3] = []
		var inner: Array[Vector3] = []
		for i in 5:
			corners.append(vertices[ring[i]])
			inner.append(center + (vertices[ring[i]] - center) * MEGA_INNER)
		var near_a: Array[Vector3] = []  # on edge i, near its first corner
		var near_b: Array[Vector3] = []  # on edge i, near its second corner
		for i in 5:
			var a := corners[i]
			var b := corners[(i + 1) % 5]
			near_a.append(a + (b - a) * MEGA_EDGE_CUT)
			near_b.append(a + (b - a) * (1.0 - MEGA_EDGE_CUT))
		_add_region(model, piece_of["c%d" % f], PackedVector3Array(inner), n, f)
		for i in 5:
			var a: int = ring[i]
			var b: int = ring[(i + 1) % 5]
			var edge := piece_of["e%d_%d" % [mini(a, b), maxi(a, b)]] as int
			_add_region(model, edge, PackedVector3Array([inner[i], near_a[i], near_b[i], inner[(i + 1) % 5]]), n, f)
			var corner := piece_of["v%d" % a] as int
			_add_region(model, corner, PackedVector3Array([corners[i], near_a[i], inner[i], near_b[(i + 4) % 5]]), n, f)

	# Layer cuts: halfway between a face's cap (dot = inradius) and the next pieces in, and the same below.
	var next_in := -INF
	var up_normal := model.face_normals[0]
	for p in model.home_positions:
		var d := p.dot(up_normal)
		if d < MEGAMINX_INRADIUS - 1e-3:
			next_in = maxf(next_in, d)
	var cut := (MEGAMINX_INRADIUS + next_in) / 2.0
	model.layer_cuts = PackedFloat32Array([cut, -cut])
	model.scramble_widths = 1
	model.radius = vertices[0].length()
	model.finish_setup()
	return model


static func _azimuth(n: Vector3) -> float:
	return atan2(n.x, n.z)


## Names a ring of 5 faces (sorted by angle) starting from the one nearest the front (+Z), going round.
static func _ring_names(ring: Array[int], normals: Array[Vector3], names: Array) -> Array[String]:
	var start := 0
	var best := INF
	for k in ring.size():
		var off := absf(_azimuth(normals[ring[k]]))
		if off < best:
			best = off
			start = k
	var result: Array[String] = []
	result.resize(5)
	for k in 5:
		result[(start + k) % 5] = names[k]
	return result


## One face region of a Megaminx piece: a sticker (shrunk a little, lifted off the face) and a body polygon,
## stored relative to the piece's home position.
static func _add_region(model: TwistyModel, piece: int, polygon: PackedVector3Array, normal: Vector3, color: int) -> void:
	var home := model.home_positions[piece]
	var centroid := Vector3.ZERO
	for p in polygon:
		centroid += p
	centroid /= polygon.size()
	var sticker := PackedVector3Array()
	var body := PackedVector3Array()
	for p in polygon:
		sticker.append(centroid + (p - centroid) * 0.84 + normal * 0.012 - home)
		body.append(centroid + (p - centroid) * 0.97 - home)
	model.sticker_normals[piece].append(normal)
	model.sticker_colors[piece].append(color)
	var geometry: Dictionary = model.piece_geometry[piece]
	(geometry["stickers"] as Array).append({"polygon": sticker, "normal": normal, "color": color})
	(geometry["body"] as Array).append(body)
	geometry["apex"] = home * 0.45 - home
