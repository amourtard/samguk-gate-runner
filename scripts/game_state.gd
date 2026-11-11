extends Node
## 자동 로드. 고른 장수, 도전할 스테이지, 열린 스테이지 수를 들고 있다.
## 데이터 목록(1-1~1-5) 뒤의 스테이지는 처음 필요할 때 만들어 두고 다시 도전할 때 그대로 쓴다.
## 금화, 영구 강화, 파일 저장은 단계 6에서 붙인다.

var hero_id := ""
var stage_index := 0
# 1-1부터 순서대로 연다. 1이면 1-1만 열린 상태. 1-5 이후로는 끝없이 늘어난다
var unlocked_stages := 1

# 자동 생성한 스테이지. 순번 → 스테이지 데이터
var _generated := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var heroes: Dictionary = DataDb.table("heroes")
	hero_id = heroes["order"][0]
	_rng.seed = randi()


## 데이터 파일에 적힌 스테이지 수
func data_stage_count() -> int:
	return (DataDb.table("stages")["list"] as Array).size()


func current_stage() -> Dictionary:
	return stage_at(stage_index)


func stage_at(index: int) -> Dictionary:
	var stages: Dictionary = DataDb.table("stages")
	var list: Array = stages["list"]
	if index < list.size():
		return list[index]
	if not _generated.has(index):
		_generated[index] = StageBuilder.endless_stage(index, stages, DataDb.table("units"), DataDb.table("tuning"), _rng)
	return _generated[index]


func current_hero() -> Dictionary:
	return DataDb.table("heroes")["list"][hero_id]


## 클리어하면 다음 스테이지를 연다.
func mark_cleared(index: int) -> void:
	unlocked_stages = maxi(unlocked_stages, index + 2)


func has_next_stage() -> bool:
	return stage_index + 1 < unlocked_stages
