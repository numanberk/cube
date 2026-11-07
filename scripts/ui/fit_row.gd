class_name FitRow
extends Container
## A row that never makes the window wider (task V.1): children are laid out left to right at their minimum width,
## vertically centred, and a child that doesn't fit whole is hidden from view (not cut in half) until there's room.
## Its own minimum width is 0, so it can sit between fixed-size controls. Hidden children don't take part.

## Space between children, in pixels.
@export var separation := 12.0


func _get_minimum_size() -> Vector2:
	var height := 0.0
	for child in _children():
		height = maxf(height, child.get_combined_minimum_size().y)
	return Vector2(0.0, height)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_lay_out()


## The children that fit, in order (for tests): every one after the first that doesn't fit is left out too.
func fitting_children() -> Array[Control]:
	var fitting: Array[Control] = []
	var x := 0.0
	for child in _children():
		var width := child.get_combined_minimum_size().x
		if x + width > size.x + 0.5:
			break
		fitting.append(child)
		x += width + separation
	return fitting


func _lay_out() -> void:
	var fitting := fitting_children()
	var x := 0.0
	for child in _children():
		var child_size := child.get_combined_minimum_size()
		if child in fitting:
			fit_child_in_rect(child, Rect2(Vector2(x, (size.y - child_size.y) / 2.0), child_size))
			child.modulate.a = 1.0
			x += child_size.x + separation
		else:
			fit_child_in_rect(child, Rect2(Vector2(size.x, 0.0), child_size))  # parked past the edge (clipped)
			child.modulate.a = 0.0


func _children() -> Array[Control]:
	var list: Array[Control] = []
	for child in get_children():
		if child is Control and (child as Control).visible and not (child as Control).top_level:
			list.append(child as Control)
	return list
