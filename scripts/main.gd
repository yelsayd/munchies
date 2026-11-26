extends Node2D
## Phase 6 view: setup (modes + slot list + optional bots) → couch split-screen.
## Slot 0 = keyboard; other filled slots = bots until pads exist. Esc pauses all.
## Unlimited never shows a clock or score target. Shared end card for ending modes.

const PIXELS_PER_METER := 24.0
const CAMERA_SETTLE := 0.2
const HOLE_SCREEN_FRACTION := 0.20 ## diameter vs shorter pane side
const SWALLOW_TWEEN_SEC := 0.20
const PANE_GAP := 3.0
const TOP_HUD_BAND := 72.0

enum Screen { SETUP, PLAYING, ENDED }
enum SetupFocus { MODES, SLOTS }

@onready var world: Node2D = $World
@onready var world_hold: Node2D = $WorldHold
@onready var pane_host: Control = $SplitLayer/PaneHost
@onready var hud: CanvasLayer = $HUD
@onready var title_label: Label = $HUD/Margin/VBox/Title
@onready var mode_line: Label = $HUD/Margin/VBox/ModeLine
@onready var score_label: Label = $HUD/Margin/VBox/Score
@onready var radius_label: Label = $HUD/Margin/VBox/Radius
@onready var hint_label: Label = $HUD/Margin/VBox/Hint
@onready var setup_panel: PanelContainer = $HUD/Setup
@onready var setup_list: ItemList = $HUD/Setup/Margin/VBox/ModeList
@onready var slot_list: ItemList = $HUD/Setup/Margin/VBox/SlotList
@onready var setup_summary: Label = $HUD/Setup/Margin/VBox/SlotSummary
@onready var setup_hint: Label = $HUD/Setup/Margin/VBox/SetupHint
@onready var end_panel: PanelContainer = $HUD/EndCard
@onready var end_title: Label = $HUD/EndCard/Margin/VBox/EndTitle
@onready var end_scores: Label = $HUD/EndCard/Margin/VBox/EndScores
@onready var end_hint: Label = $HUD/EndCard/Margin/VBox/EndHint
@onready var blip_player: AudioStreamPlayer = $BlipPlayer
@onready var split_layer: CanvasLayer = $SplitLayer

var sim: MunchiesSim
var _paused := false
var _screen: Screen = Screen.SETUP
var _mode_index: int = 0 ## Timer highlighted by default
var _setup_focus: SetupFocus = SetupFocus.MODES
var _slot_cursor: int = 1
## Four setup slots. Slot 0 is always keyboard when filled.
var _slots: PackedStringArray = MatchConfig.default_slots(4)

## Presentation-only swallow ghosts: {x,y,radius,tier,scale,age,target_x,target_y,hole_id}
var swallow_tweens: Array = []
var swallow_flash: float = 0.0
var swallow_flash_hole: int = -1

## Per-pane camera / overlay state.
## {hole_id, camera, cam_pos, cam_zoom, score_label, radius_label, viewport, frame}
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
	if world.get_parent() != world_hold:
		world.reparent(world_hold)
	world.set("host", self)
	pane_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	pane_host.offset_top = TOP_HUD_BAND
	split_layer.visible = false
	# Script owns ↑↓; ItemLists must not also consume ui_up/ui_down via focus.
	setup_list.focus_mode = Control.FOCUS_NONE
	slot_list.focus_mode = Control.FOCUS_NONE
	setup_list.item_clicked.connect(_on_mode_item_clicked)
	slot_list.item_clicked.connect(_on_slot_item_clicked)
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
	setup_summary.text = "Filled %d/4 · bots %d · panes: %s  (pads deferred)" % [
		filled,
		bots,
		_pane_layout_label(filled),
	]
	var focus_hint := "modes" if _setup_focus == SetupFocus.MODES else "slots"
	setup_hint.text = (
		"Tab: %s · ↑↓ move · ←→ bot/empty on slots 2–4 · Enter start · Esc pauses in-match"
		% focus_hint
	)


func _pane_layout_label(n: int) -> String:
	match n:
		0, 1:
			return "1 fullscreen"
		2:
			return "2 side-by-side"
		3:
			return "3 quadrants (1 blank)"
		_:
			return "4 quadrants"


func _show_setup() -> void:
	_screen = Screen.SETUP
	_paused = false
	_teardown_panes()
	split_layer.visible = false
	setup_panel.visible = true
	end_panel.visible = false
	title_label.text = "Munchies — Phase 6"
	mode_line.text = "Setup · Timer at 2:00 · optional bots · shared end card"
	score_label.text = ""
	radius_label.text = ""
	hint_label.text = ""
	_setup_focus = SetupFocus.MODES
	_apply_setup_focus()
	_refresh_slot_list()
	setup_list.select(_mode_index)


func _apply_setup_focus() -> void:
	## Keep both lists FOCUS_NONE so only `_process_setup` handles ↑↓.
	## Visual focus is selection + the ▸ mark / hint text — never grab_focus.
	setup_list.focus_mode = Control.FOCUS_NONE
	slot_list.focus_mode = Control.FOCUS_NONE
	if _setup_focus == SetupFocus.MODES:
		setup_list.select(_mode_index)
		setup_list.ensure_current_is_visible()
		slot_list.deselect_all()
	else:
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
	swallow_flash = 0.0
	_paused = false
	_screen = Screen.PLAYING
	setup_panel.visible = false
	end_panel.visible = false
	_rebuild_panes()
	split_layer.visible = true
	_update_hud()


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
	if Input.is_key_pressed(KEY_TAB):
		if not _tab_held:
			_tab_held = true
			_setup_focus = SetupFocus.SLOTS if _setup_focus == SetupFocus.MODES else SetupFocus.MODES
			_apply_setup_focus()
			return
	else:
		_tab_held = false

	if _setup_focus == SetupFocus.MODES:
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
			_mode_index = (_mode_index - 1 + MODE_ORDER.size()) % MODE_ORDER.size()
			setup_list.select(_mode_index)
		elif Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_down"):
			# Edge: leave modes into slots instead of wrapping + dual-list scroll.
			if _mode_index >= MODE_ORDER.size() - 1:
				_setup_focus = SetupFocus.SLOTS
				_apply_setup_focus()
			else:
				_mode_index += 1
				setup_list.select(_mode_index)
	else:
		if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_up"):
			if _slot_cursor <= 0:
				_setup_focus = SetupFocus.MODES
				_apply_setup_focus()
			else:
				_slot_cursor -= 1
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
	# Shared pause: Esc freezes the whole sim for every pane.
	if Input.is_action_just_pressed("pause"):
		_paused = not _paused

	if not _paused and not sim.match_over:
		var inputs := _collect_inputs()
		var events: Array = sim.step(inputs, dt)
		_handle_events(events)
		if sim.match_over and sim.config != null and sim.config.has_end_card():
			_show_end_card()

	_tick_presentation(dt)
	_sync_pane_sizes()
	_update_cameras(dt)
	_update_hud()
	if world != null:
		world.queue_redraw()


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


func _teardown_panes() -> void:
	if world != null and is_instance_valid(world) and world.get_parent() != world_hold:
		world.reparent(world_hold)
	for child in pane_host.get_children():
		child.queue_free()
	_panes.clear()


func _rebuild_panes() -> void:
	_teardown_panes()
	var n: int = sim.holes.size()
	var layout := _make_layout(n)
	pane_host.add_child(layout)

	var shared_world: World2D = null
	for i in n:
		var hole: Dictionary = sim.holes[i]
		var hole_id: int = int(hole["id"])
		var cell: Control = layout.get_node("Cell%d" % i) as Control

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
		sv.disable_3d = true
		sv.transparent_bg = false
		sv.handle_input_locally = false
		sv.gui_disable_input = true
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.size = Vector2i(2, 2)
		svc.add_child(sv)

		if shared_world == null:
			# First pane owns the World node; others share its World2D.
			world.reparent(sv)
			shared_world = sv.world_2d
		else:
			sv.world_2d = shared_world

		var cam := Camera2D.new()
		cam.enabled = true
		sv.add_child(cam)

		var overlay := MarginContainer.new()
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_theme_constant_override("margin_left", 10)
		overlay.add_theme_constant_override("margin_top", 8)
		overlay.add_theme_constant_override("margin_right", 10)
		overlay.add_theme_constant_override("margin_bottom", 8)
		frame.add_child(overlay)

		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 2)
		overlay.add_child(vbox)

		var name_l := Label.new()
		var slot: int = int(hole.get("slot", i))
		var ring: Color = MunchiesSim.HOLE_RING_COLORS[clampi(slot, 0, MunchiesSim.HOLE_RING_COLORS.size() - 1)]
		name_l.text = str(hole.get("name", "Hole"))
		name_l.add_theme_color_override("font_color", ring)
		name_l.add_theme_font_size_override("font_size", 16)
		vbox.add_child(name_l)

		var score_l := Label.new()
		score_l.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
		score_l.add_theme_font_size_override("font_size", 22)
		vbox.add_child(score_l)

		var radius_l := Label.new()
		radius_l.add_theme_color_override("font_color", Color(0.75, 0.88, 0.82))
		radius_l.add_theme_font_size_override("font_size", 16)
		vbox.add_child(radius_l)

		var cam_pos := Vector2(float(hole["x"]), float(hole["y"])) * PIXELS_PER_METER
		cam.position = cam_pos
		var z: float = _desired_zoom(float(hole["radius"]), Vector2(640, 360))
		cam.zoom = Vector2(z, z)

		_panes.append({
			"hole_id": hole_id,
			"camera": cam,
			"cam_pos": cam_pos,
			"cam_zoom": z,
			"score_label": score_l,
			"radius_label": radius_l,
			"viewport": sv,
			"frame": frame,
		})

	_sync_pane_sizes()
	world.queue_redraw()


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


func _desired_zoom(radius: float, pane_size: Vector2) -> float:
	# Aim for the hole's diameter to fill about 20% of the shorter pane side.
	# Example: pane 360 px tall → hole draws ~72 px across (0.20 × 360).
	var shorter: float = minf(pane_size.x, pane_size.y)
	if shorter < 1.0:
		shorter = 360.0
	var diameter_m: float = 2.0 * radius
	var z: float = (HOLE_SCREEN_FRACTION * shorter) / (diameter_m * PIXELS_PER_METER)
	# Keep at least one suction-diameter of ground around a large hole.
	var suction_diameter_m: float = 2.0 * radius * MunchiesSim.PROP_SUCTION_MULT
	var min_span_m: float = diameter_m + suction_diameter_m
	var max_zoom: float = shorter / (min_span_m * PIXELS_PER_METER)
	# Floor so start is not a filled pane on the 160 m map.
	return clampf(z, 0.12, maxf(0.12, max_zoom))


func _update_cameras(dt: float) -> void:
	var blend: float = 1.0 - exp(-dt / CAMERA_SETTLE)
	for pane_v in _panes:
		var pane: Dictionary = pane_v
		var hole: Dictionary = sim.hole_by_id(int(pane["hole_id"]))
		if hole.is_empty():
			continue
		var cam: Camera2D = pane["camera"]
		var target := Vector2(float(hole["x"]), float(hole["y"])) * PIXELS_PER_METER
		var vel := Vector2(float(hole["vx"]), float(hole["vy"])) * PIXELS_PER_METER
		var look := vel * 0.15
		var look_cap: float = 0.4 * float(hole["radius"]) * PIXELS_PER_METER
		if look.length() > look_cap:
			look = look.normalized() * look_cap
		target += look

		var cam_pos: Vector2 = pane["cam_pos"]
		cam_pos = cam_pos.lerp(target, blend)
		pane["cam_pos"] = cam_pos
		cam.position = cam_pos

		var sv: SubViewport = pane["viewport"]
		var pane_size := Vector2(sv.size)
		var desired_zoom: float = _desired_zoom(float(hole["radius"]), pane_size)
		var cam_zoom: float = lerpf(float(pane["cam_zoom"]), desired_zoom, blend)
		pane["cam_zoom"] = cam_zoom
		cam.zoom = Vector2(cam_zoom, cam_zoom)

		var score_l: Label = pane["score_label"]
		var radius_l: Label = pane["radius_label"]
		score_l.text = "%d" % int(hole["score"])
		radius_l.text = "r %.1f%s" % [
			float(hole["radius"]),
			"" if bool(hole["alive"]) else " · out",
		]


func _update_hud() -> void:
	if _screen != Screen.PLAYING or sim == null or sim.config == null:
		return
	title_label.text = "Munchies — %s" % sim.config.label()
	mode_line.text = _mode_line_text()
	# Shared band: mode line only. Per-hole score/radius live in each pane.
	score_label.text = "Split · %s" % _pane_layout_label(sim.holes.size())
	radius_label.text = ""
	if _paused:
		hint_label.text = "Paused (all panes) — Esc to resume"
	elif sim.config.mode == MatchConfig.Mode.UNLIMITED:
		# Unlimited: no clock, no target, no end card.
		hint_label.text = "Unlimited sandbox — Esc pause · leave running"
	elif sim.match_over and not sim.config.has_end_card():
		hint_label.text = "Unlimited running — Esc pause"
	else:
		var alive_n := 0
		for h in sim.holes:
			if h["alive"]:
				alive_n += 1
		hint_label.text = "WASD/arrows (You) · Esc pause all · alive %d/%d" % [alive_n, sim.holes.size()]


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
			# Never open unlimited with a clock or score target.
			return "Unlimited — props respawn · no player swallow"
	return cfg.label()
