## Profilo altimetrico della tappa con la posizione dei corridori, come nelle dirette.
class_name ProfileView
extends Control

var track: Track
var riders: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(200, 78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh(t: Track, rs: Array) -> void:
	track = t
	riders = rs
	queue_redraw()

func _draw() -> void:
	if track == null or track.heights.is_empty():
		return
	var w := size.x
	var h := size.y
	var top := 8.0
	var bottom := h - 6.0
	var n := float(track.size())
	var hmax := maxf(track.max_height(), 0.4)
	var to_xy := func(s: float, hh: float) -> Vector2:
		return Vector2(s / n * w, bottom - hh / hmax * (bottom - top - 14.0))
	# area sotto il profilo
	var poly := PackedVector2Array()
	poly.append(Vector2(0, bottom))
	for k in int(n) * 2 + 1:
		var s := k * 0.5
		poly.append(to_xy.call(s, track.height_at(s)))
	poly.append(Vector2(w, bottom))
	draw_colored_polygon(poly, Color("#4E7A3A"))
	# linea colorata per tratto: salita rossa, discesa blu, pavé marrone, altrimenti grigio
	for i in track.size():
		var tt: String = track.squares[i]["t"]
		var col := Color("#B9C2C9")
		if tt == "up":
			col = Color("#E0453C")
		elif tt == "down":
			col = Color("#4A9BE0")
		elif tt == "cobble":
			col = Color("#B08850")
		elif tt == "supply":
			col = Color("#7FB2E8")
		draw_line(to_xy.call(i, track.height_at(i)), to_xy.call(i + 1, track.height_at(i + 1)), col, 3.0)
	# partenza e arrivo
	var xs: float = to_xy.call(track.start_count, 0.0).x
	var xf: float = to_xy.call(track.finish + 1, 0.0).x
	draw_line(Vector2(xs, top), Vector2(xs, bottom), Color(1, 1, 1, 0.5), 1.0)
	for k in 6:
		draw_rect(Rect2(xf - 3, top + k * 4.0, 3, 2), Color.WHITE if k % 2 == 0 else Color.BLACK)
		draw_rect(Rect2(xf, top + k * 4.0, 3, 2), Color.BLACK if k % 2 == 0 else Color.WHITE)
	# corridori: pallini impilati se nella stessa casella
	var stack := {}
	for r in riders:
		if r["pos"] < 0:
			continue
		var p: int = r["pos"]
		var k: int = stack.get(p, 0)
		stack[p] = k + 1
		var q: Vector2 = to_xy.call(p + 0.5, track.height_at(p + 0.5))
		q.y -= 6.0 + k * 7.0
		draw_circle(q, 4.0, r["team"]["color"])
		draw_arc(q, 4.0, 0, TAU, 12, Color(0, 0, 0, 0.6), 1.0)
