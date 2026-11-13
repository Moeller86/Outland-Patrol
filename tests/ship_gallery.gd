extends Node3D
## Skærmbillede af alle skibstyper side om side (kun med skærm).
func _ready() -> void:
	print("gallery start")
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1a1430")
	env.environment.ambient_light_color = Color("8a86b0")
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var order: Array = Game.ship_data["order"]
	var cols := 4
	for i in order.size():
		var m := ShipModel.new()
		m.ship_class = order[i]
		m.paint = Color("e94f64") if i % 3 == 0 else (Color("4d8bff") if i % 3 == 1 else Color("6bdc4f"))
		var x := (i % cols - (cols - 1) / 2.0) * 24.0
		var z := (i / cols) * 26.0
		m.position = Vector3(x, 0, z)
		m.rotation = Vector3(0, 0.9, 0)
		var big: bool = order[i] == "krydser"
		m.scale = Vector3.ONE * (0.75 if big else 1.0)
		add_child(m)
		var l := Label3D.new()
		l.text = str(Game.ship_data["classes"][order[i]]["name"])
		l.font_size = 64
		l.pixel_size = 0.03
		l.position = m.position + Vector3(0, 6, 0)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
	print("built")
	var cam := Camera3D.new()
	cam.position = Vector3(0, 55, 85)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(0, 0, 24))
	for k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://screenshots/95_skibe.png")
	get_tree().quit()
