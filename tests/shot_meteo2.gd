extends SceneTree
func _init() -> void:
	var b := Board3D.new()
	root.add_child(b)
	await process_frame
	var t := Track.build("a b c d e f g h i j k l m n o p q r s t u".split(" "), false)
	t.compute_heights(0.0)
	b.show_track(t)
	b.show_weather([{"piece": 1, "kind": "bagnato"}, {"piece": 2, "kind": "laterale"}])
	var R := Rules.new()
	R.setup(t, ["cpu", "cpu"])
	var s0: int = t.pieces[1]["s0"]
	for i in R.riders.size():
		R.riders[i]["pos"] = s0 + i
		R.riders[i]["lane"] = i % 2
	b.make_tokens(R.riders)
	b.follow = false
	var k := 0
	for view in [[0.75, 0.5, 7.5], [1.25, 0.0, 9.0]]:
		var c := t.square_center(s0 + 2)
		b.desired = Vector3(c.x, 0.4, c.y)
		b.target = b.desired
		b.pitch = view[0]
		b.yaw = view[1]
		b.dist = view[2]
		for i in 45: await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("SP") + "/meteo2_%d.png" % k)
		k += 1
	quit()
