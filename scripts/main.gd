extends Node2D
## Phase 4 view: setup → keyboard + bots → Input → sim.step → HUD / end card.
## No RigidBody2D / physics nodes; rules live in MunchiesSim.

const PIXELS_PER_METER := 24.0
const CAMERA_SETTLE := 0.2
const HOLE_SCREEN_FRACTION := 0.20 ## diameter vs shorter pane side
const SWALLOW_TWEEN_SEC := 0.20

enum Screen { SETUP, PLAYING, ENDED }

@onready var camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var hud: CanvasLayer = $HUD
@onready var title_label: Label = $HUD/Margin/VBox/Title
@onready var mode_line: Label = $HUD/Margin/VBox/ModeLine
@onready var score_label: Label = $HUD/Margin/VBox/Score
@onready var radius_label: Label = $HUD/Margin/VBox/Radius
@onready var hint_label: Label = $HUD/Margin/VBox/Hint
@onready var setup_panel: PanelContainer = $HUD/Setup
@onready var setup_list: ItemList = $HUD/Setup/Margin/VBox/ModeList
@onready var setup_holes: Label = $HUD/Setup/Margin/VBox/HoleCount
@onready var setup_hint: Label = $HUD/Setup/Margin/VBox/SetupHint
@onready var end_panel: PanelContainer = $HUD/EndCard
@onready var end_title: Label = $HUD/EndCard/Margin/VBox/EndTitle
@onready var end_scores: Label = $HUD/EndCard/Margin/VBox/EndScores
@onready var end_hint: Label = $HUD/EndCard/Margin/VBox/EndHint
@onready var blip_player: AudioStreamPlayer = $BlipPlayer

var sim: MunchiesSim
var _cam_pos := Vector2.ZERO
var _cam_zoom := 1.0
var _paused := false
var _screen: Screen = Screen.SETUP
var _mode_index: int = 0 ## Timer highlighted by default
var _hole_count: int = 2
var hole_ring_color := Color(0.30, 0.85, 0.78)

## Presentation-only swallow ghosts: {x,y,radius,tier,scale,age,target_x,target_y,hole_id}
var swallow_tweens: Array = []
var swallow_flash: float = 0.0
var swallow_flash_hole: int = -1

const MODE_ORDER := [
	MatchConfig.Mode.TIMER,
	MatchConfig.Mode.SCORE_TARGET,
	MatchConfig.Mode.MAP_CLEARED,
	MatchConfig.Mode.LAST_STANDING,
	MatchConfig.Mode.UNLIMITED,
]


func _ready() -> void:
	sim = MunchiesSim.new()
	_build_setup_list()
	_show_setup()


func _build_setup_list() -> void:
	setup_list.clear()
	for m in MODE_ORDER:
		var cfg := MatchConfig.for_mode(m, _hole_count)
		var extra := ""
		match m:
			MatchConfig.Mode.TIMER:
				extra = " — 2:00"
			MatchConfig.Mode.SCORE_TARGET:
				extra = " — first to 800"
			MatchConfig.Mode.MAP_CLEARED:
				extra = " — clear swallowable props"
			MatchConfig.Mode.LAST_STANDING:
				extra = " — no hole respawn"
			MatchConfig.Mode.UNLIMITED:
				extra = " — no end card"
		setup_list.add_item(cfg.label() + extra)
	setup_list.select(_mode_index)
	_refresh_setup_holes()


func _refresh_setup_holes() -> void:
	setup_holes.text = "Holes: %d  (1 keyboard + %d bot%s)" % [
		_hole_count,
		_hole_count - 1,
		"" if _hole_count == 2 else "s",
	]
	setup_hint.text = "↑↓ mode · ←→ holes · Enter/Space start · Esc quit setup focus"


func _show_setup() -> void:
	_screen = Screen.SETUP
	_paused = false
	setup_panel.visible = true
	end_panel.visible = false
	title_label.text = "Munchies — Phase 4"
	mode_line.text = "Pick a match mode"
	score_label.text = ""
	radius_label.text = ""
	hint_label.text = ""
	setup_list.grab_focus()
	setup_list.select(_mode_index)


func _start_match() -> void:
	var mode: MatchConfig.Mode = MODE_ORDER[_mode_index]
	var cfg := MatchConfig.for_mode(mode, _hole_count)
	sim = MunchiesSim.new()
	sim.setup_match(cfg, 42)
	swallow_tweens.clear()
	swallow_flash = 0.0
	_paused = false
	_screen = Screen.PLAYING
	setup_panel.visible = false
	end_panel.visible = false

	var hole := sim.player_hole()
	_cam_pos = Vector2(float(hole["x"]), float(hole["y"])) * PIXELS_PER_METER
	camera.position = _cam_pos
	_cam_zoom = _desired_zoom(float(hole["radius"]))
	camera.zoom = Vector2(_cam_zoom, _cam_zoom)
	hole_ring_color = MunchiesSim.HOLE_RING_COLORS[0]
	_update_hud()
	world.queue_redraw()


func _show_end_card() -> void:
	_screen = Screen.ENDED
	end_panel.visible = true
	end_title.text = sim.match_end_reason
	var lines: PackedStringArray = PackedStringArray()
	var place := 1
	for id_v in sim.rankings:
		var hole: Dictionary = sim.hole_by_id(int(id_v))
		if hole.is_empty():
			continue
		var mark := " ←" if int(hole["id"]) == sim.winner_id else ""
		lines.append("%d. %s  %d pts  r=%.1f%s" % [
			place,
			str(hole["name"]),
			int(hole["score"]),
			float(hole["radius"]),
			mark,
		])
		place += 1
	end_scores.text = "\n".join(lines)
	end_hint.text = "Enter/Space — back to setup"


func _process(dt: float) -> void:
	match _screen:
		Screen.SETUP:
			_process_setup()
		Screen.PLAYING:
			_process_playing(dt)
		Screen.ENDED:
			_process_ended()


func _process_setup() -> void:
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
		_mode_index = (_mode_index - 1 + MODE_ORDER.size()) % MODE_ORDER.size()
		setup_list.select(_mode_index)
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
		_mode_index = (_mode_index + 1) % MODE_ORDER.size()
		setup_list.select(_mode_index)
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left"):
		_hole_count = maxi(2, _hole_count - 1)
		_refresh_setup_holes()
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right"):
		_hole_count = mini(4, _hole_count + 1)
		_refresh_setup_holes()
	if Input.is_action_just_pressed("confirm"):
		_start_match()


func _process_playing(dt: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_paused = not _paused

	if not _paused and not sim.match_over:
		var inputs := _collect_inputs()
		var events: Array = sim.step(inputs, dt)
		_handle_events(events)
		if sim.match_over and sim.config != null and sim.config.has_end_card():
			_show_end_card()

	_tick_presentation(dt)
	_update_camera(dt)
	_update_hud()
	world.queue_redraw()


func _process_ended() -> void:
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("pause"):
		_show_setup()


func _collect_inputs() -> Dictionary:
	var inputs := {}
	for hole_v in sim.holes:
		var hole: Dictionary = hole_v
		var id: int = int(hole["id"])
		if bool(hole.get("is_bot", false)):
			inputs[id] = MunchiesBot.input_for(sim, id)
		else:
			inputs[id] = _read_keyboard_input()
	return inputs


func _read_keyboard_input() -> Vector2:
	# Combine WASD + arrows into one vector, then normalize so diagonals match full tilt.
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if v.length_squared() > 1.0:
		v = v.normalized()
	return v


func _handle_events(events: Array) -> void:
	for ev_v in events:
		var ev: Dictionary = ev_v
		var kind: StringName = ev["kind"]
		if kind == MunchiesSim.EVENT_SWALLOWED:
			var hid: int = int(ev.get("hole_id", -1))
			var hole: Dictionary = sim.hole_by_id(hid)
			var hx: float = float(hole.get("x", ev.get("x", 0.0)))
			var hy: float = float(hole.get("y", ev.get("y", 0.0)))
			swallow_tweens.append({
				"x": float(ev.get("x", hx)),
				"y": float(ev.get("y", hy)),
				"target_x": hx,
				"target_y": hy,
				"radius": float(ev.get("radius", 0.25)),
				"tier": int(ev.get("tier", 0)),
				"scale": 1.0,
				"age": 0.0,
				"hole_id": hid,
			})
			swallow_flash = 0.18
			swallow_flash_hole = hid
			if blip_player.stream != null:
				blip_player.pitch_scale = 1.0 + 0.04 * float(ev.get("tier", 0))
				blip_player.play()
		elif kind == MunchiesSim.EVENT_ELIMINATED:
			if blip_player.stream != null:
				blip_player.pitch_scale = 0.7
				blip_player.play()


func _tick_presentation(dt: float) -> void:
	if swallow_flash > 0.0:
		swallow_flash = maxf(0.0, swallow_flash - dt)

	var keep: Array = []
	for tw_v in swallow_tweens:
		var tw: Dictionary = tw_v
		tw["age"] = float(tw["age"]) + dt
		var t: float = clampf(float(tw["age"]) / SWALLOW_TWEEN_SEC, 0.0, 1.0)
		tw["scale"] = 1.0 - t
		var hole: Dictionary = sim.hole_by_id(int(tw.get("hole_id", -1)))
		var hx: float = float(hole.get("x", tw["target_x"]))
		var hy: float = float(hole.get("y", tw["target_y"]))
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
	if not bool(hole["alive"]):
		# Follow a pending respawn spot / last position; camera still settles.
		pass
	var target := Vector2(float(hole["x"]), float(hole["y"])) * PIXELS_PER_METER
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
	if _screen != Screen.PLAYING or sim == null or sim.config == null:
		return
	var hole := sim.player_hole()
	title_label.text = "Munchies — %s" % sim.config.label()
	mode_line.text = _mode_line_text()
	score_label.text = "You  %d" % int(hole["score"])
	radius_label.text = "Radius  %.1f" % float(hole["radius"])
	if _paused:
		hint_label.text = "Paused — Esc to resume"
	elif sim.match_over and not sim.config.has_end_card():
		hint_label.text = "Unlimited running — Esc pause"
	else:
		var alive_n := 0
		for h in sim.holes:
			if h["alive"]:
				alive_n += 1
		hint_label.text = "WASD/arrows · Esc pause · holes alive %d/%d" % [alive_n, sim.holes.size()]


func _mode_line_text() -> String:
	var cfg: MatchConfig = sim.config
	match cfg.mode:
		MatchConfig.Mode.TIMER:
			var rem: float = sim.time_remaining()
			var m: int = int(rem) / 60
			var s: int = int(rem) % 60
			return "Time  %d:%02d" % [m, s]
		MatchConfig.Mode.SCORE_TARGET:
			var best := 0
			for h in sim.holes:
				best = maxi(best, int(h["score"]))
			return "Target  %d  ·  best %d" % [cfg.score_target, best]
		MatchConfig.Mode.MAP_CLEARED:
			return "Swallowable left  %d" % sim.swallowable_prop_count()
		MatchConfig.Mode.LAST_STANDING:
			var n := 0
			for h in sim.holes:
				if h["alive"]:
					n += 1
			return "Alive  %d" % n
		MatchConfig.Mode.UNLIMITED:
			return "Unlimited — props respawn · no player swallow"
	return cfg.label()
