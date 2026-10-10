## Motore delle regole, indipendente dalla grafica.
class_name Rules
extends RefCounted

const DECK_P := [3, 4, 5, 6, 7]
const DECK_V := [2, 3, 4, 5, 9]
const TEAM_NAMES := ["Rossi", "Blu", "Verdi", "Neri", "Rosa", "Bianchi"]
const TEAM_COLORS := [Color("#C8323C"), Color("#2856B8"), Color("#2E8B4A"), Color("#2B2B2B"), Color("#E37DAE"), Color("#EFEFEA")]
const TEAM_TEXT := [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Color("#1C2938"), Color("#1C2938")]
## Tipi di squadra: giocatore, computer, e le squadre automatiche di Peloton.
const KINDS := ["human", "cpu", "peloton", "muscle"]
const MUSCLE_CARD := 5

var track: Track
var teams: Array = []     # [{name, color, human, riders:[]}]
var riders: Array = []    # [{id, team, type "P"/"V", pos, lane, deck, recycled, hand, chosen}]
var round := 0
var rng := RandomNumberGenerator.new()
var ai_rng := RandomNumberGenerator.new()   # solo per le scelte della CPU: non tocca il caso della corsa

## kinds: per ogni squadra "human", "cpu", "peloton" o "muscle".
## extra_exh: carte fatica iniziali per le squadre di giocatori (handicap o solitario).
## seed: con lo stesso seme (e le stesse scelte) la corsa è identica su ogni dispositivo (gioco online).
func setup(t: Track, kinds: Array, extra_exh := 0, random_start := true, carry: Array = [], seed := 0) -> void:
	track = t
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	ai_rng.randomize()
	var base := rng.randi()
	teams.clear()
	riders.clear()
	for i in kinds.size():
		var kind: String = kinds[i]
		var team := {"name": TEAM_NAMES[i], "color": TEAM_COLORS[i], "text": TEAM_TEXT[i],
			"kind": kind, "human": kind == "human", "riders": [], "idx": i, "deck": []}
		var tg := RandomNumberGenerator.new()
		tg.seed = base + 104729 * (i + 1)
		team["rng"] = tg
		for typ in ["P", "V"]:
			var r := {"id": riders.size(), "team": team, "type": typ, "pos": -1, "lane": 0,
				"deck": _make_deck(typ), "recycled": [], "hand": [], "chosen": {},
				"finished": false, "fin_round": 0, "fin_over": 0, "fin_lane": 0, "fin_place": 0,
				"min": 0, "sec": 0, "tp": 0, "sprint": 0, "mountain": 0, "gone": false, "crashed": false}
			# ogni mazzo si rimescola con il suo generatore: le pescate non dipendono dall'ordine in cui avvengono
			var g := RandomNumberGenerator.new()
			g.seed = base + 7919 * (r["id"] + 1)
			r["rng"] = g
			team["riders"].append(r)
			riders.append(r)
		if kind == "peloton":
			# solo il mazzo del rouleur, con due carte Attacco!
			var d := _make_deck("P")
			d.append({"v": 2, "ex": false, "attack": true})
			d.append({"v": 2, "ex": false, "attack": true})
			_shuffle(d)
			team["deck"] = d
		elif kind == "muscle":
			team["riders"][1]["deck"].append({"v": MUSCLE_CARD, "ex": false, "muscle": true})
			_shuffle(team["riders"][1]["deck"])
		elif kind == "human" and extra_exh > 0:
			for k in extra_exh:
				team["riders"][k % 2]["recycled"].append({"v": 2, "ex": true})
		teams.append(team)
	# fatica portata dalla tappa precedente (tour)
	for i in mini(carry.size(), riders.size()):
		if not is_dummy(riders[i]):
			for k in int(carry[i]):
				riders[i]["recycled"].append({"v": 2, "ex": true})
	# le squadre automatiche si schierano per prime: Peloton, poi Muscle
	for kind in ["peloton", "muscle"]:
		for team in teams:
			if team["kind"] == kind:
				# uno davanti all'altro, il più avanti possibile (Muscle: lo sprinteur davanti)
				var order: Array = team["riders"] if kind == "peloton" else [team["riders"][1], team["riders"][0]]
				var p0 := front_slot()
				place_start(order[0], p0)
				var p1 := -1
				for q in range(p0 - 1, -1, -1):
					if count_at(q) < track.cap(q):
						p1 = q
						break
				place_start(order[1], p1 if p1 >= 0 else front_slot())
	if random_start:
		var rest: Array = []
		for r in riders:
			if r["pos"] < 0:
				rest.append(r)
		_shuffle(rest)
		for r in rest:
			place_start(r, front_slot())

func is_dummy(r: Dictionary) -> bool:
	return r["team"]["kind"] in ["peloton", "muscle"]

func start_capacity() -> int:
	var n := 0
	for p in track.start_count:
		n += track.cap(p)
	return n

## Casella di partenza libera più avanzata (-1 se piene).
func front_slot() -> int:
	for p in range(track.start_count - 1, -1, -1):
		if count_at(p) < track.cap(p):
			return p
	return -1

func free_start_squares() -> Array:
	var out: Array = []
	for p in track.start_count:
		if count_at(p) < track.cap(p):
			out.append(p)
	return out

func place_start(r: Dictionary, p: int) -> void:
	r["lane"] = first_lane(p, r)
	r["pos"] = p

## Schieramento del computer: la casella libera più avanzata.
func ai_start_square(_r: Dictionary) -> int:
	return front_slot()

func _make_deck_with(typ: String, g: RandomNumberGenerator) -> Array:
	var d: Array = []
	for k in 3:
		for v in (DECK_P if typ == "P" else DECK_V):
			d.append({"v": v, "ex": false})
	_shuffle(d, g)
	return d

func _make_deck(typ: String) -> Array:
	var d: Array = []
	for k in 3:
		for v in (DECK_P if typ == "P" else DECK_V):
			d.append({"v": v, "ex": false})
	_shuffle(d)
	return d

func _shuffle(a: Array, g: RandomNumberGenerator = null) -> void:
	if g == null:
		g = rng
	for i in range(a.size() - 1, 0, -1):
		var j := g.randi() % (i + 1)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp

static func rider_name(r: Dictionary) -> String:
	return ("Rouleur " if r["type"] == "P" else "Sprinteur ") + r["team"]["name"]

## Nome del ruolo e lettera sulla basetta e sulle carte (R = rouleur, S = sprinteur).
static func role(r: Dictionary) -> String:
	return "Rouleur" if r["type"] == "P" else "Sprinteur"

static func letter(r: Dictionary) -> String:
	return "R" if r["type"] == "P" else "S"

func exh_count(r: Dictionary) -> int:
	var n := 0
	for c in r["deck"] + r["recycled"]:
		if c["ex"]:
			n += 1
	return n

func dist_to_finish(r: Dictionary) -> int:
	if r["pos"] < 0:
		return 0
	return track.togo[r["pos"]] if r["pos"] < track.togo.size() else 0

# ---------- carte ----------

func draw_hand(r: Dictionary) -> Array:
	var h: Array = []
	var want := 4
	match weather_at(r["pos"]):
		"favore":
			want = 5
		"contrario":
			want = 3
	while h.size() < want:
		if r["deck"].is_empty():
			if r["recycled"].is_empty():
				break
			r["deck"] = r["recycled"]
			r["recycled"] = []
			_shuffle(r["deck"], r["rng"])
		h.append(r["deck"].pop_back())
	if h.is_empty():
		h.append({"v": 2, "ex": true})
	r["hand"] = h
	return h

func choose(r: Dictionary, card: Dictionary) -> void:
	var h: Array = r["hand"]
	h.erase(card)
	r["ct"] = round
	if not card.get("ex", false):
		if not r.has("played"):
			r["played"] = []
		r["played"].append(card)
	r["recycled"].append_array(h)
	r["hand"] = []
	r["chosen"] = card

# ---------- movimento ----------

## Movimento effettivo di una carta, con salite, discese e rifornimento.
func eff_move(r: Dictionary, v: int) -> int:
	var p: int = r["pos"]
	var t0 := track.terrain(p)
	var m := v
	if t0 == "down":
		m = maxi(m, 5)
	if t0 == "supply":
		m = maxi(m, 4)
	if t0 == "up":
		return mini(m, 5)
	if m <= 5:
		return m
	# con più di 5: si avanza in pianura fino all'ultima casella prima della salita
	var path := track.walk(p, m, _pref(r))
	for k in path.size():
		if track.terrain(path[k]) == "up":
			return maxi(k, 5)
	return m

# ---------- tappe speciali: cronometro a squadre ("ttt") e individuale ("itt") ----------

var tt := ""          # "", "ttt", "itt"
var _ctx = null       # corridore dal cui punto di vista si guarda la pista

## Nelle cronometro le altre squadre (o, nell'individuale, tutti gli altri) non contano.
func _sees(o: Dictionary) -> bool:
	if tt == "" or _ctx == null:
		return true
	if tt == "ttt":
		return o["team"] == _ctx["team"]
	return o == _ctx

func count_at(p: int, except: Dictionary = {}) -> int:
	var n := 0
	for r in riders:
		if r != except and r["pos"] == p and _sees(r):
			n += 1
	return n

func occupied(p: int) -> bool:
	for r in riders:
		if r["pos"] == p and _sees(r):
			return true
	return false

func first_lane(p: int, except: Dictionary) -> int:
	for l in track.cap(p):
		var used := false
		for r in riders:
			if r != except and r["pos"] == p and r["lane"] == l and _sees(r):
				used = true
		if not used:
			return l
	return 0

## Corsia preferita: chi è già su una corsia della rotonda la mantiene, gli altri tentano l'interna.
func _pref(r: Dictionary) -> String:
	var b := track.branch(r["pos"])
	return b if b != "" else "inner"

## Dove arriverebbe il corridore lungo una corsia (senza muoverlo).
func _land_on(r: Dictionary, m: int, pref: String) -> Dictionary:
	var from: int = r["pos"]
	var path := track.walk(from, m, pref)
	var want := m
	var n := path.size()
	for k in n:
		if _blocked_by_crash(path[k]):
			n = k
			break
	while n > 0 and count_at(path[n - 1], r) >= track.cap(path[n - 1]):
		n -= 1
	var to: int = path[n - 1] if n > 0 else from
	return {"pos": to, "lost": want - n, "path": path.slice(0, n), "pref": pref}

## Dove arriverebbe il corridore con un dato movimento. Sulle rotonde (Grand Tour): si deve
## muovere esattamente quanto la carta, preferendo la corsia interna; se non si può, si sceglie
## la corsia che fa avanzare di più (a parità, l'interna).
func landing(r: Dictionary, m: int) -> Dictionary:
	var old = _ctx
	_ctx = r
	var res := _landing(r, m)
	_ctx = old
	return res

func _landing(r: Dictionary, m: int) -> Dictionary:
	var a := _land_on(r, m, _pref(r))
	if track.branch(r["pos"]) != "":
		return a
	var b := _land_on(r, m, "outer")
	if a["path"] == b["path"]:
		return a
	if a["lost"] == 0:
		return a
	if b["lost"] == 0:
		return b
	return a if a["lost"] <= b["lost"] else b

## Curva stretta: una casella con tutte le corsie occupate da corridori a terra non si attraversa.
func _blocked_by_crash(p: int) -> bool:
	var n := 0
	for o in riders:
		if o["pos"] == p and o["crashed"] and _sees(o):
			n += 1
	return n > 0 and n >= track.cap(p)

func _has_crash(p: int) -> bool:
	for o in riders:
		if o["pos"] == p and o["crashed"] and _sees(o):
			return true
	return false

func is_wet(p: int) -> bool:
	return p >= 0 and p < track.size() and (track.squares[p].get("wet", false) or weather_at(p) == "bagnato")

## Vero se a è davanti a b (a parità di casella, la corsia più a destra).
func ahead(a: Dictionary, b: Dictionary) -> bool:
	var pa := track.prog(a["pos"])
	var pb := track.prog(b["pos"])
	return pa > pb or (pa == pb and a["lane"] < b["lane"])

func movement_order() -> Array:
	var o := on_track()
	o.sort_custom(ahead)
	return o

## Muove un corridore secondo la carta scelta; restituisce un riassunto.
func move_rider(r: Dictionary) -> Dictionary:
	var v: int = r["chosen"]["v"]
	var stood := false
	var m := eff_move(r, v)
	if r["crashed"]:
		# si rialza: 2 in meno, dopo gli aggiustamenti di discesa e rifornimento;
		# in salita resta il limite di 5 (serve almeno un 7 per farne 5)
		r["crashed"] = false
		stood = true
		if track.terrain(r["pos"]) == "up":
			m = mini(v - 2, 5)
		else:
			m = maxi(0, m - 2)
		m = maxi(0, m)
	var from: int = r["pos"]
	var land := landing(r, m)
	var old = _ctx
	_ctx = r
	r["lane"] = first_lane(land["pos"], r)
	_ctx = old
	r["pos"] = land["pos"]
	var path: Array = land["path"]
	var crash: bool = land["lost"] >= 1 and is_wet(land["pos"])
	if crash:
		r["crashed"] = true
	return {"rider": r, "from": from, "to": r["pos"], "card": r["chosen"]["v"], "eff": m, "lost": land["lost"], "crash": crash, "stood": stood, "path": path}

# ---------- scia e fatica ----------

func on_track() -> Array:
	return riders.filter(func(r): return not r["finished"] and r["pos"] >= 0)

func _groups() -> Array:
	var ps: Array = []
	for r in on_track():
		if not ps.has(r["pos"]):
			ps.append(r["pos"])
	ps.sort()
	var gs: Array = []
	for p in ps:
		# una casella con un corridore a terra fa gruppo a sé: non dà e non riceve scia
		if not gs.is_empty() and gs[-1][1] == p - 1 and not _has_crash(p) and not _has_crash(p - 1):
			gs[-1][1] = p
		else:
			gs.append([p, p])
	return gs

func _no_slip(t: String) -> bool:
	return t == "up" or t == "cobble"

func _compact(p: int) -> void:
	var here: Array = []
	for r in riders:
		if r["pos"] == p and _sees(r):
			here.append(r)
	here.sort_custom(func(a, b): return a["lane"] < b["lane"])
	for i in here.size():
		here[i]["lane"] = i

## Applica la scia; restituisce i corridori spostati.
func slipstream() -> Array:
	if tt == "itt":
		return []
	if tt == "ttt":
		var all: Array = []
		for t in teams:
			_ctx = t["riders"][0]
			all.append_array(_slipstream_all())
		_ctx = null
		return all
	return _slipstream_all()

func _slipstream_all() -> Array:
	var moved: Array = []
	var ls: Array = track.lines.duplicate() if not track.lines.is_empty() else [range(track.size())]
	# prima i percorsi interni: chi è sull'ultima casella a due corsie la risolve prima lì
	ls.sort_custom(func(x, y): return _outer_count(x) < _outer_count(y))
	var done_before: Array = []
	for L in ls:
		var here_moved := _slip_line(L, done_before)
		for r in here_moved:
			if not moved.has(r):
				moved.append(r)
		done_before.append_array(here_moved)
	return moved

func _outer_count(L: Array) -> int:
	var n := 0
	for q in L:
		if track.branch(q) == "outer":
			n += 1
	return n

## Scia lungo un percorso lineare L (indici di caselle). Chi ha già preso la scia su un altro
## percorso della rotonda non la riprende qui.
func _slip_line(L: Array, skip: Array) -> Array:
	var moved: Array = []
	var at := {}
	for j in L.size():
		at[L[j]] = j
	var gs := _groups_on(L, at)
	var i := 0
	while i < gs.size() - 1:
		var g: Array = gs[i]
		var nx: Array = gs[i + 1]
		var blocked := _no_slip(track.terrain(L[nx[0]])) or _has_crash(L[nx[0]]) or weather_at(L[nx[0]]) == "laterale"
		for j in range(g[0], mini(g[1] + 2, L.size())):
			if _no_slip(track.terrain(L[j])) or _has_crash(L[j]) or weather_at(L[j]) == "laterale":
				blocked = true
		var progressed := false
		if nx[0] == g[1] + 2 and not blocked:
			for j in range(g[1], g[0] - 1, -1):
				var q: int = L[j]
				var q1: int = L[j + 1]
				var free := track.cap(q1) - count_at(q1)
				var here: Array = []
				for r in riders:
					if r["pos"] == q and not r["finished"] and not skip.has(r) and _sees(r):
						here.append(r)
				here.sort_custom(func(a, b): return a["lane"] < b["lane"])
				for r in here:
					if free > 0:
						r["pos"] = q1
						r["lane"] = 99
						free -= 1
						progressed = true
						if not moved.has(r):
							moved.append(r)
				_compact(q1)
				_compact(q)
			gs = _groups_on(L, at)
		if not progressed:
			i += 1
	return moved

func _groups_on(L: Array, at: Dictionary) -> Array:
	var ps: Array = []
	for r in on_track():
		if at.has(r["pos"]) and not ps.has(at[r["pos"]]) and _sees(r):
			ps.append(at[r["pos"]])
	ps.sort()
	var gs: Array = []
	for j in ps:
		# una casella con un corridore a terra fa gruppo a sé: non dà e non riceve scia
		if not gs.is_empty() and gs[-1][1] == j - 1 and not _has_crash(L[j]) and not _has_crash(L[j - 1]):
			gs[-1][1] = j
		else:
			gs.append([j, j])
	return gs

func _two_ahead(p: int) -> bool:
	for q in track.next_of(p):
		if not occupied(q):
			for q2 in track.next_of(q):
				if occupied(q2):
					return true
	return false

## Vero se c'è qualcuno nella casella (o in una delle caselle) subito davanti.
func front_occupied(p: int) -> bool:
	for q in track.next_of(p):
		if occupied(q):
			return true
	return false

## Carte fatica a chi ha la casella davanti vuota.
func exhaustion() -> Array:
	var tired: Array = []
	if tt == "itt":
		# cronometro individuale: la prendono il rouleur e lo sprinteur che hanno giocato la carta più alta
		for typ in ["P", "V"]:
			var same := on_track().filter(func(o): return o["type"] == typ and not o["chosen"].is_empty())
			var top := 0
			for o in same:
				top = maxi(top, int(o["chosen"]["v"]))
			for o in same:
				if int(o["chosen"]["v"]) == top:
					tired.append(o)
	else:
		for r in on_track():
			_ctx = r
			if not front_occupied(r["pos"]) and not is_dummy(r):
				tired.append(r)
		_ctx = null
	for r in tired:
		r["recycled"].append({"v": 2, "ex": true})
	return tired

# ---------- tappa lunga: gettone di recupero ----------

var refresh_sq := -1
var refresh_holder = null

## Prima casella di un rettilineo da 6 a metà tappa (meglio se un rifornimento).
func place_refresh() -> void:
	var mid: float = (track.start_count + track.finish) / 2.0
	var best := -1
	var best_score := 1e9
	for i in range(1, track.pieces.size() - 1):
		var pc: Dictionary = track.pieces[i]
		var f := FacesDB.face(pc["id"])
		if f["kind"] != "straight" or f["cells"].size() != 6:
			continue
		var s0: int = pc["s0"]
		var sc := absf(s0 - mid) - (6.0 if track.terrain(s0) == "supply" else 0.0)
		if sc < best_score:
			best_score = sc
			best = s0
	refresh_sq = best

## Fine turno: il primo che raggiunge o supera il gettone lo prende e scatta il recupero.
## Ogni corridore riprende carte giocate fino a 24 punti (25 per chi ha il gettone), poi rimescola.
func check_refresh() -> Array:
	if refresh_sq < 0 or refresh_holder != null:
		return []
	var past := riders.filter(func(o): return not o["gone"] and o["pos"] >= 0 and track.prog(o["pos"]) >= track.prog(refresh_sq))
	if past.is_empty():
		return []
	past.sort_custom(ahead)
	refresh_holder = past[0]
	var out: Array = []
	for r in riders:
		if is_dummy(r):
			continue
		var cap := 24 + (1 if r == refresh_holder else 0)
		var got := _best_subset(r.get("played", []), cap)
		for c in got:
			r["played"].erase(c)
		r["deck"].append_array(got)
		r["deck"].append_array(r["recycled"])
		r["recycled"] = []
		_shuffle(r["deck"], r["rng"])
		var tot := 0
		for c in got:
			tot += int(c["v"])
		out.append({"rider": r, "cards": got.map(func(c): return int(c["v"])), "total": tot})
	return out

## Sottoinsieme di carte con la somma più alta che non supera il limite.
func _best_subset(cards: Array, cap: int) -> Array:
	var best := {0: []}
	for c in cards:
		var add := {}
		for tot in best:
			var nt: int = tot + int(c["v"])
			if nt <= cap and not best.has(nt) and not add.has(nt):
				add[nt] = best[tot] + [c]
		best.merge(add)
	var top := 0
	for k in best:
		top = maxi(top, k)
	return best[top]

# ---------- Meteo ----------

var weather := {}        # indice di casella -> "laterale", "favore", "contrario", "bagnato"
var weather_tiles: Array = []   # [{piece, kind}] per la plancia e la cronaca

## Distribuisce i 13 gettoni (4 condizioni e 9 di bel tempo) ai rettilinei, esclusi partenza e arrivo.
func deal_weather() -> void:
	weather = {}
	weather_tiles = []
	var tokens: Array = ["laterale", "favore", "contrario", "bagnato"]
	for k in 9:
		tokens.append("")
	_shuffle(tokens)
	var n := track.pieces.size()
	for i in range(1, n - 1):
		var f := FacesDB.face(track.pieces[i]["id"])
		if f["kind"] != "straight" or tokens.is_empty():
			continue
		var w: String = tokens.pop_back()
		if w == "":
			continue
		weather_tiles.append({"piece": i, "kind": w})
		var s0: int = track.pieces[i]["s0"]
		for q in range(s0, s0 + f["cells"].size()):
			weather[q] = w

func weather_at(p: int) -> String:
	return weather.get(p, "")

# ---------- variante Breakaway (Peloton) ----------

## Indice della prima casella della tessera della fuga (la 2), se è la seconda del percorso.
func breakaway_square() -> int:
	if track.pieces.size() < 2:
		return -1
	var id: String = track.pieces[1]["id"]
	if id != "2" and id != "2B":
		return -1
	return int(track.pieces[1]["s0"]) + 3     # quarta casella della tessera: la zona tratteggiata

## Offerta della CPU: punta forte nella prima offerta se ha una carta alta, poi decide se insistere.
func ai_bid(r: Dictionary, round_k: int, so_far: int) -> Dictionary:
	var hand: Array = r["hand"].duplicate()
	hand.sort_custom(func(a, b): return a["v"] > b["v"])
	if round_k == 0:
		return hand[0] if hand[0]["v"] >= 6 or ai_rng.randf() < 0.5 else hand[hand.size() / 2]
	return hand[0] if so_far >= 6 else hand[-1]

## Risolve l'asta: bids = [{rider, cards:[c, c]}]. Restituisce i vincitori nell'ordine di piazzamento.
func resolve_breakaway(bids: Array, winners_n: int) -> Array:
	var sq := breakaway_square()
	var ordered := bids.duplicate()
	ordered.sort_custom(func(a, b):
		var ta: int = a["cards"][0]["v"] + a["cards"][1]["v"]
		var tb: int = b["cards"][0]["v"] + b["cards"][1]["v"]
		if ta != tb:
			return ta > tb
		# parità: vince il più arretrato (e, nella stessa casella, il più a sinistra)
		var ra: Dictionary = a["rider"]
		var rb: Dictionary = b["rider"]
		return ahead(rb, ra))
	var winners: Array = []
	for i in mini(winners_n, ordered.size()):
		winners.append(ordered[i]["rider"])
	for i in winners.size():
		var r: Dictionary = winners[i]
		r["pos"] = sq
		r["lane"] = i                       # chi ha offerto di più prende la corsia destra
	for b in bids:
		var r: Dictionary = b["rider"]
		if winners.has(r):
			for k in 2:
				r["recycled"].append({"v": 2, "ex": true})
		else:
			r["recycled"].append_array(b["cards"])
	for r in riders:
		r["deck"].append_array(r["recycled"])
		r["recycled"] = []
		_shuffle(r["deck"], r["rng"])
	return winners

# ---------- gioco online: scelte codificate ----------

## Codice di una carta scelta: valore, +100 se è una carta fatica.
static func card_code(c: Dictionary) -> int:
	return int(c["v"]) + (100 if c.get("ex", false) else 0)

## Scelta di una squadra da pubblicare: {tipo corridore: codice carta}.
func team_choice(t: Dictionary) -> Dictionary:
	var out := {}
	for r in t["riders"]:
		if not r["finished"] and int(r.get("ct", -1)) == round:
			out[r["type"]] = card_code(r["chosen"])
	return out

## Applica la scelta ricevuta da un altro dispositivo: si pesca la stessa mano (i mazzi sono identici)
## e si gioca la carta con quel codice. Restituisce false se la carta non è nella mano (fuori sincronia).
func apply_choice(t: Dictionary, choice: Dictionary) -> bool:
	var ok := true
	for r in t["riders"]:
		if r["finished"] or int(r.get("ct", -1)) == round:
			continue
		if not choice.has(r["type"]):
			ok = false
			continue
		draw_hand(r)
		var code := int(choice[r["type"]])
		var pick: Dictionary = {}
		for c in r["hand"]:
			if card_code(c) == code:
				pick = c
				break
		if pick.is_empty():
			ok = false
			pick = r["hand"][0]
		choose(r, pick)
	return ok

## Impronta dello stato della corsa, per controllare che i dispositivi siano allineati.
func state_hash() -> int:
	var parts: Array = [round]
	for r in riders:
		parts.append([r["pos"], r["lane"], r["finished"], r["deck"].map(card_code), r["recycled"].map(card_code)])
	return hash(str(parts))

## Carte delle squadre automatiche (dopo che i giocatori hanno scelto).
func dummy_cards() -> void:
	for team in teams:
		if team["kind"] == "peloton":
			if team["deck"].is_empty():
				var d := _make_deck_with("P", team["rng"])
				team["deck"] = d
			var c: Dictionary = team["deck"].pop_back()
			var a: Dictionary = team["riders"][0]
			var b: Dictionary = team["riders"][1]
			if c.get("attack", false):
				var front := a if ahead(a, b) else b
				var back := b if front == a else a
				front["chosen"] = {"v": 2, "ex": false, "attack": true}
				back["chosen"] = {"v": 9, "ex": false, "attack": true}
			else:
				a["chosen"] = c
				b["chosen"] = c
		elif team["kind"] == "muscle":
			for r in team["riders"]:
				r["chosen"] = r["deck"].pop_back() if not r["deck"].is_empty() else {"v": 2, "ex": true}

## Primo arrivo: la tappa ha un vincitore (si continua finché arrivano tutti).
func finished() -> bool:
	for r in riders:
		if r["finished"]:
			return true
	return false

func all_finished() -> bool:
	for r in riders:
		if not r["finished"]:
			return false
	return true

func active(team: Dictionary) -> Array:
	return team["riders"].filter(func(r): return not r["finished"])

# ---------- fine tappa secondo il regolamento del Grand Tour ----------

const PODIUM_TP := [3, 2, 1]

## Fine turno, passo 2–3 e premi di podio: chi ha superato il traguardo è "arrivato" (resta in pista
## finché non si assegna la fatica). I secondi vengono dalla tavola dei tempi: quelli della casella
## del corridore più avanzato del suo gruppo.
func record_finishers() -> Array:
	var done := on_track().filter(func(r): return track.prog(r["pos"]) > track.prog(track.finish))
	if done.is_empty():
		return []
	done.sort_custom(ahead)
	var placed := 0
	for r in riders:
		if r["finished"]:
			placed += 1
	for r in done:
		placed += 1
		r["finished"] = true
		r["fin_round"] = round
		r["fin_over"] = int(track.prog(r["pos"]) - track.prog(track.finish))
		r["fin_lane"] = r["lane"]
		r["fin_place"] = placed
		_ctx = r
		r["sec"] = timing_seconds(int(track.prog(_pack_front(r["pos"])) - track.prog(track.finish)))
		_ctx = null
		if tt != "":
			if podium_given < PODIUM_TP.size() and not podium_teams.has(r["team"]["idx"]):
				r["tp"] += PODIUM_TP[podium_given]
				podium_given += 1
				podium_teams.append(r["team"]["idx"])
		elif placed <= PODIUM_TP.size():
			r["tp"] += PODIUM_TP[placed - 1]
	return done

## Casella del corridore più avanzato del gruppo (caselle occupate contigue) in cui si trova pos.
func _pack_front(pos: int) -> int:
	var p := pos
	var guard := 0
	while front_occupied(p) and guard < 50:
		guard += 1
		for q in track.next_of(p):
			if occupied(q):
				p = q
				break
	return p

## Tavola dei tempi del Grand Tour: secondi per la k-esima casella dopo la linea d'arrivo.
## Faccia in pianura (sei valori, +1:00 compreso): 40, 30, 20, 10, 0.
## Faccia in salita (cinque valori): 30, 20, 10, 0. Dall'ultima casella in poi vale 0.
const TIMING_FLAT := [40, 30, 20, 10, 0]
const TIMING_ASCENT := [30, 20, 10, 0]

func timing_seconds(k: int) -> int:
	var after := track.finish + 1
	var tbl: Array = TIMING_ASCENT if after < track.size() and track.terrain(after) == "up" else TIMING_FLAT
	return tbl[clampi(k - 1, 0, tbl.size() - 1)]

## Passo 4: da quando qualcuno è arrivato, chi non ha ancora tagliato il traguardo prende un minuto.
func add_time_tokens() -> void:
	if not finished():
		return
	for r in riders:
		if not r["finished"]:
			r["min"] += 1

## Passo 6: gli arrivati escono dalla pista (dopo l'assegnazione della fatica).
func remove_finished() -> Array:
	var out: Array = []
	for r in riders:
		if r["finished"] and not r["gone"]:
			r["gone"] = true
			r["pos"] = -100
			out.append(r)
	return out

## Ordine d'arrivo: chi è più avanti al traguardo, a parità la corsia destra.
func ranking() -> Array:
	var fin := riders.filter(func(r): return r["finished"])
	fin.sort_custom(func(a, b): return a["fin_place"] < b["fin_place"])
	var rest := on_track()
	rest.sort_custom(ahead)
	return fin + rest

var podium_given := 0
var podium_teams: Array = []

func stage_time(r: Dictionary) -> int:
	if tt == "ttt":
		# cronometro a squadre: entrambi prendono il tempo del più lento
		var worst := 0
		for o in r["team"]["riders"]:
			worst = maxi(worst, int(o["min"]) * 60 + int(o["sec"]))
		return worst
	return int(r["min"]) * 60 + int(r["sec"])

# ---------- traguardi volanti e di montagna (gettoni Major e Minor) ----------

var piles: Array = []     # {sq, major, mountain, values, taken}

## Posizione dei gettoni secondo le regole "Designing Stages" del Grand Tour.
func place_tokens() -> void:
	piles = []
	var runs: Array = []      # salite continue: [lunghezza, ultima casella]
	var i := 0
	var n := track.size()
	while i < n:
		if track.terrain(i) == "up":
			var j := i
			while j + 1 < n and track.terrain(j + 1) == "up":
				j += 1
			runs.append([j - i + 1, j])
			i = j + 1
		else:
			i += 1
	var after_finish: int = track.finish + 1
	# la salita più lunga (a parità, la più vicina all'arrivo)
	runs.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	var major_sq := after_finish
	var major_mount := false
	var used_run := -1
	if not runs.is_empty() and runs[0][0] >= 5:
		major_mount = true
		used_run = 0
		major_sq = mini(int(runs[0][1]) + 1, after_finish) if runs[0][1] < track.finish else after_finish
	piles.append({"sq": major_sq, "major": true, "mountain": major_mount, "values": [5, 3, 1], "taken": []})
	if major_sq != after_finish:
		piles.append({"sq": after_finish, "major": false, "mountain": false, "values": [2, 1], "taken": []})
	else:
		var rest: Array = []
		for k in runs.size():
			if k != used_run and runs[k][1] < track.finish:
				rest.append(runs[k])
		if not rest.is_empty():
			piles.append({"sq": int(rest[0][1]) + 1, "major": false, "mountain": true, "values": [2, 1], "taken": []})
		else:
			# niente salite: sprint a metà tappa, sulla prima casella di una tessera da 6
			var target: int = (track.start_count + track.finish) / 2
			var best := target
			var best_d := 999
			for p in track.pieces:
				if FacesDB.face(p["id"])["cells"].size() == 6 and absi(int(p["s0"]) - target) < best_d:
					best_d = absi(int(p["s0"]) - target)
					best = int(p["s0"])
			piles.append({"sq": best, "major": false, "mountain": false, "values": [2, 1], "taken": []})

## A fine turno: chi ha raggiunto o superato un mucchietto prende un gettone (il più avanzato il più alto).
func collect_tokens() -> Array:
	var got: Array = []
	for pl in piles:
		var who := riders.filter(func(r): return not r["gone"] and r["pos"] >= 0 and track.prog(r["pos"]) >= track.prog(pl["sq"]) and not pl["taken"].has(r["id"]))
		who.sort_custom(ahead)
		for r in who:
			if pl["values"].is_empty():
				break
			var v: int = pl["values"].pop_front()
			pl["taken"].append(r["id"])
			if pl["mountain"]:
				r["mountain"] += v
			else:
				r["sprint"] += v
			got.append({"rider": r, "v": v, "mountain": pl["mountain"], "major": pl["major"]})
	return got

## Carte fatica che passano alla tappa successiva (metà, arrotondata per difetto).
func carry_exhaustion(r: Dictionary) -> int:
	return exh_count(r) / 2

# ---------- computer ----------

## CPU: valuta ogni carta per avanzamento, posizione dopo la mossa ed economia del mazzo.
func ai_pick(r: Dictionary) -> Dictionary:
	if _sim and sim_fast:
		return _fast_pick(r)
	if int(r["team"].get("level", 1)) >= 2 and not _sim:
		return _mc_pick(r)
	var old = _ctx
	_ctx = r
	var c := _ai_pick(r)
	_ctx = old
	return c

# ---------- CPU difficile: simulazione dei finali possibili (Monte Carlo) ----------
# Per ogni carta in mano si giocano in testa molti finali, fino al traguardo: gli avversari pescano
# a caso dalle carte che hanno davvero ancora (l'ordine dei mazzi è sconosciuto) e giocano con la
# CPU normale. Vince la carta che in media porta il miglior piazzamento della squadra.

var _sim := false
var sim_fast := true       # nei finali simulati gli altri giocano con una versione rapida della CPU
var mc_prune := true       # scarta presto le carte nettamente peggiori

## CPU rapida per i finali simulati: stessi criteri della CPU normale, senza calcolare le strade chiuse.
func _fast_pick(r: Dictionary) -> Dictionary:
	var d := dist_to_finish(r)
	var sprinter: bool = r["type"] == "V"
	var sheltered := front_occupied(r["pos"])
	var up: bool = track.terrain(r["pos"]) == "up"
	var best := {}
	var best_s := -1e9
	for c in r["hand"]:
		var v: int = c["v"]
		var m := v
		if up:
			m = mini(v, 5)
		elif v > 5 and d > 9:
			m = eff_move(r, v)
		var s := float(m)
		if m >= d:
			s = 100.0 + m
		else:
			if c["ex"]:
				s += 1.5 + (2.0 if sheltered or up else 0.0)
			elif sprinter and v == 9 and d > 18:
				s -= 4.0
			elif v >= 6 and d > 25:
				s -= (v - 5) * 0.6
			s -= (v - m) * 1.0
		s += rng.randf() * 1.5
		if s > best_s:
			best_s = s
			best = c
	return best
var mc_samples := 16       # finali simulati per carta
var mc_max_ms := 900       # tempo massimo per decisione (millisecondi)

const _SNAP_KEYS := ["pos", "lane", "chosen", "finished", "fin_round", "fin_over", "fin_lane", "fin_place",
	"min", "sec", "tp", "crashed", "gone", "ct"]

func _snap() -> Dictionary:
	var rs: Array = []
	for r in riders:
		var d := {}
		for k in _SNAP_KEYS:
			d[k] = r.get(k)
		d["deck"] = r["deck"].duplicate()
		d["recycled"] = r["recycled"].duplicate()
		d["hand"] = r["hand"].duplicate()
		d["played"] = r.get("played", []).duplicate()
		d["rng"] = r["rng"].state
		rs.append(d)
	var td: Array = []
	for t in teams:
		td.append([t["deck"].duplicate(), t["rng"].state])
	return {"r": rs, "t": td, "round": round, "pg": podium_given, "pt": podium_teams.duplicate(), "rh": refresh_holder}

func _restore(S: Dictionary) -> void:
	for i in riders.size():
		var r: Dictionary = riders[i]
		var d: Dictionary = S["r"][i]
		for k in _SNAP_KEYS:
			if d[k] == null:
				r.erase(k)
			else:
				r[k] = d[k]
		r["deck"] = d["deck"].duplicate()
		r["recycled"] = d["recycled"].duplicate()
		r["hand"] = d["hand"].duplicate()
		r["played"] = d["played"].duplicate()
		r["rng"].state = d["rng"]
	for i in teams.size():
		teams[i]["deck"] = S["t"][i][0].duplicate()
		teams[i]["rng"].state = S["t"][i][1]
	round = S["round"]
	podium_given = S["pg"]
	podium_teams = S["pt"].duplicate()
	refresh_holder = S["rh"]

## Valore di un finale per la squadra: piazzamento del corridore migliore (vincere vale molto),
## poi quello del compagno. Chi non è ancora arrivato è ordinato per posizione in pista.
func _mc_value(team: Dictionary) -> float:
	var order := riders.duplicate()
	order.sort_custom(func(a, b):
		if a["finished"] != b["finished"]:
			return a["finished"]
		if a["finished"]:
			return a["fin_place"] < b["fin_place"]
		return ahead(a, b))
	var n := float(order.size())
	var ranks: Array = []
	for r in team["riders"]:
		ranks.append(order.find(r))
	ranks.sort()
	var r0: int = ranks[0]
	var r1: int = ranks[1]
	var v: float = (n - r0) / n + 0.25 * (n - r1) / n
	if r0 == 0:
		v += 1.0
	elif r0 == 1:
		v += 0.35
	return v

## Un turno simulato: chi non ha ancora scelto pesca e sceglie con la CPU normale, poi movimento,
## scia, arrivi, fatica.
func _sim_turn() -> void:
	for r in on_track():
		if is_dummy(r) or int(r.get("ct", -1)) == round:
			continue
		draw_hand(r)
		choose(r, ai_pick(r))
	dummy_cards()
	for r in movement_order():
		move_rider(r)
	slipstream()
	check_refresh()
	record_finishers()
	add_time_tokens()
	exhaustion()
	remove_finished()
	round += 1

func _mc_pick(r: Dictionary) -> Dictionary:
	var hand: Array = r["hand"]
	if hand.size() <= 1:
		return hand[0]
	# carte uguali danno lo stesso risultato: se ne prova una per valore
	var cands: Array = []
	var seen := {}
	for c in hand:
		var key := "%d%s" % [c["v"], "x" if c["ex"] else ""]
		if not seen.has(key):
			seen[key] = true
			cands.append(c)
	if cands.size() == 1:
		return cands[0]
	var S := _snap()
	var rng_state := rng.state
	var base := rng.randi()
	var team: Dictionary = r["team"]
	var score: Array = []
	score.resize(cands.size())
	score.fill(0.0)
	var done := 0
	var alive: Array = range(cands.size())
	var sq: Array = []
	sq.resize(cands.size())
	sq.fill(0.0)
	var t0 := Time.get_ticks_msec()
	_sim = true
	var n_samples: int = int(team.get("samples", mc_samples))
	var budget: int = int(team.get("budget", mc_max_ms))
	for k in n_samples:
		for ci in alive:
			_restore(S)
			rng.seed = base + k * 7919
			# mondo plausibile: l'ordine dei mazzi è sconosciuto
			for o in riders:
				if not o["finished"]:
					_shuffle(o["deck"])
			for t in teams:
				_shuffle(t["deck"])
			var c: Dictionary = cands[ci]
			r["hand"] = hand.duplicate()
			choose(r, c)
			var guard := 0
			while guard < 40:
				guard += 1
				var ours_left := false
				for o in team["riders"]:
					if not o["finished"]:
						ours_left = true
				if not ours_left or all_finished():
					break
				_sim_turn()
			var val := _mc_value(team)
			score[ci] += val
			sq[ci] += val * val
		done += 1
		# scarto delle carte nettamente peggiori (dopo almeno 4 finali)
		if mc_prune and done >= 4 and alive.size() > 1:
			var top := -1e9
			for ci in alive:
				top = maxf(top, score[ci] / done)
			var keep: Array = []
			for ci in alive:
				var m: float = score[ci] / done
				var var_: float = maxf(0.0, sq[ci] / done - m * m)
				if m + 2.0 * sqrt(var_ / done) + 0.05 >= top:
					keep.append(ci)
			alive = keep
			if alive.size() == 1:
				break
		if Time.get_ticks_msec() - t0 > budget and done >= 4:
			break
	_sim = false
	_restore(S)
	rng.state = rng_state
	var best: int = alive[0]
	for ci in alive:
		if score[ci] > score[best]:
			best = ci
	return cands[best]

func _ai_pick(r: Dictionary) -> Dictionary:
	if r["team"].get("ai", "") == "base":
		return _ai_pick_basic(r)
	var d := dist_to_finish(r)
	var sprinter: bool = r["type"] == "V"
	var late := d <= 14
	var head := 0.0
	for o in on_track():
		if o != r:
			head = maxf(head, track.prog(o["pos"]))
	var best := {}
	var best_s := -1e9
	for c in r["hand"]:
		var v: int = c["v"]
		var m := eff_move(r, v)
		var land := landing(r, m)
		var to: int = land["pos"]
		var gain: int = int(track.prog(to) - track.prog(r["pos"]))
		var s := 0.0
		if track.prog(to) > track.prog(track.finish):
			# si può arrivare: conta solo andare il più lontano possibile oltre la linea
			s = 1000.0 + (track.prog(to) - track.prog(track.finish)) * 10.0
		else:
			var w_gain := 1.0
			if late:
				w_gain = 3.0 if sprinter else 1.6
			elif d <= 25:
				w_gain = 1.4
			s = gain * w_gain
			# economia: le carte alte valgono di più nel finale
			if not c["ex"]:
				var keep := 0.0
				if sprinter and v == 9:
					keep = 4.0 if d > 19 else 0.0
				elif v >= 6:
					keep = (v - 5) * (0.6 if d > 25 else 0.25)
				s -= keep
			else:
				# scaricare una fatica costa poco quando si è al riparo o in salita
				s += 1.2
				if track.terrain(r["pos"]) == "up" or front_occupied(to):
					s += 1.5
			# carte sprecate dal limite in salita
			if m < v and not c["ex"]:
				s -= (v - m) * 0.9
			# strada chiusa: caselle perse (e sul bagnato si cade)
			s -= land["lost"] * 0.6
			if land["lost"] >= 1 and is_wet(to):
				s -= 5.0
			# dove si finisce: a ruota, pronti per la scia, o scoperti davanti
			var t_here := track.terrain(to)
			# lo sprinteur vive a ruota e risparmia; il rouleur può tirare
			if front_occupied(to):
				s += 2.0 if sprinter else 0.8
			elif _two_ahead(to) and t_here != "up" and t_here != "cobble":
				s += 1.2 if sprinter else 0.6
			else:
				s -= (1.6 if sprinter else 0.7) if d > 10 else 0.3
			if t_here == "cobble":
				s -= 0.3
			# restare agganciati alla testa della corsa (soprattutto lo sprinteur, per la volata)
			var behind: int = maxi(0, int(head - track.prog(to)) - 1)
			s -= behind * (0.55 if sprinter else 0.3)
		s += ai_rng.randf() * 0.35
		if s > best_s:
			best_s = s
			best = c
	return best

func _ai_pick_basic(r: Dictionary) -> Dictionary:
	var d := dist_to_finish(r)
	var best := {}
	var best_s := -1e9
	for c in r["hand"]:
		var m := eff_move(r, c["v"])
		var land := landing(r, m)
		var gain: int = int(track.prog(land["pos"]) - track.prog(r["pos"]))
		var s := gain + ai_rng.randf() * 1.2
		if track.prog(land["pos"]) > track.prog(track.finish):
			s += 100.0 + gain
		else:
			if r["type"] == "V" and c["v"] == 9 and d > 18:
				s -= 7.0
			if d > 30 and c["v"] >= 7:
				s -= 2.5
			if c["ex"] and d > 12:
				s += 3.0
			if m < c["v"]:
				s -= (c["v"] - m) * 1.2
			var sheltered := front_occupied(land["pos"])
			if sheltered and track.terrain(land["pos"]) != "cobble":
				s += 2.0
			elif not sheltered:
				s -= 1.0
		if s > best_s:
			best_s = s
			best = c
	return best
