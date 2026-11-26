extends Node2D
## Phase 2 view: keyboard → Input → sim.step → draw + swallow tween/blip.
## No RigidBody2D / physics nodes; rules live in MunchiesSim.

const PIXELS_PER_METER := 24.0
const CAMERA_SETTLE := 0.2
const HOLE_SCREEN_FRACTION := 0.20 ## diameter vs shorter pane side
const SWALLOW_TWEEN_SEC := 0.20

@onready var camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var hud: CanvasLayer = $HUD
@onready var score_label: Label = $HUD/Margin/VBox/Score
@onready var radius_label: Label = $HUD/Margin/VBox/Radius
@onready var hint_label: Label = $HUD/Margin/VBox/Hint
@onready var blip_player: AudioStreamPlayer = $BlipPlayer

var sim: MunchiesSim
var _cam_pos := Vector2.ZERO
var _cam_zoom := 1.0
var _paused := false
var hole_ring_color := Color(0.30, 0.85, 0.78)

## Presentation-only swallow ghosts: {x,y,radius,tier,scale,age,target_x,target_y}
var swallow_tweens: Array = []
var swallow_flash: float = 0.0


func _ready() -> void:
	sim = MunchiesSim.new()
	# Spawn pad 0 (SW corner) — litter trail leads toward the center parks.
	sim.setup_phase2(42, 0)
	var hole := sim.player_hole()
	_cam_pos = Vector2(float(hole["x"]), float(hole["y"])) * PIXELS_PER_METER
	camera.position = _cam_pos
	_cam_zoom = _desired_zoom(float(hole["radius"]))
	camera.zoom = Vector2(_cam_zoom, _cam_zoom)
	_update_hud()
	hint_label.text = "WASD / arrows — litter → street → vehicles → buildings"


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_paused = not _paused

	if not _paused:
		var inputs := {int(sim.player_hole()["id"]): _read_keyboard_input()}
		var events: Array = sim.step(inputs, dt)
		_handle_events(events)

	_tick_presentation(dt)
	_update_camera(dt)
	_update_hud()
	world.queue_redraw()


func _read_keyboard_input() -> Vector2:
	# Combine WASD + arrows into one vector, then normalize so diagonals match full tilt.
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v.length_squared() > 1.0:
		v = v.normalized()
	return v


func _handle_events(events: Array) -> void:
	var hole := sim.player_hole()
	for ev_v in events:
		var ev: Dictionary = ev_v
		if ev["kind"] != MunchiesSim.EVENT_SWALLOWED:
			continue
		swallow_tweens.append({
			"x": float(ev.get("x", hole["x"])),
			"y": float(ev.get("y", hole["y"])),
			"target_x": float(hole["x"]),
			"target_y": float(hole["y"]),
			"radius": float(ev.get("radius", 0.25)),
			"tier": int(ev.get("tier", 0)),
			"scale": 1.0,
			"age": 0.0,
		})
		swallow_flash = 0.18
		if blip_player.stream != null:
			blip_player.pitch_scale = 1.0 + 0.04 * float(ev.get("tier", 0))
			blip_player.play()


func _tick_presentation(dt: float) -> void:
	if swallow_flash > 0.0:
		swallow_flash = maxf(0.0, swallow_flash - dt)

	var hole := sim.player_hole()
	var hx: float = float(hole["x"])
	var hy: float = float(hole["y"])
	var keep: Array = []
	for tw_v in swallow_tweens:
		var tw: Dictionary = tw_v
		tw["age"] = float(tw["age"]) + dt
		var t: float = clampf(float(tw["age"]) / SWALLOW_TWEEN_SEC, 0.0, 1.0)
		tw["scale"] = 1.0 - t
		# Drift toward the hole center while shrinking.
		tw["x"] = lerpf(float(tw["x"]), hx, 1.0 - exp(-dt * 14.0))
		tw["y"] = lerpf(float(tw["y"]), hy, 1.0 - exp(-dt * 14.0))
		tw["target_x"] = hx
		tw["target_y"] = hy
		if t < 1.0:
			keep.append(tw)
	swallow_tweens = keep


func _desired_zoom(radius: float) -> float:
	var vp := get_viewport().get_visible_rect().size
	var shorter: float = minf(vp.x, vp.y)
	var diameter_m: float = 2.0 * radius
	var z: float = (HOLE_SCREEN_FRACTION * shorter) / (diameter_m * PIXELS_PER_METER)
	# Keep at least one suction-diameter of ground around a large hole.
	var suction_diameter_m: float = 2.0 * radius * MunchiesSim.PROP_SUCTION_MULT
	var min_span_m: float = diameter_m + suction_diameter_m
	var max_zoom: float = shorter / (min_span_m * PIXELS_PER_METER)
	# Floor so start is not a filled pane on the 160 m map.
	return clampf(z, 0.12, maxf(0.12, max_zoom))


func _update_camera(dt: float) -> void:
	var hole := sim.player_hole()
	var target := Vector2(float(hole["x"]), float(hole["y"])) * PIXELS_PER_METER
	# Look-ahead: velocity × 0.15 s, capped at 0.4 × radius.
	var vel := Vector2(float(hole["vx"]), float(hole["vy"])) * PIXELS_PER_METER
	var look := vel * 0.15
	var look_cap: float = 0.4 * float(hole["radius"]) * PIXELS_PER_METER
	if look.length() > look_cap:
		look = look.normalized() * look_cap
	target += look

	var blend: float = 1.0 - exp(-dt / CAMERA_SETTLE)
	_cam_pos = _cam_pos.lerp(target, blend)
	camera.position = _cam_pos

	var desired_zoom: float = _desired_zoom(float(hole["radius"]))
	_cam_zoom = lerpf(_cam_zoom, desired_zoom, blend)
	camera.zoom = Vector2(_cam_zoom, _cam_zoom)


func _update_hud() -> void:
	var hole := sim.player_hole()
	score_label.text = "Score  %d" % int(hole["score"])
	radius_label.text = "Radius  %.1f" % float(hole["radius"])
	if _paused:
		hint_label.text = "Paused — Esc to resume"
	else:
		var c: Dictionary = sim.count_by_tier()
		hint_label.text = "WASD/arrows — Esc pause — L%d S%d V%d B%d K%d" % [
			int(c.get(0, 0)), int(c.get(1, 0)), int(c.get(2, 0)), int(c.get(3, 0)), int(c.get(4, 0))
		]
