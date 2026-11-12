class_name Sfx
extends Node
## 달리기 씬에서 효과음을 내는 창구. 실제 재생은 자동 로드 Sound가 맡는다.


func setup(_tuning: Dictionary) -> void:
	pass


## pitch는 재생 속도 배율이다. 연속 처치에서 음을 올릴 때 쓴다.
func play(sound_name: String, pitch := 1.0) -> void:
	Sound.play(sound_name, pitch)
