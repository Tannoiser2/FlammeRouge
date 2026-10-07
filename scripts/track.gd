## Percorso montato concatenando facce di tessera.
## Coordinate del mondo in caselle (Vector2: x = X, y = Z del 3D).
class_name Track
extends RefCounted

var pieces: Array = []      # [{id, pos, angle, scale}] : trasformazione px -> mondo
var squares: Array = []     # [{cap, t, lanes:[Vector2], dir:Vector2, piece:int}]
var start_count := 0        # caselle di schieramento (indici 0..start_count-1)
var finish := -1            # ultima casella prima del traguardo
var error := ""
var heights: PackedFloat32Array = []   # quota ai bordi delle caselle (size()+1 valori)
var rise := 0.0

## Trasforma un punto in pixel della faccia nel mondo.
static func xf(piece: Dictionary, p: Vector2) -> Vector2:
	return piece["pos"] + (p - piece["origin"]).rotated(piece["angle"]) * piece["scale"]

## Costruisce un percorso da una sequenza di id di facce. Restituisce null se non valida.
static func build(seq: Array, check_overlap := true) -> Track:
	var t := Track.new()
	var pos := Vector2.ZERO
	var dir := Vector2.RIGHT
	var s := 1.0 / FacesDB.px()
	for i in seq.size():
		var id: String = seq[i]
		var f := FacesDB.face(id)
		if f.is_empty():
			t.error = "Faccia sconosciuta: %s" % id
			return t
		var ed := FacesDB.v2(f["entry"]["dir"]).normalized()
		var ang := dir.angle() - ed.angle()
		var piece := {"id": id, "pos": pos, "origin": FacesDB.v2(f["entry"]["p"]), "angle": ang, "scale": s,
			"s0": t.squares.size(), "n": f["cells"].size()}
		t.pieces.append(piece)
		for c in f["cells"]:
			var lanes: Array = []
			for l in c["lanes"]:
				lanes.append(xf(piece, FacesDB.v2(l)))
			t.squares.append({"cap": lanes.size(), "t": c["t"], "lanes": lanes, "wet": c.get("wet", false),
				"dir": FacesDB.v2(c["dir"]).rotated(ang), "piece": i, "branch": c.get("branch", "")})
		if f.has("start_squares"):
			if i != 0:
				t.error = "La partenza (%s) deve essere la prima tessera." % id
				return t
			t.start_count = int(f["start_squares"])
		if f.has("finish_after"):
			if i != seq.size() - 1:
				t.error = "Il traguardo (%s) deve essere l'ultima tessera." % id
				return t
			t.finish = t.squares.size() - f["cells"].size() + int(f["finish_after"]) - 1
		pos = xf(piece, FacesDB.v2(f["exit"]["p"]))
		dir = FacesDB.v2(f["exit"]["dir"]).normalized().rotated(ang)
	t._link()
	if t.start_count == 0:
		t.error = "Manca la tessera di partenza (a, A, 1 o 1B)."
	elif t.finish < 0:
		t.error = "Manca la tessera d'arrivo (u o U)."
	elif check_overlap and t.overlaps():
		t.error = "Le tessere si sovrappongono."
	return t

func ok() -> bool:
	return error == ""

# ---------- percorso a grafo (rotonde del Grand Tour) ----------
# Ogni casella ha le successive ("next") e le precedenti ("prev"). Sulle rotonde, dopo le tre
# caselle a due corsie, la strada si divide: corsia interna (3 caselle) ed esterna (5), che si
# ricongiungono all'uscita. "prog" ordina le caselle da dietro a davanti secondo le regole:
# sulla rotonda chi è sulle corsie separate viene prima di chi è ancora sul tratto a due corsie,
# e tra le corsie separate conta la distanza dall'uscita (a parità, prima l'interna).

var lines: Array = []        # tutti i percorsi possibili dalla partenza all'ultima casella
var togo: Array = []         # caselle mancanti per superare la linea d'arrivo

func _link() -> void:
	var n := squares.size()
	for i in n:
		squares[i]["next"] = [i + 1] if i + 1 < n else []
		squares[i]["prev"] = []
	for pc in pieces:
		if FacesDB.face(pc["id"])["kind"] != "roundabout":
			continue
		var s0: int = pc["s0"]
		var stem_last := s0 + 2
		var inner := [s0 + 3, s0 + 4, s0 + 5]
		var outer := [s0 + 6, s0 + 7, s0 + 8, s0 + 9, s0 + 10]
		var exit_i := s0 + 11
		squares[stem_last]["next"] = [inner[0], outer[0]]
		squares[inner[2]]["next"] = [exit_i] if exit_i < n else []
		squares[outer[4]]["next"] = [exit_i] if exit_i < n else []
	for i in n:
		for j in squares[i]["next"]:
			squares[j]["prev"].append(i)
	# ordine lungo il percorso
	var c := 0.0
	var i := 0
	while i < n:
		var f := FacesDB.face(pieces[squares[i]["piece"]]["id"])
		if f["kind"] == "roundabout" and squares[i]["piece"] != -1 and i == int(pieces[squares[i]["piece"]]["s0"]):
			for k in 3:
				squares[i + k]["prog"] = c + k
			for k in 3:
				squares[i + 3 + k]["prog"] = c + 6.5 + k
			for k in 5:
				squares[i + 6 + k]["prog"] = c + 4.0 + k
			c += 9.0
			i += 11
		else:
			squares[i]["prog"] = c
			c += 1.0
			i += 1
	# percorsi completi (uno per ogni combinazione di corsie)
	lines = []
	_lines_from(0, [])
	# caselle che mancano per superare il traguardo (lungo il percorso più corto)
	togo = []
	togo.resize(n)
	for k in n:
		togo[k] = 0
	for k in range(n - 1, -1, -1):
		if finish >= 0 and prog(k) > prog(finish):
			togo[k] = 0
		else:
			var best := 999
			for j in squares[k]["next"]:
				best = mini(best, togo[j] + 1)
			togo[k] = best if best < 999 else 1

func _lines_from(i: int, acc: Array) -> void:
	var path: Array = acc.duplicate()
	var k := i
	while true:
		path.append(k)
		var nx: Array = squares[k]["next"]
		if nx.is_empty():
			lines.append(path)
			return
		if nx.size() == 1:
			k = nx[0]
		else:
			for j in nx:
				_lines_from(j, path)
			return

func prog(i: int) -> float:
	return squares[i]["prog"] if i >= 0 and i < squares.size() and squares[i].has("prog") else float(i)

func next_of(i: int) -> Array:
	return squares[i]["next"] if i >= 0 and i < squares.size() and squares[i].has("next") else ([i + 1] if i + 1 < squares.size() else [])

func branch(i: int) -> String:
	return squares[i].get("branch", "") if i >= 0 and i < squares.size() else ""

## Percorso di "steps" caselle a partire da "from" (escluso), scegliendo la corsia indicata
## al bivio ("inner" o "outer"). Si ferma a fine percorso.
func walk(from: int, steps: int, pref := "inner") -> Array:
	var out: Array = []
	var k := from
	for s in steps:
		var nx := next_of(k)
		if nx.is_empty():
			break
		k = nx[0]
		if nx.size() > 1:
			for j in nx:
				if branch(j) == pref:
					k = j
		out.append(k)
	return out

## Caselle attraversate per andare da a a b (b raggiungibile da a), estremi esclusi a, incluso b.
func path_between(a: int, b: int) -> Array:
	if a == b:
		return []
	for pref in ["inner", "outer"]:
		var p := walk(a, 40, pref)
		var idx := p.find(b)
		if idx >= 0:
			return p.slice(0, idx + 1)
	return [b]

## Punti campione di un pezzo (centri delle caselle e delle corsie).
func _samples(i: int) -> Array:
	var out: Array = []
	for sq in squares:
		if sq["piece"] == i:
			out.append_array(sq["lanes"])
	return out

## Vero se due tessere non adiacenti sono troppo vicine.
func overlaps(min_dist := 1.75) -> bool:
	var smp: Array = []
	for i in pieces.size():
		smp.append(_samples(i))
	for i in pieces.size():
		for j in range(i + 2, pieces.size()):
			if _too_close(smp[i], smp[j], min_dist):
				return true
	return false

static func _too_close(a: Array, b: Array, d: float) -> bool:
	for p in a:
		for q in b:
			if p.distance_to(q) < d:
				return true
	return false

## Controllo incrementale usato dal generatore: l'ultimo pezzo tocca i precedenti?
func last_overlaps(min_dist := 1.75) -> bool:
	var n := pieces.size()
	if n < 3:
		return false
	var last := _samples(n - 1)
	for i in range(0, n - 2):
		if _too_close(last, _samples(i), min_dist):
			return true
	return false

func terrain(i: int) -> String:
	return squares[i]["t"] if i >= 0 and i < squares.size() else "flat"

func cap(i: int) -> int:
	return squares[i]["cap"] if i >= 0 and i < squares.size() else 0

func lane_pos(i: int, lane: int) -> Vector2:
	var l: Array = squares[i]["lanes"]
	return l[clampi(lane, 0, l.size() - 1)]

func size() -> int:
	return squares.size()

func bounds() -> Rect2:
	var r := Rect2(squares[0]["lanes"][0], Vector2.ZERO)
	for sq in squares:
		for p in sq["lanes"]:
			r = r.expand(p)
	return r.grow(1.5)

# ---------- altimetria ----------

## Calcola le quote: ogni casella in salita alza di `r`, ogni discesa abbassa di `r`.
## La quota minima del percorso diventa zero (il livello del prato).
func compute_heights(r: float) -> void:
	rise = r
	heights.resize(squares.size() + 1)
	var h := 0.0
	heights[0] = 0.0
	for i in squares.size():
		var tt: String = squares[i]["t"]
		if tt == "up":
			h += r
		elif tt == "down":
			h -= r
		heights[i + 1] = h
	var mn := 0.0
	for v in heights:
		mn = minf(mn, v)
	for i in heights.size():
		heights[i] -= mn

func _h_raw(s: float) -> float:
	if heights.is_empty():
		return 0.0
	s = clampf(s, 0.0, float(heights.size() - 1))
	var i := mini(int(s), heights.size() - 2)
	return lerpf(heights[i], heights[i + 1], s - i)

## Quota lisciata lungo il percorso (s in caselle dall'inizio).
func height_at(s: float) -> float:
	if heights.is_empty():
		return 0.0
	var acc := 0.0
	for k in range(-4, 5):
		acc += _h_raw(s + k * 0.08)
	return acc / 9.0

func slope_at(s: float) -> float:
	return (height_at(s + 0.25) - height_at(s - 0.25)) / 0.5

func max_height() -> float:
	var m := 0.0
	for v in heights:
		m = maxf(m, v)
	return m

## Posizione lungo il percorso (in caselle) di un punto in pixel della faccia.
static func local_s(f: Dictionary, p: Vector2) -> float:
	if f["kind"] == "hairpin" or f["kind"] == "roundabout":
		return _poly_s(f, p)
	var g := face_geo(f)
	var n := float(f["cells"].size())
	if g["straight"]:
		return (p - g["p0"]).dot(g["d0"]) / g["len"] * n
	# angolo misurato dal centro dell'arco: il salto di ±180° cade dietro il centro, fuori dalla tessera
	var sweep: float = g["sweep"]
	var a_mid: float = (g["p0"] - g["c"]).angle() + sweep * 0.5
	var a: float = (p - g["c"]).angle()
	var s := (wrapf(a - a_mid, -PI, PI) / sweep + 0.5) * n
	return clampf(s, -0.75, n + 0.75)

## Geometria di una faccia: retta o arco (centro, raggio, ampiezza).
static func face_geo(f: Dictionary) -> Dictionary:
	if f.has("_geo"):
		return f["_geo"]
	var p0 := FacesDB.v2(f["entry"]["p"])
	var d0 := FacesDB.v2(f["entry"]["dir"]).normalized()
	var p1 := FacesDB.v2(f["exit"]["p"])
	var d1 := FacesDB.v2(f["exit"]["dir"]).normalized()
	var g := {"p0": p0, "d0": d0, "p1": p1, "straight": absf(d0.cross(d1)) < 0.01}
	if g["straight"]:
		g["len"] = (p1 - p0).dot(d0)
	else:
		var n0 := Vector2(-d0.y, d0.x)
		var n1 := Vector2(-d1.y, d1.x)
		# p0 + n0*t = p1 + n1*u
		var det := n0.x * (-n1.y) - n0.y * (-n1.x)
		var rhs := p1 - p0
		var t := (rhs.x * (-n1.y) - rhs.y * (-n1.x)) / det
		var c := p0 + n0 * t
		g["c"] = c
		g["r"] = absf(t)
		g["sweep"] = wrapf((p1 - c).angle() - (p0 - c).angle(), -PI, PI)
	f["_geo"] = g
	return g

## Punto della linea di mezzeria della faccia (in pixel) a una posizione locale (caselle).
static func centerline_px(f: Dictionary, s_local: float) -> Vector2:
	if f["kind"] == "hairpin" or f["kind"] == "roundabout":
		return _poly_at(f, s_local)
	var g := face_geo(f)
	var n := float(f["cells"].size())
	if g["straight"]:
		return g["p0"] + g["d0"] * (s_local / n * g["len"])
	var a: float = (g["p0"] - g["c"]).angle() + float(g["sweep"]) * s_local / n
	return g["c"] + Vector2(cos(a), sin(a)) * g["r"]

## Centro della casella i (media delle corsie) e sua posizione s.
func square_center(i: int) -> Vector2:
	var c := Vector2.ZERO
	for l in squares[i]["lanes"]:
		c += l
	return c / squares[i]["lanes"].size()

# ---------- tornante (curva stretta del Grand Tour): mezzeria come spezzata ----------

## Punti della mezzeria con la loro posizione s: ingresso (0), centri delle caselle (i + 0.5), uscita (n).
static func _poly(f: Dictionary) -> Array:
	if f.has("_poly"):
		return f["_poly"]
	var pts: Array = [[0.0, FacesDB.v2(f["entry"]["p"])]]
	var n: int = f["cells"].size()
	if f["kind"] == "roundabout":
		# gambo (3 caselle) e corsia interna, distribuita fino all'uscita (indice n)
		for i in 3:
			pts.append([i + 0.5, FacesDB.v2(f["cells"][i]["c"])])
		for k in 3:
			pts.append([3.0 + (k + 0.5) * (n - 3) / 3.0, FacesDB.v2(f["cells"][3 + k]["c"])])
	else:
		for i in n:
			pts.append([i + 0.5, FacesDB.v2(f["cells"][i]["c"])])
	pts.append([float(n), FacesDB.v2(f["exit"]["p"])])
	f["_poly"] = pts
	return pts

static func _poly_at(f: Dictionary, s_local: float) -> Vector2:
	var pts := _poly(f)
	s_local = clampf(s_local, 0.0, pts[-1][0])
	for i in pts.size() - 1:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if s_local <= b[0]:
			return (a[1] as Vector2).lerp(b[1], (s_local - a[0]) / maxf(0.0001, b[0] - a[0]))
	return pts[-1][1]

static func _poly_s(f: Dictionary, p: Vector2) -> float:
	var pts := _poly(f)
	var best := 0.0
	var best_d := INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i][1]
		var b: Vector2 = pts[i + 1][1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best = lerpf(pts[i][0], pts[i + 1][0], t)
	return best
