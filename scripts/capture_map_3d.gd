extends SceneTree
## One-shot 3D map capture for the presentation spike.
##   godot --path . -s res://scripts/capture_map_3d.gd
## Writes /tmp/munchies-3d-spike.png

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host_script := GDScript.new()
	host_script.source_code = """
extends Node
var sim
var swallow_tweens: Array = []
var swallow_flash: float = 0.0
var swallow_flash_hole: int = -1
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
	sv.disable_3d = false
	sv.transparent_bg = false
	sv.own_world_3d = true
	root.add_child(sv)

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
	sv.add_child(sun)

	var world_script: GDScript = load("res://scripts/world_view_3d.gd") as GDScript
	var world := Node3D.new()
	world.set_script(world_script)
	world.set("host", host)
	sv.add_child(world)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 50.0
	sv.add_child(cam)
	# Frame roads + park edge + buildings from a tilted chase angle near spawn.
	var look := Vector3(-20.0, 0.0, -8.0)
	var cam_pos := look + Vector3(0.0, 28.0, 36.0)
	cam.look_at_from_position(cam_pos, look, Vector3.UP)

	# Needs a real renderer (not --headless dummy) for get_texture().
	await process_frame
	if world.has_method("sync_from_sim"):
		world.sync_from_sim()
	for _i in 8:
		await process_frame

	var tex: ViewportTexture = sv.get_texture()
	if tex == null:
		print("FAIL: viewport texture null (use without --headless)")
		quit(1)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("FAIL: image null")
		quit(1)
		return
	var out_path := "/tmp/munchies-3d-spike.png"
	var err := img.save_png(out_path)
	if err != OK:
		print("FAIL save: ", err)
		quit(1)
		return
	print("WROTE ", out_path, " bytes=", FileAccess.get_file_as_bytes(out_path).size())
	quit(0)
