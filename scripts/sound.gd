extends Node
## 자동 로드. 효과음, 배경음, 짧은 음악(승리, 패배)을 재생한다.
## 파일 이름과 음량은 tuning.json의 sfx에 둔다. 읽지 못한 소리는 경고만 남기고 건너뛴다(게임은 그대로 돈다).
## 버튼은 화면에 추가될 때 자동으로 누름 소리를 붙인다.

const AUDIO_DIR := "res://audio/"
const MSEC_PER_SEC := 1000.0

var _data: Dictionary
# 이름 → 소리 목록(여러 개면 무작위로 하나)
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _last_played := {}
var _music: AudioStreamPlayer
var _music_name := ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_data = DataDb.table("tuning")["sfx"]
	for sound_name: String in _data["files"]:
		var entry: Variant = _data["files"][sound_name]
		var files: Array = entry if entry is Array else [entry]
		var list: Array[AudioStream] = []
		for file_name: String in files:
			var stream := _load(file_name)
			if stream != null:
				list.append(stream)
		if not list.is_empty():
			_streams[sound_name] = list
	for i in int(_data["voices"]):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	get_tree().node_added.connect(_on_node_added)


## 효과음 하나를 낸다. pitch는 재생 속도 배율이다(연속 처치에서 음을 올릴 때 쓴다).
func play(sound_name: String, pitch := 1.0) -> void:
	if not _streams.has(sound_name):
		return
	var now := Time.get_ticks_msec() / MSEC_PER_SEC
	var min_interval := float((_data["min_interval"] as Dictionary).get(sound_name, 0.0))
	if now - float(_last_played.get(sound_name, -INF)) < min_interval:
		return
	_last_played[sound_name] = now
	var list: Array = _streams[sound_name]
	var player := _free_player()
	# 소리 고르기는 따로 둔 난수로 한다(게임 진행에 쓰는 난수 순서를 건드리지 않는다)
	player.stream = list[_rng.randi() % list.size()]
	player.pitch_scale = pitch
	player.volume_db = float(_data["volume_db"])
	player.play()


## 배경음을 반복 재생한다. 같은 곡이 이미 나오고 있으면 음량만 맞춘다.
func play_music(music_name: String, volume_db: float) -> void:
	_music.volume_db = volume_db
	if _music_name == music_name and _music.playing:
		return
	var files: Dictionary = _data["music"]
	if not files.has(music_name):
		return
	var stream := _load(str(files[music_name]))
	if stream == null:
		return
	if stream is AudioStreamWAV:
		# 처음부터 끝까지 이어서 되풀이한다
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	_music_name = music_name
	_music.pitch_scale = 1.0
	_music.stream = stream
	_music.play()


## 배경음의 빠르기를 바꾼다(보스가 분노했을 때). 곡을 바꾸거나 멈추면 원래대로 돌아간다.
func set_music_pitch(pitch: float) -> void:
	_music.pitch_scale = pitch


func stop_music() -> void:
	_music.pitch_scale = 1.0
	_music.stop()
	_music_name = ""


## 달리는 동안의 배경음 음량과 메뉴 화면의 배경음 음량
func music_volume() -> float:
	return float(_data["music_volume_db"])


func menu_music_volume() -> float:
	return float(_data["menu_music_volume_db"])


func _load(file_name: String) -> AudioStream:
	var path := AUDIO_DIR + file_name
	if not ResourceLoader.exists(path):
		push_warning("소리 파일을 읽지 못했습니다(에디터로 프로젝트를 한 번 열면 가져옵니다): " + path)
		return null
	return load(path) as AudioStream


## 쉬고 있는 재생기를 고른다. 모두 쓰는 중이면 첫 번째 것을 끊고 쓴다.
func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0]


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(play.bind("button"))
