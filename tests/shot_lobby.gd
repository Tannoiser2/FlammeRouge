extends SceneTree
func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	main.splash_close.call()
	for i in 20: await process_frame
	main.cfg["n"] = 3
	main.cfg["kind"] = [0, 0, 1, 1, 1, 1]
	main.online_box.visible = true
	main.online_name.text = "Stefano"
	await main._online_create()
	var guest := Net.new()
	root.add_child(guest)
	await process_frame
	await guest.join_room(main.online["code"], "Marco")
	for i in 3: await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(OS.get_environment("SP") + "/lobby.png")
	quit()
