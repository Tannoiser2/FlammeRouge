extends SceneTree
## Due giochi completi (host e ospite) contro il finto Firebase: avvio con FR_ROLE=host oppure guest.
## Il codice della stanza passa per un file. Alla fine si stampano ordine d'arrivo e impronta dello stato.
func _init() -> void:
	var role := OS.get_environment("FR_ROLE")
	var code_file := OS.get_environment("FR_CODE_FILE")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	main.splash_close.call()
	for i in 20: await process_frame
	main.autoplay = true
	main.cfg["anim"] = 2
	main.online_name.text = "Stefano" if role == "host" else "Marco"
	if role == "host":
		main.cfg["n"] = 4
		main.cfg["kind"] = [0, 0, 1, 2, 1, 1]
		main.cfg["meteo"] = true
		main.cfg["cpu"] = 1
		main.cfg["mode"] = 0
		main._preview()
		await main._online_create()
		var code: String = main.online.get("code", "")
		print("host: stanza ", code)
		var f := FileAccess.open(code_file, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 30000:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await create_timer(0.5).timeout
		await main._online_start()
	else:
		var t0 := Time.get_ticks_msec()
		while not FileAccess.file_exists(code_file) and Time.get_ticks_msec() - t0 < 30000:
			await create_timer(0.3).timeout
		await create_timer(0.5).timeout
		main.online_code.text = FileAccess.get_file_as_string(code_file).strip_edges()
		await main._online_join()
		print("ospite: posto ", main.online.get("seat"))
	Engine.time_scale = 10.0
	var t1 := Time.get_ticks_msec()
	while (main.R == null or not main.report.visible) and Time.get_ticks_msec() - t1 < 240000:
		await process_frame
	Engine.time_scale = 1.0
	if main.R == null:
		print(role, ": la corsa non è partita. ", main.online_lbl.text)
	else:
		print(role, ": conclusa=", main.R.all_finished(), " turni=", main.R.round, " ordine=", main.R.ranking().map(func(r): return Rules.rider_name(r)), " impronta=", main.R.state_hash())
	quit()
