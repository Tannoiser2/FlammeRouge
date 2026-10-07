## Catalogo delle facce delle tessere (data/faces.json).
## Coordinate in pixel dell'immagine scansionata; 1 casella = px_per_square pixel.
class_name FacesDB
extends RefCounted

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/faces.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
	return _data

static func faces() -> Dictionary:
	return data()["faces"]

static func face(id: String) -> Dictionary:
	return faces().get(id, {})

static func px() -> float:
	return float(data()["px_per_square"])

## Lato opposto della stessa tessera fisica.
static func other_side(id: String) -> String:
	var t: String = face(id)["tile"]
	for k in faces():
		if k != id and faces()[k]["tile"] == t:
			return k
	return ""

static var _tex_cache: Dictionary = {}

## Texture di una faccia letta direttamente dal file .webp, senza l'importazione di Godot:
## così l'immagine ha sempre le stesse dimensioni e la stessa disposizione su ogni sistema.
static func texture(id: String) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id]
	var path: String = "res://assets/" + face(id)["img"]
	var tex: Texture2D = null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > 0:
		var img := Image.new()
		if img.load_webp_from_buffer(bytes) == OK:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		tex = load(path)
	_tex_cache[id] = tex
	return tex

static func v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
