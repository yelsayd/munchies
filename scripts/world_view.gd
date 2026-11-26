extends Node2D
## Draws the Phase 1 map: ground, props (large→small), hole. No physics bodies.

const PIXELS_PER_METER := 24.0

const TIER_COLORS := {
	0: Color(0.95, 0.72, 0.35),
	1: Color(0.90, 0.40, 0.28),
}

@onready var main: Node2D = get_parent()


func _draw() -> void:
	var sim: MunchiesSim = main.sim as MunchiesSim
	if sim == null:
		return

	var half: float = sim.map_half * PIXELS_PER_METER
	# Ground
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), Color(0.18, 0.24, 0.20))
	# Park tint (center + second clump)
	draw_circle(Vector2.ZERO, 12.0 * PIXELS_PER_METER, Color(0.22, 0.30, 0.22, 0.55))
	draw_circle(Vector2(14, -10) * PIXELS_PER_METER, 8.0 * PIXELS_PER_METER, Color(0.22, 0.30, 0.22, 0.45))
	# Border
	draw_rect(Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)), Color(0.35, 0.42, 0.38), false, 3.0)

	# Props large → small so litter sits on top of street props when overlapping.
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
		var col: Color = TIER_COLORS.get(int(prop["tier"]), Color.WHITE) as Color
		# Oversized stand-ins (radius > normal tier 1) read as darker so the gate is visible.
		if float(prop["radius"]) > MunchiesSim.TIER1_RADIUS + 0.01:
			col = Color(0.55, 0.22, 0.18)
		draw_circle(pos, r, col)
		draw_arc(pos, r, 0.0, TAU, 24, col.darkened(0.25), 1.5, true)

	# Hole on top
	var hole: Dictionary = sim.player_hole()
	var hpos := Vector2(float(hole["x"]), float(hole["y"])) * PIXELS_PER_METER
	var hr: float = float(hole["radius"]) * PIXELS_PER_METER
	draw_circle(hpos, hr, Color(0.04, 0.04, 0.05))
	draw_arc(hpos, hr, 0.0, TAU, 48, main.hole_ring_color, 3.0, true)
