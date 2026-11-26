extends Node2D
## Draws the map: ground, parks, roads, props (large→small), all holes on top.
## Too-big props stay under holes and never block movement (sim owns that).
## Shared across split-screen panes via one World2D — every pane sees the same swallow.

const PIXELS_PER_METER := 24.0

## Distinct hues; shapes differ per tier (dot, rounded rect, capsule, square, large square).
const TIER_COLORS := {
	0: Color(0.95, 0.72, 0.35),
	1: Color(0.90, 0.45, 0.30),
	2: Color(0.35, 0.55, 0.90),
	3: Color(0.55, 0.45, 0.70),
	4: Color(0.40, 0.38, 0.42),
}

## Set by main.gd (World may live under a SubViewport, not under Main).
var host: Node = null


func _draw() -> void:
	if host == null:
		return
	var sim: MunchiesSim = host.sim as MunchiesSim
	if sim == null or sim.holes.is_empty():
		return

	var half: float = sim.map_half * PIXELS_PER_METER
	# Ground
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), Color(0.17, 0.22, 0.19))

	# Parks
	for park_v in sim.parks:
		var park: Dictionary = park_v
		var c: Vector2 = (park["center"] as Vector2) * PIXELS_PER_METER
		var r: float = float(park["radius"]) * PIXELS_PER_METER
		draw_circle(c, r, Color(0.22, 0.30, 0.22, 0.55))

	# Roads / lots
	for road_v in sim.roads:
		var road: Rect2 = road_v
		var rpx := Rect2(
			road.position * PIXELS_PER_METER,
			road.size * PIXELS_PER_METER
		)
		draw_rect(rpx, Color(0.20, 0.22, 0.24, 0.85))

	# Spawn pads (faint rings)
	for pad_v in MunchiesSim.SPAWN_PADS:
		var pad: Vector2 = pad_v * PIXELS_PER_METER
		draw_arc(pad, 2.2 * PIXELS_PER_METER, 0.0, TAU, 32, Color(0.45, 0.55, 0.50, 0.35), 2.0, true)

	# Border
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), Color(0.35, 0.42, 0.38), false, 4.0)

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
		_draw_tier_shape(tier, pos, r, col)
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
	# Every pane shares this World2D, so both sides see the same swallow.
	for tw in host.swallow_tweens:
		var t: Dictionary = tw
		var pos := Vector2(float(t["x"]), float(t["y"])) * PIXELS_PER_METER
		var r: float = float(t["radius"]) * float(t["scale"]) * PIXELS_PER_METER
		if r < 0.5:
			continue
		var col: Color = TIER_COLORS.get(int(t["tier"]), Color.WHITE) as Color
		col.a = float(t["scale"])
		_draw_tier_shape(int(t["tier"]), pos, r, col)

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
		draw_arc(hpos, hr, 0.0, TAU, 64, ring, 3.0, true)
		# Name label above hole.
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


func _draw_tier_shape(tier: int, pos: Vector2, r: float, col: Color) -> void:
	match tier:
		0:
			# Litter: small filled circle (dot).
			draw_circle(pos, r, col)
		1:
			# Street prop: rounded rect.
			var size := Vector2(r * 1.7, r * 1.3)
			var rect := Rect2(pos - size * 0.5, size)
			draw_rect(rect, col)
			draw_circle(pos + Vector2(-size.x * 0.35, 0), r * 0.45, col)
			draw_circle(pos + Vector2(size.x * 0.35, 0), r * 0.45, col)
		2:
			# Vehicle: capsule (rect + end caps).
			var half_len := r * 1.4
			var half_w := r * 0.55
			draw_rect(Rect2(pos - Vector2(half_len, half_w), Vector2(half_len * 2.0, half_w * 2.0)), col)
			draw_circle(pos + Vector2(-half_len, 0), half_w, col)
			draw_circle(pos + Vector2(half_len, 0), half_w, col)
		3:
			# Small building: square.
			var s := r * 1.6
			draw_rect(Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), col)
			draw_rect(Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), col.darkened(0.2), false, 2.0)
		_:
			# Block: larger square with inset.
			var s := r * 1.7
			draw_rect(Rect2(pos - Vector2(s, s) * 0.5, Vector2(s, s)), col)
			var inset := s * 0.55
			draw_rect(Rect2(pos - Vector2(inset, inset) * 0.5, Vector2(inset, inset)), col.lightened(0.12))
