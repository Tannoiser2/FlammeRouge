## Generatore di percorsi casuali con le tessere fisiche disponibili:
## ogni tessera si usa una sola volta, su uno dei due lati.
class_name TrackGenerator
extends RefCounted

const BASE_MIDDLE := ["b", "c", "d", "f", "l", "m", "n", "e", "g", "h", "i", "j", "k", "o", "p", "q", "r", "s", "t"]
const PELOTON_MIDDLE := ["2", "3", "4", "5", "6", "7", "8", "9"]
const LENGTHS := {"breve": 10, "media": 14, "lunga": 19, "tutte": 99}

## Le due facce di una tessera fisica, partendo dal lato "chiaro".
static func sides(tile: String) -> Array:
	var a := tile
	var b := tile.to_upper() if tile != tile.to_upper() else tile + "B"
	if FacesDB.face(b).is_empty():
		b = tile + "B"
	return [a, b]

const START_SLOTS := {"a": 10, "A": 8, "1": 12, "1B": 15}

## riders: corridori da schierare; se servono più di 10 posti si usa la partenza di Peloton.
## gt: tessere del Grand Tour (curva stretta bagnata e arrivo largo al posto di u/U).
static func generate(length := "media", peloton := false, rng: RandomNumberGenerator = null, riders := 8, breakaway := "", gt := false) -> Array:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var pool: Array = BASE_MIDDLE.duplicate()
	if peloton:
		pool.append_array(PELOTON_MIDDLE)
	if breakaway != "":
		pool.erase("2")
	if gt:
		pool.append_array(["z", "x", "y"])
	_shuffle(pool, rng)
	var n: int = mini(LENGTHS.get(length, 14), pool.size())
	var chosen: Array = pool.slice(0, n)
	for attempt in 40:
		var starts: Array = []
		for k in START_SLOTS:
			var pel_start: bool = k.begins_with("1")
			if START_SLOTS[k] >= riders and (peloton or not pel_start or riders > 10):
				starts.append(k)
		if starts.is_empty():
			return []
		var seq: Array = [starts[rng.randi() % starts.size()]]
		if breakaway != "":
			seq.append(breakaway)          # variante Breakaway: la tessera della fuga è la seconda
		var budget := [4000]
		var res := _dfs(seq, chosen.duplicate(), rng, budget, "v" if gt else "u")
		if not res.is_empty():
			return res
		_shuffle(chosen, rng)
	return []

static func _dfs(seq: Array, left: Array, rng: RandomNumberGenerator, budget: Array, fin_tile := "u") -> Array:
	budget[0] -= 1
	if budget[0] < 0:
		return []
	if left.is_empty():
		var fins := sides(fin_tile)
		_shuffle(fins, rng)
		for fin in fins:
			var full := seq + [fin]
			var t := Track.build(full, false)
			if t.ok() and not t.last_overlaps():
				return full
		return []
	var order := left.duplicate()
	_shuffle(order, rng)
	for tile in order:
		var ss := sides(tile)
		_shuffle(ss, rng)
		for side in ss:
			var cand := seq + [side]
			var t := Track.build(cand, false)
			# senza arrivo build() segnala un errore, ma la geometria è completa
			if _last_ok(t, cand.size()):
				var rest := left.duplicate()
				rest.erase(tile)
				var r := _dfs(cand, rest, rng, budget, fin_tile)
				if not r.is_empty():
					return r
			if budget[0] < 0:
				return []
	return []

static func _last_ok(t: Track, upto: int) -> bool:
	# controlla il pezzo upto-1 contro i precedenti non adiacenti
	var i := upto - 1
	if i < 2:
		return true
	var mine := t._samples(i)
	for j in range(0, i - 1):
		if Track._too_close(mine, t._samples(j), 1.75):
			return false
	return true

static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp

## Interpreta una sequenza scritta a mano: "a b c ... u" (separatori spazio, virgola, trattino).
static func parse(text: String) -> Array:
	var out: Array = []
	var cleaned := text.replace(",", " ").replace(";", " ").replace("-", " ")
	for tok in cleaned.split(" ", false):
		out.append(tok.strip_edges())
	return out

## Variante Breakaway su un percorso esistente: la tessera 2 diventa la seconda.
static func with_breakaway(seq: Array, face: String) -> Array:
	var out: Array = seq.duplicate()
	out.erase("2")
	out.erase("2B")
	out.insert(1, face)
	return out

## Tessere del Grand Tour su un percorso esistente: l'arrivo diventa quello largo (u → v, U → V).
static func with_wide_finish(seq: Array) -> Array:
	var out: Array = seq.duplicate()
	for i in out.size():
		if out[i] == "u":
			out[i] = "v"
		elif out[i] == "U":
			out[i] = "V"
	return out

## Tappa lunga (Grand Tour): quattro rettilinei da 6 caselle in più, presi tra le tessere non usate
## (meglio i rifornimenti di Peloton), inseriti a metà percorso dove non si sovrappongono.
static func extend(seq: Array) -> Array:
	var used := {}
	for id in seq:
		used[_tile_of(id)] = true
	var cand: Array = []
	for tile in ["3", "4", "b", "c", "d", "f", "l", "m", "n", "5", "6", "7", "8"]:
		if used.has(tile):
			continue
		for face in sides(tile):
			var f := FacesDB.face(face)
			if not f.is_empty() and f["kind"] == "straight" and f["cells"].size() == 6:
				cand.append(face)
				break
	var add: Array = cand.slice(0, 4)
	if add.is_empty():
		return seq
	var mid: int = seq.size() / 2
	for off in [0, 1, -1, 2, -2, 3, -3, 4, -4]:
		var at: int = clampi(mid + off, 1, seq.size() - 1)
		var out: Array = seq.slice(0, at) + add + seq.slice(at)
		if Track.build(out, true).ok():
			return out
	return seq.slice(0, mid) + add + seq.slice(mid)

## Tessera fisica di una faccia (a/A -> a, 3/3B -> 3).
static func _tile_of(face: String) -> String:
	if face.ends_with("B") and face.length() > 1:
		return face.substr(0, face.length() - 1)
	return face.to_lower()
