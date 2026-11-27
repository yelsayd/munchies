class_name MunchiesSim
extends RefCounted
## Pure simulation for Munchies. No scene tree, no physics nodes.
## Phase 6 couch: setup slots → same step for all panes; claims exclusive; modes own respawn/elim.

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


## Compact Phase 1 layout kept for regression checks.
func setup_phase1(world_seed: int = 1) -> void:
	setup_empty(world_seed, 30.0)
	_scatter_props(0, TIER0_RADIUS, 80, Vector2(0, 0), 12.0, START_RADIUS * 2.5)
	_scatter_props(0, TIER0_RADIUS, 40, Vector2(14, -10), 8.0, 0.0)
	_scatter_props(1, TIER1_RADIUS, 36, Vector2(-8, 10), 14.0, 0.0)
	_scatter_props(1, TIER1_RADIUS, 20, Vector2(16, 12), 10.0, 0.0)
	for i in 5:
		var a: float = _rng.randf() * TAU
		var d: float = 5.0 + _rng.randf() * 5.0
		objects.append(make_prop(_alloc_id(), cos(a) * d, sin(a) * d, 1, 1.15))


## Phase 2: 160 m hand-laid map, five tiers, four corner spawns.
func setup_phase2(world_seed: int = 42, spawn_pad: int = 0) -> void:
	config = MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 1)
	_layout_phase2_map(world_seed)
	var pad: Vector2 = SPAWN_PADS[clampi(spawn_pad, 0, SPAWN_PADS.size() - 1)]
	holes.append(make_hole(_alloc_id(), pad.x, pad.y, false, 0))


## Phase 6: match from setup slots (keyboard / bot / empty). Pads deferred.
func setup_match(cfg: MatchConfig, world_seed: int = 42) -> void:
	config = cfg
	_layout_phase2_map(world_seed)
	var kinds: PackedStringArray = cfg.slots
	if kinds.is_empty():
		kinds = MatchConfig.default_slots(clampi(cfg.hole_count, 1, 4))
	var bot_names: PackedStringArray = _shuffled_bot_names()
	var bot_name_i := 0
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


func _layout_phase2_map(world_seed: int) -> void:
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

	# Road grid: arterials + secondary avenues + local connectors (cosmetic + tier-2 guides).
	roads = [
		# Main cross
		Rect2(-74, -5.5, 148, 11),
		Rect2(-5.5, -74, 11, 148),
		# Secondary avenues (E–W)
		Rect2(-74, -38, 148, 8),
		Rect2(-74, 30, 148, 8),
		# Secondary avenues (N–S)
		Rect2(-38, -74, 8, 148),
		Rect2(30, -74, 8, 148),
		# Outer ring segments near the edge
		Rect2(-70, -62, 55, 7),
		Rect2(18, -62, 52, 7),
		Rect2(-70, 52, 55, 7),
		Rect2(18, 52, 52, 7),
		Rect2(-62, -70, 7, 40),
		Rect2(-62, 28, 7, 42),
		Rect2(55, -70, 7, 40),
		Rect2(55, 28, 7, 42),
		# Short local streets / lots
		Rect2(-52, 14, 36, 7),
		Rect2(14, -42, 36, 7),
		Rect2(-48, -52, 7, 28),
		Rect2(40, 10, 7, 34),
		Rect2(16, -22, 30, 7),
		Rect2(-46, 6, 28, 7),
	]

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
	while placed < count and attempts < count * 8:
		attempts += 1
		var ang: float = _rng.randf() * TAU
		var dist: float = sqrt(_rng.randf()) * spread
		var x: float = center.x + cos(ang) * dist
		var y: float = center.y + sin(ang) * dist
		if clear_radius > 0.0 and Vector2(x, y).length() < clear_radius:
			continue
		x = clampf(x, -map_half + radius, map_half - radius)
		y = clampf(y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), x, y, tier, radius))
		placed += 1


func _scatter_along_line(tier: int, radius: float, count: int, a: Vector2, b: Vector2) -> void:
	for i in count:
		var t: float = (float(i) + 0.5) / float(count)
		var p: Vector2 = a.lerp(b, t)
		p.x += _rng.randf_range(-1.5, 1.5)
		p.y += _rng.randf_range(-1.5, 1.5)
		p.x = clampf(p.x, -map_half + radius, map_half - radius)
		p.y = clampf(p.y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), p.x, p.y, tier, radius))


func _place_on_roads(tier: int, radius: float, count: int) -> void:
	if roads.is_empty():
		_scatter_props(tier, radius, count, Vector2.ZERO, 50.0, 10.0)
		return
	for i in count:
		var road: Rect2 = roads[i % roads.size()]
		var x: float = _rng.randf_range(road.position.x + radius, road.position.x + road.size.x - radius)
		var y: float = _rng.randf_range(road.position.y + radius, road.position.y + road.size.y - radius)
		x = clampf(x, -map_half + radius, map_half - radius)
		y = clampf(y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), x, y, tier, radius))


func _place_edge_landmarks(tier: int, radius: float, positions: Array) -> void:
	for pos_v in positions:
		var pos: Vector2 = pos_v
		pos.x = clampf(pos.x, -map_half + radius, map_half - radius)
		pos.y = clampf(pos.y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), pos.x, pos.y, tier, radius))


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
			return Vector2(r * 1.4, r * 1.6)
		2:
			return Vector2(r * 2.4, r * 0.9) ## car body length × height
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
		# Static world props — no suction velocity.
		prop["vx"] = 0.0
		prop["vy"] = 0.0
		_update_prop_tip(prop, alive, dt)

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
			})

	for dead in to_remove:
		objects.erase(dead)


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
		var pos := _spawn_prop_away_from_holes(Vector2(float(item["x"]), float(item["y"])), radius)
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
