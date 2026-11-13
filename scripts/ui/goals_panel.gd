class_name GoalsPanel
extends Control
## The Goals screen (tasks 7.1b, 7.2b, 7.3b, 7.4b): one overlay with three tabs.
##   Achievements: the x/y bar and one card per achievement row (its tiers, the next one's text and a bar towards it),
##     so the list works as a map of the game (PLAN §4.6). A helper not met yet shows as "???".
##   Collection: the Comp Kit's five slots (click a slot then a card, click a card, or drag a card onto a slot; "Auto"
##     lets a slot fill itself again) and the brand sets, beside every Cube Collection item (owned, or a "???" card).
##   Stats: Game.get_stats(), lifetime and this run, and Solves per puzzle.
## Reads Game and calls its public methods (equip, set_slot_auto); no rules here. Uses Game by name, so tests use it
## untyped (CLAUDE.md "Testing gotcha"). main.gd opens it from the top bar; Escape, × or a click outside close it.

signal closed

const StickerScene := preload("res://scenes/icon_sticker.tscn")
const ACHIEVEMENTS_TAB := 0
const COLLECTION_TAB := 1
const STATS_TAB := 2
const TAB_ICONS: Array[String] = ["federation_rankings", "small_cubes", "stackmat"]
const REFRESH_INTERVAL := 0.5
const ACHIEVEMENT_COLUMNS := 2
const ITEM_COLUMNS := 6
const ITEM_SIZE := Vector2(110, 134)
const SLOT_SIZE := Vector2(330, 52)
const KIT_WIDTH := 340.0
const PIP_SIZE := Vector2(8, 8)
const BAR_HEIGHT := 5.0
const ITEM_CONTENT_TOP := 23.0  ## room for the "MAIN CUBE" badge above an item's icon
## Rarity -> the sticker colour its cards wear (Common white, Rare blue, Epic purple, Legendary gold).
const RARITY_CATEGORY := {"common": &"station", "rare": &"helpers", "epic": &"lab", "legendary": &"trophies"}
## Effect type -> what it multiplies, for item and set texts.
const EFFECT_NOUNS := {"tap_mult": "tap moves", "helper_mult": "helper moves", "solve_value_mult": "Solves per solve",
		"global_mult": "all moves", "mastery_xp_mult": "mastery XP", "building_mult": "%s moves", "puzzle_mult": "%s moves"}
const BOOLEAN_TYPES := ["puzzle", "method", "drill_set"]  ## achievements with nothing to count (done or not)

@onready var _dim: ColorRect = %Dim
@onready var _panel: Control = %Panel
@onready var _close: Button = %CloseButton
@onready var _pages: TabContainer = %Pages
@onready var _achievement_chip: StatChip = %AchievementChip
@onready var _collection_chip: StatChip = %CollectionChip

var selected_slot := ""            ## the kit slot picked to fill ("" = none)
var _refresh_left := 0.0
var _achievement_rows: Dictionary = {}  ## row id -> {defs, card, icon, name, count, text, bar, value}
var _achievement_summary: Label
var _achievement_bar: ProgressBar
var _achievement_bonus: Label
var _item_cards: Dictionary = {}   ## item id -> {card, icon, name, pips, badge, frame}
var _slot_views: Dictionary = {}   ## slot id -> {card, icon, item, passive, auto, frame}
var _set_lines: Dictionary = {}    ## brand -> Label
var _collection_summary: Label
var _stat_values: Dictionary = {}  ## stat key -> Label
var _puzzle_rows: Dictionary = {}  ## puzzle id -> {name, value, bar}


func _ready() -> void:
	_close.pressed.connect(close)
	_dim.gui_input.connect(_on_dim_input)
	for i in TAB_ICONS.size():
		_pages.set_tab_icon(i, Content.icon(TAB_ICONS[i]))
	_pages.tab_changed.connect(func(_tab: int) -> void: refresh())
	_build_achievements()
	_build_collection()
	_build_stats()
	Game.kit_changed.connect(func() -> void:
		if visible:
			_refresh_collection())


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		refresh()


## Opens on `tab` (ACHIEVEMENTS_TAB, COLLECTION_TAB, STATS_TAB; -1 keeps the last one).
func open(tab: int = -1) -> void:
	if tab >= 0:
		_pages.current_tab = tab
	selected_slot = ""
	refresh()
	UiFx.open_panel(self, _dim, _panel)


func close() -> void:
	if not visible or UiFx.is_closing(self):
		return
	selected_slot = ""
	UiFx.close_panel(self, _dim, _panel)
	closed.emit()


func current_tab() -> int:
	return _pages.current_tab


## Updates the header and the open tab.
func refresh() -> void:
	_refresh_left = REFRESH_INTERVAL
	var achievements: Dictionary = Game.get_achievement_progress()
	_achievement_chip.set_stat("%d/%d" % [achievements["earned"], achievements["total"]], "achievements")
	var items: Dictionary = Game.get_collection_progress()
	_collection_chip.set_stat("%d/%d" % [items["owned"], items["total"]], "items")
	match _pages.current_tab:
		ACHIEVEMENTS_TAB:
			_refresh_achievements()
		COLLECTION_TAB:
			_refresh_collection()
		STATS_TAB:
			_refresh_stats()


# --- Achievements (7.1b) ---------------------------------------------------------------

func _build_achievements() -> void:
	var page: VBoxContainer = %Achievements
	var top := HBoxContainer.new()
	top.theme_type_variation = &"ColumnsBox"
	page.add_child(top)
	_achievement_summary = _label(&"CardTitle")
	top.add_child(_achievement_summary)
	_achievement_bar = _bar()
	top.add_child(_achievement_bar)
	_achievement_bonus = _label(&"DimLabel")
	top.add_child(_achievement_bonus)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.theme_type_variation = &"UpgradeGrid"
	grid.columns = ACHIEVEMENT_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var order: Array[String] = []
	var rows := {}
	for def: Dictionary in Content.get_achievements():
		var row := String(def["row"])
		if not rows.has(row):
			rows[row] = []
			order.append(row)
		(rows[row] as Array).append(def)
	for row: String in order:
		var view := _achievement_card(rows[row])
		grid.add_child(view["card"])
		_achievement_rows[row] = view


func _achievement_card(defs: Array) -> Dictionary:
	var card := PanelContainer.new()
	card.theme_type_variation = &"ItemCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	card.add_child(row)
	var icon: IconSticker = StickerScene.instantiate()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = Content.icon(String(defs[0]["icon"]))
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.theme_type_variation = &"TightBox"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var line := HBoxContainer.new()
	text.add_child(line)
	var name := _label(&"CardTitle")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name)
	var count := _label(&"FaintLabel")
	line.add_child(count)
	var description := _label(&"CardLine")
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(description)
	var bar_line := HBoxContainer.new()
	text.add_child(bar_line)
	var bar := _bar()
	bar_line.add_child(bar)
	var value := _label(&"FaintLabel")
	bar_line.add_child(value)
	return {"defs": defs, "card": card, "icon": icon, "name": name, "count": count, "text": description, "bar": bar,
			"value": value}


func _refresh_achievements() -> void:
	var progress: Dictionary = Game.get_achievement_progress()
	var earned_total := int(progress["earned"])
	_achievement_summary.text = "%d / %d achievements" % [earned_total, int(progress["total"])]
	_achievement_bar.value = float(earned_total) / maxf(1.0, float(progress["total"]))
	var bonus := roundi(float(Content.ACHIEVEMENTS["bonus"]) * earned_total * 100.0)
	_achievement_bonus.text = "+%d %% trophies per championship%s" % [bonus,
			"" if Game.has_won_championship() else " (from your second)"]
	_achievement_bonus.tooltip_text = "Each achievement adds +%d %% trophies to every World Championship, from the second one on." \
			% roundi(float(Content.ACHIEVEMENTS["bonus"]) * 100.0)
	for row: String in _achievement_rows:
		_refresh_achievement_row(_achievement_rows[row])


func _refresh_achievement_row(view: Dictionary) -> void:
	var defs: Array = view["defs"]
	var earned := 0
	var next: Dictionary = {}
	for def: Dictionary in defs:
		if Game.is_achievement_earned(def["id"]):
			earned += 1
		elif next.is_empty():
			next = def
	var first: Dictionary = defs[0]
	var hidden: bool = first["type"] == "helper" and earned == 0 and not Game.is_building_unlocked(String(first["target"]))
	var shown: Dictionary = defs[defs.size() - 1] if next.is_empty() else next
	var icon: IconSticker = view["icon"]
	icon.silhouette = hidden
	icon.category = &"locked" if hidden else &"trophies"
	icon.muted = earned == 0 and not hidden
	var name: Label = view["name"]
	var count: Label = view["count"]
	var text: Label = view["text"]
	var bar: ProgressBar = view["bar"]
	var value: Label = view["value"]
	name.text = "???" if hidden else String(shown["name"]) + ("  ✓" if next.is_empty() else "")
	count.text = "%d/%d" % [earned, defs.size()] if defs.size() > 1 else ""
	text.text = "A helper you haven't met yet." if hidden else Content.describe_achievement(shown)
	text.tooltip_text = text.text
	bar.value = 1.0 if next.is_empty() else achievement_fraction(next)
	value.text = "" if next.is_empty() or hidden else achievement_value_text(next)


## How far an achievement is, 0..1 (its bar).
static func achievement_fraction(def: Dictionary) -> float:
	var now: float = Game.get_achievement_value(def)
	var target := float(def["value"])
	if def["type"] == "hand_tier":  # tiers count from -1 (none yet): Bronze is 0
		return clampf((now + 1.0) / (target + 1.0), 0.0, 1.0)
	if target <= 0.0:
		return 1.0 if now >= target else 0.0
	return clampf(now / target, 0.0, 1.0)


## "5.20K / 10.0K", "12m 3s / 1h 0m"; "" for the done-or-not ones.
static func achievement_value_text(def: Dictionary) -> String:
	var type := String(def["type"])
	if type in BOOLEAN_TYPES:
		return ""
	var now: float = Game.get_achievement_value(def)
	var target := float(def["value"])
	match type:
		"time_played":
			return "%s / %s" % [Num.format_duration(now), Num.format_duration(target)]
		"hand_tier":
			return ""
		"mastery", "perks", "upgrades", "championships", "research", "tracks", "drill_cases", "helper":
			return "%d / %d" % [int(now), int(target)]
	return "%s / %s" % [Num.format(maxf(0.0, now)), Num.format(target)]


# --- Collection and Comp Kit (7.3b, 7.4b) ---------------------------------------------------

func _build_collection() -> void:
	var page: HBoxContainer = %Collection
	var kit_scroll := ScrollContainer.new()  # never taller than the page, whatever the font
	kit_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	kit_scroll.custom_minimum_size = Vector2(KIT_WIDTH + 8.0, 0)
	page.add_child(kit_scroll)
	var kit := VBoxContainer.new()
	kit.custom_minimum_size = Vector2(KIT_WIDTH, 0)
	kit_scroll.add_child(kit)
	var title := HBoxContainer.new()
	kit.add_child(title)
	var kit_title := _label(&"CardTitle", "Comp Kit")
	kit_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(kit_title)
	title.add_child(_label(&"FaintLabel", "click a slot, then a card, or drag"))
	for slot: Dictionary in Content.COMP_KIT["slots"]:
		var view := _slot_card(slot)
		kit.add_child(view["card"])
		_slot_views[slot["id"]] = view
	kit.add_child(_label(&"CardTitle", "Brand sets"))
	var sets := VBoxContainer.new()
	sets.theme_type_variation = &"TightBox"
	kit.add_child(sets)
	for def: Dictionary in Content.COMP_KIT["sets"]:
		if not _set_lines.has(def["brand"]):
			var line := _label(&"FaintLabel")
			line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			line.custom_minimum_size = Vector2(KIT_WIDTH, 0)
			sets.add_child(line)
			_set_lines[def["brand"]] = line
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(right)
	_collection_summary = _label(&"CardLine")
	right.add_child(_collection_summary)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var grid := GridContainer.new()
	grid.theme_type_variation = &"UpgradeGrid"
	grid.columns = ITEM_COLUMNS
	scroll.add_child(grid)
	for item: Dictionary in Content.COLLECTION["items"]:
		var view := _item_card(item)
		grid.add_child(view["card"])
		_item_cards[item["id"]] = view


func _item_card(item: Dictionary) -> Dictionary:
	var id := String(item["id"])
	var card := Button.new()
	card.theme_type_variation = &"ShopCard"
	card.custom_minimum_size = ITEM_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(press_item.bind(id))
	card.set_drag_forwarding(_item_drag_data.bind(id), Callable(), Callable())
	var box := VBoxContainer.new()
	box.theme_type_variation = &"TightBox"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_top = ITEM_CONTENT_TOP
	box.offset_left = 4.0
	box.offset_right = -4.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var icon: IconSticker = StickerScene.instantiate()
	icon.custom_minimum_size = Vector2(46, 46)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = Content.icon(String(item["icon"]))
	box.add_child(icon)
	var name := _label(&"CardLine")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.max_lines_visible = 2
	name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(name)
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in int(Content.COLLECTION["max_stars"]):
		var pip := Panel.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	box.add_child(pips)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var frame := Panel.new()
	frame.theme_type_variation = &"TileFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(frame)
	var badge := _label(&"ChoiceBadge")
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.position = Vector2(4, 4)
	badge.visible = false
	card.add_child(badge)
	return {"card": card, "icon": icon, "name": name, "pips": pips, "badge": badge, "frame": frame}


func _slot_card(slot: Dictionary) -> Dictionary:
	var id := String(slot["id"])
	var card := Button.new()
	card.theme_type_variation = &"ShopCard"
	card.custom_minimum_size = SLOT_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(select_slot.bind(id))
	card.set_drag_forwarding(_slot_drag_data.bind(id), _can_drop_on_slot.bind(id), _drop_on_slot.bind(id))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8.0
	row.offset_right = -8.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon: IconSticker = StickerScene.instantiate()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.theme_type_variation = &"TightBox"
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var item := _label(&"CardTitle")
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(item)
	var passive := _label(&"CardLine")
	passive.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(passive)
	var auto := Button.new()
	auto.theme_type_variation = &"ToggleChip"
	auto.toggle_mode = true
	auto.focus_mode = Control.FOCUS_NONE
	auto.text = "Auto"
	auto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	auto.tooltip_text = "On: this slot fills itself with your best %s." % String(slot["kind"])
	auto.toggled.connect(set_slot_auto.bind(id))
	row.add_child(auto)
	var frame := Panel.new()
	frame.theme_type_variation = &"TileFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.visible = false
	card.add_child(frame)
	return {"card": card, "icon": icon, "item": item, "passive": passive, "auto": auto, "frame": frame, "def": slot}


func _refresh_collection() -> void:
	var progress: Dictionary = Game.get_collection_progress()
	_collection_summary.text = "%d / %d items  ·  %d / %d stars  ·  kit items give their full bonus, the rest %d %%" \
			% [progress["owned"], progress["total"], progress["stars"], progress["max_stars"],
			roundi(float(Content.COMP_KIT["owned_share"]) * 100.0)]
	_collection_summary.tooltip_text = "Items drop from Golden Scrambles solved in time, World Championships and, after your first championship, achievements. A second copy adds a star."
	var kit: Dictionary = Game.get_kit()
	var selected_kind := String(Content.get_kit_slot(selected_slot).get("kind", ""))
	for id: String in _item_cards:
		_refresh_item_card(id, _item_cards[id], kit, selected_kind)
	for slot: String in _slot_views:
		_refresh_slot(slot, _slot_views[slot], kit)
	var counts: Dictionary = Game.get_kit_brand_counts()
	var active: Array[Dictionary] = Game.get_active_kit_sets()
	for brand: String in _set_lines:
		var line: Label = _set_lines[brand]
		var have := int(counts.get(brand, 0))
		var on: Dictionary = {}
		var goal: Dictionary = {}
		for def: Dictionary in Content.COMP_KIT["sets"]:
			if def["brand"] != brand:
				continue
			if active.has(def):
				on = def
			elif goal.is_empty() and int(def["pieces"]) > have:
				goal = def
		var shown: Dictionary = on if goal.is_empty() else goal
		line.text = "%s%s %d/%d · %s: %s" % ["✓ " if not on.is_empty() else "", brand.capitalize(), have,
				int(shown["pieces"]), shown["name"], effect_text(shown["effect"])]
		if not on.is_empty() and not goal.is_empty():
			line.text = "✓ %s %d · %s: %s (%d: %s)" % [brand.capitalize(), have, on["name"], effect_text(on["effect"]),
					int(goal["pieces"]), effect_text(goal["effect"])]
		line.theme_type_variation = &"CardLine" if not on.is_empty() else &"FaintLabel"
		line.tooltip_text = line.text


func _refresh_item_card(id: String, view: Dictionary, kit: Dictionary, selected_kind: String) -> void:
	var item := Content.get_collection_item(id)
	var stars: int = Game.get_collection_stars(id)
	var owned := stars > 0
	var card: Button = view["card"]
	var icon: IconSticker = view["icon"]
	var category: StringName = RARITY_CATEGORY.get(item["rarity"], &"station")
	icon.silhouette = not owned
	icon.category = category if owned else &"locked"
	(view["name"] as Label).text = String(item["name"]) if owned else "???"
	var pips: HBoxContainer = view["pips"]
	for i in pips.get_child_count():
		(pips.get_child(i) as Panel).theme_type_variation = &"PipOn" if i < stars else &"Pip"
	pips.visible = owned
	var in_slot := ""
	for slot: String in kit:
		if kit[slot] == id:
			in_slot = slot
	var badge: Label = view["badge"]
	badge.visible = in_slot != ""
	badge.text = String(Content.get_kit_slot(in_slot).get("name", "")).to_upper() if in_slot != "" else ""
	var frame_colour := IconSticker.colour_of(self, category)
	frame_colour.a = (1.0 if in_slot != "" else 0.55) if owned else 0.15
	(view["frame"] as Panel).self_modulate = frame_colour
	var fits: bool = selected_kind == "" or item["kind"] == selected_kind
	card.modulate.a = (1.0 if fits else 0.35) if owned else (0.6 if fits else 0.25)
	card.tooltip_text = item_tooltip(id)


func _refresh_slot(slot: String, view: Dictionary, kit: Dictionary) -> void:
	var def: Dictionary = view["def"]
	var id := String(kit.get(slot, ""))
	var icon: IconSticker = view["icon"]
	var item := Content.get_collection_item(id)
	(view["item"] as Label).text = String(item["name"]) if id != "" else "Empty"
	var line := item_effect_text(id) if id != "" else ("nothing of this kind yet" if not _owns_kind(String(def["kind"]))
			else "click, then pick a %s" % def["kind"])
	(view["passive"] as Label).text = "%s  ·  %s" % [def["name"], line]
	icon.texture = Content.icon(String(item.get("icon", "locked")))
	icon.silhouette = id == ""
	icon.category = RARITY_CATEGORY.get(item.get("rarity", ""), &"locked") if id != "" else &"locked"
	var auto: Button = view["auto"]
	auto.set_pressed_no_signal(not Game.is_slot_manual(slot))
	(view["frame"] as Panel).visible = selected_slot == slot
	(view["frame"] as Panel).self_modulate = IconSticker.colour_of(self, &"trophies")
	(view["card"] as Button).tooltip_text = "%s (%s). Click it, then a card; or drag a card here.%s" % [def["name"], def["kind"],
			"" if id == "" else "\n" + item_tooltip(id)]


func _owns_kind(kind: String) -> bool:
	for item: Dictionary in Content.COLLECTION["items"]:
		if item["kind"] == kind and Game.get_collection_stars(String(item["id"])) > 0:
			return true
	return false


## A click on a collection card: into the selected slot (if it fits), else into a slot of its kind (a cube already in
## one cube slot goes to the other). Unowned cards do nothing. Returns true if the kit changed.
func press_item(id: String) -> bool:
	var item := Content.get_collection_item(id)
	if item.is_empty() or Game.get_collection_stars(id) <= 0:
		return false
	var target := ""
	var selected := Content.get_kit_slot(selected_slot)
	if not selected.is_empty() and selected["kind"] == item["kind"]:
		target = selected_slot
	else:
		var kit: Dictionary = Game.get_kit()
		for slot: Dictionary in Content.COMP_KIT["slots"]:
			if slot["kind"] != item["kind"]:
				continue
			if kit.get(slot["id"], "") == id:
				continue  # already here: try the kind's other slot
			target = slot["id"]
			break
	selected_slot = ""
	if target != "" and Game.get_kit().get(target, "") == id:
		target = ""  # already there: nothing to do (an equip would switch the slot's Auto off)
	var changed := target != "" and bool(Game.equip(target, id))
	refresh()
	return changed


## Picks a slot to fill (a second click on it un-picks it).
func select_slot(slot: String) -> void:
	selected_slot = "" if selected_slot == slot else slot
	refresh()


func set_slot_auto(on: bool, slot: String) -> void:
	if on:
		Game.set_slot_auto(slot)
	else:
		Game.equip(slot, String(Game.get_kit().get(slot, "")))  # keep what's there, chosen by hand from now on
	refresh()


func _item_drag_data(_at: Vector2, id: String) -> Variant:
	if Game.get_collection_stars(id) <= 0:
		return null
	_set_drag_preview(id)
	return {"collection_item": id}


func _slot_drag_data(_at: Vector2, slot: String) -> Variant:
	var id := String(Game.get_kit().get(slot, ""))
	if id == "":
		return null
	_set_drag_preview(id)
	return {"collection_item": id}


func _can_drop_on_slot(_at: Vector2, data: Variant, slot: String) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("collection_item"):
		return false
	var item := Content.get_collection_item(String(data["collection_item"]))
	return not item.is_empty() and item["kind"] == Content.get_kit_slot(slot).get("kind", "")


func _drop_on_slot(_at: Vector2, data: Variant, slot: String) -> void:
	if _can_drop_on_slot(Vector2.ZERO, data, slot) and Game.get_kit().get(slot, "") != data["collection_item"]:
		Game.equip(slot, String(data["collection_item"]))
		selected_slot = ""
		refresh()


func _set_drag_preview(id: String) -> void:
	var item := Content.get_collection_item(id)
	var preview: IconSticker = StickerScene.instantiate()
	preview.custom_minimum_size = Vector2(52, 52)
	preview.size = Vector2(52, 52)
	preview.texture = Content.icon(String(item["icon"]))
	preview.category = RARITY_CATEGORY.get(item["rarity"], &"station")
	set_drag_preview(preview)


## The tooltip of an item: name, brand · rarity · kind, its stars and bonus, or "???" with where drops come from.
static func item_tooltip(id: String) -> String:
	var item := Content.get_collection_item(id)
	var rarity := String(Content.get_rarity(String(item["rarity"])).get("name", ""))
	if Game.get_collection_stars(id) <= 0:
		return "??? (a %s %s)\nNot found yet. Golden Scrambles, championships and (after your first championship) achievements drop items." % [rarity, item["kind"]]
	return "%s\n%s · %s · %s\n%d / %d stars: %s" % [item["name"], String(item["brand"]).capitalize(), rarity, item["kind"],
			Game.get_collection_stars(id), int(Content.COLLECTION["max_stars"]), item_effect_text(id, true)]


## "+4 % 3×3 moves" (in the kit), or "+1 % 3×3 moves (+4 % in the kit)".
static func item_effect_text(id: String, long: bool = false) -> String:
	var item := Content.get_collection_item(id)
	var full := Content.get_item_per_star(item) * Game.get_collection_stars(id)
	var noun := effect_noun(item["effect"])
	if Game.is_equipped(id):
		return "+%s %% %s%s" % [_percent(full), noun, " (in your kit)" if long else ""]
	var share := full * float(Content.COMP_KIT["owned_share"])
	return "+%s %% %s (+%s %% in the kit)" % [_percent(share), noun, _percent(full)]


## A set's bonus: "+15 % tap moves".
static func effect_text(effect: Dictionary) -> String:
	return "+%s %% %s" % [_percent(float(effect["value"]) - 1.0), effect_noun(effect)]


static func effect_noun(effect: Dictionary) -> String:
	var type := String(effect.get("type", ""))
	var noun := String(EFFECT_NOUNS.get(type, type))
	if type == "puzzle_mult":
		var puzzles: Array = effect.get("puzzles", [])
		return noun % (", ".join(puzzles.map(func(p: Variant) -> String: return String(Content.get_puzzle(str(p)).get("name", p)))))
	if type == "building_mult":
		return noun % Content.get_building(String(effect.get("target", ""))).get("name", "")
	return noun


static func _percent(fraction: float) -> String:
	var percent := fraction * 100.0
	return str(roundi(percent)) if absf(percent - roundf(percent)) < 0.05 else "%.1f" % percent


# --- Stats (7.2b) ---------------------------------------------------------------------

## [key, name, kind]: kind time | count | number | best.
const STAT_ROWS := [
	["time_played", "Time played", "time"], ["run_time", "This run", "time"],
	["fastest_championship", "Fastest championship", "best"], ["taps", "Taps", "count"],
	["lifetime_solves", "Solves, lifetime", "number"], ["run_solves", "Solves, this run", "number"],
	["lifetime_moves", "Moves, lifetime", "number"], ["best_solves_per_second", "Best Solves/s (helpers)", "number"],
	["championships", "World Championships", "count"], ["trophies_won", "Trophies won", "count"],
	["trophies", "Trophies unspent", "count"], ["hand_solves", "Solve Station solves", "count"],
	["golden_solved", "Golden Scrambles solved", "count"], ["dailies", "Daily rewards", "count"],
	["achievements", "Achievements", "ratio"], ["collection", "Collection items", "ratio"],
]


func _build_stats() -> void:
	var scroll: ScrollContainer = %Stats
	var page := VBoxContainer.new()
	page.theme_type_variation = &"StackBox"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	var grid := GridContainer.new()
	grid.theme_type_variation = &"UpgradeGrid"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(grid)
	for row: Array in STAT_ROWS:
		var card := PanelContainer.new()
		card.theme_type_variation = &"ItemCard"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		box.theme_type_variation = &"TightBox"
		card.add_child(box)
		box.add_child(_label(&"FaintLabel", String(row[1])))
		var value := _label(&"StatValue")
		box.add_child(value)
		grid.add_child(card)
		_stat_values[row[0]] = value
	page.add_child(_label(&"CardTitle", "Solves per puzzle"))
	var puzzles := GridContainer.new()
	puzzles.theme_type_variation = &"UpgradeGrid"
	puzzles.columns = 3
	puzzles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(puzzles)
	for puzzle: Dictionary in Content.PUZZLES:
		var name := _label(&"CardLine", String(puzzle["name"]))
		name.custom_minimum_size = Vector2(120, 0)
		var bar := _bar()
		var value := _label(&"StatValue")
		value.custom_minimum_size = Vector2(110, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for node: Control in [name, bar, value]:
			puzzles.add_child(node)
		_puzzle_rows[puzzle["id"]] = {"name": name, "bar": bar, "value": value}


func _refresh_stats() -> void:
	var stats: Dictionary = Game.get_stats()
	var items: Dictionary = Game.get_collection_progress()
	for row: Array in STAT_ROWS:
		var label: Label = _stat_values[row[0]]
		match String(row[2]):
			"time":
				label.text = Num.format_duration(float(stats.get(row[0], 0.0)))
			"best":
				var seconds := float(stats.get(row[0], 0.0))
				label.text = Num.format_duration(seconds) if seconds > 0.0 else "—"
			"count":
				label.text = Num.format(roundf(float(stats.get(row[0], 0.0))))
			"ratio":
				label.text = "%d / %d" % ([stats["achievements_earned"], stats["achievements_total"]] if row[0] == "achievements"
						else [items["owned"], items["total"]])
			_:
				label.text = Num.format(float(stats.get(row[0], 0.0)))
	var per_puzzle: Dictionary = stats.get("puzzle_solves", {})
	var most := 0.0
	for id: String in per_puzzle:
		most = maxf(most, float(per_puzzle[id]))
	for id: String in _puzzle_rows:
		var view: Dictionary = _puzzle_rows[id]
		var reached: bool = Game.puzzles_reached.has(id) or per_puzzle.has(id)
		var solves := float(per_puzzle.get(id, 0.0))
		(view["name"] as Label).text = String(Content.get_puzzle(id)["name"]) if reached else "???"
		(view["value"] as Label).text = Num.format(roundf(solves)) if reached else "—"
		(view["bar"] as ProgressBar).value = solves / most if most > 0.0 else 0.0


# --- Helpers ------------------------------------------------------------------------

## A thin goal bar (0..1), like the goal card's.
func _bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"GoalBar"
	bar.custom_minimum_size = Vector2(0, BAR_HEIGHT)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _label(variation: StringName, text: String = "") -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		if selected_slot != "":
			select_slot(selected_slot)  # first Escape drops the slot pick
		else:
			close()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()
