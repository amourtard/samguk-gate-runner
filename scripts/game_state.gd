extends Node
## 자동 로드. 고른 장수, 도전할 스테이지, 열린 스테이지 수를 들고 있다.
## 금화, 영구 강화, 파일 저장은 단계 6에서 붙인다.

var hero_id := ""
var stage_index := 0
# 1-1부터 순서대로 연다. 1이면 1-1만 열린 상태
var unlocked_stages := 1


func _ready() -> void:
	var heroes: Dictionary = DataDb.table("heroes")
	hero_id = heroes["order"][0]


func stage_count() -> int:
	return (DataDb.table("stages")["list"] as Array).size()


func current_stage() -> Dictionary:
	return DataDb.table("stages")["list"][stage_index]


func current_hero() -> Dictionary:
	return DataDb.table("heroes")["list"][hero_id]


## 클리어하면 다음 스테이지를 연다.
func mark_cleared(index: int) -> void:
	unlocked_stages = clampi(index + 2, unlocked_stages, stage_count())


func has_next_stage() -> bool:
	return stage_index + 1 < unlocked_stages
