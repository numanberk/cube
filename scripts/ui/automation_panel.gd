class_name AutomationPanel
extends VBoxContainer
## The shop's "Auto" tab (task 6.3b): one row per auto-buyer (Content.AUTOMATION kinds) with an On/Off switch, and
## auto-Compete's trophy target (− / +). An auto-buyer not bought yet shows which perk opens it. The rules live in
## GameState (run_automation); this only reads Game and calls set_auto / set_auto_compete_at. main.gd shows the tab
## once the "automation" perk is owned and calls refresh() while it's open.

## The steps − / + move auto-Compete's target through.
const COMPETE_STEPS: Array[int] = [1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 200, 300, 500, 750, 1000, 1500,
		2000, 3000, 5000, 7500, 10000]

@onready var _rows: VBoxContainer = %AutoRows

var _row_views: Dictionary = {}  ## kind -> {box, status: Label, toggle: Button, target: Label, minus, plus}


func _ready() -> void:
	_build()
	refresh()


## The perk that opens an auto-buyer ("auto_<kind>").
static func perk_for(kind: String) -> Dictionary:
	for def: Dictionary in Content.PERKS:
		if String(def["effect"].get("system", "")) == "auto_" + kind:
			return def
	return {}


## The next step up (dir 1) or down (dir -1) from `value` in COMPETE_STEPS.
static func step(value: int, dir: int) -> int:
	if dir > 0:
		for s: int in COMPETE_STEPS:
			if s > value:
				return s
		return COMPETE_STEPS.back()
	for i in range(COMPETE_STEPS.size() - 1, -1, -1):
		if COMPETE_STEPS[i] < value:
			return COMPETE_STEPS[i]
	return COMPETE_STEPS[0]


func _build() -> void:
	for kind: String in Content.AUTOMATION["kinds"]:
		var perk := perk_for(kind)
		var row := HBoxContainer.new()
		row.theme_type_variation = &"ColumnsBox"
		var icon := TextureRect.new()
		icon.texture = Content.icon(perk.get("icon", Content.LOCKED_ICON))
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.theme_type_variation = &"TightBox"
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(_label(perk.get("name", kind), &"CardTitle"))
		var status := _label("", &"CardLine")
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(status)
		var views := {"box": row, "status": status}
		if kind == "compete":
			var target_row := HBoxContainer.new()
			var minus := _button("−")
			minus.pressed.connect(func() -> void:
				Game.set_auto_compete_at(step(Game.get_auto_compete_at(), -1))
				refresh())
			var target := _label("", &"CostAffordable")
			target.custom_minimum_size = Vector2(130, 0)
			target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var plus := _button("+")
			plus.pressed.connect(func() -> void:
				Game.set_auto_compete_at(step(Game.get_auto_compete_at(), 1))
				refresh())
			target_row.add_child(minus)
			target_row.add_child(target)
			target_row.add_child(plus)
			text.add_child(target_row)
			views.merge({"target": target, "minus": minus, "plus": plus})
		row.add_child(text)
		var toggle := Button.new()
		toggle.theme_type_variation = &"ToggleChip"
		toggle.toggle_mode = true
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.custom_minimum_size = Vector2(64, 0)
		toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		toggle.toggled.connect(func(on: bool) -> void:
			Game.set_auto(kind, on)
			refresh())
		row.add_child(toggle)
		views["toggle"] = toggle
		_rows.add_child(row)
		_row_views[kind] = views


func refresh() -> void:
	for kind: String in _row_views:
		var views: Dictionary = _row_views[kind]
		var perk := perk_for(kind)
		var unlocked: bool = Game.is_auto_unlocked(kind)
		var on: bool = Game.is_auto_on(kind)
		var toggle: Button = views["toggle"]
		toggle.disabled = not unlocked
		toggle.set_pressed_no_signal(on)
		toggle.text = "On" if on else "Off"
		(views["box"] as Control).modulate.a = 1.0 if unlocked else 0.5
		(views["status"] as Label).text = String(perk.get("description", "")) if unlocked \
				else "Buy %s in Perks (%s trophies) to use it." % [perk.get("name", kind), Num.format(float(perk.get("cost", 0)))]
		if views.has("target"):
			var wanted: int = Game.get_auto_compete_at()
			(views["target"] as Label).text = "at +%s %s" % [Num.format(float(wanted)), "trophy" if wanted == 1 else "trophies"]
			(views["minus"] as Button).disabled = not unlocked
			(views["plus"] as Button).disabled = not unlocked


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"ToggleChip"
	button.custom_minimum_size = Vector2(36, 0)
	return button
