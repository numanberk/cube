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


## An n×n×n cube (n = 2-7), solved. Only the visible pieces exist: n³ − (n−2)³ of them.
static func cube(n: int) -> TwistyModel:
	assert(n >= MIN_CUBE and n <= MAX_CUBE, "cube size must be 2-7")
	var model := TwistyModel.new()
	model.id = "cube%d" % n
	model.size = n
	model.step_angle = PI / 2.0
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
