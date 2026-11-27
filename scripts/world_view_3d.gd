extends Node3D
## Presentation-only 3D skin over the sim.
## Reads sim x/y/radius each frame; never writes claims, modes, or step state.
## Y-up: sim (x, y) → world (x, 0, y). One unit = one meter.

const TIER_COLORS := {
	0: Color(0.95, 0.72, 0.35),
	1: Color(0.90, 0.45, 0.30),
	2: Color(0.35, 0.55, 0.90),
	3: Color(0.55, 0.45, 0.70),
	4: Color(0.40, 0.38, 0.42),
}

const COL_GROUND := Color(0.18, 0.23, 0.19)
const COL_SIDEWALK := Color(0.42, 0.44, 0.40)
const COL_ROAD := Color(0.16, 0.17, 0.19)
const COL_LANE := Color(0.78, 0.72, 0.42, 0.85)
const COL_PARK := Color(0.24, 0.38, 0.24)
const COL_BORDER := Color(0.38, 0.46, 0.40)
const SIDEWALK_M := 2.2
## Road top ≈ 0.085 m; hole fill/rim/flash sit clearly above so roads never occlude them.
const HOLE_FILL_Y := 0.12
const HOLE_RIM_Y := 0.16
const HOLE_FLASH_Y := 0.185
const LANE_Y := 0.095

## Set by main.gd (World3D may live under a SubViewport).
var host: Node = null

var _static_seed: int = -1
var _static_root: Node3D
var _props_root: Node3D
var _holes_root: Node3D
var _tweens_root: Node3D
var _prop_nodes: Dictionary = {} ## id -> Node3D (composite prop)
var _hole_nodes: Dictionary = {} ## id -> Node3D (pit + ring)
var _tween_nodes: Array = []
var _mat_cache: Dictionary = {} ## Color key -> StandardMaterial3D


func _ready() -> void:
	_static_root = Node3D.new()
	_static_root.name = "Static"
	add_child(_static_root)
	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)
	_holes_root = Node3D.new()
	_holes_root.name = "Holes"
	add_child(_holes_root)
	_tweens_root = Node3D.new()
	_tweens_root.name = "SwallowTweens"
	add_child(_tweens_root)


func clear_presentation() -> void:
	_clear_children(_static_root)
	_clear_children(_props_root)
	_clear_children(_holes_root)
	_clear_children(_tweens_root)
	_prop_nodes.clear()
	_hole_nodes.clear()
	_tween_nodes.clear()
	_static_seed = -1


func sync_from_sim() -> void:
	if host == null:
		return
	var sim: MunchiesSim = host.sim as MunchiesSim
	if sim == null or sim.holes.is_empty():
		return

	# Include a layout version so ground texture / roads rebuild on upgrade.
	var seed_key: int = (
		hash(sim.map_half)
		^ (sim.roads.size() * 17)
		^ (sim.parks.size() * 31)
		^ int(MunchiesSim.ROAD_OVERSHOOT * 10.0)
		^ 6
	)
	if seed_key != _static_seed:
		_rebuild_static(sim)
		_static_seed = seed_key

	_sync_props(sim)
	_sync_holes(sim)
	_sync_tweens()


func _rebuild_static(sim: MunchiesSim) -> void:
	_clear_children(_static_root)
	var half: float = sim.map_half
	var ground_half: float = half + MunchiesSim.ROAD_OVERSHOOT

	# Ground plane extends past the playable rim so off-map roads/traffic have footing.
	_static_root.add_child(_make_box(
		Vector3(0.0, -0.05, 0.0),
		Vector3(ground_half * 2.0, 0.1, ground_half * 2.0),
		COL_GROUND
	))
	_add_ground_texture(half)
	_add_city_lots(half)

	# Low curb at the playable edge (roads continue past it; not a wall).
	var border_h := 0.14
	var t := 0.55
	_static_root.add_child(_make_box(Vector3(0, border_h * 0.5, -half), Vector3(half * 2.0 + t, border_h, t), COL_BORDER))
	_static_root.add_child(_make_box(Vector3(0, border_h * 0.5, half), Vector3(half * 2.0 + t, border_h, t), COL_BORDER))
	_static_root.add_child(_make_box(Vector3(-half, border_h * 0.5, 0), Vector3(t, border_h, half * 2.0), COL_BORDER))
	_static_root.add_child(_make_box(Vector3(half, border_h * 0.5, 0), Vector3(t, border_h, half * 2.0), COL_BORDER))

	# Parks
	for park_v in sim.parks:
		var park: Dictionary = park_v
		var c: Vector2 = park["center"] as Vector2
		var r: float = float(park["radius"])
		var park_mesh := _make_cylinder(Vector3(c.x, 0.04, c.y), r, 0.08, COL_PARK)
		_static_root.add_child(park_mesh)

	# Sidewalks then roads (roads on top).
	for road_v in sim.roads:
		var road: Rect2 = road_v
		var pad := SIDEWALK_M
		var scx := road.position.x + road.size.x * 0.5
		var scz := road.position.y + road.size.y * 0.5
		_static_root.add_child(_make_box(
			Vector3(scx, 0.03, scz),
			Vector3(road.size.x + pad * 2.0, 0.06, road.size.y + pad * 2.0),
			COL_SIDEWALK
		))
	for road_v in sim.roads:
		var road: Rect2 = road_v
		var rcx := road.position.x + road.size.x * 0.5
		var rcz := road.position.y + road.size.y * 0.5
		_static_root.add_child(_make_box(
			Vector3(rcx, 0.06, rcz),
			Vector3(road.size.x, 0.05, road.size.y),
			COL_ROAD
		))
		_add_lane_dashes(road)

	# Spawn pads
	for pad_v in MunchiesSim.SPAWN_PADS:
		var pad: Vector2 = pad_v
		_static_root.add_child(_make_cylinder(
			Vector3(pad.x, 0.07, pad.y), 2.2, 0.05, Color(0.32, 0.36, 0.33, 0.7)
		))


func _hash2(a: int, b: int) -> float:
	var n: int = a * 374761393 + b * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0x7fffffff) / 2147483647.0


func _add_ground_texture(half: float) -> void:
	## Scatter low turf / dirt patches so the ground isn't a flat slab.
	var step := 7.0
	var cells: int = int(ceil(half / step)) + 1
	for i in range(-cells, cells + 1):
		for j in range(-cells, cells + 1):
			var h: float = _hash2(i * 5 + 2, j * 9 + 4)
			if h < 0.38:
				continue
			var x: float = float(i) * step + (h - 0.5) * 2.0
			var z: float = float(j) * step + (_hash2(j, i) - 0.5) * 2.0
			if absf(x) > half - 2.0 or absf(z) > half - 2.0:
				continue
			# Skip the densest road corridors so patches don't fight asphalt.
			if absf(x) < 8.0 or absf(z) < 8.0:
				continue
			var w: float = 2.2 + h * 3.4
			var d: float = 1.8 + (1.0 - h) * 3.0
			var col: Color
			if h > 0.78:
				col = Color(0.30, 0.27, 0.20) ## worn dirt
			elif h > 0.55:
				col = COL_GROUND.lightened(0.06 + h * 0.05)
			else:
				col = COL_GROUND.darkened(0.05)
			_static_root.add_child(_make_box(
				Vector3(x, 0.01, z),
				Vector3(w, 0.03, d),
				col
			))


func _add_city_lots(half: float) -> void:
	## Lot pads between streets.
	var step := 16.0
	var margin := 6.0
	var x: float = -half + margin
	while x < half - margin:
		var z: float = -half + margin
		while z < half - margin:
			var cx: float = x + step * 0.4
			var cz: float = z + step * 0.4
			if absf(cx) < 12.0 or absf(cz) < 12.0:
				z += step
				continue
			var h: float = _hash2(int(x * 10.0), int(z * 10.0))
			if h < 0.30:
				z += step
				continue
			var w: float = step * (0.55 + h * 0.22)
			var d: float = step * (0.48 + (1.0 - h) * 0.2)
			var lot := Color(0.24, 0.25, 0.23).lightened((h - 0.5) * 0.05)
			_static_root.add_child(_make_box(
				Vector3(cx, 0.015, cz),
				Vector3(w, 0.025, d),
				lot
			))
			z += step
		x += step


func _add_lane_dashes(road: Rect2) -> void:
	## Lane dashes along the road midline (meters).
	var horizontal: bool = road.size.x >= road.size.y
	var dash := 1.6
	var gap := 1.2
	var thick := 0.18
	if horizontal:
		var z: float = road.position.y + road.size.y * 0.5
		var x: float = road.position.x + dash * 0.5
		var end_x: float = road.position.x + road.size.x - dash * 0.5
		while x < end_x:
			_static_root.add_child(_make_box(
				Vector3(x, LANE_Y, z),
				Vector3(dash, 0.03, thick),
				COL_LANE
			))
			x += dash + gap
	else:
		var x: float = road.position.x + road.size.x * 0.5
		var z: float = road.position.y + dash * 0.5
		var end_z: float = road.position.y + road.size.y - dash * 0.5
		while z < end_z:
			_static_root.add_child(_make_box(
				Vector3(x, LANE_Y, z),
				Vector3(thick, 0.03, dash),
				COL_LANE
			))
			z += dash + gap


func _sync_props(sim: MunchiesSim) -> void:
	var seen: Dictionary = {}
	for prop_v in sim.objects:
		var prop: Dictionary = prop_v
		var id: int = int(prop["id"])
		if not bool(prop["alive"]):
			continue
		seen[id] = true
		var node: Node3D = _prop_nodes.get(id) as Node3D
		var want_key: String = _prop_mesh_key(prop)
		# Rebuild when shape/color kind changes (or legacy single-mesh).
		if node != null and str(node.get_meta("mesh_key", "")) != want_key:
			node.queue_free()
			_prop_nodes.erase(id)
			node = null
		if node == null:
			node = _make_prop_node(prop)
			node.set_meta("mesh_key", want_key)
			_props_root.add_child(node)
			_prop_nodes[id] = node
		_place_prop(node, prop, sim)
		var claimed: int = int(prop.get("claimed_by", -1))
		_apply_claim_tint(node, claimed, sim)

	# Drop dead / missing props.
	var drop: Array = []
	for id_v in _prop_nodes.keys():
		if not seen.has(int(id_v)):
			drop.append(int(id_v))
	for id in drop:
		var n: Node = _prop_nodes[id]
		_prop_nodes.erase(id)
		if is_instance_valid(n):
			n.queue_free()


func _sync_holes(sim: MunchiesSim) -> void:
	var seen: Dictionary = {}
	for hole_v in sim.holes:
		var hole: Dictionary = hole_v
		var id: int = int(hole["id"])
		seen[id] = true
		var root: Node3D = _hole_nodes.get(id) as Node3D
		# Recreate if rim is not the current sealed flat-ring (old cylinder/torus / gap rims).
		if root != null:
			var rim_n: MeshInstance3D = root.get_node_or_null("Rim") as MeshInstance3D
			var needs_rebuild: bool = (
				rim_n == null
				or not (rim_n.mesh is ArrayMesh)
				or int(rim_n.get_meta("rim_v", 0)) < 2
				or root.get_node_or_null("Name") == null
			)
			if needs_rebuild:
				root.queue_free()
				_hole_nodes.erase(id)
				root = null
		if root == null:
			root = _make_hole_node(hole)
			_holes_root.add_child(root)
			_hole_nodes[id] = root
		_place_hole(root, hole, sim)
		root.visible = bool(hole["alive"])

	var drop: Array = []
	for id_v in _hole_nodes.keys():
		if not seen.has(int(id_v)):
			drop.append(int(id_v))
	for id in drop:
		var n: Node = _hole_nodes[id]
		_hole_nodes.erase(id)
		if is_instance_valid(n):
			n.queue_free()


func _sync_tweens() -> void:
	# Rebuild tween meshes each frame — few and short-lived.
	_clear_children(_tweens_root)
	_tween_nodes.clear()
	if host == null:
		return
	for tw_v in host.swallow_tweens:
		var tw: Dictionary = tw_v
		var alpha: float = float(tw.get("alpha", tw.get("scale", 1.0)))
		if alpha < 0.04:
			continue
		var scale_v: float = float(tw.get("scale", 1.0))
		var r: float = float(tw["radius"])
		var tier: int = int(tw["tier"])
		var role: int = int(tw.get("role", MunchiesSim.ROLE_PROP))
		var body_col: Variant = tw.get("body_color", null)
		if body_col == null:
			body_col = TIER_COLORS.get(tier, Color.WHITE)
		var fake := {
			"id": int(tw.get("prop_id", 0)),
			"x": float(tw["x"]),
			"y": float(tw["y"]),
			"radius": r * scale_v,
			"tier": tier,
			"claimed_by": -1,
			"alive": true,
			"tip_angle": float(tw.get("tip_angle", 0.0)),
			"fallen": bool(tw.get("fallen", false)),
			"tip_dx": float(tw.get("tip_dx", 1.0)),
			"tip_dy": float(tw.get("tip_dy", 0.0)),
			"role": role,
			"vehicle": int(tw.get("vehicle", 0)),
			"body_color": body_col,
		}
		var node := _make_prop_node(fake)
		_apply_prop_alpha(node, alpha)
		_tweens_root.add_child(node)
		var drop: float = float(tw.get("drop", 0.0))
		var h: float = _prop_height(tier, r * scale_v, fake)
		var face_yaw := 0.0
		if (tier == 2 or role == MunchiesSim.ROLE_PERSON) and host != null and host.sim != null:
			face_yaw = -_prop_facing(fake, host.sim as MunchiesSim)
		# People / street clutter keep their upright silhouette while dropping —
		# tipping them reads as a horizontal orange slab.
		var keep_upright: bool = (
			role == MunchiesSim.ROLE_PERSON
			or role == MunchiesSim.ROLE_LAMP
			or tier <= 1
		)
		if keep_upright:
			node.transform = Transform3D.IDENTITY
			node.position = Vector3(float(fake["x"]), h * 0.5 - drop, float(fake["y"]))
			node.rotation = Vector3(0.0, face_yaw, 0.0)
		else:
			_place_prop_tipped(node, fake, h, face_yaw)
			node.position.y -= drop
		_tween_nodes.append(node)


func _prop_mesh_key(prop: Dictionary) -> String:
	var tier: int = int(prop["tier"])
	var role: int = int(prop.get("role", 0))
	if role == MunchiesSim.ROLE_LAMP:
		return "lamp"
	if role == MunchiesSim.ROLE_PERSON:
		var pc: Color = prop.get("body_color", TIER_COLORS[1]) as Color
		return "person:%s" % pc
	if tier == 2:
		var bc: Color = prop.get("body_color", TIER_COLORS[2]) as Color
		return "2:%d:%.2f:%s" % [int(prop.get("vehicle", 0)), float(prop["radius"]), bc]
	return "%d:%d" % [tier, int(prop.get("id", 0)) % 3]


func _make_prop_node(prop: Dictionary) -> Node3D:
	## Procedural stand-ins (no external GLBs): litter / street / car / building.
	var root := Node3D.new()
	root.set_meta("composite", true)
	var tier: int = int(prop["tier"])
	var r: float = float(prop["radius"])
	var col: Color = TIER_COLORS.get(tier, Color.WHITE) as Color
	var prop_id: int = int(prop.get("id", 0))
	var role: int = int(prop.get("role", MunchiesSim.ROLE_PROP))
	if role == MunchiesSim.ROLE_LAMP:
		_build_lamp(root, r)
		return root
	if role == MunchiesSim.ROLE_PERSON:
		var body: Color = prop.get("body_color", col) as Color
		_build_person(root, r, body)
		return root
	match tier:
		0:
			_build_litter(root, r, col, prop_id)
		1:
			_build_street_prop(root, r, col, prop_id)
		2:
			var body: Color = prop.get("body_color", col) as Color
			_build_car(root, r, body, int(prop.get("vehicle", 0)))
		3:
			_build_building(root, r, col, false, prop_id)
		_:
			_build_building(root, r, col, true, prop_id)
	return root


func _add_prop_part(root: Node3D, part: MeshInstance3D, base_col: Color) -> void:
	part.set_meta("base_color", base_col)
	part.material_override = _mat(base_col)
	root.add_child(part)


func _build_litter(root: Node3D, r: float, col: Color, prop_id: int) -> void:
	var kind: int = abs(prop_id) % 3
	match kind:
		0:
			# Chip bag / wrapper — flat diamond slab
			var bag := _make_box(Vector3.ZERO, Vector3(r * 1.5, r * 0.35, r * 1.1), col)
			bag.rotation.y = PI * 0.25
			_add_prop_part(root, bag, col)
			var shine := _make_box(Vector3(0.0, r * 0.12, 0.0), Vector3(r * 0.55, r * 0.12, r * 0.4), col.lightened(0.25))
			shine.rotation.y = PI * 0.25
			_add_prop_part(root, shine, col.lightened(0.25))
		1:
			# Bottle / can
			var can := _make_cylinder(Vector3.ZERO, r * 0.45, r * 1.5, col)
			_add_prop_part(root, can, col)
			var rim := _make_cylinder(Vector3(0.0, r * 0.55, 0.0), r * 0.38, r * 0.22, col.lightened(0.2))
			_add_prop_part(root, rim, col.lightened(0.2))
		_:
			# Crumpled scrap
			_add_prop_part(root, _make_box(Vector3.ZERO, Vector3(r * 1.2, r * 0.5, r * 0.9), col), col)
			_add_prop_part(
				root,
				_make_box(Vector3(r * 0.25, r * 0.2, -r * 0.15), Vector3(r * 0.7, r * 0.35, r * 0.55), col.darkened(0.12)),
				col.darkened(0.12)
			)


func _build_street_prop(root: Node3D, r: float, col: Color, prop_id: int) -> void:
	var kind: int = abs(prop_id) % 3
	var dark: Color = col.darkened(0.22)
	match kind:
		0:
			# Bench: seat + back + legs
			_add_prop_part(root, _make_box(Vector3(0.0, -r * 0.15, 0.0), Vector3(r * 2.1, r * 0.28, r * 0.7), col), col)
			_add_prop_part(root, _make_box(Vector3(0.0, r * 0.35, -r * 0.28), Vector3(r * 2.1, r * 0.7, r * 0.18), col), col)
			_add_prop_part(root, _make_box(Vector3(-r * 0.75, -r * 0.55, 0.1), Vector3(r * 0.22, r * 0.7, r * 0.55), dark), dark)
			_add_prop_part(root, _make_box(Vector3(r * 0.75, -r * 0.55, 0.1), Vector3(r * 0.22, r * 0.7, r * 0.55), dark), dark)
		1:
			# Trash bin
			_add_prop_part(root, _make_cylinder(Vector3.ZERO, r * 0.7, r * 1.55, col), col)
			_add_prop_part(root, _make_cylinder(Vector3(0.0, r * 0.72, 0.0), r * 0.78, r * 0.22, dark), dark)
			_add_prop_part(
				root,
				_make_box(Vector3(0.0, r * 0.1, 0.0), Vector3(r * 0.55, r * 0.45, r * 0.12), Color(0.12, 0.12, 0.14)),
				Color(0.12, 0.12, 0.14)
			)
		_:
			# Fire hydrant / bollard
			_add_prop_part(root, _make_cylinder(Vector3(0.0, -r * 0.15, 0.0), r * 0.55, r * 1.1, col), col)
			_add_prop_part(root, _make_cylinder(Vector3(0.0, r * 0.55, 0.0), r * 0.35, r * 0.45, col.lightened(0.1)), col.lightened(0.1))
			_add_prop_part(root, _make_box(Vector3(r * 0.55, r * 0.15, 0.0), Vector3(r * 0.45, r * 0.28, r * 0.28), col), col)
			_add_prop_part(root, _make_box(Vector3(-r * 0.55, r * 0.15, 0.0), Vector3(r * 0.45, r * 0.28, r * 0.28), col), col)


func _build_lamp(root: Node3D, r: float) -> void:
	## Very tall thin pole + small lamp head.
	var pole_col := Color(0.22, 0.22, 0.24)
	var head_col := Color(0.92, 0.88, 0.65)
	var h: float = r * 8.0
	_add_prop_part(root, _make_cylinder(Vector3(0.0, 0.0, 0.0), r * 0.35, h, pole_col), pole_col)
	_add_prop_part(root, _make_box(Vector3(0.0, h * 0.48, 0.0), Vector3(r * 1.6, r * 0.7, r * 1.6), head_col), head_col)
	_add_prop_part(root, _make_box(Vector3(0.0, -h * 0.48, 0.0), Vector3(r * 1.4, r * 0.35, r * 1.4), pole_col.darkened(0.15)), pole_col.darkened(0.15))


func _build_person(root: Node3D, r: float, col: Color) -> void:
	## Simple walker: legs stub + torso + head.
	var cloth: Color = col
	var skin := Color(0.86, 0.70, 0.58).lerp(col, 0.15)
	var dark := col.darkened(0.25)
	_add_prop_part(root, _make_box(Vector3(-r * 0.22, -r * 0.75, 0.0), Vector3(r * 0.28, r * 0.7, r * 0.28), dark), dark)
	_add_prop_part(root, _make_box(Vector3(r * 0.22, -r * 0.75, 0.0), Vector3(r * 0.28, r * 0.7, r * 0.28), dark), dark)
	_add_prop_part(root, _make_box(Vector3(0.0, -r * 0.05, 0.0), Vector3(r * 0.85, r * 1.1, r * 0.45), cloth), cloth)
	_add_prop_part(root, _make_cylinder(Vector3(0.0, r * 0.85, 0.0), r * 0.32, r * 0.55, skin), skin)


func _build_car(root: Node3D, r: float, col: Color, kind: int = 0) -> void:
	## Sedan / van / truck. Length along local X (yaw follows drive direction).
	var body_col: Color = col
	var cabin_col := Color(0.45, 0.62, 0.78).lerp(col, 0.2)
	var wheel_col := Color(0.12, 0.12, 0.14)
	var trim := col.darkened(0.2)
	match kind:
		MunchiesSim.VEHICLE_TRUCK:
			# Cab + boxy cargo
			_add_prop_part(root, _make_box(Vector3(r * 0.85, -r * 0.05, 0.0), Vector3(r * 1.2, r * 0.7, r * 1.2), body_col), body_col)
			_add_prop_part(root, _make_box(Vector3(r * 0.85, r * 0.45, 0.0), Vector3(r * 0.95, r * 0.55, r * 1.05), cabin_col), cabin_col)
			_add_prop_part(root, _make_box(Vector3(-r * 0.55, r * 0.15, 0.0), Vector3(r * 2.0, r * 1.1, r * 1.25), trim), trim)
			_add_prop_part(root, _make_box(Vector3(r * 1.35, r * 0.05, 0.0), Vector3(r * 0.35, r * 0.2, r * 0.9), body_col.lightened(0.15)), body_col.lightened(0.15))
			for xz in [
				Vector3(r * 1.1, -r * 0.38, r * 0.55),
				Vector3(r * 1.1, -r * 0.38, -r * 0.55),
				Vector3(-r * 0.2, -r * 0.38, r * 0.55),
				Vector3(-r * 0.2, -r * 0.38, -r * 0.55),
				Vector3(-r * 1.2, -r * 0.38, r * 0.55),
				Vector3(-r * 1.2, -r * 0.38, -r * 0.55),
			]:
				var wheel := _make_cylinder(xz, r * 0.3, r * 0.24, wheel_col)
				wheel.rotation.x = PI * 0.5
				_add_prop_part(root, wheel, wheel_col)
		MunchiesSim.VEHICLE_VAN:
			# Tall cabin covering most of the body
			_add_prop_part(root, _make_box(Vector3(0.0, -r * 0.05, 0.0), Vector3(r * 2.6, r * 0.65, r * 1.2), body_col), body_col)
			_add_prop_part(root, _make_box(Vector3(-r * 0.15, r * 0.45, 0.0), Vector3(r * 2.1, r * 0.7, r * 1.05), cabin_col), cabin_col)
			_add_prop_part(root, _make_box(Vector3(r * 1.0, r * 0.15, 0.0), Vector3(r * 0.45, r * 0.2, r * 1.0), trim), trim)
			for xz in [
				Vector3(r * 0.85, -r * 0.35, r * 0.55),
				Vector3(r * 0.85, -r * 0.35, -r * 0.55),
				Vector3(-r * 0.85, -r * 0.35, r * 0.55),
				Vector3(-r * 0.85, -r * 0.35, -r * 0.55),
			]:
				var wheel := _make_cylinder(xz, r * 0.28, r * 0.22, wheel_col)
				wheel.rotation.x = PI * 0.5
				_add_prop_part(root, wheel, wheel_col)
		_:
			# Sedan
			_add_prop_part(root, _make_box(Vector3(0.0, -r * 0.12, 0.0), Vector3(r * 2.5, r * 0.55, r * 1.15), body_col), body_col)
			_add_prop_part(root, _make_box(Vector3(-r * 0.05, r * 0.32, 0.0), Vector3(r * 1.15, r * 0.42, r * 0.95), cabin_col), cabin_col)
			_add_prop_part(root, _make_box(Vector3(r * 0.85, r * 0.05, 0.0), Vector3(r * 0.55, r * 0.12, r * 1.0), trim), trim)
			_add_prop_part(root, _make_box(Vector3(-r * 0.95, r * 0.02, 0.0), Vector3(r * 0.4, r * 0.1, r * 1.0), trim), trim)
			for xz in [
				Vector3(r * 0.75, -r * 0.32, r * 0.52),
				Vector3(r * 0.75, -r * 0.32, -r * 0.52),
				Vector3(-r * 0.75, -r * 0.32, r * 0.52),
				Vector3(-r * 0.75, -r * 0.32, -r * 0.52),
			]:
				var wheel := _make_cylinder(xz, r * 0.28, r * 0.22, wheel_col)
				wheel.rotation.x = PI * 0.5
				_add_prop_part(root, wheel, wheel_col)


func _build_building(root: Node3D, r: float, col: Color, is_block: bool, prop_id: int = 0) -> void:
	var w: float = r * (1.8 if is_block else 1.6)
	var h: float = r * (2.8 if is_block else 2.2)
	_add_prop_part(root, _make_box(Vector3.ZERO, Vector3(w, h, w), col), col)
	# Roof cap
	var roof := col.darkened(0.18)
	_add_prop_part(root, _make_box(Vector3(0.0, h * 0.48, 0.0), Vector3(w * 1.05, h * 0.08, w * 1.05), roof), roof)
	# Window grid on two faces (skip a few buildings for variety).
	if abs(prop_id) % 5 == 0:
		return
	var glass := Color(0.42, 0.58, 0.72).lerp(col, 0.15)
	var lit := Color(0.85, 0.78, 0.45).lerp(glass, 0.35)
	var cols_n: int = 3 if is_block else 2
	var rows_n: int = 4 if is_block else 3
	var pane_w: float = w * 0.16
	var pane_h: float = h * 0.12
	var x0: float = -w * 0.28
	var y0: float = -h * 0.28
	for row in rows_n:
		for col_i in cols_n:
			var px: float = x0 + float(col_i) * (w * 0.28)
			var py: float = y0 + float(row) * (h * 0.2)
			var pane_col: Color = lit if ((prop_id + row * 3 + col_i) % 4 == 0) else glass
			_add_prop_part(
				root,
				_make_box(Vector3(px, py, w * 0.51), Vector3(pane_w, pane_h, w * 0.03), pane_col),
				pane_col
			)
			_add_prop_part(
				root,
				_make_box(Vector3(w * 0.51, py, px), Vector3(w * 0.03, pane_h, pane_w), pane_col),
				pane_col
			)


func _prop_height(tier: int, r: float, prop: Dictionary = {}) -> float:
	var role: int = int(prop.get("role", MunchiesSim.ROLE_PROP))
	if role == MunchiesSim.ROLE_LAMP:
		return r * 8.0
	if role == MunchiesSim.ROLE_PERSON:
		return r * 2.4
	match tier:
		0:
			return r * 0.7
		1:
			return r * 1.6
		2:
			var kind: int = int(prop.get("vehicle", 0))
			if kind == MunchiesSim.VEHICLE_TRUCK:
				return r * 1.15
			if kind == MunchiesSim.VEHICLE_VAN:
				return r * 1.2
			return r * 0.95
		3:
			return r * 2.2
		_:
			return r * 2.8


func _prop_facing(prop: Dictionary, sim: MunchiesSim) -> float:
	## Prefer drive/walk velocity so movers face the way they travel.
	var vx: float = float(prop.get("vx", 0.0))
	var vy: float = float(prop.get("vy", 0.0))
	if vx * vx + vy * vy > 0.04:
		return atan2(vy, vx)
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


func _place_prop(node: Node3D, prop: Dictionary, sim: MunchiesSim) -> void:
	var r: float = float(prop["radius"])
	var tier: int = int(prop["tier"])
	var h: float = _prop_height(tier, r, prop)
	var role: int = int(prop.get("role", MunchiesSim.ROLE_PROP))
	var face_yaw: float = 0.0
	if tier == 2 or role == MunchiesSim.ROLE_PERSON:
		face_yaw = -_prop_facing(prop, sim)
	var tip_angle: float = float(prop.get("tip_angle", 0.0))
	if bool(prop.get("fallen", false)) or tip_angle > 0.01:
		_place_prop_tipped(node, prop, h, face_yaw)
		return
	# Upright: cars keep road facing; others face world axes.
	node.transform = Transform3D.IDENTITY
	node.position = Vector3(float(prop["x"]), h * 0.5, float(prop["y"]))
	node.rotation = Vector3(0.0, face_yaw, 0.0)


func _place_prop_tipped(node: Node3D, prop: Dictionary, height: float, face_yaw: float = 0.0) -> void:
	## Tip toward the hole while keeping the mesh on the ground.
	## Cars keep road yaw so a vertical car doesn't snap 90° when tip starts.
	var dims: Vector2 = MunchiesSim.prop_tip_dims(prop)
	var width: float = dims.x
	var tip_angle: float = float(prop.get("tip_angle", 0.0))
	if bool(prop.get("fallen", false)):
		tip_angle = PI * 0.5
	var tdx: float = float(prop.get("tip_dx", 1.0))
	var tdy: float = float(prop.get("tip_dy", 0.0))
	var tip := Vector3(tdx, 0.0, tdy)
	if tip.length_squared() < 0.0001:
		tip = Vector3.RIGHT
	else:
		tip = tip.normalized()
	# UP × tip with +angle rotates UP toward tip.
	var axis := Vector3.UP.cross(tip)
	if axis.length_squared() < 0.0001:
		axis = Vector3.RIGHT
	else:
		axis = axis.normalized()
	var yaw_basis := Basis(Vector3.UP, face_yaw)
	var tip_basis := Basis(axis, tip_angle)
	var basis := tip_basis * yaw_basis
	var origin := Vector3(float(prop["x"]), 0.0, float(prop["y"]))
	# Arc the center toward the hole; sit_y keeps the body resting on the ground
	# (upright → height/2, fallen on its side → width/2) so nothing embeds.
	var local_upright: Vector3 = yaw_basis * Vector3(0.0, height * 0.5, 0.0)
	var tipped: Vector3 = tip_basis * local_upright
	var sit_y: float = lerpf(height * 0.5, width * 0.5, sin(tip_angle))
	var mesh_center := Vector3(origin.x + tipped.x, maxf(sit_y, 0.02), origin.z + tipped.z)
	node.transform = Transform3D(basis, mesh_center)


func _apply_claim_tint(node: Node3D, claimed: int, sim: MunchiesSim) -> void:
	var ring := Color.WHITE
	var use_ring := false
	if claimed != -1:
		var claimer: Dictionary = sim.hole_by_id(claimed)
		if not claimer.is_empty():
			var slot: int = int(claimer.get("slot", 0))
			ring = MunchiesSim.HOLE_RING_COLORS[clampi(slot, 0, MunchiesSim.HOLE_RING_COLORS.size() - 1)]
			use_ring = true
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			var base: Color = mi.get_meta("base_color", Color.WHITE) as Color
			var col: Color = base.lerp(ring, 0.35) if use_ring else base
			mi.material_override = _mat(col)


func _apply_prop_alpha(node: Node3D, alpha: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			var base: Color = mi.get_meta("base_color", Color.WHITE) as Color
			base.a = alpha
			mi.material_override = _mat(base, true)


func _make_hole_node(hole: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Hole_%d" % int(hole["id"])

	# Dark fill sits ABOVE roads/sidewalks. Oversized vs rim-inner so pavement
	# cannot peek between the black disc and the colored ring under a tilt.
	var pit := MeshInstance3D.new()
	pit.name = "Pit"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.04
	cyl.bottom_radius = 1.04
	cyl.height = 0.10
	cyl.radial_segments = 96
	pit.mesh = cyl
	pit.material_override = _mat(Color(0.03, 0.03, 0.04))
	pit.position.y = HOLE_FILL_Y
	root.add_child(pit)

	# Deeper inner shadow (still above road top).
	var inner := MeshInstance3D.new()
	inner.name = "Inner"
	var ic := CylinderMesh.new()
	ic.top_radius = 0.72
	ic.bottom_radius = 0.72
	ic.height = 0.06
	ic.radial_segments = 64
	inner.mesh = ic
	inner.material_override = _mat(Color(0.01, 0.01, 0.015))
	inner.position.y = HOLE_FILL_Y + 0.02
	root.add_child(inner)

	# Flat annular rim — inner edge sits on top of the oversized pit (no ground gap).
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = _make_flat_ring_mesh(0.98, 1.12, 96)
	rim.set_meta("flat_ring", true)
	rim.set_meta("rim_v", 2)
	rim.position.y = HOLE_RIM_Y
	root.add_child(rim)

	var flash := MeshInstance3D.new()
	flash.name = "Flash"
	flash.mesh = _make_flat_ring_mesh(1.02, 1.20, 96)
	flash.set_meta("flat_ring", true)
	flash.set_meta("rim_v", 2)
	flash.position.y = HOLE_FLASH_Y
	flash.material_override = _mat(Color(1, 1, 1, 0.0), true)
	flash.visible = false
	root.add_child(flash)

	# Billboard name under the rim (counter-scaled in _place_hole so radius growth
	# does not stretch the glyphs).
	var slot: int = int(hole.get("slot", 0))
	var ring_col: Color = MunchiesSim.HOLE_RING_COLORS[
		clampi(slot, 0, MunchiesSim.HOLE_RING_COLORS.size() - 1)
	]
	var nametag := Label3D.new()
	nametag.name = "Name"
	nametag.text = str(hole.get("name", ""))
	nametag.font_size = 42
	nametag.pixel_size = 0.014
	nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nametag.no_depth_test = true
	nametag.outline_size = 10
	nametag.outline_modulate = Color(0.02, 0.02, 0.03, 0.85)
	nametag.modulate = ring_col
	# Just outside the rim; _place_hole keeps a fixed world gap past the edge.
	nametag.position = Vector3(0.0, 0.2, 1.55)
	root.add_child(nametag)

	return root


func _make_flat_ring_mesh(inner_r: float, outer_r: float, segments: int = 96) -> ArrayMesh:
	## Flat XZ annulus. Looks like a clean circular border under a tilted camera.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var c0 := cos(a0)
		var s0 := sin(a0)
		var c1 := cos(a1)
		var s1 := sin(a1)
		var i0 := Vector3(c0 * inner_r, 0.0, s0 * inner_r)
		var i1 := Vector3(c1 * inner_r, 0.0, s1 * inner_r)
		var o0 := Vector3(c0 * outer_r, 0.0, s0 * outer_r)
		var o1 := Vector3(c1 * outer_r, 0.0, s1 * outer_r)
		st.set_normal(Vector3.UP)
		st.add_vertex(i0)
		st.add_vertex(o0)
		st.add_vertex(o1)
		st.add_vertex(i0)
		st.add_vertex(o1)
		st.add_vertex(i1)
	return st.commit()


func _place_hole(root: Node3D, hole: Dictionary, _sim: MunchiesSim) -> void:
	var r: float = float(hole["radius"])
	root.position = Vector3(float(hole["x"]), 0.0, float(hole["y"]))
	root.scale = Vector3(r, 1.0, r)

	var slot: int = int(hole.get("slot", 0))
	var ring: Color = MunchiesSim.HOLE_RING_COLORS[clampi(slot, 0, MunchiesSim.HOLE_RING_COLORS.size() - 1)]
	var rim: MeshInstance3D = root.get_node("Rim") as MeshInstance3D
	var flash: MeshInstance3D = root.get_node("Flash") as MeshInstance3D
	var nametag: Label3D = root.get_node_or_null("Name") as Label3D
	if nametag != null:
		nametag.text = str(hole.get("name", ""))
		nametag.modulate = ring
		# Counter-scale glyphs; keep ~0.7 m past the rim so text clears the ring.
		var inv: float = 1.0 / maxf(r, 0.01)
		nametag.scale = Vector3(inv, 1.0, inv)
		nametag.position = Vector3(0.0, 0.18, 1.0 + 0.7 * inv)

	var growing: bool = (
		host != null
		and host.grow_flash > 0.0
		and int(hole["id"]) == int(host.grow_flash_hole)
	)
	if growing:
		var flash_a: float = clampf(host.grow_flash / 0.34, 0.0, 1.0)
		# Brighten the claim rim while grown; white/gold bloom expands then settles.
		rim.material_override = _mat(ring.lerp(Color(1.0, 0.98, 0.85), flash_a * 0.7))
		flash.visible = true
		var pulse: float = 1.0 + 0.22 * flash_a
		flash.scale = Vector3(pulse, 1.0, pulse)
		flash.material_override = _mat(Color(1.0, 0.95, 0.65, flash_a * 0.9), true)
	else:
		rim.material_override = _mat(ring)
		flash.visible = false
		flash.scale = Vector3.ONE


func _make_box(pos: Vector3, size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = _mat(col)
	return mi


func _make_cylinder(pos: Vector3, radius: float, height: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 20
	mi.mesh = cyl
	mi.position = pos
	mi.material_override = _mat(col)
	return mi


func _mat(col: Color, transparent: bool = false) -> StandardMaterial3D:
	var key := "%s|%s" % [col, transparent]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if transparent or col.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		node.remove_child(c)
		c.free()
