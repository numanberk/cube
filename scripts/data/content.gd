class_name Content
extends RefCounted
## All game content lives here as plain data, so balancing and adding
## new helpers/upgrades never requires touching game logic.
##
## Building fields:
##   id, name, description, base_cost (Solves), mps (moves/sec per unit),
##   unlock_at (optional, lifetime Solves needed to show it; default base_cost * 0.5)
##
## Upgrade fields:
##   id, name, description, cost (Solves), effect, requires (optional {building_id: count})
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
		"name": "Cubing Friend",
		"description": "Practices with you after school.",
		"base_cost": 5,
		"mps": 0.5,
		"unlock_at": 0,
	},
	{
		"id": "club",
		"name": "Cubing Club",
		"description": "A room full of people turning cubes.",
		"base_cost": 60,
		"mps": 4.0,
	},
	{
		"id": "robot",
		"name": "Solving Robot",
		"description": "Never gets tired. Never drops a piece.",
		"base_cost": 700,
		"mps": 32.0,
	},
	{
		"id": "competition",
		"name": "Local Competition",
		"description": "Hundreds of solves every weekend.",
		"base_cost": 9000,
		"mps": 260.0,
	},
	{
		"id": "factory",
		"name": "Cube Factory",
		"description": "Mass-produced, pre-lubed, pre-scrambled.",
		"base_cost": 120000,
		"mps": 2100.0,
	},
	{
		"id": "lab",
		"name": "Speedcubing Lab",
		"description": "Researching the perfect turn.",
		"base_cost": 1800000,
		"mps": 18000.0,
	},
]

const UPGRADES := [
	{
		"id": "lube",
		"name": "Cube Lube",
		"description": "Smoother turns. Taps make 2x moves.",
		"cost": 15,
		"effect": {"type": "tap_mult", "value": 2.0},
	},
	{
		"id": "stackmat",
		"name": "Stackmat Timer",
		"description": "Friends practice 2x faster.",
		"cost": 50,
		"effect": {"type": "building_mult", "target": "friend", "value": 2.0},
		"requires": {"friend": 1},
	},
	{
		"id": "cfop",
		"name": "Learn CFOP",
		"description": "Solves take 30% fewer moves.",
		"cost": 200,
		"effect": {"type": "solve_moves_mult", "value": 0.7},
	},
	{
		"id": "club_snacks",
		"name": "Club Snacks",
		"description": "Clubs turn 2x faster.",
		"cost": 600,
		"effect": {"type": "building_mult", "target": "club", "value": 2.0},
		"requires": {"club": 1},
	},
	{
		"id": "magnets",
		"name": "Magnetic Cube",
		"description": "Every move counts double.",
		"cost": 1500,
		"effect": {"type": "global_mult", "value": 2.0},
	},
	{
		"id": "firmware",
		"name": "Robot Firmware v2",
		"description": "Robots turn 2x faster.",
		"cost": 8000,
		"effect": {"type": "building_mult", "target": "robot", "value": 2.0},
		"requires": {"robot": 1},
	},
	{
		"id": "roux",
		"name": "Learn Roux",
		"description": "Solves take 20% fewer moves.",
		"cost": 25000,
		"effect": {"type": "solve_moves_mult", "value": 0.8},
	},
]


static func get_building(id: String) -> Dictionary:
	for def: Dictionary in BUILDINGS:
		if def["id"] == id:
			return def
	return {}


static func get_upgrade(id: String) -> Dictionary:
	for def: Dictionary in UPGRADES:
		if def["id"] == id:
			return def
	return {}
