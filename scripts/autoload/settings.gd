class_name GameSettings
extends Node
## Player settings, registered as the autoload "Settings". Stored in user://settings.cfg, separate from the save,
## so resetting the save never touches them. Took over GraphicsConfig (task 1.5): same file, [graphics] quality.
##
## Read with get_value(key); change with set_value(key, value), which validates, saves, applies and emits `changed`.
## Applying: audio settings go straight to Audio and number notation to Num; graphics and reduce motion are applied
## by main.gd (it owns the views), listening to `changed`.

signal changed(key: String)

## key -> {section, default, and either `choices` or a `min`/`max` range}
const SPEC := {
	"master_volume": {"section": "audio", "default": 1.0, "min": 0.0, "max": 1.0},
	"music_volume": {"section": "audio", "default": 0.5, "min": 0.0, "max": 1.0},
	"sfx_volume": {"section": "audio", "default": 0.7, "min": 0.0, "max": 1.0},
	"music_mode": {"section": "audio", "default": "follow", "choices": ["follow", "shuffle", "loop"]},
	"loop_track": {"section": "audio", "default": ""},
	"focus_audio": {"section": "audio", "default": "duck", "choices": ["duck", "mute", "keep"]},
	"quality": {"section": "graphics", "default": "high", "choices": ["high", "low"]},
	"reduce_motion": {"section": "graphics", "default": false},
	"notation": {"section": "display", "default": "short", "choices": ["short", "scientific"]},
}

## Set to false before the node enters the tree to skip loading from disk (tests do this).
var persistence_enabled := true
var path := "user://settings.cfg"
var _values: Dictionary = {}


func _ready() -> void:
	reset_to_defaults()
	if persistence_enabled:
		load_settings()
	apply_all()


func reset_to_defaults() -> void:
	for key: String in SPEC:
		_values[key] = SPEC[key]["default"]


func get_value(key: String) -> Variant:
	return _values.get(key, SPEC.get(key, {}).get("default"))


## Validates and stores a setting, saves the file, applies it and emits `changed`. Returns false if invalid.
func set_value(key: String, value: Variant) -> bool:
	if not SPEC.has(key):
		push_warning("Unknown setting '%s'" % key)
		return false
	var clean: Variant = _validate(key, value)
	if clean == null:
		push_warning("Invalid value %s for setting '%s'" % [value, key])
		return false
	_values[key] = clean
	if persistence_enabled:
		save_settings()
	_apply(key)
	changed.emit(key)
	return true


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key: String in SPEC:
		var spec: Dictionary = SPEC[key]
		if config.has_section_key(spec["section"], key):
			var clean: Variant = _validate(key, config.get_value(spec["section"], key))
			if clean != null:
				_values[key] = clean


func save_settings() -> void:
	var config := ConfigFile.new()
	config.load(path)  # keep anything else already in the file
	for key: String in SPEC:
		config.set_value(SPEC[key]["section"], key, _values[key])
	var err := config.save(path)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))


func apply_all() -> void:
	for key: String in SPEC:
		_apply(key)


func _apply(key: String) -> void:
	var audio: AudioManager = get_node_or_null("/root/Audio") as AudioManager if is_inside_tree() else null
	match key:
		"master_volume":
			if audio:
				audio.set_bus_volume(&"Master", _values[key])
		"music_volume":
			if audio:
				audio.set_bus_volume(AudioManager.MUSIC_BUS, _values[key])
		"sfx_volume":
			if audio:
				audio.set_bus_volume(AudioManager.SFX_BUS, _values[key])
		"music_mode", "loop_track":
			if audio:
				audio.set_music_mode(_values["music_mode"], _values["loop_track"])
		"focus_audio":
			if audio:
				audio.focus_behaviour = _values[key]
		"notation":
			Num.notation = _values[key]


## Returns the cleaned value, or null if it isn't valid for this key.
func _validate(key: String, value: Variant) -> Variant:
	var spec: Dictionary = SPEC[key]
	var default: Variant = spec["default"]
	if spec.has("choices"):
		return value if str(value) in spec["choices"] else null
	if typeof(default) == TYPE_BOOL:
		return bool(value) if typeof(value) in [TYPE_BOOL, TYPE_INT] else null
	if typeof(default) == TYPE_FLOAT:
		if not typeof(value) in [TYPE_FLOAT, TYPE_INT]:
			return null
		return clampf(float(value), spec["min"], spec["max"])
	return str(value)
