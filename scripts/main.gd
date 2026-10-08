## Scena principale: impostazione della corsa, svolgimento dei turni, interfaccia.
extends Node3D

signal choice(value)

var board: Board3D
var R: Rules
var track: Track
var ui: CanvasLayer
var root: Control
var setup_box: PanelContainer
var panel: PanelContainer
var status_lbl: Label
var chips: HFlowContainer
var profile: ProfileView
var action: VBoxContainer
var log_box: RichTextLabel
var follow_btn: CheckButton
var overlay: PanelContainer
var cfg := {"n": 3, "kind": [0, 1, 1, 1, 1, 1], "mode": 0, "length": 1, "peloton": false, "seq": "", "stage": 0, "exh": 0, "free_start": true, "relief": 2, "tour": 0, "carry": true, "anim": 0, "breakaway": false, "rest": true, "gt": false, "meteo": false, "stype": 0, "cpu": 1}
var stages: Array = []
var tour := {}
var history: Array = []
var replay := {}
var report: PanelContainer
var stage_title := ""
var splash_close := Callable()
var slots: Dictionary = {}
var anim_seg: HBoxContainer
var menu_dialog: ConfirmationDialog
var race_id := 0      # cambia a ogni nuova corsa o ritorno al menu
var preview_seq: Array = []

const VERSION := "0.38 (8 ottobre)"
const LENGTH_KEYS := ["breve", "media", "lunga", "tutte"]
const LENGTH_NAMES := ["Breve", "Media", "Completa", "Tutte le tessere"]
const RELIEF := [0.0, 0.06, 0.1, 0.15]
const RELIEF_NAMES := ["Piatto", "Leggero", "Normale", "Marcato"]
const TOURS := [
	{"name": "Tour de France 2018, carte Gigamic (21 tappe)", "group": "Tour de France 2018 (carte Gigamic)"},
	{"name": "Tour de France 2018, L'Étape du Tour (20 tappe)", "group": "Tour de France 2018"},
	{"name": "Le classiche (7 tappe)", "group": "Classiche"},
	{"name": "Tappe del gioco base (5)", "group": "Gioco base"},
	{"name": "Tappe della Companion App (17)", "group": "Companion App"},
	{"name": "Grand Tour TTS, 21 tappe (5–6 giocatori)", "group": "Grand Tour TTS (5–6 giocatori)"},
	{"name": "Grand Tour TTS, 21 tappe (2–4 giocatori)", "group": "Grand Tour TTS (2–4 giocatori)"},
	{"name": "Grand Tour: tappe 3 e 4 (regolamento)", "group": "Grand Tour"},
	{"name": "Tre tappe casuali", "random": 3},
	{"name": "Sei tappe casuali", "random": 6},
]
const CPU_LEVEL_NAMES := ["Normale", "Difficile", "Esperto"]
## Livello della CPU: [livello nel motore, finali simulati per carta, millisecondi massimi per decisione]
const CPU_LEVELS := [[1, 0, 0], [2, 16, 700], [2, 32, 1500]]
const ANIM_NAMES := ["Lenta", "Normale", "Veloce"]
const ANIM_STEP := [0.4, 0.22, 0.12]     # secondi per casella
const KIND_NAMES := ["Giocatore", "Computer", "Squadra Peloton", "Squadra Muscle"]

func _ready() -> void:
	stages = JSON.parse_string(FileAccess.open("res://data/stages.json", FileAccess.READ).get_as_text())
	board = Board3D.new()
	add_child(board)
	board.follow_changed.connect(func(on): if follow_btn: follow_btn.set_pressed_no_signal(on))
	ui = CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 18
	root.theme = th
	ui.add_child(root)
	_build_setup()
	_build_panel()
	_build_overlay()
	_build_report()
	get_viewport().size_changed.connect(_layout)
	_check_assets()
	_preview()
	_layout()
	_show_splash()

# ---------- interfaccia ----------

func _style(bg: Color, radius := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(14)
	return sb

func _set_anim(k: int) -> void:
	cfg["anim"] = k
	board.step_time = ANIM_STEP[k]

func _section(t: String) -> Label:
	var l := _plain(t, 13, Color(1, 0.86, 0.55))
	l.uppercase = true
	return l

func _row(title: String, ctrl: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := _plain(title, 16, Color(1, 1, 1, 0.85))
	l.custom_minimum_size.x = 118
	r.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ctrl)
	return r

## Gruppo di tasti a scelta singola, al posto dei menu a tendina.
func _seg(options: Array, selected: int, on_change: Callable, size := 15) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var group := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == selected
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", size)
		var on := _style(Color("#E8B84A"), 5)
		on.set_content_margin_all(5)
		var off := _style(Color(1, 1, 1, 0.08), 5)
		off.set_content_margin_all(5)
		var hov := _style(Color(1, 1, 1, 0.16), 5)
		hov.set_content_margin_all(5)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_color_override("font_pressed_color", Color("#1C2938"))
		b.add_theme_color_override("font_hover_pressed_color", Color("#1C2938"))
		b.pressed.connect(func(): on_change.call(i))
		box.add_child(b)
	return box

func _build_setup() -> void:
	setup_box = PanelContainer.new()
	setup_box.add_theme_stylebox_override("panel", _style(Color(0.08, 0.11, 0.15, 0.94)))
	root.add_child(setup_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	setup_box.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 9)
	scroll.add_child(v)
	# ----- squadre -----
	v.add_child(_section("Squadre"))
	var teams_box := VBoxContainer.new()
	teams_box.add_theme_constant_override("separation", 5)
	var holder := [null]
	var fill_teams := func():
		for c in teams_box.get_children():
			c.queue_free()
		for i in cfg["n"]:
			var row := HBoxContainer.new()
			var sw := ColorRect.new()
			sw.color = Rules.TEAM_COLORS[i]
			sw.custom_minimum_size = Vector2(16, 16)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(sw)
			var lb := _plain("  " + Rules.TEAM_NAMES[i], 16)
			lb.custom_minimum_size.x = 90
			row.add_child(lb)
			var seg := _seg(["Giocatore", "Computer", "Peloton", "Muscle"], cfg["kind"][i], func(k):
				if k == 2:
					# una sola Squadra Peloton: le altre tornano al computer
					for j in cfg["kind"].size():
						if j != i and cfg["kind"][j] == 2:
							cfg["kind"][j] = 1
					cfg["kind"][i] = k
					holder[0].call()
				else:
					cfg["kind"][i] = k, 14)
			seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(seg)
			teams_box.add_child(row)
	v.add_child(_row("Squadre", _seg(["1", "2", "3", "4", "5", "6"], cfg["n"] - 1, func(k):
		cfg["n"] = k + 1
		fill_teams.call()
		if not _custom_track():
			_preview())))
	v.add_child(teams_box)
	holder[0] = fill_teams
	fill_teams.call()
	var exh := _seg(["0", "1", "2", "3", "4", "5", "6"], cfg["exh"], func(k): cfg["exh"] = k)
	exh.tooltip_text = "Carte fatica in più per ogni squadra di giocatori: handicap, o 3 nel solitario."
	v.add_child(_row("Fatica iniziale", exh))
	v.add_child(_row("Schieramento", _seg(["A scelta", "Casuale"], 0 if cfg["free_start"] else 1, func(k): cfg["free_start"] = k == 0)))
	var cpu_seg := _seg(CPU_LEVEL_NAMES, cfg["cpu"], func(k): cfg["cpu"] = k)
	cpu_seg.tooltip_text = "Normale: la CPU valuta la carta sulla posizione di adesso. Difficile ed Esperto: per ogni carta immagina molti finali di corsa e sceglie quella che porta al piazzamento migliore (Esperto ne immagina di più e ci mette qualche istante in più)."
	v.add_child(_row("Computer", cpu_seg))
	var bw := _seg(["Nessuna", "Variante Breakaway"], 1 if cfg["breakaway"] else 0, func(k):
		cfg["breakaway"] = k == 1
		_refresh_preview())
	bw.tooltip_text = "Prima della partenza un'asta manda in fuga uno o due corridori (regole di Peloton). La tessera 2 diventa la seconda del percorso."
	v.add_child(_row("Fuga", bw))
	v.add_child(HSeparator.new())
	# ----- pista -----
	v.add_child(_section("Pista"))
	var rand_box := VBoxContainer.new()
	var stage_box := VBoxContainer.new()
	var seq_box := VBoxContainer.new()
	var tour_box := VBoxContainer.new()
	for bx in [rand_box, stage_box, seq_box, tour_box]:
		bx.add_theme_constant_override("separation", 8)
	var show_mode := func(k):
		cfg["mode"] = k
		rand_box.visible = k == 0 or (k == 3 and TOURS[cfg["tour"]].has("random"))
		stage_box.visible = k == 1
		seq_box.visible = k == 2
		tour_box.visible = k == 3
	v.add_child(_row("Percorso", _seg(["Casuale", "Libretto", "Sequenza", "Tour"], cfg["mode"], func(k):
		show_mode.call(k)
		if k == 0:
			_preview()
		elif k == 1:
			_show_stage()
		elif k == 3:
			_show_tour_preview(), 14)))
	v.add_child(stage_box)
	v.add_child(tour_box)
	v.add_child(rand_box)
	v.add_child(seq_box)
	# casuale
	rand_box.add_child(_row("Lunghezza", _seg(LENGTH_NAMES, cfg["length"], func(k):
		cfg["length"] = k
		_preview(), 14)))
	var pel_row := HBoxContainer.new()
	rand_box.add_child(_row("Peloton", _seg(["Solo gioco base", "Anche tessere Peloton"], 1 if cfg["peloton"] else 0, func(k):
		cfg["peloton"] = k == 1
		_preview(), 14)))
	var again := Button.new()
	again.text = "Un altro percorso"
	again.pressed.connect(_preview)
	rand_box.add_child(again)
	# libretto
	var sopt := OptionButton.new()
	var last_group := ""
	var idx_map: Array = []
	for i in stages.size():
		var st: Dictionary = stages[i]
		if st["group"] != last_group:
			sopt.add_separator(st["group"])
			idx_map.append(-1)
			last_group = st["group"]
		sopt.add_item(st["name"])
		idx_map.append(i)
	sopt.fit_to_longest_item = false
	sopt.item_selected.connect(func(k):
		if idx_map[k] >= 0:
			cfg["stage"] = idx_map[k]
			_show_stage())
	sopt.select(1)
	stage_box.add_child(_row("Tappa", sopt))
	# sequenza
	var hint := _label("Scrivi le facce in ordine, ad esempio a b c d e f … u. Maiuscola = lato scuro; Peloton 1 … 9, lato scuro 1B … 9B.", 14, Color(1, 1, 1, 0.7))
	seq_box.add_child(hint)
	var seq := LineEdit.new()
	seq.placeholder_text = "a b c … u"
	seq.text_changed.connect(func(t): _preview_seq_live(t))
	seq_box.add_child(seq)
	# tour
	var topt := OptionButton.new()
	for t in TOURS:
		topt.add_item(t["name"])
	topt.selected = cfg["tour"]
	topt.item_selected.connect(func(k):
		cfg["tour"] = k
		show_mode.call(3)
		_show_tour_preview())
	tour_box.add_child(_row("Tour", topt))
	tour_box.add_child(_row("Fatica", _seg(["Metà passa alla tappa dopo", "Si riparte da zero"], 0 if cfg["carry"] else 1, func(k): cfg["carry"] = k == 0, 13)))
	var rest := _seg(["Sì", "No"], 0 if cfg["rest"] else 1, func(k): cfg["rest"] = k == 0, 13)
	rest.tooltip_text = "Nei tour da 15 tappe o più ci sono sempre due giorni di riposo (dopo la 9ª e la 15ª); nei tour più corti, uno a metà."
	tour_box.add_child(_row("Giorno di riposo", rest))
	var gts := _seg(["No", "Sì: arrivo largo, curva bagnata, rotonde"], 1 if cfg["gt"] else 0, func(k):
		cfg["gt"] = k == 1
		_refresh_preview(), 14)
	gts.tooltip_text = "Tessere di Grand Tour: l'arrivo largo (v/V) sostituisce u/U; nei percorsi casuali possono comparire la curva stretta bagnata (z/Z) e le rotonde (x/X, y/Y)."
	v.add_child(_row("Grand Tour", gts))
	var met := _seg(["No", "Sì: vento e pioggia sui rettilinei"], 1 if cfg["meteo"] else 0, func(k): cfg["meteo"] = k == 1, 14)
	met.tooltip_text = "Espansione Meteo: a ogni tappa i rettilinei (tranne partenza e arrivo) ricevono a caso vento laterale, a favore, contrario o pioggia."
	v.add_child(_row("Meteo", met))
	var sty := _seg(["Normale", "Crono squadre", "Crono individuale", "Tappa lunga"], cfg["stype"], func(k):
		cfg["stype"] = k
		_refresh_preview(), 13)
	sty.tooltip_text = "Tappe speciali del Grand Tour. Con 'Normale', le tappe del libretto che erano cronometro nel Tour 2018 lo restano."
	v.add_child(_row("Tipo di tappa", sty))
	# rilievo
	v.add_child(_row("Rilievo", _seg(RELIEF_NAMES, cfg["relief"], func(k):
		cfg["relief"] = k
		if track != null:
			track.compute_heights(RELIEF[k])
			board.show_track(track), 14)))
	v.add_child(_row("Animazioni", _seg(ANIM_NAMES, cfg["anim"], func(k): _set_anim(k), 14)))
	show_mode.call(cfg["mode"])
	var msg := Label.new()
	msg.name = "Msg"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.add_theme_font_size_override("font_size", 15)
	v.add_child(msg)
	var start := Button.new()
	start.text = "Inizia la corsa"
	start.custom_minimum_size.y = 50
	start.add_theme_font_size_override("font_size", 20)
	var st_on := _style(Color("#C8323C"), 8)
	start.add_theme_stylebox_override("normal", st_on)
	var st_h := _style(Color("#DD4450"), 8)
	start.add_theme_stylebox_override("hover", st_h)
	start.pressed.connect(_start_race)
	v.add_child(start)
	v.add_child(_plain("Versione " + VERSION, 12, Color(1, 1, 1, 0.4)))

## Controlla che immagini e dati delle tessere siano della stessa versione.
func _check_assets() -> void:
	var bad: Array = []
	for id in FacesDB.faces():
		var f := FacesDB.face(id)
		var path: String = "res://assets/" + f["img"]
		var tex: Texture2D = FacesDB.texture(id)
		var size_ok: bool = tex != null and int(tex.get_width()) == int(f["w"]) and int(tex.get_height()) == int(f["h"])
		var md5_ok := true
		if f.has("md5") and FileAccess.file_exists(path):
			md5_ok = FileAccess.get_md5(path).substr(0, 10) == f["md5"]
		if not size_ok or not md5_ok:
			bad.append(id)
	if not bad.is_empty():
		_msg("ATTENZIONE: le immagini di queste tessere non corrispondono ai dati (file di una versione precedente?): %s. Estrai lo zip in una cartella nuova." % " ".join(bad))
		push_warning("Tessere non aggiornate: %s" % " ".join(bad))
	else:
		print("Tessere verificate: %d facce, dati versione %s" % [FacesDB.faces().size(), FacesDB.data().get("version", "?")])

## Schermata iniziale con la copertina: si chiude con un clic, un tocco o un tasto.
func _show_splash() -> void:
	var sp := Control.new()
	sp.set_anchors_preset(Control.PRESET_FULL_RECT)
	sp.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(sp)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(bg)
	var cover := TextureRect.new()
	cover.texture = load("res://assets/copertina.webp")
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.offset_top = 24
	cover.offset_bottom = -96
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(cover)
	var foot := VBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -90
	foot.offset_bottom = -14
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(foot)
	var t1 := _plain("Ultimo chilometro, versione digitale per uso personale (v%s)" % VERSION.split(" ")[0], 20, Color(1, 0.93, 0.8))
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(t1)
	var t2 := _plain("Clicca o premi un tasto per continuare", 16, Color(1, 1, 1, 0.65))
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(t2)
	var blink := create_tween().set_loops()
	blink.tween_property(t2, "modulate:a", 0.25, 0.9)
	blink.tween_property(t2, "modulate:a", 1.0, 0.9)
	var closing := [false]
	var close := func():
		if closing[0]:
			return
		closing[0] = true
		blink.kill()
		var tw := create_tween()
		tw.tween_property(sp, "modulate:a", 0.0, 0.6)
		tw.tween_callback(sp.queue_free)
	sp.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed:
			close.call())
	splash_close = close

func _input(ev: InputEvent) -> void:
	if splash_close.is_valid() and ev is InputEventKey and ev.pressed:
		splash_close.call()
		splash_close = Callable()

func _msg(t: String) -> void:
	(setup_box.find_child("Msg", true, false) as Label).text = t

## Tipo della tappa: scelto nel menu, oppure quello indicato dalla tappa del libretto.
func _stage_type(st: Dictionary = {}) -> String:
	match cfg["stype"]:
		1: return "ttt"
		2: return "itt"
		3: return "ext"
	return st.get("type", "")

func _bw_face() -> String:
	return ("2" if cfg["n"] >= 5 else "2B") if cfg["breakaway"] else ""

func _refresh_preview() -> void:
	match cfg["mode"]:
		0: _preview()
		1: _show_stage()
		3: _show_tour_preview()

func _custom_track() -> bool:
	return cfg["mode"] != 0

func _riders_needed() -> int:
	return cfg["n"] * 2

func _show_tour_preview() -> void:
	var pr: Dictionary = TOURS[cfg["tour"]]
	if pr.has("group"):
		var first: Dictionary = {}
		var n := 0
		for st in stages:
			if st["group"] == pr["group"]:
				n += 1
				if first.is_empty():
					first = st
		_show_preview(first["seq"], false, "%s, %d tappe. Prima tappa: %s" % [pr["name"].split(" (")[0], n, first["name"]])
	else:
		_preview()

func _show_stage() -> void:
	var st: Dictionary = stages[cfg["stage"]]
	var seq: Array = st["seq"]
	if cfg["breakaway"]:
		seq = TrackGenerator.with_breakaway(seq, _bw_face())
	if cfg["gt"]:
		seq = TrackGenerator.with_wide_finish(seq)
	_show_preview(seq, false, st["name"])

func _preview() -> void:
	var seq := TrackGenerator.generate(LENGTH_KEYS[cfg["length"]], cfg["peloton"], null, _riders_needed(), _bw_face(), cfg["gt"])
	if seq.is_empty():
		_msg("Non sono riuscito a generare un percorso, riprova.")
		return
	_show_preview(seq)

## Anteprima dal vivo mentre si scrive la sequenza: ogni faccia riconosciuta viene piazzata subito.
func _preview_seq_live(text: String) -> void:
	var toks := TrackGenerator.parse(text)
	var ok: Array = []
	var bad := ""
	for tk in toks:
		if FacesDB.face(tk).is_empty():
			bad = tk
			break
		ok.append(tk)
	if ok.is_empty():
		_msg("Scrivi le facce separate da spazi, partendo dalla tessera di partenza (a, A, 1 o 1B)." if bad == "" else "Faccia sconosciuta: %s" % bad)
		return
	var t := Track.build(ok, false)
	if t.squares.is_empty():
		_msg(t.error)
		return
	t.compute_heights(RELIEF[cfg["relief"]])
	track = t
	preview_seq = ok
	board.show_track(t)
	var notes: Array = ["%d tessere" % ok.size()]
	if bad != "":
		notes.append("faccia sconosciuta: %s" % bad)
	if t.ok():
		notes.append("%d caselle dalla partenza all'arrivo" % (t.finish + 1 - t.start_count))
		var chk := Track.build(ok, true)
		if not chk.ok():
			notes.append("attenzione: alcune tessere si sovrappongono")
	else:
		notes.append(t.error.trim_suffix(".").to_lower())
	_msg(", ".join(notes).substr(0, 1).to_upper() + ", ".join(notes).substr(1) + ".")

func _preview_seq(text: String) -> void:
	_show_preview(TrackGenerator.parse(text))

func _show_preview(seq: Array, check := true, title := "") -> void:
	if cfg["stype"] == 3:
		seq = TrackGenerator.extend(seq)
	_show_preview_raw(seq, check, title)

func _show_preview_raw(seq: Array, check := true, title := "") -> void:
	var t := Track.build(seq, check)
	if not t.ok():
		_msg(t.error)
		if t.squares.is_empty():
			return
	else:
		_msg("%s%d tessere, %d caselle dalla partenza all'arrivo:\n%s" % [(title + ": ") if title != "" else "", seq.size(), t.finish + 1 - t.start_count, " ".join(seq)])
	track = t
	preview_seq = seq
	t.compute_heights(RELIEF[cfg["relief"]])
	board.show_track(t)

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.11, 0.15, 0.9), 0))
	panel.visible = false
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	status_lbl = Label.new()
	status_lbl.add_theme_font_size_override("font_size", 22)
	v.add_child(status_lbl)
	# comandi sotto il turno; la riga va a capo da sola se il pannello è stretto
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 8)
	top.add_theme_constant_override("v_separation", 6)
	follow_btn = CheckButton.new()
	follow_btn.text = "Segui"
	follow_btn.button_pressed = true
	follow_btn.focus_mode = Control.FOCUS_NONE
	follow_btn.toggled.connect(func(on): board.follow = on)
	top.add_child(follow_btn)
	anim_seg = _seg(ANIM_NAMES, cfg["anim"], func(k): _set_anim(k), 13)
	anim_seg.custom_minimum_size.x = 210
	anim_seg.tooltip_text = "Velocità delle animazioni"
	top.add_child(anim_seg)
	var whole := Button.new()
	whole.text = "Tutto"
	whole.tooltip_text = "Inquadra tutto il percorso"
	whole.focus_mode = Control.FOCUS_NONE
	whole.pressed.connect(func():
		board.follow = false
		follow_btn.set_pressed_no_signal(false)
		board.fit_view())
	top.add_child(whole)
	var menu_b := Button.new()
	menu_b.text = "Menu"
	menu_b.tooltip_text = "Torna al menu di scelta della corsa"
	menu_b.focus_mode = Control.FOCUS_NONE
	menu_b.pressed.connect(_ask_menu)
	top.add_child(menu_b)
	v.add_child(top)
	chips = HFlowContainer.new()
	v.add_child(chips)
	profile = ProfileView.new()
	v.add_child(profile)
	v.add_child(HSeparator.new())
	action = VBoxContainer.new()
	action.add_theme_constant_override("separation", 8)
	v.add_child(action)
	v.add_child(HSeparator.new())
	var lt := Label.new()
	lt.text = "Cronaca"
	lt.add_theme_font_size_override("font_size", 16)
	lt.modulate = Color(1, 1, 1, 0.6)
	v.add_child(lt)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_box.custom_minimum_size.x = 0
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.custom_minimum_size.y = 70
	v.add_child(log_box)


func _build_report() -> void:
	report = PanelContainer.new()
	report.add_theme_stylebox_override("panel", _style(Color(0.08, 0.11, 0.15, 1.0)))
	report.visible = false
	root.add_child(report)

func _build_overlay() -> void:
	overlay = PanelContainer.new()
	overlay.add_theme_stylebox_override("panel", _style(Color(0.08, 0.11, 0.15, 0.97)))
	overlay.visible = false
	root.add_child(overlay)

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x >= vs.y:
		var sw: float = clampf(vs.x * 0.42, 440.0, 600.0)
		setup_box.position = Vector2(16, 16)
		setup_box.size = Vector2(sw, vs.y - 32)
	else:
		setup_box.position = Vector2(12, vs.y * 0.42)
		setup_box.size = Vector2(vs.x - 24, vs.y * 0.58 - 12)
	if vs.x >= vs.y:
		var w := clampf(vs.x * 0.3, 340, 430)
		panel.position = Vector2(vs.x - w, 0)
		panel.size = Vector2(w, vs.y)
		board.screen_shift = Vector2(w / vs.x, 0) if panel.visible else Vector2(-(setup_box.size.x + 16.0) / vs.x, 0)
	else:
		var h := vs.y * 0.46
		panel.position = Vector2(0, vs.y - h)
		panel.size = Vector2(vs.x, h)
		board.screen_shift = Vector2(0, h / vs.y) if panel.visible else Vector2(0, -0.58)
	if report:
		report.position = Vector2(16, 16)
		report.size = vs - Vector2(32, 32)
	overlay.size = Vector2.ZERO
	overlay.position = (vs - overlay.get_combined_minimum_size()) / 2

func _clear_action() -> void:
	for c in action.get_children():
		c.queue_free()

func _label(t: String, size := 18, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	return l

func _hex(c: Color) -> String:
	return c.to_html(false)

func _rname(r: Dictionary) -> String:
	var c: Color = r["team"]["color"]
	if c.get_luminance() < 0.2:
		c = Color("#9AA4AE")
	return "[color=#%s]%s[/color]" % [_hex(c), Rules.rider_name(r)]

func log_line(t: String) -> void:
	log_box.append_text(t + "\n")

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

# ---------- corsa ----------

func _kinds() -> Array:
	var kinds: Array = []
	for i in cfg["n"]:
		kinds.append(Rules.KINDS[cfg["kind"][i]])
	return kinds

static func _slots(t: Track) -> int:
	var n := 0
	for p in t.start_count:
		n += t.cap(p)
	return n

func _start_race() -> void:
	var kinds := _kinds()
	if kinds.count("peloton") > 1:
		_msg("Può esserci una sola Squadra Peloton.")
		return
	tour = {}
	if cfg["mode"] == 3:
		var list := _tour_stages()
		if list.is_empty():
			_msg("Non sono riuscito a preparare le tappe del tour.")
			return
		var worst := 99
		for st in list:
			worst = mini(worst, _slots(Track.build(st["seq"], false)))
		if worst < cfg["n"] * 2:
			_msg("In questo tour c'è una partenza con %d posti: con %d squadre servono %d posti. Riduci le squadre." % [worst, cfg["n"], cfg["n"] * 2])
			return
		tour = {"stages": list, "idx": 0, "times": [], "sprint": [], "mountain": [], "carry": [], "last": [],
			"podium_tp": [], "rest_tp": [], "bonus_tp": [], "team_times": [], "results": [], "jerseys": {}, "rest_after": []}
		for i in cfg["n"] * 2:
			for k in ["times", "sprint", "mountain", "carry", "last"]:
				tour[k].append(0)
		for i in cfg["n"]:
			for k in ["podium_tp", "rest_tp", "bonus_tp", "team_times"]:
				tour[k].append(0)
		var ns: int = list.size()
		if ns >= 15:
			tour["rest_after"] = [8, 14]          # dopo la 9ª e la 15ª tappa
		elif cfg["rest"]:
			tour["rest_after"] = [(ns - 1) / 2]
	else:
		if track == null or not track.ok():
			_msg("Serve un percorso valido prima di iniziare.")
			return
		if _slots(track) < cfg["n"] * 2:
			_msg("La partenza ha %d posti per %d corridori: con 5 o 6 squadre serve la partenza di Peloton (1 o 1B)." % [_slots(track), cfg["n"] * 2])
			return
	race_id += 1
	setup_box.visible = false
	panel.visible = true
	for i in anim_seg.get_child_count():
		(anim_seg.get_child(i) as Button).set_pressed_no_signal(i == cfg["anim"])
	_set_anim(cfg["anim"])
	_layout()
	_begin_stage()

## Lista delle tappe del tour scelto (nome e sequenza).
func _tour_stages() -> Array:
	var pr: Dictionary = TOURS[cfg["tour"]]
	var out: Array = []
	if pr.has("group"):
		for st in stages:
			if st["group"] == pr["group"]:
				var sq: Array = st["seq"]
				if cfg["breakaway"]:
					sq = TrackGenerator.with_breakaway(sq, _bw_face())
				if cfg["gt"]:
					sq = TrackGenerator.with_wide_finish(sq)
				out.append({"name": st["name"], "seq": sq})
	else:
		for k in int(pr["random"]):
			var seq := TrackGenerator.generate(["media", "lunga"][k % 2], cfg["peloton"], null, _riders_needed(), _bw_face(), cfg["gt"])
			if seq.is_empty():
				return []
			out.append({"name": "", "seq": seq})
	return out

func _begin_stage() -> void:
	stage_title = "Tappa"
	var carry: Array = []
	var order: Array = []
	var stype := ""
	if not tour.is_empty():
		var st: Dictionary = tour["stages"][tour["idx"]]
		stype = _stage_type(st)
		var sq: Array = st["seq"]
		if stype == "ext":
			sq = TrackGenerator.extend(sq)
		track = Track.build(sq, false)
		track.compute_heights(RELIEF[cfg["relief"]])
		preview_seq = st["seq"]
		stage_title = "Tappa %d di %d" % [tour["idx"] + 1, tour["stages"].size()]
		var own := "Tappa %d" % (tour["idx"] + 1)
		if st["name"].begins_with(own):
			stage_title += st["name"].substr(own.length())     # es. "(cronometro)"
		elif st["name"] != "":
			stage_title += ": " + st["name"]
		if cfg["carry"]:
			carry = tour["carry"]
	elif cfg["mode"] == 1:
		stage_title = stages[cfg["stage"]]["name"]
		stype = _stage_type(stages[cfg["stage"]])
	else:
		stype = _stage_type()
	R = Rules.new()
	R.setup(track, _kinds(), cfg["exh"] if tour.is_empty() or tour["idx"] == 0 else 0, not cfg["free_start"], carry)
	var lv: Array = CPU_LEVELS[cfg["cpu"]]
	for t in R.teams:
		if t["kind"] == "cpu":
			t["level"] = lv[0]
			t["samples"] = lv[1]
			t["budget"] = lv[2]
	R.tt = stype if stype == "ttt" or stype == "itt" else ""
	if R.tt == "":
		R.place_tokens()
	if stype == "ext" or stype == "lunga":
		R.place_refresh()
	if R.tt != "":
		# cronometro: tutti nella casella subito dietro la linea di partenza, ogni squadra per conto suo
		for t in R.teams:
			for k in t["riders"].size():
				t["riders"][k]["pos"] = track.start_count - 1
				t["riders"][k]["lane"] = mini(k, track.cap(track.start_count - 1) - 1)
	if cfg["meteo"]:
		R.deal_weather()
	board.show_track(track)
	board.show_weather(R.weather_tiles)
	board.tt_mode = R.tt != ""
	board.tt_teams = R.teams.size()
	board.make_tokens(R.riders)
	board.show_refresh(R.refresh_sq)
	board.update_piles(R.piles)
	if not tour.is_empty():
		board.set_jerseys(tour.get("jerseys", {}))
	var placed := R.riders.filter(func(r): return r["pos"] >= 0)
	board.focus(board.pack_center(placed) if not placed.is_empty() else _start_center(), 10.0)
	log_box.clear()
	log_line("[b]%s[/b]: %d caselle all'arrivo." % [stage_title, track.finish + 1 - track.start_count])
	log_line("[color=#9AA4AE]Versione %s. Percorso: %s. Rilievo: %s.[/color]" % [VERSION, " ".join(preview_seq), RELIEF_NAMES[cfg["relief"]]])
	match stype:
		"ttt":
			log_line("[b]Cronometro a squadre[/b]: ogni squadra corre da sola (le altre non contano per movimento, scia e fatica); entrambi i corridori prendono il tempo del più lento; al massimo un podio a squadra.")
		"itt":
			log_line("[b]Cronometro individuale[/b]: nessuna scia, nemmeno dal compagno; a ogni turno la fatica va al rouleur e allo sprinteur che giocano la carta più alta.")
		"ext", "lunga":
			log_line("[b]Tappa lunga[/b]: %s" % ("quattro rettilinei in più. " if stype == "ext" else "") + " il primo che raggiunge il ristoro prende il gettone, e tutti recuperano carte giocate fino a 24 punti (25 per chi ha il gettone).")
	if cfg["meteo"]:
		var wnames := {"laterale": "vento laterale (niente scia)", "favore": "vento a favore (5 carte)", "contrario": "vento contrario (3 carte)", "bagnato": "strada bagnata (cadute)"}
		if R.weather_tiles.is_empty():
			log_line("[color=#9AA4AE]Meteo: bel tempo su tutto il percorso.[/color]")
		for wt in R.weather_tiles:
			var pc: Dictionary = track.pieces[wt["piece"]]
			var a: int = int(pc["s0"]) + 1 - track.start_count
			log_line("[color=#9AA4AE]Meteo: %s sulla tessera %s (caselle %d–%d dalla partenza).[/color]" % [wnames[wt["kind"]], pc["id"], a, a + 5])
	if not tour.is_empty() and cfg["carry"] and tour["idx"] > 0:
		log_line("[color=#9AA4AE]Ogni corridore riparte con metà delle carte fatica della tappa precedente.[/color]")
	profile.refresh(track, R.riders)
	if cfg["free_start"] and R.tt == "":
		# nel tour si schiera per prima la squadra più attardata in classifica
		var teams_order: Array = R.teams.duplicate()
		if not tour.is_empty() and tour["idx"] > 0:
			teams_order.sort_custom(func(x, y):
				var tx: int = _team_tp(x["idx"])
				var ty: int = _team_tp(y["idx"])
				if tx != ty:
					return tx < ty
				# a parità perde lo spareggio (si schiera dopo) chi ha il corridore meglio piazzato in classifica
				return _best_gc(x) > _best_gc(y))
		var my := race_id
		await _placement(teams_order)
		if my != race_id:
			return
	if cfg["breakaway"] and R.tt == "" and R.breakaway_square() >= 0:
		var my2 := race_id
		await _breakaway()
		if my2 != race_id:
			return
	history = []
	_snapshot("start")
	_race_loop()

func _snapshot(phase: String) -> void:
	history.append({"round": R.round, "phase": phase, "s": R.riders.map(func(r): return [r["pos"], r["lane"]])})

func _update_status() -> void:
	status_lbl.text = "Turno %d (v%s)" % [R.round, VERSION.split(" ")[0]]
	profile.refresh(track, R.riders)
	for c in chips.get_children():
		c.queue_free()
	var rank := R.ranking()
	for i in rank.size():
		var r: Dictionary = rank[i]
		var pc := PanelContainer.new()
		var sb := _style(r["team"]["color"], 6)
		sb.border_color = Color(1, 1, 1, 0.5)
		sb.set_border_width_all(1)
		sb.set_content_margin_all(4)
		pc.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = "%d %s" % [i + 1, Rules.letter(r)]
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", r["team"]["text"])
		pc.add_child(l)
		pc.tooltip_text = "%s: a %d dall'arrivo, fatica %d" % [Rules.rider_name(r), R.dist_to_finish(r), R.exh_count(r)]
		chips.add_child(pc)

func _race_loop() -> void:
	var my := race_id
	while true:
		R.round += 1
		_update_status()
		log_line("[b]Turno %d[/b]" % R.round)
		var humans := 0
		for t in R.teams:
			if t["human"] and not R.active(t).is_empty():
				humans += 1
		# il computer sceglie per primo: così non può mai conoscere le carte già scelte dai giocatori
		var choosers: Array = R.teams.filter(func(t): return not t["human"]) + R.teams.filter(func(t): return t["human"])
		var cpu_thinking := false
		for t in choosers:
			var act: Array = R.active(t)
			if act.is_empty():
				continue
			if t["human"] and cpu_thinking:
				cpu_thinking = false
				_update_status()
			if not t["human"] and t["kind"] == "cpu" and int(t.get("level", 1)) >= 2 and not cpu_thinking:
				cpu_thinking = true
				status_lbl.text = "Turno %d: il computer ci pensa…" % R.round
				await get_tree().process_frame
				await get_tree().process_frame
				if my != race_id:
					return
			if t["human"]:
				if humans > 1:
					await _pass_device(t)
					if my != race_id:
						return
				var order: Array = act
				if act.size() == 2:
					var first: Dictionary = await _ask_order(t)
					if my != race_id:
						return
					order = [first, act[1] if first == act[0] else act[0]]
				var prev = null
				for r in order:
					R.draw_hand(r)
					board.highlight(r)
					var c: Dictionary = await _ask_card(r, prev)
					if my != race_id:
						return
					R.choose(r, c)
					prev = r
				board.highlight(null)
			elif t["kind"] == "cpu":
				for r in act:
					R.draw_hand(r)
					R.choose(r, R.ai_pick(r))
		if cpu_thinking:
			_update_status()
		R.dummy_cards()
		_show_reveal()
		await _wait(0.7)
		if my != race_id:
			return
		for r in R.movement_order():
			var res := R.move_rider(r)
			var tag := " (fatica)" if r["chosen"]["ex"] else (" (Attacco!)" if r["chosen"].get("attack", false) else (" (Muscolo)" if r["chosen"].get("muscle", false) else ""))
			var txt := "%s gioca %d%s" % [_rname(r), res["card"], tag]
			if res["eff"] != res["card"]:
				txt += ", il terreno lo porta a %d" % res["eff"]
			if res.get("stood", false):
				txt += ", si rialza (carta −2)"
			if res["lost"] > 0:
				txt += ": strada chiusa, perde %s" % ("1 casella" if res["lost"] == 1 else "%d caselle" % res["lost"])
			if res.get("crash", false):
				txt += " [b]e cade sul bagnato![/b]"
			log_line(txt + ".")
			await board.move_along(r, res["from"], res["to"], res.get("path", []))
			if my != race_id:
				return
			await _wait(board.step_time * 0.5)
			if my != race_id:
				return
		_snapshot("move")
		var moved := R.slipstream()
		if not moved.is_empty():
			for r in moved:
				board.place(r)
			log_line("Scia: " + ", ".join(moved.map(func(r): return _rname(r))) + ".")
			await _wait(board.step_time * 1.7)
			if my != race_id:
				return
		_snapshot("slip")
		var rf := R.check_refresh()
		if not rf.is_empty():
			log_line("[b]Ristoro[/b]: %s prende il gettone. Recupero delle carte giocate:" % _rname(R.refresh_holder))
			for x in rf:
				if not x["cards"].is_empty():
					log_line("   %s riprende %s (%d punti)." % [_rname(x["rider"]), ", ".join(x["cards"].map(func(v): return str(v))), x["total"]])
			board.show_refresh(-1)
		for g in R.collect_tokens():
			log_line("%s prende %d punti %s (%s)." % [_rname(g["rider"]), g["v"], "montagna" if g["mountain"] else "sprint", "Major" if g["major"] else "Minor"])
		board.update_piles(R.piles)
		var arrived := R.record_finishers()
		for r in arrived:
			if r["fin_place"] == 1:
				log_line("[b]%s vince la tappa![/b]" % _rname(r))
			else:
				log_line("%s taglia il traguardo, %d° arrivato." % [_rname(r), r["fin_place"]])
		R.add_time_tokens()
		var tired := R.exhaustion()
		for r in tired:
			board.flash_tired(r)
		if not tired.is_empty():
			log_line("Fatica per chi tira: " + ", ".join(tired.map(func(r): return _rname(r))) + ".")
		for r in R.remove_finished():
			board.finish_token(r)
		_snapshot("finish")
		_update_status()
		if R.all_finished() or R.round >= 150:
			await _wait(0.8)
			if my != race_id:
				return
			_show_report()
			return
		if humans > 0:
			await _ask_next()
			if my != race_id:
				return
		else:
			await _wait(1.0)
			if my != race_id:
				return

## Schieramento: a turno ogni squadra piazza i suoi due corridori dietro la linea di partenza.
func _placement(teams_order: Array) -> void:
	var my := race_id
	log_line("[b]Schieramento[/b]: le squadre automatiche sono già in posizione.")
	board.focus(_start_center(), 8.0)
	for t in teams_order:
		var todo: Array = t["riders"].filter(func(r): return r["pos"] < 0)
		while not todo.is_empty():
			var r: Dictionary
			if t["human"]:
				var res = await _ask_place(t, todo)
				if my != race_id:
					return
				r = res[0]
				R.place_start(r, res[1])
			else:
				r = todo[0]
				R.place_start(r, R.ai_start_square(r))
			board.place(r, false)
			profile.refresh(track, R.riders)
			todo.erase(r)
	board.clear_pick()

func _start_center() -> Vector3:
	var p := track.lane_pos(maxi(0, track.start_count / 2), 0)
	return Vector3(p.x, 0, p.y)

func _ask_place(t: Dictionary, todo: Array) -> Array:
	var sel: Array = [todo[0]]
	while true:
		_clear_action()
		action.add_child(_label("%s: schiera i corridori" % t["name"], 20))
		action.add_child(_label("Scegli il corridore, poi tocca una casella dietro la linea di partenza (i dischi gialli).", 15, Color(1, 1, 1, 0.75)))
		var row := HBoxContainer.new()
		for r in todo:
			var b := Button.new()
			b.text = Rules.role(r)
			b.toggle_mode = true
			b.button_pressed = r == sel[0]
			b.custom_minimum_size = Vector2(140, 44)
			b.pressed.connect(func(): choice.emit({"rider": r}))
			row.add_child(b)
		action.add_child(row)
		board.show_pick(R.free_start_squares(), R.riders)
		var got = await _next_place_event()
		if got is Dictionary:
			sel[0] = got["rider"]
		else:
			return [sel[0], int(got)]
	return []

func _next_place_event():
	var result := [null]
	var on_sq := func(sq):
		result[0] = sq
		choice.emit(null)
	board.square_clicked.connect(on_sq)
	var v = await choice
	board.square_clicked.disconnect(on_sq)
	return v if v != null else result[0]

# ---------- carte e plance scansionate ----------

const CARD_RATIO := 1.553

func _card_tex(r: Dictionary, c: Dictionary) -> Texture2D:
	var l: String = Rules.letter(r).to_lower()
	if c.get("ex", false):
		return load("res://assets/carte/%s_fatica.webp" % l)
	return load("res://assets/carte/%s_%s.webp" % [l, r["team"]["name"].to_lower()])

func _num_color(r: Dictionary) -> Color:
	return Color("#1E1E1E") if r["team"]["name"] == "Bianchi" else r["team"]["color"]

## Carta disegnata con la scansione: il valore viene scritto negli angoli in alto.
func _card_view(r: Dictionary, c: Dictionary, w: float, note := "") -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(w, w * CARD_RATIO)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = _card_tex(r, c)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	if not c.get("ex", false):
		for k in 2:
			var n := Label.new()
			n.text = str(c["v"])
			n.add_theme_font_size_override("font_size", int(w * 0.25))
			n.add_theme_color_override("font_color", _num_color(r))
			n.add_theme_color_override("font_outline_color", Color.WHITE)
			n.add_theme_constant_override("outline_size", maxi(3, int(w * 0.06)))
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			n.size = Vector2(w * 0.22, w * 0.32)
			n.position = Vector2(w * 0.035 if k == 0 else w * 0.745, -w * 0.02)
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(n)
	if note != "":
		var tag := Label.new()
		tag.text = note
		tag.add_theme_font_size_override("font_size", maxi(11, int(w * 0.15)))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.1, 0.13, 0.85)
		sb.set_corner_radius_all(4)
		tag.add_theme_stylebox_override("normal", sb)
		tag.position = Vector2(0, w * CARD_RATIO * 0.62)
		tag.size = Vector2(w, w * 0.22)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tag)
	return box

## Plancia della squadra: sprinteur a sinistra, rouleur a destra.
## Sotto ogni figura, in colonna: distanza dall'arrivo, mazzo, riciclo e fatica.
## Con selectable le figure diventano pulsanti per scegliere il corridore; active ha il bordo acceso.
func _board_view(t: Dictionary, active = null, selectable := false) -> Control:
	var tex: Texture2D = load("res://assets/carte/plancia_%s.png" % t["name"].to_lower())
	var w: float = maxf(260.0, panel.size.x - 60.0)
	var h: float = w * tex.get_height() / tex.get_width()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var box := Control.new()
	box.custom_minimum_size = Vector2(w, h)
	col.add_child(box)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.size = Vector2(w, h)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tr)
	var info_row := Control.new()
	info_row.custom_minimum_size = Vector2(w, 78)
	col.add_child(info_row)
	if slots.is_empty():
		slots = JSON.parse_string(FileAccess.get_file_as_string("res://assets/carte/plance.json"))
	var sd: Dictionary = slots[t["name"].to_lower()]
	for r in t["riders"]:
		var q: Array = sd["R" if r["type"] == "P" else "S"]
		var slot := Rect2(q[0] * w, q[1] * h, q[2] * w, q[3] * h)
		var cx: float = slot.get_center().x
		var done: bool = r["finished"]
		if done:
			var veil := ColorRect.new()
			veil.color = Color(0, 0, 0, 0.55)
			veil.position = slot.position
			veil.size = slot.size
			veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(veil)
		if selectable and not done:
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.position = slot.position
			b.size = slot.size
			b.tooltip_text = "Pesca per primo per il %s" % Rules.role(r).to_lower()
			var idle := StyleBoxFlat.new()
			idle.draw_center = false
			idle.border_color = Color(1, 1, 1, 0.7)
			idle.set_border_width_all(3)
			idle.set_corner_radius_all(6)
			idle.expand_margin_left = 3
			idle.expand_margin_right = 3
			idle.expand_margin_top = 3
			idle.expand_margin_bottom = 3
			var hot := idle.duplicate()
			hot.border_color = Color("#FFD24D")
			hot.set_border_width_all(7)
			hot.bg_color = Color(1, 0.85, 0.3, 0.12)
			hot.draw_center = true
			b.add_theme_stylebox_override("normal", idle)
			b.add_theme_stylebox_override("hover", hot)
			b.add_theme_stylebox_override("pressed", hot)
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.mouse_entered.connect(func(): board.highlight(r))
			b.pressed.connect(func(): choice.emit(r))
			box.add_child(b)
		elif active != null and r == active:
			var fr := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.border_color = Color("#FFD24D")
			sb.set_border_width_all(7)
			sb.set_corner_radius_all(6)
			sb.expand_margin_left = 3
			sb.expand_margin_right = 3
			sb.expand_margin_top = 3
			sb.expand_margin_bottom = 3
			fr.add_theme_stylebox_override("panel", sb)
			fr.position = slot.position
			fr.size = slot.size
			fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(fr)
		var info := Label.new()
		if done:
			info.text = "%s\narrivato" % Rules.role(r)
		else:
			info.text = "%s\na %d dall'arrivo\nMazzo %d · Riciclo %d\nFatica %d" % [Rules.role(r), R.dist_to_finish(r), r["deck"].size(), r["recycled"].size(), R.exh_count(r)]
		info.add_theme_font_size_override("font_size", 12)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.modulate = Color(1, 1, 1, 1.0 if (active == null or r == active) else 0.6)
		info.size = Vector2(w * 0.44, 78)
		info.position = Vector2(clampf(cx - w * 0.22, 0.0, w * 0.56), 0)
		info_row.add_child(info)
	return col

## Variante Breakaway: due offerte per squadra, la somma più alta va in fuga.
func _breakaway() -> void:
	var my := race_id
	var bidders: Array = R.teams.filter(func(t): return t["kind"] == "human" or t["kind"] == "cpu")
	var winners_n := 2 if cfg["n"] >= 5 else 1
	var humans := bidders.filter(func(t): return t["human"]).size()
	var who := {}
	var bids := {}
	log_line("[b]Fuga[/b]: ogni squadra fa due offerte per mandare un corridore in fuga (%s)." % ("vanno in fuga i due migliori" if winners_n == 2 else "va in fuga il migliore"))
	for k in 2:
		for t in bidders:
			var r: Dictionary
			if t["human"]:
				if humans > 1:
					await _pass_device(t)
					if my != race_id:
						return
				if k == 0:
					r = await _ask_order(t, "%s: chi tenta la fuga?" % t["name"], "Tocca il corridore che proverà ad andare in fuga: per lui farai due offerte, pescando ogni volta 4 carte.")
					if my != race_id:
						return
					who[t["idx"]] = r
				r = who[t["idx"]]
				R.draw_hand(r)
				board.highlight(r)
				var c: Dictionary = await _ask_card(r, null, "Fuga, offerta %d di 2: %s" % [k + 1, Rules.rider_name(r)])
				if my != race_id:
					return
				R.choose(r, c)
				board.highlight(null)
			else:
				if k == 0:
					who[t["idx"]] = t["riders"][0] if R.rng.randf() < 0.7 else t["riders"][1]
				r = who[t["idx"]]
				R.draw_hand(r)
				var so_far: int = bids[r["id"]][0]["v"] if bids.has(r["id"]) else 0
				var c2 := R.ai_bid(r, k, so_far)
				R.choose(r, c2)
			if not bids.has(r["id"]):
				bids[r["id"]] = []
			bids[r["id"]].append(r["chosen"])
	var list: Array = []
	for id in bids:
		list.append({"rider": R.riders[id], "cards": bids[id]})
	var lines: Array = []
	for b in list:
		lines.append("%s %d+%d=%d" % [_rname(b["rider"]), b["cards"][0]["v"], b["cards"][1]["v"], b["cards"][0]["v"] + b["cards"][1]["v"]])
	log_line("Offerte: " + ", ".join(lines) + ".")
	var won := R.resolve_breakaway(list, winners_n)
	for r in won:
		board.place(r)
	log_line("[b]In fuga[/b]: " + ", ".join(won.map(func(r): return _rname(r))) + ". Due carte fatica a testa.")
	_clear_action()
	action.add_child(_label("In fuga: " + ", ".join(won.map(func(r): return Rules.rider_name(r))), 20))
	action.add_child(_label("Offerte: " + ", ".join(list.map(func(b): return "%s %d" % [Rules.rider_name(b["rider"]), b["cards"][0]["v"] + b["cards"][1]["v"]])), 14, Color(1, 1, 1, 0.75)))
	if not won.is_empty():
		board.focus(board.token_pos(won[0]), 7.0)
	if humans > 0:
		await _ask_next()
	else:
		await _wait(1.5)

func _ask_order(t: Dictionary, title := "", hint := "") -> Dictionary:
	_clear_action()
	action.add_child(_label(title if title != "" else "%s: per chi peschi per primo?" % t["name"], 20))
	action.add_child(_label(hint if hint != "" else "Tocca la figura del corridore sulla plancia: sceglierai la sua carta e poi pescherai per l'altro sapendo cosa gli hai dato.", 14, Color(1, 1, 1, 0.7)))
	action.add_child(_board_view(t, null, true))
	board.highlight(t["riders"][0])
	return await choice

func _terrain_hint(r: Dictionary) -> String:
	var tags: Array = []
	var p: int = r["pos"]
	var t0 := track.terrain(p)
	if t0 == "up":
		tags.append("in salita: massimo 5")
	elif t0 == "down":
		tags.append("in discesa: almeno 5")
	elif t0 == "supply":
		tags.append("nel rifornimento: almeno 4")
	var ahead: Array = []
	for k in range(1, 10):
		ahead.append(track.terrain(p + k))
	if t0 != "up" and ahead.has("up"):
		tags.append("salita in vista")
	if ahead.has("cobble"):
		tags.append("pavé in vista")
	tags.append("%d caselle all'arrivo" % R.dist_to_finish(r))
	var s := "; ".join(tags)
	return s.substr(0, 1).to_upper() + s.substr(1) + "."

func _ask_card(r: Dictionary, prev, title := "") -> Dictionary:
	_clear_action()
	action.add_child(_label(title if title != "" else "%s: scegli una carta" % Rules.rider_name(r), 20))
	action.add_child(_board_view(r["team"], r))
	var pv := ""
	if prev != null:
		pv = "Al %s hai dato %d. " % [Rules.role(prev).to_lower(), prev["chosen"]["v"]]
	action.add_child(_label(pv + _terrain_hint(r), 15, Color(1, 1, 1, 0.75)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var cw: float = clampf((panel.size.x - 60.0) / maxf(4.0, r["hand"].size()), 52.0, 92.0)
	for c in r["hand"]:
		var m := R.eff_move(r, c["v"])
		var land := R.landing(r, m)
		var b := Button.new()
		b.flat = true
		b.custom_minimum_size = Vector2(cw, cw * CARD_RATIO)
		b.focus_mode = Control.FOCUS_NONE
		var view := _card_view(r, c, cw, ("muove %d" % m) if m != c["v"] else "")
		b.add_child(view)
		b.mouse_entered.connect(func():
			view.position.y = -8
			board.show_target(r["pos"], land["pos"], R.first_lane(land["pos"], r), land["lost"] > 0))
		b.mouse_exited.connect(func():
			view.position.y = 0
			board.clear_target())
		b.tooltip_text = "Arriverebbe a %d dall'arrivo%s" % [maxi(0, track.finish + 1 - land["pos"]), (", perdendo %d caselle" % land["lost"]) if land["lost"] > 0 else ""]
		b.pressed.connect(func(): choice.emit(c))
		row.add_child(b)
	action.add_child(row)
	var picked = await choice
	board.clear_target()
	return picked

func _show_reveal() -> void:
	_clear_action()
	action.add_child(_label("Carte rivelate", 20))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for r in R.on_track():
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		v.add_child(_card_view(r, r["chosen"], 52))
		var l := _plain(Rules.letter(r) + " " + r["team"]["name"], 11, Color(1, 1, 1, 0.8))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		flow.add_child(v)
	action.add_child(flow)

func _ask_next() -> void:
	var b := Button.new()
	b.text = "Turno successivo"
	b.custom_minimum_size.y = 44
	b.pressed.connect(func(): choice.emit(true))
	action.add_child(b)
	await choice

func _pass_device(t: Dictionary) -> void:
	_clear_action()
	action.add_child(_label("Cambio giocatore: le carte restano coperte.", 16))
	for c in overlay.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_child(_label("Tocca ai %s" % t["name"], 30))
	v.add_child(_label("Passa il dispositivo al giocatore dei %s. Gli altri non guardano." % t["name"], 17))
	var b := Button.new()
	b.text = "Sono pronto"
	b.pressed.connect(func(): choice.emit(true))
	v.add_child(b)
	overlay.add_child(v)
	overlay.visible = true
	_layout()
	await choice
	overlay.visible = false

# ---------- resoconto, tour e replay ----------

static func fmt_time(sec: int) -> String:
	var sgn := "-" if sec < 0 else ""
	sec = absi(sec)
	if sec >= 3600:
		return "%s%d:%02d:%02d" % [sgn, sec / 3600, (sec / 60) % 60, sec % 60]
	return "%s%d:%02d" % [sgn, sec / 60, sec % 60]

static func fmt_gap(sec: int) -> String:
	return "—" if sec == 0 else "+" + fmt_time(sec)

func _plain(t: String, size := 16, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	return l

## Quadratino del colore di squadra con bordo chiaro (visibile anche per i Neri).
func _swatch(c: Color) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = Color(1, 1, 1, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(14, 14)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p

func _team_cell(t: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_child(_swatch(t["color"]))
	h.add_child(_plain(" " + t["name"]))
	return h

func _table(headers: Array, rows: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = headers.size()
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 4)
	for h in headers:
		g.add_child(_plain(h, 14, Color(1, 1, 1, 0.55)))
	for row in rows:
		for cell in row:
			g.add_child(cell if cell is Control else _plain(str(cell)))
	return g

func _rider_cell(r: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_child(_swatch(r["team"]["color"]))
	h.add_child(_plain(" " + Rules.rider_name(r)))
	return h

# ---------- classifiche del Grand Tour ----------

const BONUS_TABLE := {
	"gc": [[3, 2, 1], [4, 3, 2, 1], [5, 4, 3, 2, 1]],
	"tc": [[1], [2, 1], [3, 2, 1]],
	"sc": [[2, 1], [3, 2, 1], [4, 3, 2, 1]],
	"mc": [[2, 1], [3, 2, 1], [4, 3, 2, 1]],
}

func _team_tp(i: int) -> int:
	return tour["podium_tp"][i] + tour["rest_tp"][i] + tour["bonus_tp"][i]

## Posizione in classifica generale del miglior corridore della squadra.
func _best_gc(t: Dictionary) -> int:
	var order := _gc_order()
	var best := 999
	for r in t["riders"]:
		best = mini(best, order.find(r["id"]))
	return best

## Spareggio di tutte le classifiche: chi ha tagliato prima il traguardo nell'ultima tappa.
func _gc_order() -> Array:
	var ids: Array = range(R.riders.size())
	ids.sort_custom(func(x, y): return tour["times"][x] < tour["times"][y] or (tour["times"][x] == tour["times"][y] and tour["last"][x] < tour["last"][y]))
	return ids

func _points_order(key: String) -> Array:
	var ids: Array = range(R.riders.size())
	ids.sort_custom(func(x, y): return tour[key][x] > tour[key][y] or (tour[key][x] == tour[key][y] and tour["last"][x] < tour["last"][y]))
	return ids

## Maglie: gialla (tempo), verde (sprint), a pois (montagna); un corridore ne porta una sola.
func _award_jerseys() -> Dictionary:
	var j := {}
	var used: Array = []
	var gc := _gc_order()
	j["gc"] = gc[0]
	used.append(gc[0])
	for kv in [["sc", "sprint"], ["mc", "mountain"]]:
		for id in _points_order(kv[1]):
			if tour[kv[1]][id] <= 0:
				break
			if not used.has(id):
				j[kv[0]] = id
				used.append(id)
				break
	return j

func _leaders() -> Array:
	var out: Array = [_gc_order()[0]]
	for key in ["sprint", "mountain"]:
		var o := _points_order(key)
		if tour[key][o[0]] > 0:
			out.append(o[0])
	return out

## Punti bonus di fine tour secondo la tabella del regolamento.
func _end_bonus() -> Array:
	var ns: int = tour["stages"].size()
	var col := 0 if ns <= 7 or R.teams.size() == 2 else (1 if ns <= 14 else 2)
	var lines: Array = []
	var gc := _gc_order()
	var tbl: Array = BONUS_TABLE["gc"][col]
	for i in mini(tbl.size(), gc.size()):
		var r: Dictionary = R.riders[gc[i]]
		tour["bonus_tp"][r["team"]["idx"]] += tbl[i]
		lines.append("Generale %d°: %s +%d" % [i + 1, Rules.rider_name(r), tbl[i]])
	var tids: Array = range(R.teams.size())
	tids.sort_custom(func(x, y): return tour["team_times"][x] < tour["team_times"][y])
	tbl = BONUS_TABLE["tc"][col]
	for i in mini(tbl.size(), tids.size()):
		tour["bonus_tp"][tids[i]] += tbl[i]
		lines.append("Squadre %d°: %s +%d" % [i + 1, R.teams[tids[i]]["name"], tbl[i]])
	for kv in [["sc", "sprint", "Sprint"], ["mc", "mountain", "Montagna"]]:
		var o := _points_order(kv[1])
		tbl = BONUS_TABLE[kv[0]][col]
		for i in mini(tbl.size(), o.size()):
			if tour[kv[1]][o[i]] <= 0:
				break
			var r: Dictionary = R.riders[o[i]]
			tour["bonus_tp"][r["team"]["idx"]] += tbl[i]
			lines.append("%s %d°: %s +%d" % [kv[2], i + 1, Rules.rider_name(r), tbl[i]])
	return lines

func _jersey_of(id: int) -> String:
	for k in tour.get("jerseys", {}):
		if tour["jerseys"][k] == id:
			return k
	return ""

const JERSEY_NAMES := {"gc": "maglia gialla", "sc": "maglia verde", "mc": "maglia a pois"}
const JERSEY_COLORS := {"gc": Color("#F2C200"), "sc": Color("#2E9E4A"), "mc": Color("#F4F1EA")}

func _rider_cell_j(r: Dictionary) -> Control:
	var h := _rider_cell(r)
	var j := _jersey_of(r["id"]) if not tour.is_empty() else ""
	if j != "":
		var tag := _plain("  " + JERSEY_NAMES[j], 12, JERSEY_COLORS[j])
		h.add_child(tag)
	return h

func _show_report() -> void:
	_clear_action()
	board.follow = false
	var rank := R.ranking()
	var times: Array = []
	for r in R.riders:
		times.append(R.stage_time(r))
	var best: int = times.min()
	var bonus_lines: Array = []
	var rest_note := ""
	if not tour.is_empty():
		for r in R.riders:
			var id: int = r["id"]
			tour["times"][id] += times[id]
			tour["sprint"][id] += r["sprint"]
			tour["mountain"][id] += r["mountain"]
			tour["last"][id] = r["fin_place"]
			tour["podium_tp"][r["team"]["idx"]] += r["tp"]
			tour["carry"][id] = R.carry_exhaustion(r) if not R.is_dummy(r) else 0
		for t in R.teams:
			tour["team_times"][t["idx"]] += times[t["riders"][0]["id"]] + times[t["riders"][1]["id"]]
		tour["results"].append({"name": stage_title, "winner": Rules.rider_name(rank[0])})
		tour["jerseys"] = _award_jerseys()
		board.set_jerseys(tour["jerseys"])
		var last: bool = tour["idx"] >= tour["stages"].size() - 1
		if not last and tour["rest_after"].has(tour["idx"]):
			var lead := _leaders()
			for id in lead:
				tour["rest_tp"][R.riders[id]["team"]["idx"]] += 1
			for r in R.riders:
				if not lead.has(r["id"]):
					tour["carry"][r["id"]] = tour["carry"][r["id"]] / 2
			rest_note = "Giorno di riposo: un punto Tour ai leader delle classifiche (%s); gli altri corridori smaltiscono ancora metà della fatica." % ", ".join(lead.map(func(id): return Rules.rider_name(R.riders[id])))
		if last:
			bonus_lines = _end_bonus()
	for c in report.get_children():
		c.queue_free()
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	sc.add_child(v)
	v.add_child(_plain(stage_title, 26))
	v.add_child(_plain("Vince il %s in %d turni." % [Rules.rider_name(rank[0]), rank[0]["fin_round"]], 18, Color(1, 0.86, 0.55)))
	# ordine d'arrivo | squadre
	var rows: Array = []
	for i in rank.size():
		var r: Dictionary = rank[i]
		var pts := ""
		if r["sprint"] > 0:
			pts += "S%d " % r["sprint"]
		if r["mountain"] > 0:
			pts += "M%d" % r["mountain"]
		rows.append([str(i + 1) + ".", _rider_cell(r), fmt_time(times[r["id"]]), fmt_gap(times[r["id"]] - best), ("%d TP" % r["tp"]) if r["tp"] > 0 else "", pts])
	var right_title := "Squadre (somma dei due corridori)"
	var trows: Array = []
	var right_table: Control
	if tour.is_empty():
		var tt: Array = []
		for t in R.teams:
			tt.append([t, times[t["riders"][0]["id"]] + times[t["riders"][1]["id"]]])
		tt.sort_custom(func(x, y): return x[1] < y[1])
		for i in tt.size():
			trows.append([str(i + 1) + ".", _team_cell(tt[i][0]), fmt_time(tt[i][1]), fmt_gap(tt[i][1] - tt[0][1])])
		right_table = _table(["", "Squadra", "Tempo", "Distacco"], trows)
	else:
		right_title = "Punti Tour delle squadre"
		var tids: Array = range(R.teams.size())
		tids.sort_custom(func(x, y): return _team_tp(x) > _team_tp(y))
		for i in tids.size():
			var k: int = tids[i]
			trows.append([str(i + 1) + ".", _team_cell(R.teams[k]), tour["podium_tp"][k], tour["rest_tp"][k], tour["bonus_tp"][k], _team_tp(k)])
		right_table = _table(["", "Squadra", "Podi", "Riposo", "Bonus", "Totale"], trows)
	v.add_child(_two_cols(
		["Ordine d'arrivo", _table(["", "Corridore", "Tempo", "Distacco", "Podio", "Punti"], rows)],
		[right_title, right_table]))
	v.add_child(_plain("Tempo: un minuto per ogni turno passato dopo il primo arrivo, più i secondi della tavola dei tempi presi dal primo del proprio gruppo. Podio: 3, 2 e 1 punti Tour.", 13, Color(1, 1, 1, 0.5)))
	if not tour.is_empty():
		v.add_child(HSeparator.new())
		_tour_tables(v)
		if rest_note != "":
			v.add_child(_label(rest_note, 14, Color(1, 0.86, 0.55)))
		if not bonus_lines.is_empty():
			v.add_child(_section("Punti bonus di fine tour"))
			v.add_child(_label(", ".join(bonus_lines) + ".", 14, Color(1, 1, 1, 0.8)))
			var tids2: Array = range(R.teams.size())
			tids2.sort_custom(func(x, y): return _team_tp(x) > _team_tp(y) or (_team_tp(x) == _team_tp(y) and _best_last(x) < _best_last(y)))
			v.add_child(_plain("Vince il tour la squadra %s con %d punti Tour." % [R.teams[tids2[0]]["name"], _team_tp(tids2[0])], 22, Color(1, 0.86, 0.55)))
	v.add_child(HSeparator.new())
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	var rep := _big_button("Rivedi la tappa", Color(1, 1, 1, 0.1))
	rep.pressed.connect(_start_replay)
	bar.add_child(rep)
	if not tour.is_empty() and tour["idx"] < tour["stages"].size() - 1:
		var nx := _big_button("Tappa successiva", Color("#C8323C"))
		nx.pressed.connect(func():
			report.visible = false
			tour["idx"] += 1
			_begin_stage())
		bar.add_child(nx)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var menu_b := _big_button("Torna al menu", Color(1, 1, 1, 0.06))
	menu_b.pressed.connect(_ask_menu)
	bar.add_child(menu_b)
	v.add_child(bar)
	report.visible = true
	report.move_to_front()
	_layout()
	action.add_child(_label("Tappa conclusa", 20))
	var again := Button.new()
	again.text = "Mostra il resoconto"
	again.pressed.connect(func():
		report.visible = true
		report.move_to_front()
		_layout())
	action.add_child(again)

func _best_last(team_idx: int) -> int:
	var b := 999
	for r in R.teams[team_idx]["riders"]:
		b = mini(b, tour["last"][r["id"]])
	return b

func _big_button(t: String, col: Color) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(190, 48)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_stylebox_override("normal", _style(col, 8))
	b.add_theme_stylebox_override("hover", _style(col.lightened(0.15), 8))
	b.add_theme_stylebox_override("pressed", _style(col.darkened(0.15), 8))
	return b

## Due colonne affiancate, ognuna con titolo di sezione e tabella.
func _two_cols(left: Array, right: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	for col in [left, right]:
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_theme_constant_override("separation", 6)
		c.add_child(_section(col[0]))
		c.add_child(col[1])
		h.add_child(c)
	return h

## Classifiche del tour: generale a sinistra, sprint e montagna a destra.
func _tour_tables(v: VBoxContainer) -> void:
	var last: bool = tour["idx"] >= tour["stages"].size() - 1
	v.add_child(_plain("Classifiche dopo %d %s su %d%s" % [tour["idx"] + 1, "tappa" if tour["idx"] == 0 else "tappe", tour["stages"].size(), " (finali)" if last else ""], 22, Color(1, 0.86, 0.55)))
	var gc := _gc_order()
	var rows: Array = []
	var b0: int = tour["times"][gc[0]]
	for i in gc.size():
		var r: Dictionary = R.riders[gc[i]]
		rows.append([str(i + 1) + ".", _rider_cell_j(r), fmt_time(tour["times"][gc[i]]), fmt_gap(tour["times"][gc[i]] - b0)])
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	for kv in [["sprint", "Sprint"], ["mountain", "Montagna"]]:
		var o := _points_order(kv[0])
		var prow: Array = []
		for i in o.size():
			if tour[kv[0]][o[i]] <= 0:
				break
			prow.append([str(i + 1) + ".", _rider_cell_j(R.riders[o[i]]), tour[kv[0]][o[i]]])
		right.add_child(_section(kv[1]))
		if prow.is_empty():
			right.add_child(_plain("nessun punto finora", 14, Color(1, 1, 1, 0.5)))
		else:
			right.add_child(_table(["", "Corridore", "Punti"], prow))
	v.add_child(_two_cols(["Classifica generale (tempo)", _table(["", "Corridore", "Tempo totale", "Distacco"], rows)], ["Classifiche a punti", right]))
	var wins: Array = tour["results"].map(func(x): return "%s: %s" % [x["name"], x["winner"]])
	v.add_child(_label("Vincitori di tappa\n" + "\n".join(wins), 14, Color(1, 1, 1, 0.7)))

# ---------- ritorno al menu ----------

func _race_open() -> bool:
	if R == null:
		return false
	if not R.all_finished():
		return true
	return not tour.is_empty() and tour["idx"] < tour["stages"].size() - 1

## Chiede conferma solo se si abbandona una corsa o un tour non finiti.
func _ask_menu() -> void:
	if not _race_open():
		_back_to_menu()
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Tornare al menu?"
	dlg.dialog_text = "La %s in corso andrà persa." % ("corsa" if tour.is_empty() else "partita del tour")
	dlg.ok_button_text = "Abbandona"
	dlg.cancel_button_text = "Continua a giocare"
	dlg.confirmed.connect(_back_to_menu)
	menu_dialog = dlg
	dlg.visibility_changed.connect(func():
		if not dlg.visible:
			dlg.queue_free())
	ui.add_child(dlg)
	dlg.popup_centered()

## Torna alla scelta della corsa (non alla copertina), con le impostazioni e il percorso di prima.
func _back_to_menu() -> void:
	if is_instance_valid(menu_dialog):
		menu_dialog.queue_free()
	race_id += 1
	replay["token"] = replay.get("token", 0) + 1
	report.visible = false
	overlay.visible = false
	panel.visible = false
	setup_box.visible = true
	board.clear_target()
	board.clear_pick()
	board.highlight(null)
	R = null
	tour = {}
	if cfg["mode"] == 3:
		_show_tour_preview()
	elif track != null:
		board.show_track(track)
	_layout()

# ---------- replay in tempo reale ----------

func _start_replay() -> void:
	report.visible = false
	replay = {"k": 0, "playing": true, "speed": 1.0, "token": replay.get("token", 0) + 1}
	board.set_state(history[0]["s"])
	board.follow = true
	follow_btn.set_pressed_no_signal(true)
	_clear_action()
	action.add_child(_label("Replay della tappa", 20))
	var info := _label("", 15, Color(1, 1, 1, 0.75))
	info.name = "ReplayInfo"
	action.add_child(info)
	var row := HBoxContainer.new()
	var play := Button.new()
	play.text = "Pausa"
	play.custom_minimum_size = Vector2(90, 40)
	play.pressed.connect(func():
		replay["playing"] = not replay["playing"]
		play.text = "Pausa" if replay["playing"] else "Riprendi")
	row.add_child(play)
	var sp := OptionButton.new()
	for t in ["Velocità ×0,5", "Velocità ×1", "Velocità ×2", "Velocità ×4"]:
		sp.add_item(t)
	sp.selected = 1
	sp.item_selected.connect(func(k): replay["speed"] = [0.5, 1.0, 2.0, 4.0][k])
	row.add_child(sp)
	action.add_child(row)
	var row2 := HBoxContainer.new()
	var again := Button.new()
	again.text = "Ricomincia"
	again.pressed.connect(_start_replay)
	row2.add_child(again)
	var back := Button.new()
	back.text = "Torna al resoconto"
	back.pressed.connect(func():
		replay["token"] += 1
		board.set_state(history[-1]["s"])
		report.visible = true
		_layout())
	row2.add_child(back)
	action.add_child(row2)
	_run_replay(replay["token"])

## Un movimento continuo per turno: dalla posizione di inizio turno a quella dopo la scia;
## chi arriva esce di scena alla fine del suo movimento mentre gli altri proseguono.
func _replay_frames() -> Array:
	var frames: Array = []
	var cur: Array = history[0]["s"]
	for h in history:
		if h["phase"] == "slip":
			var after: Dictionary = {}
			for g in history:
				if g["phase"] == "finish" and g["round"] == h["round"]:
					after = g
			var vanish: Array = []
			if not after.is_empty():
				for id in after["s"].size():
					if h["s"][id][0] >= 0 and after["s"][id][0] < 0:
						vanish.append(id)
			frames.append({"round": h["round"], "a": cur, "b": h["s"], "vanish": vanish})
			cur = after["s"] if not after.is_empty() else h["s"]
	return frames

func _run_replay(token: int) -> void:
	var frames := _replay_frames()
	var total: int = history[-1]["round"]
	replay["k"] = 0
	while replay["k"] < frames.size():
		if replay["token"] != token:
			return
		if not replay["playing"]:
			await get_tree().process_frame
			continue
		var fr: Dictionary = frames[replay["k"]]
		var info := action.find_child("ReplayInfo", true, false) as Label
		if info:
			info.text = "Turno %d di %d" % [fr["round"], total]
		status_lbl.text = "Replay, turno %d" % fr["round"]
		await board.animate_state(fr["a"], fr["b"], board.step_time * 6.0 / replay["speed"], fr["vanish"])
		var ghost: Array = []
		for r in R.riders:
			ghost.append({"pos": fr["b"][r["id"]][0], "team": r["team"]})
		profile.refresh(track, ghost)
		replay["k"] += 1
	if replay["token"] == token:
		var info := action.find_child("ReplayInfo", true, false) as Label
		if info:
			info.text = "Replay concluso."
