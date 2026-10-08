extends SceneTree
## Confronto tra livelli di CPU: metà squadre con il livello A, metà con il livello B.
## Uso: godot --headless --path . -s res://tests/ai_bench.gd -- A B corse campioni
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var la := int(args[0]) if args.size() > 0 else 2
	var lb := int(args[1]) if args.size() > 1 else 1
	var n := int(args[2]) if args.size() > 2 else 20
	var samples := int(args[3]) if args.size() > 3 else 16
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var wins := {la: 0, lb: 0}
	var podium := {la: 0.0, lb: 0.0}
	var dec_ms: Array = []
	var t_all := Time.get_ticks_msec()
	for k in n:
		var seq := TrackGenerator.generate(["media", "lunga"][k % 2], k % 3 == 0, rng, 8)
		var R := Rules.new()
		R.setup(Track.build(seq, false), ["cpu", "cpu", "cpu", "cpu"])
		R.mc_samples = samples
		R.mc_max_ms = 100000
		for i in 4:
			R.teams[i]["level"] = la if (i + k) % 2 == 0 else lb
		while not R.all_finished() and R.round < 150:
			R.round += 1
			for t in R.teams:
				for r in R.active(t):
					R.draw_hand(r)
					var t0 := Time.get_ticks_msec()
					var c := R.ai_pick(r)
					if int(t.get("level", 1)) >= 2:
						dec_ms.append(Time.get_ticks_msec() - t0)
					R.choose(r, c)
			for r in R.movement_order():
				R.move_rider(r)
			R.slipstream()
			R.record_finishers()
			R.add_time_tokens()
			R.exhaustion()
			R.remove_finished()
		var rank := R.ranking()
		wins[int(rank[0]["team"]["level"])] += 1
		for p in 3:
			podium[int(rank[p]["team"]["level"])] += 1
	dec_ms.sort()
	var avg := 0.0
	for x in dec_ms:
		avg += x
	print("livello %d contro %d, %d corse: vittorie %s, posti sul podio %s" % [la, lb, n, wins, podium])
	if not dec_ms.is_empty():
		print("tempo per decisione (livello alto): media %d ms, massimo %d ms; totale %.0f s" % [avg / dec_ms.size(), dec_ms[-1], (Time.get_ticks_msec() - t_all) / 1000.0])
	quit()
