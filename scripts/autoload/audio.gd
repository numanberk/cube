class_name AudioManager
extends Node
## Sound effects and music. Registered as the autoload "Audio".
## Buses live in default_bus_layout.tres: Master > Music, SFX. Default volumes: Music 50 %, SFX 70 % (PLAN §4.3);
## the Settings autoload (3.4) will set them from user://settings.cfg.
## Every play_* call is rate-limited per sound, so fast play never stacks dozens of the same sound.
## Sounds are made by tools/make_sfx.py (CC0, ours). Display/feedback only: no game rules here.

const SFX_BUS := &"SFX"
const MUSIC_BUS := &"Music"
const DEFAULT_SFX_VOLUME := 0.7
const DEFAULT_MUSIC_VOLUME := 0.5
const PITCH_JITTER := 0.08      ## clicks vary ±8 % so repeated taps don't sound robotic

# Music (task 3.2). Two players crossfade, so two songs are never both at full volume.
const CROSSFADE_TIME := 2.0
const MUSIC_START_DELAY := 2.0   ## music fades in this long after launch (the first clicks lead in)
const MUSIC_MODES: Array[String] = ["follow", "shuffle", "loop"]  ## Follow progress / Shuffle unlocked / Loop one
const FOCUS_BEHAVIOURS: Array[String] = ["duck", "mute", "keep"]  ## when the window loses focus
const DUCK_VOLUME := 0.3
const DUCK_SPEED := 2.0          ## how fast music ducks / comes back (per second)
const FOLLOW_LOOPS_BEFORE_VARIETY := 3  ## follow mode: after this many loops, sometimes play another unlocked track...
const FOLLOW_VARIETY_CHANCE := 0.25
const VARIETY_LOOPS := 2         ## ...for this many loops, then go back
const SHUFFLE_LOOPS := 2         ## shuffle mode: change track after this many loops

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

var _shut_down := false           ## set by shut_down(): no new sounds
var music_enabled := true        ## false = never start music (the screenshot tool; nothing to hear there)
var music_mode := "follow"
var loop_track_id := ""          ## the track "loop" mode plays ("" = the follow track)
var focus_behaviour := "duck"
var current_track_id := ""       ## what's playing (or fading in)
var _music_players: Array[AudioStreamPlayer] = []
var _current_player := 0         ## index into _music_players of the one fading in / playing
var _fade := 1.0                 ## 0 -> 1 during a crossfade
var _duck := 1.0                 ## 1 = full, eases towards the focus target
var _window_focused := true
var _unlocked_tracks: Array[String] = []
var _follow_track_id := ""
var _loops := 0                  ## loops of the current track
var _on_detour := false          ## follow mode is playing another track for variety
var _last_position := 0.0
var music_clock := 0.0           ## seconds since launch, for MUSIC_START_DELAY (tests may set it)
var _context_ready := false


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
	for i in 2:
		var music := AudioStreamPlayer.new()
		music.name = "Music%d" % i
		music.bus = MUSIC_BUS
		add_child(music)
		_music_players.append(music)
	set_bus_volume(SFX_BUS, DEFAULT_SFX_VOLUME)
	set_bus_volume(MUSIC_BUS, DEFAULT_MUSIC_VOLUME)


func _process(delta: float) -> void:
	advance_music(delta)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_window_focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_window_focused = true


# --- Music ---------------------------------------------------------------------------

## Tells the music what's available: the unlocked track ids, and the track for the focused puzzle (follow mode).
## Called by main.gd whenever the game state may have changed; cheap when nothing changed.
func set_music_context(unlocked_track_ids: Array[String], follow_track_id: String) -> void:
	_unlocked_tracks = unlocked_track_ids.duplicate()
	_follow_track_id = follow_track_id
	_context_ready = true
	if not music_enabled or music_clock < MUSIC_START_DELAY:
		return  # advance_music starts it once the delay has passed
	var wanted := _wanted_track()
	if current_track_id == "" or not _unlocked_tracks.has(current_track_id) or (music_mode == "loop" and wanted != current_track_id) \
			or (music_mode == "follow" and not _on_detour and wanted != current_track_id):
		play_track(wanted)


## Crossfades to a track (no-op if it's already playing or has no file).
func play_track(track_id: String) -> void:
	if _shut_down or not music_enabled or track_id == "" or track_id == current_track_id:
		return
	var def := Content.get_track(track_id)
	if def.is_empty() or def["file"] == "":
		return
	var incoming := 1 - _current_player if current_track_id != "" else _current_player
	var player := _music_players[incoming]
	player.stream = load(def["file"])
	player.volume_db = linear_to_db(0.0001)
	player.play()
	_current_player = incoming
	current_track_id = track_id
	_fade = 0.0  # fade in (and out of the old track, if one is playing)
	_loops = 0
	_last_position = 0.0
	_apply_music_volumes()


## Music mode: "follow" (default), "shuffle" or "loop" (loop_track_id, or the follow track).
func set_music_mode(mode: String, track_id: String = "") -> void:
	if not mode in MUSIC_MODES:
		push_warning("Unknown music mode '%s'" % mode)
		return
	music_mode = mode
	loop_track_id = track_id
	_on_detour = false
	if music_clock >= MUSIC_START_DELAY:
		play_track(_wanted_track())


## Linear volume of each music player right now, after crossfade and ducking (tests use this).
func music_volumes() -> Array[float]:
	var volumes: Array[float] = []
	for player in _music_players:
		volumes.append(db_to_linear(player.volume_db) if player.playing else 0.0)
	return volumes


## One step of the music logic (crossfade, ducking, loop counting). Runs every frame; tests call it directly.
func advance_music(delta: float) -> void:
	var was_waiting := music_clock < MUSIC_START_DELAY
	music_clock += delta
	if was_waiting and music_clock >= MUSIC_START_DELAY and _context_ready:
		set_music_context(_unlocked_tracks, _follow_track_id)
		return  # the fade-in starts from silence on the next step
	if _fade < 1.0:
		_fade = minf(1.0, _fade + delta / CROSSFADE_TIME)
		if _fade >= 1.0:
			_music_players[1 - _current_player].stop()
	var duck_target := 1.0
	if not _window_focused:
		duck_target = {"duck": DUCK_VOLUME, "mute": 0.0, "keep": 1.0}[focus_behaviour]
	_duck = move_toward(_duck, duck_target, delta * DUCK_SPEED)
	_apply_music_volumes()
	var player := _music_players[_current_player]
	if player.playing:
		var position := player.get_playback_position()
		if position + 0.5 < _last_position:  # it wrapped round: one loop done
			on_music_looped()
		_last_position = position


## Called when the current track finishes a loop: maybe change track, depending on the mode.
func on_music_looped() -> void:
	_loops += 1
	match music_mode:
		"shuffle":
			if _loops >= SHUFFLE_LOOPS:
				play_track(_random_other_track())
		"follow":
			if _on_detour and _loops >= VARIETY_LOOPS:
				_on_detour = false
				play_track(_follow_track_id)
			elif not _on_detour and _loops >= FOLLOW_LOOPS_BEFORE_VARIETY and _rng.randf() < FOLLOW_VARIETY_CHANCE:
				var other := _random_other_track()
				if other != "":
					_on_detour = true
					play_track(other)


func set_window_focused(focused: bool) -> void:
	_window_focused = focused


func _wanted_track() -> String:
	match music_mode:
		"loop":
			return loop_track_id if _unlocked_tracks.has(loop_track_id) else _follow_or_first()
		"shuffle":
			return current_track_id if _unlocked_tracks.has(current_track_id) else _follow_or_first()
	return _follow_or_first()


func _follow_or_first() -> String:
	if _unlocked_tracks.has(_follow_track_id):
		return _follow_track_id
	return _unlocked_tracks[0] if not _unlocked_tracks.is_empty() else ""


func _random_other_track() -> String:
	var others: Array[String] = []
	for id in _unlocked_tracks:
		if id != current_track_id:
			others.append(id)
	return others[_rng.randi_range(0, others.size() - 1)] if not others.is_empty() else ""


func _apply_music_volumes() -> void:
	var incoming := _music_players[_current_player]
	var outgoing := _music_players[1 - _current_player]
	incoming.volume_db = linear_to_db(maxf(0.0001, _fade * _duck))
	if outgoing.playing:
		outgoing.volume_db = linear_to_db(maxf(0.0001, (1.0 - _fade) * _duck))


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


## For quitting: stops every sound and refuses new ones, so nothing is still playing at exit (Godot reports a
## playback alive at exit as a leaked resource). The game keeps running during the short wait before quitting,
## and without this its solves would start new chimes.
func shut_down() -> void:
	_shut_down = true
	stop_all()


## Stops every sound now (used before quitting, so no playback is left alive at exit).
func stop_all() -> void:
	for player: AudioStreamPlayer in _players.values():
		player.stop()
	for player in _music_players:
		player.stop()
	current_track_id = ""


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
	if _shut_down:
		return false
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
