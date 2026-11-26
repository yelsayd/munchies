extends Node2D
## Draws the map as a place: painted ground, sidewalks, roads, parks,
## litter / street props / cars / building silhouettes. Sim + prop tiers stay authority.
## Shared across split-screen panes via one World2D — every pane sees the same swallow.

const PIXELS_PER_METER := 24.0
const SIDEWALK_M := 2.2
const BLOCK_M := 16.0

## Distinct hues per tier; shapes sell the object (litter, street, car, building, block).
const TIER_COLORS := {
	0: Color(0.95, 0.72, 0.35),
	1: Color(0.90, 0.45, 0.30),
	2: Color(0.35, 0.55, 0.90),
	3: Color(0.55, 0.45, 0.70),
	4: Color(0.40, 0.38, 0.42),
}

const COL_GROUND := Color(0.18, 0.23, 0.19)
const COL_BLOCK := Color(0.20, 0.24, 0.21)
const COL_SIDEWALK := Color(0.42, 0.44, 0.40)
const COL_ROAD := Color(0.16, 0.17, 0.19)
const COL_ROAD_EDGE := Color(0.28, 0.30, 0.28)
const COL_LANE := Color(0.78, 0.72, 0.42, 0.55)
const COL_PARK := Color(0.24, 0.38, 0.24)
const COL_PARK_DEEP := Color(0.18, 0.30, 0.18)
const COL_TREE := Color(0.14, 0.28, 0.14)
const COL_TREE_TOP := Color(0.22, 0.42, 0.20)
const COL_BORDER := Color(0.38, 0.46, 0.40)

## Set by main.gd (World may live under a SubViewport, not under Main).
var host: Node = null


func _draw() -> void:
	if host == null:
		return
	var sim: MunchiesSim = host.sim as MunchiesSim
	if sim == null or sim.holes.is_empty():
		return

	var half: float = sim.map_half * PIXELS_PER_METER
	_draw_ground(half)
	_draw_city_blocks(half)
	_draw_parks(sim)
	_draw_sidewalks(sim)
	_draw_roads(sim)
	_draw_spawn_pads()
	# Border
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), COL_BORDER, false, 4.0)

	# Props large → small so litter reads on top of buildings when overlapping.
	# Holes draw after this, so too-big props sit under holes.
	var props: Array = sim.objects.duplicate()
	props.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float((a as Dictionary)["radius"]) > float((b as Dictionary)["radius"])
	)
	for prop_v in props:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue
		var pos := Vector2(float(prop["x"]), float(prop["y"])) * PIXELS_PER_METER
		var r: float = float(prop["radius"]) * PIXELS_PER_METER
		var tier: int = int(prop["tier"])
		var col: Color = TIER_COLORS.get(tier, Color.WHITE) as Color
		var facing: float = _prop_facing(prop, sim)
		_draw_tier_shape(tier, pos, r, col, int(prop["id"]), facing)
		# Contested / claimed: only the claiming hole owns the prop — ring in that hole's color.
		var claimed: int = int(prop.get("claimed_by", -1))
		if claimed != -1:
			var claimer: Dictionary = sim.hole_by_id(claimed)
			if not claimer.is_empty():
				var slot: int = int(claimer.get("slot", 0))
				var ring: Color = MunchiesSim.HOLE_RING_COLORS[clampi(slot, 0, MunchiesSim.HOLE_RING_COLORS.size() - 1)]
				ring.a = 0.85
				draw_arc(pos, r + 3.0, 0.0, TAU, 24, ring, 2.0, true)

	# Active swallow tweens (presentation only; sim already removed the prop).
	for tw in host.swallow_tweens:
		var t: Dictionary = tw
		var pos := Vector2(float(t["x"]), float(t["y"])) * PIXELS_PER_METER
		var r: float = float(t["radius"]) * float(t["scale"]) * PIXELS_PER_METER
		if r < 0.5:
			continue
		var col: Color = TIER_COLORS.get(int(t["tier"]), Color.WHITE) as Color
		col.a = float(t["scale"])
		_draw_tier_shape(int(t["tier"]), pos, r, col, 0, 0.0)

	# All holes (alive) on top; dead holes are invisible until respawn.
	for hole_v in sim.holes:
		var hole: Dictionary = hole_v
		if not bool(hole["alive"]):
			continue
		var hpos := Vector2(float(hole["x"]), float(hole["y"])) * PIXELS_PER_METER
		var hr: float = float(hole["radius"]) * PIXELS_PER_METER
		var slot: int = int(hole.get("slot", 0))
		var ring: Color = MunchiesSim.HOLE_RING_COLORS[clampi(slot, 0, MunchiesSim.HOLE_RING_COLORS.size() - 1)]
		draw_circle(hpos, hr, Color(0.04, 0.04, 0.05))
		draw_arc(hpos, hr * 0.72, 0.0, TAU, 48, Color(0.08, 0.08, 0.10, 0.7), 2.0, true)
		draw_arc(hpos, hr, 0.0, TAU, 64, ring, 3.0, true)
		var label: String = str(hole.get("name", ""))
		draw_string(
			ThemeDB.fallback_font,
			hpos + Vector2(-24, -hr - 10),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			ring
		)

		if host.swallow_flash > 0.0 and int(hole["id"]) == int(host.swallow_flash_hole):
			var flash_a: float = clampf(host.swallow_flash / 0.18, 0.0, 1.0)
			draw_arc(hpos, hr + 4.0, 0.0, TAU, 64, Color(1, 1, 1, flash_a), 3.5, true)


func _draw_ground(half: float) -> void:
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), COL_GROUND)
	# Quiet turf patches — small rectangles, not giant blobs.
	var step: float = 10.0 * PIXELS_PER_METER
	var i := -10
	while i <= 10:
		var j := -10
		while j <= 10:
			var h: float = _hash2(i * 3, j * 5)
			if h > 0.62:
				var c := Vector2(float(i) * step * 0.7, float(j) * step * 0.7)
				var w: float = step * (0.22 + h * 0.18)
				var ht: float = step * (0.16 + (1.0 - h) * 0.14)
				var tint := COL_GROUND.lightened(0.03 + h * 0.05)
				tint.a = 0.4
				draw_rect(Rect2(c - Vector2(w, ht) * 0.5, Vector2(w, ht)), tint)
			j += 1
		i += 1


func _draw_city_blocks(half: float) -> void:
	## Lot pads between the cross so the map reads as city blocks, not empty green.
	var step: float = BLOCK_M * PIXELS_PER_METER
	var margin: float = 4.0 * PIXELS_PER_METER
	var x: float = -half + margin
	while x < half - margin:
		var y: float = -half + margin
		while y < half - margin:
			var cx: float = x + step * 0.4
			var cy: float = y + step * 0.4
			if absf(cx) < 11.0 * PIXELS_PER_METER or absf(cy) < 11.0 * PIXELS_PER_METER:
				y += step
				continue
			var h: float = _hash2(int(x), int(y))
			if h < 0.28:
				y += step
				continue
			var w: float = step * (0.62 + h * 0.2)
			var ht: float = step * (0.5 + (1.0 - h) * 0.22)
			var lot := Color(0.26, 0.27, 0.25, 0.7)
			lot = lot.lightened((h - 0.5) * 0.06)
			draw_rect(Rect2(Vector2(cx - w * 0.5, cy - ht * 0.5), Vector2(w, ht)), lot)
			# Faint lot outline
			draw_rect(
				Rect2(Vector2(cx - w * 0.5, cy - ht * 0.5), Vector2(w, ht)),
				Color(0.35, 0.36, 0.33, 0.35),
				false,
				1.5
			)
			y += step
		x += step


func _draw_parks(sim: MunchiesSim) -> void:
	for park_v in sim.parks:
		var park: Dictionary = park_v
		var c: Vector2 = (park["center"] as Vector2) * PIXELS_PER_METER
		var r: float = float(park["radius"]) * PIXELS_PER_METER
		draw_circle(c, r, COL_PARK)
		draw_circle(c, r * 0.78, COL_PARK_DEEP)
		# Path ring
		draw_arc(c, r * 0.42, 0.0, TAU, 48, Color(0.48, 0.42, 0.30, 0.45), 3.0, true)
		# A few tree crowns — fixed offsets from park center (no RNG per frame).
		var tree_n: int = clampi(int(r / (4.0 * PIXELS_PER_METER)), 4, 10)
		for t in tree_n:
			var ang: float = float(t) * TAU / float(tree_n) + 0.4
			var dist: float = r * (0.55 + 0.12 * float(t % 3))
			var tp := c + Vector2(cos(ang), sin(ang)) * dist
			draw_circle(tp, r * 0.08, COL_TREE)
			draw_circle(tp + Vector2(r * 0.02, -r * 0.02), r * 0.055, COL_TREE_TOP)


func _draw_sidewalks(sim: MunchiesSim) -> void:
	var pad: float = SIDEWALK_M * PIXELS_PER_METER
	for road_v in sim.roads:
		var road: Rect2 = road_v
		var rpx := Rect2(
			road.position * PIXELS_PER_METER - Vector2(pad, pad),
			road.size * PIXELS_PER_METER + Vector2(pad * 2.0, pad * 2.0)
		)
		draw_rect(rpx, COL_SIDEWALK)


func _draw_roads(sim: MunchiesSim) -> void:
	for road_v in sim.roads:
		var road: Rect2 = road_v
		var rpx := Rect2(road.position * PIXELS_PER_METER, road.size * PIXELS_PER_METER)
		draw_rect(rpx, COL_ROAD)
		# Curb / edge stroke
		draw_rect(rpx, COL_ROAD_EDGE, false, 2.0)
		_draw_lane_dashes(rpx)


func _draw_lane_dashes(rpx: Rect2) -> void:
	var horizontal: bool = rpx.size.x >= rpx.size.y
	var dash: float = 1.6 * PIXELS_PER_METER
	var gap: float = 1.2 * PIXELS_PER_METER
	var thick: float = 0.18 * PIXELS_PER_METER
	if horizontal:
		var y: float = rpx.position.y + rpx.size.y * 0.5 - thick * 0.5
		var x: float = rpx.position.x + dash * 0.5
		var end_x: float = rpx.position.x + rpx.size.x - dash * 0.5
		while x < end_x:
			draw_rect(Rect2(Vector2(x, y), Vector2(dash, thick)), COL_LANE)
			x += dash + gap
	else:
		var x: float = rpx.position.x + rpx.size.x * 0.5 - thick * 0.5
		var y: float = rpx.position.y + dash * 0.5
		var end_y: float = rpx.position.y + rpx.size.y - dash * 0.5
		while y < end_y:
			draw_rect(Rect2(Vector2(x, y), Vector2(thick, dash)), COL_LANE)
			y += dash + gap


func _draw_spawn_pads() -> void:
	for pad_v in MunchiesSim.SPAWN_PADS:
		var pad: Vector2 = pad_v * PIXELS_PER_METER
		draw_circle(pad, 2.4 * PIXELS_PER_METER, Color(0.32, 0.36, 0.33, 0.35))
		draw_arc(pad, 2.2 * PIXELS_PER_METER, 0.0, TAU, 32, Color(0.55, 0.65, 0.58, 0.45), 2.0, true)


func _prop_facing(prop: Dictionary, sim: MunchiesSim) -> float:
	## Prefer road orientation for cars; otherwise a stable angle from id.
	var px: float = float(prop["x"])
	var py: float = float(prop["y"])
	var best_d: float = INF
	var facing: float = float(int(prop["id"]) % 8) * (PI * 0.25)
	for road_v in sim.roads:
		var road: Rect2 = road_v
		var expanded := road.grow(4.0)
		if not expanded.has_point(Vector2(px, py)):
			continue
		var cx: float = clampf(px, road.position.x, road.position.x + road.size.x)
		var cy: float = clampf(py, road.position.y, road.position.y + road.size.y)
		var d: float = Vector2(px - cx, py - cy).length()
		if d < best_d:
			best_d = d
			facing = 0.0 if road.size.x >= road.size.y else PI * 0.5
	return facing


func _draw_tier_shape(tier: int, pos: Vector2, r: float, col: Color, prop_id: int, facing: float) -> void:
	match tier:
		0:
			_draw_litter(pos, r, col, prop_id)
		1:
			_draw_street_prop(pos, r, col, prop_id)
		2:
			_draw_car(pos, r, col, facing)
		3:
			_draw_building(pos, r, col, false)
		_:
			_draw_building(pos, r, col, true)


func _draw_litter(pos: Vector2, r: float, col: Color, prop_id: int) -> void:
	## Small, high-contrast scraps so parks/trails read as food, not noise.
	var kind: int = abs(prop_id) % 3
	var outline := col.darkened(0.35)
	outline.a = minf(1.0, col.a)
	match kind:
		0:
			# Wrapper / chip bag: diamond
			var pts := PackedVector2Array([
				pos + Vector2(0, -r * 1.1),
				pos + Vector2(r * 0.9, 0),
				pos + Vector2(0, r * 1.1),
				pos + Vector2(-r * 0.9, 0),
			])
			draw_colored_polygon(pts, col)
			draw_polyline(pts + PackedVector2Array([pts[0]]), outline, 1.2, true)
		1:
			# Bottle / can: short capsule
			var half_h := r * 1.15
			var half_w := r * 0.55
			draw_rect(Rect2(pos - Vector2(half_w, half_h), Vector2(half_w * 2.0, half_h * 2.0)), col)
			draw_circle(pos + Vector2(0, -half_h), half_w, col)
			draw_circle(pos + Vector2(0, half_h), half_w, col)
			draw_circle(pos + Vector2(0, -half_h * 0.55), half_w * 0.45, col.lightened(0.25))
		_:
			# Crumpled scrap: bright dot with dark ring
			draw_circle(pos, r * 1.05, outline)
			draw_circle(pos, r * 0.75, col)
			draw_circle(pos + Vector2(r * 0.2, -r * 0.15), r * 0.28, col.lightened(0.2))


func _draw_street_prop(pos: Vector2, r: float, col: Color, prop_id: int) -> void:
	var kind: int = abs(prop_id) % 3
	match kind:
		0:
			# Bench: plank + two legs
			var plank := Vector2(r * 2.0, r * 0.55)
			draw_rect(Rect2(pos - plank * 0.5, plank), col)
			draw_rect(Rect2(pos + Vector2(-r * 0.75, r * 0.15), Vector2(r * 0.3, r * 0.55)), col.darkened(0.2))
			draw_rect(Rect2(pos + Vector2(r * 0.45, r * 0.15), Vector2(r * 0.3, r * 0.55)), col.darkened(0.2))
		1:
			# Trash bin: upright cylinder
			draw_rect(Rect2(pos - Vector2(r * 0.7, r * 0.95), Vector2(r * 1.4, r * 1.9)), col)
			draw_rect(Rect2(pos - Vector2(r * 0.85, r * 1.05), Vector2(r * 1.7, r * 0.35)), col.darkened(0.15))
			draw_rect(Rect2(pos - Vector2(r * 0.35, r * 0.35), Vector2(r * 0.7, r * 0.55)), Color(0.12, 0.12, 0.14, col.a))
		_:
			# Hydrant / bollard
			draw_circle(pos + Vector2(0, r * 0.2), r * 0.7, col)
			draw_rect(Rect2(pos - Vector2(r * 0.35, r * 1.1), Vector2(r * 0.7, r * 1.0)), col.lightened(0.1))
			draw_circle(pos + Vector2(0, -r * 0.95), r * 0.4, col.lightened(0.15))


func _draw_car(pos: Vector2, r: float, col: Color, facing: float) -> void:
	## Top-down car: tapered body, glass cabin, wheels. Facing aligns to nearest road.
	var body_len := r * 2.55
	var body_w := r * 1.2
	var axis := Vector2(cos(facing), sin(facing))
	var perp := Vector2(-axis.y, axis.x)

	draw_colored_polygon(
		_oriented_rect(pos + Vector2(r * 0.06, r * 0.06), body_len * 1.02, body_w * 1.08, axis, perp),
		Color(0, 0, 0, 0.25 * col.a)
	)
	# Body (slightly rounded via end caps)
	draw_colored_polygon(_oriented_rect(pos, body_len, body_w, axis, perp), col)
	draw_circle(pos + axis * (body_len * 0.42), body_w * 0.48, col)
	draw_circle(pos - axis * (body_len * 0.42), body_w * 0.42, col)
	# Cabin glass
	var cabin_c := pos + axis * (r * 0.12)
	draw_colored_polygon(
		_oriented_rect(cabin_c, r * 1.05, body_w * 0.72, axis, perp),
		Color(0.62, 0.78, 0.90, col.a)
	)
	# Nose stripe so facing reads
	draw_colored_polygon(
		_oriented_rect(pos + axis * (body_len * 0.38), r * 0.35, body_w * 0.55, axis, perp),
		col.lightened(0.18)
	)
	# Wheels
	var wheel_col := Color(0.08, 0.08, 0.10, col.a)
	var wheel_r := r * 0.3
	var long_off := body_len * 0.3
	var lat_off := body_w * 0.58
	draw_circle(pos + axis * long_off + perp * lat_off, wheel_r, wheel_col)
	draw_circle(pos + axis * long_off - perp * lat_off, wheel_r, wheel_col)
	draw_circle(pos - axis * long_off + perp * lat_off, wheel_r, wheel_col)
	draw_circle(pos - axis * long_off - perp * lat_off, wheel_r, wheel_col)


func _draw_building(pos: Vector2, r: float, col: Color, is_block: bool) -> void:
	## Footprint silhouette: shadow, walls, roof plate, windows. Blocks get a courtyard.
	var s: float = r * (1.9 if is_block else 1.7)
	var shadow_off := Vector2(r * 0.22, r * 0.22)
	draw_rect(Rect2(pos - Vector2(s, s) * 0.5 + shadow_off, Vector2(s, s)), Color(0, 0, 0, 0.32 * col.a))
	# Outer wall
	draw_rect(Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), col.darkened(0.08))
	# Roof inset
	var roof := s * (0.82 if is_block else 0.76)
	draw_rect(Rect2(pos - Vector2(roof, roof) * 0.5, Vector2(roof, roof)), col.lightened(0.12))
	# Parapet stroke
	draw_rect(Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), col.darkened(0.35), false, 2.5)
	# Window grid
	var win := Color(0.82, 0.88, 0.55, 0.7 * col.a)
	var cells: int = 3 if is_block else 2
	var inset: float = s * 0.16
	var cell: float = (s - inset * 2.0) / float(cells)
	for ix in cells:
		for iy in cells:
			var wx: float = pos.x - s * 0.5 + inset + (float(ix) + 0.5) * cell
			var wy: float = pos.y - s * 0.5 + inset + (float(iy) + 0.5) * cell
			var ws: float = cell * 0.38
			draw_rect(Rect2(Vector2(wx - ws * 0.5, wy - ws * 0.5), Vector2(ws, ws)), win)
	if is_block:
		var court := s * 0.34
		draw_rect(Rect2(pos - Vector2(court, court) * 0.5, Vector2(court, court)), COL_PARK.darkened(0.1))
		draw_rect(Rect2(pos - Vector2(court, court) * 0.5, Vector2(court, court)), COL_PARK_DEEP, false, 1.5)


func _oriented_rect(center: Vector2, length: float, width: float, axis: Vector2, perp: Vector2) -> PackedVector2Array:
	var hl := length * 0.5
	var hw := width * 0.5
	return PackedVector2Array([
		center + axis * hl + perp * hw,
		center - axis * hl + perp * hw,
		center - axis * hl - perp * hw,
		center + axis * hl - perp * hw,
	])


func _hash2(a: int, b: int) -> float:
	## Cheap deterministic 0..1 hash for static ground detail (no RNG per frame).
	var n: int = a * 374761393 + b * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0
