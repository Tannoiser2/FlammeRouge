## Collegamento a Firebase (Realtime Database) per il gioco online.
## Usa solo le chiamate web standard (REST), quindi funziona sia nell'app sia nella versione web.
## Accesso anonimo: ogni dispositivo riceve un identificativo, senza registrazione.
class_name Net
extends Node

# Configurazione pubblica del progetto Firebase del gioco (non è un segreto: la protezione la fanno
# le regole del database, in firebase/database.rules.json).
const API_KEY := "AIzaSyCf1NQodB-J3OrdU_gHYQ1I6VJtXBk1ciU"
const DB_URL := "https://flammerouge-f8669-default-rtdb.europe-west1.firebasedatabase.app"
const AUTH_URL := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key="
const REFRESH_URL := "https://securetoken.googleapis.com/v1/token?key="
const CODE_LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"

var db_url := DB_URL
var auth_url := AUTH_URL + API_KEY
var refresh_url := REFRESH_URL + API_KEY
var uid := ""
var id_token := ""
var refresh_token := ""
var token_at := 0.0
var last_error := ""

func _init() -> void:
	# per le prove automatiche si può puntare a un finto Firebase locale
	var test_db := OS.get_environment("FR_DB_URL")
	if test_db != "":
		db_url = test_db
		auth_url = OS.get_environment("FR_AUTH_URL")
		refresh_url = OS.get_environment("FR_REFRESH_URL")

## Una richiesta HTTP: restituisce {code, data}. code 0 = rete non raggiungibile.
func _request(method: int, url: String, body = null, form := false) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded" if form else "Content-Type: application/json"])
	var payload := ""
	if body != null:
		payload = body if form else JSON.stringify(body)
	var err := http.request(url, headers, method, payload)
	if err != OK:
		http.queue_free()
		last_error = "richiesta non partita (%d)" % err
		return {"code": 0, "data": null}
	var res: Array = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		last_error = "rete non raggiungibile"
		return {"code": 0, "data": null}
	if code >= 300:
		last_error = "errore %d: %s" % [code, text.substr(0, 200)]
	return {"code": code, "data": data}

## Accesso anonimo (una volta per sessione).
func sign_in() -> bool:
	if id_token != "":
		return await _fresh()
	var r := await _request(HTTPClient.METHOD_POST, auth_url, {"returnSecureToken": true})
	if r["code"] != 200 or not (r["data"] is Dictionary):
		return false
	id_token = r["data"].get("idToken", "")
	refresh_token = r["data"].get("refreshToken", "")
	uid = r["data"].get("localId", "")
	token_at = Time.get_unix_time_from_system()
	return id_token != ""

## Il gettone d'accesso dura un'ora: lo si rinnova dopo 50 minuti.
func _fresh() -> bool:
	if refresh_token == "" or Time.get_unix_time_from_system() - token_at < 3000:
		return true
	var r := await _request(HTTPClient.METHOD_POST, refresh_url, "grant_type=refresh_token&refresh_token=" + refresh_token.uri_encode(), true)
	if r["code"] != 200 or not (r["data"] is Dictionary):
		return false
	id_token = r["data"].get("id_token", id_token)
	refresh_token = r["data"].get("refresh_token", refresh_token)
	token_at = Time.get_unix_time_from_system()
	return true

func _url(path: String) -> String:
	return "%s/%s.json?auth=%s" % [db_url, path, id_token]

func db_get(path: String) -> Dictionary:
	await _fresh()
	return await _request(HTTPClient.METHOD_GET, _url(path))

func db_put(path: String, value) -> Dictionary:
	await _fresh()
	return await _request(HTTPClient.METHOD_PUT, _url(path), value)

func db_patch(path: String, value: Dictionary) -> Dictionary:
	await _fresh()
	return await _request(HTTPClient.METHOD_PATCH, _url(path), value)

func db_delete(path: String) -> Dictionary:
	await _fresh()
	return await _request(HTTPClient.METHOD_DELETE, _url(path))

# ---------- stanze ----------

## Crea una stanza con un codice di 4 lettere. seats: indici delle squadre dei giocatori;
## l'host occupa il primo. Restituisce il codice, oppure "" se non ci riesce.
func create_room(player: String, seats: Array) -> String:
	if not await sign_in():
		return ""
	var g := RandomNumberGenerator.new()
	g.randomize()
	for attempt in 6:
		var code := ""
		for k in 4:
			code += CODE_LETTERS[g.randi() % CODE_LETTERS.length()]
		var existing := await db_get("rooms/%s/host" % code)
		if existing["code"] == 200 and existing["data"] != null:
			continue
		var body := {"host": uid, "created": {".sv": "timestamp"}, "status": "lobby",
			"open": seats, ("seats/%d" % seats[0]): {"uid": uid, "name": player}}
		var r := await db_patch("rooms/" + code, body)
		if r["code"] == 200:
			return code
	return ""

## Entra in una stanza: occupa il primo posto libero. Restituisce l'indice della squadra, -1 se non c'è posto,
## -2 se la stanza non esiste o la corsa è già partita.
func join_room(code: String, player: String) -> int:
	if not await sign_in():
		return -2
	var r := await db_get("rooms/" + code)
	if r["code"] != 200 or not (r["data"] is Dictionary) or r["data"].get("status", "") != "lobby":
		return -2
	var room: Dictionary = r["data"]
	var seats: Dictionary = _as_dict(room.get("seats", {}))
	for k in seats:
		if seats[k] is Dictionary and seats[k].get("uid", "") == uid:
			return int(k)
	for idx in room.get("open", []):
		if not seats.has(str(int(idx))):
			var w := await db_put("rooms/%s/seats/%d" % [code, int(idx)], {"uid": uid, "name": player})
			if w["code"] == 200:
				return int(idx)
	return -1

func room(code: String) -> Dictionary:
	var r := await db_get("rooms/" + code)
	return r["data"] if r["code"] == 200 and r["data"] is Dictionary else {}

func start_room(code: String, game: Dictionary) -> bool:
	var r := await db_patch("rooms/" + code, {"game": game, "status": "playing"})
	return r["code"] == 200

## Pubblica le carte scelte da una squadra in un turno.
func post_choice(code: String, round_n: int, team_idx: int, choice: Dictionary) -> bool:
	var r := await db_put("rooms/%s/turns/%d/%d" % [code, round_n, team_idx], choice)
	return r["code"] == 200

## Scelte arrivate per un turno: {indice squadra: scelta}.
func choices(code: String, round_n: int) -> Dictionary:
	var r := await db_get("rooms/%s/turns/%d" % [code, round_n])
	return _as_dict(r["data"]) if r["code"] == 200 else {}

func close_room(code: String) -> void:
	await db_delete("rooms/" + code)

## Firebase restituisce gli elenchi con chiavi numeriche come array (con buchi a null): li riporta a dizionario.
static func _as_dict(v) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			if v[k] != null:
				out[str(k)] = v[k]
	elif v is Array:
		for i in v.size():
			if v[i] != null:
				out[str(i)] = v[i]
	return out
