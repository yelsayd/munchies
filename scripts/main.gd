extends Node2D
## Phase 1 view: keyboard → Input → sim.step → draw circles + HUD.
## No RigidBody2D / physics nodes; rules live in MunchiesSim.

const PIXELS_PER_METER := 24.0
const CAMERA_SETTLE := 0.2
const HOLE_SCREEN_FRACTION := 0.20 ## diameter vs shorter pane side

@onready var camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var hud: CanvasLayer = $HUD
@onready var score_label: Label = $HUD/Margin/VBox/Score
@onready var radius_label: Label = $HUD/Margin/VBox/Radius
@onready var hint_label: Label = $HUD/Margin/VBox/Hint

var sim: MunchiesSim
var _cam_pos := Vector2.ZERO
var _cam_zoom := 1.0
var _paused := false
var hole_ring_color := Color(0.30, 0.85, 0.78)


func _ready() -> void:
	sim = MunchiesSim.new()
	sim.setup_phase1(42)
	var hole := sim.player_hole()
	_cam_pos = Vector2(hole["x"], hole["y"]) * PIXELS_PER_METER
	camera.position = _cam_pos
	_update_hud()
	hint_label.text = "WASD / arrows — Esc pause — grow past ~0.58 to eat street props"


func _process(dt: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_paused = not _paused

	if not _paused:
		var inputs := {sim.player_hole()["id"]: _read_keyboard_input()}
		sim.step(inputs, dt)
		world.queue_redraw()

	_update_camera(dt)
	_update_hud()


func _read_keyboard_input() -> Vector2:
	# Combine WASD + arrows into one vector, then normalize so diagonals match full tilt.
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v.length_squared() > 1.0:
		v = v.normalized()
	return v


func _update_camera(dt: float) -> void:
	var hole := sim.player_hole()
	var target := Vector2(hole["x"], hole["y"]) * PIXELS_PER_METER
	# Look-ahead (rough Phase 1).
	var vel := Vector2(hole["vx"], hole["vy"]) * PIXELS_PER_METER
	var look := vel * 0.15
	var look_cap := 0.4 * float(hole["radius"]) * PIXELS_PER_METER
	if look.length() > look_cap:
		look = look.normalized() * look_cap
	target += look

	var blend := 1.0 - exp(-dt / CAMERA_SETTLE)
	_cam_pos = _cam_pos.lerp(target, blend)
	camera.position = _cam_pos

	# Zoom: hole diameter ≈ 20% of shorter viewport side.
	var vp := get_viewport().get_visible_rect().size
	var shorter := minf(vp.x, vp.y)
	var diameter_m := 2.0 * float(hole["radius"])
	var desired_zoom := (HOLE_SCREEN_FRACTION * shorter) / (diameter_m * PIXELS_PER_METER)
	# Clamp so start is not a filled pane; keep some ground around a large hole.
	desired_zoom = clampf(desired_zoom, 0.35, 2.5)
	_cam_zoom = lerpf(_cam_zoom, desired_zoom, blend)
	camera.zoom = Vector2(_cam_zoom, _cam_zoom)


func _update_hud() -> void:
	var hole := sim.player_hole()
	score_label.text = "Score  %d" % int(hole["score"])
	radius_label.text = "Radius  %.1f" % float(hole["radius"])
	if _paused:
		hint_label.text = "Paused — Esc to resume"
	else:
		hint_label.text = "WASD / arrows — Esc pause — props left: %d" % sim.alive_prop_count()
