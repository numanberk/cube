class_name Content
extends RefCounted
## All game content lives here as plain data, so balancing and adding
## new helpers/upgrades never requires touching game logic.
##
## Building fields:
##   id, icon (file name in assets/icons/, no extension), name, description, base_cost (Solves), mps (moves/sec per unit),
##   unlock_at (optional, lifetime Solves needed to show it; default base_cost * 0.5)
##
## Upgrade fields:
##   id, icon (file name in assets/icons/), name, description, cost (Solves), effect, requires (optional {building_id: count})
##   effect.type is one of EFFECT_TYPES below; "building_mult" also needs effect.target.

const EFFECT_TYPES := [
	"tap_mult",          # multiplies moves per tap
	"global_mult",       # multiplies all moves (taps and helpers)
	"building_mult",     # multiplies one helper's moves (needs "target")
	"solve_moves_mult",  # multiplies moves needed per solve (< 1 is good)
	"solve_value_mult",  # multiplies Solves earned per solve
]

const BUILDINGS := [
	{
		"id": "friend",
		"icon": "friend",
		"name": "Cubing Friend",
		"description": "Practices with you after school.",
		"base_cost": 5,
		"mps": 0.5,
		"unlock_at": 0,
	},
	{
		"id": "club",
		"icon": "club",
		"name": "Cubing Club",
		"description": "A room full of people turning cubes.",
		"base_cost": 60,
		"mps": 4.0,
	},
	{
		"id": "robot",
		"icon": "robot",
		"name": "Solving Robot",
		"description": "Never gets tired. Never drops a piece.",
		"base_cost": 1500,
		"mps": 32.0,
	},
	{
		"id": "competition",
		"icon": "competition",
		"name": "Local Competition",
		"description": "Hundreds of solves every weekend.",
		"base_cost": 9000,
		"mps": 260.0,
	},
	{
		"id": "factory",
		"icon": "factory",
		"name": "Cube Factory",
		"description": "Mass-produced, pre-lubed, pre-scrambled.",
		"base_cost": 120000,
		"mps": 2100.0,
	},
	{
		"id": "lab",
		"icon": "lab",
		"name": "Speedcubing Lab",
		"description": "Researching the perfect turn.",
		"base_cost": 1800000,
		"mps": 18000.0,
	},
]

const UPGRADES := [
	{
		"id": "lube",
		"icon": "lube",
		"name": "Cube Lube",
		"description": "Smoother turns. Taps make 2x moves.",
		"cost": 15,
		"effect": {"type": "tap_mult", "value": 2.0},
	},
	{
		"id": "stackmat",
		"icon": "stackmat",
		"name": "Stackmat Timer",
		"description": "Friends practice 2x faster.",
		"cost": 50,
		"effect": {"type": "building_mult", "target": "friend", "value": 2.0},
		"requires": {"friend": 1},
	},
	{
		"id": "club_snacks",
		"icon": "club_snacks",
		"name": "Club Snacks",
		"description": "Clubs turn 2x faster.",
		"cost": 600,
		"effect": {"type": "building_mult", "target": "club", "value": 2.0},
		"requires": {"club": 1},
	},
	{
		"id": "magnets",
		"icon": "magnets",
		"name": "Magnetic Cube",
		"description": "Every move counts double.",
		"cost": 1500,
		"effect": {"type": "global_mult", "value": 2.0},
	},
	{
		"id": "firmware",
		"icon": "firmware",
		"name": "Robot Firmware v2",
		"description": "Robots turn 2x faster.",
		"cost": 8000,
		"effect": {"type": "building_mult", "target": "robot", "value": 2.0},
		"requires": {"robot": 1},
	},
]

## Methods (PLAN §4.1, task 5.1): a chain learned in order, Beginner → CFOP → Roux → ZZ → God's Number. Everyone starts
## with the first (cost 0). Each learned method multiplies moves per solve on every puzzle by its `mult`, down to that
## puzzle's floor (`min_moves_per_solve` in PUZZLES), so no puzzle ever becomes trivial.
## (Until save v4 CFOP and Roux were ordinary upgrades with the ids "cfop" and "roux"; GameState._migrate converts them.)
##   id, icon, name, description, cost (Solves), mult (moves per solve multiplier, < 1 is good)
const METHODS: Array[Dictionary] = [
	{
		"id": "beginner",
		"icon": "beginner",
		"name": "Beginner Method",
		"description": "Layer by layer, one piece at a time. Where every cuber starts.",
		"cost": 0,
		"mult": 1.0,
	},
	{
		"id": "cfop",
		"icon": "cfop",
		"name": "Learn CFOP",
		"description": "Cross, F2L, OLL, PLL. Solves take 30% fewer moves.",
		"cost": 200,
		"mult": 0.7,
	},
	{
		"id": "roux",
		"icon": "roux",
		"name": "Learn Roux",
		"description": "Build blocks, finish with the middle slice. Solves take another 30% fewer moves.",
		"cost": 25000,
		"mult": 0.7,
	},
	{
		"id": "zz",
		"icon": "zz",
		"name": "Learn ZZ",
		"description": "Orient the edges first, then never rotate. Solves take another 30% fewer moves.",
		"cost": 5.0e7,
		"mult": 0.7,
	},
	{
		"id": "gods_number",
		"icon": "gods_number",
		"name": "God's Number",
		"description": "Every scramble solved in the fewest moves there are. Solves take another 30% fewer moves.",
		"cost": 3.0e10,
		"mult": 0.7,
	},
]


## Puzzles (PLAN §4.1): the ladder 2×2 → Megaminx. With D9 every unlocked puzzle runs at once, each with its own
## moves per solve and Solves per solve. Higher tiers take more moves but pay more per move, so moving up is always a
## gain. Starting curve from PLAN §4.1, for the simulator to tune (task 4.7).
##   id (also the PuzzleShapes id), name, moves_per_solve, min_moves_per_solve (the floor that methods and perks can't
##   push below: a fifth of moves_per_solve, a quarter on the tiny 2×2, where every method plus mastery reaches it),
##   scramble_length (random moves in a Solve Station scramble, task S.1; WCA-like), solve_value (Solves per solve),
##   unlock_cost (Solves; 0 = owned from the start), requires_prestige (only after the first World Championship).
const PUZZLES := [
	{"id": "2x2", "name": "2×2", "moves_per_solve": 8.0, "min_moves_per_solve": 2.0, "scramble_length": 11, "solve_value": 1.0, "unlock_cost": 0.0, "requires_prestige": false},
	{"id": "3x3", "name": "3×3", "moves_per_solve": 20.0, "min_moves_per_solve": 4.0, "scramble_length": 25, "solve_value": 4.0, "unlock_cost": 150.0, "requires_prestige": false},
	{"id": "4x4", "name": "4×4", "moves_per_solve": 60.0, "min_moves_per_solve": 12.0, "scramble_length": 40, "solve_value": 18.0, "unlock_cost": 400000.0, "requires_prestige": false},
	{"id": "5x5", "name": "5×5", "moves_per_solve": 120.0, "min_moves_per_solve": 24.0, "scramble_length": 60, "solve_value": 50.0, "unlock_cost": 3e8, "requires_prestige": false},
	{"id": "7x7", "name": "7×7", "moves_per_solve": 300.0, "min_moves_per_solve": 60.0, "scramble_length": 100, "solve_value": 200.0, "unlock_cost": 5e8, "requires_prestige": true},
	{"id": "megaminx", "name": "Megaminx", "moves_per_solve": 700.0, "min_moves_per_solve": 140.0, "scramble_length": 77, "solve_value": 800.0, "unlock_cost": 2e11, "requires_prestige": true},
]

## Algorithms (task R.1, shared with the drills in S.4): real speedcubing algorithms in WCA notation, for the staged
## solver (StagedSolver) that the main cube's showcase solve plays. Every one is checked by a test: it must keep the
## first two layers and the centres where they were (and a PLL must keep the last layer's orientation).
##   id, name, set ("OLL", "PLL" or "Beginner"), two_look (part of 2-look OLL/PLL, what CFOP learners start with), alg
## S.4 adds the full OLL (57) and PLL (21) sets here; the solver uses a full set once the player has learned it.
const ALGORITHMS: Array[Dictionary] = [
	# 2-look OLL, step 1: orient the edges (make the cross on top)
	{"id": "oll_line", "name": "Line", "set": "OLL", "two_look": true, "alg": "F R U R' U' F'"},
	{"id": "oll_l_shape", "name": "L shape", "set": "OLL", "two_look": true, "alg": "F U R U' R' F'"},
	# 2-look OLL, step 2: orient the corners (OCLL)
	{"id": "oll_sune", "name": "Sune", "set": "OLL", "two_look": true, "alg": "R U R' U R U2 R'"},
	{"id": "oll_antisune", "name": "Antisune", "set": "OLL", "two_look": true, "alg": "R U2 R' U' R U' R'"},
	{"id": "oll_h", "name": "H (Double Sune)", "set": "OLL", "two_look": true, "alg": "R U R' U R U' R' U R U2 R'"},
	{"id": "oll_pi", "name": "Pi (Bruno)", "set": "OLL", "two_look": true, "alg": "R U2 R2 U' R2 U' R2 U2 R"},
	{"id": "oll_headlights", "name": "Headlights", "set": "OLL", "two_look": true, "alg": "R2 D R' U2 R D' R' U2 R'"},
	{"id": "oll_chameleon", "name": "Chameleon", "set": "OLL", "two_look": true, "alg": "r U R' U' r' F R F'"},
	{"id": "oll_bowtie", "name": "Bowtie", "set": "OLL", "two_look": true, "alg": "F R' F' r U R U' r'"},
	# 2-look PLL, step 1: permute the corners
	{"id": "pll_aa", "name": "Aa perm", "set": "PLL", "two_look": true, "alg": "x R' U R' D2 R U' R' D2 R2 x'"},
	{"id": "pll_ab", "name": "Ab perm", "set": "PLL", "two_look": true, "alg": "x R2 D2 R U R' D2 R U' R x'"},
	{"id": "pll_t", "name": "T perm", "set": "PLL", "two_look": true, "alg": "R U R' U' R' F R2 U' R' U' R U R' F'"},
	{"id": "pll_y", "name": "Y perm", "set": "PLL", "two_look": true, "alg": "F R U' R' U' R U R' F' R U R' U' R' F R F'"},
	# 2-look PLL, step 2: permute the edges
	{"id": "pll_ua", "name": "Ua perm", "set": "PLL", "two_look": true, "alg": "R U' R U R U R U' R' U' R2"},
	{"id": "pll_ub", "name": "Ub perm", "set": "PLL", "two_look": true, "alg": "R2 U R U R' U' R' U' R' U R'"},
	{"id": "pll_h", "name": "H perm", "set": "PLL", "two_look": true, "alg": "M2 U M2 U2 M2 U M2"},
	{"id": "pll_z", "name": "Z perm", "set": "PLL", "two_look": true, "alg": "M' U M2 U M2 U M' U2 M2"},
	# The beginner (layer-by-layer) method. Written for the front/right; the solver turns them to face any side.
	{"id": "beg_corner", "name": "Corner insert (repeat)", "set": "Beginner", "two_look": false, "alg": "R U R' U'"},
	{"id": "beg_edge_right", "name": "Edge to the right", "set": "Beginner", "two_look": false, "alg": "U R U' R' U' F' U F"},
	{"id": "beg_edge_left", "name": "Edge to the left", "set": "Beginner", "two_look": false, "alg": "U' L' U L U F U' F'"},
	{"id": "beg_yellow_cross", "name": "Yellow cross", "set": "Beginner", "two_look": false, "alg": "F R U R' U' F'"},
	{"id": "beg_yellow_edges", "name": "Yellow edges", "set": "Beginner", "two_look": false, "alg": "R U R' U R U2 R'"},
	{"id": "beg_corner_cycle", "name": "Corner cycle", "set": "Beginner", "two_look": false, "alg": "U R U' L' U R' U' L"},
	{"id": "beg_corner_twist", "name": "Corner twist (repeat)", "set": "Beginner", "two_look": false, "alg": "R' D' R D"},
]


## Time tiers (task R.3): progress in a cuber's language. A helper's solve time on a puzzle is its moves per solve ÷ the
## helper's moves/s there; the team's best time is the fastest helper's. Crossing a tier pops a message. Per puzzle,
## slowest first: [seconds, name]. "WR pace" is about the human world record single (approximate, 2025); past it come
## machine tiers (the solving-robot record is about 0.3 s).
const TIME_TIERS := {
	"2x2": [[30.0, "Sub-30"], [10.0, "Sub-10"], [5.0, "Sub-5"], [2.0, "Sub-2"], [1.0, "Sub-1"], [0.5, "WR pace"],
			[0.1, "Faster than a blink"], [0.001, "Sub-millisecond"], [1e-6, "Sub-microsecond"]],
	"3x3": [[60.0, "Sub-1:00"], [30.0, "Sub-30"], [20.0, "Sub-20"], [10.0, "Sub-10"], [5.0, "Sub-5"], [3.1, "WR pace"],
			[0.31, "Robot record pace"], [0.1, "Faster than a blink"], [0.001, "Sub-millisecond"], [1e-6, "Sub-microsecond"]],
	"4x4": [[180.0, "Sub-3:00"], [60.0, "Sub-1:00"], [40.0, "Sub-40"], [30.0, "Sub-30"], [20.0, "Sub-20"],
			[16.0, "WR pace"], [1.0, "Sub-1"], [0.1, "Faster than a blink"], [0.001, "Sub-millisecond"],
			[1e-6, "Sub-microsecond"]],
	"5x5": [[300.0, "Sub-5:00"], [120.0, "Sub-2:00"], [60.0, "Sub-1:00"], [45.0, "Sub-45"], [33.0, "WR pace"],
			[1.0, "Sub-1"], [0.1, "Faster than a blink"], [0.001, "Sub-millisecond"], [1e-6, "Sub-microsecond"]],
	"7x7": [[600.0, "Sub-10:00"], [300.0, "Sub-5:00"], [180.0, "Sub-3:00"], [120.0, "Sub-2:00"], [95.0, "WR pace"],
			[1.0, "Sub-1"], [0.1, "Faster than a blink"], [0.001, "Sub-millisecond"], [1e-6, "Sub-microsecond"]],
	"megaminx": [[180.0, "Sub-3:00"], [90.0, "Sub-1:30"], [60.0, "Sub-1:00"], [40.0, "Sub-40"], [24.0, "WR pace"],
			[1.0, "Sub-1"], [0.1, "Faster than a blink"], [0.001, "Sub-millisecond"], [1e-6, "Sub-microsecond"]],
}
## Above this many solves a second on the focused puzzle, the "moves to next solve" bar can't be followed; it shows the
## top goal instead (task R.3).
const GOAL_BAR_SOLVES_PER_SECOND := 10.0


## News feed (task R.4): who does what. Each helper kind has a title and a name pool ("people" or "codes" for machines);
## a member's name is picked by a seeded hash, so the same Club member keeps the same name. The feed shows one line
## every `interval` seconds at most, merges repeats of the same kind of news, and keeps the last `history` lines.
const NEWS := {
	"interval": 1.2,
	"queue": 6,
	"history": 20,
	"who": {
		"friend": ["Your friend", "people"], "club": ["Club member", "people"], "robot": ["Robot", "codes"],
		"competition": ["Competitor", "people"], "factory": ["Factory line", "codes"], "lab": ["Researcher", "people"],
	},
	"people": ["Ana", "Kenji", "Lena", "Mateo", "Priya", "Omar", "Sofia", "Lucas", "Mei", "Yusuf", "Elif", "Noah",
			"Aiko", "Diego", "Zara", "Ivan", "Chloe", "Arjun", "Nora", "Emre", "Hana", "Leo", "Amara", "Felix",
			"Ines", "Tariq", "Maya", "Jonas", "Selin", "Kofi"],
	"codes": ["Unit 7", "CB-3", "Turbo-9", "Model K", "Quad-12", "Spinner 4", "R-21", "Axis-5", "Twister 8", "Nova-2"],
}


## Hand-solve rewards (task S.3, D13: an active player earns ~2–3× an idle one). Per-puzzle time targets for the Solve
## Station, slowest first (seconds, keyboard solving). Tuned for our player (owner, 2026-11-03: best ~30 s on a real 3×3,
## consistently under 1:00); keyboard solving is slower than a real cube, so Gold 1:30 should be within reach and Master a
## stretch. A finished solve's tier sets its Flow; the best tier a puzzle's PB single has reached is a permanent bonus.
##   tiers: names, slowest first (index 0 = Bronze)
##   flow_by_tier: Flow multiplier for a solve below every target, then for each tier
##   flow_min_seconds / flow_time_factor: Flow lasts max(min, factor × the solve's time) (bigger puzzles take longer)
##   tier_moves_bonus: +moves on that puzzle per tier its PB has reached
##   xp_solves / xp_pb_factor: a hand solve gives the mastery XP of this many idle solves (×factor for a PB single)
const SOLVE_REWARDS := {
	"tiers": ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Master"],
	"targets": {
		"2x2": [90.0, 45.0, 25.0, 15.0, 10.0, 6.0],
		"3x3": [300.0, 150.0, 90.0, 60.0, 40.0, 25.0],
		"4x4": [900.0, 480.0, 300.0, 200.0, 140.0, 100.0],
		"5x5": [1500.0, 900.0, 600.0, 420.0, 300.0, 210.0],
		"7x7": [3600.0, 2400.0, 1600.0, 1200.0, 900.0, 650.0],
		"megaminx": [1800.0, 1200.0, 800.0, 500.0, 350.0, 240.0],
	},
	"flow_by_tier": [1.5, 1.6, 1.8, 2.0, 2.3, 2.6, 3.0],
	"flow_min_seconds": 120.0,
	"flow_time_factor": 1.5,
	"tier_moves_bonus": 0.05,
	"xp_solves": 10.0,
	"xp_pb_factor": 5.0,
}


## Golden Scramble (task S.6, was 8.1): every spawn_min..spawn_max seconds a golden sticker glows on the main puzzle
## for `glow` seconds. Clicking it opens a quick case (the puzzle case_moves_min..max moves from solved) to solve within
## `solve_seconds` for a random buff (by weight). "frenzy": all moves ×mult for `seconds`; "lucky": `minutes` of the
## current Solves/s at once (at least `min_solves_value` solves' worth of the focused puzzle, so it's never nothing).
## Buffs pause while the game is closed and never count for offline progress.
const GOLDEN := {
	"spawn_min": 120.0, "spawn_max": 300.0, "glow": 12.0, "solve_seconds": 10.0,
	"case_moves_min": 2, "case_moves_max": 5,
	"buffs": [
		{"id": "frenzy", "name": "Frenzy", "weight": 1.0, "mult": 7.0, "seconds": 30.0},
		{"id": "lucky", "name": "Lucky solve", "weight": 1.0, "minutes": 15.0, "min_solves_value": 10.0},
	],
}


## Showcase solve (task R.2): the main cube plays one real solve (StagedSolver) at a speed you can follow, instead of
## showing every move. Visual only: it never changes a number. Turns per second come from the learned method plus a bit
## per 10× more moves/s of the focused puzzle (owner, 2026-11-03: ~3 TPS Beginner up to ~10–12 with CFOP and many
## helpers), never above max_tps and never faster than the puzzle really gets moves (no helpers: only taps turn it).
##   inspection: seconds the scramble is shown before the solve (the inspection turns, like z2 y, play in it)
##   solved_hold: seconds the solved cube stays before the next scramble
const SHOWCASE := {
	"tps_by_method": {"beginner": 3.0, "cfop": 5.0, "roux": 6.0, "zz": 7.0, "gods_number": 8.0},
	"tps_per_decade": 0.9,
	"max_tps": 12.0,
	"inspection": 1.6,
	"solved_hold": 1.4,
}


## Solve Station keys (task S.1): csTimer's virtual-cube layout, so a speedcuber's muscle memory just works.
## Keys are physical positions (Godot Key constants, US layout names), so they work on any keyboard layout.
## Each entry: [first layer, last layer, face, direction], layers counted from that face starting at 1, like csTimer.
## Layer tokens: a number, "n" (the cube's size), "n-1", or the hands: "l"/"l+1" and "r"/"r+1" (keys 3/4 and 8/7
## move the left/right hand one layer in/out on big cubes, Space puts both back; csTimer does the same).
const SOLVE_KEYS := {
	KEY_I: [1, "r", "R", 1], KEY_K: [1, "r", "R", -1],          # R R'
	KEY_D: [1, "l", "L", 1], KEY_E: [1, "l", "L", -1],          # L L'
	KEY_J: [1, 1, "U", 1], KEY_F: [1, 1, "U", -1],              # U U'
	KEY_S: [1, 1, "D", 1], KEY_L: [1, 1, "D", -1],              # D D'
	KEY_H: [1, 1, "F", 1], KEY_G: [1, 1, "F", -1],              # F F'
	KEY_W: [1, 1, "B", 1], KEY_O: [1, 1, "B", -1],              # B B'
	KEY_U: [1, "r+1", "R", 1], KEY_M: [1, "r+1", "R", -1],      # r r'
	KEY_V: [1, "l+1", "L", 1], KEY_R: [1, "l+1", "L", -1],      # l l'
	KEY_COMMA: [1, 2, "U", 1], KEY_C: [1, 2, "U", -1],          # u u'
	KEY_Z: [1, 2, "D", 1], KEY_SLASH: [1, 2, "D", -1],          # d d'
	KEY_5: ["l+1", "l+1", "L", 1], KEY_6: ["r+1", "r+1", "R", -1],      # M M
	KEY_X: ["l+1", "l+1", "L", -1], KEY_PERIOD: ["r+1", "r+1", "R", 1], # M' M'
	KEY_2: [2, "n-1", "U", -1], KEY_9: [2, "n-1", "U", 1],      # E E'
	KEY_0: [2, "n-1", "F", 1], KEY_1: [2, "n-1", "F", -1],      # S S'
	KEY_T: [1, "n", "L", -1], KEY_Y: [1, "n", "R", 1],          # x x
	KEY_B: [1, "n", "L", 1], KEY_N: [1, "n", "R", -1],          # x' x'
	KEY_SEMICOLON: [1, "n", "U", 1], KEY_A: [1, "n", "U", -1],  # y y'
	KEY_P: [1, "n", "F", 1], KEY_Q: [1, "n", "F", -1],          # z z'
}
## Hand keys: key -> [hand, step]. Moving a hand in makes I/K, D/E, U/M, V/R and the M keys turn deeper layers.
## The "simple" layout (owner, 2026-11-03), a setting next to csTimer's: the key is the face (R U F L D B), Shift turns it
## the other way (R'), X Y Z are rotations, M E S the 3×3 slices, and a number first makes the next turn that many layers
## wide (2 then R = Rw, 3 then R = 3Rw). Keys are physical positions, like SOLVE_KEYS.
const SOLVE_KEYS_SIMPLE := {
	KEY_R: "R", KEY_U: "U", KEY_F: "F", KEY_L: "L", KEY_D: "D", KEY_B: "B",
	KEY_X: "x", KEY_Y: "y", KEY_Z: "z", KEY_M: "M", KEY_E: "E", KEY_S: "S",
}
const SOLVE_WIDTH_KEYS := {KEY_2: 2, KEY_3: 3, KEY_4: 4, KEY_5: 5, KEY_6: 6}
const SOLVE_KEY_LAYOUTS := ["cstimer", "simple"]
const SOLVE_HAND_KEYS := {KEY_3: ["l", -1], KEY_4: ["l", 1], KEY_7: ["r", 1], KEY_8: ["r", -1]}
const SOLVE_HAND_RESET_KEY := KEY_SPACE
## WCA inspection: 15 s; starting after that is +2, after 17 s it's a DNF.
const INSPECTION := {"seconds": 15.0, "plus_two_until": 17.0}

## Variety (task 4.7): practising several puzzles keeps you sharp. A puzzle that gets share s of the helpers' moves
## effectively gets s^exponent of them (with exponent < 1, small shares are boosted: 10 % works like 25 % at 0.6).
## With one puzzle (s = 1) nothing changes; spreading pays, and the best split is a real mix (PLAN §4.1's design risk):
## each puzzle's best share is proportional to (Solves per move)^(1 / (1 - exponent)). Taps aren't affected.
const VARIETY := {"exponent": 0.5}

## Puzzle Mastery (task 4.6, PLAYER_RESEARCH): every puzzle levels up from its own solves, in parallel.
## A solve gives moves_per_solve / xp_per_solve_moves XP, so XP per move is the same on every puzzle.
## Level L -> L+1 needs xp_first_level × xp_growth^(L-1) XP. Each level above 1 gives +per_level_moves moves on
## that puzzle; milestones add perks. Types: "moves" (× moves on that puzzle), "solve_moves" (× moves per solve on it),
## "solve_value" (× Solves per solve on it), "all_moves" (× moves on every puzzle). Kept through prestige (Phase 6).
const MASTERY := {
	"max_level": 100,
	"xp_first_level": 25.0,
	"xp_growth": 1.15,
	"xp_per_solve_moves": 8.0,
	"per_level_moves": 0.01,
	"milestones": [
		{"level": 5, "type": "moves", "value": 1.10, "text": "+10 % moves on this puzzle"},
		{"level": 10, "type": "solve_moves", "value": 0.9, "text": "10 % fewer moves per solve"},
		{"level": 25, "type": "solve_value", "value": 1.25, "text": "+25 % Solves per solve"},
		{"level": 50, "type": "all_moves", "value": 1.05, "text": "+5 % moves on every puzzle"},
		{"level": 100, "type": "solve_value", "value": 2.0, "text": "×2 Solves per solve"},
	],
}

## Music (PLAN §4.3): one track per puzzle tier plus "Finals". `unlock` is the puzzle id that unlocks the track
## ("championship" = the first World Championship). `file` is "" until the track exists (task 4.5 / decision D8);
## tracks without a file are skipped by the player. License must be CC0 or CC-BY (credited in assets/CREDITS.md).
const TRACKS := [
	{"id": "practice_room", "title": "Practice Room", "artist": "Cube Idle (placeholder)", "license": "CC0",
		"file": "res://assets/audio/music/practice_room.wav", "unlock": "2x2"},
	{"id": "first_sub_20", "title": "First Sub-20", "artist": "Cube Idle (placeholder)", "license": "CC0",
		"file": "res://assets/audio/music/first_sub_20.wav", "unlock": "3x3"},
	{"id": "parity", "title": "Parity", "artist": "Cube Idle (placeholder)", "license": "CC0",
		"file": "res://assets/audio/music/parity.wav", "unlock": "4x4"},
	{"id": "big_cube_energy", "title": "Big Cube Energy", "artist": "Cube Idle (placeholder)", "license": "CC0",
		"file": "res://assets/audio/music/big_cube_energy.wav", "unlock": "5x5"},
	{"id": "long_solve", "title": "Long Solve", "artist": "Cube Idle (placeholder)", "license": "CC0",
		"file": "res://assets/audio/music/long_solve.wav", "unlock": "7x7"},
	{"id": "twelve_faces", "title": "Twelve Faces", "artist": "Cube Idle (placeholder)", "license": "CC0",
		"file": "res://assets/audio/music/twelve_faces.wav", "unlock": "megaminx"},
	{"id": "finals", "title": "Finals", "artist": "Cube Idle (placeholder)", "license": "CC0",
		"file": "res://assets/audio/music/finals.wav", "unlock": "championship"},
]

const ICON_DIR := "res://assets/icons/"
const LOCKED_ICON := "locked"


## The icon texture for a content entry's "icon" field (assets/icons/<name>.svg).
static func icon(name: String) -> Texture2D:
	return load(ICON_DIR + name + ".svg")


static func get_puzzle(id: String) -> Dictionary:
	for def: Dictionary in PUZZLES:
		if def["id"] == id:
			return def
	return {}


static func get_track(id: String) -> Dictionary:
	for def: Dictionary in TRACKS:
		if def["id"] == id:
			return def
	return {}


static func get_building(id: String) -> Dictionary:
	for def: Dictionary in BUILDINGS:
		if def["id"] == id:
			return def
	return {}


static func get_algorithm(id: String) -> Dictionary:
	for def: Dictionary in ALGORITHMS:
		if def["id"] == id:
			return def
	return {}


static func get_method(id: String) -> Dictionary:
	for def: Dictionary in METHODS:
		if def["id"] == id:
			return def
	return {}


## Position of a method in the chain (0 = Beginner), or -1 for an unknown id.
static func get_method_index(id: String) -> int:
	for i in METHODS.size():
		if METHODS[i]["id"] == id:
			return i
	return -1


static func get_upgrade(id: String) -> Dictionary:
	for def: Dictionary in UPGRADES:
		if def["id"] == id:
			return def
	return {}
