extends Node2D
## Setup (modes + slot list + optional bots) → 3D match view.
## Slot 0 = keyboard; other filled slots = bots until pads exist. Esc pauses all.
## Unlimited never shows a clock or score target. Shared end card for ending modes.
## Presentation-only World3D reads sim each frame (one pane following the keyboard hole).

const CAMERA_SETTLE := 0.2
const SWALLOW_TWEEN_SEC := 0.72
## Rim pulse only after the hole grows by this much (not every swallow nibble).
const GROW_FLASH_STEP := 0.12
const GROW_FLASH_SEC := 0.34
## How far (meters) a swallowed prop falls straight down (no pull toward hole center).
const SWALLOW_DROP_M := 7.0
const PANE_GAP := 3.0
## Swallow blip: your hole loud, rivals duck so yours stays clear.
const BLIP_VOL_MINE_DB := -5.0
const BLIP_VOL_OTHER_DB := -26.0
## 3D camera: height / back offset in hole-radii (tilted chase).
const CAM3D_HEIGHT_MULT := 9.0
const CAM3D_BACK_MULT := 11.0
const CAM3D_BASE_M := 6.0

enum Screen { SETUP, PLAYING, ENDED }
enum SetupFocus { MODES, SLOTS }
enum PauseChoice { RESUME, RESTART, EXIT }

@onready var world3d: Node3D = $World3D
@onready var world3d_hold: Node = $World3DHold
@onready var pane_host: Control = $SplitLayer/PaneHost
@onready var hud: CanvasLayer = $HUD
@onready var left_panel: PanelContainer = $HUD/LeftPanel
@onready var timer_panel: PanelContainer = $HUD/TimerPanel
@onready var title_label: Label = $HUD/LeftPanel/Margin/VBox/Title
@onready var score_label: Label = $HUD/LeftPanel/Margin/VBox/Score
@onready var hint_label: Label = $HUD/LeftPanel/Margin/VBox/Hint
@onready var timer_label: Label = $HUD/TimerPanel/Margin/TimerLabel
@onready var setup_panel: PanelContainer = $HUD/Setup
@onready var setup_list: ItemList = $HUD/Setup/Margin/VBox/ModeList
@onready var slot_list: ItemList = $HUD/Setup/Margin/VBox/SlotList
@onready var setup_summary: Label = $HUD/Setup/Margin/VBox/SlotSummary
@onready var setup_hint: Label = $HUD/Setup/Margin/VBox/SetupHint
@onready var end_dim: ColorRect = $HUD/EndDim
@onready var end_panel: PanelContainer = $HUD/EndCard
@onready var end_title: Label = $HUD/EndCard/Margin/VBox/EndTitle
@onready var end_scores: Label = $HUD/EndCard/Margin/VBox/EndScores
@onready var end_hint: Label = $HUD/EndCard/Margin/VBox/EndHint
@onready var pause_overlay: Control = $HUD/Pause
@onready var pause_list: ItemList = $HUD/Pause/Panel/Margin/VBox/PauseList
@onready var blip_player: AudioStreamPlayer = $BlipPlayer
@onready var split_layer: CanvasLayer = $SplitLayer

var sim: MunchiesSim
var _paused := false
var _pause_cursor: int = 0
var _screen: Screen = Screen.SETUP
var _mode_index: int = 0 ## Timer highlighted by default
var _setup_focus: SetupFocus = SetupFocus.MODES
var _slot_cursor: int = 1
## Four setup slots. Slot 0 is always keyboard when filled.
var _slots: PackedStringArray = MatchConfig.default_slots(4)
## Presentation-only swallow ghosts: {x,y,radius,tier,scale,age,drop,hole_id,...}
var swallow_tweens: Array = []
## Rim grow flash (seconds remaining) — not tied to every swallow.
var grow_flash: float = 0.0
var grow_flash_hole: int = -1
## Last radius that triggered a grow flash, per hole id.
var _last_grow_radius: Dictionary = {}

## Per-pane camera / overlay state (Camera3D + look target).
var _panes: Array = []

const MODE_ORDER := [
	MatchConfig.Mode.TIMER,
	MatchConfig.Mode.SCORE_TARGET,
	MatchConfig.Mode.MAP_CLEARED,
	MatchConfig.Mode.LAST_STANDING,
	MatchConfig.Mode.UNLIMITED,
]


func _ready() -> void:
	sim = MunchiesSim.new()
	if world3d.get_parent() != world3d_hold:
		world3d.reparent(world3d_hold)
	world3d.set("host", self)
	pane_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	pane_host.offset_top = 0.0
	split_layer.visible = false
	pause_overlay.visible = false
	timer_panel.visible = false
	# Script owns ↑↓; ItemLists must not also consume ui_up/ui_down via focus.
	setup_list.focus_mode = Control.FOCUS_NONE
	slot_list.focus_mode = Control.FOCUS_NONE
	pause_list.focus_mode = Control.FOCUS_NONE
	setup_list.item_clicked.connect(_on_mode_item_clicked)
	slot_list.item_clicked.connect(_on_slot_item_clicked)
	pause_list.item_clicked.connect(_on_pause_item_clicked)
	_build_pause_list()
	_build_setup_list()
	_refresh_slot_list()
	_show_setup()


func _build_setup_list() -> void:
	setup_list.clear()
	for m in MODE_ORDER:
		var cfg := MatchConfig.for_mode(m, 4)
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
				extra = " — sandbox, no clock / target / end card"
		setup_list.add_item(cfg.label() + extra)
	setup_list.select(_mode_index)


func _slot_label(index: int) -> String:
	var kind: String = str(_slots[index])
	var mark := "▸ " if _setup_focus == SetupFocus.SLOTS and index == _slot_cursor else "  "
	match kind:
		MatchConfig.SLOT_KEYBOARD:
			return "%s%d. You (keyboard)" % [mark, index + 1]
		MatchConfig.SLOT_BOT:
			return "%s%d. Bot" % [mark, index + 1]
		_:
			return "%s%d. Empty  (optional bot)" % [mark, index + 1]


func _refresh_slot_list() -> void:
	slot_list.clear()
	for i in 4:
		slot_list.add_item(_slot_label(i))
	if _setup_focus == SetupFocus.SLOTS:
		slot_list.select(_slot_cursor)
	else:
		slot_list.deselect_all()
	var filled := 0
	var bots := 0
	for k in _slots:
		if str(k) == MatchConfig.SLOT_EMPTY:
			continue
		filled += 1
		if str(k) == MatchConfig.SLOT_BOT:
			bots += 1
	setup_summary.text = "Filled %d/4 · bots %d  (pads deferred)" % [filled, bots]
	var focus_hint := "modes" if _setup_focus == SetupFocus.MODES else "slots"
	setup_hint.text = (
		"Tab: %s · ↑↓ move · ←→ bot/empty · Enter start · Esc pauses in-match"
		% focus_hint
	)


func _show_setup() -> void:
	_screen = Screen.SETUP
	_set_paused(false)
	_teardown_panes()
	split_layer.visible = false
	setup_panel.visible = true
	end_dim.visible = false
	end_panel.visible = false
	timer_panel.visible = false
	left_panel.visible = true
	title_label.text = "Munchies"
	score_label.text = "Setup · optional bots"
	hint_label.text = ""
	_setup_focus = SetupFocus.MODES
	_apply_setup_focus()
	_refresh_slot_list()
	setup_list.select(_mode_index)


func _apply_setup_focus() -> void:
	## Keep both lists FOCUS_NONE so only `_process_setup` handles ↑↓.
	## Visual focus is selection + the ▸ mark / hint text — never grab_focus.
	## Only the active list stays selected; inactive list is deselected.
	setup_list.focus_mode = Control.FOCUS_NONE
	slot_list.focus_mode = Control.FOCUS_NONE
	if _setup_focus == SetupFocus.MODES:
		setup_list.select(_mode_index)
		setup_list.ensure_current_is_visible()
		slot_list.deselect_all()
	else:
		setup_list.deselect_all()
		_slot_cursor = clampi(_slot_cursor, 0, 3)
		slot_list.select(_slot_cursor)
		slot_list.ensure_current_is_visible()
	_refresh_slot_list()


func _on_mode_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	_mode_index = clampi(index, 0, MODE_ORDER.size() - 1)
	_setup_focus = SetupFocus.MODES
	_apply_setup_focus()


func _on_slot_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	_slot_cursor = clampi(index, 0, 3)
	_setup_focus = SetupFocus.SLOTS
	_apply_setup_focus()


func _make_config_from_setup() -> MatchConfig:
	var mode: MatchConfig.Mode = MODE_ORDER[_mode_index]
	var cfg := MatchConfig.for_mode(mode, 4)
	cfg.set_slots(_slots)
	return cfg


func _start_match() -> void:
	var cfg := _make_config_from_setup()
	if cfg.active_hole_count() < 1:
		return
	sim = MunchiesSim.new()
	sim.setup_match(cfg, 42)
	swallow_tweens.clear()
	grow_flash = 0.0
	grow_flash_hole = -1
	_last_grow_radius.clear()
	for h_v in sim.holes:
		var h: Dictionary = h_v
		_last_grow_radius[int(h["id"])] = float(h["radius"])
	_set_paused(false)
	_screen = Screen.PLAYING
	setup_panel.visible = false
	end_dim.visible = false
	end_panel.visible = false
	_rebuild_panes()
	split_layer.visible = true
	_update_hud()


func _show_end_card() -> void:
	_screen = Screen.ENDED
	end_dim.visible = true
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
	if Input.is_key_pressed(KEY_TAB):
		if not _tab_held:
			_tab_held = true
			_setup_focus = SetupFocus.SLOTS if _setup_focus == SetupFocus.MODES else SetupFocus.MODES
			_apply_setup_focus()
			return
	else:
		_tab_held = false

	# ↑↓ wrap inside the active list only. Tab alone switches SetupFocus.
	if _setup_focus == SetupFocus.MODES:
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
			_mode_index = (_mode_index - 1 + MODE_ORDER.size()) % MODE_ORDER.size()
			setup_list.select(_mode_index)
		elif Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
			_mode_index = (_mode_index + 1) % MODE_ORDER.size()
			setup_list.select(_mode_index)
	else:
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
			_slot_cursor = (_slot_cursor - 1 + 4) % 4
			_refresh_slot_list()
		elif Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
			_slot_cursor = (_slot_cursor + 1) % 4
			_refresh_slot_list()
		if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left") \
				or Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right"):
			_toggle_slot(_slot_cursor)
	if Input.is_action_just_pressed("confirm"):
		_start_match()


var _tab_held := false


func _toggle_slot(index: int) -> void:
	if index <= 0:
		# Slot 1 (index 0) stays keyboard for the local human.
		_slots[0] = MatchConfig.SLOT_KEYBOARD
		_refresh_slot_list()
		return
	if str(_slots[index]) == MatchConfig.SLOT_BOT:
		_slots[index] = MatchConfig.SLOT_EMPTY
	else:
		_slots[index] = MatchConfig.SLOT_BOT
	_refresh_slot_list()


func _process_playing(dt: float) -> void:
	if _paused:
		_process_pause_menu()
		_update_hud()
		return

	# Shared pause: Esc freezes the whole sim for every pane.
	if Input.is_action_just_pressed("pause"):
		_set_paused(true)
		_update_hud()
		return

	if not sim.match_over:
		var inputs := _collect_inputs()
		var events: Array = sim.step(inputs, dt)
		_handle_events(events)
		_check_grow_flash()
		if sim.match_over and sim.config != null and sim.config.has_end_card():
			_show_end_card()

	_tick_presentation(dt)
	_sync_pane_sizes()
	_update_cameras(dt)
	_update_hud()
	if world3d != null and world3d.has_method("sync_from_sim"):
		world3d.sync_from_sim()


func _build_pause_list() -> void:
	pause_list.clear()
	pause_list.add_item("Resume")
	pause_list.add_item("Restart match")
	pause_list.add_item("Exit to setup")
	_pause_cursor = 0
	pause_list.select(_pause_cursor)


func _on_pause_item_clicked(index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	_pause_cursor = clampi(index, 0, pause_list.item_count - 1)
	pause_list.select(_pause_cursor)
	_confirm_pause_choice()


func _set_paused(paused: bool) -> void:
	_paused = paused
	pause_overlay.visible = paused and _screen == Screen.PLAYING
	if paused:
		_pause_cursor = 0
		pause_list.select(_pause_cursor)


func _process_pause_menu() -> void:
	if Input.is_action_just_pressed("pause"):
		_set_paused(false)
		return
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
		_pause_cursor = (_pause_cursor - 1 + pause_list.item_count) % pause_list.item_count
		pause_list.select(_pause_cursor)
	elif Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
		_pause_cursor = (_pause_cursor + 1) % pause_list.item_count
		pause_list.select(_pause_cursor)
	if Input.is_action_just_pressed("confirm"):
		_confirm_pause_choice()


func _confirm_pause_choice() -> void:
	match _pause_cursor:
		PauseChoice.RESUME:
			_set_paused(false)
		PauseChoice.RESTART:
			_start_match()
		PauseChoice.EXIT:
			_show_setup()


func _process_ended() -> void:
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("pause"):
		_show_setup()


func _collect_inputs() -> Dictionary:
	# Keyboard hole(s) read WASD/arrows; bots emit Input. Pads deferred.
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
	# WASD/arrows make a 2D stick. Holding W+D is (1,1), length √2 ≈ 1.41.
	# Normalize when longer than 1 so diagonal speed matches full tilt, not faster.
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
			# Freeze world x/y at the swallow spot — fall down, do not slide to hole center.
			swallow_tweens.append({
				"x": float(ev.get("x", 0.0)),
				"y": float(ev.get("y", 0.0)),
				"radius": float(ev.get("radius", 0.25)),
				"tier": int(ev.get("tier", 0)),
				"prop_id": int(ev.get("prop_id", 0)),
				"role": int(ev.get("role", MunchiesSim.ROLE_PROP)),
				"vehicle": int(ev.get("vehicle", MunchiesSim.VEHICLE_SEDAN)),
				"body_color": ev.get("body_color"),
				"scale": 1.0,
				"alpha": 1.0,
				"drop": 0.0, ## meters straight down into the pit
				"age": 0.0,
				"hole_id": hid,
				"tip_angle": float(ev.get("tip_angle", 0.0)),
				"fallen": bool(ev.get("fallen", false)),
				"tip_dx": float(ev.get("tip_dx", 1.0)),
				"tip_dy": float(ev.get("tip_dy", 0.0)),
			})
			# Rim flash is grow-only — swallow still gets an audio blip.
			# Duck rivals so your own swallows stay clear.
			if blip_player.stream != null:
				var mine := _keyboard_hole()
				var mine_id: int = int(mine.get("id", -1)) if not mine.is_empty() else -1
				blip_player.volume_db = (
					BLIP_VOL_MINE_DB if hid == mine_id else BLIP_VOL_OTHER_DB
				)
				blip_player.pitch_scale = 1.0 + 0.04 * float(ev.get("tier", 0))
				blip_player.play()
		elif kind == MunchiesSim.EVENT_ELIMINATED:
			if blip_player.stream != null:
				blip_player.volume_db = BLIP_VOL_MINE_DB
				blip_player.pitch_scale = 0.7
				blip_player.play()


func _check_grow_flash() -> void:
	## Pulse the rim when radius crosses the next grow step (not every nibble).
	for hole_v in sim.holes:
		var hole: Dictionary = hole_v
		var hid: int = int(hole["id"])
		var r: float = float(hole["radius"])
		if not _last_grow_radius.has(hid):
			_last_grow_radius[hid] = r
			continue
		var prev: float = float(_last_grow_radius[hid])
		if r - prev >= GROW_FLASH_STEP:
			grow_flash = GROW_FLASH_SEC
			grow_flash_hole = hid
			_last_grow_radius[hid] = r


func _tick_presentation(dt: float) -> void:
	if grow_flash > 0.0:
		grow_flash = maxf(0.0, grow_flash - dt)

	var keep: Array = []
	for tw_v in swallow_tweens:
		var tw: Dictionary = tw_v
		tw["age"] = float(tw["age"]) + dt
		var t: float = clampf(float(tw["age"]) / SWALLOW_TWEEN_SEC, 0.0, 1.0)
		# Fall straight down at freeze x/y — accelerate into the pit, fade late.
		# No attraction toward the hole center (x/y stay where the swallow started).
		var fall_t: float = t * t
		tw["drop"] = fall_t * SWALLOW_DROP_M
		tw["scale"] = 1.0 - 0.2 * t
		# Stay readable through most of the fall; fade only in the last third.
		tw["alpha"] = 1.0 - smoothstep(0.55, 1.0, t)
		if t < 1.0:
			keep.append(tw)
	swallow_tweens = keep


func _teardown_panes() -> void:
	if world3d != null and is_instance_valid(world3d) and world3d.get_parent() != world3d_hold:
		world3d.reparent(world3d_hold)
	for child in pane_host.get_children():
		child.queue_free()
	_panes.clear()


func _rebuild_panes() -> void:
	_teardown_panes()
	## One 3D pane following the keyboard hole.
	var follow: Dictionary = _keyboard_hole()
	if follow.is_empty() and not sim.holes.is_empty():
		follow = sim.holes[0]
	if follow.is_empty():
		return

	var layout := _make_layout(1)
	pane_host.add_child(layout)
	var cell: Control = layout.get_node("Cell0") as Control

	var frame := Control.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(frame)

	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(svc)

	var sv := SubViewport.new()
	sv.disable_3d = false
	sv.transparent_bg = false
	sv.handle_input_locally = false
	sv.gui_disable_input = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.size = Vector2i(2, 2)
	svc.add_child(sv)

	# Soft daylight + sky so meshes read without a baked env resource.
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.58, 0.72)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.60, 0.58)
	environment.ambient_light_energy = 0.55
	env.environment = environment
	sv.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	sv.add_child(sun)

	world3d.reparent(sv)
	if world3d.has_method("clear_presentation"):
		world3d.clear_presentation()
	world3d.set("host", self)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 50.0
	cam.near = 0.2
	cam.far = 400.0
	sv.add_child(cam)

	var labels := _make_pane_overlay(frame, follow, 0)
	var look := Vector3(float(follow["x"]), 0.0, float(follow["y"]))
	var r: float = float(follow["radius"])
	_place_camera_3d(cam, look, r)

	_panes.append({
		"hole_id": int(follow["id"]),
		"camera": cam,
		"cam_pos": look,
		"cam_zoom": r,
		"score_label": labels["score"],
		"radius_label": labels["radius"],
		"viewport": sv,
		"frame": frame,
	})

	_sync_pane_sizes()
	if world3d.has_method("sync_from_sim"):
		world3d.sync_from_sim()


func _make_pane_overlay(frame: Control, _hole: Dictionary, _slot_fallback: int) -> Dictionary:
	## Local score/radius sit top-right in a dark chip so they stay readable.
	## Hole names live on the hole mesh, not here.
	var overlay := MarginContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_theme_constant_override("margin_left", 10)
	overlay.add_theme_constant_override("margin_top", 10)
	overlay.add_theme_constant_override("margin_right", 12)
	overlay.add_theme_constant_override("margin_bottom", 8)
	frame.add_child(overlay)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(row)

	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.04, 0.048, 0.72)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.2, 0.24, 0.22, 0.7)
	sb.set_corner_radius_all(8)
	chip.add_theme_stylebox_override("panel", sb)
	row.add_child(chip)

	var chip_margin := MarginContainer.new()
	chip_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_margin.add_theme_constant_override("margin_left", 12)
	chip_margin.add_theme_constant_override("margin_top", 8)
	chip_margin.add_theme_constant_override("margin_right", 12)
	chip_margin.add_theme_constant_override("margin_bottom", 8)
	chip.add_child(chip_margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	chip_margin.add_child(vbox)

	var score_l := Label.new()
	score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	score_l.add_theme_font_size_override("font_size", 22)
	vbox.add_child(score_l)

	var radius_l := Label.new()
	radius_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	radius_l.add_theme_color_override("font_color", Color(0.75, 0.88, 0.82))
	radius_l.add_theme_font_size_override("font_size", 16)
	vbox.add_child(radius_l)

	return {"score": score_l, "radius": radius_l}


func _keyboard_hole() -> Dictionary:
	for hole_v in sim.holes:
		var hole: Dictionary = hole_v
		if not bool(hole.get("is_bot", false)):
			return hole
	return {}


func _place_camera_3d(cam: Camera3D, look: Vector3, radius: float) -> void:
	var dist: float = CAM3D_BASE_M + radius * CAM3D_BACK_MULT
	var height: float = CAM3D_BASE_M * 0.7 + radius * CAM3D_HEIGHT_MULT
	var cam_pos := look + Vector3(0.0, height, dist)
	cam.look_at_from_position(cam_pos, look + Vector3(0.0, radius * 0.2, 0.0), Vector3.UP)


func _make_layout(n: int) -> Control:
	## 1 fullscreen · 2 side-by-side · 3/4 quadrants (blank cell when n==3).
	if n <= 1:
		var root := Control.new()
		_fill_parent(root)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cell := _make_cell(0)
		_fill_parent(cell)
		root.add_child(cell)
		return root

	if n == 2:
		var row := HBoxContainer.new()
		_fill_parent(row)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", int(PANE_GAP))
		for i in 2:
			var cell := _make_cell(i)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
			row.add_child(cell)
		return row

	# 3 or 4 → 2×2 grid; empty quadrant stays blank with three.
	var grid := GridContainer.new()
	grid.columns = 2
	_fill_parent(grid)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", int(PANE_GAP))
	grid.add_theme_constant_override("v_separation", int(PANE_GAP))
	for i in 4:
		if i < n:
			var cell := _make_cell(i)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cell.custom_minimum_size = Vector2(64, 64)
			grid.add_child(cell)
		else:
			var blank := ColorRect.new()
			blank.color = Color(0.08, 0.10, 0.09)
			blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			blank.size_flags_vertical = Control.SIZE_EXPAND_FILL
			blank.custom_minimum_size = Vector2(64, 64)
			blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(blank)
	return grid


func _fill_parent(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.grow_horizontal = Control.GROW_DIRECTION_BOTH
	node.grow_vertical = Control.GROW_DIRECTION_BOTH


func _make_cell(index: int) -> Control:
	var cell := PanelContainer.new()
	cell.name = "Cell%d" % index
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.06)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.22, 0.28, 0.24)
	cell.add_theme_stylebox_override("panel", sb)
	return cell


func _sync_pane_sizes() -> void:
	for pane_v in _panes:
		var pane: Dictionary = pane_v
		var frame: Control = pane["frame"]
		var sv: SubViewport = pane["viewport"]
		var sz := frame.size
		if sz.x < 2.0 or sz.y < 2.0:
			continue
		var want := Vector2i(maxi(2, int(sz.x)), maxi(2, int(sz.y)))
		if sv.size != want:
			sv.size = want


func _update_cameras(dt: float) -> void:
	var blend: float = 1.0 - exp(-dt / CAMERA_SETTLE)
	for pane_v in _panes:
		var pane: Dictionary = pane_v
		var hole: Dictionary = sim.hole_by_id(int(pane["hole_id"]))
		if hole.is_empty():
			continue

		_update_camera_3d(pane, hole, blend)

		var score_l: Label = pane["score_label"]
		var radius_l: Label = pane["radius_label"]
		score_l.text = "%d" % int(hole["score"])
		radius_l.text = "r %.1f%s" % [
			float(hole["radius"]),
			"" if bool(hole["alive"]) else " · out",
		]


func _update_camera_3d(pane: Dictionary, hole: Dictionary, blend: float) -> void:
	var cam: Camera3D = pane["camera"]
	var look := Vector3(float(hole["x"]), 0.0, float(hole["y"]))
	var vel := Vector3(float(hole["vx"]), 0.0, float(hole["vy"]))
	var lead := vel * 0.15
	var lead_cap: float = 0.4 * float(hole["radius"])
	if lead.length() > lead_cap:
		lead = lead.normalized() * lead_cap
	look += lead

	var cam_pos: Vector3 = pane["cam_pos"]
	cam_pos = cam_pos.lerp(look, blend)
	pane["cam_pos"] = cam_pos
	var radius_s: float = lerpf(float(pane["cam_zoom"]), float(hole["radius"]), blend)
	pane["cam_zoom"] = radius_s
	_place_camera_3d(cam, cam_pos, radius_s)


func _update_hud() -> void:
	if _screen != Screen.PLAYING or sim == null or sim.config == null:
		return
	# World is fullscreen; HUD floats in content-sized dark panels over it.
	pane_host.offset_top = 0.0
	left_panel.visible = true
	title_label.text = "Munchies — %s" % sim.config.label()
	if sim.holes.size() > 1:
		score_label.text = _leaderboard_text()
	else:
		score_label.text = "You"

	# Mode status (timer, target, …) sits top-center in its own panel.
	var status: String = _mode_status_text()
	timer_panel.visible = not status.is_empty()
	if not status.is_empty():
		timer_label.text = status

	if _paused:
		hint_label.text = ""
	elif sim.config.mode == MatchConfig.Mode.UNLIMITED:
		hint_label.text = "Esc pause"
	elif sim.match_over and not sim.config.has_end_card():
		hint_label.text = "Esc pause"
	else:
		var alive_n := 0
		for h in sim.holes:
			if h["alive"]:
				alive_n += 1
		hint_label.text = "WASD · Esc pause · alive %d/%d" % [alive_n, sim.holes.size()]


func _leaderboard_text() -> String:
	var ranked: Array = sim.holes.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"])
	)
	var lines := PackedStringArray()
	for i in ranked.size():
		var hole: Dictionary = ranked[i]
		var place: int = i + 1
		var alive_mark: String = "" if bool(hole["alive"]) else " · out"
		lines.append("%d. %s  %d%s" % [
			place,
			str(hole.get("name", "?")),
			int(hole["score"]),
			alive_mark,
		])
	return "\n".join(lines)


func _mode_status_text() -> String:
	## Top-center status. Timer is just the clock, larger; other modes keep a short label.
	var cfg: MatchConfig = sim.config
	match cfg.mode:
		MatchConfig.Mode.TIMER:
			var rem: float = sim.time_remaining()
			var m: int = int(rem) / 60
			var s: int = int(rem) % 60
			return "%d:%02d" % [m, s]
		MatchConfig.Mode.SCORE_TARGET:
			var best := 0
			for h in sim.holes:
				best = maxi(best, int(h["score"]))
			return "Target %d · %d" % [cfg.score_target, best]
		MatchConfig.Mode.MAP_CLEARED:
			return "Left %d" % sim.swallowable_prop_count()
		MatchConfig.Mode.LAST_STANDING:
			var n := 0
			for h in sim.holes:
				if h["alive"]:
					n += 1
			return "Alive %d" % n
		MatchConfig.Mode.UNLIMITED:
			return "Unlimited"
	return cfg.label()
