extends SceneTree
## One-shot map capture for art-pass evidence.
##   godot --path . -s res://scripts/capture_map.gd
## Writes /tmp/munchies-map-after.png

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host_script := GDScript.new()
	host_script.source_code = """
extends Node
var sim
var swallow_tweens: Array = []
var grow_flash: float = 0.0
var grow_flash_hole: int = -1
"""
	host_script.reload()
	var host := Node.new()
	host.set_script(host_script)
	root.add_child(host)

	var sim := MunchiesSim.new()
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 1)
	cfg.set_slots(PackedStringArray([
		MatchConfig.SLOT_KEYBOARD,
		MatchConfig.SLOT_EMPTY,
		MatchConfig.SLOT_EMPTY,
		MatchConfig.SLOT_EMPTY,
	]))
	sim.setup_match(cfg, 42)
	host.sim = sim

	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.disable_3d = true
	sv.transparent_bg = false
	root.add_child(sv)

	var world_script: GDScript = load("res://scripts/world_view.gd") as GDScript
	var world := Node2D.new()
	world.set_script(world_script)
	world.set("host", host)
	sv.add_child(world)

	var cam := Camera2D.new()
	cam.enabled = true
	# Frame roads + park edge + a building so place-making reads in one shot.
	cam.position = Vector2(-20, -8) * 24.0
	cam.zoom = Vector2(0.42, 0.42)
	sv.add_child(cam)

	world.queue_redraw()
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	var img: Image = sv.get_texture().get_image()
	var out_path := "/tmp/munchies-map-after.png"
	var err := img.save_png(out_path)
	if err != OK:
		print("FAIL save: ", err)
		quit(1)
		return
	print("WROTE ", out_path, " bytes=", FileAccess.get_file_as_bytes(out_path).size())
	quit(0)
