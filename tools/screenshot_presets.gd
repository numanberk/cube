extends RefCounted
## Game states for tools/screenshot.sh, written as *version 1* save data.
## They go through GameState.apply_save_data(), so _migrate() keeps them loading
## after future save-format changes. test_runner.gd checks every preset still loads.
## Add a preset: add a key here, then `bash tools/screenshot.sh <dir> <key>`.

const PRESETS := {
	# Brand-new player: nothing owned.
	"fresh": {},

	# ~15 minutes in: a few helper types and the cheap upgrades.
	"mid": {
		"version": 1,
		"solves": 420.0,
		"total_solves": 6000.0,
		"total_moves": 90000.0,
		"move_progress": 7.0,
		"buildings": {"friend": 15, "club": 8, "robot": 2},
		"upgrades": ["lube", "stackmat", "cfop", "club_snacks", "magnets"],
	},

	# The mid preset after 2h 15m away: shows the Welcome back panel. "away_seconds" isn't save data; the screenshot
	# tool turns it into saved_at = now - away_seconds.
	"welcome": {
		"version": 1,
		"away_seconds": 8100,
		"solves": 420.0,
		"total_solves": 6000.0,
		"total_moves": 90000.0,
		"move_progress": 7.0,
		"buildings": {"friend": 15, "club": 8, "robot": 2},
		"upgrades": ["lube", "stackmat", "cfop", "club_snacks", "magnets"],
	},

	# Everything unlocked and bought, lots of each helper.
	"late": {
		"version": 1,
		"solves": 3200000.0,
		"total_solves": 90000000.0,
		"total_moves": 900000000.0,
		"move_progress": 4.0,
		"buildings": {"friend": 60, "club": 45, "robot": 35, "competition": 25, "factory": 15, "lab": 8},
		"upgrades": ["lube", "stackmat", "cfop", "club_snacks", "magnets", "firmware", "roux"],
	},
}
