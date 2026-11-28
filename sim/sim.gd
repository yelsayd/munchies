class_name MunchiesSim
extends RefCounted
## Pure simulation for Munchies. No scene tree, no physics nodes.
## Couch match: setup slots → same step for all panes; claims exclusive; modes own respawn/elim.

const START_RADIUS := 1.0
const START_MASS := 1.0
# Score is just mass × 10, then rounded.
# Example: mass 1.0 → score 10; mass 2.5 → score 25.
const SCORE_SCALE := 10.0

const SPEED_BASE := 14.0
## Gentler than 1/r: pow(start/r, exp). Lower exp → big holes stay faster.
const SPEED_RADIUS_EXP := 0.55
const SPEED_FLOOR := 0.45
const STEER_TAU := 0.15

## Funny names for bot holes (unique per match).
const FUNNY_BOT_NAMES := [
	"Chonkus", "Void Goblin", "Pavement Pete", "Snack Hole", "Mr. Munch",
	"Bitty Abyss", "Gulpina", "The Vacuum", "Lil Sinkhole", "Nom Nom",
	"Asphalt Annie", "Curb Crusher", "Pothole Paul", "Yum Gap", "Big Sip",
	"Munchkin", "Holey Moley", "Gulp-o-Tron", "Sir Swallows", "Nibblet",
]

# You can eat a prop only if it is a bit smaller than you.
# Gate: prop.radius ≤ hole.radius × 0.95 (not quite equal size).
# Example: hole radius 2.0 can eat props up to 1.9.
const PROP_EAT_RATIO := 0.95
## How close a hole must be to claim a prop for the contested ring (no pull).
## Claim when center distance < hole.radius × this (props stay put until covered).
const PROP_SUCTION_MULT := 2.0
## Legacy names kept so old call sites/tests can see the no-gravity switch.
## Consume is full coverage now (see prop_fully_covered); pull accel is unused.
const PROP_CONSUME_MULT := 1.0 ## unused — swallow uses full coverage
const PROP_PULL_ACCEL := 0.0 ## no gravity / no suction pull on props
const PROP_PULL_MAX_SPEED := 0.0

## All props tip when a hole contains the CoG; fall on their side if not covered.
const PROP_TIP_RATE := 2.4 ## rad/s while CoG is inside a hole
const PROP_TIP_RECOVER := 1.6 ## rad/s spring-back when CoG is free
const PROP_FALL_ANGLE := PI * 0.5 ## 90° → fallen on its side
## After this lean, cover = CoG-in-hole (rim tips can never satisfy full-disc cover).
const PROP_TIP_COMMIT := PI * 0.22
## Aliases kept for older call sites / comments.
const BUILDING_TIP_MIN_TIER := 3
const BUILDING_TIP_RATE := PROP_TIP_RATE
const BUILDING_TIP_RECOVER := PROP_TIP_RECOVER
const BUILDING_FALL_ANGLE := PROP_FALL_ANGLE
const BUILDING_TIP_COMMIT := PROP_TIP_COMMIT
## Footprint multipliers — keep in sync with world_view_3d mesh sizes.
const BUILDING_WIDTH_MULT := 1.6
const BUILDING_HEIGHT_MULT := 2.2
const BLOCK_WIDTH_MULT := 1.8
const BLOCK_HEIGHT_MULT := 2.8

const PLAYER_EAT_RATIO := 0.80
const PLAYER_SUCTION_MULT := 1.35
const PLAYER_CONSUME_MULT := 0.55
const PLAYER_PULL_ACCEL := 16.0
const PLAYER_MASS_TRANSFER := 0.60

const HOLE_RESPAWN_DELAY := 2.0
const PROP_RESPAWN_DELAY := 8.0

## Tier radii (m) from the plan table.
const TIER_RADIUS := [0.25, 0.55, 1.30, 3.20, 6.50]
const TIER0_RADIUS := 0.25
const TIER1_RADIUS := 0.55
const TIER2_RADIUS := 1.30
const TIER3_RADIUS := 3.20
const TIER4_RADIUS := 6.50

## Tier-2 road vehicles.
const VEHICLE_SEDAN := 0
const VEHICLE_VAN := 1
const VEHICLE_TRUCK := 2
const VEHICLE_SPEED_MIN := 2.0
const VEHICLE_SPEED_MAX := 4.8
const VEHICLE_COLORS := [
	Color(0.32, 0.52, 0.88), ## blue
	Color(0.86, 0.24, 0.22), ## red
	Color(0.93, 0.93, 0.90), ## white
	Color(0.14, 0.14, 0.15), ## black
	Color(0.94, 0.78, 0.22), ## yellow
	Color(0.28, 0.55, 0.36), ## green
	Color(0.58, 0.58, 0.62), ## silver
	Color(0.92, 0.48, 0.18), ## orange
]

## Special prop roles (beyond the eat-tier number).
const ROLE_PROP := 0
const ROLE_LAMP := 1
const ROLE_PERSON := 2
const LAMP_RADIUS := 0.22
const PERSON_RADIUS := 0.38
const PERSON_SPEED_MIN := 0.7
const PERSON_SPEED_MAX := 1.6
const PERSON_COLORS := [
	Color(0.55, 0.42, 0.35),
	Color(0.35, 0.40, 0.55),
	Color(0.50, 0.35, 0.45),
	Color(0.40, 0.50, 0.40),
	Color(0.60, 0.48, 0.30),
]
## Extra clearance when rejecting overlapping spawns.
const SPAWN_GAP := 0.35
## Roads / traffic continue this far past the playable map edge.
const ROAD_OVERSHOOT := 18.0
const TARGET_VEHICLES := 36
const TARGET_PEOPLE := 30
const EDGE_SPAWN_INTERVAL := 0.45

## Full map is 160 × 160 m → half-extent 80.
const MAP_HALF_DEFAULT := 80.0

## Corner spawn pads (outside the heaviest food, path inward).
const SPAWN_PADS := [
	Vector2(-55.0, -55.0),
	Vector2(55.0, -55.0),
	Vector2(-55.0, 55.0),
	Vector2(55.0, 55.0),
]

const HOLE_RING_COLORS := [
	Color(0.30, 0.85, 0.78),
	Color(0.95, 0.55, 0.35),
	Color(0.70, 0.55, 0.95),
	Color(0.95, 0.85, 0.35),
]

## Event kinds returned by step().
const EVENT_SWALLOWED := &"Swallowed"
const EVENT_SUCKED := &"Sucked"
const EVENT_ELIMINATED := &"Eliminated"
const EVENT_RESPAWNED := &"Respawned"
const EVENT_MATCH_ENDED := &"MatchEnded"

var tick: int = 0
var elapsed: float = 0.0
var map_half: float = MAP_HALF_DEFAULT
var holes: Array = [] ## Array of Dictionary
var objects: Array = [] ## Array of Dictionary
var parks: Array = [] ## Array of {center: Vector2, radius: float} for drawing
var roads: Array = [] ## Array of Rect2 in meters for drawing
var config: MatchConfig = null
var match_over: bool = false
var match_end_reason: String = ""
var winner_id: int = -1
var rankings: Array = [] ## Array of hole ids best→worst

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()
var _pending_hole_respawns: Array = [] ## {id, at}
var _pending_prop_spawns: Array = [] ## {tier, at, x, y}
var _edge_spawn_cd: float = 0.0


static func make_hole(
	id: int,
	x: float,
	y: float,
	is_bot: bool = false,
	slot: int = 0,
	hole_name: String = ""
) -> Dictionary:
	var nm: String = hole_name
	if nm.is_empty():
		nm = ("Bot %d" % (slot + 1)) if is_bot else "You"
	return {
		"id": id,
		"x": x,
		"y": y,
		"vx": 0.0,
		"vy": 0.0,
		"mass": START_MASS,
		"radius": START_RADIUS,
		"score": roundi(START_MASS * SCORE_SCALE),
		"alive": true,
		"score_changed_tick": 0,
		"is_bot": is_bot,
		"slot": slot,
		"name": nm,
	}


static func make_prop(id: int, x: float, y: float, tier: int, radius: float) -> Dictionary:
	return {
		"id": id,
		"x": x,
		"y": y,
		"vx": 0.0,
		"vy": 0.0,
		"radius": radius,
		"tier": tier,
		"claimed_by": -1,
		"alive": true,
		## Tip toward hole when CoG is inside; may fall on side if not swallowed.
		"tip_angle": 0.0,
		"fallen": false,
		"tip_dx": 1.0,
		"tip_dy": 0.0,
		## Tier-2 vehicle fields (ignored for other tiers).
		"vehicle": VEHICLE_SEDAN,
		"body_color": VEHICLE_COLORS[0],
		"road_i": -1,
		## ROLE_PROP / ROLE_LAMP / ROLE_PERSON.
		"role": ROLE_PROP,
		## People wander retarget timer (seconds).
		"wander_t": 0.0,
	}


func setup_empty(world_seed: int = 1, half: float = 30.0) -> void:
	_rng.seed = world_seed
	tick = 0
	elapsed = 0.0
	map_half = half
	_next_id = 1
	holes.clear()
	objects.clear()
	parks.clear()
	roads.clear()
	_pending_hole_respawns.clear()
	_pending_prop_spawns.clear()
	match_over = false
	match_end_reason = ""
	winner_id = -1
	rankings.clear()
	if config == null:
		config = MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 1)
	holes.append(make_hole(_alloc_id(), 0.0, 0.0, false, 0))


## Single-player sandbox on the city map (tests / unlimited smoke).
func setup_map(world_seed: int = 42, spawn_pad: int = 0) -> void:
	config = MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 1)
	_layout_map(world_seed)
	var pad: Vector2 = SPAWN_PADS[clampi(spawn_pad, 0, SPAWN_PADS.size() - 1)]
	holes.append(make_hole(_alloc_id(), pad.x, pad.y, false, 0))


## Match from setup slots (keyboard / keyboard_p2 / bot / empty). Extra pads deferred.
func setup_match(cfg: MatchConfig, world_seed: int = 42) -> void:
	config = cfg
	_layout_map(world_seed)
	var kinds: PackedStringArray = cfg.slots
	if kinds.is_empty():
		kinds = MatchConfig.default_slots(clampi(cfg.hole_count, 1, 4))
	var bot_names: PackedStringArray = _shuffled_bot_names()
	var bot_name_i := 0
	var human_n := 0
	for slot_i in mini(4, kinds.size()):
		var kind: String = str(kinds[slot_i])
		if MatchConfig.is_human_slot(kind):
			human_n += 1
	for slot_i in mini(4, kinds.size()):
		var kind: String = str(kinds[slot_i])
		if kind == MatchConfig.SLOT_EMPTY:
			continue
		var pad: Vector2 = SPAWN_PADS[slot_i]
		var is_bot: bool = kind == MatchConfig.SLOT_BOT
		var nm := "You"
		if is_bot:
			nm = str(bot_names[bot_name_i % bot_names.size()])
			bot_name_i += 1
		elif kind == MatchConfig.SLOT_KEYBOARD_P2:
			nm = "P2"
		elif human_n > 1:
			nm = "P1"
		holes.append(make_hole(_alloc_id(), pad.x, pad.y, is_bot, slot_i, nm))
	if holes.is_empty():
		# Safety: always at least the keyboard hole.
		var pad0: Vector2 = SPAWN_PADS[0]
		holes.append(make_hole(_alloc_id(), pad0.x, pad0.y, false, 0, "You"))


func _shuffled_bot_names() -> PackedStringArray:
	var names: Array = FUNNY_BOT_NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = names[i]
		names[i] = names[j]
		names[j] = tmp
	var out := PackedStringArray()
	for n in names:
		out.append(str(n))
	return out


func _layout_map(world_seed: int) -> void:
	_rng.seed = world_seed
	tick = 0
	elapsed = 0.0
	map_half = MAP_HALF_DEFAULT
	_next_id = 1
	holes.clear()
	objects.clear()
	parks.clear()
	roads.clear()
	_pending_hole_respawns.clear()
	_pending_prop_spawns.clear()
	match_over = false
	match_end_reason = ""
	winner_id = -1
	rankings.clear()

	# Parks: center + two side parks (dense tier 0 / 1).
	parks = [
		{"center": Vector2(0, 0), "radius": 18.0},
		{"center": Vector2(28, -22), "radius": 14.0},
		{"center": Vector2(-30, 24), "radius": 14.0},
	]

	# Road grid: through-streets run past the map edge so traffic can enter from off-map.
	var ext: float = map_half + ROAD_OVERSHOOT
	var span: float = ext * 2.0
	roads = [
		# Main cross (edge → edge)
		Rect2(-ext, -5.5, span, 11),
		Rect2(-5.5, -ext, 11, span),
		# Secondary avenues (E–W / N–S), also through
		Rect2(-ext, -38, span, 8),
		Rect2(-ext, 30, span, 8),
		Rect2(-38, -ext, 8, span),
		Rect2(30, -ext, 8, span),
		# Outer ring segments near the edge (reach the rim)
		Rect2(-ext, -62, ext - 18.0, 7),
		Rect2(18, -62, ext - 18.0, 7),
		Rect2(-ext, 52, ext - 18.0, 7),
		Rect2(18, 52, ext - 18.0, 7),
		Rect2(-62, -ext, 7, ext - 28.0),
		Rect2(-62, 28, 7, ext - 28.0),
		Rect2(55, -ext, 7, ext - 28.0),
		Rect2(55, 28, 7, ext - 28.0),
		# Short local streets / lots (interior)
		Rect2(-52, 14, 36, 7),
		Rect2(14, -42, 36, 7),
		Rect2(-48, -52, 7, 28),
		Rect2(40, 10, 7, 34),
		Rect2(16, -22, 30, 7),
		Rect2(-46, 6, 28, 7),
	]
	_edge_spawn_cd = 0.2

	# --- Tier 0 litter: parks + dense rings/trails at every spawn so the inward path reads ---
	_scatter_props(0, TIER0_RADIUS, 55, Vector2(0, 0), 16.0, 3.0)
	_scatter_props(0, TIER0_RADIUS, 42, Vector2(28, -22), 12.0, 2.0)
	_scatter_props(0, TIER0_RADIUS, 43, Vector2(-30, 24), 12.0, 2.0)
	# Dense litter around each corner spawn (pad clear runs after); food direction is obvious.
	for pad_v in SPAWN_PADS:
		var pad: Vector2 = pad_v
		_scatter_props(0, TIER0_RADIUS, 22, pad, 11.0, 0.0)
	# Thick trails from each spawn toward the center parks.
	_scatter_along_line(0, TIER0_RADIUS, 22, Vector2(-55, -55), Vector2(-18, -18))
	_scatter_along_line(0, TIER0_RADIUS, 22, Vector2(55, -55), Vector2(18, -18))
	_scatter_along_line(0, TIER0_RADIUS, 22, Vector2(-55, 55), Vector2(-18, 18))
	_scatter_along_line(0, TIER0_RADIUS, 22, Vector2(55, 55), Vector2(18, 18))
	# A second offset trail so the corridor reads even after a few swallows.
	_scatter_along_line(0, TIER0_RADIUS, 10, Vector2(-52, -58), Vector2(-22, -16))
	_scatter_along_line(0, TIER0_RADIUS, 10, Vector2(58, -52), Vector2(16, -22))
	_scatter_along_line(0, TIER0_RADIUS, 10, Vector2(-58, 52), Vector2(-16, 22))
	_scatter_along_line(0, TIER0_RADIUS, 10, Vector2(52, 58), Vector2(22, 16))

	# --- Tier 1 street props (70): parks + near roads ---
	_scatter_props(1, TIER1_RADIUS, 22, Vector2(0, 0), 20.0, 4.0)
	_scatter_props(1, TIER1_RADIUS, 16, Vector2(28, -22), 14.0, 3.0)
	_scatter_props(1, TIER1_RADIUS, 16, Vector2(-30, 24), 14.0, 3.0)
	_scatter_props(1, TIER1_RADIUS, 16, Vector2(0, 0), 45.0, 8.0)

	# --- Tier 2 vehicles: roads and lots (more streets → a few more cars) ---
	_place_on_roads(2, TIER2_RADIUS, 36)

	# Light poles along sidewalks; people wander parks / roadside.
	_place_lamps(28)
	_place_people(30)

	# --- Tier 3 small buildings (16): edges with path gaps ---
	_place_edge_landmarks(3, TIER3_RADIUS, [
		Vector2(-68, -20), Vector2(-68, 20),
		Vector2(68, -25), Vector2(68, 15),
		Vector2(-25, -68), Vector2(20, -68),
		Vector2(-15, 68), Vector2(25, 68),
		Vector2(-50, -60), Vector2(50, -60),
		Vector2(-50, 60), Vector2(50, 60),
		Vector2(-60, 0), Vector2(60, 5),
		Vector2(0, -62), Vector2(5, 62),
	])

	# --- Tier 4 blocks (6): far corners / edges as landmarks, not walls ---
	_place_edge_landmarks(4, TIER4_RADIUS, [
		Vector2(-70, -70),
		Vector2(70, -70),
		Vector2(-70, 70),
		Vector2(70, 70),
		Vector2(0, -72),
		Vector2(0, 72),
	])

	_clear_spawn_pads()


func _alloc_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _scatter_props(
	tier: int,
	radius: float,
	count: int,
	center: Vector2,
	spread: float,
	clear_radius: float
) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 24:
		attempts += 1
		var ang: float = _rng.randf() * TAU
		var dist: float = sqrt(_rng.randf()) * spread
		var x: float = center.x + cos(ang) * dist
		var y: float = center.y + sin(ang) * dist
		if clear_radius > 0.0 and Vector2(x, y).length() < clear_radius:
			continue
		x = clampf(x, -map_half + radius, map_half - radius)
		y = clampf(y, -map_half + radius, map_half - radius)
		if not _can_place_prop(x, y, radius):
			continue
		objects.append(make_prop(_alloc_id(), x, y, tier, radius))
		placed += 1


func _scatter_along_line(tier: int, radius: float, count: int, a: Vector2, b: Vector2) -> void:
	for i in count:
		var placed := false
		for _try in 10:
			var t: float = (float(i) + 0.5) / float(count)
			var p: Vector2 = a.lerp(b, t)
			p.x += _rng.randf_range(-1.5, 1.5)
			p.y += _rng.randf_range(-1.5, 1.5)
			p.x = clampf(p.x, -map_half + radius, map_half - radius)
			p.y = clampf(p.y, -map_half + radius, map_half - radius)
			if not _can_place_prop(p.x, p.y, radius):
				continue
			objects.append(make_prop(_alloc_id(), p.x, p.y, tier, radius))
			placed = true
			break
		if not placed:
			pass


func _place_on_roads(tier: int, radius: float, count: int) -> void:
	if roads.is_empty():
		_scatter_props(tier, radius, count, Vector2.ZERO, 50.0, 10.0)
		return
	for i in count:
		var road_i: int = i % roads.size()
		var road: Rect2 = roads[road_i]
		if tier == 2:
			var vehicle: Dictionary = _make_vehicle_on_road(road_i, road)
			if not vehicle.is_empty():
				objects.append(vehicle)
			continue
		var placed := false
		for _try in 12:
			var x: float = _rng.randf_range(road.position.x + radius, road.position.x + road.size.x - radius)
			var y: float = _rng.randf_range(road.position.y + radius, road.position.y + road.size.y - radius)
			x = clampf(x, -map_half + radius, map_half - radius)
			y = clampf(y, -map_half + radius, map_half - radius)
			if not _can_place_prop(x, y, radius):
				continue
			objects.append(make_prop(_alloc_id(), x, y, tier, radius))
			placed = true
			break
		if not placed:
			pass


func _make_vehicle_on_road(road_i: int, road: Rect2) -> Dictionary:
	var kind: int = _rng.randi_range(0, 2)
	## Wide size spread so the street reads as mixed traffic.
	var r: float = TIER2_RADIUS * _rng.randf_range(0.72, 1.12)
	if kind == VEHICLE_VAN:
		r *= _rng.randf_range(1.15, 1.4)
	elif kind == VEHICLE_TRUCK:
		r *= _rng.randf_range(1.35, 1.7)
	else:
		r *= _rng.randf_range(0.85, 1.15)
	var horizontal: bool = road.size.x >= road.size.y
	var margin: float = r * 1.4
	for _try in 16:
		var x: float
		var y: float
		if horizontal:
			if road.size.x <= margin * 2.0:
				return {}
			x = _rng.randf_range(road.position.x + margin, road.position.x + road.size.x - margin)
			y = road.position.y + road.size.y * 0.5
		else:
			if road.size.y <= margin * 2.0:
				return {}
			x = road.position.x + road.size.x * 0.5
			y = _rng.randf_range(road.position.y + margin, road.position.y + road.size.y - margin)
		x = clampf(x, -map_half + r, map_half - r)
		y = clampf(y, -map_half + r, map_half - r)
		if not _can_place_prop(x, y, r):
			continue
		var prop: Dictionary = make_prop(_alloc_id(), x, y, 2, r)
		_configure_vehicle(prop, kind, road_i, horizontal)
		return prop
	return {}


func _configure_vehicle(prop: Dictionary, kind: int, road_i: int, horizontal: bool) -> void:
	prop["vehicle"] = kind
	prop["role"] = ROLE_PROP
	prop["body_color"] = VEHICLE_COLORS[_rng.randi_range(0, VEHICLE_COLORS.size() - 1)]
	prop["road_i"] = road_i
	var speed: float = _rng.randf_range(VEHICLE_SPEED_MIN, VEHICLE_SPEED_MAX)
	var sign: float = -1.0 if _rng.randf() < 0.5 else 1.0
	if horizontal:
		prop["vx"] = speed * sign
		prop["vy"] = 0.0
	else:
		prop["vx"] = 0.0
		prop["vy"] = speed * sign


func _place_lamps(count: int) -> void:
	## Tall thin poles along sidewalks (offset from road centerlines).
	if roads.is_empty():
		return
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 20:
		attempts += 1
		var road: Rect2 = roads[_rng.randi_range(0, roads.size() - 1)]
		var horizontal: bool = road.size.x >= road.size.y
		var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
		var offset: float = road.size.y * 0.5 + 1.6 if horizontal else road.size.x * 0.5 + 1.6
		var x: float
		var y: float
		if horizontal:
			x = _rng.randf_range(road.position.x + 2.0, road.position.x + road.size.x - 2.0)
			y = road.position.y + road.size.y * 0.5 + side * offset
		else:
			x = road.position.x + road.size.x * 0.5 + side * offset
			y = _rng.randf_range(road.position.y + 2.0, road.position.y + road.size.y - 2.0)
		x = clampf(x, -map_half + LAMP_RADIUS, map_half - LAMP_RADIUS)
		y = clampf(y, -map_half + LAMP_RADIUS, map_half - LAMP_RADIUS)
		if not _can_place_prop(x, y, LAMP_RADIUS):
			continue
		var lamp: Dictionary = make_prop(_alloc_id(), x, y, 1, LAMP_RADIUS)
		lamp["role"] = ROLE_LAMP
		objects.append(lamp)
		placed += 1


func _place_people(count: int) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 24:
		attempts += 1
		var x: float
		var y: float
		if not parks.is_empty() and _rng.randf() < 0.45:
			var park: Dictionary = parks[_rng.randi_range(0, parks.size() - 1)]
			var c: Vector2 = park["center"] as Vector2
			var pr: float = float(park["radius"]) * 0.85
			var ang: float = _rng.randf() * TAU
			var dist: float = sqrt(_rng.randf()) * pr
			x = c.x + cos(ang) * dist
			y = c.y + sin(ang) * dist
		elif not roads.is_empty():
			var road: Rect2 = roads[_rng.randi_range(0, roads.size() - 1)]
			var horizontal: bool = road.size.x >= road.size.y
			var side: float = -1.0 if _rng.randf() < 0.5 else 1.0
			var offset: float = (road.size.y if horizontal else road.size.x) * 0.5 + _rng.randf_range(2.0, 4.5)
			if horizontal:
				x = _rng.randf_range(road.position.x + 2.0, road.position.x + road.size.x - 2.0)
				y = road.position.y + road.size.y * 0.5 + side * offset
			else:
				x = road.position.x + road.size.x * 0.5 + side * offset
				y = _rng.randf_range(road.position.y + 2.0, road.position.y + road.size.y - 2.0)
		else:
			x = _rng.randf_range(-map_half * 0.6, map_half * 0.6)
			y = _rng.randf_range(-map_half * 0.6, map_half * 0.6)
		x = clampf(x, -map_half + PERSON_RADIUS, map_half - PERSON_RADIUS)
		y = clampf(y, -map_half + PERSON_RADIUS, map_half - PERSON_RADIUS)
		if not _can_place_prop(x, y, PERSON_RADIUS):
			continue
		var person: Dictionary = make_prop(_alloc_id(), x, y, 1, PERSON_RADIUS)
		person["role"] = ROLE_PERSON
		person["body_color"] = PERSON_COLORS[_rng.randi_range(0, PERSON_COLORS.size() - 1)]
		_retarget_person(person)
		objects.append(person)
		placed += 1


func _retarget_person(prop: Dictionary) -> void:
	var speed: float = _rng.randf_range(PERSON_SPEED_MIN, PERSON_SPEED_MAX)
	var ang: float = _rng.randf() * TAU
	prop["vx"] = cos(ang) * speed
	prop["vy"] = sin(ang) * speed
	prop["wander_t"] = _rng.randf_range(1.2, 3.5)


func _count_alive_vehicles() -> int:
	var n := 0
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if bool(prop["alive"]) and int(prop["tier"]) == 2:
			n += 1
	return n


func _count_alive_people() -> int:
	var n := 0
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if bool(prop["alive"]) and int(prop.get("role", ROLE_PROP)) == ROLE_PERSON:
			n += 1
	return n


func _top_up_edge_traffic() -> void:
	## Keep streets busy: spawn from off-map ends of through-roads / map rim.
	## Empty-road layouts (unit tests / tiny maps) skip edge traffic entirely.
	if roads.is_empty():
		return
	if _count_alive_vehicles() < TARGET_VEHICLES:
		_try_spawn_inbound_vehicle()
	if _count_alive_people() < TARGET_PEOPLE:
		_try_spawn_inbound_person()


func _through_road_entries() -> Array:
	## Entry points just off the playable map, aimed inward along the road.
	var entries: Array = []
	for i in roads.size():
		var road: Rect2 = roads[i]
		if not _road_is_through(road):
			continue
		var horizontal: bool = road.size.x >= road.size.y
		if horizontal:
			var y: float = road.position.y + road.size.y * 0.5
			var x_lo: float = road.position.x
			var x_hi: float = road.position.x + road.size.x
			if x_lo < -map_half + 0.5:
				entries.append({
					"road_i": i,
					"x": x_lo + 1.5,
					"y": y,
					"horizontal": true,
					"sign": 1.0,
				})
			if x_hi > map_half - 0.5:
				entries.append({
					"road_i": i,
					"x": x_hi - 1.5,
					"y": y,
					"horizontal": true,
					"sign": -1.0,
				})
		else:
			var x: float = road.position.x + road.size.x * 0.5
			var y_lo: float = road.position.y
			var y_hi: float = road.position.y + road.size.y
			if y_lo < -map_half + 0.5:
				entries.append({
					"road_i": i,
					"x": x,
					"y": y_lo + 1.5,
					"horizontal": false,
					"sign": 1.0,
				})
			if y_hi > map_half - 0.5:
				entries.append({
					"road_i": i,
					"x": x,
					"y": y_hi - 1.5,
					"horizontal": false,
					"sign": -1.0,
				})
	return entries


func _try_spawn_inbound_vehicle() -> bool:
	var entries: Array = _through_road_entries()
	if entries.is_empty():
		return false
	## Shuffle a few picks so busy roads don't always win.
	for _pick in mini(6, entries.size()):
		var entry: Dictionary = entries[_rng.randi_range(0, entries.size() - 1)]
		var road_i: int = int(entry["road_i"])
		var road: Rect2 = roads[road_i]
		var kind: int = _rng.randi_range(0, 2)
		var r: float = TIER2_RADIUS * _rng.randf_range(0.72, 1.12)
		if kind == VEHICLE_VAN:
			r *= _rng.randf_range(1.15, 1.4)
		elif kind == VEHICLE_TRUCK:
			r *= _rng.randf_range(1.35, 1.7)
		else:
			r *= _rng.randf_range(0.85, 1.15)
		var x: float = float(entry["x"])
		var y: float = float(entry["y"])
		if not _can_place_prop(x, y, r):
			continue
		var prop: Dictionary = make_prop(_alloc_id(), x, y, 2, r)
		_configure_vehicle(prop, kind, road_i, bool(entry["horizontal"]))
		var speed: float = _rng.randf_range(VEHICLE_SPEED_MIN, VEHICLE_SPEED_MAX)
		var sign: float = float(entry["sign"])
		if bool(entry["horizontal"]):
			prop["vx"] = speed * sign
			prop["vy"] = 0.0
		else:
			prop["vx"] = 0.0
			prop["vy"] = speed * sign
		objects.append(prop)
		return true
	return false


func _try_spawn_inbound_person() -> bool:
	## Walk in from just past the map rim toward a point inside the city.
	for _try in 10:
		var side: int = _rng.randi_range(0, 3)
		var along: float = _rng.randf_range(-map_half * 0.92, map_half * 0.92)
		var outside: float = map_half + _rng.randf_range(3.0, ROAD_OVERSHOOT * 0.85)
		var x: float
		var y: float
		match side:
			0:
				x = -outside
				y = along
			1:
				x = outside
				y = along
			2:
				x = along
				y = -outside
			_:
				x = along
				y = outside
		if not _can_place_prop(x, y, PERSON_RADIUS):
			continue
		var person: Dictionary = make_prop(_alloc_id(), x, y, 1, PERSON_RADIUS)
		person["role"] = ROLE_PERSON
		person["body_color"] = PERSON_COLORS[_rng.randi_range(0, PERSON_COLORS.size() - 1)]
		var target := Vector2(
			_rng.randf_range(-map_half * 0.45, map_half * 0.45),
			_rng.randf_range(-map_half * 0.45, map_half * 0.45)
		)
		var dir := (target - Vector2(x, y)).normalized()
		var speed: float = _rng.randf_range(PERSON_SPEED_MIN, PERSON_SPEED_MAX)
		person["vx"] = dir.x * speed
		person["vy"] = dir.y * speed
		person["wander_t"] = _rng.randf_range(3.0, 6.0)
		objects.append(person)
		return true
	return false


func _place_edge_landmarks(tier: int, radius: float, positions: Array) -> void:
	for pos_v in positions:
		var pos: Vector2 = pos_v
		pos.x = clampf(pos.x, -map_half + radius, map_half - radius)
		pos.y = clampf(pos.y, -map_half + radius, map_half - radius)
		if not _can_place_prop(pos.x, pos.y, radius):
			## Nudge outward a bit if blocked.
			var found := false
			for _try in 8:
				var n := pos + Vector2(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4))
				n.x = clampf(n.x, -map_half + radius, map_half - radius)
				n.y = clampf(n.y, -map_half + radius, map_half - radius)
				if _can_place_prop(n.x, n.y, radius):
					pos = n
					found = true
					break
			if not found:
				continue
		objects.append(make_prop(_alloc_id(), pos.x, pos.y, tier, radius))


func _can_place_prop(x: float, y: float, radius: float, ignore_id: int = -1) -> bool:
	var p := Vector2(x, y)
	for other_v in objects:
		var other: Dictionary = other_v
		if not bool(other["alive"]):
			continue
		if int(other["id"]) == ignore_id:
			continue
		var min_d: float = radius + float(other["radius"]) + SPAWN_GAP
		if p.distance_to(Vector2(float(other["x"]), float(other["y"]))) < min_d:
			return false
	return true


static func is_mover_prop(prop: Dictionary) -> bool:
	var role: int = int(prop.get("role", ROLE_PROP))
	return int(prop.get("tier", 0)) == 2 or role == ROLE_PERSON


func _clear_spawn_pads() -> void:
	## Drop props that sit on a spawn pad so a corner start is free.
	var keep: Array = []
	for prop_v in objects:
		var prop: Dictionary = prop_v
		var p := Vector2(float(prop["x"]), float(prop["y"]))
		var blocked := false
		for pad_v in SPAWN_PADS:
			var pad: Vector2 = pad_v
			if p.distance_to(pad) < START_RADIUS * 3.0 + float(prop["radius"]):
				blocked = true
				break
		if not blocked:
			keep.append(prop)
	objects = keep


## inputs_by_hole: Dictionary[int, Vector2] with each component in [-1, 1].
## Returns Array of event Dictionaries.
func step(inputs_by_hole: Dictionary, dt: float) -> Array:
	var events: Array = []
	if dt <= 0.0 or match_over:
		return events

	tick += 1
	elapsed += dt

	_process_hole_respawns(events)
	_process_prop_respawns()

	for hole_v in holes:
		var hole: Dictionary = hole_v
		if not bool(hole["alive"]):
			continue
		var input: Vector2 = inputs_by_hole.get(int(hole["id"]), Vector2.ZERO) as Vector2
		_steer_hole(hole, input, dt)
		_clamp_hole(hole)

	_update_props(dt, events)
	if config != null and config.allow_player_eat:
		_update_player_swallow(dt, events)

	_edge_spawn_cd -= dt
	if _edge_spawn_cd <= 0.0:
		_edge_spawn_cd = EDGE_SPAWN_INTERVAL
		_top_up_edge_traffic()

	_check_match_end(events)
	return events


func _steer_hole(hole: Dictionary, input: Vector2, dt: float) -> void:
	var radius: float = float(hole["radius"])
	# Bigger hole → slower, but softer than 1/r so large holes stay playable.
	# Example: r=1 → full speed; r=2 → ~68% (was 50%); floor at SPEED_FLOOR.
	var speed_scale: float = pow(START_RADIUS / maxf(radius, 0.01), SPEED_RADIUS_EXP)
	var speed: float = SPEED_BASE * clampf(speed_scale, SPEED_FLOOR, 1.0)
	var desired := Vector2.ZERO
	var mag: float = input.length()
	if mag > 0.0001:
		# Keyboard vectors are normalized by the view; stick magnitude scales speed.
		desired = input.normalized() * speed * minf(mag, 1.0)

	var vx: float = float(hole["vx"])
	var vy: float = float(hole["vy"])
	var blend: float = 1.0 - exp(-dt / STEER_TAU)
	vx += (desired.x - vx) * blend
	vy += (desired.y - vy) * blend
	hole["vx"] = vx
	hole["vy"] = vy
	hole["x"] = float(hole["x"]) + vx * dt
	hole["y"] = float(hole["y"]) + vy * dt


func _clamp_hole(hole: Dictionary) -> void:
	var r: float = float(hole["radius"]) * 0.5
	var min_c: float = -map_half + r
	var max_c: float = map_half - r
	var x: float = float(hole["x"])
	var y: float = float(hole["y"])
	var vx: float = float(hole["vx"])
	var vy: float = float(hole["vy"])

	if x < min_c:
		x = min_c
		if vx < 0.0:
			vx = 0.0
	elif x > max_c:
		x = max_c
		if vx > 0.0:
			vx = 0.0

	if y < min_c:
		y = min_c
		if vy < 0.0:
			vy = 0.0
	elif y > max_c:
		y = max_c
		if vy > 0.0:
			vy = 0.0

	hole["x"] = x
	hole["y"] = y
	hole["vx"] = vx
	hole["vy"] = vy


func _alive_holes() -> Array:
	var out: Array = []
	for hole_v in holes:
		var hole: Dictionary = hole_v
		if bool(hole["alive"]):
			out.append(hole)
	return out


func hole_by_id(id: int) -> Dictionary:
	for hole_v in holes:
		var hole: Dictionary = hole_v
		if int(hole["id"]) == id:
			return hole
	return {}


func _add_mass(hole: Dictionary, mass_gain: float) -> void:
	hole["mass"] = float(hole["mass"]) + mass_gain
	hole["radius"] = sqrt(float(hole["mass"]))
	hole["score"] = roundi(float(hole["mass"]) * SCORE_SCALE)
	hole["score_changed_tick"] = tick


## True when a circular footprint sits inside the hole (upright props / tipping buildings).
## Example: building r=3.2 needs hole r≥3.2 and center close enough that
## distance + 3.2 ≤ hole.radius — partial overlap is not enough.
static func prop_fully_covered(dist: float, prop_radius: float, hole_radius: float) -> bool:
	return dist + prop_radius <= hole_radius


static func building_dims(prop: Dictionary) -> Vector2:
	## Returns (width, height) in meters matching the 3D building/block mesh.
	var r: float = float(prop["radius"])
	if int(prop["tier"]) >= 4:
		return Vector2(r * BLOCK_WIDTH_MULT, r * BLOCK_HEIGHT_MULT)
	return Vector2(r * BUILDING_WIDTH_MULT, r * BUILDING_HEIGHT_MULT)


## (hinge footprint width, mesh height) for tip pivot — match world_view_3d meshes.
static func prop_tip_dims(prop: Dictionary) -> Vector2:
	var r: float = float(prop["radius"])
	match int(prop.get("tier", 0)):
		0:
			return Vector2(r * 1.2, r * 0.6)
		1:
			if int(prop.get("role", ROLE_PROP)) == ROLE_LAMP:
				return Vector2(r * 0.6, r * 8.0) ## thin tall pole
			if int(prop.get("role", ROLE_PROP)) == ROLE_PERSON:
				return Vector2(r * 0.9, r * 2.4)
			return Vector2(r * 1.4, r * 1.6)
		2:
			var kind: int = int(prop.get("vehicle", VEHICLE_SEDAN))
			if kind == VEHICLE_TRUCK:
				return Vector2(r * 3.1, r * 1.15)
			if kind == VEHICLE_VAN:
				return Vector2(r * 2.6, r * 1.2)
			return Vector2(r * 2.5, r * 0.95) ## sedan length × height
		3:
			return Vector2(r * BUILDING_WIDTH_MULT, r * BUILDING_HEIGHT_MULT)
		_:
			return Vector2(r * BLOCK_WIDTH_MULT, r * BLOCK_HEIGHT_MULT)


static func is_building_prop(prop: Dictionary) -> bool:
	return int(prop.get("tier", 0)) >= BUILDING_TIP_MIN_TIER


## Steer / seek point for a prop (CoG).
static func prop_cover_center(prop: Dictionary) -> Vector2:
	return Vector2(float(prop["x"]), float(prop["y"]))


static func prop_cover_radius(prop: Dictionary) -> float:
	return float(prop["radius"])


## True when this hole is big enough to finish the prop (size gate).
## Once CoG is inside and tip commits, any prop swallows the same way.
static func hole_can_cover_prop(hole_radius: float, prop: Dictionary) -> bool:
	return float(prop["radius"]) <= hole_radius * PROP_EAT_RATIO


static func prop_tip_committed(prop: Dictionary) -> bool:
	return bool(prop.get("fallen", false)) \
		or float(prop.get("tip_angle", 0.0)) >= PROP_TIP_COMMIT


static func building_tip_committed(prop: Dictionary) -> bool:
	return prop_tip_committed(prop)


## Cover test. Upright: full disc. Tip-committed / fallen: CoG inside the hole.
static func hole_covers_prop(hole: Dictionary, prop: Dictionary) -> bool:
	var hr: float = float(hole["radius"])
	var hx: float = float(hole["x"])
	var hy: float = float(hole["y"])
	var px: float = float(prop["x"])
	var py: float = float(prop["y"])
	var cdist: float = Vector2(hx - px, hy - py).length()
	if prop_tip_committed(prop):
		return cdist <= hr
	return prop_fully_covered(cdist, float(prop["radius"]), hr)


func _update_prop_tip(prop: Dictionary, alive: Array, dt: float) -> void:
	if bool(prop.get("fallen", false)):
		prop["tip_angle"] = PROP_FALL_ANGLE
		return

	var px: float = float(prop["x"])
	var py: float = float(prop["y"])
	# Closest hole whose disc contains the CoG drives the tip.
	var tip_hole: Dictionary = {}
	var tip_dist: float = INF
	for hole_v in alive:
		var hole: Dictionary = hole_v
		var hx: float = float(hole["x"])
		var hy: float = float(hole["y"])
		var hr: float = float(hole["radius"])
		var d: float = Vector2(hx - px, hy - py).length()
		if d <= hr and d < tip_dist:
			tip_dist = d
			tip_hole = hole

	var angle: float = float(prop.get("tip_angle", 0.0))
	if not tip_hole.is_empty():
		var dir := Vector2(float(tip_hole["x"]) - px, float(tip_hole["y"]) - py)
		if dir.length_squared() > 0.0001:
			dir = dir.normalized()
			prop["tip_dx"] = dir.x
			prop["tip_dy"] = dir.y
		angle = minf(PROP_FALL_ANGLE, angle + PROP_TIP_RATE * dt)
		if angle >= PROP_FALL_ANGLE - 0.001:
			prop["fallen"] = true
			angle = PROP_FALL_ANGLE
	else:
		angle = maxf(0.0, angle - PROP_TIP_RECOVER * dt)
	prop["tip_angle"] = angle


func _update_props(dt: float, events: Array) -> void:
	## No gravity: props do not get pulled. Cover (or tip-commit + CoG) to swallow.
	## Every prop tips when a hole crosses its CoG; may fall on its side if not covered.
	var alive: Array = _alive_holes()
	if alive.is_empty():
		return

	var to_remove: Array = []

	for prop_v in objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue

		var px: float = float(prop["x"])
		var py: float = float(prop["y"])
		var pr: float = float(prop["radius"])
		_update_prop_tip(prop, alive, dt)
		var upright: bool = (
			not bool(prop.get("fallen", false))
			and float(prop.get("tip_angle", 0.0)) < 0.05
		)
		if upright and int(prop["tier"]) == 2:
			if _drive_vehicle(prop, dt):
				prop["alive"] = false
				to_remove.append(prop)
				continue
			px = float(prop["x"])
			py = float(prop["y"])
		elif upright and int(prop.get("role", ROLE_PROP)) == ROLE_PERSON:
			if _drive_person(prop, dt):
				prop["alive"] = false
				to_remove.append(prop)
				continue
			px = float(prop["x"])
			py = float(prop["y"])
		else:
			prop["vx"] = 0.0
			prop["vy"] = 0.0

		# Closest qualifying hole claims (ring UI); others ignore a claimed prop.
		var best_hole: Dictionary = {}
		var best_dist: float = INF
		for hole_v in alive:
			var hole: Dictionary = hole_v
			var hr: float = float(hole["radius"])
			if pr > hr * PROP_EAT_RATIO:
				continue
			var dx: float = float(hole["x"]) - px
			var dy: float = float(hole["y"]) - py
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < hr * PROP_SUCTION_MULT and dist < best_dist:
				best_dist = dist
				best_hole = hole

		if best_hole.is_empty():
			prop["claimed_by"] = -1
			continue

		var hole_id: int = int(best_hole["id"])
		var claimed: int = int(prop["claimed_by"])
		if claimed != -1 and claimed != hole_id:
			# Another hole already owns it — only the claimer keeps the ring.
			var still_claimer := false
			for hole_v2 in alive:
				var h2: Dictionary = hole_v2
				if int(h2["id"]) == claimed:
					var hr2: float = float(h2["radius"])
					if pr <= hr2 * PROP_EAT_RATIO:
						var ddx: float = float(h2["x"]) - px
						var ddy: float = float(h2["y"]) - py
						var d2: float = sqrt(ddx * ddx + ddy * ddy)
						if d2 < hr2 * PROP_SUCTION_MULT:
							best_hole = h2
							best_dist = d2
							hole_id = claimed
							still_claimer = true
					break
			if not still_claimer:
				prop["claimed_by"] = hole_id
		else:
			prop["claimed_by"] = hole_id

		var hr: float = float(best_hole["radius"])
		var eat_limit: float = hr * PROP_EAT_RATIO
		# Swallow only when the current footprint is fully inside (and size gate).
		if pr <= eat_limit and hole_covers_prop(best_hole, prop):
			var mass_gain: float = pr * pr
			_add_mass(best_hole, mass_gain)
			prop["alive"] = false
			to_remove.append(prop)
			if config != null and config.respawn_props:
				_pending_prop_spawns.append({
					"tier": int(prop["tier"]),
					"at": elapsed + PROP_RESPAWN_DELAY,
					"x": px,
					"y": py,
				})
			events.append({
				"kind": EVENT_SWALLOWED,
				"hole_id": hole_id,
				"prop_id": prop["id"],
				"mass_gained": mass_gain,
				"tier": prop["tier"],
				"x": px,
				"y": py,
				"radius": pr,
				## Presentation: fall-in-place keeps tip pose while dropping.
				"tip_angle": float(prop.get("tip_angle", 0.0)),
				"fallen": bool(prop.get("fallen", false)),
				"tip_dx": float(prop.get("tip_dx", 1.0)),
				"tip_dy": float(prop.get("tip_dy", 0.0)),
				"role": int(prop.get("role", ROLE_PROP)),
				"vehicle": int(prop.get("vehicle", VEHICLE_SEDAN)),
				"body_color": prop.get("body_color", VEHICLE_COLORS[0]),
			})

	for dead in to_remove:
		objects.erase(dead)

	_resolve_mover_collisions()


func _drive_person(prop: Dictionary, dt: float) -> bool:
	## Walk freely; leave the map when past the road overshoot (edge spawn replaces them).
	prop["wander_t"] = float(prop.get("wander_t", 0.0)) - dt
	if float(prop["wander_t"]) <= 0.0:
		_retarget_person(prop)
	var x: float = float(prop["x"]) + float(prop["vx"]) * dt
	var y: float = float(prop["y"]) + float(prop["vy"]) * dt
	prop["x"] = x
	prop["y"] = y
	var lim: float = map_half + ROAD_OVERSHOOT + 1.0
	return absf(x) > lim or absf(y) > lim


func _resolve_mover_collisions() -> void:
	## Keep moving cars/people from stacking; bounce soft off static props too.
	var movers: Array = []
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue
		if bool(prop.get("fallen", false)) or float(prop.get("tip_angle", 0.0)) >= 0.05:
			continue
		if is_mover_prop(prop):
			movers.append(prop)
	for i in movers.size():
		var a: Dictionary = movers[i]
		var ax: float = float(a["x"])
		var ay: float = float(a["y"])
		var ar: float = float(a["radius"])
		# Movers vs movers.
		for j in range(i + 1, movers.size()):
			var b: Dictionary = movers[j]
			var bx: float = float(b["x"])
			var by: float = float(b["y"])
			var br: float = float(b["radius"])
			var dx: float = bx - ax
			var dy: float = by - ay
			var dist: float = sqrt(dx * dx + dy * dy)
			var min_d: float = ar + br + 0.05
			if dist >= min_d or dist < 0.0001:
				continue
			var nx: float = dx / dist
			var ny: float = dy / dist
			var push: float = (min_d - dist) * 0.5
			a["x"] = ax - nx * push
			a["y"] = ay - ny * push
			b["x"] = bx + nx * push
			b["y"] = by + ny * push
			ax = float(a["x"])
			ay = float(a["y"])
			# Flip velocity components along the contact for cars on rails / walkers.
			var avx: float = float(a["vx"])
			var avy: float = float(a["vy"])
			var bvx: float = float(b["vx"])
			var bvy: float = float(b["vy"])
			var a_along: float = avx * nx + avy * ny
			var b_along: float = bvx * nx + bvy * ny
			if a_along > 0.0:
				a["vx"] = avx - nx * a_along * 2.0
				a["vy"] = avy - ny * a_along * 2.0
			if b_along < 0.0:
				b["vx"] = bvx - nx * b_along * 2.0
				b["vy"] = bvy - ny * b_along * 2.0
			# Road cars: keep axis-aligned after bounce.
			if int(a["tier"]) == 2:
				_realign_vehicle_velocity(a)
			if int(b["tier"]) == 2:
				_realign_vehicle_velocity(b)
		# Movers vs solid statics (buildings / lamps / street furniture).
		for other_v in objects:
			var other: Dictionary = other_v
			if not bool(other["alive"]) or int(other["id"]) == int(a["id"]):
				continue
			if is_mover_prop(other):
				continue
			var ox: float = float(other["x"])
			var oy: float = float(other["y"])
			var orad: float = float(other["radius"])
			# Buildings use a wider block footprint.
			if int(other["tier"]) >= 3:
				orad *= 1.35
			var dx2: float = ax - ox
			var dy2: float = ay - oy
			var dist2: float = sqrt(dx2 * dx2 + dy2 * dy2)
			var min2: float = ar + orad + 0.05
			if dist2 >= min2 or dist2 < 0.0001:
				continue
			var nx2: float = dx2 / dist2
			var ny2: float = dy2 / dist2
			var push2: float = min2 - dist2
			a["x"] = ax + nx2 * push2
			a["y"] = ay + ny2 * push2
			ax = float(a["x"])
			ay = float(a["y"])
			var along: float = float(a["vx"]) * nx2 + float(a["vy"]) * ny2
			if along < 0.0:
				a["vx"] = float(a["vx"]) - nx2 * along * 2.0
				a["vy"] = float(a["vy"]) - ny2 * along * 2.0
			if int(a["tier"]) == 2:
				_realign_vehicle_velocity(a)
			elif int(a.get("role", ROLE_PROP)) == ROLE_PERSON:
				_retarget_person(a)


func _realign_vehicle_velocity(prop: Dictionary) -> void:
	## After a collision, restore axis-aligned road motion at a varied cruise speed.
	var road_i: int = int(prop.get("road_i", -1))
	var horizontal := true
	if road_i >= 0 and road_i < roads.size():
		var road: Rect2 = roads[road_i]
		horizontal = road.size.x >= road.size.y
	var speed: float = maxf(absf(float(prop["vx"])), absf(float(prop["vy"])))
	if speed < VEHICLE_SPEED_MIN * 0.5:
		speed = _rng.randf_range(VEHICLE_SPEED_MIN, VEHICLE_SPEED_MAX)
	speed = clampf(speed, VEHICLE_SPEED_MIN, VEHICLE_SPEED_MAX)
	if horizontal:
		var sign_x: float = -1.0 if float(prop["vx"]) < 0.0 else 1.0
		prop["vx"] = speed * sign_x
		prop["vy"] = 0.0
	else:
		var sign_y: float = -1.0 if float(prop["vy"]) < 0.0 else 1.0
		prop["vx"] = 0.0
		prop["vy"] = speed * sign_y


func _road_is_through(road: Rect2) -> bool:
	## Through-streets reach past the playable map so traffic can enter/exit off-screen.
	if road.size.x >= road.size.y:
		return (
			road.position.x < -map_half + 0.5
			or road.position.x + road.size.x > map_half - 0.5
		)
	return (
		road.position.y < -map_half + 0.5
		or road.position.y + road.size.y > map_half - 0.5
	)


func _drive_vehicle(prop: Dictionary, dt: float) -> bool:
	## Keep tier-2 vehicles on their road centerline.
	## Through-roads: cruise off the map ends. Local streets: bounce at the ends.
	var road_i: int = int(prop.get("road_i", -1))
	if road_i < 0 or road_i >= roads.size():
		road_i = _find_road_index(float(prop["x"]), float(prop["y"]))
		prop["road_i"] = road_i
	if road_i < 0 or road_i >= roads.size():
		## No road (tests / tipped leftovers): stay put, do not cull.
		prop["vx"] = 0.0
		prop["vy"] = 0.0
		return false
	var road: Rect2 = roads[road_i]
	var r: float = float(prop["radius"])
	var horizontal: bool = road.size.x >= road.size.y
	var through: bool = _road_is_through(road)
	var speed: float = maxf(absf(float(prop["vx"])), absf(float(prop["vy"])))
	if speed < 0.5:
		speed = lerpf(VEHICLE_SPEED_MIN, VEHICLE_SPEED_MAX, 0.5)
	var x: float = float(prop["x"]) + float(prop["vx"]) * dt
	var y: float = float(prop["y"]) + float(prop["vy"]) * dt
	if horizontal:
		y = road.position.y + road.size.y * 0.5
		prop["vy"] = 0.0
		if absf(float(prop["vx"])) < 0.5:
			prop["vx"] = speed
		if through:
			var pad: float = r + 0.75
			if x < road.position.x - pad or x > road.position.x + road.size.x + pad:
				prop["x"] = x
				prop["y"] = y
				return true
		else:
			var min_x: float = road.position.x + r
			var max_x: float = road.position.x + road.size.x - r
			if x <= min_x:
				x = min_x
				prop["vx"] = speed
			elif x >= max_x:
				x = max_x
				prop["vx"] = -speed
	else:
		x = road.position.x + road.size.x * 0.5
		prop["vx"] = 0.0
		if absf(float(prop["vy"])) < 0.5:
			prop["vy"] = speed
		if through:
			var pad_y: float = r + 0.75
			if y < road.position.y - pad_y or y > road.position.y + road.size.y + pad_y:
				prop["x"] = x
				prop["y"] = y
				return true
		else:
			var min_y: float = road.position.y + r
			var max_y: float = road.position.y + road.size.y - r
			if y <= min_y:
				y = min_y
				prop["vy"] = speed
			elif y >= max_y:
				y = max_y
				prop["vy"] = -speed
	prop["x"] = x
	prop["y"] = y
	if not through:
		prop["x"] = clampf(x, -map_half + r, map_half - r)
		prop["y"] = clampf(y, -map_half + r, map_half - r)
	return false


func _find_road_index(x: float, y: float) -> int:
	var best_i := -1
	var best_d: float = INF
	var p := Vector2(x, y)
	for i in roads.size():
		var road: Rect2 = roads[i]
		var expanded := road.grow(2.0)
		if not expanded.has_point(p):
			continue
		var cx: float = clampf(x, road.position.x, road.position.x + road.size.x)
		var cy: float = clampf(y, road.position.y, road.position.y + road.size.y)
		var d: float = p.distance_to(Vector2(cx, cy))
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


func _update_player_swallow(dt: float, events: Array) -> void:
	var alive: Array = _alive_holes()
	if alive.size() < 2:
		return

	# Snapshot ids so we do not double-process in one tick.
	var eliminated_ids: Dictionary = {} ## id -> true

	for attacker_v in alive:
		var attacker: Dictionary = attacker_v
		var aid: int = int(attacker["id"])
		if eliminated_ids.has(aid):
			continue
		var ax: float = float(attacker["x"])
		var ay: float = float(attacker["y"])
		var ar: float = float(attacker["radius"])

		for victim_v in alive:
			var victim: Dictionary = victim_v
			var vid: int = int(victim["id"])
			if vid == aid or eliminated_ids.has(vid) or not bool(victim["alive"]):
				continue
			var vr: float = float(victim["radius"])
			if vr > ar * PLAYER_EAT_RATIO:
				continue
			var vx: float = float(victim["x"])
			var vy: float = float(victim["y"])
			var dx: float = ax - vx
			var dy: float = ay - vy
			var dist: float = sqrt(dx * dx + dy * dy)
			var suction: float = ar * PLAYER_SUCTION_MULT
			if dist >= suction:
				continue

			# Pull victim toward attacker; victim can still steer (already applied this tick).
			if dist > 0.0001:
				var nx: float = dx / dist
				var ny: float = dy / dist
				victim["vx"] = float(victim["vx"]) + nx * PLAYER_PULL_ACCEL * dt
				victim["vy"] = float(victim["vy"]) + ny * PLAYER_PULL_ACCEL * dt
				victim["x"] = vx + float(victim["vx"]) * dt
				victim["y"] = vy + float(victim["vy"]) * dt
				_clamp_hole(victim)
				dx = ax - float(victim["x"])
				dy = ay - float(victim["y"])
				dist = sqrt(dx * dx + dy * dy)

			if dist < ar * PLAYER_CONSUME_MULT and float(victim["radius"]) <= ar * PLAYER_EAT_RATIO:
				var transfer: float = float(victim["mass"]) * PLAYER_MASS_TRANSFER
				_add_mass(attacker, transfer)
				victim["alive"] = false
				victim["vx"] = 0.0
				victim["vy"] = 0.0
				eliminated_ids[vid] = true
				_release_claims(vid)
				if config != null and config.respawn_holes:
					_pending_hole_respawns.append({"id": vid, "at": elapsed + HOLE_RESPAWN_DELAY})
				events.append({
					"kind": EVENT_ELIMINATED,
					"hole_id": aid,
					"victim_id": vid,
					"mass_gained": transfer,
					"x": victim["x"],
					"y": victim["y"],
				})


func _release_claims(hole_id: int) -> void:
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if int(prop["claimed_by"]) == hole_id:
			prop["claimed_by"] = -1


func _process_hole_respawns(events: Array) -> void:
	if config == null or not config.respawn_holes:
		_pending_hole_respawns.clear()
		return
	var keep: Array = []
	for item_v in _pending_hole_respawns:
		var item: Dictionary = item_v
		if float(item["at"]) > elapsed:
			keep.append(item)
			continue
		var hole: Dictionary = hole_by_id(int(item["id"]))
		if hole.is_empty() or bool(hole["alive"]):
			continue
		var pad: Vector2 = _free_spawn_pad()
		hole["x"] = pad.x
		hole["y"] = pad.y
		hole["vx"] = 0.0
		hole["vy"] = 0.0
		hole["mass"] = START_MASS
		hole["radius"] = START_RADIUS
		# Score kept.
		hole["alive"] = true
		events.append({
			"kind": EVENT_RESPAWNED,
			"hole_id": int(hole["id"]),
			"x": pad.x,
			"y": pad.y,
		})
	_pending_hole_respawns = keep


func _free_spawn_pad() -> Vector2:
	## Prefer a pad farthest from alive holes.
	var best: Vector2 = SPAWN_PADS[0]
	var best_score: float = -1.0
	for pad_v in SPAWN_PADS:
		var pad: Vector2 = pad_v
		var min_d: float = INF
		for hole_v in _alive_holes():
			var hole: Dictionary = hole_v
			var d: float = pad.distance_to(Vector2(float(hole["x"]), float(hole["y"])))
			if d < min_d:
				min_d = d
		if min_d > best_score:
			best_score = min_d
			best = pad
	return best


func _process_prop_respawns() -> void:
	if config == null or not config.respawn_props:
		_pending_prop_spawns.clear()
		return
	var keep: Array = []
	for item_v in _pending_prop_spawns:
		var item: Dictionary = item_v
		if float(item["at"]) > elapsed:
			keep.append(item)
			continue
		var tier: int = int(item["tier"])
		var radius: float = float(TIER_RADIUS[clampi(tier, 0, TIER_RADIUS.size() - 1)])
		if tier == 2 and not roads.is_empty():
			var road_i: int = _rng.randi_range(0, roads.size() - 1)
			var vehicle: Dictionary = _make_vehicle_on_road(road_i, roads[road_i])
			if not vehicle.is_empty():
				objects.append(vehicle)
			continue
		var pos := _spawn_prop_away_from_holes(Vector2(float(item["x"]), float(item["y"])), radius)
		if not _can_place_prop(pos.x, pos.y, radius):
			continue
		objects.append(make_prop(_alloc_id(), pos.x, pos.y, tier, radius))
	_pending_prop_spawns = keep


func _spawn_prop_away_from_holes(near: Vector2, radius: float) -> Vector2:
	for _attempt in 24:
		var ang: float = _rng.randf() * TAU
		var dist: float = 4.0 + _rng.randf() * 18.0
		var p := Vector2(
			clampf(near.x + cos(ang) * dist, -map_half + radius, map_half - radius),
			clampf(near.y + sin(ang) * dist, -map_half + radius, map_half - radius)
		)
		var clear := true
		for hole_v in _alive_holes():
			var hole: Dictionary = hole_v
			var suction: float = float(hole["radius"]) * PROP_SUCTION_MULT
			if p.distance_to(Vector2(float(hole["x"]), float(hole["y"]))) < suction + radius:
				clear = false
				break
		if clear:
			return p
	return Vector2(
		clampf(near.x, -map_half + radius, map_half - radius),
		clampf(near.y, -map_half + radius, map_half - radius)
	)


func _check_match_end(events: Array) -> void:
	if match_over or config == null:
		return
	match config.mode:
		MatchConfig.Mode.UNLIMITED:
			return
		MatchConfig.Mode.TIMER:
			if elapsed >= config.duration:
				_end_match("Time", _rank_holes(), events)
		MatchConfig.Mode.SCORE_TARGET:
			for hole_v in holes:
				var hole: Dictionary = hole_v
				if bool(hole["alive"]) and int(hole["score"]) >= config.score_target:
					_end_match(config.end_title(), _rank_holes(), events)
					return
		MatchConfig.Mode.MAP_CLEARED:
			if not any_swallowable_prop():
				_end_match("Map cleared", _rank_holes(), events)
		MatchConfig.Mode.LAST_STANDING:
			var alive: Array = _alive_holes()
			if alive.size() == 1:
				_end_match("Last hole standing", _rank_holes(), events)
			elif alive.is_empty():
				_end_match("Last hole standing", _rank_holes(), events)
			elif not any_swallowable_prop() and not any_player_eat_pair():
				# Fallback so a couch session cannot sit forever.
				_end_match("Last hole standing", _rank_holes(), events)


func _end_match(reason: String, ranked: Array, events: Array) -> void:
	match_over = true
	match_end_reason = reason
	rankings = ranked
	winner_id = int(ranked[0]) if ranked.size() > 0 else -1
	events.append({
		"kind": EVENT_MATCH_ENDED,
		"reason": reason,
		"winner_id": winner_id,
		"rankings": rankings.duplicate(),
	})


## Tie-break: higher score, then larger radius, then earlier score_changed_tick.
func _rank_holes() -> Array:
	var list: Array = holes.duplicate()
	list.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ha: Dictionary = a
		var hb: Dictionary = b
		var sa: int = int(ha["score"])
		var sb: int = int(hb["score"])
		if sa != sb:
			return sa > sb
		var ra: float = float(ha["radius"])
		var rb: float = float(hb["radius"])
		if not is_equal_approx(ra, rb):
			return ra > rb
		return int(ha["score_changed_tick"]) < int(hb["score_changed_tick"])
	)
	var ids: Array = []
	for h in list:
		ids.append(int((h as Dictionary)["id"]))
	return ids


func any_swallowable_prop() -> bool:
	var alive: Array = _alive_holes()
	if alive.is_empty():
		return false
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue
		var pr: float = float(prop["radius"])
		for hole_v in alive:
			var hole: Dictionary = hole_v
			if pr <= float(hole["radius"]) * PROP_EAT_RATIO:
				return true
	return false


func any_player_eat_pair() -> bool:
	var alive: Array = _alive_holes()
	for a_v in alive:
		var a: Dictionary = a_v
		for b_v in alive:
			var b: Dictionary = b_v
			if int(a["id"]) == int(b["id"]):
				continue
			if float(b["radius"]) <= float(a["radius"]) * PLAYER_EAT_RATIO:
				return true
	return false


func swallowable_prop_count() -> int:
	var n := 0
	var alive: Array = _alive_holes()
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue
		var pr: float = float(prop["radius"])
		for hole_v in alive:
			var hole: Dictionary = hole_v
			if pr <= float(hole["radius"]) * PROP_EAT_RATIO:
				n += 1
				break
	return n


func player_hole() -> Dictionary:
	for hole_v in holes:
		var hole: Dictionary = hole_v
		if not bool(hole.get("is_bot", false)):
			return hole
	return holes[0] as Dictionary


func alive_prop_count() -> int:
	var n := 0
	for p in objects:
		if p["alive"]:
			n += 1
	return n


func count_by_tier() -> Dictionary:
	var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	for p in objects:
		if not p["alive"]:
			continue
		var t: int = int(p["tier"])
		counts[t] = int(counts.get(t, 0)) + 1
	return counts


func time_remaining() -> float:
	if config == null or config.mode != MatchConfig.Mode.TIMER:
		return 0.0
	return maxf(0.0, config.duration - elapsed)
