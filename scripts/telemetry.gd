extends Node
## 자동 로드. 플레이 사건(판 시작, 선택, 교전, 판 끝)을 모아 서버로 보낸다. 분석해서 수치 조정에 쓴다.
## 기기마다 무작위 식별자만 쓰고 이름, 계정, 위치는 받지 않는다.
## 웹 빌드에서는 접속한 주소의 endpoint로 보낸다. PC 실행에서는 보내지 않고, local_file이 켜져 있으면 파일에 쓴다.
## 보내지 못해도 게임은 그대로 돈다. 값은 tuning.json의 telemetry에 둔다.

const PLAYER_PATH := "user://player.json"
const LOCAL_PATH := "user://telemetry.jsonl"
const ID_BYTES := 8
const MSEC_PER_SEC := 1000.0

var _data: Dictionary
var _enabled := false
var _url := ""
var _local := false
var _queue: Array[Dictionary] = []
# 지금 보내는 중인 사건 수(보내기가 성공하면 큐 앞에서 이만큼 지운다)
var _sending := 0
var _request: HTTPRequest
var _since_flush := 0.0
var _player := ""
var _session := ""
var _run := ""
var _run_count := 0
var _stage := ""
var _hero := ""
# 게임 진행용 난수와 섞이지 않게 따로 둔다
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_data = DataDb.table("tuning")["telemetry"]
	_rng.randomize()
	_load_player()
	_session = _random_id()
	var on_web := OS.has_feature("web")
	_local = bool(_data["local_file"]) and not on_web
	if bool(_data["enabled"]):
		var endpoint := str(_data["endpoint"])
		if endpoint.begins_with("http"):
			_url = endpoint
		elif on_web:
			_url = str(JavaScriptBridge.eval("window.location.origin", true)) + endpoint
	_enabled = _url != "" or _local
	if _url != "":
		_request = HTTPRequest.new()
		_request.timeout = float(_data["timeout"])
		add_child(_request)
		_request.request_completed.connect(_on_request_completed)
	var view_size := get_viewport().get_visible_rect().size
	track("session_start", {
		"platform": OS.get_name(),
		"web": on_web,
		"screen": [roundi(view_size.x), roundi(view_size.y)],
		"runs_before": _run_count,
	})


func _process(delta: float) -> void:
	if not _enabled or _queue.is_empty():
		return
	_since_flush += delta
	if _since_flush >= float(_data["flush_interval"]):
		flush()


## 판을 시작한다. 이후의 사건은 이 판 번호로 묶인다.
func begin_run(stage_id: String, hero_id: String, info: Dictionary) -> void:
	_run = _random_id()
	_stage = stage_id
	_hero = hero_id
	_run_count += 1
	_save_player()
	info["run_number"] = _run_count
	track("run_start", info)


## 판이 끝났다. 끝 사건을 넣고 바로 보낸다.
func end_run(info: Dictionary) -> void:
	track("run_end", info)
	flush()
	_run = ""


## 사건 하나를 큐에 넣는다. data는 JSON으로 바꿀 수 있는 값만 담는다.
func track(type: String, data: Dictionary = {}) -> void:
	if not _enabled:
		return
	_queue.append({
		"type": type,
		"time": roundi(Time.get_unix_time_from_system() * MSEC_PER_SEC),
		"run": _run,
		"stage": _stage,
		"hero": _hero,
		"data": data,
	})
	# 오래 못 보내 쌓이면 오래된 것부터 버린다(보내는 중인 것은 건드리지 않는다)
	var over := _queue.size() - int(_data["max_queue"])
	if over > 0 and _sending == 0:
		_queue = _queue.slice(over)


## 쌓인 사건을 보낸다(또는 파일에 쓴다).
func flush() -> void:
	_since_flush = 0.0
	if not _enabled or _queue.is_empty():
		return
	if _local:
		_write_local()
		return
	if _sending > 0:
		return
	var batch := _queue.slice(0, int(_data["batch_size"]))
	var body := JSON.stringify({
		"player": _player,
		"session": _session,
		"build": str(_data["build"]),
		"events": batch,
	})
	_sending = batch.size()
	var error := _request.request(_url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if error != OK:
		_sending = 0


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	# 성공했을 때만 보낸 만큼 지운다. 실패하면 다음 간격에 다시 보낸다
	if result == HTTPRequest.RESULT_SUCCESS and response_code == HTTPClient.RESPONSE_OK:
		_queue = _queue.slice(_sending)
	_sending = 0


func _write_local() -> void:
	var file := FileAccess.open(LOCAL_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOCAL_PATH) else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	for event in _queue:
		var line := event.duplicate()
		line["player"] = _player
		line["session"] = _session
		line["build"] = str(_data["build"])
		file.store_line(JSON.stringify(line))
	_queue.clear()


func _random_id() -> String:
	var bytes := PackedByteArray()
	for i in ID_BYTES:
		bytes.append(_rng.randi() % 256)
	return bytes.hex_encode()


func _load_player() -> void:
	if FileAccess.file_exists(PLAYER_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAYER_PATH))
		if parsed is Dictionary:
			_player = str((parsed as Dictionary).get("id", ""))
			_run_count = int((parsed as Dictionary).get("runs", 0))
	if _player == "":
		_player = _random_id()
		_save_player()


func _save_player() -> void:
	var file := FileAccess.open(PLAYER_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"id": _player, "runs": _run_count}))
