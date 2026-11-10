class_name Sfx
extends Node
## 효과음 3종(게이트 통과, 화살 발사, 타격) 재생.
## 계산 간격마다 사건이 나오므로 종류별 최소 간격으로 겹침을 줄인다.

const STREAMS := {
	"gate": preload("res://audio/gate.wav"),
	"arrow": preload("res://audio/arrow.wav"),
	"hit": preload("res://audio/hit.wav"),
}
const MSEC_PER_SEC := 1000.0

var _players: Dictionary = {}
var _min_interval: Dictionary = {}
var _last_played: Dictionary = {}


func setup(tuning: Dictionary) -> void:
	var data: Dictionary = tuning["sfx"]
	_min_interval = data["min_interval"]
	for sound_name in STREAMS:
		var player := AudioStreamPlayer.new()
		player.stream = STREAMS[sound_name]
		player.volume_db = float(data["volume_db"])
		add_child(player)
		_players[sound_name] = player
		_last_played[sound_name] = -INF


func play(sound_name: String) -> void:
	var now := Time.get_ticks_msec() / MSEC_PER_SEC
	if now - float(_last_played[sound_name]) < float(_min_interval[sound_name]):
		return
	_last_played[sound_name] = now
	_players[sound_name].play()

