class_name GraphicsConfig
extends RefCounted
## The Graphics: High / Low choice, kept in user://settings.cfg under [graphics] quality.
## Settings aren't game state, so this is separate from the save (a save reset never touches it).
## Task 3.4's Settings autoload takes this over: same file, section and key, so players keep their choice.

const QUALITIES: Array[String] = ["high", "low"]
const DEFAULT_QUALITY := "high"

static var path := "user://settings.cfg"  ## tests point this elsewhere


static func load_quality() -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return DEFAULT_QUALITY
	var quality := str(config.get_value("graphics", "quality", DEFAULT_QUALITY))
	return quality if quality in QUALITIES else DEFAULT_QUALITY


static func save_quality(quality: String) -> void:
	if not quality in QUALITIES:
		push_warning("Unknown graphics quality '%s'" % quality)
		return
	var config := ConfigFile.new()
	config.load(path)  # keep any other sections already in the file
	config.set_value("graphics", "quality", quality)
	var err := config.save(path)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))
