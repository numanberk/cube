class_name SettingsPanel
extends Control
## The Settings panel (task 3.4): volumes, music mode, background audio, Jukebox, graphics, reduce motion,
## number notation and "Reset save". Reads and writes the Settings autoload; the only game call is
## Game.wipe_save(), after a confirmation that names what is lost. Escape or a click outside closes it.

const MUSIC_MODES := {"follow": "Follow progress", "shuffle": "Shuffle unlocked tracks", "loop": "Loop one track"}
const FOCUS_AUDIO := {"duck": "Lower the music", "mute": "Mute the music", "keep": "Keep playing"}
const QUALITIES := {"high": "High", "low": "Low (faster on older PCs)"}
const NOTATIONS := {"short": "Short (1.50K)", "scientific": "Scientific (1.50e3)"}
const UNLOCK_NAMES := {
	"2x2": "2×2", "3x3": "3×3", "4x4": "4×4", "5x5": "5×5", "7x7": "7×7", "megaminx": "Megaminx",
}

@onready var _dim: ColorRect = %Dim
@onready var _panel: Control = %Panel
@onready var _close: Button = %CloseButton
@onready var _sliders := {"master_volume": %MasterSlider, "music_volume": %MusicSlider, "sfx_volume": %SfxSlider}
@onready var _slider_values := {"master_volume": %MasterSliderValue, "music_volume": %MusicSliderValue, "sfx_volume": %SfxSliderValue}
@onready var _options := {"music_mode": %MusicMode, "focus_audio": %FocusAudio, "quality": %Graphics, "notation": %Notation}
@onready var _reduce_motion: CheckButton = %ReduceMotion
@onready var _jukebox: VBoxContainer = %JukeboxList
@onready var _reset_button: Button = %ResetButton
@onready var _reset_dialog: ConfirmationDialog = %ResetDialog

var _syncing := false  ## true while filling controls from Settings, so their signals don't write back


func _ready() -> void:
	_fill_option(_options["music_mode"], MUSIC_MODES)
	_fill_option(_options["focus_audio"], FOCUS_AUDIO)
	_fill_option(_options["quality"], QUALITIES)
	_fill_option(_options["notation"], NOTATIONS)
	for key: String in _sliders:
		(_sliders[key] as HSlider).value_changed.connect(_on_slider_changed.bind(key))
	for key: String in _options:
		(_options[key] as OptionButton).item_selected.connect(_on_option_selected.bind(key))
	_reduce_motion.toggled.connect(func(on: bool) -> void: _write("reduce_motion", on))
	_close.pressed.connect(close)
	_dim.gui_input.connect(_on_dim_input)
	_reset_button.pressed.connect(_ask_reset)
	_reset_dialog.confirmed.connect(_reset_save)
	Settings.changed.connect(func(_key: String) -> void: if visible: sync())


func open() -> void:
	sync()
	UiFx.open_panel(self, _dim, _panel)  # V.6: scale + fade over a dimmed (High: blurred) backdrop


func close() -> void:
	UiFx.close_panel(self, _dim, _panel)


## Fills every control from the current settings and rebuilds the Jukebox.
func sync() -> void:
	_syncing = true
	for key: String in _sliders:
		(_sliders[key] as HSlider).value = Settings.get_value(key)
		(_slider_values[key] as Label).text = "%d%%" % roundi(float(Settings.get_value(key)) * 100.0)
	for key: String in _options:
		var option: OptionButton = _options[key]
		for i in option.item_count:
			if option.get_item_metadata(i) == Settings.get_value(key):
				option.select(i)
	_reduce_motion.button_pressed = Settings.get_value("reduce_motion")
	_syncing = false
	_rebuild_jukebox()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# --- Controls -> Settings ----------------------------------------------------------

func _write(key: String, value: Variant) -> void:
	if not _syncing:
		Settings.set_value(key, value)


func _on_slider_changed(value: float, key: String) -> void:
	(_slider_values[key] as Label).text = "%d%%" % roundi(value * 100.0)
	_write(key, value)


func _on_option_selected(index: int, key: String) -> void:
	_write(key, (_options[key] as OptionButton).get_item_metadata(index))


func _on_dim_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		close()


func _fill_option(option: OptionButton, items: Dictionary) -> void:
	option.clear()
	for value: String in items:
		option.add_item(items[value])
		option.set_item_metadata(option.item_count - 1, value)


# --- Jukebox --------------------------------------------------------------------

## One row per track: a play button if it's unlocked and exists, otherwise what unlocks it.
func _rebuild_jukebox() -> void:
	for child in _jukebox.get_children():
		_jukebox.remove_child(child)  # queue_free alone keeps it in the list until the frame ends
		child.queue_free()
	var unlocked_puzzles := Game.get_unlocked_puzzle_ids()
	var playable := Game.get_unlocked_track_ids()
	for def: Dictionary in Content.TRACKS:
		var id: String = def["id"]
		if playable.has(id):
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var playing: bool = Audio.current_track_id == id
			button.text = ("Now playing:  " if playing else "Play:  ") + "%s  ·  %s" % [def["title"], def["artist"]]
			button.pressed.connect(play_track.bind(id))
			_jukebox.add_child(button)
		else:
			var label := Label.new()
			label.theme_type_variation = &"FaintLabel"
			label.text = "%s  ·  %s" % [def["title"], _locked_reason(def, unlocked_puzzles)]
			_jukebox.add_child(label)


## Plays a track from the Jukebox: switches the music to "Loop one track" on it.
func play_track(track_id: String) -> void:
	Settings.set_value("loop_track", track_id)
	Settings.set_value("music_mode", "loop")
	Audio.play_track(track_id)
	sync()


func _locked_reason(def: Dictionary, unlocked_puzzles: Array[String]) -> String:
	var unlock: String = def["unlock"]
	if unlock == "championship":
		return "Win a World Championship to hear this"
	if unlocked_puzzles.has(unlock):
		return "Coming soon"
	return "Unlock %s to hear this" % UNLOCK_NAMES.get(unlock, unlock)


# --- Reset save -----------------------------------------------------------------

func _ask_reset() -> void:
	var helpers := 0
	for id: String in Game.buildings:
		helpers += int(Game.buildings[id])
	_reset_dialog.dialog_text = ("This deletes your save:\n"
		+ "  •  %s Solves (%s earned in total)\n" % [Num.format(Game.solves), Num.format(Game.total_solves)]
		+ "  •  %d helpers and %d upgrades\n" % [helpers, Game.upgrades.size()]
		+ "  •  all other progress and lifetime stats\n\n"
		+ "Your settings are kept. This can't be undone.")
	_reset_dialog.popup_centered(Vector2i(460, 0))


func _reset_save() -> void:
	Game.wipe_save()
	close()
