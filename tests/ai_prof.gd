extends SceneTree
func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seq := TrackGenerator.generate("media", false, rng, 8)
	var R := Rules.new()
	R.setup(Track.build(seq, false), ["cpu", "cpu", "cpu", "cpu"])
	var S := R._snap()
	R._sim = true
	var t0 := Time.get_ticks_msec()
	var turns := 0
	for k in 5:
		R._restore(S)
		while not R.all_finished() and turns < 400:
			R._sim_turn()
			turns += 1
	var dt := Time.get_ticks_msec() - t0
	print("5 corse intere simulate: %d ms, %d turni, %.2f ms per turno" % [dt, turns, float(dt) / turns])
	R._restore(S)
	var parts := {"pesca+scelta": 0, "movimento": 0, "scia": 0, "resto": 0}
	for k in 15:
		var a := Time.get_ticks_usec()
		for r in R.on_track():
			R.draw_hand(r)
			R.choose(r, R.ai_pick(r))
		var b := Time.get_ticks_usec()
		for r in R.movement_order():
			R.move_rider(r)
		var c := Time.get_ticks_usec()
		R.slipstream()
		var d := Time.get_ticks_usec()
		R.record_finishers(); R.add_time_tokens(); R.exhaustion(); R.remove_finished(); R.round += 1
		var e := Time.get_ticks_usec()
		parts["pesca+scelta"] += b - a; parts["movimento"] += c - b; parts["scia"] += d - c; parts["resto"] += e - d
	for k2 in parts:
		parts[k2] = parts[k2] / 15000.0
	print("ms per turno: ", parts)
	var t1 := Time.get_ticks_usec()
	for k in 200:
		R._restore(S)
	print("ripristino dello stato: %.3f ms" % ((Time.get_ticks_usec() - t1) / 200000.0))
	quit()
