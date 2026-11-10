class_name PuzzleMeshes
extends RefCounted
## Meshes for puzzle pieces, made in code (no imported models).


## A box with rounded edges and corners, centred on the origin.
## `half` = half the edge length, `radius` = edge rounding, `steps` = segments per rounded edge.
static func rounded_box(half: float, radius: float, steps: int = 3) -> ArrayMesh:
	var inner := half - radius
	# Grid coordinates along one face: curve (steps), flat middle (1), curve (steps).
	var coords := PackedFloat32Array()
	for i in steps + 1:
		coords.append(lerpf(-half, -inner, float(i) / steps))
	for i in range(1, steps + 1):
		coords.append(lerpf(inner, half, float(i) / steps))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for axis_index in 3:
		for sign_value: float in [1.0, -1.0]:
			var normal := axes[axis_index] * sign_value
			var u_axis := axes[(axis_index + 1) % 3]
			var v_axis := axes[(axis_index + 2) % 3]
			for i in coords.size() - 1:
				for j in coords.size() - 1:
					var a := _round_point(normal * half + u_axis * coords[i] + v_axis * coords[j], inner, radius)
					var b := _round_point(normal * half + u_axis * coords[i + 1] + v_axis * coords[j], inner, radius)
					var c := _round_point(normal * half + u_axis * coords[i + 1] + v_axis * coords[j + 1], inner, radius)
					var d := _round_point(normal * half + u_axis * coords[i] + v_axis * coords[j + 1], inner, radius)
					# Godot's front faces are clockwise when seen from outside.
					if sign_value > 0.0:
						_add_quad(st, a, d, c, b, inner)
					else:
						_add_quad(st, a, b, c, d, inner)
	return st.commit()


## A box of any proportions with rounded edges and corners (the cubing mat under the puzzle, V.3), centred on the
## origin. `half` = half size per axis; every half must be larger than `radius`.
static func rounded_slab(half: Vector3, radius: float, steps: int = 3) -> ArrayMesh:
	var inner := half - Vector3.ONE * radius
	var coords: Array[PackedFloat32Array] = []  # per axis: curve (steps), flat middle (1), curve (steps)
	for axis in 3:
		var line := PackedFloat32Array()
		for i in steps + 1:
			line.append(lerpf(-half[axis], -inner[axis], float(i) / steps))
		for i in steps + 1:  # from +inner itself, so the flat middle is one segment and both curves are alike
			line.append(lerpf(inner[axis], half[axis], float(i) / steps))
		coords.append(line)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for axis_index in 3:
		for sign_value: float in [1.0, -1.0]:
			var normal := axes[axis_index] * sign_value
			var u_index := (axis_index + 1) % 3
			var v_index := (axis_index + 2) % 3
			var us := coords[u_index]
			var vs := coords[v_index]
			for i in us.size() - 1:
				for j in vs.size() - 1:
					var corners: Array[Vector3] = []
					for uv: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]:
						var p := normal * half[axis_index] + axes[u_index] * us[uv.x] + axes[v_index] * vs[uv.y]
						var core := p.clamp(-inner, inner)
						corners.append(core + (p - core).normalized() * radius)
					# Godot's front faces are clockwise when seen from outside.
					var order := PackedInt32Array([0, 3, 2, 0, 2, 1]) if sign_value > 0.0 else PackedInt32Array([0, 1, 2, 0, 2, 3])
					for k in order:
						var q := corners[k]
						st.set_normal((q - q.clamp(-inner, inner)).normalized())
						st.add_vertex(q)
	return st.commit()


## A flat rounded rectangle in the XY plane facing +Z, centred on the origin (for stickers).
static func rounded_rect(half: float, radius: float, segments: int = 4) -> ArrayMesh:
	var inner := half - radius
	var outline := PackedVector3Array()
	var corners: Array[Vector2] = [Vector2(inner, inner), Vector2(-inner, inner), Vector2(-inner, -inner), Vector2(inner, -inner)]
	for corner_index in 4:
		var start_angle := corner_index * PI / 2.0
		for s in segments + 1:
			var angle := start_angle + PI / 2.0 * float(s) / segments
			var p := corners[corner_index] + Vector2(cos(angle), sin(angle)) * radius
			outline.append(Vector3(p.x, p.y, 0.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	for i in outline.size():
		st.add_vertex(Vector3.ZERO)  # clockwise from the front, so +Z is the front face
		st.add_vertex(outline[(i + 1) % outline.size()])
		st.add_vertex(outline[i])
	return st.commit()


static func _round_point(p: Vector3, inner: float, radius: float) -> Vector3:
	var core := p.clamp(Vector3.ONE * -inner, Vector3.ONE * inner)
	return core + (p - core).normalized() * radius


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inner: float) -> void:
	for p: Vector3 in [a, b, c, a, c, d]:
		var core := p.clamp(Vector3.ONE * -inner, Vector3.ONE * inner)
		st.set_normal((p - core).normalized())
		st.add_vertex(p)


## A piece of a shaped puzzle (the Megaminx) from TwistyModel.piece_geometry: surface 0 is the dark body (each face
## region as a flat cap plus sides down to an inner apex), surface 1 the coloured stickers (vertex colours).
## Normals face away from the piece's middle, so it doesn't matter which way the polygons wind.
static func shaped_piece(geometry: Dictionary, colors: Array[Color], body_material: Material, sticker_material: Material) -> ArrayMesh:
	var apex: Vector3 = geometry["apex"]
	var mesh := ArrayMesh.new()
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	for polygon: PackedVector3Array in geometry["body"]:
		var centroid := Vector3.ZERO
		for p in polygon:
			centroid += p
		centroid /= polygon.size()
		var inside := (centroid + apex) / 2.0
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			_triangle(body, centroid, a, b, inside)  # the cap
			_triangle(body, a, b, apex, inside)       # a side, down to the apex
	body.set_material(body_material)
	body.commit(mesh)
	var stickers := SurfaceTool.new()
	stickers.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sticker: Dictionary in geometry["stickers"]:
		var polygon: PackedVector3Array = sticker["polygon"]
		var normal: Vector3 = sticker["normal"]
		stickers.set_color(colors[int(sticker["color"])])
		var centroid := Vector3.ZERO
		for p in polygon:
			centroid += p
		centroid /= polygon.size()
		for i in polygon.size():
			for p: Vector3 in [centroid, polygon[i], polygon[(i + 1) % polygon.size()]]:
				stickers.set_normal(normal)
				stickers.add_vertex(p)
	stickers.set_material(sticker_material)
	stickers.commit(mesh)
	return mesh


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot((a + b + c) / 3.0 - inside) < 0.0:
		normal = -normal
	for p: Vector3 in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(p)
