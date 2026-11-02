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
