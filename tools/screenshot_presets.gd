extends RefCounted
## Game states for tools/screenshot.sh, as save data (version 1, or version 2 for puzzle states).
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

	# Three puzzles running (v2 save): 2x2, 3x3 and 4x4, focused on the 4x4, helpers spread over all three.
	"row3": {
		"version": 3,
		"mastery": {"2x2": 640.0, "3x3": 230.0, "4x4": 40.0},
		"solves": 18000.0,
		"total_solves": 260000.0,
		"total_moves": 2.2e6,
		"puzzles": {"unlocked": ["2x2", "3x3", "4x4"], "progress": {"4x4": 30.0}, "focus": "4x4",
			"split": {"2x2": 0.2, "3x3": 0.3, "4x4": 0.5}},
		"buildings": {"friend": 30, "club": 20, "robot": 12, "competition": 6},
		"upgrades": ["lube", "stackmat", "cfop", "club_snacks", "magnets", "firmware"],
	},

	# Every cube running (as if after a championship): 2x2 to 7x7, focused on the 7x7.
	"row5": {
		"version": 2,
		"solves": 4.0e6,
		"total_solves": 9.0e7,
		"total_moves": 9.0e8,
		"puzzles": {"unlocked": ["2x2", "3x3", "4x4", "5x5", "7x7"], "progress": {"7x7": 120.0}, "focus": "7x7",
			"split": {"2x2": 0.1, "3x3": 0.15, "4x4": 0.2, "5x5": 0.25, "7x7": 0.3}},
		"buildings": {"friend": 60, "club": 45, "robot": 35, "competition": 25, "factory": 15, "lab": 8},
		"upgrades": ["lube", "stackmat", "cfop", "club_snacks", "magnets", "firmware", "roux"],
		"championship": {"trophies": 12, "count": 1, "run_solves": 9.0e7, "reached": []},  # after a championship
	},
	## Task 5.5: deep into a long run, every helper tier owned (the six past the Lab too), four cubes.
	"endgame": {
		"version": 2,
		"solves": 3.0e13,
		"total_solves": 5.0e14,
		"total_moves": 5.0e15,
		"puzzles": {"unlocked": ["2x2", "3x3", "4x4", "5x5"], "progress": {}, "focus": "3x3",
			"split": {"2x2": 0.1, "3x3": 0.2, "4x4": 0.3, "5x5": 0.4}},
		"buildings": {"friend": 150, "club": 120, "robot": 100, "competition": 90, "factory": 75, "lab": 60,
			"pro_team": 45, "federation": 30, "museum": 18, "ai_solver": 9, "orbital": 3, "quantum": 0},
		"upgrades": ["lube", "stackmat", "cfop", "club_snacks", "magnets", "firmware", "roux"],
	},

	# All six puzzles (later in the game, after a championship), focused on the Megaminx.
	"row6": {
		"version": 2,
		"solves": 4.0e9,
		"total_solves": 9.0e10,
		"total_moves": 9.0e11,
		"puzzles": {"unlocked": ["2x2", "3x3", "4x4", "5x5", "7x7", "megaminx"], "progress": {}, "focus": "megaminx",
			"split": {"2x2": 0.05, "3x3": 0.1, "4x4": 0.15, "5x5": 0.2, "7x7": 0.2, "megaminx": 0.3}},
		"buildings": {"friend": 80, "club": 60, "robot": 45, "competition": 35, "factory": 25, "lab": 15},
		"upgrades": ["lube", "stackmat", "cfop", "club_snacks", "magnets", "firmware", "roux"],
		"championship": {"trophies": 20, "count": 1, "run_solves": 9.0e10, "reached": []},  # after a championship
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
