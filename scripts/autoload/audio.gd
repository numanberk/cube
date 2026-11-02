class_name AudioManager
extends Node
## Sound effects (and, from task 3.2, music). Registered as the autoload "Audio".
## Buses live in default_bus_layout.tres: Master > Music, SFX. Default volumes: Music 50 %, SFX 70 % (PLAN §4.3);
## the Settings autoload (3.4) will set them from user://settings.cfg.
## Every play_* call is rate-limited per sound, so fast play never stacks dozens of the same sound.
## Sounds are made by tools/make_sfx.py (CC0, ours). Display/feedback only: no game rules here.

const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const DEFAULT_SFX_VOLUME := 0.7
const DEFAULT_MUSIC_VOLUME := 0.5
const PITCH_JITTER := 0.08      ## clicks vary ±8 % so repeated taps don't sound robotic

## name -> {stream, min_interval (s), polyphony}
const SOUNDS := {
	"click": {"stream": preload("res://assets/audio/sfx/click.wav"), "min_interval": 0.05, "polyphony": 6},
	"chime": {"stream": preload("res://assets/audio/sfx/chime.wav"), "min_interval": 0.25, "polyphony": 3},
	"buy": {"stream": preload("res://assets/audio/sfx/buy.wav"), "min_interval": 0.06, "polyphony": 3},
	"unlock": {"stream": preload("res://assets/audio/sfx/unlock.wav"), "min_interval": 0.5, "polyphony": 1},
}

var played: Dictionary = {}      ## sound name -> times it actually played (tests and debugging)
var _players: Dictionary = {}    ## sound name -> AudioStreamPlayer
var _last_played: Dictionary = {}  ## sound name -> seconds (engine time) it last played
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for sound_name: String in SOUNDS:
		var def: Dictionary = SOUNDS[sound_name]
		var player := AudioStreamPlayer.new()
		player.name = sound_name.capitalize() + "Player"
		player.stream = def["stream"]
		player.bus = SFX_BUS
		player.max_polyphony = def["polyphony"]
		add_child(player)
		_players[sound_name] = player
		played[sound_name] = 0
	set_bus_volume(SFX_BUS, DEFAULT_SFX_VOLUME)
	set_bus_volume(MUSIC_BUS, DEFAULT_MUSIC_VOLUME)


## A turn of the puzzle. Bigger puzzles click lower (2×2 a bit higher, 7×7 about 20 % lower).
func play_click(puzzle_size: int = 3) -> bool:
	var pitch := pow(3.0 / maxf(2.0, puzzle_size), 0.25) * _rng.randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)
	return _play("click", pitch)


## A solve. At most ~4 a second, however many solves happen.
func play_solve() -> bool:
	return _play("chime")


func play_buy() -> bool:
	return _play("buy")


## Something new appeared (a helper now; puzzles later).
func play_unlock() -> bool:
	return _play("unlock")


## Stops every sound now (used before quitting, so no playback is left alive at exit).
func stop_all() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()


## Linear volume 0..1 for a bus ("Master", "Music", "SFX").
func set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("No audio bus '%s'" % bus)
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0, 1.0)))
	AudioServer.set_bus_mute(index, linear <= 0.001)


func get_bus_volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(index)) if index >= 0 else 0.0


func _play(sound_name: String, pitch: float = 1.0) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var min_interval: float = SOUNDS[sound_name]["min_interval"]
	if now - float(_last_played.get(sound_name, -INF)) < min_interval:
		return false
	_last_played[sound_name] = now
	var player: AudioStreamPlayer = _players[sound_name]
	player.pitch_scale = pitch
	player.play()
	played[sound_name] = int(played[sound_name]) + 1
	return true
