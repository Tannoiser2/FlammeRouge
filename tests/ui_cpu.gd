extends SceneTree
func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	main.splash_close.call()
	for i in 20: await process_frame
	main.cfg["n"] = 3
	main.cfg["kind"] = [1, 1, 1, 1, 1, 1]
	main.cfg["free_start"] = false
	main.cfg["anim"] = 2
	main.cfg["mode"] = 0
	main.cfg["cpu"] = 1
	main._preview()
	Engine.time_scale = 12.0
	var t0 := Time.get_ticks_msec()
	main._start_race()
	while not main.report.visible and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("livelli: ", main.R.teams.map(func(t): return t.get("level")), ", corsa conclusa: ", main.R.all_finished(), " in ", main.R.round, " turni, ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	quit()
