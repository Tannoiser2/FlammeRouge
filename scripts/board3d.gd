## Plancia 3D: tessere scansionate, segnalini, telecamera orbitale.
class_name Board3D
extends Node3D

signal follow_changed(on: bool)
signal square_clicked(sq: int)

var track: Track
var tiles_root: Node3D
var tokens := {}        # rider id -> Node3D
var ring: MeshInstance3D
var cam: Camera3D
var target := Vector3.ZERO
var desired := Vector3.ZERO
var yaw := -0.6
var pitch := 0.95
var dist := 14.0
var follow := true
var _drag := 0
var screen_shift := Vector2.ZERO
var pick_squares: Array = []     # caselle cliccabili (schieramento)
var markers: Array = []
var _press := Vector2.ZERO
var _bank_mat: StandardMaterial3D
var _letters: Array = []
var step_time := 0.4     # secondi per casella nelle animazioni (velocità scelta nel menu)
var anims := {}          # rider id -> stato di ruote e pedalata
var _pp: Dictionary = {}
var _jersey_shader: Shader = preload("res://assets/models/jersey.gdshader")   # frazione dello schermo coperta dal pannello (x a destra, y in basso)          # 0 nessuno, 1 ruota, 2 sposta
const TOKEN_Y := 0.09
const GROUND := Color("#A98652")      # tavolo color terra ocra
const BANK_TOP := Color(1, 1, 1)
const BANK_FOOT := Color(0.85, 0.6, 0.3)   # l'erba sfuma in terra alla base dell'argine

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("#6E9BC7")
	sm.sky_horizon_color = Color("#C9D9E2")
	sm.ground_horizon_color = Color("#C2A77E")
	sm.ground_bottom_color = Color("#8C6E44")
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = GROUND
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = noise
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.78, 0.74))
	grad.set_color(1, Color(1.04, 1.02, 1.0))
	nt.color_ramp = grad
	gm.albedo_texture = nt
	gm.uv1_scale = Vector3(40, 40, 40)
	gm.texture_repeat = true
	ground.material_override = gm
	ground.position.y = -0.02
	add_child(ground)
	_bank_mat = StandardMaterial3D.new()
	_bank_mat.albedo_texture = load("res://assets/erba_argine.png")
	_bank_mat.albedo_color = Color(0.78, 0.78, 0.74)
	_bank_mat.uv1_triplanar = true
	_bank_mat.uv1_scale = Vector3(1.6, 1.6, 1.6)
	_bank_mat.vertex_color_use_as_albedo = true
	_bank_mat.texture_repeat = true
	_bank_mat.roughness = 1.0
	_bank_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tiles_root = Node3D.new()
	add_child(tiles_root)
	cam = Camera3D.new()
	cam.fov = 50
	add_child(cam)
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.46
	tm.outer_radius = 0.52
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("#FFE14D")
	rm.emission_enabled = true
	rm.emission = Color("#FFD000")
	rm.emission_energy_multiplier = 0.8
	ring.material_override = rm
	ring.visible = false
	add_child(ring)

func show_track(t: Track) -> void:
	show_weather([])
	track = t
	for c in tiles_root.get_children():
		c.queue_free()
	for c in tokens.values():
		c.queue_free()
	tokens.clear()
	_letters.clear()
	anims.clear()
	if t.heights.is_empty():
		t.compute_heights(0.0)
	for i in t.pieces.size():
		tiles_root.add_child(_tile_mesh(t.pieces[i], i))
		var e := _embankment(t.pieces[i])
		if e:
			tiles_root.add_child(e)
	for at_end in [false, true]:
		var cap := _end_cap(t.pieces[-1] if at_end else t.pieces[0], at_end)
		if cap:
			tiles_root.add_child(cap)
	fit_view()

func _tile_mesh(piece: Dictionary, i: int) -> MeshInstance3D:
	var f := FacesDB.face(piece["id"])
	var w := float(f["w"])
	var h := float(f["h"])
	var lift := 0.0015 * (i % 4)
	var nx := maxi(2, int(ceil(w / 40.0)))
	var ny := maxi(2, int(ceil(h / 40.0)))
	var s0 := float(piece["s0"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array = []
	for yy in ny + 1:
		for xx in nx + 1:
			var px := Vector2(w * xx / nx, h * yy / ny)
			var wp := Track.xf(piece, px)
			var y := track.height_at(s0 + Track.local_s(f, px)) + lift
			verts.append([Vector3(wp.x, y, wp.y), Vector2(float(xx) / nx, float(yy) / ny)])
	for yy in ny:
		for xx in nx:
			var k := yy * (nx + 1) + xx
			for q in [k, k + 1, k + nx + 2, k, k + nx + 2, k + nx + 1]:
				st.set_uv(verts[q][1])
				st.add_vertex(verts[q][0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = FacesDB.texture(piece["id"])
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Argini di prato sotto i tratti rialzati: un nastro per lato, dal bordo della tessera al prato.
func _embankment(piece: Dictionary) -> MeshInstance3D:
	var f := FacesDB.face(piece["id"])
	if f.has("outline"):
		return _outline_skirt(piece)
	var g := Track.face_geo(f)
	var n := float(f["cells"].size())
	var s0 := float(piece["s0"])
	var hw := 0.97                       # mezza larghezza della tessera, in caselle
	var inner_max := 9.0
	var inner_side := 0
	if not g["straight"]:
		inner_side = 1 if g["sweep"] > 0 else -1
		inner_max = maxf(0.0, g["r"] / FacesDB.px() - hw - 0.08)
	var steps := int(ceil(n / 0.2))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for side in [-1, 1]:
		var prev_top := Vector3.ZERO
		var prev_bot := Vector3.ZERO
		for k in steps + 1:
			var sl := n * k / steps
			var c_px := Track.centerline_px(f, sl)
			var c_px2 := Track.centerline_px(f, sl + 0.05)
			var c := Track.xf(piece, c_px)
			var tan := (Track.xf(piece, c_px2) - c).normalized()
			var lat: Vector2 = Vector2(-tan.y, tan.x) * side
			var hh := track.height_at(s0 + sl)
			var spread := hh * 0.9 + 0.04
			# lato interno di una curva: l'argine non può allargarsi oltre il centro
			var is_inner: bool = inner_side != 0 and ((g["sweep"] > 0) == (side == 1))
			if is_inner:
				spread = minf(spread, inner_max)
			spread = minf(spread, _free_room(c, lat, tan, s0 + sl, hw))
			var top: Vector2 = c + lat * hw
			var bot: Vector2 = c + lat * (hw + spread)
			var vt := Vector3(top.x, hh - 0.02, top.y)
			var vb := Vector3(bot.x, -0.012, bot.y)
			if k > 0 and (hh > 0.005 or prev_top.y > 0.005):
				any = true
				for v in [prev_top, prev_bot, vb, prev_top, vb, vt]:
					st.set_color(BANK_TOP if v == prev_top or v == vt else BANK_FOOT)
					st.add_vertex(v)
			prev_top = vt
			prev_bot = vb
	if not any:
		return null
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _bank_mat
	return mi

## Argine per le tessere dalla forma irregolare (tornante, rotonde): un pendio d'erba che scende
## dal contorno vero della tessera, ricavato dalla trasparenza dell'immagine, verso l'esterno.
func _outline_skirt(piece: Dictionary) -> MeshInstance3D:
	var f := FacesDB.face(piece["id"])
	var s0 := float(piece["s0"])
	var px_pts: Array = f["outline"]
	var n := px_pts.size()
	if n < 3:
		return null
	var w_pts := PackedVector2Array()
	var hs: Array = []
	var top := 0.0
	for q in px_pts:
		var v := Vector2(q[0], q[1])
		w_pts.append(Track.xf(piece, v))
		var h := track.height_at(s0 + Track.local_s(f, v))
		hs.append(h)
		top = maxf(top, h)
	if top < 0.01:
		return null
	# normale verso l'esterno di ogni lato, scelta controllando da che parte sta il poligono
	var en: Array = []
	for i in n:
		var a := w_pts[i]
		var b := w_pts[(i + 1) % n]
		var e := (b - a).normalized()
		var nn := Vector2(e.y, -e.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nn * 0.03, w_pts):
			nn = -nn
		en.append(nn)
	var vn: Array = []
	for i in n:
		vn.append(((en[i] as Vector2) + (en[(i - 1 + n) % n] as Vector2)).normalized())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j := (i + 1) % n
		if hs[i] < 0.005 and hs[j] < 0.005:
			continue
		var ta := Vector3(w_pts[i].x, hs[i] - 0.02, w_pts[i].y)
		var tb := Vector3(w_pts[j].x, hs[j] - 0.02, w_pts[j].y)
		var ga: Vector2 = w_pts[i] + vn[i] * (hs[i] * 0.9 + 0.04)
		var gb: Vector2 = w_pts[j] + vn[j] * (hs[j] * 0.9 + 0.04)
		var ba := Vector3(ga.x, -0.012, ga.y)
		var bb := Vector3(gb.x, -0.012, gb.y)
		for v in [ta, ba, bb, ta, bb, tb]:
			st.set_color(BANK_TOP if v == ta or v == tb else BANK_FOOT)
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _bank_mat
	return mi

## Spazio libero di lato (o in avanti) prima di incontrare un altro tratto di strada:
## l'argine non deve coprire le tessere vicine; se lo spazio manca diventa un muro verticale.
func _free_room(c: Vector2, dir: Vector2, across: Vector2, s_here: float, start: float) -> float:
	var room := 99.0
	for j in track.size():
		if absf(j + 0.5 - s_here) < 2.0:
			continue
		var v := track.square_center(j) - c
		var along := v.dot(dir)
		if along <= 0.0:
			continue
		if absf(v.dot(across)) > 1.4:
			continue
		room = minf(room, along - start - 1.05)
	return maxf(room, 0.0)

## Testata dell'argine dove il percorso comincia o finisce in quota: un pendio frontale
## con la stessa pendenza dei fianchi, più due triangoli d'angolo che lo raccordano agli argini laterali.
func _end_cap(piece: Dictionary, at_end: bool) -> MeshInstance3D:
	var f := FacesDB.face(piece["id"])
	var n := float(f["cells"].size())
	var sl := n if at_end else 0.0
	var s_abs := float(piece["s0"]) + sl
	var hh := track.height_at(s_abs)
	if hh < 0.01:
		return null
	var c := Track.xf(piece, Track.centerline_px(f, sl))
	var c2 := Track.xf(piece, Track.centerline_px(f, sl - 0.05 if at_end else sl + 0.05))
	var out := (c - c2).normalized()
	var lat := Vector2(-out.y, out.x)
	var hw := 0.97
	var base := hh * 0.9 + 0.04
	var front := minf(base, _free_room(c, out, lat, s_abs, 0.0))
	var sp_l := minf(base, _free_room(c, -lat, out, s_abs, hw))
	var sp_r := minf(base, _free_room(c, lat, out, s_abs, hw))
	var top_y := hh - 0.02
	var foot := -0.012
	var tl := c - lat * hw
	var tr := c + lat * hw
	var vtl := Vector3(tl.x, top_y, tl.y)
	var vtr := Vector3(tr.x, top_y, tr.y)
	var fl := tl + out * front
	var fr := tr + out * front
	var vfl := Vector3(fl.x, foot, fl.y)
	var vfr := Vector3(fr.x, foot, fr.y)
	var sl_p := tl - lat * sp_l
	var sr_p := tr + lat * sp_r
	var vsl := Vector3(sl_p.x, foot, sl_p.y)
	var vsr := Vector3(sr_p.x, foot, sr_p.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [[vtl, vfl, vfr], [vtl, vfr, vtr], [vtl, vsl, vfl], [vtr, vfr, vsr]]
	for t in tris:
		for v in t:
			st.set_color(BANK_TOP if v == vtl or v == vtr else BANK_FOOT)
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _bank_mat
	return mi

# ---------- segnalini ----------

const MODEL_SCALE := 11.0
## Orientamento dei modelli: in gioco l'avanti è +X locale.
const MODEL_YAW := {"P": 90.0, "V": 180.0}
const MODEL_FILE := {"P": "passista", "V": "velocista"}

func make_tokens(riders: Array) -> void:
	for r in riders:
		var n := Node3D.new()
		var col: Color = r["team"]["color"]
		var txt: Color = r["team"].get("text", Color.WHITE)
		# basetta ovale del colore della squadra
		var base := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.25
		cm.bottom_radius = 0.26
		cm.height = 0.035
		cm.radial_segments = 40
		base.mesh = cm
		base.scale = Vector3(1.72, 1.0, 0.88)
		base.position.y = 0.0175
		var bm := StandardMaterial3D.new()
		bm.albedo_color = col
		bm.roughness = 0.45
		base.material_override = bm
		n.add_child(base)
		# lettera stampata sulla basetta, su entrambi i lati del ciclista
		for side in [-1, 1]:
			var lab := Label3D.new()
			lab.text = Rules.letter(r)
			lab.font_size = 64
			lab.pixel_size = 0.0019
			lab.outline_size = 0
			lab.modulate = txt
			lab.double_sided = true
			lab.rotation_degrees = Vector3(-90, 0, 0)
			lab.position = Vector3(-0.18, 0.037, 0.17 * side)
			n.add_child(lab)
			_letters.append(lab)
		# ciclista con la maglia della squadra
		var f: String = MODEL_FILE[r["type"]]
		var model: Node3D = load("res://assets/models/%s.glb" % f).instantiate()
		model.scale = Vector3.ONE * MODEL_SCALE
		model.rotation_degrees.y = MODEL_YAW[r["type"]]
		model.position.y = 0.035
		var pp: Dictionary = _pedal_params()[f]
		var anim := {"wheels": [], "mats": [], "r": 0.0, "phase": 0.0, "angle": 0.0, "last": Vector3.INF,
			"axis": Vector3(1, 0, 0) if int(pp["lat_axis"]) == 0 else Vector3(0, 0, 1)}
		var fwd := Vector3(-1, 0, 0) if r["type"] == "V" else Vector3(0, 0, 1)
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var sm := ShaderMaterial.new()
			sm.shader = _jersey_shader
			sm.set_shader_parameter("albedo_tex", load("res://assets/models/%s_tex.png" % f))
			sm.set_shader_parameter("mask_tex", load("res://assets/models/%s_mask.png" % f))
			sm.set_shader_parameter("team_color", col)
			mi.material_override = sm
			if mi.name.begins_with("ruota"):
				anim["wheels"].append(mi)
				sm.set_shader_parameter("wheel_on", 1.0)
				sm.set_shader_parameter("lat_axis", anim["axis"])
			else:
				sm.set_shader_parameter("pedal_on", 1.0)
				sm.set_shader_parameter("fwd_axis", fwd)
				sm.set_shader_parameter("lat_axis", anim["axis"])
				for k in ["lat0", "crank_y", "crank_len", "hip_y", "reach"]:
					sm.set_shader_parameter(k, float(pp[k]) * (1.35 if k == "crank_len" else 1.0))
				var fa := Vector3(1, 0, 0) if int(pp["fwd_axis"]) == 0 else Vector3(0, 0, 1)
				sm.set_shader_parameter("crank_fwd", float(pp["crank_fwd"]) * fwd.dot(fa))
				anim["mats"].append(sm)
		anim["r"] = float(pp["wheels"][0]["r"]) * MODEL_SCALE
		anims[r["id"]] = anim
		n.add_child(model)
		add_child(n)
		if tt_mode:
			n.scale = Vector3.ONE * 0.7
		tokens[r["id"]] = n
		n.visible = r["pos"] >= 0
		if r["pos"] >= 0:
			place(r, false)

func _pedal_params() -> Dictionary:
	if _pp.is_empty():
		_pp = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/pedalata.json"))
	return _pp

## Ruote e pedali seguono lo spostamento reale del segnalino: chi va più veloce pedala più veloce,
## da fermi tutto si ferma, in discesa le gambe restano immobili (ruota libera).
const GEAR := 2.6   # giri di ruota per ogni giro di pedivella

func _animate_riders() -> void:
	for id in anims:
		var a: Dictionary = anims[id]
		var n: Node3D = tokens[id]
		var p := n.global_position
		if a["last"] == Vector3.INF or not n.visible:
			a["last"] = p
			continue
		var d := Vector2(p.x - a["last"].x, p.z - a["last"].z).length()
		a["last"] = p
		if d < 0.00001 or d > 2.5:
			continue
		var turn: float = d / maxf(0.001, a["r"])
		a["angle"] = fmod(a["angle"] + turn, TAU)
		for w in a["wheels"]:
			w.basis = Basis(a["axis"], a["angle"])
		if n.rotation.z > -0.04:
			a["phase"] = fmod(a["phase"] + turn / GEAR, TAU)
			for m in a["mats"]:
				m.set_shader_parameter("phase", a["phase"])

var tt_mode := false   # cronometro: più squadre nella stessa casella, sfalsate
var tt_teams := 1

func token_pos(r: Dictionary) -> Vector3:
	var p := track.lane_pos(r["pos"], r["lane"])
	if tt_mode and r["pos"] >= 0:
		# più squadre nella stessa casella: sfalsate lungo la strada, centrate sulla casella
		var n_teams: int = tt_teams
		var k: float = int(r["team"]["idx"]) - (n_teams - 1) * 0.5
		p -= (track.squares[r["pos"]]["dir"] as Vector2) * 0.2 * k
	return Vector3(p.x, track.height_at(r["pos"] + 0.5), p.y)

func _pitch(sq: int) -> float:
	return atan(track.slope_at(sq + 0.5))

func _heading(sq: int) -> float:
	var d: Vector2 = track.squares[sq]["dir"]
	return -d.angle()

func place(r: Dictionary, animate := true) -> void:
	var n: Node3D = tokens[r["id"]]
	if not n.visible:
		n.visible = true
		animate = false
	var to := token_pos(r)
	if animate:
		var tw := create_tween()
		var d := step_time * 1.5
		tw.tween_property(n, "position", to, d).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(n, "rotation:y", _near(n.rotation.y, _heading(r["pos"])), d)
		tw.parallel().tween_property(n, "rotation:z", _pitch(r["pos"]), d)
	else:
		n.position = to
		n.rotation.y = _heading(r["pos"])
		n.rotation.z = _pitch(r["pos"])
	_lie(n, r)

## Angolo equivalente a "to" più vicino a "from": la rotazione segue sempre la via più breve
## (senza questo, passando da +179° a −179° il ciclista farebbe un giro su sé stesso).
## Un corridore caduto resta coricato sul fianco (rotazione attorno all'asse di marcia) finché non si rialza.
func _lie(n: Node3D, r: Dictionary) -> void:
	var m: Node3D = null
	for c in n.get_children():
		if c is Node3D and c.scene_file_path.ends_with(".glb"):
			m = c
	if m == null:
		return
	var yaw := deg_to_rad(MODEL_YAW[r["type"]])
	var target := 1.25 if r.get("crashed", false) else 0.0
	var cur: float = m.get_meta("lie", 0.0)
	if is_equal_approx(cur, target):
		return
	m.set_meta("lie", target)
	create_tween().tween_method(func(a: float):
		m.basis = (Basis(Vector3.RIGHT, a) * Basis(Vector3.UP, yaw)).scaled(Vector3.ONE * MODEL_SCALE), cur, target, 0.35)

static func _near(from: float, to: float) -> float:
	return from + wrapf(to - from, -PI, PI)

## Animazione casella per casella lungo il percorso.
func move_along(r: Dictionary, from: int, to: int, path: Array = []) -> void:
	var n: Node3D = tokens[r["id"]]
	var tw := create_tween()
	var yaw := n.rotation.y
	if path.is_empty():
		path = track.path_between(from, to)
	for p in path.slice(0, maxi(0, path.size() - 1)):
		var lanes: Array = track.squares[p]["lanes"]
		var c := Vector2.ZERO
		for l in lanes:
			c += l
		c /= lanes.size()
		yaw = _near(yaw, _heading(p))
		tw.tween_property(n, "position", Vector3(c.x, track.height_at(p + 0.5), c.y), step_time)
		tw.parallel().tween_property(n, "rotation:y", yaw, step_time)
		tw.parallel().tween_property(n, "rotation:z", _pitch(p), step_time)
	yaw = _near(yaw, _heading(r["pos"]))
	tw.tween_property(n, "position", token_pos(r), step_time * 1.2)
	tw.parallel().tween_property(n, "rotation:y", yaw, step_time * 1.2)
	tw.parallel().tween_property(n, "rotation:z", _pitch(r["pos"]), step_time * 1.2)
	tw.tween_callback(func(): _lie(n, r))
	if follow:
		desired = token_pos(r)
	await tw.finished

func highlight(r) -> void:
	if r == null:
		ring.visible = false
		return
	ring.visible = true
	var p := token_pos(r)
	ring.position = p + Vector3(0, 0.03, 0)
	if follow:
		desired = p

func flash_tired(r: Dictionary) -> void:
	var lab := Label3D.new()
	lab.text = "+F"
	lab.font_size = 56
	lab.pixel_size = 0.004
	lab.outline_size = 10
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color("#FFE9A8")
	lab.position = token_pos(r) + Vector3(0, 0.85, 0)
	add_child(lab)
	var tw := create_tween()
	tw.tween_property(lab, "position:y", 0.9, 1.2)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, 1.2)
	tw.tween_callback(lab.queue_free)

func pack_center(riders: Array) -> Vector3:
	var c := Vector3.ZERO
	for r in riders:
		c += token_pos(r)
	return c / max(1, riders.size())

# ---------- telecamera ----------

func fit_view() -> void:
	var bb := track.bounds()
	desired = Vector3(bb.get_center().x, track.max_height() * 0.4, bb.get_center().y)
	target = desired
	# vista d'insieme: allineata agli assi e quasi dall'alto, adattata allo spazio libero dai pannelli
	yaw = 0.0
	pitch = 1.3
	var vs := get_viewport().get_visible_rect().size
	var aspect: float = vs.x / maxf(1.0, vs.y)
	var t := tan(deg_to_rad(cam.fov * 0.5))
	var free_x: float = maxf(0.3, 1.0 - absf(screen_shift.x))
	var free_y: float = maxf(0.3, 1.0 - absf(screen_shift.y))
	var need_w := bb.size.x / (2.0 * t * aspect * free_x)
	var need_h := bb.size.y / (2.0 * t * free_y * sin(pitch))
	dist = clampf(maxf(need_w, need_h) * 1.08, 6.0, 160.0)

func focus(p: Vector3, d := 11.0) -> void:
	desired = p
	dist = d
	pitch = 0.95

func _process(delta: float) -> void:
	_animate_riders()
	target = target.lerp(desired, clampf(delta * 3.0, 0, 1))
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.position = target + off
	cam.look_at(target, Vector3.UP)
	# le lettere sulle basette restano sempre dritte rispetto allo schermo
	var lb := Basis.from_euler(Vector3(-PI / 2, yaw, 0))
	for lab in _letters:
		if is_instance_valid(lab):
			lab.global_basis = lb
	var half := dist * tan(deg_to_rad(cam.fov * 0.5))
	var vs := get_viewport().get_visible_rect().size
	var aspect: float = vs.x / maxf(1.0, vs.y)
	cam.h_offset = half * aspect * screen_shift.x
	cam.v_offset = -half * screen_shift.y

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			dist = clampf(dist * 0.9, 3.0, 120.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			dist = clampf(dist * 1.1, 3.0, 120.0)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = (2 if ev.shift_pressed else 1) if ev.pressed else 0
			if ev.pressed:
				_press = ev.position
			elif not pick_squares.is_empty() and ev.position.distance_to(_press) < 8:
				_pick(ev.position)
		elif ev.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = 2 if ev.pressed else 0
	elif ev is InputEventMouseMotion and _drag != 0:
		if _drag == 1:
			yaw -= ev.relative.x * 0.006
			pitch = clampf(pitch + ev.relative.y * 0.005, 0.25, 1.5)
		else:
			_pan(ev.relative)
	elif ev is InputEventMagnifyGesture:
		dist = clampf(dist / ev.factor, 3.0, 120.0)
	elif ev is InputEventPanGesture:
		_pan(-ev.delta * 8.0)

func _pan(rel: Vector2) -> void:
	if follow:
		follow = false
		follow_changed.emit(false)
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var k := dist * 0.0016
	desired += (-right * rel.x + fwd * rel.y) * k
	target = desired

# ---------- schieramento ----------

## Mostra i segnaposto sulle caselle di partenza libere.
func show_pick(squares: Array, riders: Array) -> void:
	clear_pick()
	pick_squares = squares
	for p in squares:
		var lanes: Array = track.squares[p]["lanes"]
		var used := 0
		for r in riders:
			if r["pos"] == p:
				used += 1
		var lp: Vector2 = lanes[mini(used, lanes.size() - 1)]
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.height = 0.02
		m.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.9, 0.3, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.position = Vector3(lp.x, track.height_at(p + 0.5) + 0.03, lp.y)
		add_child(m)
		markers.append(m)

func clear_pick() -> void:
	for m in markers:
		m.queue_free()
	markers.clear()
	pick_squares = []

func _pick(screen: Vector2) -> void:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 1e-4:
		return
	var plane_y := track.height_at(track.start_count * 0.5)
	var t := (plane_y - o.y) / d.y
	var hit := o + d * t
	var p2 := Vector2(hit.x, hit.z)
	var best := -1
	var bd := 1e9
	for sq in pick_squares:
		for l in track.squares[sq]["lanes"]:
			var dd: float = p2.distance_to(l)
			if dd < bd:
				bd = dd
				best = sq
	if best >= 0 and bd < 1.2:
		square_clicked.emit(best)

# ---------- arrivo e replay ----------

func _pos_pl(pos: int, lane: int) -> Vector3:
	var p := track.lane_pos(pos, lane)
	return Vector3(p.x, track.height_at(pos + 0.5), p.y)

## Il corridore arrivato esce di scena (le caselle dopo il traguardo tornano libere).
func finish_token(r: Dictionary) -> void:
	var n: Node3D = tokens[r["id"]]
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.35)
	tw.tween_callback(func():
		n.visible = false
		n.scale = Vector3.ONE * (0.7 if tt_mode else 1.0))

## Porta subito tutti i segnalini in uno stato salvato: s[i] = [casella, corsia].
func set_state(s: Array) -> void:
	for id in tokens:
		var n: Node3D = tokens[id]
		var pos: int = s[id][0]
		n.scale = Vector3.ONE * (0.7 if tt_mode else 1.0)
		n.visible = pos >= 0
		if pos >= 0:
			n.position = _pos_pl(pos, s[id][1])
			n.rotation.y = _heading(pos)
			n.rotation.z = _pitch(pos)
	_follow_state(s)

## Movimento simultaneo da uno stato al successivo: tutti impiegano lo stesso tempo t,
## quindi chi ha giocato una carta più alta va più veloce.
func animate_state(a: Array, b: Array, t: float, vanish: Array = []) -> void:
	for id in tokens:
		var n: Node3D = tokens[id]
		var p0: int = a[id][0]
		var p1: int = b[id][0]
		if p0 < 0 and p1 < 0:
			continue
		if p0 >= 0 and p1 < 0:
			# arrivato: esce di scena
			var tw0 := create_tween()
			tw0.tween_property(n, "scale", Vector3.ONE * 0.01, t)
			tw0.tween_callback(func():
				n.visible = false
				n.scale = Vector3.ONE * (0.7 if tt_mode else 1.0))
			continue
		if p0 < 0:
			n.visible = true
			n.position = _pos_pl(p1, b[id][1])
			continue
		if p0 == p1 and a[id][1] == b[id][1]:
			continue
		var steps: int = maxi(1, p1 - p0)
		var dt: float = t / steps
		var tw := create_tween()
		var yaw := n.rotation.y
		var pth := track.path_between(p0, p1)
		steps = maxi(1, pth.size())
		dt = t / steps
		for p in pth.slice(0, maxi(0, pth.size() - 1)):
			var lanes: Array = track.squares[p]["lanes"]
			var c := Vector2.ZERO
			for l in lanes:
				c += l
			c /= lanes.size()
			yaw = _near(yaw, _heading(p))
			tw.tween_property(n, "position", Vector3(c.x, track.height_at(p + 0.5), c.y), dt)
			tw.parallel().tween_property(n, "rotation:y", yaw, dt)
			tw.parallel().tween_property(n, "rotation:z", _pitch(p), dt)
		yaw = _near(yaw, _heading(p1))
		tw.tween_property(n, "position", _pos_pl(p1, b[id][1]), dt)
		tw.parallel().tween_property(n, "rotation:y", yaw, dt)
		tw.parallel().tween_property(n, "rotation:z", _pitch(p1), dt)
		if vanish.has(id):
			tw.tween_property(n, "scale", Vector3.ONE * 0.01, 0.3)
			tw.tween_callback(func():
				n.visible = false
				n.scale = Vector3.ONE * (0.7 if tt_mode else 1.0))
	_follow_state(b)
	await get_tree().create_timer(t).timeout

## La telecamera segue la testa della corsa.
func _follow_state(s: Array) -> void:
	if not follow:
		return
	var best: Array = []
	for id in s.size():
		if s[id][0] >= 0:
			best.append(s[id])
	if best.is_empty():
		return
	best.sort_custom(func(x, y): return track.prog(x[0]) > track.prog(y[0]))
	var c := Vector3.ZERO
	var k: int = mini(4, best.size())
	for i in k:
		c += _pos_pl(best[i][0], best[i][1])
	desired = c / k

# ---------- anteprima del movimento ----------

var _target_nodes: Array = []

## Evidenzia la casella (e la corsia) d'arrivo di una carta, con le caselle attraversate.
## blocked: il corridore si fermerebbe prima perché la casella voluta è piena.
func show_target(from: int, pos: int, lane: int, blocked := false) -> void:
	clear_target()
	var col := Color(1.0, 0.55, 0.15, 0.75) if blocked else Color(1.0, 0.86, 0.25, 0.75)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.27
	cm.bottom_radius = 0.27
	cm.height = 0.02
	cm.radial_segments = 32
	disc.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 2
	disc.material_override = mat
	disc.scale = Vector3(1.6, 1, 0.85)
	disc.position = _pos_pl(pos, lane) + Vector3(0, 0.04, 0)
	disc.rotation.y = _heading(pos)
	add_child(disc)
	_target_nodes.append(disc)
	var pulse := create_tween().set_loops()
	pulse.tween_property(mat, "albedo_color:a", 0.35, 0.45)
	pulse.tween_property(mat, "albedo_color:a", 0.8, 0.45)
	disc.set_meta("tween", pulse)
	var pth := track.path_between(from, pos)
	for p in pth.slice(0, maxi(0, pth.size() - 1)):
		var dot := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.04
		dot.mesh = sm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(col.r, col.g, col.b, 0.85)
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.no_depth_test = true
		dot.material_override = dm
		var c := track.square_center(p)
		dot.position = Vector3(c.x, track.height_at(p + 0.5) + 0.05, c.y)
		add_child(dot)
		_target_nodes.append(dot)

func clear_target() -> void:
	for n in _target_nodes:
		if is_instance_valid(n):
			if n.has_meta("tween"):
				(n.get_meta("tween") as Tween).kill()
			n.queue_free()
	_target_nodes.clear()


# ---------- gettoni dei traguardi e maglie ----------

var _pile_nodes: Array = []

## Mucchietti di gettoni a bordo strada: verde per lo sprint, bianco a pois rossi per la montagna.
func update_piles(piles: Array) -> void:
	for n in _pile_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_pile_nodes.clear()
	for pl in piles:
		if pl["values"].is_empty() or pl["sq"] >= track.size():
			continue
		var sq: int = pl["sq"]
		var lanes: Array = track.squares[sq]["lanes"]
		var edge: Vector2 = lanes[0] + (lanes[0] - track.square_center(sq)).normalized() * 0.55 if lanes.size() > 1 else lanes[0] + Vector2(0.6, 0)
		var base := Vector3(edge.x, track.height_at(sq + 0.5), edge.y)
		var holder := Node3D.new()
		holder.position = base
		add_child(holder)
		_pile_nodes.append(holder)
		for k in pl["values"].size():
			var t := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.16
			cm.bottom_radius = 0.16
			cm.height = 0.035
			t.mesh = cm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color("#F4F1EA") if pl["mountain"] else Color("#2E9E4A")
			t.material_override = m
			t.position.y = 0.02 + k * 0.04
			holder.add_child(t)
		var lab := Label3D.new()
		lab.text = ("Montagna " if pl["mountain"] else "Sprint ") + "/".join(pl["values"].map(func(v): return str(v)))
		lab.font_size = 40
		lab.pixel_size = 0.004
		lab.outline_size = 10
		lab.modulate = Color("#E23B3B") if pl["mountain"] else Color("#9BE3A6")
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position.y = 0.4
		holder.add_child(lab)

## Maglie del tour: un anello colorato attorno alla basetta (giallo, verde, bianco a pois).
func set_jerseys(j: Dictionary) -> void:
	for id in tokens:
		var old: Node = (tokens[id] as Node3D).get_node_or_null("Maglia")
		if old:
			old.queue_free()
	var cols := {"gc": Color("#F2C200"), "sc": Color("#2E9E4A"), "mc": Color("#F4F1EA")}
	for kind in j:
		var id: int = j[kind]
		if not tokens.has(id):
			continue
		var ring := MeshInstance3D.new()
		ring.name = "Maglia"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42
		tm.outer_radius = 0.5
		ring.mesh = tm
		ring.scale = Vector3(1.0, 0.6, 0.55)
		var m := StandardMaterial3D.new()
		m.albedo_color = cols[kind]
		if kind == "mc":
			m.emission_enabled = true
			m.emission = Color("#C8323C") * 0.3
		ring.material_override = m
		ring.position.y = 0.03
		tokens[id].add_child(ring)


# ---------- Meteo: sagome in piedi accanto ai rettilinei ----------

var _weather_nodes: Array = []

func show_weather(tiles: Array) -> void:
	for n in _weather_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_weather_nodes.clear()
	for wt in tiles:
		var pc: Dictionary = track.pieces[wt["piece"]]
		var s0: int = pc["s0"]
		var n_cells: int = FacesDB.face(pc["id"])["cells"].size()
		var a := track.square_center(s0)
		var b := track.square_center(s0 + n_cells - 1)
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)        # a sinistra del senso di marcia
		var spr := Sprite3D.new()
		spr.texture = load("res://assets/meteo/%s.png" % wt["kind"])
		var w := 4.6
		spr.pixel_size = w / spr.texture.get_width()
		spr.double_sided = true
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.shaded = false
		var hgt: float = spr.texture.get_height() * spr.pixel_size
		var base := mid + side * 1.25
		var y := track.height_at(s0 + n_cells * 0.5)
		spr.position = Vector3(base.x, y + hgt * 0.5, base.y)
		spr.rotation.y = -dir.angle()
		add_child(spr)
		_weather_nodes.append(spr)


# ---------- tappa lunga: gettone del ristoro ----------

var _refresh_node: Node3D

func show_refresh(sq: int) -> void:
	if is_instance_valid(_refresh_node):
		_refresh_node.queue_free()
	if sq < 0 or track == null or sq >= track.size():
		return
	var lanes: Array = track.squares[sq]["lanes"]
	var c := track.square_center(sq)
	var edge: Vector2 = lanes[-1] + ((lanes[-1] as Vector2) - c).normalized() * 0.55 if lanes.size() > 1 else lanes[0] + Vector2(0.6, 0)
	var holder := Node3D.new()
	holder.position = Vector3(edge.x, track.height_at(sq + 0.5), edge.y)
	var t := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.17
	cm.height = 0.05
	t.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#3FA9E0")
	t.material_override = m
	t.position.y = 0.03
	holder.add_child(t)
	var lab := Label3D.new()
	lab.text = "Ristoro"
	lab.font_size = 40
	lab.pixel_size = 0.004
	lab.outline_size = 10
	lab.modulate = Color("#9ED8FF")
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position.y = 0.4
	holder.add_child(lab)
	add_child(holder)
	_refresh_node = holder
