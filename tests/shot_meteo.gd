extends SceneTree
func _init() -> void:
	var b := Board3D.new()
	root.add_child(b)
	await process_frame
	var t := Track.build("a b c d e f g h i j k l m n o p q r s t u".split(" "), false)
	t.compute_heights(0.0)
	b.show_track(t)
	b.show_weather([{"piece": 1, "kind": "bagnato"}, {"piece": 2, "kind": "laterale"}, {"piece": 3, "kind": "favore"}, {"piece": 12, "kind": "contrario"}])
	b.follow = false
	var shots := [[1, 0.75, 0.5], [2, 0.6, 0.9], [3, 0.7, 0.3]]
	var k := 0
	for sh in shots:
		var pc: Dictionary = t.pieces[sh[0]]
		var c := t.square_center(int(pc["s0"]) + 2)
		b.desired = Vector3(c.x, 0.6, c.y)
		b.target = b.desired
		b.dist = 7.5
		b.pitch = sh[1]
		b.yaw = sh[2]
		for i in 45: await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("SP") + "/meteo_%d.png" % k)
		k += 1
	quit()
