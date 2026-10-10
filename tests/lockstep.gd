extends SceneTree
## Due "dispositivi" giocano la stessa corsa: ognuno sceglie per la sua squadra in un ordine diverso,
## riceve le scelte dell'altro come codici e le applica. Gli stati devono restare identici.
func _run(seq: Array, kinds: Array, seed: int, meteo: bool) -> String:
	var A := Rules.new()
	var B := Rules.new()
	A.setup(Track.build(seq, false), kinds, 0, true, [], seed)
	B.setup(Track.build(seq, false), kinds, 0, true, [], seed)
	for X in [A, B]:
		X.place_tokens()
		if meteo:
			X.deal_weather()
		for t in X.teams:
			if t["kind"] == "cpu":
				t["level"] = 2
				t["samples"] = 4
	if A.state_hash() != B.state_hash():
		return "diversi già alla partenza"
	var rounds := 0
	while not A.all_finished() and A.round < 120:
		A.round += 1
		B.round += 1
		var posts := {}
		# A: squadra 0 (giocatore) e, come host, le squadre del computer
		for t in A.teams:
			if t["idx"] == 0 or t["kind"] == "cpu":
				for r in A.active(t):
					A.draw_hand(r)
					A.choose(r, A.ai_pick(r))
				posts[t["idx"]] = A.team_choice(t)
		# B: squadra 1, scelta in ordine inverso (prima lo sprinteur)
		var tb: Dictionary = B.teams[1]
		var act := B.active(tb)
		act.reverse()
		for r in act:
			B.draw_hand(r)
			B.choose(r, B.ai_pick(r))
		posts[1] = B.team_choice(tb)
		# ognuno applica le scelte degli altri, in ordine di squadra
		for X in [A, B]:
			for t in X.teams:
				if posts.has(t["idx"]):
					if not X.apply_choice(t, posts[t["idx"]]):
						return "carta non trovata al turno %d" % X.round
		for X in [A, B]:
			X.dummy_cards()
			for r in X.movement_order():
				X.move_rider(r)
			X.slipstream()
			X.check_refresh()
			X.collect_tokens()
			X.record_finishers()
			X.add_time_tokens()
			X.exhaustion()
			X.remove_finished()
		if A.state_hash() != B.state_hash():
			return "divergenza al turno %d" % A.round
		rounds += 1
	return "ok, %d turni, vince %s" % [rounds, Rules.rider_name(A.ranking()[0])]

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var ok := 0
	for k in 8:
		var seq := TrackGenerator.generate("media", k % 2 == 0, rng, 8, "", k % 3 == 0)
		var kinds: Array = [["human", "human", "cpu", "peloton"], ["human", "human", "cpu", "muscle"], ["human", "human"], ["human", "human", "cpu"]][k % 4]
		var res := _run(seq, kinds, 1000 + k, k % 2 == 1)
		print("corsa %d (%s): %s" % [k + 1, ", ".join(kinds), res])
		if res.begins_with("ok"):
			ok += 1
	print("corse in sincronia: %d/8" % ok)
	quit()
